//
//  Log.swift
//  diplomski
//

import Foundation

/// Leveled console output.
///
/// Protocol-level traces (blockhashes, balances, individual RPC calls) are useful while
/// debugging but bury measurements and failures in normal use, so they are gated behind
/// `isVerbose` rather than removed.
enum Log {
    /// Enables `debug` output. Off by default.
    nonisolated(unsafe) static var isVerbose = false

    /// Step-by-step protocol detail. Silent unless `isVerbose` is set.
    static func debug(_ message: @autoclosure () -> String) {
        guard isVerbose else { return }
        print(message())
    }

    /// Notable outcomes: a mint completing, a sale settling, a transaction signature.
    static func event(_ message: @autoclosure () -> String) {
        print(message())
    }

    /// Failures. Always printed.
    static func error(_ message: @autoclosure () -> String) {
        print("[Error] \(message())")
    }
}

/// Retries an operation when it fails for transport reasons.
///
/// The biometric prompt can interrupt an in-flight `URLSession` request. Retrying on the
/// resulting `URLError` costs nothing when the network is healthy, unlike a fixed delay
/// after every prompt.
///
/// Only `URLError` is retried. An HTTP error or a decoding failure means the request
/// arrived and was answered, so repeating it would fail the same way.
func withTransportRetry<T>(
    attempts: Int = 3,
    label: String = "request",
    _ operation: () async throws -> T
) async throws -> T {
    var lastError: Error?

    for attempt in 1 ... attempts {
        do {
            return try await operation()
        } catch let error as URLError {
            lastError = error
            Log.debug("[Retry] \(label) attempt \(attempt)/\(attempts) failed (\(error.code.rawValue)).")
            if attempt < attempts {
                // 150ms, then 300ms: a socket dropped by the biometric overlay
                // recovers almost immediately.
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 150_000_000)
            }
        }
    }

    throw lastError ?? URLError(.unknown)
}
