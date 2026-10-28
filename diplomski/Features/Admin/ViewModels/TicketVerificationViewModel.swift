//
//  TicketVerificationViewModel.swift
//  diplomski
//

import SwiftUI
import Combine

/// One field as the database records it, next to the same field as the chain records it.
///
/// Postgres rows can be edited by anyone with database access, while on-chain values
/// cannot be changed without the owner's private key, so a mismatch indicates the
/// database has diverged from the authoritative record.
struct FieldComparison: Identifiable {
    let id = UUID()
    let label: String
    let database: String
    let chain: String
    let status: Status

    enum Status {
        case match
        case mismatch
        /// One side could not be read — absence of evidence, not evidence of tampering.
        case unavailable
    }
}

/// The gate's decision about a scanned code.
enum VerificationVerdict: Equatable {
    case valid

    // Cryptographic failures — the code itself is not trustworthy.
    case malformedCode
    case forgedSignature
    case staleCode(age: TimeInterval)
    case unsignedLegacyCode

    // Chain failures.
    case notOnChain(String)
    /// Solana could not be reached. Not a rejection of the ticket: the check could not
    /// be performed.
    case chainUnreachable(String)
    case notNonFungible
    /// Presenter's key is not the wallet that holds the NFT. The core check.
    case ownerMismatch(presented: String, actual: String)

    // Record failures.
    case notInDatabase
    case alreadyUsed
    case expired
    case listedForSale

    var admits: Bool { self == .valid }

    var title: String {
        switch self {
        case .valid: return "VALID TICKET"
        case .malformedCode: return "UNREADABLE CODE"
        case .forgedSignature: return "INVALID SIGNATURE"
        case .staleCode: return "EXPIRED CODE"
        case .unsignedLegacyCode: return "UNSIGNED CODE"
        case .notOnChain: return "NOT ON BLOCKCHAIN"
        case .chainUnreachable: return "CANNOT VERIFY"
        case .notNonFungible: return "NOT A VALID NFT"
        case .ownerMismatch: return "OWNERSHIP MISMATCH"
        case .notInDatabase: return "UNKNOWN TICKET"
        case .alreadyUsed: return "ALREADY USED"
        case .expired: return "SHOWTIME PASSED"
        case .listedForSale: return "LISTED FOR SALE"
        }
    }

    var subtitle: String {
        switch self {
        case .valid:
            return "Signature verified, holder confirmed on-chain, ticket unused."
        case .malformedCode:
            return "This is not a RushGuard ticket code."
        case .forgedSignature:
            return "The signature does not match the key embedded in the code. This pass was not produced by the wallet it claims to come from."
        case .staleCode(let age):
            return "This code was generated \(Int(age)) seconds ago and is no longer valid. Ask the holder to reopen their ticket — most likely this is a screenshot."
        case .unsignedLegacyCode:
            return "An older static code that proves only which ticket is being claimed, not who is presenting it. Anyone holding a copy could produce it. Verify identity manually."
        case .notOnChain(let detail):
            return detail
        case .chainUnreachable(let detail):
            return "\(detail)\n\nThe signature on this pass was checked locally and is shown above. Retry once connectivity returns, or admit manually on that basis." 
        case .notNonFungible:
            return "The token at this address is not a unique NFT and cannot be a ticket."
        case .ownerMismatch(let presented, let actual):
            return "The code was signed by \(presented.prefix(8))… but the NFT is held by \(actual.prefix(8))…. The presenter does not own this ticket."
        case .notInDatabase:
            return "This NFT exists on-chain but has no matching cinema record. It was not issued by this system."
        case .alreadyUsed:
            return "This ticket has already been scanned and redeemed."
        case .expired:
            return "The showtime for this ticket has already passed."
        case .listedForSale:
            return "This ticket is listed on the marketplace. The owner must unlist it before entry."
        }
    }

