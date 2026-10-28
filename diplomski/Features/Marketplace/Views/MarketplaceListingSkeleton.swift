//
//  MarketplaceListingSkeleton.swift
//  diplomski
//

import SwiftUI

/// Placeholder that mirrors `MarketplaceListingCard` while listings are loading.
struct MarketplaceListingSkeleton: View {
    @Environment(\.theme) var theme

    var body: some View {
        HStack(spacing: Layout.Spacing.md) {
            SkeletonBlock().frame(width: 80, height: 120)

            VStack(alignment: .leading, spacing: Layout.Spacing.xs) {
                SkeletonBlock().frame(width: 180, height: 20)
                SkeletonBlock().frame(width: 140, height: 14)
                SkeletonBlock().frame(width: 120, height: 14)
                SkeletonBlock().frame(width: 90, height: 14)
                SkeletonBlock().frame(width: 100, height: 18)
                Spacer()
                SkeletonBlock().frame(width: 140, height: 34)
            }
            .frame(height: 120, alignment: .topLeading)
        }
        .padding(Layout.Spacing.md)
        .background(theme.colors.surface)
        .cornerRadius(Layout.Radius.xl)
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }
}
