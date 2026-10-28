//
//  Colors.swift
//  diplomski
//
//  Created by Karlo Šibalić on 19.04.2026..
//

import SwiftUI

public struct Colors {
    public let primary: Color
    public let primaryContainer: Color
    
    public let secondary: Color
    public let secondaryContainer: Color
    
    public let tertiary: Color
    
    public let background: Color
    public let surface: Color
    public let surfaceContainerLow: Color
    public let surfaceContainer: Color
    public let surfaceContainerHigh: Color
    public let surfaceContainerHighest: Color
    public let surfaceBright: Color
    public let surfaceLowest: Color
    
    public let error: Color
    
    public let onBackground: Color
    public let onSurface: Color
    public let onSurfaceVariant: Color
    public let onPrimary: Color
    public let onSecondary: Color
    
    public let outline: Color
    public let outlineVariant: Color
}

public extension Colors {
    static let dark = Colors(
        primary: Color(hex: "#C59AFF"),
        primaryContainer: Color(hex: "#BB88FF"),
        secondary: Color(hex: "#34FEA0"),
        secondaryContainer: Color(hex: "#006D40"),
        tertiary: Color(hex: "#B1FFCE"),
        background: Color(hex: "#0E0E0E"),
        surface: Color(hex: "#0E0E0E"),
        surfaceContainerLow: Color(hex: "#131313"),
        surfaceContainer: Color(hex: "#1A1919"),
        surfaceContainerHigh: Color(hex: "#201F1F"),
        surfaceContainerHighest: Color(hex: "#262626"),
        surfaceBright: Color(hex: "#2C2C2C"),
        surfaceLowest: Color(hex: "#000000"),
        error: Color(hex: "#FF6E84"),
        onBackground: Color(hex: "#FFFFFF"),
        onSurface: Color(hex: "#FFFFFF"),
        onSurfaceVariant: Color(hex: "#ADAAAA"),
        onPrimary: Color(hex: "#420081"),
        onSecondary: Color(hex: "#005C36"),
        outline: Color(hex: "#767575"),
        outlineVariant: Color(hex: "#484847")
    )
    
    static let light = Colors(
        primary: Color(hex: "#9742FD"),
        primaryContainer: Color(hex: "#9945FF"),
        secondary: Color(hex: "#0CEF93"),
        secondaryContainer: Color(hex: "#006D40"),
        tertiary: Color(hex: "#00EF99"),
        background: Color(hex: "#F5F5F5"),
        surface: Color(hex: "#FFFFFF"),
        surfaceContainerLow: Color(hex: "#F0F0F0"),
        surfaceContainer: Color(hex: "#E8E8E8"),
        surfaceContainerHigh: Color(hex: "#E0E0E0"),
        surfaceContainerHighest: Color(hex: "#D6D6D6"),
        surfaceBright: Color(hex: "#FFFFFF"),
        surfaceLowest: Color(hex: "#FFFFFF"),
        error: Color(hex: "#A70138"),
        onBackground: Color(hex: "#1A1A1A"),
        onSurface: Color(hex: "#1A1A1A"),
        onSurfaceVariant: Color(hex: "#5C5C5C"),
        onPrimary: Color(hex: "#FFFFFF"),
        onSecondary: Color(hex: "#FFFFFF"),
        outline: Color(hex: "#8F8E8E"),
        outlineVariant: Color(hex: "#D1D1D1")
    )
}
