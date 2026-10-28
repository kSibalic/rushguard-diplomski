//
//  APIConfig.swift
//  diplomski
//
//  Created by Karlo Šibalić on 21.04.2026..
//

import Foundation

struct APIConfig {
    static let baseURL = "https://api.themoviedb.org/3"
    static let imageBaseURL = "https://image.tmdb.org/t/p/w500"
    static let readAccessToken = Secrets.tmdbReadAccessToken
}

/// Shyft credentials, shared by the minting and marketplace clients.
///
/// Shyft only builds transactions: it returns unsigned transactions that this app signs
/// locally with a key Shyft never sees. A leaked key allows building transactions on
/// this account's quota — an availability and billing concern, not a custody one.
enum ShyftConfig {
    static let apiKey = Secrets.shyftAPIKey
}
