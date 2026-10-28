//
//  TicketCardSkeleton.swift
//  diplomski
//

import SwiftUI

/// Placeholder that mirrors `NFTTicketCard` while ticket data is loading.
struct TicketCardSkeleton: View {
    @Environment(\.theme) var theme

    var body: some View {
        VStack(spacing: 0) {
            SkeletonBlock(cornerRadius: 0)
                .frame(height: 200)

            VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
                SkeletonBlock().frame(width: 220, height: 20)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonBlock().frame(width: 80, height: 12)
                        SkeletonBlock().frame(width: 120, height: 14)
                        SkeletonBlock().frame(width: 100, height: 14)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        SkeletonBlock().frame(width: 40, height: 12)
                        SkeletonBlock().frame(width: 60, height: 16)
                    }
                }
                .padding(.vertical, Layout.Spacing.xs)

                Divider().background(theme.colors.outlineVariant)

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        SkeletonBlock().frame(width: 60, height: 12)
                        SkeletonBlock().frame(width: 150, height: 12)
                    }
                    Spacer()
                    SkeletonBlock(cornerRadius: 4).frame(width: 60, height: 60)
                }

                SkeletonBlock()
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .padding(.top, Layout.Spacing.xs)
            }
            .padding()
            .background(theme.colors.surface)
        }
        .cornerRadius(Layout.Radius.xl)
        .shadow(color: theme.colors.surfaceLowest.opacity(0.5), radius: 10, y: 5)
    }
}
