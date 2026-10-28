//
//  VaultView.swift
//  diplomski
//

import SwiftUI

struct VaultView: View {
    @StateObject private var viewModel = VaultViewModel()
    @Environment(\.theme) var theme
    @State private var selectedTicketForQR: SupabaseTicket?
    @State private var showExpired = false
    
    /// Tickets filtered based on the expired toggle.
    private var filteredTickets: [SupabaseTicket] {
        if showExpired {
            return viewModel.tickets
        } else {
            return viewModel.tickets.filter { !$0.isExpired && !$0.isUsed }
        }
    }
    
    /// Count of hidden expired/used tickets for the badge.
    private var hiddenCount: Int {
        viewModel.tickets.count - viewModel.tickets.filter { !$0.isExpired && !$0.isUsed }.count
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                theme.colors.background.ignoresSafeArea()
                
                if viewModel.isLoading {
                    ScrollView {
                        VStack(spacing: Layout.Spacing.lg) {
                            ForEach(0..<3, id: \.self) { _ in
                                TicketCardSkeleton()
                            }
                        }
                        .padding()
                        .padding(.bottom, Layout.tabBarReservedHeight)
                    }
                    .disabled(true)
                } else if filteredTickets.isEmpty {
                    VStack(spacing: Layout.Spacing.md) {
                        Image(systemName: "ticket")
                            .font(theme.typography.iconLarge)
                            .foregroundColor(theme.colors.onSurfaceVariant)
                        Text(showExpired ? "No Tickets" : "No Active Tickets")
                            .font(theme.typography.bodyLarge)
                            .foregroundColor(theme.colors.onSurface)
                        Text(showExpired
                             ? "Purchase a movie ticket and it will appear here as an NFT."
                             : "All your tickets are expired or used. Toggle \"Show Expired\" to see them.")
                            .font(theme.typography.bodyMedium)
                            .foregroundColor(theme.colors.onSurfaceVariant)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        if !showExpired && hiddenCount > 0 {
                            Button(action: { showExpired = true }) {
                                Text("Show \(hiddenCount) expired ticket\(hiddenCount == 1 ? "" : "s")")
                                    .font(theme.typography.labelMedium)
                                    .foregroundColor(theme.colors.primary)
                            }
                        }
                    }
                } else {
                    ScrollView {
                        VStack(spacing: Layout.Spacing.lg) {
                            ForEach(filteredTickets, id: \.nftId) { ticket in
                                NFTTicketCard(ticket: ticket, viewModel: viewModel, selectedTicketForQR: $selectedTicketForQR)
                            }
                        }
                        .padding()
                        .padding(.bottom, Layout.tabBarReservedHeight)
                    }
                }
            }
            .navigationTitle("My Tickets")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showExpired.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: showExpired ? "eye.slash" : "eye")
                            if hiddenCount > 0 {
                                Text("\(hiddenCount)")
                                    .font(theme.typography.badge)
                            }
                        }
                        .foregroundColor(theme.colors.onSurfaceVariant)
                    }
                }
            }
            .task {
                await viewModel.loadTickets()
            }
            .sheet(item: $viewModel.selectedTicketForListing, onDismiss: {
                if viewModel.pendingListingSuccess {
                    viewModel.pendingListingSuccess = false
                    viewModel.listingSuccess = true
                }
            }) { ticket in
                ListTicketSheet(viewModel: viewModel, ticket: ticket)
            }
            .sheet(item: $selectedTicketForQR) { ticket in
                TicketQRSheet(ticket: ticket)
            }
            .alert("Listed!", isPresented: $viewModel.listingSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your ticket is now on the P2P Marketplace.")
            }
        }
    }
}


struct NFTTicketCard: View {
    let ticket: SupabaseTicket
    @ObservedObject var viewModel: VaultViewModel
    @Binding var selectedTicketForQR: SupabaseTicket?
    @Environment(\.theme) var theme
    
    var body: some View {
        VStack(spacing: 0) {
            // Movie Poster with status overlay
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: ticket.posterURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(theme.colors.surfaceContainerHigh)
                }
                .frame(height: 200)
                .contentShape(Rectangle())
                .clipped()
                
                // Status overlay for non-usable tickets
                if ticket.isUsed {
                    Badge(text: "USED", style: .status(.gray))
                        .padding(8)
                } else if ticket.isExpired {
                    Badge(text: "EXPIRED", style: .status(.orange))
                        .padding(8)
                } else if ticket.isListedOnMarketplace {
                    Badge(text: "ON SALE", style: .status(.blue))
                        .padding(8)
                }
            }
            
