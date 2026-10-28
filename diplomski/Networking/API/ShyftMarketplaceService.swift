//
//  ShyftMarketplaceService.swift
//  diplomski
//

import Foundation

/// Configuration for the cinema's on-chain resale marketplace.
///
/// The marketplace is a Metaplex Auction House instance, accessed through Shyft's
/// marketplace API. Its address is a program-derived address (PDA) seeded by
/// `(authority, currency)`, so the same inputs always resolve to the same marketplace.
///
/// ## Why Auction House rather than an escrow wallet
///
/// With escrow, the seller transfers the ticket to a cinema-controlled wallet when
/// listing and the cinema forwards it on sale. The cinema would then hold tickets it
/// does not own, reintroducing the trusted intermediary the system is meant to remove.
///
/// Auction House avoids custody. When listing, the seller signs a transaction that
/// records the asking price in a `SellerTradeState` account and approves an Auction
/// House PDA as delegate on their token account; the ticket stays in the seller's
/// wallet. A buyer later submits a transaction that uses this delegation to move the
/// NFT to the buyer and the payment to the seller atomically — without the seller
/// being online.
enum MarketplaceConfig {
    /// The wallet that owns the marketplace: it can change the fee and fee recipient,
    /// and withdraw accumulated fees.
    ///
    /// This is the cinema's institutional wallet rather than any administrator's, so
    /// ownership of the marketplace does not depend on any individual staff account.
    static var authorityAddress: String { WalletManager.cinemaWalletAddress }

    /// The cinema's Auction House address on Devnet.
    ///
    /// Derived from `(authority, currency)`, so it is known before the account exists
    /// and does not depend on which wallet pays to create it. The admin dashboard's
    /// Marketplace Setup screen checks that the account exists on-chain.
    static let auctionHouseAddress = "8vaqmooCTZ42qJfRXFzxp2BJ53q9MKNgnxcPQyofDmTD"

    /// Cinema's fee on every resale, as a whole percentage.
    ///
    /// Enforced on-chain by the Auction House program, inside the same instruction that
    /// moves the NFT, so it cannot be bypassed by a modified client.
    static let transactionFeePercent = 5

    /// Native SOL. An Auction House is denominated in exactly one currency.
    static let currencyAddress = "So11111111111111111111111111111111111111112"

    static var isConfigured: Bool { !auctionHouseAddress.isEmpty }
}

enum ShyftMarketplaceError: LocalizedError {
    case notConfigured
    case api(String)
    case unexpectedResponse
    case walletUnavailable

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "The on-chain marketplace has not been set up yet. An administrator must run the one-time marketplace creation in the admin dashboard."
        case .api(let message):
            return message
        case .unexpectedResponse:
            return "The marketplace service returned a response the app could not read."
        case .walletUnavailable:
            return "No wallet is available for this account."
        }
    }
}

/// Client for Shyft's Auction House marketplace endpoints.
///
/// Every mutating endpoint follows the same pattern as minting: Shyft builds a
/// transaction and returns it base64-encoded, the app signs it locally with the key in
/// the Keychain, and broadcasts it through `SolanaRPCPool`. Shyft never holds a private
/// key. If Shyft is unavailable, existing tickets are unaffected; only new listings and
/// purchases cannot be built.
final class ShyftMarketplaceService {
    static let shared = ShyftMarketplaceService()

    private let apiKey = ShyftConfig.apiKey
    private let baseURL = "https://api.shyft.to/sol/v1/marketplace"
    private let network = "devnet"

    private init() {}

    // MARK: - Response shapes

    /// Returned by `create` and `find`. Field names match Shyft's payload exactly.
    struct MarketplaceInfo: Decodable {
        let address: String
        let treasuryAddress: String?
        let feeRecipient: String?
        let currencySymbol: String?
        let transactionFee: Double?
        let authority: String?
        let creator: String?
        /// Present on `create` (the transaction still needs signing), absent on `find`.
        let encodedTransaction: String?

        enum CodingKeys: String, CodingKey {
            case address
            case treasuryAddress = "treasury_address"
            case feeRecipient = "fee_recipient"
            case currencySymbol = "currency_symbol"
            case transactionFee = "transaction_fee"
            case authority
            case creator
            case encodedTransaction = "encoded_transaction"
        }
    }

    struct ListResult: Decodable {
        let encodedTransaction: String
        /// Address of the `SellerTradeState` account holding this listing. Required to
        /// cancel the listing later, and not derivable from the ticket alone — it must
        /// be persisted alongside the listing row.
        let listState: String

        enum CodingKeys: String, CodingKey {
            case encodedTransaction = "encoded_transaction"
            case listState = "list_state"
        }
    }

    struct BuyResult: Decodable {
        let encodedTransaction: String
        let purchaseReceipt: String?

        enum CodingKeys: String, CodingKey {
            case encodedTransaction = "encoded_transaction"
            case purchaseReceipt = "purchase_receipt"
        }
    }

    struct UnlistResult: Decodable {
        let encodedTransaction: String

