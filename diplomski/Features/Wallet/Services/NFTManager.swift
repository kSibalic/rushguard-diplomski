//
//  NFTManager.swift
//  diplomski
//

import Foundation
import SolanaSwift

/// A failure reported by Shyft's mint endpoint, classified by whether repeating the
/// request could succeed.
///
/// The HTTP status alone is not enough: Shyft reports both its rate limit and its
/// internal fetch timeout (`"timeout of 25000ms exceeded"`) as HTTP 400, a status that
/// normally means the request should not be repeated.
enum ShyftMintError: LocalizedError {
    case transient(String)
    /// Rate limited. Retried after a longer delay than other transient failures.
    case rateLimited(String)
    case permanent(String)

    var errorDescription: String? {
        switch self {
        case .transient(let detail): return "The minting service is temporarily unavailable (\(detail))."
        case .rateLimited: return "The minting service is rate limiting this API key. Tickets are being minted more slowly to compensate."
        case .permanent(let detail): return "The minting service rejected the request (\(detail))."
        }
    }
}

class NFTManager {
    static let shared = NFTManager()

    private let shyftApiKey = ShyftConfig.apiKey

    private init() {}

    /// Mints an NFT: Shyft builds the transaction, which is signed locally and broadcast.
    ///
    /// Retries on `blockhashNotFound` — Shyft embeds a blockhash from its own RPC node,
    /// which the broadcasting node may not have seen yet; a retry yields a fresh
    /// transaction with a fresh blockhash. Also retries transient Shyft failures
    /// (timeouts, rate limits, 5xx), since by the time minting runs the payment has
    /// already been made.
    func mintNFT(
        privateKeyData: Data,
        uri: String,
        name: String,
        timer: PhaseTimer? = nil
    ) async throws -> String {
        let keyPair = try KeyPair(secretKey: privateKeyData)
        let walletAddress = keyPair.publicKey.base58EncodedString

        let maxAttempts = 4
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                return try await performMintAttempt(
                    keyPair: keyPair,
                    walletAddress: walletAddress,
                    uri: uri,
                    name: name,
                    timer: timer
                )
            } catch let error as ShyftMintError {
                switch error {
                case .permanent:
                    throw error
                case .transient(let detail):
                    lastError = error
                    Log.error("Mint attempt \(attempt)/\(maxAttempts): \(detail) — retrying.")
                    try await backOff(attempt: attempt, of: maxAttempts)
                case .rateLimited(let detail):
                    lastError = error
                    Log.error("Mint attempt \(attempt)/\(maxAttempts): \(detail) — backing off.")
                    try await backOff(attempt: attempt, of: maxAttempts, base: 3_000_000_000)
                }
            } catch APIClientError.blockhashNotFound {
                lastError = APIClientError.blockhashNotFound
                Log.error("Mint attempt \(attempt)/\(maxAttempts): blockhash not found — retrying.")
                try await backOff(attempt: attempt, of: maxAttempts)
            } catch let error as URLError where error.code == .timedOut || error.code == .networkConnectionLost {
                lastError = error
                Log.error("Mint attempt \(attempt)/\(maxAttempts): \(error.code) — retrying.")
                try await backOff(attempt: attempt, of: maxAttempts)
            }
        }

        throw lastError ?? APIClientError.blockhashNotFound
    }

    /// Linear backoff, capped at three steps. Only applied after a failure, so it never
    /// affects a successful mint.
    private func backOff(attempt: Int, of maxAttempts: Int, base: UInt64 = 700_000_000) async throws {
        guard attempt < maxAttempts else { return }
        try await Task.sleep(nanoseconds: UInt64(min(attempt, 3)) * base)
    }

    /// Decides whether a non-2xx Shyft response is worth repeating, inspecting the body
    /// as well as the status (see `ShyftMintError`).
    private static func classify(status: Int, body: String) -> ShyftMintError {
        let lowered = body.lowercased()

        if status == 429 || lowered.contains("rate limit") || lowered.contains("too many request") {
            return .rateLimited("HTTP \(status)")
        }

        let transientPhrases = ["timeout", "timed out", "socket hang up", "econnreset", "econnrefused", "try again"]
        if transientPhrases.contains(where: lowered.contains) {
            return .transient("HTTP \(status), \(body.prefix(80))")
        }

        switch status {
        case 408, 500...599:
            return .transient("HTTP \(status)")
        default:
            return .permanent("HTTP \(status), \(body.prefix(120))")
        }
    }

    private func performMintAttempt(
        keyPair: KeyPair,
        walletAddress: String,
        uri: String,
        name: String,
        timer: PhaseTimer?
    ) async throws -> String {
        // 1. Request an unsigned mint transaction from Shyft.
        guard let url = URL(string: "https://api.shyft.to/sol/v1/nft/create_from_metadata") else {
            throw APIClientError.invalidAPIURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(shyftApiKey, forHTTPHeaderField: "x-api-key")

        // Shorter than Shyft's own 25-second limit. Abandoning this request is safe: it
        // only builds an unsigned transaction, so nothing has been minted yet.
        request.timeoutInterval = 18

        let payload: [String: Any] = [
            "network": "devnet",
            "creator_wallet": walletAddress,
            "metadata_uri": uri,
            "max_supply": 1,
            "receiver": walletAddress,
            "fee_payer": walletAddress
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown Shyft Error"
            Log.error("Shyft mint request failed (\(httpResponse.statusCode)): \(errorMsg)")
            throw Self.classify(status: httpResponse.statusCode, body: errorMsg)
        }

        struct ShyftResponse: Decodable {
            let result: ShyftResult
        }
        struct ShyftResult: Decodable {
            let encoded_transaction: String
            let mint: String
        }

        let res = try JSONDecoder().decode(ShyftResponse.self, from: data)
        let base64Tx = res.result.encoded_transaction

        guard let txData = Data(base64Encoded: base64Tx) else {
            throw URLError(.cannotDecodeRawData)
        }
        timer?.mark("shyft")

        // 2. Sign locally.
        var versionedTransaction = try VersionedTransaction.deserialize(data: txData)
        try versionedTransaction.sign(signers: [keyPair])
        let signedBase64 = try versionedTransaction.serialize().base64EncodedString()
        timer?.mark("potpis")

        // 3. Broadcast. Preflight is skipped because Shyft embeds a blockhash from its own
        //    RPC node, which the broadcasting node may not have seen yet; preflight would
        //    then reject a transaction the cluster accepts. The cluster still validates
        //    the blockhash on inclusion.
        do {
            let signature = try await WalletManager.shared.sendSignedTransaction(
                base64Tx: signedBase64,
                skipPreflight: true
            )
            timer?.mark("slanje")

            // With preflight skipped, confirmation is the only evidence the mint landed.
            // The `tickets` row is written only after it.
            try await WalletManager.shared.awaitConfirmation(signature: signature)
            timer?.mark("potvrda")

            Log.debug("[Solana] Mint confirmed: \(res.result.mint) (tx \(signature.prefix(8))…)")
            return res.result.mint
        } catch let error as APIClientError {
            Log.error("Mint broadcast failed: \(error)")
            throw error
        }
    }
}
