//
//  OnChainTicketReader.swift
//  diplomski
//

import Foundation
import SolanaSwift

/// What the blockchain itself says about a ticket, independent of anything stored
/// in Postgres.
///
/// `tickets` rows can be changed by whoever controls the database; this data can only
/// be changed by the holder of the private key that owns the token. Verification
/// compares the two.
struct OnChainTicket {
    /// The NFT mint address — the ticket's on-chain identity.
    let mint: String
    /// Wallet that currently holds the token. The authoritative owner.
    let owner: String
    /// The token account holding the NFT (owned by `owner`).
    let tokenAccount: String
    /// Token supply held in that account. An NFT holds exactly 1.
    let amount: UInt64
    /// Name written into the Metaplex metadata account at mint time.
    let onChainName: String?
    let onChainSymbol: String?
    /// Pointer to the off-chain JSON metadata (IPFS via Pinata here).
    let metadataURI: String?
    /// The fetched JSON, if the gateway responded.
    let offChainMetadata: TicketMetadataJSON?

    /// A single token in a single account is what makes this a non-fungible ticket
    /// rather than a balance. If this is false, the asset is not a valid ticket.
    var isNonFungible: Bool { amount == 1 }

    var row: Int? { offChainMetadata?.intValue(for: "Row") }
    var seat: Int? { offChainMetadata?.intValue(for: "Seat") }
    /// Present only when the metadata includes a `Showtime` attribute.
    var showtime: Date? {
        guard let raw = offChainMetadata?.stringValue(for: "Showtime") else { return nil }
        return ISO8601DateFormatter().date(from: raw)
    }
}

/// The Metaplex-standard JSON that `metadataURI` points at.
struct TicketMetadataJSON: Decodable {
    let name: String?
    let symbol: String?
    let description: String?
    let image: String?
    let attributes: [Attribute]?

    struct Attribute: Decodable {
        let traitType: String?
        let value: String?

        enum CodingKeys: String, CodingKey {
            case traitType = "trait_type"
            case value
        }

        /// The Metaplex standard allows string or numeric values; accept either.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            traitType = try container.decodeIfPresent(String.self, forKey: .traitType)

            if let string = try? container.decodeIfPresent(String.self, forKey: .value) {
                value = string
            } else if let int = try? container.decodeIfPresent(Int.self, forKey: .value) {
                value = String(int)
            } else if let double = try? container.decodeIfPresent(Double.self, forKey: .value) {
                value = String(double)
            } else {
                value = nil
            }
        }
    }

    func stringValue(for trait: String) -> String? {
        attributes?.first { $0.traitType?.caseInsensitiveCompare(trait) == .orderedSame }?.value
    }

    func intValue(for trait: String) -> Int? {
        stringValue(for: trait).flatMap(Int.init)
    }
}

enum OnChainReadError: LocalizedError {
    case mintNotFound(String)
    case noHolder(String)
    case metadataAccountMissing
    /// The chain could not be queried: every RPC endpoint was unreachable, throttled or
    /// erroring.
    ///
    /// Kept separate from `mintNotFound` (the cluster answering that no such mint
    /// exists), so a network failure is never reported as a counterfeit ticket.
    case chainUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .mintNotFound(let mint):
            return "No such mint on Devnet: \(mint.prefix(8))… The ticket does not exist on-chain."
        case .noHolder(let mint):
            return "Mint \(mint.prefix(8))… has no holder — the token was burned or never issued."
        case .metadataAccountMissing:
            return "This mint has no Metaplex metadata account."
        case .chainUnavailable(let detail):
            return "Could not reach Solana to verify this ticket (\(detail)). This is a network problem, not a problem with the ticket — try again."
        }
    }
}

/// Reads ticket state directly from Solana over plain JSON-RPC.
///
/// Uses no indexing API (such as Shyft), so verification depends only on RPC endpoints,
/// of which `SolanaRPCPool` provides several.
final class OnChainTicketReader {
    static let shared = OnChainTicketReader()

    private let rpc = SolanaRPCPool.shared
    private let metadataCache = NSCache<NSString, CacheBox>()

    /// Metaplex Token Metadata program. Same address on all clusters.
    static let tokenMetadataProgramID = "metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s"

    final class CacheBox {
        let metadata: TicketMetadataJSON
        init(_ metadata: TicketMetadataJSON) { self.metadata = metadata }
    }

