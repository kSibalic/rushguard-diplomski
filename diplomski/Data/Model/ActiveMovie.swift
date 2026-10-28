//
//  ActiveMovie.swift
//  diplomski
//

import Foundation

struct ActiveMovie: Identifiable, Codable {
    let id: Int
    let title: String
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let ticketPriceSol: Double?
    let isActive: Bool?
    let createdAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case overview
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case ticketPriceSol = "ticket_price_sol"
        case isActive = "is_active"
        case createdAt = "created_at"
    }
    
    var posterURL: URL? {
        guard let path = posterPath else { return nil }
        return URL(string: "\(APIConfig.imageBaseURL)\(path)")
    }
    
    var backdropURL: URL? {
        guard let path = backdropPath else { return nil }
        return URL(string: "\(APIConfig.imageBaseURL)\(path)")
    }
}
