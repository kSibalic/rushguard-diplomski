//
//  AdminDashboardViewModel.swift
//  diplomski
//

import SwiftUI
import Combine

struct ShowtimeEntry: Identifiable {
    let id = UUID()
    var date: Date = Date().addingTimeInterval(86400)
    var seats: String = "100"
    var theaterName: String = "Theatre A"
}

@MainActor
class AdminDashboardViewModel: ObservableObject {
    @Published var searchQuery = ""
    @Published var searchResults: [Movie] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // For "Add to Cinema" flow
    @Published var selectedMovie: Movie?
    @Published var ticketPriceSol: String = "0.45"
    @Published var showtimeEntries: [ShowtimeEntry] = [ShowtimeEntry()]
    
    @Published var isSuccess = false
    
    static let availableTheaters = ["Theatre A", "Theatre B", "Theatre C", "Theatre D"]
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        $searchQuery
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                Task {
                    await self?.search(query: query)
                }
            }
            .store(in: &cancellables)
    }
    
    func search(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let results = try await TMDBAdminClient.shared.searchMovies(query: query)
            self.searchResults = results
            self.isLoading = false
        } catch {
            self.errorMessage = "Failed to search movies: \(error.localizedDescription)"
            self.isLoading = false
        }
    }
    
    func addShowtimeEntry() {
        showtimeEntries.append(ShowtimeEntry())
    }
    
    func removeShowtimeEntry(at offsets: IndexSet) {
        showtimeEntries.remove(atOffsets: offsets)
    }
    
    func addToCinema() async {
        guard let movie = selectedMovie,
              let price = Double(ticketPriceSol),
              !showtimeEntries.isEmpty else {
            errorMessage = "Invalid input data."
            return
        }
        
        // Validate all seat counts
        for entry in showtimeEntries {
            guard Int(entry.seats) != nil else {
                errorMessage = "Invalid seat count in one of the showtimes."
                return
            }
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // 1. Insert the movie (once)
            let activeMovie = ActiveMovie(
                id: movie.id,
                title: movie.title,
                overview: movie.overview,
                posterPath: movie.posterPath,
                backdropPath: nil,
                releaseDate: movie.releaseDate,
                ticketPriceSol: price,
                isActive: true,
                createdAt: Date()
            )
            
            try await DatabaseService.shared.addMovieToCinema(movie: activeMovie)
            
            // 2. Insert each showtime
            for entry in showtimeEntries {
                let showtime = Showtime(
                    id: UUID(),
                    movieId: movie.id,
                    startTime: entry.date,
                    availableSeats: Int(entry.seats) ?? 100,
                    theaterName: entry.theaterName,
                    createdAt: Date()
                )
                try await DatabaseService.shared.addShowtime(showtime: showtime)
            }
            
            isSuccess = true
            isLoading = false
            selectedMovie = nil
            // Reset entries for next use
            showtimeEntries = [ShowtimeEntry()]
        } catch {
            self.errorMessage = "Failed to add to database: \(error.localizedDescription)"
            self.isLoading = false
        }
    }
}
