//
//  SkeletonBlock.swift
//  diplomski
//

import SwiftUI

/// A rounded rectangle with a shimmering highlight sweeping left-to-right.
/// Compose several inside a layout-mirroring skeleton view while content loads.
struct SkeletonBlock: View {
    var cornerRadius: CGFloat = Layout.Radius.md

    @Environment(\.theme) var theme
    @State private var animate = false

    var body: some View {
        Rectangle()
            .fill(theme.colors.surfaceContainerHigh)
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            .clear,
                            theme.colors.surfaceContainerHighest,
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.5)
                    .offset(x: animate ? geo.size.width : -geo.size.width * 0.5)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
    }
}
