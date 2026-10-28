//
//  ExplorerLink.swift
//  diplomski
//

import SwiftUI

/// Deep links into Solana Explorer, so ownership and transactions shown in the app can
/// be checked independently on the public ledger.
enum SolanaExplorer {
    /// Devnet. A production build would switch this with the RPC endpoint.
    static let cluster = "devnet"

    /// An account: a mint, a wallet, or the marketplace itself.
    static func address(_ address: String) -> URL? {
        URL(string: "https://explorer.solana.com/address/\(address)?cluster=\(cluster)")
    }

    /// A transaction signature.
    static func transaction(_ signature: String) -> URL? {
        URL(string: "https://explorer.solana.com/tx/\(signature)?cluster=\(cluster)")
    }
}

/// A labelled row that opens Solana Explorer, showing the truncated address it points at.
struct ExplorerLink: View {
    enum Target {
        case address(String)
        case transaction(String)

        var value: String {
            switch self {
            case .address(let value), .transaction(let value): return value
            }
        }

        var url: URL? {
            switch self {
            case .address(let value): return SolanaExplorer.address(value)
            case .transaction(let value): return SolanaExplorer.transaction(value)
            }
        }

        var defaultTitle: String {
            switch self {
            case .address: return "View on Solana Explorer"
            case .transaction: return "View transaction"
            }
        }
    }

    let target: Target
    var title: String?
    var showsValue: Bool = true

    @Environment(\.theme) var theme

    var body: some View {
        if let url = target.url {
            Link(destination: url) {
                HStack(spacing: Layout.Spacing.sm) {
                    Image(systemName: "link")
                        .font(theme.typography.iconSmall)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title ?? target.defaultTitle)
                            .font(theme.typography.labelMedium)
                        if showsValue {
                            Text(truncated(target.value))
                                .font(theme.typography.monoSmall)
                                .foregroundColor(theme.colors.onSurfaceVariant)
                        }
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right.square")
                        .font(theme.typography.iconSmall)
                }
                .foregroundColor(theme.colors.primary)
                .padding(.vertical, 10)
                .padding(.horizontal, Layout.Spacing.md)
                .frame(maxWidth: .infinity)
                .background(theme.colors.primary.opacity(0.12))
                .cornerRadius(Layout.Radius.md)
            }
        }
    }

    /// Base58 addresses are 32–44 characters; showing both ends keeps them recognisable.
    private func truncated(_ value: String) -> String {
        guard value.count > 20 else { return value }
        return value.prefix(8) + "…" + value.suffix(8)
    }
}
