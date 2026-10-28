//
//  TicketPass.swift
//  diplomski
//

import Foundation
import SolanaSwift
import TweetNacl

/// The data a ticket holder presents at the gate, signed with the private key that
/// owns the NFT.
///
/// A code containing only the mint address would be public, constant for the ticket's
/// lifetime, and indistinguishable when copied — a screenshot could be forwarded to any
/// number of people. Signing a timestamped payload addresses both problems: the
/// signature proves the presenter controls the wallet that owns the ticket, and the
/// timestamp makes a captured code expire within seconds.
struct TicketPassPayload: Codable, Equatable {
    /// NFT mint address — the ticket's on-chain identity.
    let mint: String
    /// Base58 public key that signed this pass. Must match the on-chain token owner.
    let pubkey: String
    /// Unix seconds at issue time.
    let issuedAt: Int
    /// Random per-issue value, so two passes minted in the same second still differ.
    let nonce: String

    // Short keys — every byte here becomes QR modules.
    enum CodingKeys: String, CodingKey {
        case mint = "m"
        case pubkey = "p"
        case issuedAt = "t"
        case nonce = "n"
    }

    var issuedAtDate: Date { Date(timeIntervalSince1970: TimeInterval(issuedAt)) }
}

/// Outcome of checking a scanned code's cryptography and freshness.
///
/// This is deliberately separate from checking the chain or the database: a pass can
/// be perfectly signed and still belong to a used or resold ticket.
enum TicketPassCheck: Equatable {
    /// Signature verified and the pass is inside its validity window.
    case valid(TicketPassPayload)
    /// Signature verified, but the pass is too old — a screenshot or a replay.
    case expired(TicketPassPayload, age: TimeInterval)
    /// Well-formed pass whose signature does not verify against the embedded key.
    case badSignature
    /// An unsigned `rushguard://verify?mint=…` code. It identifies a ticket but proves
    /// nothing about who is presenting it, so it is reported explicitly rather than
    /// accepted.
    case unsignedLegacyCode(mint: String)
    /// Not a RushGuard code at all.
    case malformed

    var payload: TicketPassPayload? {
        switch self {
        case .valid(let payload): return payload
        case .expired(let payload, _): return payload
        case .badSignature, .unsignedLegacyCode, .malformed: return nil
        }
    }
}

enum TicketPass {
    /// How long a pass stays acceptable: short enough that a forwarded screenshot
    /// expires before it can be used, long enough for a slow scan.
    static let validityWindow: TimeInterval = 30

    /// Tolerance for the phone and the scanner disagreeing about the time. Also
    /// absorbs a pass that arrives fractionally "from the future".
    static let clockSkewAllowance: TimeInterval = 10

    private static let currentVersion = "1"

    // MARK: - Issuing

    /// Builds and signs a pass.
    ///
    /// The signature covers the exact payload bytes that are transmitted, so the
    /// verifier checks the bytes it received rather than a re-encoding of them and there
    /// is no canonicalisation step to exploit.
    static func issue(mint: String, keyPair: KeyPair, at date: Date = Date()) throws -> String {
        let payload = TicketPassPayload(
            mint: mint,
            pubkey: keyPair.publicKey.base58EncodedString,
            issuedAt: Int(date.timeIntervalSince1970),
            nonce: randomNonce()
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payloadData = try encoder.encode(payload)

        let signature = try NaclSign.signDetached(
            message: payloadData,
            secretKey: keyPair.secretKey
        )

        return "rushguard://pass?v=\(currentVersion)"
            + "&d=\(base64URLEncode(payloadData))"
            + "&s=\(base64URLEncode(signature))"
    }

    // MARK: - Verifying

    /// Checks a scanned string's signature and freshness. Performs no network access:
    /// Ed25519 verification is local.
    static func check(_ code: String, now: Date = Date()) -> TicketPassCheck {
        guard let components = URLComponents(string: code) else { return .malformed }
        let items = components.queryItems ?? []

        func query(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        // Unsigned legacy format.
        if code.hasPrefix("rushguard://verify"), let mint = query("mint") {
            return .unsignedLegacyCode(mint: mint)
        }

        guard code.hasPrefix("rushguard://pass"),
              let encodedPayload = query("d"),
              let encodedSignature = query("s"),
              let payloadData = base64URLDecode(encodedPayload),
              let signatureData = base64URLDecode(encodedSignature),
              let payload = try? JSONDecoder().decode(TicketPassPayload.self, from: payloadData) else {
            return .malformed
        }

        guard let publicKey = try? PublicKey(string: payload.pubkey) else {
            return .malformed
        }

        let signatureIsValid = (try? NaclSign.signDetachedVerify(
            message: payloadData,
            sig: signatureData,
            publicKey: publicKey.data
        )) ?? false

        guard signatureIsValid else { return .badSignature }

        // Signature is good — now judge freshness.
        let age = now.timeIntervalSince(payload.issuedAtDate)

        if age > validityWindow + clockSkewAllowance {
            return .expired(payload, age: age)
        }
        if age < -clockSkewAllowance {
            // Issued too far in the future to be a clock difference.
            return .expired(payload, age: age)
        }

        return .valid(payload)
    }

    // MARK: - Helpers

    private static func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 8)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            // Fall back to a non-cryptographic source. The nonce only needs to make
            // two passes distinct; the signature and timestamp carry the security.
            bytes = (0 ..< 8).map { _ in UInt8.random(in: 0 ... 255) }
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Base64url without padding — `+` and `/` are legal in a QR but awkward inside a
    /// URL query, and `=` padding just wastes modules.
    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }
}
