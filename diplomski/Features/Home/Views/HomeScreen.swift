//
//  HomeScreen.swift
//  diplomski
//
//  Created by Karlo Šibalić on 22.04.2026..
//

import SwiftUI

struct HomeScreen: View {
    @StateObject private var viewModel = CatalogViewModel()
    
    @Environment(\.theme) var theme
    
    var body: some View {
        NavigationStack {
            ZStack {
                theme.colors.background
                    .ignoresSafeArea()
                
                if viewModel.isLoading {
                    HomeScreenSkeleton()
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: Layout.Spacing.lg) {
                            HeaderView()
                            
                            if let featured = viewModel.featuredMovie {
                                FeaturedMovieCard(movie: featured)
                            }
                            
                            TrendingMoviesSection(movies: viewModel.trendingMovies)
                        }
                        .padding(.horizontal, Layout.Spacing.md)
                        .padding(.top, Layout.Spacing.md)
                        .padding(.bottom, Layout.tabBarReservedHeight)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            if viewModel.featuredMovie == nil {
                await viewModel.loadMovies()
            }
        }
    }
}

#Preview {
    HomeScreen()
}
