//
//  AdminDashboardView.swift
//  diplomski
//

import SwiftUI

struct AdminDashboardView: View {
    @Environment(\.theme) var theme
    @State private var showingScanner = false
    @State private var scanResultError: String?
    @State private var activeTicket: ScannedTicket?
    /// Holds a scanned code between the scanner closing and the verification sheet
    /// opening. SwiftUI will not present a second sheet while the first is dismissing.
    @State private var pendingScannedCode: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                theme.colors.background.ignoresSafeArea()
                
                VStack(spacing: Layout.Spacing.lg) {
                    
                    NavigationLink(destination: AddMoviesView()) {
                        AdminHubCard(
                            icon: "film",
                            title: "Add Movies",
                            subtitle: "Search TMDB and schedule showtimes",
                            color: .blue
                        )
                    }
                    
                    Button(action: {
                        showingScanner = true
                    }) {
                        AdminHubCard(
                            icon: "qrcode.viewfinder",
                            title: "Scan Ticket",
                            subtitle: "Verify NFTs via QR Code",
                            color: .green
                        )
                    }
                    
                    NavigationLink(destination: MarketplaceView(isAdmin: true)) {
                        AdminHubCard(
                            icon: "cart.fill",
                            title: "Marketplace Management",
                            subtitle: "View seller data and moderate listings",
                            color: .orange
                        )
                    }

                    NavigationLink(destination: MarketplaceSetupView()) {
                        AdminHubCard(
                            icon: "building.columns",
                            title: "Marketplace Setup",
                            subtitle: "Create or verify the on-chain marketplace",
                            color: .purple
                        )
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Control Center")
            // The verification sheet is presented from `onDismiss`, once the scanner
            // sheet has fully closed.
            .sheet(isPresented: $showingScanner, onDismiss: {
                if let code = pendingScannedCode {
                    pendingScannedCode = nil
                    activeTicket = ScannedTicket(rawCode: code)
                }
            }) {
                QRScannerView(
                    completion: { result in
                        switch result {
                        case .success(let code):
                            // Pass the code through untouched — the signature covers
                            // these exact bytes, so parsing happens after verification.
                            pendingScannedCode = code
                        case .failure(let error):
                            scanResultError = error.localizedDescription
                        }
                        showingScanner = false
                    },
                    onCancel: { showingScanner = false }
                )
            }
            .sheet(item: $activeTicket) { ticket in
                TicketVerificationSheet(scannedCode: ticket.rawCode)
            }
            .alert("Scan Error", isPresented: .constant(scanResultError != nil)) {
                Button("OK", role: .cancel) { scanResultError = nil }
            } message: {
                Text(scanResultError ?? "")
            }
        }
    }
}

// MARK: - Ticket Verification Sheet (Admin)

