//
//  WalletRecoveryView.swift
//  diplomski
//

import SwiftUI
import Combine
import Supabase

/// Wallet key management: shows whether this device can sign, and offers recovery when
/// it cannot.
///
/// The private key lives only in this device's Keychain; Supabase stores only the public
/// address. On a second device the balance and tickets therefore load normally, but
/// signing is impossible until the wallet is restored from its recovery phrase (or a new
/// wallet is created for this device).
///
/// This is the non-custodial trade-off: nobody else can take the user's tickets, and
/// nobody else can recover them either.
@MainActor
final class WalletRecoveryViewModel: ObservableObject {
    @Published var hasLocalKey = false
    @Published var publicKey: String?
    @Published var mnemonicToShow: [String]?
    @Published var importPhrase = ""
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var isWorking = false

    private var userId: String?

    func refresh() async {
        guard let id = try? await supabase.auth.session.user.id.uuidString else { return }
        userId = id
        publicKey = WalletViewModel.shared.publicKey
        hasLocalKey = WalletManager.shared.hasLocalKey(for: id)
    }

    /// Replaces this device's key with a brand-new wallet.
    ///
    /// Destructive: SOL and tickets held by the previous address become unreachable
    /// unless its recovery phrase was kept. The caller must confirm intent first.
    func createNewWallet() async {
        guard let userId else { return }
        isWorking = true
        errorMessage = nil
        successMessage = nil
        defer { isWorking = false }

        do {
            let wallet = try await WalletManager.shared.createWallet(for: userId)
            publicKey = wallet.publicKey
            hasLocalKey = true
            mnemonicToShow = wallet.mnemonic

            WalletViewModel.shared.adoptWallet(publicKey: wallet.publicKey, for: userId)
            await WalletViewModel.shared.syncWalletToProfile(userId: userId)
            await WalletViewModel.shared.fetchBalance()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importWallet() async {
        guard let userId else { return }
        let words = importPhrase
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)

        guard words.count == 12 || words.count == 24 else {
            errorMessage = "A recovery phrase is 12 or 24 words. This one has \(words.count)."
            return
        }

        isWorking = true
        errorMessage = nil
        successMessage = nil
        defer { isWorking = false }

        do {
            let pubKey = try await WalletManager.shared.importWallet(mnemonicWords: words, for: userId)
            publicKey = pubKey
            hasLocalKey = true
            importPhrase = ""
            successMessage = "Wallet restored. This device can sign again."

            WalletViewModel.shared.adoptWallet(publicKey: pubKey, for: userId)
            await WalletViewModel.shared.syncWalletToProfile(userId: userId)
            await WalletViewModel.shared.fetchBalance()
        } catch {
            errorMessage = "That phrase could not be used: \(error.localizedDescription)"
        }
    }
}

struct WalletRecoveryView: View {
    @StateObject private var viewModel = WalletRecoveryViewModel()
    @Environment(\.theme) var theme
    @State private var showingNewWalletConfirmation = false
    @State private var showingImport = false

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Layout.Spacing.lg) {
                    statusCard

                    if let mnemonic = viewModel.mnemonicToShow {
                        mnemonicCard(mnemonic)
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(theme.typography.bodyMedium)
                            .foregroundColor(theme.colors.error)
                    }
                    if let success = viewModel.successMessage {
                        Text(success)
                            .font(theme.typography.bodyMedium)
                            .foregroundColor(.green)
                    }

                    actions

                    Spacer(minLength: Layout.Spacing.lg)
                }
                .padding()
            }
        }
        .navigationTitle("Wallet")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.refresh() }
        .alert("Create a new wallet?", isPresented: $showingNewWalletConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Create new wallet", role: .destructive) {
                Task { await viewModel.createNewWallet() }
            }
        } message: {
            Text("This device will get a brand-new address. Any SOL or tickets held by your current address stay with it, and will only be reachable again if you have its recovery phrase. If you are trying to get back into an existing wallet, use Restore instead.")
        }
        .sheet(isPresented: $showingImport) {
            importSheet
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
            HStack(spacing: Layout.Spacing.sm) {
                Image(systemName: viewModel.hasLocalKey ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(viewModel.hasLocalKey ? .green : .orange)
                Text(viewModel.hasLocalKey ? "This device can sign" : "This device cannot sign")
                    .font(theme.typography.bodyLarge)
                    .bold()
                    .foregroundColor(theme.colors.onSurface)
            }

            Text(viewModel.hasLocalKey
                 ? "Your private key is stored in this device's Keychain and released only after Face ID."
                 : "Your address is known, but the private key that authorises transactions is not on this device — so the balance shown is real, while purchases and listings will fail. Restore from your recovery phrase, or create a new wallet for this device.")
                .font(theme.typography.bodyMedium)
                .foregroundColor(theme.colors.onSurfaceVariant)

            if let pubKey = viewModel.publicKey {
                Text(pubKey)
                    .font(theme.typography.monoSmall)
                    .foregroundColor(theme.colors.onSurfaceVariant)
                    .textSelection(.enabled)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(theme.colors.surface)
        .cornerRadius(Layout.Radius.xl)
    }

    private func mnemonicCard(_ words: [String]) -> some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
            Text("WRITE THIS DOWN NOW")
                .font(theme.typography.labelSmall)
                .foregroundColor(.orange)
            Text("These \(words.count) words are the only way to recover this wallet. They are not stored anywhere and will not be shown again — not by the app, and not by the cinema.")
                .font(theme.typography.bodyMedium)
                .foregroundColor(theme.colors.onSurfaceVariant)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), spacing: 8) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    HStack(spacing: 4) {
                        Text("\(index + 1).")
                            .font(theme.typography.labelSmall)
                            .foregroundColor(theme.colors.onSurfaceVariant)
                        Text(word)
                            .font(theme.typography.monoSmall)
                            .foregroundColor(theme.colors.onSurface)
                    }
                }
            }
            .padding(.vertical, 4)

            Button {
                viewModel.mnemonicToShow = nil
            } label: {
                Text("I have written it down")
                    .font(theme.typography.labelMedium)
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(theme.colors.primary)
                    .foregroundColor(.white)
                    .cornerRadius(Layout.Radius.md)
            }
        }
        .padding()
        .background(theme.colors.surfaceContainerHigh)
        .cornerRadius(Layout.Radius.xl)
    }

    private var actions: some View {
        VStack(spacing: Layout.Spacing.md) {
            Button {
                showingImport = true
            } label: {
                Label("Restore from recovery phrase", systemImage: "arrow.clockwise")
                    .font(theme.typography.bodyLarge)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(theme.colors.primary.opacity(0.15))
                    .foregroundColor(theme.colors.primary)
                    .cornerRadius(Layout.Radius.xl)
            }

            Button {
                showingNewWalletConfirmation = true
            } label: {
                Label("Create a new wallet", systemImage: "plus.circle")
                    .font(theme.typography.bodyLarge)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(theme.colors.error.opacity(0.15))
                    .foregroundColor(theme.colors.error)
                    .cornerRadius(Layout.Radius.xl)
            }
        }
        .disabled(viewModel.isWorking)
    }

    private var importSheet: some View {
        NavigationStack {
            ZStack {
                theme.colors.background.ignoresSafeArea()

                VStack(alignment: .leading, spacing: Layout.Spacing.lg) {
                    Text("Enter the 12 or 24 words in order, separated by spaces.")
                        .font(theme.typography.bodyMedium)
                        .foregroundColor(theme.colors.onSurfaceVariant)

                    TextEditor(text: $viewModel.importPhrase)
                        .font(theme.typography.monoBody)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(height: 140)
                        .background(theme.colors.surfaceContainerHigh)
                        .cornerRadius(Layout.Radius.md)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(theme.typography.bodyMedium)
                            .foregroundColor(theme.colors.error)
                    }

                    Button {
                        Task {
                            await viewModel.importWallet()
                            if viewModel.errorMessage == nil { showingImport = false }
                        }
                    } label: {
                        HStack {
                            if viewModel.isWorking {
                                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text("Restore wallet")
                        }
                        .font(theme.typography.bodyLarge)
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(theme.colors.primary)
                        .foregroundColor(.white)
                        .cornerRadius(Layout.Radius.xl)
                    }
                    .disabled(viewModel.isWorking)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Restore Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { showingImport = false }
                }
            }
        }
    }
}
