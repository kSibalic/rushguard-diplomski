//
//  APIClient.swift
//  diplomski
//
//  Created by Karlo Šibalić on 21.04.2026..
//

import Foundation

class TMDBAdminClient {
    static let shared = TMDBAdminClient()
    
    private init() {}
    
    func searchMovies(query: String) async throws -> [Movie] {
        guard !query.isEmpty else { return [] }
        
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "\(APIConfig.baseURL)/search/movie?query=\(encodedQuery)&include_adult=false&language=en-US&page=1"
        
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = [
            "accept": "application/json",
            "Authorization": "Bearer \(APIConfig.readAccessToken)"
        ]
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        let movieResponse = try decoder.decode(MovieResponse.self, from: data)
        return movieResponse.results
    }
    
    func fetchMovieDetails(movieID: Int) async throws -> MovieDetail {
        let urlString = "\(APIConfig.baseURL)/movie/\(movieID)?append_to_response=credits"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = [
            "accept": "application/json",
            "Authorization": "Bearer \(APIConfig.readAccessToken)"
        ]
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(MovieDetail.self, from: data)
    }
}