struct TicketVerificationSheet: View {
    @StateObject private var viewModel: TicketVerificationViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.theme) var theme

    init(scannedCode: String) {
        _viewModel = StateObject(wrappedValue: TicketVerificationViewModel(scannedCode: scannedCode))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                theme.colors.background.ignoresSafeArea()

                if viewModel.isLoading {
                    VStack(spacing: Layout.Spacing.md) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Checking signature and reading the blockchain…")
                            .font(theme.typography.bodyMedium)
                            .foregroundColor(theme.colors.onSurfaceVariant)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: Layout.Spacing.lg) {
                            verdictBanner
                            signatureCard
                            comparisonCard
                            chainCard
                            mintCard

                            if viewModel.verdict.admits || viewModel.verdict == .unsignedLegacyCode {
                                redeemButton
                            }

                            if let error = viewModel.redeemError {
                                Text(error)
                                    .font(theme.typography.labelSmall)
                                    .foregroundColor(theme.colors.error)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Ticket Verification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await viewModel.verify()
            }
        }
    }

    // MARK: - Verdict

    private var verdictBanner: some View {
        VStack(spacing: 12) {
            Image(systemName: viewModel.verdict.icon)
                .font(theme.typography.iconLarge)
                .foregroundColor(viewModel.verdict.color)
            Text(viewModel.verdict.title)
                .font(theme.typography.statusTitle)
                .foregroundColor(viewModel.verdict.color)
            Text(viewModel.verdict.subtitle)
                .font(theme.typography.bodyMedium)
                .foregroundColor(theme.colors.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.top, Layout.Spacing.lg)
    }

    // MARK: - Cryptographic evidence

    private var signatureCard: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.md) {
            Text("CRYPTOGRAPHIC CHECK")
                .font(theme.typography.labelSmall)
                .foregroundColor(theme.colors.onSurfaceVariant)

            Divider()

            if let payload = viewModel.passPayload {
                VerificationRow(
                    label: "Signature",
                    value: viewModel.verdict == .forgedSignature ? "Invalid" : "Verified (Ed25519)",
                    icon: "signature"
                )
                Divider()
                VerificationRow(
                    label: "Signed by",
                    value: String(payload.pubkey.prefix(8)) + "…" + String(payload.pubkey.suffix(4)),
                    icon: "key.fill"
                )
                Divider()
                VerificationRow(
                    label: "Code age",
                    value: ageDescription(for: payload),
                    icon: "clock"
                )
            } else {
                VerificationRow(
                    label: "Signature",
                    value: "None — static code",
                    icon: "exclamationmark.triangle"
                )
                Text("This code carries no proof of who presented it. Any copy of it scans identically.")
                    .font(theme.typography.labelSmall)
                    .foregroundColor(theme.colors.onSurfaceVariant)
            }
        }
        .padding()
        .background(theme.colors.surface)
        .cornerRadius(Layout.Radius.xl)
    }

    private func ageDescription(for payload: TicketPassPayload) -> String {
        let age = Int(Date().timeIntervalSince(payload.issuedAtDate))
        if age < 0 { return "issued in the future" }
        return "\(age)s old (valid for \(Int(TicketPass.validityWindow))s)"
    }

    // MARK: - Database vs. chain

    private var comparisonCard: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.md) {
            HStack {
                Text("DATABASE")
                    .font(theme.typography.labelSmall)
                    .foregroundColor(theme.colors.onSurfaceVariant)
                Spacer()
                Text("BLOCKCHAIN")
                    .font(theme.typography.labelSmall)
                    .foregroundColor(theme.colors.onSurfaceVariant)
            }

            Divider()

            ForEach(viewModel.comparisons) { comparison in
                ComparisonRow(comparison: comparison)
            }

            if viewModel.comparisons.contains(where: { $0.status == .mismatch }) {
                Text("A mismatch means the database no longer agrees with the chain. The chain is the record that cannot be edited without the owner's private key.")
                    .font(theme.typography.labelSmall)
                    .foregroundColor(.orange)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(theme.colors.surface)
        .cornerRadius(Layout.Radius.xl)
    }

    // MARK: - Raw chain state

    @ViewBuilder
    private var chainCard: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.md) {
            Text("ON-CHAIN STATE")
                .font(theme.typography.labelSmall)
                .foregroundColor(theme.colors.onSurfaceVariant)

            Divider()

            if let chain = viewModel.chain {
                VerificationRow(
                    label: "Current holder",
                    value: String(chain.owner.prefix(8)) + "…" + String(chain.owner.suffix(4)),
                    icon: "wallet.pass"
                )
                Divider()
                VerificationRow(
                    label: "Token account",
                    value: String(chain.tokenAccount.prefix(8)) + "…" + String(chain.tokenAccount.suffix(4)),
                    icon: "tray.full"
                )
                Divider()
                VerificationRow(
                    label: "Supply held",
                    value: chain.isNonFungible ? "1 (non-fungible)" : "\(chain.amount)",
                    icon: "number"
                )
                if let uri = chain.metadataURI, !uri.isEmpty {
                    Divider()
                    VerificationRow(label: "Metadata", value: uri, icon: "doc.text")
                }
            } else {
                VerificationRow(
                    label: "Chain read",
                    value: viewModel.chainReadFailure ?? "unavailable",
                    icon: "xmark.icloud"
                )
            }
        }
        .padding()
        .background(theme.colors.surface)
        .cornerRadius(Layout.Radius.xl)
    }

    private var mintCard: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.sm) {
            Text("NFT MINT ADDRESS")
                .font(theme.typography.labelSmall)
                .foregroundColor(theme.colors.onSurfaceVariant)
            Text(viewModel.mint ?? "—")
                .font(theme.typography.monoBody)
                .foregroundColor(theme.colors.onSurface)
                .textSelection(.enabled)

            if let mint = viewModel.mint {
                ExplorerLink(target: .address(mint), showsValue: false)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(theme.colors.surface)
        .cornerRadius(Layout.Radius.xl)
    }

    private var redeemButton: some View {
        Button(action: {
            Task { await viewModel.markAsUsed() }
        }) {
            HStack {
                if viewModel.isMarkingUsed {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Redeem Ticket — Mark as Used")
                }
            }
            .font(theme.typography.bodyLarge)
            .bold()
            .frame(maxWidth: .infinity)
            .padding()
            .background(viewModel.verdict.admits ? .green : .orange)
            .foregroundColor(.white)
            .cornerRadius(Layout.Radius.xl)
        }
        .disabled(viewModel.isMarkingUsed)
        .padding(.top, Layout.Spacing.sm)
    }
}

