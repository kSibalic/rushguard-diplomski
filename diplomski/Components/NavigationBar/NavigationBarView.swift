//
//  NavigationBarView.swift
//  diplomski
//
//  Created by Karlo Šibalić on 20.04.2026..
//

import SwiftUI

struct NavigationBarView: View {
    @Binding var selectedTab: NavigationTab
    var visibleTabs: [NavigationTab] = NavigationTab.allCases
    
    @Environment(\.theme) var theme
    
    var body: some View {
        HStack(spacing: Layout.Spacing.sm) {
            ForEach(visibleTabs, id: \.self) { tab in
                TabBarItem(tab: tab, selectedTab: $selectedTab)
            }
        }
        .padding(.horizontal, Layout.Spacing.sm)
        .padding(.vertical, Layout.Spacing.sm)
        .glassEffect(in: .capsule)
    }
}
    
#Preview {
    VStack(spacing: 16){
        NavigationBarView(selectedTab: .constant(.home))
            .environment(\.theme, .dark)
        
        NavigationBarView(selectedTab: .constant(.home))
            .environment(\.theme, .light)
    }
}
