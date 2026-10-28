//
//  FeaturedMovieCard.swift
//  diplomski
//
//  Created by Karlo Šibalić on 22.04.2026..
//

import SwiftUI

struct FeaturedMovieCard: View {
    let movie: ActiveMovie
    @Environment(\.theme) var theme
    @State private var detail: MovieDetail?
    
    private var runtimeText: String? {
        guard let runtime = detail?.runtime, runtime > 0 else { return nil }
        return "\(runtime) min"
    }
    
    private var ratingText: String? {
        guard let rating = detail?.voteAverage, rating > 0 else { return nil }
        return String(format: "%.1f/10", rating)
    }
    
    private var primaryGenre: String? {
        detail?.genres?.first?.name
    }
    
    private var hasAnyMetadata: Bool {
        runtimeText != nil || ratingText != nil || primaryGenre != nil
    }
    
    var body: some View {
        NavigationLink(destination: MovieDetailView(movie: movie)) {
            ZStack(alignment: .bottom) {
                // Poster Image
                AsyncImage(url: movie.posterURL) { image in
                    image
                        .resizable()
                        .aspectRatio(0.7, contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(theme.colors.surfaceContainerHigh)
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Layout.Radius.xxl))
                .overlay(
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, theme.colors.surfaceLowest.opacity(0.8), theme.colors.surfaceLowest]),
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Layout.Radius.xxl))
                )
                
                // Content Overlay
                VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
                    // Badge
                    Badge(
                        text: "● PREMIERE",
                        style: .tag(
                            foreground: theme.colors.secondary,
                            background: theme.colors.secondaryContainer.opacity(0.6)
                        )
                    )
                    
                    // Title
                    Text(movie.title)
                        .font(theme.typography.displayLarge)
                        .minimumScaleFactor(0.4)
                        .lineLimit(2)
                        .foregroundColor(theme.colors.onSurface)
                    
                    // Info Row — only rendered when at least one real value is available.
                    if hasAnyMetadata {
                        HStack(spacing: Layout.Spacing.md) {
                            if let runtimeText {
                                HStack(spacing: Layout.Spacing.xs) {
                                    Image(systemName: "clock")
                                    Text(runtimeText)
                                }
                            }
                            if let ratingText {
                                HStack(spacing: Layout.Spacing.xs) {
                                    Image(systemName: "star.fill")
                                    Text(ratingText)
                                }
                            }
                            if let primaryGenre {
                                Text(primaryGenre)
                                    .padding(.horizontal, Layout.Spacing.sm)
                                    .padding(.vertical, Layout.Spacing.xs)
                                    .background(theme.colors.surfaceContainerHighest)
                                    .clipShape(RoundedRectangle(cornerRadius: Layout.Radius.md))
                            }
                        }
                        .font(theme.typography.bodySmall)
                        .foregroundColor(theme.colors.onSurfaceVariant)
                    }
                    
                    // Real Synopsis
                    if let overview = movie.overview {
                        Text(overview)
                            .font(theme.typography.bodyMedium)
                            .foregroundColor(theme.colors.onSurfaceVariant)
                            .lineLimit(2)
                            .padding(.top, Layout.Spacing.xs)
                    }
                    
                    Divider()
                        .background(theme.colors.outlineVariant)
                        .padding(.vertical, Layout.Spacing.sm)
                    
                    // Price & Action Row
                    HStack {
                        VStack(alignment: .leading, spacing: Layout.Spacing.xs) {
                            Text("TICKET PRICE")
                                .font(theme.typography.labelSmall)
                                .foregroundColor(theme.colors.onSurfaceVariant)
                            
                            let priceText = movie.ticketPriceSol != nil ? String(format: "%.2f SOL", movie.ticketPriceSol!) : "N/A SOL"
                            Text(priceText)
                                .font(theme.typography.bodyLarge)
                                .foregroundColor(theme.colors.secondary)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: Layout.Spacing.sm) {
                            Text("Buy Ticket")
                                .font(theme.typography.labelMedium)
                            Image(systemName: "ticket.fill")
                        }
                        .padding(.horizontal, Layout.Spacing.md)
                        .padding(.vertical, Layout.Spacing.sm)
                        .background(theme.colors.primary)
                        .foregroundColor(theme.colors.onPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: Layout.Radius.xl))
                    }
                }
                .padding(Layout.Spacing.md)
            }
            .shadow(color: theme.colors.surfaceLowest.opacity(0.5), radius: Layout.Shadows.ambientRadius, y: Layout.Shadows.ambientY)
        }
        .buttonStyle(.plain)
        .task(id: movie.id) {
            detail = try? await TMDBAdminClient.shared.fetchMovieDetails(movieID: movie.id)
        }
    }
}