    private init() {}

    // MARK: - Public API

    /// Resolves the current on-chain state of a ticket.
    ///
    /// - Parameter claimedOwner: the wallet presenting the ticket, when known. Enables a
    ///   cheaper ownership check (see `resolveHolder`).
    /// - Parameter fetchOffChainMetadata: when false, skips the IPFS fetch. Ownership
    ///   alone is enough for a verdict, and the gateway is the slowest dependency.
    func read(
        mint: String,
        claimedOwner: String? = nil,
        fetchOffChainMetadata: Bool = true
    ) async throws -> OnChainTicket {
        let holder = try await resolveHolder(mint: mint, claimedOwner: claimedOwner)
        let metadata = try? await readMetadataAccount(mint: mint)

        var offChain: TicketMetadataJSON?
        if fetchOffChainMetadata, let uri = metadata?.uri, !uri.isEmpty {
            offChain = await fetchMetadataJSON(uri: uri)
        }

        return OnChainTicket(
            mint: mint,
            owner: holder.owner,
            tokenAccount: holder.tokenAccount,
            amount: holder.amount,
            onChainName: metadata?.name,
            onChainSymbol: metadata?.symbol,
            metadataURI: metadata?.uri,
            offChainMetadata: offChain
        )
    }

    // MARK: - Ownership

    private struct Holder {
        let owner: String
        let tokenAccount: String
        let amount: UInt64
    }

    /// Checks whether `wallet` holds the NFT, via its associated token account.
    ///
    /// Returns `nil` when the wallet does not hold it, including when the associated
    /// token account does not exist; the caller then falls back to the full scan.
    ///
    /// Errors are swallowed deliberately: this is an optimisation, and a failure should
    /// fall back to the slower path rather than fail verification.
    private func holderIfOwned(mint: String, by wallet: String) async throws -> Holder? {
        guard
            let mintKey = try? PublicKey(string: mint),
            let ownerKey = try? PublicKey(string: wallet),
            let ata = try? PublicKey.associatedTokenAddress(
                walletAddress: ownerKey,
                tokenMintAddress: mintKey,
                tokenProgramId: TokenProgram.id
            )
        else { return nil }

        do {
            let balance = try await rpc.perform("getTokenAccountBalance") { client in
                try await client.getTokenAccountBalance(
                    pubkey: ata.base58EncodedString,
                    commitment: "confirmed"
                )
            }
            guard let amount = UInt64(balance.amount), amount > 0 else { return nil }
            return Holder(owner: wallet, tokenAccount: ata.base58EncodedString, amount: amount)
        } catch {
            // Usually "could not find account": this wallet does not hold the ticket.
            return nil
        }
    }

    /// Finds who holds the NFT: largest token account for the mint, then that
    /// account's owner from the SPL token account layout.
    private func resolveHolder(mint: String, claimedOwner: String? = nil) async throws -> Holder {
        // Fast path: when the presenting wallet is known, check its associated token
        // account directly with one cheap lookup. `getTokenLargestAccounts` is an
        // expensive scan that the public Devnet endpoint rate-limits specifically.
        if let claimedOwner, let holder = try await holderIfOwned(mint: mint, by: claimedOwner) {
            return holder
        }

        let largest: [TokenAmount]
        do {
            largest = try await rpc.perform("getTokenLargestAccounts") { client in
                try await client.getTokenLargestAccounts(pubkey: mint, commitment: "confirmed")
            }
        } catch {
            // Distinguish "no such mint" from "could not ask". The pool has already tried
            // every endpoint, so an infrastructure error means verification is
            // impossible right now, not that the ticket is counterfeit.
            if SolanaRPCPool.isInfrastructureFailure(error) {
                throw OnChainReadError.chainUnavailable(error.localizedDescription)
            }
            throw OnChainReadError.mintNotFound(mint)
        }

        guard let holding = largest.first(where: { (UInt64($0.amount) ?? 0) > 0 }),
              let tokenAccount = holding.address else {
            throw OnChainReadError.noHolder(mint)
        }

        let accountInfo: BufferInfo<TokenAccountState>? = try await rpc.perform("getAccountInfo") { client in
            try await client.getAccountInfo(account: tokenAccount)
        }

        guard let state = accountInfo?.data else {
            throw OnChainReadError.noHolder(mint)
        }

        return Holder(
            owner: state.owner.base58EncodedString,
            tokenAccount: tokenAccount,
            amount: UInt64(holding.amount) ?? 0
        )
    }

