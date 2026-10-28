//
//  MarketplaceListing.swift
//  diplomski
//

import Foundation

struct MarketplaceListing: Identifiable, Codable {
    let id: UUID
    let nftId: String
    let movieTitle: String
    let posterPath: String?
    let showtime: Date
    let seat: Int
    let price: Double
    let sellerId: UUID
    let sellerPubKey: String
    let createdAt: Date?

    /// Address of the on-chain `SellerTradeState` account backing this listing.
    ///
    /// Returned by Shyft when the listing transaction is built and required to cancel
    /// the listing later; it cannot be derived from the ticket alone. A listing without
    /// it has no on-chain backing (see `isOnChain`).
    let listState: String?

    enum CodingKeys: String, CodingKey {
        case id
        case nftId = "nft_id"
        case movieTitle = "movie_title"
        case posterPath = "poster_path"
        case showtime
        case seat
        case price
        case sellerId = "seller_id"
        case sellerPubKey = "seller_pub_key"
        case createdAt = "created_at"
        case listState = "list_state"
    }

    /// True when the ticket is delegated to the Auction House, so a purchase moves it
    /// on-chain. A listing without a trade state cannot be bought.
    var isOnChain: Bool {
        guard let listState else { return false }
        return !listState.isEmpty
    }
    
    var posterURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "\(APIConfig.imageBaseURL)\(path)")
    }
}
