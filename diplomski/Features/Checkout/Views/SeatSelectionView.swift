//
//  SeatSelectionView.swift
//  diplomski
//

import SwiftUI

struct SeatSelectionView: View {
    let movie: ActiveMovie
    let showtime: Showtime
    @Environment(\.theme) var theme
    
    @State private var selectedSeats: Set<Int> = []
    @State private var takenSeats: Set<Int> = []
    @State private var showCheckout = false
    @State private var totalCapacity: Int = 60
    
    @Environment(\.dismiss) private var dismiss
    
    // Locked column count so the displayed row/seat labels always match the visual grid.
    let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: Showtime.seatsPerRow)
    
    var body: some View {
        VStack(spacing: Layout.Spacing.lg) {
            // Screen Curve
            ZStack(alignment: .top) {
                GeometryReader { geometry in
                    Path { path in
                        let width = geometry.size.width
                        path.move(to: CGPoint(x: 0, y: 50))
                        path.addQuadCurve(to: CGPoint(x: width, y: 50),
                                          control: CGPoint(x: width / 2, y: 0))
                    }
                    .stroke(theme.colors.primary, lineWidth: 3)
                    .shadow(color: theme.colors.primary, radius: 10, y: 5)
                }
                
                Text("SCREEN")
                    .font(theme.typography.labelMedium)
                    .foregroundColor(theme.colors.onSurfaceVariant)
                    .padding(.top, 60)
            }
            .frame(height: 100)
            .padding(.horizontal)
            
            // Seats Grid
            ScrollView {
                LazyVGrid(columns: columns, spacing: 15) {
                    // Use the actual total capacity from the showtime database entry
                    ForEach(1...totalCapacity, id: \.self) { seatNumber in
                        let isTaken = takenSeats.contains(seatNumber)
                        let isSelected = selectedSeats.contains(seatNumber)
                        
                        Button(action: {
                            if selectedSeats.contains(seatNumber) {
                                selectedSeats.remove(seatNumber)
                            } else {
                                selectedSeats.insert(seatNumber)
                            }
                        }) {
                            ZStack {
                                Image("seat")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundColor(
                                        isTaken ? theme.colors.outlineVariant :
                                        isSelected ? theme.colors.primary : theme.colors.surfaceContainerHighest
                                    )
                                    .frame(height: 35)
                                
                                Text("\(seatNumber)")
                                    .font(theme.typography.labelSmall)
                                    .foregroundColor(
                                        isTaken ? theme.colors.outline :
                                        isSelected ? .white : theme.colors.onSurfaceVariant
                                    )
                                    .offset(y: -2)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isTaken)
                    }
                }
                .padding()
            }
            
            Spacer()
            
            // Checkout Summary
            VStack(spacing: Layout.Spacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Selected Seats:")
                            .font(theme.typography.bodyMedium)
                            .foregroundColor(theme.colors.onSurfaceVariant)
                        if selectedSeats.isEmpty {
                            Text("None")
                                .font(theme.typography.labelMedium)
                                .foregroundColor(theme.colors.onSurface)
                        } else {
                            // Sort and display the seats with correct 1-indexed row/seat math
                            let sortedSeats = Array(selectedSeats).sorted()
                            let seatDescriptions = sortedSeats.map { Showtime.seatLabel(for: $0) }
                            
                            // For UI neatness, if more than 2, show a summarized version or list them
                            if seatDescriptions.count <= 2 {
                                ForEach(seatDescriptions, id: \.self) { desc in
                                    Text(desc)
                                        .font(theme.typography.labelMedium)
                                        .foregroundColor(theme.colors.onSurface)
                                }
                            } else {
                                Text("\(seatDescriptions.count) seats selected")
                                    .font(theme.typography.labelMedium)
                                    .foregroundColor(theme.colors.onSurface)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Total:")
                            .font(theme.typography.bodyMedium)
                            .foregroundColor(theme.colors.onSurfaceVariant)
                        if let price = movie.ticketPriceSol {
                            let total = price * Double(selectedSeats.count)
                            Text(String(format: "%.2f SOL", total))
                                .font(theme.typography.bodyLarge)
                                .foregroundColor(theme.colors.secondary)
                                .bold()
                        }
                    }
                }
                
                Button(action: {
                    showCheckout = true
                }) {
                    Text("Proceed to Web3 Checkout")
                        .font(theme.typography.bodyLarge)
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(!selectedSeats.isEmpty ? theme.colors.primary : theme.colors.surfaceContainerHigh)
                        .foregroundColor(!selectedSeats.isEmpty ? .white : theme.colors.onSurfaceVariant)
                        .cornerRadius(Layout.Radius.xl)
                }
                .disabled(selectedSeats.isEmpty)
            }
            .padding()
            .background(theme.colors.surface)
            .cornerRadius(Layout.Radius.xl, corners: [.topLeft, .topRight])
            .shadow(color: .black.opacity(0.1), radius: 10, y: -5)
        }
        .padding(.bottom, Layout.tabBarReservedHeight)
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle("Select Seats")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // The raw `available_seats` DB column is the max capacity for the showtime;
            // remaining seats are derived live from the `tickets` table below.
            totalCapacity = showtime.availableSeats > 0 ? showtime.availableSeats : 60
            
            do {
                let taken = try await DatabaseService.shared.fetchTakenSeats(movieTitle: movie.title, showtime: showtime.startTime)
                self.takenSeats = Set(taken)
            } catch {
                Log.error("Failed to fetch taken seats: \(error)")
            }
        }
        .sheet(isPresented: $showCheckout) {
            if !selectedSeats.isEmpty {
                CheckoutSheet(viewModel: CheckoutViewModel(movie: movie, showtime: showtime, seatNumbers: Array(selectedSeats))) {
                    dismiss()
                }
            }
        }
    }
}