    // MARK: - Metaplex metadata account

    private struct MetadataAccount {
        let name: String
        let symbol: String
        let uri: String
    }

    private struct RawAccount: Decodable {
        let data: [String]
        let owner: String
    }

    /// Reads and parses the Metaplex metadata PDA for a mint.
    ///
    /// The account is Borsh-encoded. Its prefix is fixed-width — a 1-byte key, a
    /// 32-byte update authority, a 32-byte mint — followed by three length-prefixed
    /// strings. Metaplex pads those strings to fixed maximums (32 / 10 / 200) with
    /// null bytes and reports the *padded* length, so each has to be trimmed.
    private func readMetadataAccount(mint: String) async throws -> MetadataAccount {
        let mintKey = try PublicKey(string: mint)
        let programKey = try PublicKey(string: Self.tokenMetadataProgramID)

        let (pda, _) = try PublicKey.findProgramAddress(
            seeds: [
                Data("metadata".utf8),
                programKey.data,
                mintKey.data
            ],
            programId: programKey
        )

        let response: Rpc<RawAccount?> = try await rpc.perform("getAccountInfo(metadata)") { client in
            try await client.request(
                method: "getAccountInfo",
                params: [pda.base58EncodedString, RequestConfiguration(encoding: "base64")]
            )
        }

        guard let base64 = response.value?.data.first,
              let raw = Data(base64Encoded: base64) else {
            throw OnChainReadError.metadataAccountMissing
        }

        var reader = ByteReader(data: raw)
        reader.skip(1 + 32 + 32)  // key + update authority + mint

        guard let name = reader.readBorshString(),
              let symbol = reader.readBorshString(),
              let uri = reader.readBorshString() else {
            throw OnChainReadError.metadataAccountMissing
        }

        return MetadataAccount(name: name, symbol: symbol, uri: uri)
    }

    // MARK: - Off-chain JSON

    /// Fetches the JSON the metadata URI points at. Never throws: the IPFS gateway is
    /// the least reliable dependency, and ownership alone already decides the verdict.
    private func fetchMetadataJSON(uri: String) async -> TicketMetadataJSON? {
        if let cached = metadataCache.object(forKey: uri as NSString) {
            return cached.metadata
        }

        // `ipfs://` is not a scheme URLSession understands; route it through a gateway.
        let resolved = uri.hasPrefix("ipfs://")
            ? "https://gateway.pinata.cloud/ipfs/" + uri.dropFirst("ipfs://".count)
            : uri

        guard let url = URL(string: resolved) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, _) = try await URLSession.shared.data(for: request)
            let metadata = try JSONDecoder().decode(TicketMetadataJSON.self, from: data)
            // Immutable once pinned, so caching it indefinitely is safe.
            metadataCache.setObject(CacheBox(metadata), forKey: uri as NSString)
            return metadata
        } catch {
            Log.error("[Chain] Metadata fetch failed for \(resolved): \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Borsh helpers

/// Minimal sequential reader for the Borsh fields needed from the metadata account.
/// Bounds-checked throughout: it parses untrusted bytes, and a malformed account must
/// return nil rather than crash.
private struct ByteReader {
    let data: Data
    private(set) var offset: Int = 0

    init(data: Data) {
        self.data = data
    }

    mutating func skip(_ count: Int) {
        offset = min(offset + count, data.count)
    }

    mutating func readUInt32() -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        let slice = data.subdata(in: offset ..< offset + 4)
        offset += 4
        return slice.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
    }

    /// Reads a Borsh string (u32 little-endian length prefix, then bytes) and strips
    /// Metaplex's null padding.
    mutating func readBorshString() -> String? {
        guard let length = readUInt32() else { return nil }

        // Sanity bound: the largest Metaplex string field is the 200-byte URI.
        // Anything wildly larger means we have lost sync with the layout.
        guard length <= 1024, offset + Int(length) <= data.count else { return nil }

        let bytes = data.subdata(in: offset ..< offset + Int(length))
        offset += Int(length)

        let trimmed = bytes.prefix { $0 != 0 }
        return String(data: Data(trimmed), encoding: .utf8)
    }
}
