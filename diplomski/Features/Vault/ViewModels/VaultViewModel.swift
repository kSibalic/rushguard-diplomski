//
//  VaultViewModel.swift
//  diplomski
//

import SwiftUI
import Combine
import Supabase

@MainActor
class VaultViewModel: ObservableObject {
    @Published var tickets: [SupabaseTicket] = []
    @Published var isLoading = true
    @Published var listingPrice: String = "0.00"
    @Published var selectedTicketForListing: SupabaseTicket?
    @Published var listingError: String?
    @Published var listingSuccess = false
    /// Progress text for the multi-step listing flow (build, authenticate, confirm).
    @Published var listingStatus: String?
    @Published var isListing = false
    /// Set when a listing succeeds; promoted to `listingSuccess` once the listing sheet
    /// has finished dismissing.
    var pendingListingSuccess = false

    func loadTickets() async {
        isLoading = true
        do {
            self.tickets = try await DatabaseService.shared.fetchMyTickets()
        } catch {
            Log.error("Failed to fetch tickets from Supabase: \(error)")
        }
        isLoading = false
    }
    
    /// Lists a ticket on the Auction House marketplace.
    ///
    /// The ticket is not transferred. The seller signs a transaction that records the
    /// asking price on-chain and approves the Auction House as delegate on their token
    /// account, so a buyer can complete the purchase later without the seller present.
    ///
    /// The on-chain step runs first. If it fails there is nothing to undo; if the
    /// database step fails afterwards, the ticket is delegated but not advertised,
    /// which unlisting resolves.
    func listOnMarketplace(ticket: SupabaseTicket, price: Double) async {
        guard let userId = try? await supabase.auth.session.user.id else {
            listingError = "You must be logged in."
            return
        }

        guard let pubKey = WalletViewModel.shared.publicKey, !pubKey.isEmpty else {
            listingError = ShyftMarketplaceError.walletUnavailable.localizedDescription
            return
        }

        guard MarketplaceConfig.isConfigured else {
            listingError = ShyftMarketplaceError.notConfigured.localizedDescription
            return
        }

        isListing = true
        listingError = nil
        defer { isListing = false; listingStatus = nil }

        do {
            // 1. Ask Shyft to assemble the listing transaction.
            listingStatus = "Preparing listing…"
            let listResult = try await ShyftMarketplaceService.shared.buildList(
                nftAddress: ticket.nftId,
                sellerWallet: pubKey,
                priceSOL: price
            )

            // 2. Sign it locally (Face ID) and wait for the cluster to confirm.
            listingStatus = "Confirm with Face ID…"
            let signature = try await WalletManager.shared.signAndBroadcast(
                encodedTransaction: listResult.encodedTransaction,
                userId: userId.uuidString,
                label: "list \(ticket.nftId.prefix(8))…"
            )
            Log.event("[Marketplace] Listed on chain. TX: \(signature)")

            // 3. Record it in the database, including the trade state address needed to
            //    cancel the listing later.
            listingStatus = "Publishing…"
            let listing = MarketplaceListing(
                id: UUID(),
                nftId: ticket.nftId,
                movieTitle: ticket.movieTitle,
                posterPath: ticket.posterPath,
                showtime: ticket.showtime,
                seat: ticket.seat,
                price: price,
                sellerId: userId,
                sellerPubKey: pubKey,
                createdAt: Date(),
                listState: listResult.listState
            )
            try await DatabaseService.shared.createListing(listing: listing)
            try await DatabaseService.shared.updateTicketListingStatus(nftId: ticket.nftId, isListed: true)

            if let index = tickets.firstIndex(where: { $0.nftId == ticket.nftId }) {
                tickets[index].isListedOnMarketplace = true
            }

            // The success alert is raised from the sheet's `onDismiss`: SwiftUI will not
            // present an alert while a sheet is still dismissing.
            pendingListingSuccess = true
            selectedTicketForListing = nil

        } catch {
            listingError = "Failed to list: \(error.localizedDescription)"
        }
    }
}