    var icon: String {
        switch self {
        case .valid: return "checkmark.shield.fill"
        case .unsignedLegacyCode, .listedForSale: return "exclamationmark.triangle.fill"
        case .staleCode: return "clock.badge.xmark"
        case .expired: return "clock.badge.xmark"
        case .alreadyUsed: return "ticket.fill"
        case .forgedSignature, .ownerMismatch: return "xmark.shield.fill"
        default: return "xmark.shield.fill"
        }
    }

    var color: Color {
        switch self {
        case .valid: return .green
        case .unsignedLegacyCode, .listedForSale: return .yellow
        case .staleCode, .expired: return .orange
        case .alreadyUsed: return .gray
        default: return .red
        }
    }
}

@MainActor
final class TicketVerificationViewModel: ObservableObject {
    @Published private(set) var isLoading = true
    @Published private(set) var verdict: VerificationVerdict = .malformedCode
    @Published private(set) var comparisons: [FieldComparison] = []
    @Published private(set) var ticket: SupabaseTicket?
    @Published private(set) var chain: OnChainTicket?
    @Published private(set) var ownerProfile: UserProfile?
    @Published private(set) var passPayload: TicketPassPayload?
    @Published private(set) var mint: String?
    @Published private(set) var chainReadFailure: String?
    /// True when the chain read failed for infrastructure reasons rather than because
    /// the mint is absent. Drives the difference between "cannot verify" and
    /// "not on blockchain".
    private var chainWasUnreachable = false

    @Published var isMarkingUsed = false
    @Published var redeemError: String?
    @Published private(set) var markedUsed = false

    /// The raw string that came off the scanner.
    private let scannedCode: String

    init(scannedCode: String) {
        self.scannedCode = scannedCode
    }

    // MARK: - Verification

    func verify() async {
        isLoading = true
        defer { isLoading = false }

        // 1. Cryptography first. Everything downstream is meaningless if the code
        //    itself cannot be trusted, and this step needs no network at all.
        let passCheck = TicketPass.check(scannedCode)

        var resolvedMint: String
        var cryptographicVerdict: VerificationVerdict?

        switch passCheck {
        case .valid(let payload):
            resolvedMint = payload.mint
            passPayload = payload

        case .expired(let payload, let age):
            resolvedMint = payload.mint
            passPayload = payload
            cryptographicVerdict = .staleCode(age: age)

        case .unsignedLegacyCode(let legacyMint):
            resolvedMint = legacyMint
            cryptographicVerdict = .unsignedLegacyCode

        case .badSignature:
            verdict = .forgedSignature
            return

        case .malformed:
            verdict = .malformedCode
            return
        }

        mint = resolvedMint

        // 2. Read both sources concurrently; they are independent.
        let mintToRead = resolvedMint
        async let chainRead = readChain(mint: mintToRead)
        async let databaseRead = readDatabase(mint: mintToRead)

        let (chainResult, databaseTicket) = await (chainRead, databaseRead)

        chain = chainResult
        ticket = databaseTicket

        if let databaseTicket {
            ownerProfile = try? await DatabaseService.shared.fetchProfileById(userId: databaseTicket.userId)
        }

        comparisons = buildComparisons(ticket: databaseTicket, chain: chainResult)

        // 3. Decide. A cryptographic failure outranks everything else, but the reads
        //    above still run so the admin sees the full picture behind a refusal.
        if let cryptographicVerdict, cryptographicVerdict != .unsignedLegacyCode {
            verdict = cryptographicVerdict
            return
        }

        verdict = decide(
            chain: chainResult,
            ticket: databaseTicket,
            presentedKey: passPayload?.pubkey,
            legacyCode: cryptographicVerdict == .unsignedLegacyCode
        )
    }

    private func readChain(mint: String) async -> OnChainTicket? {
        do {
            // Passing the presented key lets the reader answer "does this wallet hold
            // it?" with one cheap lookup instead of an expensive, rate-limited scan.
            return try await OnChainTicketReader.shared.read(
                mint: mint,
                claimedOwner: passPayload?.pubkey
            )
        } catch OnChainReadError.chainUnavailable(let detail) {
            chainReadFailure = detail
            chainWasUnreachable = true
            return nil
        } catch {
            chainReadFailure = error.localizedDescription
            return nil
        }
    }

