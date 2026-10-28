//
//  WalletManager.swift
//  diplomski
//

import Foundation
import Security
import SolanaSwift
import LocalAuthentication

enum WalletError: LocalizedError {
    case signingKeyMissing
    case transactionFailedOnChain(signature: String)
    case confirmationTimedOut(signature: String)
    case notARequiredSigner(wallet: String)
    case authenticationCancelled
    case authenticationFailed
    case keychainFailure(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .signingKeyMissing:
            return "This account has no signing key on this device, so it cannot approve transactions here. Open Profile → Wallet to restore it from your recovery phrase, or to create a new wallet for this device."
        case .authenticationCancelled:
            return "Authentication was cancelled, so nothing was signed or sent."
        case .authenticationFailed:
            return "Face ID could not verify you, so the transaction was not signed. Try again, or use your device passcode."
        case .keychainFailure(let status):
            return "The device refused access to your signing key (Keychain error \(status)). Nothing was signed or sent."
        case .notARequiredSigner(let wallet):
            return "This transaction does not expect a signature from your wallet (\(wallet.prefix(8))…), so it was not sent. This usually means the request was built for a different account."
        case .transactionFailedOnChain(let signature):
            return "The transaction was rejected by the network. Nothing was charged. (Signature: \(signature.prefix(8))…)"
        case .confirmationTimedOut(let signature):
            return "The network did not confirm the transaction in time. It may still land — check the explorer before retrying. (Signature: \(signature.prefix(8))…)"
        }
    }
}

class WalletManager {
    static let shared = WalletManager()

    /// All network calls go through the pool, so an unreachable or throttling endpoint
    /// costs one extra round trip instead of a failed operation.
    private let rpc = SolanaRPCPool.shared

    /// Cinema treasury wallet. Receives primary-sale payments and is the authority of
    /// the resale marketplace.
    ///
    /// `nonisolated` so it can be used in default argument values, which are evaluated
    /// outside any actor.
    nonisolated static let cinemaWalletAddress = "EdruEDJn5tdR9uNG1BfYWYv2spyVgWadu7AXiqaRa5dk"

    private let baseTag = "com.rushguard.solana.privatekey"

    private init() {}

    /// Per-user Keychain tag, so several accounts on one device each keep their own key.
    private func keychainTag(for userId: String) -> Data {
        return "\(baseTag).\(userId)".data(using: .utf8)!
    }

    // MARK: - Wallet Generation

    /// A newly created wallet. The mnemonic is returned so the caller can show it to the
    /// user once: it is never stored, and cannot be recovered from the Keychain.
    struct GeneratedWallet {
        let publicKey: String
        let mnemonic: [String]
    }

    /// Generates a BIP39 mnemonic, derives an Ed25519 keypair from it, and stores the
    /// private key in the Keychain.
    ///
    /// The wallet is non-custodial: whoever holds the phrase can restore it on any
    /// device, and nobody else — including the cinema — can recover it.
    func createWallet(for userId: String) async throws -> GeneratedWallet {
        let mnemonic = Mnemonic()
        let account = try await KeyPair(phrase: mnemonic.phrase, network: .devnet)

        try storeInKeychain(data: account.secretKey, tag: keychainTag(for: userId))

        return GeneratedWallet(
            publicKey: account.publicKey.base58EncodedString,
            mnemonic: mnemonic.phrase
        )
    }

    /// Restores a wallet from a 12- or 24-word recovery phrase and stores it on this
    /// device. The same phrase derives the same keypair on any device.
    func importWallet(mnemonicWords: [String], for userId: String) async throws -> String {
        let account = try await KeyPair(phrase: mnemonicWords, network: .devnet)
        try storeInKeychain(data: account.secretKey, tag: keychainTag(for: userId))
        return account.publicKey.base58EncodedString
    }

    /// Whether a private key for this user exists on this device.
    ///
    /// Queries attributes only, never the key data, so it does not trigger a biometric
    /// prompt. This lets the UI report that the device cannot sign before the user
    /// starts an operation rather than after.
    func hasLocalKey(for userId: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keychainTag(for: userId),
            kSecReturnData as String: false,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }

