//
//  Showtime.swift
//  diplomski
//

import Foundation

/// Raw `showtimes` row as stored in the DB. Immutable — derived availability
/// belongs on `ShowtimeAvailability`.
struct Showtime: Identifiable, Codable {
    let id: UUID
    let movieId: Int
    let startTime: Date
    /// Max seat capacity for this showtime. Persisted as `available_seats`
    /// in the DB for historical reasons.
    let availableSeats: Int
    let theaterName: String
    let createdAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case movieId = "movie_id"
        case startTime = "start_time"
        case availableSeats = "available_seats"
        case theaterName = "theater_name"
        case createdAt = "created_at"
    }
}

/// A `Showtime` together with its live remaining-seat count, derived from
/// the `tickets` table at fetch time.
struct ShowtimeAvailability: Identifiable {
    let showtime: Showtime
    let remainingSeats: Int

    var id: UUID { showtime.id }
}

extension Showtime {
    /// Column count used by the seat-selection grid and stamped into NFT metadata.
    /// The SeatSelectionView grid MUST lock to this value so display math stays consistent.
    static let seatsPerRow = 7

    /// 1-indexed (row, column) position for a linear seat index.
    static func rowAndColumn(for seat: Int) -> (row: Int, column: Int) {
        let row = (seat - 1) / seatsPerRow + 1
        let column = (seat - 1) % seatsPerRow + 1
        return (row, column)
    }

    /// Formatted "Row X, Seat Y" label for a linear seat index.
    static func seatLabel(for seat: Int) -> String {
        let pos = rowAndColumn(for: seat)
        return "Row \(pos.row), Seat \(pos.column)"
    }
}
