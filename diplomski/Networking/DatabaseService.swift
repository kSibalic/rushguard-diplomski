//
//  DatabaseService.swift
//  diplomski
//

import Foundation
import Supabase

class DatabaseService {
    static let shared = DatabaseService()
    
    private init() {}
    
    // MARK: - Admin Functions
    
    /// Inserts a movie into the `active_movies` table.
    func addMovieToCinema(movie: ActiveMovie) async throws {
        try await supabase
            .from("active_movies")
            .insert(movie)
            .execute()
    }
    
    /// Inserts a showtime into the `showtimes` table.
    func addShowtime(showtime: Showtime) async throws {
        try await supabase
            .from("showtimes")
            .insert(showtime)
            .execute()
    }
    
    // MARK: - Client Functions
    
    /// Fetches all active movies from the `active_movies` table.
    func fetchActiveMovies() async throws -> [ActiveMovie] {
        let movies: [ActiveMovie] = try await supabase
            .from("active_movies")
            .select()
            .eq("is_active", value: true)
            .execute()
            .value
        return movies
    }
    
    /// Fetches showtimes for a specific movie.
    func fetchShowtimes(for movieId: Int) async throws -> [Showtime] {
        let showtimes: [Showtime] = try await supabase
            .from("showtimes")
            .select()
            .eq("movie_id", value: movieId)
            .execute()
            .value
        return showtimes
    }
    
    // MARK: - Marketplace Functions
    
    /// Fetches all marketplace listings.
    func fetchListings() async throws -> [MarketplaceListing] {
        let listings: [MarketplaceListing] = try await supabase
            .from("marketplace_listings")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value
        return listings
    }
    
    /// Creates a new marketplace listing (seller lists a ticket).
    func createListing(listing: MarketplaceListing) async throws {
        try await supabase
            .from("marketplace_listings")
            .insert(listing)
            .execute()
    }
    
    /// Deletes a listing by ID (for the seller's own listing after sale).
    func deleteListing(id: UUID) async throws {
        try await supabase
            .from("marketplace_listings")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
    
    /// Admin-only: deletes any listing and un-lists the underlying ticket.
    ///
    /// Runs as a `SECURITY DEFINER` function so it bypasses RLS; the function
    /// itself checks `is_admin()` before doing anything, so a non-admin caller
    /// gets a Postgres exception rather than a deletion.
    func adminDeleteListing(id: UUID) async throws {
        try await supabase
            .rpc("admin_delete_listing", params: ["listing_id": id.uuidString])
            .execute()
    }

    /// Pre-check run before the buyer signs, so an already sold or expired listing is
    /// rejected without a biometric prompt or network fee. The on-chain sale itself is
    /// atomic and would fail independently if the listing were gone.
    func listingIsPurchasable(listingId: UUID) async throws -> Bool {
        let purchasable: Bool = try await supabase
            .rpc("listing_is_purchasable", params: ["p_listing_id": listingId.uuidString])
            .execute()
            .value
        return purchasable
    }

    /// Updates the database after an Auction House sale has settled on-chain:
    /// reassigns the ticket to the buyer and removes the listing.
    ///
    /// The function re-verifies the listing, buyer and seller under a `FOR UPDATE`
    /// lock, so concurrent calls cannot both succeed. Returns the ticket's mint address.
    ///
    /// - Parameter txSignature: the confirmed settling transaction, written to the
    ///   Postgres log so any divergence between database and chain can be traced.
    func buyMarketplaceTicket(listingId: UUID, txSignature: String? = nil) async throws -> String {
        let nftId: String = try await supabase
            .rpc("buy_marketplace_ticket", params: [
                "p_listing_id": listingId.uuidString,
                "p_tx_signature": txSignature
            ])
            .execute()
            .value
        return nftId
    }
    
    // MARK: - Vault / Ticket Functions
    
    /// Fetches the current user's tickets from the `tickets` table.
    func fetchMyTickets() async throws -> [SupabaseTicket] {
        guard let userId = try? await supabase.auth.session.user.id else {
            return []
        }
        
        let tickets: [SupabaseTicket] = try await supabase
            .from("tickets")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
        return tickets
    }
    
    /// Adds a newly minted ticket to the `tickets` table.
    func addTicket(ticket: SupabaseTicket) async throws {
        try await supabase
            .from("tickets")
            .insert(ticket)
            .execute()
    }
    
    /// Updates the `is_listed_on_marketplace` status of a ticket.
    func updateTicketListingStatus(nftId: String, isListed: Bool) async throws {
        struct UpdatePayload: Encodable {
            let is_listed_on_marketplace: Bool
        }
        try await supabase
            .from("tickets")
            .update(UpdatePayload(is_listed_on_marketplace: isListed))
            .eq("nft_id", value: nftId)
            .execute()
    }
    
    /// Fetches occupied seat numbers for a specific movie and showtime.
    ///
    /// Uses the `taken_seats` RPC rather than querying `tickets` directly: under Row
    /// Level Security a client sees only its own tickets, so a direct query would
    /// report other customers' seats as free. The function returns seat numbers only.
    func fetchTakenSeats(movieTitle: String, showtime: Date) async throws -> [Int] {
        struct SeatResponse: Decodable {
            let seat: Int
        }
        struct Params: Encodable {
            let p_movie_title: String
            let p_showtime: Date
        }

        let responses: [SeatResponse] = try await supabase
            .rpc("taken_seats", params: Params(p_movie_title: movieTitle, p_showtime: showtime))
            .execute()
            .value

        return responses.map { $0.seat }
    }
    
    /// Fetches a single ticket by its NFT mint address (for admin verification).
    func fetchTicketByNftId(nftId: String) async throws -> SupabaseTicket? {
        let tickets: [SupabaseTicket] = try await supabase
            .from("tickets")
            .select()
            .eq("nft_id", value: nftId)
            .limit(1)
            .execute()
            .value
        return tickets.first
    }
    
    /// Fetches a user profile by their UUID (for admin verification).
    func fetchProfileById(userId: UUID) async throws -> UserProfile? {
        let profiles: [UserProfile] = try await supabase
            .from("profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value
        return profiles.first
    }
    
    /// Marks a ticket as used/redeemed by the admin after scanning.
    ///
    /// Not a plain `UPDATE`: owner-scoped RLS would reject it (the admin does not own
    /// the ticket), and a client able to write `is_used` could also reset it. The RPC
    /// checks `is_admin()` and only ever sets the flag to `true`.
    ///
    /// - Returns: `true` if this call redeemed the ticket, `false` if it was
    ///   already redeemed — so a replayed scan is distinguishable from a fresh one.
    @discardableResult
    func markTicketAsUsed(nftId: String) async throws -> Bool {
        let redeemed: Bool = try await supabase
            .rpc("redeem_ticket", params: ["p_nft_id": nftId])
            .execute()
            .value
        return redeemed
    }
}