    private func readDatabase(mint: String) async -> SupabaseTicket? {
        try? await DatabaseService.shared.fetchTicketByNftId(nftId: mint)
    }

    /// The validation rule, in one place.
    ///
    /// Ownership is checked against the chain, not the database. The database supplies
    /// only what the chain does not record: whether the ticket has been redeemed and
    /// whether it is listed for resale.
    private func decide(
        chain: OnChainTicket?,
        ticket: SupabaseTicket?,
        presentedKey: String?,
        legacyCode: Bool
    ) -> VerificationVerdict {
        guard let chain else {
            // Failing to reach the chain is not evidence against the ticket, so it must
            // not be reported as "not on blockchain".
            if chainWasUnreachable {
                return .chainUnreachable(chainReadFailure ?? "Solana could not be reached.")
            }
            return .notOnChain(chainReadFailure ?? "The ticket could not be read from Solana.")
        }

        guard chain.isNonFungible else { return .notNonFungible }

        // The core check: whoever signed the pass must be the wallet that currently
        // holds the token. A legacy code carries no key, which is why it is flagged.
        if let presentedKey, presentedKey != chain.owner {
            return .ownerMismatch(presented: presentedKey, actual: chain.owner)
        }

        guard let ticket else { return .notInDatabase }

        if ticket.isUsed || markedUsed { return .alreadyUsed }
        if ticket.isExpired { return .expired }
        if ticket.isListedOnMarketplace { return .listedForSale }

        if legacyCode { return .unsignedLegacyCode }

        return .valid
    }

    // MARK: - Side-by-side comparison

    private func buildComparisons(ticket: SupabaseTicket?, chain: OnChainTicket?) -> [FieldComparison] {
        var rows: [FieldComparison] = []

        func compare(_ label: String, database: String?, chain: String?) {
            let databaseValue = database ?? "—"
            let chainValue = chain ?? "not published on-chain"
            let status: FieldComparison.Status

            if database == nil || chain == nil {
                status = .unavailable
            } else {
                status = database?.caseInsensitiveCompare(chain ?? "") == .orderedSame ? .match : .mismatch
            }

            rows.append(FieldComparison(label: label, database: databaseValue, chain: chainValue, status: status))
        }

        compare("Movie", database: ticket?.movieTitle, chain: chain?.onChainName)

        let databaseSeat = ticket.map { Showtime.rowAndColumn(for: $0.seat) }
        compare(
            "Row",
            database: databaseSeat.map { String($0.row) },
            chain: chain?.row.map(String.init)
        )
        compare(
            "Seat",
            database: databaseSeat.map { String($0.column) },
            chain: chain?.seat.map(String.init)
        )

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        compare(
            "Showtime",
            database: ticket.map { formatter.string(from: $0.showtime) },
            chain: chain?.showtime.map { formatter.string(from: $0) }
        )

        // After a resale, the database owner is updated once the sale settles on-chain.
        // A mismatch means the database index is out of date or has been altered; the
        // chain value is authoritative either way.
        compare(
            "Owner wallet",
            database: ownerProfile?.solanaPublicKey,
            chain: chain?.owner
        )

        return rows
    }

    // MARK: - Redemption

    func markAsUsed() async {
        guard let mint else { return }
        isMarkingUsed = true
        defer { isMarkingUsed = false }

        do {
            // `redeem_ticket` sets `is_used` only if it was still false and reports which
            // happened, so two staff scanning the same ticket cannot both admit it.
            let didRedeem = try await DatabaseService.shared.markTicketAsUsed(nftId: mint)
            markedUsed = true
            verdict = .alreadyUsed

            if !didRedeem {
                redeemError = "This ticket had already been redeemed — it was not redeemed again."
            }
        } catch {
            redeemError = "Failed to redeem: \(error.localizedDescription)"
        }
    }
}
