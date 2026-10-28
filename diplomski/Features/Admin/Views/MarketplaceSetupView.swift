//
//  MarketplaceSetupView.swift
//  diplomski
//

import SwiftUI
import Combine
import Supabase

/// One-time setup for the cinema's on-chain marketplace.
///
/// Creating an Auction House is a single transaction whose only required signer is the
/// payer. The signed-in administrator's in-app wallet pays and signs; the cinema
/// treasury is set as both authority and fee recipient, so the marketplace belongs to
/// the cinema rather than to the administrator who created it.
///
/// The marketplace address is a PDA of `(authority, currency)`, so setup is idempotent:
/// `find` reports an existing marketplace rather than creating a duplicate.
@MainActor
final class MarketplaceSetupViewModel: ObservableObject {
    enum State: Equatable {
        case checking
        case notCreated
        case creating(String)
        case created(address: String, treasury: String?, fee: Double?)
        case failed(String)
    }

    @Published var state: State = .checking

    /// Whether the address reported by the chain matches what is compiled into the app.
    var isWiredUp: Bool {
        guard case .created(let address, _, _) = state else { return false }
        return address == MarketplaceConfig.auctionHouseAddress
    }

    func check() async {
        state = .checking
        do {
            if let existing = try await ShyftMarketplaceService.shared.findMarketplace() {
                state = .created(
                    address: existing.address,
                    treasury: existing.treasuryAddress,
                    fee: existing.transactionFee
                )
            } else {
                state = .notCreated
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func create() async {
        guard let userId = try? await supabase.auth.session.user.id else {
            state = .failed("You must be signed in.")
            return
        }
        guard let pubKey = WalletViewModel.shared.publicKey, !pubKey.isEmpty else {
            state = .failed(ShyftMarketplaceError.walletUnavailable.localizedDescription)
            return
        }

        do {
            state = .creating("Building the marketplace transaction…")
            // This wallet only pays and signs; the cinema treasury becomes the owner.
            let info = try await ShyftMarketplaceService.shared.buildCreateMarketplace(payer: pubKey)

            guard let encoded = info.encodedTransaction else {
                throw ShyftMarketplaceError.unexpectedResponse
            }

            state = .creating("Confirm with Face ID…")
            let signature = try await WalletManager.shared.signAndBroadcast(
                encodedTransaction: encoded,
                userId: userId.uuidString,
                label: "create marketplace"
            )
            Log.event("[Marketplace] Auction House created. TX: \(signature)")

            state = .created(
                address: info.address,
                treasury: info.treasuryAddress,
                fee: info.transactionFee
            )
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct MarketplaceSetupView: View {
    @StateObject private var viewModel = MarketplaceSetupViewModel()
    @Environment(\.theme) var theme

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Layout.Spacing.lg) {
                    explanation

                    switch viewModel.state {
                    case .checking:
                        HStack(spacing: Layout.Spacing.sm) {
                            ProgressView()
                            Text("Checking for an existing marketplace…")
                                .font(theme.typography.bodyMedium)
                                .foregroundColor(theme.colors.onSurfaceVariant)
                        }

                    case .notCreated:
                        notCreatedSection

                    case .creating(let status):
                        HStack(spacing: Layout.Spacing.sm) {
                            ProgressView()
                            Text(status)
                                .font(theme.typography.bodyMedium)
                                .foregroundColor(theme.colors.onSurface)
                        }

                    case .created(let address, let treasury, let fee):
                        createdSection(address: address, treasury: treasury, fee: fee)

                    case .failed(let message):
                        VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
                            Text(message)
                                .font(theme.typography.bodyMedium)
                                .foregroundColor(theme.colors.error)
                            Button("Try again") {
                                Task { await viewModel.check() }
                            }
                            .font(theme.typography.labelMedium)
                        }
                    }

                    Spacer(minLength: Layout.Spacing.lg)
                }
                .padding()
            }
        }
        .navigationTitle("Marketplace Setup")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.check() }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
            Text("On-chain marketplace")
                .font(theme.typography.bodyLarge)
                .bold()
                .foregroundColor(theme.colors.onSurface)
            Text("Resale runs through a Metaplex Auction House. Sellers keep their ticket in their own wallet and grant the marketplace permission to move it only if someone pays the asking price. This has to be created once, and costs a small amount of SOL from your wallet.")
                .font(theme.typography.bodyMedium)
                .foregroundColor(theme.colors.onSurfaceVariant)
        }
        .padding()
        .background(theme.colors.surface)
        .cornerRadius(Layout.Radius.xl)
    }

    private var notCreatedSection: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text("The marketplace account has not been created yet.")
                    .font(theme.typography.bodyMedium)
                    .foregroundColor(theme.colors.onSurface)
                Text("Your wallet pays the rent and signs. Ownership goes to the cinema treasury, not to you — so this stays valid after you no longer have an account.")
                    .font(theme.typography.bodyMedium)
                    .foregroundColor(theme.colors.onSurfaceVariant)
            }

            Button {
                Task { await viewModel.create() }
            } label: {
                Text("Create marketplace")
                    .font(theme.typography.bodyLarge)
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(theme.colors.primary)
                    .foregroundColor(.white)
                    .cornerRadius(Layout.Radius.xl)
            }
        }
    }

    private func createdSection(address: String, treasury: String?, fee: Double?) -> some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.md) {
            HStack(spacing: Layout.Spacing.sm) {
                Image(systemName: viewModel.isWiredUp ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(viewModel.isWiredUp ? .green : .orange)
                Text(viewModel.isWiredUp ? "Marketplace live and wired up" : "Marketplace exists — not yet wired up")
                    .font(theme.typography.bodyLarge)
                    .bold()
                    .foregroundColor(theme.colors.onSurface)
            }

            VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
                labelled("Marketplace address", address)
                if let treasury { labelled("Treasury", treasury) }
                if let fee { labelled("Cinema fee", "\(Int(fee))% of every resale, taken on-chain") }
            }
            .padding()
            .background(theme.colors.surface)
            .cornerRadius(Layout.Radius.xl)

            if !viewModel.isWiredUp {
                VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
                    Text("Address mismatch")
                        .font(theme.typography.labelSmall)
                        .foregroundColor(theme.colors.onSurfaceVariant)
                    Text("The marketplace on chain is at a different address than the one compiled into the app. That should not happen — the address is derived from the treasury wallet, so this means the treasury constant has changed since the marketplace was created. Update MarketplaceConfig.auctionHouseAddress to the address above and rebuild.")
                        .font(theme.typography.bodyMedium)
                        .foregroundColor(theme.colors.onSurfaceVariant)

                    Button {
                        UIPasteboard.general.string = address
                    } label: {
                        Label("Copy address", systemImage: "doc.on.doc")
                            .font(theme.typography.labelMedium)
                    }
                }
                .padding()
                .background(theme.colors.surfaceContainerHigh)
                .cornerRadius(Layout.Radius.xl)
            }
        }
    }

    private func labelled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(theme.typography.labelSmall)
                .foregroundColor(theme.colors.onSurfaceVariant)
            Text(value)
                .font(theme.typography.monoSmall)
                .foregroundColor(theme.colors.onSurface)
                .textSelection(.enabled)
        }
    }
}