// MARK: - Comparison Row

struct ComparisonRow: View {
    let comparison: FieldComparison
    @Environment(\.theme) var theme

    private var indicator: (icon: String, color: Color) {
        switch comparison.status {
        case .match: return ("checkmark.circle.fill", .green)
        case .mismatch: return ("exclamationmark.triangle.fill", .orange)
        case .unavailable: return ("minus.circle", theme.colors.onSurfaceVariant)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: indicator.icon)
                    .font(theme.typography.iconSmall)
                    .foregroundColor(indicator.color)
                Text(comparison.label)
                    .font(theme.typography.labelSmall)
                    .foregroundColor(theme.colors.onSurfaceVariant)
            }

            HStack(alignment: .top, spacing: Layout.Spacing.sm) {
                Text(comparison.database)
                    .font(theme.typography.bodyMedium)
                    .foregroundColor(theme.colors.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: comparison.status == .mismatch ? "arrow.left.and.right" : "equal")
                    .font(theme.typography.iconSmall)
                    .foregroundColor(indicator.color)

                Text(comparison.chain)
                    .font(theme.typography.bodyMedium)
                    .foregroundColor(comparison.status == .mismatch ? .orange : theme.colors.onSurface)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 4)
    }
}


struct VerificationRow: View {
    let label: String
    let value: String
    let icon: String
    @Environment(\.theme) var theme
    
    init(label: String, value: String, icon: String) {
        self.label = label
        self.value = String(value)
        self.icon = icon
    }
    
    init(label: String, value: Substring, icon: String) {
        self.label = label
        self.value = String(value)
        self.icon = icon
    }
    
    var body: some View {
        HStack(spacing: Layout.Spacing.sm) {
            Image(systemName: icon)
                .foregroundColor(theme.colors.primary)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(theme.typography.labelSmall)
                    .foregroundColor(theme.colors.onSurfaceVariant)
                Text(value)
                    .font(theme.typography.bodyMedium)
                    .foregroundColor(theme.colors.onSurface)
            }
            
            Spacer()
        }
    }
}

struct AdminHubCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    @Environment(\.theme) var theme
    
    var body: some View {
        HStack(spacing: Layout.Spacing.md) {
            Image(systemName: icon)
                .font(theme.typography.iconMedium)
                .foregroundColor(color)
                .frame(width: 50)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(theme.typography.bodyMedium)
                    .foregroundColor(theme.colors.onSurface)
                Text(subtitle)
                    .font(theme.typography.bodyMedium)
                    .foregroundColor(theme.colors.onSurfaceVariant)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(theme.colors.onSurfaceVariant)
        }
        .padding()
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Layout.Radius.xl))
    }
}

