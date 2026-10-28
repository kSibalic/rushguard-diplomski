//
//  MovieDetailViewModel.swift
//  diplomski
//

import SwiftUI
import Combine

@MainActor
class MovieDetailViewModel: ObservableObject {
    let movie: ActiveMovie
    @Published var showtimes: [ShowtimeAvailability] = []
    @Published var isLoading = true
    @Published var errorMessage: String?
    
    init(movie: ActiveMovie) {
        self.movie = movie
    }
    
    func fetchShowtimes() async {
        isLoading = true
        do {
            let fetchedShowtimes = try await DatabaseService.shared.fetchShowtimes(for: movie.id)
            let movieTitle = movie.title

            // Fan out one `fetchTakenSeats` per showtime in parallel, then collect by index.
            let takenCounts: [Int: Int] = await withTaskGroup(of: (Int, Int).self) { group in
                for (index, showtime) in fetchedShowtimes.enumerated() {
                    group.addTask {
                        let taken = try? await DatabaseService.shared.fetchTakenSeats(
                            movieTitle: movieTitle,
                            showtime: showtime.startTime
                        )
                        return (index, taken?.count ?? 0)
                    }
                }
                var result: [Int: Int] = [:]
                for await (index, count) in group {
                    result[index] = count
                }
                return result
            }

            self.showtimes = fetchedShowtimes.enumerated().map { index, showtime in
                let remaining = max(0, showtime.availableSeats - (takenCounts[index] ?? 0))
                return ShowtimeAvailability(showtime: showtime, remainingSeats: remaining)
            }
            self.isLoading = false
        } catch {
            self.errorMessage = "Failed to load showtimes."
            self.isLoading = false
        }
    }
}
