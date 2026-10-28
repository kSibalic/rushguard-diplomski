//
//  MarketplaceViewModel.swift
//  diplomski
//

import SwiftUI
import Combine
import Supabase

enum MarketplaceError: LocalizedError {
    case ownListing
    case listingUnavailable
    case insufficientFunds(needed: Double, available: Double)
    case legacyListing

    var errorDescription: String? {
        switch self {
        case .ownListing:
            return "This is your own listing. Unlist it instead if you want the ticket back."
        case .listingUnavailable:
            return "This listing is no longer available — it was just sold, unlisted, or the showtime has passed."
        case .insufficientFunds(let needed, let available):
            return String(
                format: "Not enough SOL. This ticket costs %.3f SOL and your balance is %.3f SOL.",
                needed, available
            )
        case .legacyListing:
            return "This listing predates on-chain resale and cannot be bought — buying it would transfer the ticket in the database only, without moving the NFT. The seller needs to unlist and list it again."
        }
    }
}

@MainActor
class MarketplaceViewModel: ObservableObject {
    /// Headroom left for the network fee when checking the buyer's balance.
    /// A Devnet transfer costs ~5000 lamports per signature; 0.001 SOL is a
    /// comfortable margin that still rejects an obviously empty wallet.
    private static let feeMarginLamports: UInt64 = 1_000_000

    @Published var listings: [MarketplaceListing] = []
    @Published var isLoading = true
    @Published var isProcessingPurchase = false
    @Published var errorMessage: String?
    @Published var purchaseSuccess = false
    @Published var currentUserId: String?
    /// Progress text for the multi-step purchase (build, authenticate, broadcast,
    /// confirm), which takes several seconds.
    @Published var purchaseStatus: String?
    /// Which listing is being bought, so only that row shows progress.
    @Published var processingListingId: UUID?
    
    let isAdmin: Bool
    
    init(isAdmin: Bool = false) {
        self.isAdmin = isAdmin
    }
    
    func loadListings() async {
        isLoading = true
        do {
            if let user = try? await supabase.auth.session.user {
                self.currentUserId = user.id.uuidString
            }
            let allListings = try await DatabaseService.shared.fetchListings()

            let now = Date()
            var active: [MarketplaceListing] = []
            var expired: [MarketplaceListing] = []
            for listing in allListings {
                if listing.showtime >= now {
                    active.append(listing)
                } else {
                    expired.append(listing)
                }
            }

            // Show only active listings — never block the UI on cleanup.
            self.listings = active

            // Fire-and-forget cleanup of the caller's own expired listings. Row Level
            // Security only lets a client delete listings it owns; removing everyone's
            // expired rows would belong in a scheduled server-side job.
            let ownExpired = expired.filter { $0.sellerId.uuidString == self.currentUserId }
            if !ownExpired.isEmpty {
                Task.detached(priority: .background) {
                    for listing in ownExpired {
                        try? await DatabaseService.shared.deleteListing(id: listing.id)
                        try? await DatabaseService.shared.updateTicketListingStatus(
                            nftId: listing.nftId,
                            isListed: false
                        )
                    }
                }
            }
        } catch {
            self.errorMessage = "Failed to load listings: \(error.localizedDescription)"
        }
        self.isLoading = false
    }
    
