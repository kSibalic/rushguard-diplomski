//
//  ContentView.swift
//  diplomski
//
//  Created by Karlo Šibalić on 19.04.2026..
//

import SwiftUI
import Supabase

struct ContentView: View {
    @StateObject private var authViewModel = AuthViewModel()
    @ObservedObject private var walletViewModel = WalletViewModel.shared
    @Environment(\.theme) var theme

    var body: some View {
        content
            // Presented at the app shell rather than inside the sign-up screen, because
            // the wallet is created asynchronously after authentication succeeds — by
            // which point the login view is already gone.
            .fullScreenCover(item: $walletViewModel.pendingMnemonic) { mnemonic in
                MnemonicBackupView(
                    words: mnemonic.words,
                    publicKey: walletViewModel.publicKey
                ) {
                    walletViewModel.pendingMnemonic = nil
                }
            }
    }

    private var content: some View {
        Group {
            switch authViewModel.authState {
            case .loading:
                ZStack {
                    theme.colors.background.ignoresSafeArea()
                    VStack(spacing: Layout.Spacing.md) {
                        ProgressView()
                            .tint(theme.colors.primary)
                        Text("Loading...")
                            .font(theme.typography.bodyMedium)
                            .foregroundColor(theme.colors.onSurfaceVariant)
                    }
                }
                
            case .unauthenticated:
                LoginView(authViewModel: authViewModel)
                
            case .authenticated(let isAdmin):
                MainAppView(isAdmin: isAdmin, authViewModel: authViewModel)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authViewModel.authState)
    }
}

/// The main tabbed app shell shown after login.
struct MainAppView: View {
    let isAdmin: Bool
    @ObservedObject var authViewModel: AuthViewModel
    @State private var selectedTab: NavigationTab = .home
    @Environment(\.theme) var theme
    
    /// Admin: Home, Marketplace, Profile (no Vault)
    /// User: Home, Vault, Marketplace, Profile
    var visibleTabs: [NavigationTab] {
        if isAdmin {
            return [.home, .marketplace, .profile]
        } else {
            return NavigationTab.allCases
        }
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab Content. Each tab applies its own `.padding(.bottom, Layout.tabBarReservedHeight)`
            // so scrollable content clears the floating NavigationBarView below.
            Group {
                switch selectedTab {
                case .home:
                    if isAdmin {
                        NavigationStack {
                            AdminDashboardView()
                                .toolbar {
                                    ToolbarItem(placement: .topBarTrailing) {
                                        Button(action: {
                                            Task { await authViewModel.signOut() }
                                        }) {
                                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                                .foregroundColor(theme.colors.onSurfaceVariant)
                                        }
                                    }
                                }
                        }
                    } else {
                        HomeScreen()
                    }
                case .vault:
                    VaultView()
                case .marketplace:
                    MarketplaceView(isAdmin: isAdmin)
                case .profile:
                    ProfileView(authViewModel: authViewModel)
                }
            }
            
            NavigationBarView(selectedTab: $selectedTab, visibleTabs: visibleTabs)
        }
    }
}

/// Simple profile view with sign-out.
struct ProfileView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @ObservedObject var walletViewModel = WalletViewModel.shared
    @Environment(\.theme) var theme
    @State private var email: String?
    
    var body: some View {
        NavigationStack {
            profileContent
        }
    }

    private var profileContent: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: Layout.Spacing.lg) {
                Spacer()
                
                Image(systemName: "person.circle.fill")
                    .font(theme.typography.iconXLarge)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [theme.colors.primary, theme.colors.secondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                if let email {
                    Text(email)
                        .font(theme.typography.bodyLarge)
                        .foregroundColor(theme.colors.onSurface)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, Layout.Spacing.lg)
                }
                
                if !walletViewModel.isLoading {
                    Text(String(format: "%.2f SOL", walletViewModel.balance))
                        .font(theme.typography.displayLarge)
                        .foregroundColor(theme.colors.secondary)
                }
                
                if let pubKey = walletViewModel.publicKey {
                    Button(action: {
                        UIPasteboard.general.string = pubKey
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    }) {
                        HStack(spacing: 6) {
                            Text(pubKey.prefix(8) + "..." + pubKey.suffix(8))
                            Image(systemName: "square.on.square")
                                .font(theme.typography.iconSmall)
                        }
                        .font(theme.typography.labelSmall)
                        .foregroundColor(theme.colors.onSurfaceVariant)
                        .padding(.horizontal)
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()

                NavigationLink(destination: WalletRecoveryView()) {
                    HStack {
                        Image(systemName: "key.horizontal")
                        Text("Wallet")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(theme.typography.bodyLarge)
                    .foregroundColor(theme.colors.onSurface)
                    .padding()
                    .background(theme.colors.surface)
                    .cornerRadius(Layout.Radius.xl)
                }
                .padding(.horizontal, Layout.Spacing.lg)

                Button(action: {
                    Task { await authViewModel.signOut() }
                }) {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign Out")
                    }
                    .font(theme.typography.bodyLarge)
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(theme.colors.error.opacity(0.15))
                    .foregroundColor(theme.colors.error)
                    .cornerRadius(Layout.Radius.xl)
                }
                .padding(.horizontal, Layout.Spacing.lg)
                .padding(.bottom, Layout.tabBarReservedHeight + Layout.Spacing.lg)
            }
        }
        .task {
            email = try? await supabase.auth.session.user.email
        }
    }
}

#Preview {
    ContentView()
        .environment(\.theme, .dark)
}