    /// Retrieves the user's keypair from the Keychain, requiring user presence
    /// (Face ID, Touch ID or passcode).
    ///
    /// Failures are mapped by `OSStatus` so the user is told the actual cause: a
    /// cancelled prompt and a key that does not exist on this device call for very
    /// different responses.
    func retrieveWallet(for userId: String) throws -> KeyPair {
        let privateKeyData: Data
        do {
            privateKeyData = try retrieveFromKeychain(tag: keychainTag(for: userId))
        } catch let error as NSError where error.domain == NSOSStatusErrorDomain {
            switch OSStatus(error.code) {
            case errSecItemNotFound:
                throw WalletError.signingKeyMissing
            case errSecUserCanceled:
                throw WalletError.authenticationCancelled
            case errSecAuthFailed, errSecInteractionNotAllowed:
                throw WalletError.authenticationFailed
            default:
                throw WalletError.keychainFailure(status: OSStatus(error.code))
            }
        }
        return try KeyPair(secretKey: privateKeyData)
    }

    // MARK: - Keychain

    private func storeInKeychain(data: Data, tag: Data) throws {
        // Replace any existing key for this tag.
        let queryDelete: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag
        ]
        SecItemDelete(queryDelete as CFDictionary)

        // Readable only while the device is unlocked, never synced or backed up off this
        // device, and only after user presence is confirmed.
        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            &error
        ) else {
            throw error!.takeRetainedValue() as Error
        }

        let queryAdd: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: accessControl
        ]

        let status = SecItemAdd(queryAdd as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
        }
    }

    private func retrieveFromKeychain(tag: Data) throws -> Data {
        let context = LAContext()
        context.localizedReason = "Authenticate to sign Solana transaction"

        let queryLoad: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(queryLoad as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
        }

        return data
    }

    // MARK: - Solana Network

    /// Requests a Devnet airdrop (2 SOL by default).
    func requestAirdrop(pubKey: String, amount: UInt64 = 2_000_000_000) async throws -> String {
        let signature = try await rpc.perform("requestAirdrop") { client in
            try await client.requestAirdrop(account: pubKey, lamports: amount)
        }
        Log.debug("[Solana] Airdrop requested. Signature: \(signature)")
        return signature
    }

    /// Returns the balance of `pubKey` in lamports.
    func getBalance(pubKey: String) async throws -> UInt64 {
        let balance = try await rpc.perform("getBalance") { client in
            try await client.getBalance(account: pubKey, commitment: "confirmed")
        }
        Log.debug("[Solana] Balance for \(pubKey.prefix(8))…: \(balance) lamports")
        return balance
    }

    /// Fetches the latest blockhash via `getLatestBlockhash`.
    func getLatestBlockhash() async throws -> String {
        nonisolated struct BlockhashResponse: Decodable {
            let blockhash: String
            let lastValidBlockHeight: UInt64
        }
        let result: Rpc<BlockhashResponse> = try await rpc.perform("getLatestBlockhash") { client in
            try await client.request(
                method: "getLatestBlockhash",
                params: [RequestConfiguration(commitment: "confirmed")]
            )
        }
        return result.value.blockhash
    }

    /// Broadcasts an already-signed, base64-encoded transaction.
    ///
    /// `skipPreflight` is used only for minting, where Shyft embeds a blockhash from its
    /// own RPC node that the broadcasting node may not have seen yet. Everywhere else
    /// preflight stays on so simulation errors are reported rather than lost.
    func sendSignedTransaction(base64Tx: String, skipPreflight: Bool = false) async throws -> String {
        try await rpc.perform("sendTransaction") { client in
            try await client.sendTransaction(
                transaction: base64Tx,
                configs: RequestConfiguration(
                    encoding: "base64",
                    skipPreflight: skipPreflight,
                    preflightCommitment: "confirmed"
                )!
            )
        }
    }

    /// Polls until the transaction reaches at least `confirmed`, or the timeout expires.
    ///
    /// A signature returned by `sendTransaction` only means a node accepted the
    /// transaction for forwarding, not that the cluster included it. Success is reported
    /// only after confirmation.
    ///
    /// - Returns: the time taken to reach confirmation.
    @discardableResult
    func awaitConfirmation(signature: String, timeout: TimeInterval = 30) async throws -> TimeInterval {
        let started = Date()

        while Date().timeIntervalSince(started) < timeout {
            let statuses = try await rpc.perform("getSignatureStatuses") { client in
                try await client.getSignatureStatuses(signatures: [signature], configs: nil)
            }

            if let status = statuses.first ?? nil {
                if let error = status.err {
                    Log.error("Transaction \(signature.prefix(8))… failed on-chain: \(error)")
                    throw WalletError.transactionFailedOnChain(signature: signature)
                }
                if let confirmation = status.confirmationStatus,
                   confirmation == "confirmed" || confirmation == "finalized" {
                    let elapsed = Date().timeIntervalSince(started)
                    Log.debug("[Solana] Confirmed \(signature.prefix(8))… in \(String(format: "%.2f", elapsed))s (\(confirmation))")
                    return elapsed
                }
            }

            // Devnet often confirms in under half a second, so a coarse interval would
            // dominate the measured confirmation time.
            try await Task.sleep(nanoseconds: 250_000_000)
        }

        Log.error("Confirmation timed out for \(signature.prefix(8))… after \(Int(timeout))s")
        throw WalletError.confirmationTimedOut(signature: signature)
    }

    /// Signs a transaction built by Shyft, broadcasts it, and waits for confirmation.
    ///
    /// This is the trust boundary of the marketplace: Shyft assembles the instructions,
    /// but the transaction has no effect until it is signed here with a key held in the
    /// Keychain and released only after biometric authentication. Shyft cannot list,
    /// sell or move a ticket on its own.
    ///
    /// Known limitation: the payload arrives pre-encoded and is not decoded for the user
    /// before signing, so the app trusts Shyft's construction of it.
    ///
    /// - Returns: the confirmed transaction signature.
    func signAndBroadcast(
        encodedTransaction: String,
        userId: String,
        label: String
    ) async throws -> String {
        guard let txData = Data(base64Encoded: encodedTransaction) else {
            throw APIClientError.invalidResponse
        }

        // Handles both legacy and v0 messages; `VersionedMessage.deserialize` dispatches
        // on the version prefix.
        var transaction = try VersionedTransaction.deserialize(data: txData)

        // Unlocking the key is the last step before signing, so the only network call
        // after the biometric prompt is the broadcast.
        let account = try retrieveWallet(for: userId)
        try transaction.sign(signers: [account])

        // `VersionedTransaction.sign` silently skips keys that are not required signers.
        // Verify the signature slot was actually filled, so a wallet mismatch fails here
        // with a clear cause rather than opaquely at the RPC.
        let signerIndex = transaction.message.value.staticAccountKeys
            .prefix(Int(transaction.message.value.header.numRequiredSignatures))
            .firstIndex(of: account.publicKey)
        guard let signerIndex,
              transaction.signatures.indices.contains(signerIndex),
              transaction.signatures[signerIndex] != Constants.defaultSignature else {
            throw WalletError.notARequiredSigner(wallet: account.publicKey.base58EncodedString)
        }

        let signedBase64 = try transaction.serialize().base64EncodedString()
        Log.debug("[Marketplace] \(label): signed, broadcasting…")

        // Preflight stays on: marketplace transactions can fail for meaningful reasons
        // (listing already cancelled, ticket already sold) that should surface as
        // simulation errors.
        let signature = try await sendSignedTransaction(base64Tx: signedBase64)
        try await awaitConfirmation(signature: signature)

        Log.event("[Marketplace] \(label): confirmed. TX: \(signature)")
        return signature
    }

    /// Pays the cinema treasury for a primary ticket sale.
    ///
    /// The blockhash is fetched before the Keychain is unlocked, so the biometric prompt
    /// is followed only by local signing and a single broadcast. Secondary (resale)
    /// payments do not use this method: the Auction House settles them on-chain together
    /// with the NFT transfer.
    ///
    /// - Parameters:
    ///   - signer: an already-unlocked key. Pass one when several operations belong to a
    ///     single user-confirmed action, so the user authenticates once.
    ///   - timer: optional instrumentation. Records `blockhash`, `faceid` (only when this
    ///     call unlocks the Keychain), `potpis`, `slanje` and `potvrda`.
    func transferSOL(
        amountLamports: UInt64,
        userId: String,
        signer: KeyPair? = nil,
        timer: PhaseTimer? = nil
    ) async throws -> String {
        let recipient = Self.cinemaWalletAddress
        Log.debug("[Solana] Transfer \(amountLamports) lamports → \(recipient)")

        let recentBlockhash = try await getLatestBlockhash()
        timer?.mark("blockhash")

        // The resolved keypair's public key is used as both sender and fee payer, which
        // guarantees the signer appears in the transaction's account keys.
        let senderAccount = try signer ?? retrieveWallet(for: userId)
        let senderPublicKey = senderAccount.publicKey

        // `mark` attributes all time since the previous mark, so `faceid` is recorded
        // only when this call actually prompted.
        if signer == nil {
            timer?.mark("faceid")
        }

        let instruction = try SystemProgram.transferInstruction(
            from: senderPublicKey,
            to: PublicKey(string: recipient),
            lamports: amountLamports
        )

        var transaction = Transaction(
            instructions: [instruction],
            recentBlockhash: recentBlockhash,
            feePayer: senderPublicKey
        )
        try transaction.sign(signers: [senderAccount])

        let base64Tx = try transaction.serialize().base64EncodedString()
        timer?.mark("potpis")

        do {
            let signature = try await sendSignedTransaction(base64Tx: base64Tx)
            timer?.mark("slanje")

            try await awaitConfirmation(signature: signature)
            timer?.mark("potvrda")

            Log.event("Payment confirmed: \(signature)")
            return signature
        } catch let error as APIClientError {
            Log.error("Payment failed: \(Self.describe(error))")
            throw error
        }
    }

    /// Flattens an `APIClientError` into one readable line.
    private static func describe(_ error: APIClientError) -> String {
        switch error {
        case .invalidAPIURL: return "invalid RPC URL"
        case .invalidResponse: return "malformed RPC response"
        case .couldNotRetrieveAccountInfo: return "could not retrieve account info"
        case .blockhashNotFound: return "blockhash not found"
        case .transactionSimulationError(let logs):
            return "simulation failed — \(logs.suffix(3).joined(separator: " | "))"
        case .responseError(let response):
            let code = response.code.map(String.init) ?? "?"
            return "RPC \(code): \(response.message ?? "no message")"
        }
    }

    /// Mints a ticket NFT: pins its metadata to IPFS via Pinata, then has Shyft build
    /// the mint transaction, which is signed locally and broadcast.
    ///
    /// - Parameters:
    ///   - signer: an already-unlocked key. Pass one when minting several seats, so the
    ///     user authenticates once for the whole purchase rather than once per ticket.
    ///   - timer: optional instrumentation. Records `faceid` (only when this call
    ///     unlocks the Keychain), `ipfs`, `shyft`, `potpis`, `slanje` and `potvrda`.
    func mintNFTTicket(
        movieTitle: String,
        showtime: Date,
        seat: Int,
        userId: String,
        signer: KeyPair? = nil,
        timer: PhaseTimer? = nil
    ) async throws -> String {
        let account = try signer ?? retrieveWallet(for: userId)
        let privateKeyData = account.secretKey
        let walletAddress = account.publicKey.base58EncodedString

        // `mark` attributes all time since the previous mark, so `faceid` is recorded
        // only when this call actually prompted. Otherwise it would absorb whatever
        // preceded it, such as the pause between sequential mints.
        if signer == nil {
            timer?.mark("faceid")
        }

        // Row and seat as shown in the seat grid.
        let pos = Showtime.rowAndColumn(for: seat)

        // Placeholder artwork shared by all tickets.
        let placeholderImage = "https://bafybeicwqjlyrnj3p5y7ivt3r7qjovxtnguovbvwkkhuol2zcwrtncllre.ipfs.nftstorage.link/"

        // The biometric prompt can drop an in-flight connection, so the first request
        // after it is retried on transport errors.
        let uri = try await withTransportRetry(label: "pinata") {
            try await PinataService.shared.uploadJSONMetadata(
                name: movieTitle,
                symbol: "RUSHGUARD",
                description: "A secure Web3 cinema ticket for \(movieTitle).",
                imageURL: placeholderImage,
                row: pos.row,
                seat: pos.column,
                showtime: showtime,
                walletAddress: walletAddress
            )
        }
        timer?.mark("ipfs")

        let mintAddress = try await NFTManager.shared.mintNFT(
            privateKeyData: privateKeyData,
            uri: uri,
            name: movieTitle,
            timer: timer
        )

        Log.event("Minted \(mintAddress) (seat \(seat))")
        return mintAddress
    }
}
