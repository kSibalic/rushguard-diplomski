//
//  MovieDetailView.swift
//  diplomski
//

import SwiftUI

struct MovieDetailView: View {
    @StateObject private var viewModel: MovieDetailViewModel
    @Environment(\.theme) var theme
    
    init(movie: ActiveMovie) {
        _viewModel = StateObject(wrappedValue: MovieDetailViewModel(movie: movie))
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.Spacing.md) {
                // Header Image
                ZStack(alignment: .bottomLeading) {
                    AsyncImage(url: viewModel.movie.posterURL) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(theme.colors.surfaceContainerHigh)
                    }
                    .frame(height: 300)
                    .clipped()
                    
                    LinearGradient(colors: [.clear, theme.colors.background], startPoint: .top, endPoint: .bottom)
                    
                    Text(viewModel.movie.title)
                        .font(theme.typography.labelMedium)
                        .foregroundColor(theme.colors.onSurface)
                        .padding()
                }
                
                // Overview
                if let overview = viewModel.movie.overview {
                    Text("Overview")
                        .font(theme.typography.bodyLarge)
                        .foregroundColor(theme.colors.onSurface)
                        .padding(.horizontal)
                    
                    Text(overview)
                        .font(theme.typography.bodyMedium)
                        .foregroundColor(theme.colors.onSurfaceVariant)
                        .padding(.horizontal)
                }
                
                // Price
                if let price = viewModel.movie.ticketPriceSol {
                    HStack {
                        Text("Price:")
                            .font(theme.typography.labelMedium)
                            .foregroundColor(theme.colors.onSurface)
                        Text(String(format: "%.2f SOL", price))
                            .font(theme.typography.labelMedium)
                            .foregroundColor(theme.colors.secondary)
                    }
                    .padding(.horizontal)
                }
                
                // Showtimes
                Text("Select Showtime")
                    .font(theme.typography.labelMedium)
                    .foregroundColor(theme.colors.onSurface)
                    .padding(.horizontal)
                    .padding(.top)
                
                if viewModel.isLoading {
                    ProgressView()
                        .padding()
                } else if viewModel.showtimes.isEmpty {
                    Text("No showtimes available.")
                        .foregroundColor(theme.colors.onSurfaceVariant)
                        .padding(.horizontal)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Layout.Spacing.md) {
                            ForEach(viewModel.showtimes) { availability in
                                let showtime = availability.showtime
                                NavigationLink(destination: SeatSelectionView(movie: viewModel.movie, showtime: showtime)) {
                                    VStack(spacing: 6) {
                                        Text(showtime.theaterName)
                                            .font(theme.typography.labelSmall)
                                            .foregroundColor(theme.colors.primary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(theme.colors.primary.opacity(0.15))
                                            .cornerRadius(Layout.Radius.sm)
                                        
                                        Text(showtime.startTime, style: .date)
                                            .font(theme.typography.labelSmall)
                                        Text(showtime.startTime, style: .time)
                                            .font(theme.typography.bodyLarge)
                                            .bold()
                                        Text("\(availability.remainingSeats) seats left")
                                            .font(theme.typography.labelSmall)
                                            .foregroundColor(theme.colors.secondary)
                                    }
                                    .padding()
                                    .background(theme.colors.surfaceContainer)
                                    .cornerRadius(Layout.Radius.md)
                                    .foregroundColor(theme.colors.onSurface)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.bottom, Layout.tabBarReservedHeight)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.fetchShowtimes()
        }
    }
}