            // Ticket Details
            VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
                HStack {
                    Text(ticket.movieTitle)
                        .font(theme.typography.bodyLarge)
                        .foregroundColor(ticket.isUsable ? theme.colors.onSurface : theme.colors.onSurfaceVariant)
                        .bold()
                    Spacer()
                    if ticket.isUsed {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.gray)
                    } else if ticket.isExpired {
                        Image(systemName: "clock.badge.xmark")
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.blue)
                    }
                }
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("DATE & TIME")
                            .font(theme.typography.labelSmall)
                            .foregroundColor(theme.colors.onSurfaceVariant)
                        Text(ticket.showtime, style: .date)
                            .font(theme.typography.bodyMedium)
                            .foregroundColor(theme.colors.onSurface)
                        Text(ticket.showtime, style: .time)
                            .font(theme.typography.bodyMedium)
                            .foregroundColor(theme.colors.onSurface)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("SEAT")
                            .font(theme.typography.labelSmall)
                            .foregroundColor(theme.colors.onSurfaceVariant)
                        Text("\(ticket.seat)")
                            .font(theme.typography.labelMedium)
                            .foregroundColor(theme.colors.secondary)
                    }
                }
                .padding(.vertical, Layout.Spacing.xs)
                
                Divider().background(theme.colors.outlineVariant)
                
                // QR Code area — only tappable if ticket is usable
                if ticket.isUsable {
                    Button(action: {
                        selectedTicketForQR = ticket
                    }) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("NFT ID")
                                    .font(theme.typography.labelSmall)
                                    .foregroundColor(theme.colors.onSurfaceVariant)
                                Text(ticket.nftId)
                                    .font(theme.typography.labelSmall)
                                    .foregroundColor(theme.colors.onSurfaceVariant)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            
                            Spacer()

                            // No QR preview in the list: a pass must be signed, which
                            // needs Face ID, and a static code would be copyable.
                            ZStack {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(theme.colors.surfaceContainerHigh)
                                    .frame(width: 60, height: 60)
                                Image(systemName: "qrcode")
                                    .font(theme.typography.iconMedium)
                                    .foregroundColor(theme.colors.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    // Non-usable: show NFT ID without QR and without tap action
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NFT ID")
                                .font(theme.typography.labelSmall)
                                .foregroundColor(theme.colors.onSurfaceVariant)
                            Text(ticket.nftId)
                                .font(theme.typography.labelSmall)
                                .foregroundColor(theme.colors.onSurfaceVariant)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        
                        Spacer()
                        
                        // Greyed-out placeholder instead of QR
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(theme.colors.surfaceContainerHigh)
                                .frame(width: 60, height: 60)
                            Image(systemName: "qrcode")
                                .foregroundColor(theme.colors.outlineVariant)
                        }
                    }
                }
                
                // Bottom action area
                if ticket.isUsed {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.gray)
                        Text("Ticket Redeemed")
                            .font(theme.typography.labelMedium)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, Layout.Spacing.xs)
                } else if ticket.isExpired {
                    HStack {
                        Image(systemName: "clock.badge.xmark")
                            .foregroundColor(.orange)
                        Text("Expired")
                            .font(theme.typography.labelMedium)
                            .foregroundColor(.orange)
                    }
                    .padding(.top, Layout.Spacing.xs)
                } else if ticket.isListedOnMarketplace {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(theme.colors.secondary)
                        Text("Listed on Marketplace")
                            .font(theme.typography.labelMedium)
                            .foregroundColor(theme.colors.secondary)
                    }
                    .padding(.top, Layout.Spacing.xs)
                } else {
                    Button(action: {
                        viewModel.selectedTicketForListing = ticket
                        viewModel.listingPrice = "0.50"
                    }) {
                        HStack {
                            Image(systemName: "tag.fill")
                            Text("List on Marketplace")
                        }
                        .font(theme.typography.labelMedium)
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(theme.colors.secondary.opacity(0.15))
                        .foregroundColor(theme.colors.secondary)
                        .cornerRadius(Layout.Radius.md)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, Layout.Spacing.xs)
                }
            }
            .padding()
            .background(theme.colors.surface)
        }
        .opacity(ticket.isUsable ? 1.0 : 0.75)
        .cornerRadius(Layout.Radius.xl)
        .shadow(color: theme.colors.surfaceLowest.opacity(0.5), radius: 10, y: 5)
    }
}

// MARK: - Listing Sheet

struct ListTicketSheet: View {
    @ObservedObject var viewModel: VaultViewModel
    let ticket: SupabaseTicket
    @Environment(\.dismiss) var dismiss
    @Environment(\.theme) var theme
    
