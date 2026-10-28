//
//  WalletViewModel.swift
//  diplomski
//

import SwiftUI
import Combine
import Supabase

@MainActor
class WalletViewModel: ObservableObject {
    static let shared = WalletViewModel()
    
    @Published var publicKey: String?
    @Published var balance: Double = 0.0
    @Published var isLoading = true

    /// Recovery phrase for a wallet just created at sign-up, awaiting presentation.
    /// Cleared once the user confirms they have written it down; never persisted.
    @Published var pendingMnemonic: MnemonicPresentation?
    
    /// The active user's ID — set on login, cleared on logout.
    private var currentUserId: String?
    
    /// Returns a user-specific UserDefaults key for the wallet.
    private func pubKeyDefaultsKey(for userId: String) -> String {
        return "solana_public_key_\(userId)"
    }
    
    private init() {}
    
    // MARK: - Main Entry Point
    
    /// Called after authentication succeeds. Loads or creates a wallet for the given user.
    func initializeWallet(for userId: String? = nil) async {
        isLoading = true
        
        // Resolve the user ID — either passed directly or fetched from the current session.
        let resolvedUserId: String
        if let userId = userId {
            resolvedUserId = userId
        } else if let sessionUserId = try? await supabase.auth.session.user.id.uuidString {
            resolvedUserId = sessionUserId
        } else {
            Log.error("[Wallet] No user ID available. Cannot initialize wallet.")
            isLoading = false
            return
        }
        
        self.currentUserId = resolvedUserId
        let userDefaultsKey = pubKeyDefaultsKey(for: resolvedUserId)
        
        // Step 1: Check the local cache for this user's wallet.
        if let localPubKey = UserDefaults.standard.string(forKey: userDefaultsKey) {
            self.publicKey = localPubKey
            await fetchBalance()
            isLoading = false
            return
        }
        
        // Step 2: No local key for this user — check Supabase profile (cross-device sync).
        if let profilePubKey = await fetchWalletFromProfile(userId: resolvedUserId) {
            // A wallet already exists for this user. Its address is cached locally; signing
            // requires the private key on this device (see WalletRecoveryView).
            self.publicKey = profilePubKey
            UserDefaults.standard.set(profilePubKey, forKey: userDefaultsKey)
            await fetchBalance()
            isLoading = false
            return
        }
        
        // Step 3: Brand new user — no wallet anywhere. Generate one.
        do {
            let wallet = try await WalletManager.shared.createWallet(for: resolvedUserId)
            self.publicKey = wallet.publicKey
            UserDefaults.standard.set(wallet.publicKey, forKey: userDefaultsKey)

            // Show the recovery phrase exactly once. It is never written to disk: the
            // Keychain holds only the derived key and Supabase only the public address.
            self.pendingMnemonic = MnemonicPresentation(words: wallet.mnemonic)

            // Publish the public address to the user's profile.
            await syncWalletToProfile(userId: resolvedUserId)

            // Devnet airdrop so a new account can pay for tickets.
            do {
                _ = try await WalletManager.shared.requestAirdrop(pubKey: wallet.publicKey)
                // Poll until the funds arrive rather than waiting a fixed time.
                await awaitFundedBalance(pubKey: wallet.publicKey)
            } catch {
                Log.error("Airdrop failed (possibly rate limited): \(error.localizedDescription)")
            }

            await fetchBalance()
        } catch {
            Log.error("Failed to generate wallet: \(error.localizedDescription)")
        }

        isLoading = false
    }

    /// Waits for an airdrop to show up, up to `timeout`. Returns as soon as the balance
    /// is non-zero.
    private func awaitFundedBalance(pubKey: String, timeout: TimeInterval = 8) async {
        let started = Date()
        while Date().timeIntervalSince(started) < timeout {
            if let lamports = try? await WalletManager.shared.getBalance(pubKey: pubKey),
               lamports > 0 {
                return
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        Log.debug("[Wallet] Airdrop did not land within \(Int(timeout))s.")
    }
    
    /// Points this session at a wallet that has just been created or restored on this
    /// device, replacing whatever was cached for the user.
    ///
    /// The cached address is read back on every launch, so it must be replaced here to
    /// match the key this device can actually sign with.
    func adoptWallet(publicKey newKey: String, for userId: String) {
        self.publicKey = newKey
        self.currentUserId = userId
        UserDefaults.standard.set(newKey, forKey: pubKeyDefaultsKey(for: userId))
    }

    // MARK: - Profile Sync
    
    /// Fetches the wallet public key from the Supabase profile for a specific user.
    private func fetchWalletFromProfile(userId: String) async -> String? {
        do {
            let profile: UserProfile = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            return profile.solanaPublicKey
        } catch {
            Log.error("[Wallet] Could not fetch profile wallet: \(error)")
            return nil
        }
    }
    
    /// Saves the current public key to the user's Supabase profile.
    func syncWalletToProfile(userId: String? = nil) async {
        guard let pubKey = self.publicKey else { return }
        let resolvedUserId = userId ?? currentUserId
        guard let uid = resolvedUserId else { return }
        
        do {
            struct ProfileUpdate: Codable {
                let solana_public_key: String
            }
            try await supabase
                .from("profiles")
                .update(ProfileUpdate(solana_public_key: pubKey))
                .eq("id", value: uid)
                .execute()
            Log.debug("[Wallet] Synced wallet \(pubKey.prefix(8))... to profile \(uid.prefix(8))...")
        } catch {
            Log.error("[Wallet] Failed to sync wallet to Supabase: \(error)")
        }
    }
    
    // MARK: - Balance
    
    func fetchBalance() async {
        guard let pubKey = publicKey else { return }
        do {
            let lamports = try await WalletManager.shared.getBalance(pubKey: pubKey)
            self.balance = Double(lamports) / 1_000_000_000.0
        } catch {
            Log.error("[Wallet] Failed to fetch balance: \(error)")
        }
    }
    
    // MARK: - Logout Cleanup
    
    /// Clears the in-memory wallet state on sign-out. Keychain and UserDefaults data are
    /// kept, so the wallet is restored when the same user signs back in.
    func clearWalletState() {
        self.publicKey = nil
        self.balance = 0.0
        self.currentUserId = nil
    }
}
