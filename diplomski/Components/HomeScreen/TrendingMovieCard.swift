//
//  TrendingMovieCard.swift
//  diplomski
//
//  Created by Karlo Šibalić on 22.04.2026..
//

import SwiftUI

struct TrendingMovieCard: View {
    let movie: ActiveMovie
    @Environment(\.theme) var theme
    
    var priceText: String {
        if let price = movie.ticketPriceSol {
            return String(format: "%.2f SOL", price)
        }
        return "N/A SOL"
    }
    
    var body: some View {
        NavigationLink(destination: MovieDetailView(movie: movie)) {
            VStack(alignment: .leading, spacing: Layout.Radius.none) {
                // Poster
                AsyncImage(url: movie.posterURL) { image in
                    image
                        .resizable()
                        .aspectRatio(0.75, contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(theme.colors.surfaceContainerHighest)
                }
                .frame(width: 160, height: 213)
                .clipped()
                
                // Card Content
                VStack(alignment: .leading, spacing: Layout.Spacing.xs) {
                    Text(movie.title)
                        .font(theme.typography.labelMedium)
                        .foregroundColor(theme.colors.onSurface)
                        .lineLimit(1)
                    
                    HStack {
                        Text("Cinema")
                            .font(theme.typography.bodySmall)
                            .foregroundColor(theme.colors.onSurfaceVariant)
                        
                        Spacer()
                        
                        Text(priceText)
                            .font(theme.typography.labelSmall)
                            .foregroundColor(theme.colors.secondary)
                    }
                }
                .padding(Layout.Spacing.sm)
                .frame(width: 160)
                .background(theme.colors.surfaceContainerLow)
            }
            .clipShape(RoundedRectangle(cornerRadius: Layout.Radius.xxl))
            .overlay(
                RoundedRectangle(cornerRadius: Layout.Radius.xxl)
                    .stroke(theme.colors.outlineVariant, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
