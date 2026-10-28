//
//  CatalogViewModel.swift
//  diplomski
//
//  Created by Karlo Šibalić on 22.04.2026..
//

import SwiftUI
import Combine

@MainActor
class CatalogViewModel: ObservableObject {
    @Published var featuredMovie: ActiveMovie?
    @Published var trendingMovies: [ActiveMovie] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    
    func loadMovies() async {
        isLoading = true
        errorMessage = nil
        do {
            let movies = try await DatabaseService.shared.fetchActiveMovies()
            if let first = movies.first {
                self.featuredMovie = first
                self.trendingMovies = Array(movies.dropFirst())
            } else {
                self.featuredMovie = nil
                self.trendingMovies = []
            }
            self.isLoading = false
        } catch {
            Log.error("Failed to load catalog: \(error)")
            self.errorMessage = "Failed to load movies."
            self.isLoading = false
        }
    }
}