    var body: some View {
        NavigationStack {
            VStack(spacing: Layout.Spacing.lg) {
                Text(ticket.movieTitle)
                    .font(theme.typography.bodyLarge)
                    .bold()
                    .foregroundColor(theme.colors.onSurface)
                
                Text("Seat \(ticket.seat) • \(ticket.showtime.formatted(date: .abbreviated, time: .shortened))")
                    .font(theme.typography.bodyMedium)
                    .foregroundColor(theme.colors.onSurfaceVariant)
                
                Divider()
                
                HStack {
                    Text("Listing Price (SOL)")
                        .foregroundColor(theme.colors.onSurface)
                    Spacer()
                    TextField("0.50", text: $viewModel.listingPrice)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .foregroundColor(theme.colors.secondary)
                }
                .padding()
                .background(theme.colors.surfaceContainerHigh)
                .cornerRadius(Layout.Radius.md)
                
                if let error = viewModel.listingError {
                    Text(error)
                        .font(theme.typography.bodySmall)
                        .foregroundColor(theme.colors.error)
                }
                
                Spacer()
                
                Button(action: {
                    guard let price = Double(viewModel.listingPrice), price > 0 else {
                        viewModel.listingError = "Enter a valid price."
                        return
                    }
                    Task {
                        await viewModel.listOnMarketplace(ticket: ticket, price: price)
                    }
                }) {
                    HStack(spacing: Layout.Spacing.sm) {
                        if viewModel.isListing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            Text(viewModel.listingStatus ?? "Working…")
                        } else {
                            Text("Confirm Listing")
                        }
                    }
                    .font(theme.typography.bodyLarge)
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(theme.colors.primary)
                    .foregroundColor(.white)
                    .cornerRadius(Layout.Radius.xl)
                }
                .disabled(viewModel.isListing)
            }
            .padding()
            .navigationTitle("List Ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        viewModel.selectedTicketForListing = nil
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Full-Screen Pass Sheet

/// Displays a live, signed, rotating entry pass.
///
/// The code is a signed assertion, valid for `TicketPass.validityWindow` seconds, that
/// the holder of this phone controls the wallet owning the NFT. A screenshot expires
/// before it can be reused.
struct TicketQRSheet: View {
    let ticket: SupabaseTicket
    @Environment(\.dismiss) var dismiss
    @Environment(\.theme) var theme
    @StateObject private var viewModel: TicketPassViewModel

    init(ticket: SupabaseTicket) {
        self.ticket = ticket
        _viewModel = StateObject(wrappedValue: TicketPassViewModel(mint: ticket.nftId))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.colors.background.ignoresSafeArea()

                VStack(spacing: Layout.Spacing.lg) {
                    Text(ticket.movieTitle)
                        .font(theme.typography.labelMedium)
                        .foregroundColor(theme.colors.onSurface)

                    Text("\(Showtime.seatLabel(for: ticket.seat)) • \(ticket.showtime.formatted(date: .abbreviated, time: .shortened))")
                        .font(theme.typography.bodyMedium)
                        .foregroundColor(theme.colors.onSurfaceVariant)

                    passArea

                    Spacer()

                    // Lets anyone confirm the ticket on the public ledger.
                    ExplorerLink(target: .address(ticket.nftId))
                        .padding(.horizontal)
                }
                .padding(.top, Layout.Spacing.lg)
                .padding(.bottom, Layout.Spacing.lg)
            }
            .navigationTitle("Your Ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await viewModel.start() }
            .onDisappear { viewModel.stop() }
        }
    }

    @ViewBuilder
    private var passArea: some View {
        if viewModel.isUnlocking {
            VStack(spacing: Layout.Spacing.md) {
                ProgressView().scaleEffect(1.4)
                Text("Authenticate to sign your pass")
                    .font(theme.typography.bodyMedium)
                    .foregroundColor(theme.colors.onSurfaceVariant)
            }
            .frame(height: 282)
        } else if let error = viewModel.errorMessage {
            VStack(spacing: Layout.Spacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(theme.typography.iconLarge)
                    .foregroundColor(.orange)
                Text("Pass unavailable")
                    .font(theme.typography.bodyLarge)
                    .foregroundColor(theme.colors.onSurface)
                Text(error)
                    .font(theme.typography.bodyMedium)
                    .foregroundColor(theme.colors.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(height: 282)
        } else if let code = viewModel.code {
            VStack(spacing: Layout.Spacing.md) {
                QRCodeView(payload: code)
                    .frame(width: 250, height: 250)
                    .padding(16)
                    .background(Color.white)
                    .cornerRadius(Layout.Radius.xl)
                    .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
                    .id(viewModel.rotationCount)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.rotationCount)

                countdown

                Text("Show this to cinema staff. It refreshes every \(Int(TicketPass.validityWindow)) seconds — a screenshot will not work.")
                    .font(theme.typography.bodyMedium)
                    .foregroundColor(theme.colors.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }

    private var countdown: some View {
        HStack(spacing: Layout.Spacing.sm) {
            Image(systemName: "lock.rotation")
                .foregroundColor(theme.colors.secondary)

            ProgressView(
                value: Double(viewModel.secondsRemaining),
                total: TicketPass.validityWindow
            )
            .tint(viewModel.secondsRemaining <= 5 ? .orange : theme.colors.secondary)
            .frame(width: 120)

            Text("\(viewModel.secondsRemaining)s")
                .font(theme.typography.monoBody)
                .foregroundColor(theme.colors.onSurfaceVariant)
                .monospacedDigit()
        }
    }
}
