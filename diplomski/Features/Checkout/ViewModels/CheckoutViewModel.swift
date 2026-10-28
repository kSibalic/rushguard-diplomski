//
//  CheckoutViewModel.swift
//  diplomski
//

import SwiftUI
import Combine
import Supabase

@MainActor
class CheckoutViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var transactionError: String?
    @Published var transactionSuccess = false
    @Published var mintedNFTIds: [String] = []
    /// Signature of the SOL payment, so the success screen can link to it on Explorer.
    @Published var paymentSignature: String?
    /// Seats that were paid for but whose mint did not complete.
    @Published var failedSeats: [Int] = []
    @Published var amountPaidSOL: Double = 0
    @Published var pricePerSeatSOL: Double = 0

    /// True when money moved but not every seat produced a ticket.
    var isPartialPurchase: Bool { !failedSeats.isEmpty && !mintedNFTIds.isEmpty }

    /// What the cinema owes the user for seats that were paid for but never minted.
    var owedSOL: Double { Double(failedSeats.count) * pricePerSeatSOL }
    /// Per-stage durations from the completed purchase, shown on the success screen.
    @Published var timings: [(phase: String, duration: Double)] = []
    @Published var totalDuration: TimeInterval = 0
    
    let movie: ActiveMovie
    let showtime: Showtime
    let seatNumbers: [Int]
    
    init(movie: ActiveMovie, showtime: Showtime, seatNumbers: [Int]) {
        self.movie = movie
        self.showtime = showtime
        self.seatNumbers = seatNumbers
    }
    
    func processCheckout() async {
        guard let priceSOL = movie.ticketPriceSol else {
            transactionError = "Invalid ticket price."
            return
        }
        
        guard !seatNumbers.isEmpty else {
            transactionError = "No seats selected."
            return
        }
        
        isProcessing = true
        transactionError = nil

        // Measures the purchase as the user experiences it, from confirmation to the
        // success screen, broken down by stage.
        let timer = PhaseTimer("kupnja-\(seatNumbers.count)-sjedala")

        do {
            guard let userId = try? await supabase.auth.session.user.id else {
                throw URLError(.userAuthenticationRequired)
            }
            let userIdString = userId.uuidString

            // 1. Convert the total to lamports.
            let totalPriceSOL = priceSOL * Double(seatNumbers.count)
            let amountLamports = UInt64(totalPriceSOL * 1_000_000_000)

            // 2. Unlock the signing key once for the whole purchase, so the user
            //    authenticates once rather than once per ticket.
            let signer = try WalletManager.shared.retrieveWallet(for: userIdString)
            timer.mark("faceid")

            // 3. Transfer total SOL.
            let paymentSignature = try await WalletManager.shared.transferSOL(
                amountLamports: amountLamports,
                userId: userIdString,
                signer: signer,
                timer: timer
            )
            self.paymentSignature = paymentSignature

            // 4. Mint one NFT per seat. A failed seat does not abort the batch: payment
            //    for every seat has already been made, so the remaining seats are still
            //    minted and any failures are reported individually.
            var mintedIds: [String] = []
            var failures: [(seat: Int, reason: String)] = []

            for seat in seatNumbers {
                let nftId: String
                do {
                    nftId = try await WalletManager.shared.mintNFTTicket(
                        movieTitle: movie.title,
                        showtime: showtime.startTime,
                        seat: seat,
                        userId: userIdString,
                        signer: signer,
                        timer: timer
                    )
                } catch {
                    Log.error("Seat \(seat) failed to mint: \(error.localizedDescription)")
                    failures.append((seat, error.localizedDescription))
                    continue
                }

                // The NFT now exists on-chain and is owned, whatever happens next.
                mintedIds.append(nftId)

                do {
                    let ticket = SupabaseTicket(
                        nftId: nftId,
                        userId: userId,
                        movieTitle: movie.title,
                        posterPath: movie.posterPath,
                        showtime: showtime.startTime,
                        seat: seat,
                        isListedOnMarketplace: false,
                        isUsed: false,
                        createdAt: Date()
                    )

                    try await DatabaseService.shared.addTicket(ticket: ticket)
                    timer.mark("baza")
                } catch {
                    // The ticket is minted and owned; only the database index is missing,
                    // so this is not reported as an unminted seat.
                    Log.error("Seat \(seat) minted (\(nftId)) but the database insert failed: \(error.localizedDescription). The NFT exists on chain.")
                }
            }

            self.mintedNFTIds = mintedIds
            self.failedSeats = failures.map(\.seat)
            self.transactionSuccess = !mintedIds.isEmpty

            if !failures.isEmpty {
                self.amountPaidSOL = totalPriceSOL
                self.pricePerSeatSOL = priceSOL
                if mintedIds.isEmpty {
                    self.transactionError = "Payment went through, but no tickets could be minted. \(failures.first?.reason ?? "")"
                }
            }

            // 5. Refresh the displayed balance.
            await WalletViewModel.shared.fetchBalance()

            timer.dump()
            self.timings = timer.rows
            self.totalDuration = timer.total

        } catch {
            self.transactionError = "Transaction failed: \(error.localizedDescription)"
            // Print the partial timing too; it shows which stage failed.
            timer.dump(record: false)
        }

        isProcessing = false
    }
}
