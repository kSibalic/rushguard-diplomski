//
//  TrendingMoviesSection.swift
//  diplomski
//
//  Created by Karlo Šibalić on 22.04.2026..
//

import SwiftUI
import Combine

struct TrendingMoviesSection: View {
    let movies: [ActiveMovie]
    @Environment(\.theme) var theme
    @State private var showAllMovies = false
    
    var body: some View {
        VStack(spacing: Layout.Spacing.md) {
            // Section Header
            HStack {
                Text("Trending Now")
                    .font(theme.typography.bodyLarge)
                    .foregroundColor(theme.colors.onSurface)
                
                Spacer()
                
                Button("SEE ALL") {
                    showAllMovies = true
                }
                .font(theme.typography.bodySmall)
                .foregroundColor(theme.colors.primaryContainer)
            }
            
            // Horizontal Scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Layout.Spacing.md) {
                    ForEach(movies) { movie in
                        TrendingMovieCard(movie: movie)
                    }
                }
            }
        }
        .sheet(isPresented: $showAllMovies) {
            AllMoviesView(movies: movies)
        }
    }
}

/// Full grid view of all active movies
struct AllMoviesView: View {
    let movies: [ActiveMovie]
    @Environment(\.theme) var theme
    @Environment(\.dismiss) var dismiss
    
    let columns = [
        GridItem(.flexible(), spacing: Layout.Spacing.md),
        GridItem(.flexible(), spacing: Layout.Spacing.md)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                theme.colors.background.ignoresSafeArea()
                
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Layout.Spacing.md) {
                        ForEach(movies) { movie in
                            NavigationLink(destination: MovieDetailView(movie: movie)) {
                                VStack(alignment: .leading, spacing: 0) {
                                    AsyncImage(url: movie.posterURL) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Rectangle().fill(theme.colors.surfaceContainerHigh)
                                    }
                                    .frame(height: 220)
                                    .clipped()
                                    
                                    VStack(alignment: .leading, spacing: Layout.Spacing.xs) {
                                        Text(movie.title)
                                            .font(theme.typography.labelMedium)
                                            .foregroundColor(theme.colors.onSurface)
                                            .lineLimit(1)
                                        
                                        if let price = movie.ticketPriceSol {
                                            Text(String(format: "%.2f SOL", price))
                                                .font(theme.typography.labelSmall)
                                                .foregroundColor(theme.colors.secondary)
                                        }
                                    }
                                    .padding(Layout.Spacing.sm)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(theme.colors.surfaceContainerLow)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: Layout.Radius.xl))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Layout.Radius.xl)
                                        .stroke(theme.colors.outlineVariant, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("All Movies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundColor(theme.colors.primary)
                }
            }
        }
    }
}
