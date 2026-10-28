//
//  TabBarItem.swift
//  diplomski
//
//  Created by Karlo Šibalić on 20.04.2026..
//

import SwiftUI

struct TabBarItem: View {
    let tab: NavigationTab
    @Binding var selectedTab: NavigationTab
    
    @Environment(\.theme) var theme
    @ObservedObject var walletViewModel = WalletViewModel.shared
    
    var isSelected: Bool {
        tab == selectedTab
    }
    
    var body: some View {
        HStack(spacing: Layout.Spacing.sm) {
            Image(systemName: tab.iconName)
                .font(theme.typography.iconTabBar)
                .foregroundColor(isSelected ? theme.colors.onSecondary : theme.colors.onSurfaceVariant)
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(isSelected ? theme.colors.secondary : theme.colors.surfaceContainerHigh)
                )
            
            if isSelected {
                if tab == .profile {
                    HStack(spacing: 4) {
                        Text(tab.rawValue)
                        if !walletViewModel.isLoading {
                            Text(String(format: "(%.2f SOL)", walletViewModel.balance))
                                .foregroundColor(theme.colors.secondary)
                        }
                    }
                    .font(theme.typography.bodyLarge)
                    .foregroundColor(theme.colors.onSurface)
                    .padding(.trailing, Layout.Spacing.md)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    Text(tab.rawValue)
                        .font(theme.typography.bodyLarge)
                        .foregroundColor(theme.colors.onSurface)
                        .padding(.trailing, Layout.Spacing.md)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .padding(isSelected ? 6 : 0)
        .background(
            Capsule()
                .fill(isSelected ? theme.colors.surfaceContainerHigh : Color.clear)
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0), value: selectedTab)
        .onTapGesture {
            selectedTab = tab
        }
    }
}