struct AddMoviesView: View {
    @StateObject private var viewModel = AdminDashboardViewModel()
    @Environment(\.theme) var theme
    
    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(theme.colors.onSurfaceVariant)
                    TextField("Search TMDB...", text: $viewModel.searchQuery)
                        .foregroundColor(theme.colors.onSurface)
                        .disableAutocorrection(true)
                }
                .padding()
                .background(theme.colors.surface)
                .cornerRadius(Layout.Radius.md)
                .padding()
                
                if viewModel.isLoading && viewModel.searchResults.isEmpty {
                    ProgressView()
                        .padding()
                    Spacer()
                } else if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(theme.colors.error)
                        .padding()
                    Spacer()
                } else {
                    List(viewModel.searchResults) { movie in
                        HStack {
                            if let url = movie.posterURL {
                                AsyncImage(url: url) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Color.gray
                                }
                                .frame(width: 50, height: 75)
                                .cornerRadius(4)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(movie.title)
                                    .font(theme.typography.bodyLarge)
                                    .foregroundColor(theme.colors.onSurface)
                                if let date = movie.releaseDate {
                                    Text(date)
                                        .font(theme.typography.labelSmall)
                                        .foregroundColor(theme.colors.onSurfaceVariant)
                                }
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                viewModel.selectedMovie = movie
                            }) {
                                Text("Add")
                                    .font(theme.typography.labelMedium)
                                    .bold()
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(theme.colors.primary)
                                    .foregroundColor(.white)
                                    .cornerRadius(Layout.Radius.sm)
                            }
                        }
                        .listRowBackground(theme.colors.background)
                    }
                    .listStyle(PlainListStyle())
                }
            }
        }
        .navigationTitle("Add Movies")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $viewModel.selectedMovie) { movie in
            AddMovieSheet(viewModel: viewModel, movie: movie)
        }
        .alert("Success", isPresented: $viewModel.isSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Movie and showtime added to database.")
        }
    }
}

struct AddMovieSheet: View {
    @ObservedObject var viewModel: AdminDashboardViewModel
    let movie: Movie
    @Environment(\.dismiss) var dismiss
    @Environment(\.theme) var theme
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Movie Details")) {
                    Text(movie.title).bold()
                    Text(movie.overview).lineLimit(3)
                }
                
                Section(header: Text("Ticket Price")) {
                    HStack {
                        Text("Price (SOL)")
                        Spacer()
                        TextField("0.45", text: $viewModel.ticketPriceSol)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section(header: HStack {
                    Text("Showtimes")
                    Spacer()
                    Button(action: {
                        viewModel.addShowtimeEntry()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add")
                        }
                        .font(theme.typography.labelMedium)
                        .foregroundColor(theme.colors.secondary)
                    }
                }) {
                    ForEach($viewModel.showtimeEntries) { $entry in
                        VStack(spacing: 8) {
                            Picker("Theatre", selection: $entry.theaterName) {
                                ForEach(AdminDashboardViewModel.availableTheaters, id: \.self) { theater in
                                    Text(theater).tag(theater)
                                }
                            }
                            
                            DatePicker("Date & Time", selection: $entry.date)
                            
                            HStack {
                                Text("Seats")
                                Spacer()
                                TextField("100", text: $entry.seats)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: viewModel.removeShowtimeEntry)
                }
                
                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(theme.colors.error)
                    }
                }
                
                Button(action: {
                    Task {
                        await viewModel.addToCinema()
                        if viewModel.isSuccess {
                            dismiss()
                        }
                    }
                }) {
                    HStack {
                        Spacer()
                        if viewModel.isLoading {
                            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Confirm & Add to Supabase")
                        }
                        Spacer()
                    }
                }
                .disabled(viewModel.isLoading)
                .listRowBackground(theme.colors.primary)
                .foregroundColor(.white)
            }
            .navigationTitle("Add to Cinema")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