        enum CodingKeys: String, CodingKey {
            case encodedTransaction = "encoded_transaction"
        }
    }

    // MARK: - Endpoints

    /// Builds the one-time marketplace-creation transaction.
    ///
    /// - `payer` signs and covers the rent; it is the only required signer, so any
    ///   wallet — such as an administrator's in-app wallet — can perform the creation.
    /// - The authority (the cinema treasury) owns the result and does not sign.
    ///
    /// Because the PDA is seeded by the authority, the marketplace address is the same
    /// regardless of which account pays.
    func buildCreateMarketplace(payer: String) async throws -> MarketplaceInfo {
        try await post(
            "create",
            body: [
                "network": network,
                "creator_wallet": payer,
                "authority_address": MarketplaceConfig.authorityAddress,
                "fee_recipient": MarketplaceConfig.authorityAddress,
                "transaction_fee": MarketplaceConfig.transactionFeePercent,
                "currency_address": MarketplaceConfig.currencyAddress
            ]
        )
    }

    /// Checks whether the cinema's marketplace account exists on-chain.
    /// Returns `nil` when it has not been created yet.
    func findMarketplace() async throws -> MarketplaceInfo? {
        var components = URLComponents(string: "\(baseURL)/find")!
        components.queryItems = [
            URLQueryItem(name: "network", value: network),
            URLQueryItem(name: "creator_address", value: MarketplaceConfig.authorityAddress),
            URLQueryItem(name: "authority_address", value: MarketplaceConfig.authorityAddress),
            URLQueryItem(name: "currency_address", value: MarketplaceConfig.currencyAddress)
        ]

        do {
            return try await get(components)
        } catch ShyftMarketplaceError.api(let message)
                    where message.localizedCaseInsensitiveContains("not found") {
            // Shyft reports a missing Auction House account as an error; here it simply
            // means the marketplace has not been created yet.
            return nil
        }
    }

    /// Builds the listing transaction: records the price and approves the Auction House
    /// as delegate. Signed by the **seller**, who is present at listing time.
    func buildList(nftAddress: String, sellerWallet: String, priceSOL: Double) async throws -> ListResult {
        try await post(
            "list",
            body: [
                "network": network,
                "marketplace_address": try requireMarketplace(),
                "nft_address": nftAddress,
                "seller_wallet": sellerWallet,
                "price": priceSOL
            ]
        )
    }

    /// Builds the purchase transaction. Signed by the buyer only: the seller authorised
    /// the transfer when listing and need not be online.
    func buildBuy(
        nftAddress: String,
        sellerAddress: String,
        buyerWallet: String,
        priceSOL: Double
    ) async throws -> BuyResult {
        try await post(
            "buy",
            body: [
                "network": network,
                "marketplace_address": try requireMarketplace(),
                "nft_address": nftAddress,
                "seller_address": sellerAddress,
                "buyer_wallet": buyerWallet,
                "price": priceSOL
            ]
        )
    }

    /// Builds the cancel-listing transaction, revoking the delegation. Signed by the seller.
    func buildUnlist(listState: String, sellerWallet: String) async throws -> UnlistResult {
        try await post(
            "unlist",
            body: [
                "network": network,
                "marketplace_address": try requireMarketplace(),
                "list_state": listState,
                "seller_wallet": sellerWallet
            ]
        )
    }

    // MARK: - Transport

    private func requireMarketplace() throws -> String {
        guard MarketplaceConfig.isConfigured else { throw ShyftMarketplaceError.notConfigured }
        return MarketplaceConfig.auctionHouseAddress
    }

    /// Shyft wraps every payload as `{ success, message, result }` and reports failures
    /// with HTTP 200 plus `success: false`, so the status code alone is not enough to
    /// tell success from failure.
    private struct Envelope<T: Decodable>: Decodable {
        let success: Bool
        let message: String?
        let error: String?
        let result: T?
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        guard let url = URL(string: "\(baseURL)/\(path)") else {
            throw ShyftMarketplaceError.unexpectedResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30
        return try await send(request, label: path)
    }

    private func get<T: Decodable>(_ components: URLComponents) async throws -> T {
        guard let url = components.url else { throw ShyftMarketplaceError.unexpectedResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.timeoutInterval = 30
        return try await send(request, label: components.path)
    }

    private func send<T: Decodable>(_ request: URLRequest, label: String) async throws -> T {
        let (data, _) = try await URLSession.shared.data(for: request)

        let envelope: Envelope<T>
        do {
            envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        } catch {
            // Log the raw payload: a bare decoding error would hide what Shyft returned.
            let raw = String(data: data, encoding: .utf8) ?? "<unreadable>"
            Log.debug("[Marketplace] \(label) returned an unreadable payload: \(raw)")
            throw ShyftMarketplaceError.unexpectedResponse
        }

        guard envelope.success, let result = envelope.result else {
            let message = envelope.error ?? envelope.message ?? "Marketplace request failed."
            Log.error("[Marketplace] \(label) failed: \(message)")
            throw ShyftMarketplaceError.api(message)
        }

        return result
    }
}