struct CheckoutSheet: View {
    @StateObject var viewModel: CheckoutViewModel
    var onComplete: () -> Void
    @Environment(\.dismiss) var dismiss
    @Environment(\.theme) var theme
    
    var body: some View {
        NavigationStack {
            VStack(spacing: Layout.Spacing.lg) {
                if viewModel.transactionSuccess {
                    ScrollView {
                        VStack(spacing: Layout.Spacing.md) {
                            Image(systemName: viewModel.isPartialPurchase
                                  ? "exclamationmark.triangle.fill"
                                  : "checkmark.seal.fill")
                                .font(theme.typography.iconLarge)
                                .foregroundColor(viewModel.isPartialPurchase ? .orange : .green)

                            Text(viewModel.isPartialPurchase
                                 ? "\(viewModel.mintedNFTIds.count) of \(viewModel.seatNumbers.count) tickets minted"
                                 : "\(viewModel.mintedNFTIds.count) Ticket(s) Minted Successfully!")
                                .font(theme.typography.labelMedium)

                            if viewModel.isPartialPurchase {
                                // Partial purchase: state exactly which seats failed
                                // and how much is owed.
                                VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
                                    Text("Some tickets could not be minted")
                                        .font(theme.typography.bodyLarge)
                                        .bold()
                                        .foregroundColor(theme.colors.onSurface)

                                    Text("You paid \(String(format: "%.2f", viewModel.amountPaidSOL)) SOL for \(viewModel.seatNumbers.count) seats, and \(viewModel.mintedNFTIds.count) were issued. Seats \(viewModel.failedSeats.map(String.init).joined(separator: ", ")) failed, so \(String(format: "%.2f", viewModel.owedSOL)) SOL is owed to you.")
                                        .font(theme.typography.bodyMedium)
                                        .foregroundColor(theme.colors.onSurfaceVariant)

                                    Text("Show the payment transaction below to cinema staff to arrange a refund. Your issued tickets are valid and already in your Vault.")
                                        .font(theme.typography.bodyMedium)
                                        .foregroundColor(theme.colors.onSurfaceVariant)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.12))
                                .cornerRadius(Layout.Radius.xl)
                            } else {
                                Text("Check your Vault for your NFTs.")
                                    .font(theme.typography.labelSmall)
                                    .foregroundColor(theme.colors.onSurfaceVariant)
                            }

                            // Links to the minted tickets and payment on the public ledger.
                            VStack(spacing: Layout.Spacing.sm) {
                                ForEach(Array(viewModel.mintedNFTIds.enumerated()), id: \.offset) { index, mint in
                                    ExplorerLink(
                                        target: .address(mint),
                                        title: viewModel.mintedNFTIds.count > 1
                                            ? "Ticket \(index + 1) on Explorer"
                                            : "View ticket on Solana Explorer"
                                    )
                                }
                                if let signature = viewModel.paymentSignature {
                                    ExplorerLink(target: .transaction(signature), title: "Payment transaction")
                                }
                            }

                            if !viewModel.timings.isEmpty {
                                TimingBreakdown(
                                    rows: viewModel.timings,
                                    total: viewModel.totalDuration
                                )
                            }

                            Button("Close") {
                                dismiss()
                                onComplete()
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(theme.colors.primary)
                            .foregroundColor(.white)
                            .cornerRadius(Layout.Radius.md)
                        }
                    }
                } else {
                    Text("Confirm Purchase")
                        .font(theme.typography.labelMedium)
                    
                    if let error = viewModel.transactionError {
                        Text(error)
                            .foregroundColor(theme.colors.error)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    
                    Text("You are about to purchase \(viewModel.seatNumbers.count) ticket(s) for \(viewModel.movie.title).")
                        .multilineTextAlignment(.center)
                    
                    if let price = viewModel.movie.ticketPriceSol {
                        let total = price * Double(viewModel.seatNumbers.count)
                        Text("Total: \(String(format: "%.2f SOL", total))")
                            .font(theme.typography.bodyLarge)
                            .bold()
                            .foregroundColor(theme.colors.secondary)
                    }
                    
                    Button(action: {
                        Task {
                            await viewModel.processCheckout()
                        }
                    }) {
                        HStack {
                            if viewModel.isProcessing {
                                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Sign Transaction with FaceID")
                                Image(systemName: "faceid")
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(theme.colors.primary)
                        .foregroundColor(.white)
                        .cornerRadius(Layout.Radius.md)
                    }
                    .disabled(viewModel.isProcessing)
                    .padding()
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// Extension to round specific corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape( RoundedCorner(radius: radius, corners: corners) )
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
