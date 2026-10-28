//
//  Layout.swift
//  diplomski
//
//  Created by Karlo Šibalić on 19.04.2026..
//

import SwiftUI

public enum Layout {
    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 24
        public static let xl: CGFloat = 32
        public static let xxl: CGFloat = 40
    }
    
    public enum Radius {
        public static let none: CGFloat = 0
        public static let sm: CGFloat = 2
        public static let md: CGFloat = 6
        public static let xl: CGFloat = 12
        public static let xxl: CGFloat = 16
        public static let round: CGFloat = 9999
    }
    
    public enum Shadows {
        public static let ambientRadius: CGFloat = 40
        public static let ambientY: CGFloat = 0
    }
    
    /// Vertical space reserved at the bottom of every tab for the floating `NavigationBarView`.
    /// Apply as `.padding(.bottom, Layout.tabBarReservedHeight)` on the scroll content of
    /// each tab so it clears the floating bar.
    public static let tabBarReservedHeight: CGFloat = 100
}