    /// Buys a listed ticket through the Auction House.
    ///
    /// Payment and delivery are a single transaction: the Auction House `executeSale`
    /// instruction moves the NFT from seller to buyer and the SOL from buyer to seller,
    /// taking the cinema's fee, atomically. The buyer can never pay without receiving
    /// the ticket. The seller is not involved; they authorised the transfer when listing.
    func buyTicket(listing: MarketplaceListing) async {
        isProcessingPurchase = true
        processingListingId = listing.id
        errorMessage = nil
        defer {
            isProcessingPurchase = false
            processingListingId = nil
            purchaseStatus = nil
        }

        do {
            guard let userId = try? await supabase.auth.session.user.id else {
                throw URLError(.userAuthenticationRequired)
            }
            guard let buyerPubKey = WalletViewModel.shared.publicKey, !buyerPubKey.isEmpty else {
                throw ShyftMarketplaceError.walletUnavailable
            }
            guard MarketplaceConfig.isConfigured else {
                throw ShyftMarketplaceError.notConfigured
            }

            // Pre-checks. The on-chain transaction is atomic, but rejecting obvious
            // failures here spares the buyer a fee and a biometric prompt.

            // 1. You cannot buy your own listing.
            guard listing.sellerId != userId else {
                throw MarketplaceError.ownListing
            }

            // 2. A listing without a trade state has no on-chain backing: "buying" it
            //    would change a database row without moving the NFT, so it is refused.
            guard listing.isOnChain else {
                throw MarketplaceError.legacyListing
            }

            // 3. The listing must still be live and the seller must still hold the
            //    ticket. Checked server-side, where the authoritative state lives.
            guard try await DatabaseService.shared.listingIsPurchasable(listingId: listing.id) else {
                throw MarketplaceError.listingUnavailable
            }

            // 4. Enough SOL for the price plus a margin for network fees, so
            //    insufficient funds are reported clearly rather than as an RPC error.
            let amountLamports = UInt64(listing.price * 1_000_000_000)
            await WalletViewModel.shared.fetchBalance()
            let balanceLamports = UInt64(WalletViewModel.shared.balance * 1_000_000_000)
            guard balanceLamports >= amountLamports + Self.feeMarginLamports else {
                throw MarketplaceError.insufficientFunds(
                    needed: listing.price,
                    available: WalletViewModel.shared.balance
                )
            }

            // 5. Build the purchase. Only the buyer signs.
            purchaseStatus = "Preparing purchase…"
            let buyResult = try await ShyftMarketplaceService.shared.buildBuy(
                nftAddress: listing.nftId,
                sellerAddress: listing.sellerPubKey,
                buyerWallet: buyerPubKey,
                priceSOL: listing.price
            )

            // 6. Sign and settle. When this returns, the buyer owns the ticket on-chain.
            purchaseStatus = "Confirm with Face ID…"
            let signature = try await WalletManager.shared.signAndBroadcast(
                encodedTransaction: buyResult.encodedTransaction,
                userId: userId.uuidString,
                label: "buy \(listing.nftId.prefix(8))…"
            )
            Log.event("[Marketplace] Sale settled on chain. TX: \(signature)")

            // 7. Update the database to match the chain. If this fails the buyer still
            //    owns the ticket on-chain, and verification reads the chain, so the
            //    ticket remains valid; only the database index is out of date.
            purchaseStatus = "Updating your tickets…"
            _ = try await DatabaseService.shared.buyMarketplaceTicket(
                listingId: listing.id,
                txSignature: signature
            )

            // 8. Reflect the result locally.
            self.listings.removeAll { $0.id == listing.id }
            await WalletViewModel.shared.fetchBalance()

            purchaseSuccess = true
        } catch {
            self.errorMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }

    /// Cancels a listing, revoking the Auction House's delegation over the ticket.
    ///
    /// The delegation is revoked on-chain first; removing only the database row would
    /// leave the ticket purchasable on-chain.
    func unlistTicket(listing: MarketplaceListing) async {
        do {
            guard let userId = try? await supabase.auth.session.user.id else {
                throw URLError(.userAuthenticationRequired)
            }

            // 1. Revoke on-chain, if there is a trade state. Rows without one only need
            //    the database cleaned up.
            if listing.isOnChain, let listState = listing.listState {
                guard let pubKey = WalletViewModel.shared.publicKey, !pubKey.isEmpty else {
                    throw ShyftMarketplaceError.walletUnavailable
                }
                let unlistResult = try await ShyftMarketplaceService.shared.buildUnlist(
                    listState: listState,
                    sellerWallet: pubKey
                )
                let signature = try await WalletManager.shared.signAndBroadcast(
                    encodedTransaction: unlistResult.encodedTransaction,
                    userId: userId.uuidString,
                    label: "unlist \(listing.nftId.prefix(8))…"
                )
                Log.debug("[Marketplace] Listing cancelled on chain. TX: \(signature)")
            }

            // 2. Then remove the advertisement.
            try await DatabaseService.shared.deleteListing(id: listing.id)
            try await DatabaseService.shared.updateTicketListingStatus(nftId: listing.nftId, isListed: false)

            self.listings.removeAll { $0.id == listing.id }
        } catch {
            self.errorMessage = "Failed to unlist: \(error.localizedDescription)"
        }
    }
    
    func adminDeleteListing(_ listing: MarketplaceListing) async {
        do {
            try await DatabaseService.shared.adminDeleteListing(id: listing.id)
            self.listings.removeAll { $0.id == listing.id }
        } catch {
            self.errorMessage = "Failed to delete: \(error.localizedDescription)"
        }
    }
}
