import Foundation

struct SupabaseTicket: Codable, Identifiable, Equatable {
    var id: String { nftId }
    
    let nftId: String
    let userId: UUID
    let movieTitle: String
    let posterPath: String?
    let showtime: Date
    let seat: Int
    var isListedOnMarketplace: Bool
    var isUsed: Bool
    var createdAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case nftId = "nft_id"
        case userId = "user_id"
        case movieTitle = "movie_title"
        case posterPath = "poster_path"
        case showtime
        case seat
        case isListedOnMarketplace = "is_listed_on_marketplace"
        case isUsed = "is_used"
        case createdAt = "created_at"
    }
    
    /// A ticket is expired if its showtime is in the past.
    var isExpired: Bool {
        showtime < Date()
    }
    
    /// A ticket can show a QR code only if it's not listed, not used, and not expired.
    var isUsable: Bool {
        !isListedOnMarketplace && !isUsed && !isExpired
    }
    
    var posterURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "\(APIConfig.imageBaseURL)\(path)")
    }
}
