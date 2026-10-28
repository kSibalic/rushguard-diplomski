//
//  MarketplaceView.swift
//  diplomski
//

import SwiftUI

struct MarketplaceView: View {
    let isAdmin: Bool
    @StateObject private var viewModel: MarketplaceViewModel
    @Environment(\.theme) var theme
    
    init(isAdmin: Bool = false) {
        self.isAdmin = isAdmin
        _viewModel = StateObject(wrappedValue: MarketplaceViewModel(isAdmin: isAdmin))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                theme.colors.background.ignoresSafeArea()
                
                if viewModel.isLoading {
                    ScrollView {
                        VStack(spacing: Layout.Spacing.md) {
                            ForEach(0..<3, id: \.self) { _ in
                                MarketplaceListingSkeleton()
                            }
                        }
                        .padding()
                        .padding(.bottom, Layout.tabBarReservedHeight)
                    }
                    .disabled(true)
                } else if viewModel.listings.isEmpty {
                    VStack(spacing: Layout.Spacing.md) {
                        Image(systemName: "cart")
                            .font(theme.typography.iconLarge)
                            .foregroundColor(theme.colors.onSurfaceVariant)
                        Text("No Listings")
                            .font(theme.typography.bodyLarge)
                            .foregroundColor(theme.colors.onSurface)
                        Text("When users list their tickets for resale, they will appear here.")
                            .font(theme.typography.bodyMedium)
                            .foregroundColor(theme.colors.onSurfaceVariant)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Layout.Spacing.xl)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: Layout.Spacing.md) {
                            ForEach(viewModel.listings) { listing in
                                MarketplaceListingCard(
                                    listing: listing,
                                    isAdmin: isAdmin,
                                    viewModel: viewModel
                                )
                            }
                        }
                        .padding()
                        .padding(.bottom, Layout.tabBarReservedHeight)
                    }
                }
            }
            .navigationTitle("P2P Marketplace")
            .task {
                await viewModel.loadListings()
            }
            .alert("Purchased!", isPresented: $viewModel.purchaseSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Ticket added to your Vault. Check your tickets!")
            }
            .alert(isPresented: .constant(viewModel.errorMessage != nil)) {
                Alert(
                    title: Text("Error"),
                    message: Text(viewModel.errorMessage ?? ""),
                    dismissButton: .default(Text("OK")) { viewModel.errorMessage = nil }
                )
            }
        }
    }
}

struct MarketplaceListingCard: View {
    let listing: MarketplaceListing
    let isAdmin: Bool
    @ObservedObject var viewModel: MarketplaceViewModel
    @Environment(\.theme) var theme
    
    var body: some View {
        HStack(spacing: Layout.Spacing.md) {
            // Movie Poster
            AsyncImage(url: listing.posterURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Rectangle().fill(theme.colors.surfaceContainerHigh)
                    Image(systemName: "film")
                        .foregroundColor(theme.colors.onSurfaceVariant)
                }
            }
            .frame(width: 80, height: 120)
            .cornerRadius(Layout.Radius.md)
            
            // Details
            VStack(alignment: .leading, spacing: Layout.Spacing.xs) {
                Text(listing.movieTitle)
                    .font(theme.typography.bodyLarge)
                    .foregroundColor(theme.colors.onSurface)
                    .bold()
                    .lineLimit(1)
                
                HStack(spacing: Layout.Spacing.xs) {
                    Image(systemName: "calendar")
                    Text(listing.showtime, style: .date)
                }
                .font(theme.typography.labelSmall)
                .foregroundColor(theme.colors.onSurfaceVariant)
                
                HStack(spacing: Layout.Spacing.xs) {
                    Image(systemName: "clock")
                    Text(listing.showtime, style: .time)
                }
                .font(theme.typography.labelSmall)
                .foregroundColor(theme.colors.onSurfaceVariant)
                
                Text("Seat \(listing.seat)")
                    .font(theme.typography.labelSmall)
                    .foregroundColor(theme.colors.onSurfaceVariant)
                
                Text(String(format: "%.2f SOL", listing.price))
                    .font(theme.typography.bodyLarge)
                    .foregroundColor(theme.colors.secondary)
                    .bold()
                
                if isAdmin {
                    Divider().padding(.vertical, 4)
                    Text("Seller: \(listing.sellerPubKey.prefix(8))...")
                        .font(theme.typography.labelSmall)
                        .foregroundColor(theme.colors.onSurfaceVariant)
                    
                    Text("Listed: \(listing.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown")")
                        .font(theme.typography.labelSmall)
                        .foregroundColor(theme.colors.onSurfaceVariant)
                }
                
                Spacer()
                
                // Action Button
                if isAdmin {
                    Button(action: {
                        Task {
                            await viewModel.adminDeleteListing(listing)
                        }
                    }) {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Remove (Admin)")
                        }
                        .font(theme.typography.labelMedium)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(theme.colors.error.opacity(0.15))
                        .foregroundColor(theme.colors.error)
                        .cornerRadius(Layout.Radius.sm)
                    }
                } else if viewModel.currentUserId == listing.sellerId.uuidString {
                    Button(action: {
                        Task {
                            await viewModel.unlistTicket(listing: listing)
                        }
                    }) {
                        HStack {
                            Image(systemName: "arrow.uturn.backward")
                            Text("Unlist")
                        }
                        .font(theme.typography.labelMedium)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(theme.colors.secondary.opacity(0.15))
                        .foregroundColor(theme.colors.secondary)
                        .cornerRadius(Layout.Radius.sm)
                    }
                } else {
                    Button(action: {
                        Task {
                            await viewModel.buyTicket(listing: listing)
                        }
                    }) {
                        HStack {
                            // Only the row actually being purchased shows progress.
                            if viewModel.processingListingId == listing.id {
                                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                                // Settling on-chain takes seconds; show the current step.
                                Text(viewModel.purchaseStatus ?? "Working…")
                            } else {
                                Image(systemName: "cart.badge.plus")
                                Text("Buy Ticket")
                            }
                        }
                        .font(theme.typography.labelMedium)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(theme.colors.primary)
                        .foregroundColor(.white)
                        .cornerRadius(Layout.Radius.sm)
                    }
                    .disabled(viewModel.isProcessingPurchase)
                }
            }
        }
        .padding(Layout.Spacing.md)
        .background(theme.colors.surface)
        .cornerRadius(Layout.Radius.xl)
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }
}
