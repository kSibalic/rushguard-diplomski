//
//  MovieDetail.swift
//  diplomski
//
//  Created by Karlo Šibalić on 21.04.2026..
//

import Foundation

struct MovieDetail: Codable {
    let title: String
    let overview: String
    let posterPath: String?
    let releaseDate: String
    let voteAverage: Double
    let runtime: Int?
    let genres: [Genre]?
    let credits: Credits
    
    enum CodingKeys: String, CodingKey {
        case title, overview, runtime, genres, credits
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case voteAverage = "vote_average"
    }
    
    var directorName: String? {
        credits.crew.first(where: { $0.job == "Director" })?.name
    }
}

struct Genre: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
}

struct Credits: Codable {
    let cast: [CastMember]
    let crew: [CrewMember]
}

struct CastMember: Codable, Identifiable {
    let id: Int
    let name: String
    let profilePath: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case profilePath = "profile_path"
    }
}

struct CrewMember: Codable {
    let name: String
    let job: String
}
