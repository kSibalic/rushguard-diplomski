//
//  HomeScreenSkeleton.swift
//  diplomski
//

import SwiftUI

/// Placeholder mirroring the HomeScreen layout (header, featured card, trending row) while catalog data loads.
struct HomeScreenSkeleton: View {
    @Environment(\.theme) var theme

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Layout.Spacing.lg) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: Layout.Spacing.xs) {
                        SkeletonBlock().frame(width: 120, height: 14)
                        SkeletonBlock().frame(width: 180, height: 22)
                    }
                    Spacer()
                    SkeletonBlock(cornerRadius: 20).frame(width: 40, height: 40)
                }

                // Featured card
                SkeletonBlock(cornerRadius: Layout.Radius.xxl)
                    .aspectRatio(0.7, contentMode: .fit)

                // Trending header
                HStack {
                    SkeletonBlock().frame(width: 140, height: 20)
                    Spacer()
                    SkeletonBlock().frame(width: 60, height: 14)
                }

                // Trending row
                HStack(spacing: Layout.Spacing.md) {
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 0) {
                            SkeletonBlock(cornerRadius: 0)
                                .frame(width: 160, height: 213)
                            VStack(alignment: .leading, spacing: Layout.Spacing.xs) {
                                SkeletonBlock().frame(width: 130, height: 16)
                                HStack {
                                    SkeletonBlock().frame(width: 50, height: 12)
                                    Spacer()
                                    SkeletonBlock().frame(width: 60, height: 12)
                                }
                            }
                            .padding(Layout.Spacing.sm)
                            .frame(width: 160)
                            .background(theme.colors.surfaceContainerLow)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Layout.Radius.xxl))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Layout.Spacing.md)
            .padding(.top, Layout.Spacing.md)
            .padding(.bottom, Layout.tabBarReservedHeight)
        }
    }
}
