//
//  Theme.swift
//  diplomski
//
//  Created by Karlo Šibalić on 19.04.2026..
//

import SwiftUI

public struct Theme {
    public let colors: Colors
    public let typography: Typography
}

public extension Theme {
    static let light = Theme(
        colors: .light,
        typography: .standard,
    )
    
    static let dark = Theme(
        colors: .dark,
        typography: .standard,
    )
}

private struct ThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: Theme = .dark
}

public extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeEnvironmentKey.self] }
        set { self[ThemeEnvironmentKey.self] = newValue }
    }
}

public struct ThemeModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    
    public func body(content: Content) -> some View {
        content.environment(\.theme, colorScheme == .dark ? .dark : .light)
    }
}

public extension View {
    func withRushguardTheme() -> some View {
        self.modifier(ThemeModifier())
    }
}
