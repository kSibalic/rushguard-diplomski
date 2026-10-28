//
//  Typography.swift
//  diplomski
//
//  Created by Karlo Šibalić on 19.04.2026..
//

import SwiftUI

public struct Typography {
    // Custom text (SpaceGrotesk / Manrope)
    public let displayLarge: Font
    public let labelMedium: Font
    public let labelSmall: Font

    public let bodySmall: Font
    public let bodyMedium: Font
    public let bodyLarge: Font

    // System-font sizes for SF Symbol iconography
    public let iconSmall: Font
    public let iconTabBar: Font
    public let iconMedium: Font
    public let iconLarge: Font
    public let iconXLarge: Font
    public let iconHero: Font

    // Monospaced (on-chain identifiers)
    public let monoBody: Font
    public let monoSmall: Font

    // Badges and status headings
    public let badge: Font
    public let statusTitle: Font
}

public extension Typography {
    static let standard = Typography(
        displayLarge: .custom("SpaceGrotesk-Bold", size: 56, relativeTo: .largeTitle),
        labelMedium: .custom("SpaceGrotesk-Medium", size: 14, relativeTo: .subheadline),
        labelSmall: .custom("SpaceGrotesk-Medium", size: 12, relativeTo: .caption),
        bodySmall: .custom("Manrope-Regular", size: 12, relativeTo: .caption),
        bodyMedium: .custom("Manrope-Regular", size: 14, relativeTo: .body),
        bodyLarge: .custom("Manrope-Regular", size: 16, relativeTo: .body),

        iconSmall: .system(size: 12),
        iconTabBar: .system(size: 18, weight: .semibold),
        iconMedium: .system(size: 32),
        iconLarge: .system(size: 64),
        iconXLarge: .system(size: 80),
        iconHero: .system(size: 56, weight: .light),

        monoBody: .system(.caption, design: .monospaced),
        monoSmall: .system(.caption2, design: .monospaced),

        badge: .system(.caption2, design: .rounded, weight: .bold),
        statusTitle: .system(.title2, design: .rounded, weight: .bold)
    )
}
