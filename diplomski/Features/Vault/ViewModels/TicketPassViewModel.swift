//
//  TicketPassViewModel.swift
//  diplomski
//

import SwiftUI
import Combine
import SolanaSwift
import Supabase

/// Drives a live, self-refreshing ticket pass.
///
/// The signing key is unlocked once when the sheet opens and held in memory only while
/// it is on screen, then discarded in `stop()`. Reading it from the Keychain on every
/// refresh would require a biometric prompt every thirty seconds. The exposure window
/// is the lifetime of a single sheet, and the key never leaves the process.
@MainActor
final class TicketPassViewModel: ObservableObject {
    @Published private(set) var code: String?
    @Published private(set) var secondsRemaining: Int = 0
    @Published private(set) var isUnlocking = true
    @Published private(set) var errorMessage: String?
    /// Number of times the pass has rotated; drives the refresh animation.
    @Published private(set) var rotationCount = 0

    private let mint: String
    private var keyPair: KeyPair?
    private var refreshTask: Task<Void, Never>?
    private var issuedAt: Date?

    init(mint: String) {
        self.mint = mint
    }

    deinit {
        refreshTask?.cancel()
    }

    // MARK: - Lifecycle

    func start() async {
        isUnlocking = true
        errorMessage = nil

        guard let userId = try? await supabase.auth.session.user.id.uuidString else {
            errorMessage = "You are not signed in."
            isUnlocking = false
            return
        }

        do {
            // The only biometric prompt for this sheet.
            keyPair = try WalletManager.shared.retrieveWallet(for: userId)
        } catch {
            errorMessage = error.localizedDescription
            isUnlocking = false
            return
        }

        isUnlocking = false
        issue()
        startRefreshLoop()
    }

    /// Drops the in-memory key and stops refreshing. Called when the sheet closes.
    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        keyPair = nil
        code = nil
    }

    // MARK: - Issuing

    private func issue() {
        guard let keyPair else { return }
        do {
            let now = Date()
            code = try TicketPass.issue(mint: mint, keyPair: keyPair, at: now)
            issuedAt = now
            secondsRemaining = Int(TicketPass.validityWindow)
            rotationCount += 1
        } catch {
            errorMessage = "Could not sign the pass: \(error.localizedDescription)"
        }
    }

    private func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    private func tick() {
        guard let issuedAt else { return }
        let elapsed = Date().timeIntervalSince(issuedAt)
        let remaining = TicketPass.validityWindow - elapsed

        if remaining <= 0 {
            issue()
        } else {
            secondsRemaining = max(0, Int(remaining.rounded(.up)))
        }
    }
}
