//
//  MnemonicBackupView.swift
//  diplomski
//

import SwiftUI

/// A recovery phrase awaiting presentation.
///
/// Identifiable so it can drive `fullScreenCover(item:)`.
struct MnemonicPresentation: Identifiable {
    let id = UUID()
    let words: [String]
}

/// The recovery phrase, laid out for copying onto paper.
///
/// Shared between sign-up and manual wallet creation so both present it identically.
struct MnemonicGrid: View {
    let words: [String]
    @Environment(\.theme) var theme

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3),
            spacing: 10
        ) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                HStack(spacing: 4) {
                    Text("\(index + 1).")
                        .font(theme.typography.labelSmall)
                        .foregroundColor(theme.colors.onSurfaceVariant)
                        .frame(width: 22, alignment: .trailing)
                    Text(word)
                        .font(theme.typography.monoSmall)
                        .foregroundColor(theme.colors.onSurface)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// Shown once, immediately after a wallet is created at sign-up.
///
/// Non-dismissable by design: the phrase is never shown again, and without it the
/// wallet cannot be recovered on any other device.
struct MnemonicBackupView: View {
    let words: [String]
    let publicKey: String?
    let onAcknowledged: () -> Void

    @Environment(\.theme) var theme
    @State private var hasConfirmed = false

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Layout.Spacing.lg) {
                    VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
                        Image(systemName: "key.horizontal.fill")
                            .font(theme.typography.iconLarge)
                            .foregroundColor(theme.colors.secondary)

                        Text("Your wallet is ready")
                            .font(theme.typography.displayLarge)
                            .foregroundColor(theme.colors.onSurface)

                        Text("A Solana wallet has been created for your tickets. Its private key is stored on this device and protected by Face ID.")
                            .font(theme.typography.bodyMedium)
                            .foregroundColor(theme.colors.onSurfaceVariant)
                    }

                    if let publicKey {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("YOUR ADDRESS")
                                .font(theme.typography.labelSmall)
                                .foregroundColor(theme.colors.onSurfaceVariant)
                            Text(publicKey)
                                .font(theme.typography.monoSmall)
                                .foregroundColor(theme.colors.onSurface)
                                .textSelection(.enabled)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.colors.surface)
                        .cornerRadius(Layout.Radius.xl)
                    }

                    VStack(alignment: .leading, spacing: Layout.Spacing.md) {
                        Label("WRITE THESE \(words.count) WORDS DOWN", systemImage: "exclamationmark.triangle.fill")
                            .font(theme.typography.labelSmall)
                            .foregroundColor(.orange)

                        Text("They are the only way to recover this wallet if you lose this device or sign in on another one. They are not stored anywhere — not on this phone, not by the cinema. Nobody can give them back to you.")
                            .font(theme.typography.bodyMedium)
                            .foregroundColor(theme.colors.onSurfaceVariant)

                        MnemonicGrid(words: words)
                            .padding(.vertical, Layout.Spacing.sm)

                        Toggle(isOn: $hasConfirmed) {
                            Text("I have written them down somewhere safe")
                                .font(theme.typography.bodyMedium)
                                .foregroundColor(theme.colors.onSurface)
                        }
                        .tint(theme.colors.primary)
                    }
                    .padding()
                    .background(theme.colors.surfaceContainerHigh)
                    .cornerRadius(Layout.Radius.xl)

                    Button(action: onAcknowledged) {
                        Text("Continue")
                            .font(theme.typography.bodyLarge)
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(hasConfirmed ? theme.colors.primary : theme.colors.outlineVariant)
                            .foregroundColor(.white)
                            .cornerRadius(Layout.Radius.xl)
                    }
                    .disabled(!hasConfirmed)

                    Text("You can review this wallet at any time in Profile → Wallet, but the phrase will not be shown again.")
                        .font(theme.typography.labelSmall)
                        .foregroundColor(theme.colors.onSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding()
            }
        }
        .interactiveDismissDisabled()
    }
}
