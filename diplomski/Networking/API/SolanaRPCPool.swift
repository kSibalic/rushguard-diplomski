//
//  SolanaRPCPool.swift
//  diplomski
//

import Foundation
import SolanaSwift

/// RPC provider credentials.
///
/// The public Solana endpoint (`api.devnet.solana.com`) needs no key but is heavily
/// rate-limited. Providers with an empty key are skipped, so the app works with no
/// keys configured and becomes more resilient as keys are added.
enum SolanaRPCConfig {
    static let heliusAPIKey = Secrets.heliusAPIKey

    /// Shyft also serves RPC. Note this makes Shyft a shared dependency for both
    /// minting and RPC.
    static let shyftAPIKey = Secrets.shyftAPIKey
}

/// An ordered pool of Solana RPC endpoints with automatic failover.
///
/// A single endpoint is a single point of failure: the public Devnet endpoint
/// rate-limits by IP and has no uptime guarantee. Failing over to an equivalent
/// endpoint costs one extra round trip and removes that failure mode.
///
/// This does not protect against a Devnet-wide outage or a ledger reset — every
/// provider serves the same cluster.
final class SolanaRPCPool: @unchecked Sendable {
    static let shared = SolanaRPCPool()

    struct Provider {
        let name: String
        let client: JSONRPCAPIClient
    }

    private let providers: [Provider]

    /// Index of the provider that last worked. Sticky, so a dead endpoint is not
    /// re-tried from scratch on every single call — we only pay the failover cost
    /// once, then keep using whatever answered.
    private var preferredIndex = 0
    private let lock = NSLock()

    private init() {
        var built: [Provider] = []

        if !SolanaRPCConfig.heliusAPIKey.isEmpty {
            built.append(
                Provider(
                    name: "Helius",
                    client: JSONRPCAPIClient(endpoint: APIEndPoint(
                        address: "https://devnet.helius-rpc.com/?api-key=\(SolanaRPCConfig.heliusAPIKey)",
                        network: .devnet
                    ))
                )
            )
        }

        built.append(
            Provider(
                name: "Public",
                client: JSONRPCAPIClient(endpoint: APIEndPoint(
                    address: "https://api.devnet.solana.com",
                    network: .devnet
                ))
            )
        )
        
        if !SolanaRPCConfig.shyftAPIKey.isEmpty {
            built.append(
                Provider(
                    name: "Shyft",
                    client: JSONRPCAPIClient(endpoint: APIEndPoint(
                        address: "https://devnet-rpc.shyft.to?api_key=\(SolanaRPCConfig.shyftAPIKey)",
                        network: .devnet
                    ))
                )
            )
        }

        providers = built
        Log.debug("[RPC] Pool initialised with \(built.count) provider(s): \(built.map(\.name).joined(separator: " -> "))")
    }

    /// The currently preferred client, for callers that need a client directly rather
    /// than a failover-wrapped operation. Prefer `perform` wherever possible.
    var preferredClient: JSONRPCAPIClient {
        lock.lock()
        defer { lock.unlock() }
        return providers[preferredIndex].client
    }

    /// Runs `operation` against the preferred provider, falling back through the
    /// remaining providers if it fails for infrastructure reasons.
    ///
    /// Only *infrastructure* failures trigger failover (see `isInfrastructureFailure`).
    /// A transaction that legitimately fails simulation — insufficient funds, a bad
    /// instruction — is rethrown immediately, because retrying it elsewhere would
    /// produce the same failure while hiding the real error behind a different one.
    ///
    /// Re-broadcasting a signed transaction across providers is safe: Solana
    /// deduplicates by signature, so a transaction that actually landed on the first
    /// provider cannot be applied twice by the second.
    @discardableResult
    func perform<T>(
        _ label: String,
        _ operation: (JSONRPCAPIClient) async throws -> T
    ) async throws -> T {
        let startIndex = currentPreferredIndex()
        var lastError: Error?

        for offset in 0 ..< providers.count {
            let index = (startIndex + offset) % providers.count
            let provider = providers[index]

            do {
                let result = try await operation(provider.client)
                if index != startIndex {
                    Log.debug("[RPC] \(label) succeeded on fallback provider '\(provider.name)' — promoting it.")
                    setPreferredIndex(index)
                }
                return result
            } catch {
                guard Self.isInfrastructureFailure(error) else {
                    // A real, meaningful error from the cluster. Surface it as-is.
                    throw error
                }
                lastError = error
                Log.error("[RPC] \(label) failed on '\(provider.name)' (\(error)) — trying next provider.")
            }
        }

        Log.error("[RPC] \(label) exhausted all \(providers.count) provider(s).")
        throw lastError ?? APIClientError.invalidResponse
    }

    // MARK: - Preferred index

    private func currentPreferredIndex() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return preferredIndex
    }

    private func setPreferredIndex(_ index: Int) {
        lock.lock()
        preferredIndex = index
        lock.unlock()
    }

    // MARK: - Error classification

    /// Distinguishes "this endpoint is unreachable, degraded, or throttling us" from
    /// "the cluster considered this request and rejected it".
    ///
    /// Getting this boundary right is the whole point of the class. Failing over on a
    /// genuine rejection would mask real bugs; not failing over on a transport error
    /// would defeat the purpose.
    static func isInfrastructureFailure(_ error: Error) -> Bool {
        // Timeouts, DNS failures, connection drops, offline device.
        if error is URLError { return true }

        // A rate-limit or gateway page returned instead of JSON-RPC — the response
        // decodes as garbage rather than as a structured error.
        if error is DecodingError { return true }

        if let apiError = error as? APIClientError {
            switch apiError {
            case .invalidAPIURL, .invalidResponse:
                return true

            case .responseError(let response):
                // -32005: node is behind / request rate exceeded.
                // -32004: block not available on this node yet.
                // -32603: internal error.
                if let code = response.code, [-32005, -32004, -32603, 429, 502, 503, 504].contains(code) {
                    return true
                }
                return false

            case .blockhashNotFound, .transactionSimulationError, .couldNotRetrieveAccountInfo:
                // All three are real answers from the cluster, not endpoint problems.
                return false
            }
        }

        return false
    }
}
