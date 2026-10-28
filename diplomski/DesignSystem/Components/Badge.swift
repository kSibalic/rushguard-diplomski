//
//  Badge.swift
//  diplomski
//

import SwiftUI

/// Compact pill for status callouts and category labels.
///
/// - `.status(Color)` — solid colored pill for overlays like USED / EXPIRED / ON SALE.
/// - `.tag(foreground:background:)` — themed pill for inline category tags.
struct Badge: View {
    enum Style {
        case status(Color)
        case tag(foreground: Color, background: Color)
    }

    let text: String
    let style: Style

    @Environment(\.theme) var theme

    var body: some View {
        Text(text)
            .font(font)
            .foregroundColor(foreground)
            .padding(.horizontal, Layout.Spacing.sm)
            .padding(.vertical, Layout.Spacing.xs)
            .background(background)
            .clipShape(Capsule())
    }

    private var font: Font {
        switch style {
        case .status: return theme.typography.badge
        case .tag: return theme.typography.labelSmall
        }
    }

    private var foreground: Color {
        switch style {
        case .status: return .white
        case .tag(let fg, _): return fg
        }
    }

    private var background: Color {
        switch style {
        case .status(let color): return color.opacity(0.85)
        case .tag(_, let bg): return bg
        }
    }
}
