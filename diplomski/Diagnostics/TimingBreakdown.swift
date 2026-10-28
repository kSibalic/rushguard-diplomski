//
//  TimingBreakdown.swift
//  diplomski
//

import SwiftUI

/// Shows where the time in an operation went, grouped by what was being waited on:
/// the Solana cluster, the device (biometrics and local signing), or external HTTP
/// services.
struct TimingBreakdown: View {
    let rows: [(phase: String, duration: Double)]
    let total: TimeInterval

    @Environment(\.theme) var theme

    /// What a stage was waiting on.
    enum Category {
        case solana      // Broadcasting to, and confirming on, the cluster
        case device      // Face ID, Keychain, local Ed25519 signing
        case service     // Pinata, Shyft, Supabase

        var color: Color {
            switch self {
            case .solana: return .green
            case .device: return .blue
            case .service: return .orange
            }
        }

        var label: String {
            switch self {
            case .solana: return "Solana"
            case .device: return "Uređaj"
            case .service: return "Vanjski servisi"
            }
        }
    }

    private func category(for phase: String) -> Category {
        switch phase {
        case "blockhash", "slanje", "potvrda": return .solana
        case "faceid", "potpis": return .device
        default: return .service          // ipfs, shyft, baza
        }
    }

    private func humanName(for phase: String) -> String {
        switch phase {
        case "blockhash": return "Dohvat blockhasha"
        case "faceid": return "Face ID + Keychain"
        case "potpis": return "Lokalno potpisivanje"
        case "slanje": return "Slanje na mrežu"
        case "potvrda": return "Potvrda na blockchainu"
        case "ipfs": return "Pinata / IPFS"
        case "shyft": return "Shyft (izrada tx)"
        case "baza": return "Supabase zapis"
        default: return phase
        }
    }

    private var categoryTotals: [(Category, Double)] {
        var solana = 0.0, device = 0.0, service = 0.0
        for row in rows {
            switch category(for: row.phase) {
            case .solana: solana += row.duration
            case .device: device += row.duration
            case .service: service += row.duration
            }
        }
        return [(.solana, solana), (.device, device), (.service, service)]
    }

    /// Sum of the measured phases. Slightly less than `total`, because the wall clock
    /// also covers work between marks. Percentages use this so they add to 100.
    private var measured: Double {
        max(rows.reduce(0) { $0 + $1.duration }, 0.001)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.md) {
            HStack {
                Text("VRIJEME")
                    .font(theme.typography.labelSmall)
                    .foregroundColor(theme.colors.onSurfaceVariant)
                Spacer()
                Text(String(format: "%.2f s", total))
                    .font(theme.typography.labelMedium)
                    .bold()
                    .foregroundColor(theme.colors.onSurface)
            }

            // Proportional bar: the green segment is the blockchain's actual share.
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(rows, id: \.phase) { row in
                        Rectangle()
                            .fill(category(for: row.phase).color)
                            .frame(width: max(geometry.size.width * (row.duration / measured), 1))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 10)

            // Category summary — the headline numbers.
            HStack(spacing: Layout.Spacing.md) {
                ForEach(categoryTotals, id: \.0.label) { category, seconds in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(category.color)
                            .frame(width: 8, height: 8)
                        Text("\(category.label) \(String(format: "%.1f s", seconds))")
                            .font(theme.typography.labelSmall)
                            .foregroundColor(theme.colors.onSurfaceVariant)
                    }
                }
            }

            Divider()

            // Per-stage detail.
            VStack(spacing: 6) {
                ForEach(rows, id: \.phase) { row in
                    HStack {
                        Circle()
                            .fill(category(for: row.phase).color)
                            .frame(width: 6, height: 6)
                        Text(humanName(for: row.phase))
                            .font(theme.typography.labelSmall)
                            .foregroundColor(theme.colors.onSurface)
                        Spacer()
                        Text("\(Int((row.duration / measured) * 100))%")
                            .font(theme.typography.labelSmall)
                            .foregroundColor(theme.colors.onSurfaceVariant)
                        Text(String(format: "%.2f s", row.duration))
                            .font(theme.typography.monoSmall)
                            .foregroundColor(theme.colors.onSurface)
                            .frame(width: 60, alignment: .trailing)
                    }
                }
            }

            // Prints mean, standard deviation, min and max per stage across all
            // purchases recorded in this session.
            Button {
                PhaseStats.shared.summary()
            } label: {
                Label("Ispiši mjerenja u konzolu", systemImage: "tablecells")
                    .font(theme.typography.labelSmall)
                    .foregroundColor(theme.colors.primary)
            }
            .padding(.top, 4)
        }
        .padding()
        .background(theme.colors.surface)
        .cornerRadius(Layout.Radius.xl)
    }
}
