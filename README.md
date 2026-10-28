# RushGuard

A native iOS cinema-ticketing app in which every ticket is an NFT on Solana. Ownership,
resale and gate validation are backed by the blockchain rather than by a database row.

Built with SwiftUI as part of a master's thesis on blockchain-based ticketing security.
Runs against **Solana Devnet**: SOL has no monetary value and wallets are funded by airdrop.

## Features

- **Non-custodial wallets.** An Ed25519 keypair is derived from a BIP39 recovery phrase
  at sign-up. The private key is stored in the iOS Keychain, readable only on this device
  and only after Face ID. The phrase is shown once and never stored.
- **NFT tickets.** Each seat is minted as a 1-of-1 Metaplex NFT. Metadata (film, row,
  seat, showtime) is pinned to IPFS.
- **Signed, rotating entry passes.** The QR code is a payload signed with the holder's
  key and valid for 30 seconds, so a screenshot cannot be reused.
- **On-chain gate validation.** Staff scan the pass; the app verifies the signature
  locally, then confirms on-chain that the signing wallet currently holds the NFT.
  Database and chain state are shown side by side.
- **Escrow-less resale.** Listings use a Metaplex Auction House. The seller delegates
  transfer authority without giving up the ticket; a buyer's single transaction moves
  the NFT and the payment atomically, with the cinema's fee enforced on-chain.
- **Row Level Security.** All database tables are protected by RLS; operations that must
  cross ownership boundaries run as self-authorizing `SECURITY DEFINER` functions.

## Where state lives

| State | Stored in | Changed by |
|---|---|---|
| Private key | iOS Keychain (device-only, biometric) | The user |
| Ticket ownership | Solana | The holder's signature |
| Ticket metadata | IPFS (URI on-chain) | — |
| Listing and price | Solana (Auction House trade state) | The seller |
| Redemption status | Supabase | Cinema staff |
| Films and showtimes | Supabase | Administrators |

## Stack

SwiftUI (MVVM) · [SolanaSwift](https://github.com/p2p-org/solana-swift) ·
[Supabase](https://supabase.com) (Postgres, Auth) · [Shyft](https://shyft.to)
(transaction building) · [Pinata](https://pinata.cloud) (IPFS) ·
[Helius](https://helius.dev) (RPC) · [TMDB](https://www.themoviedb.org) (film catalogue)

## Project structure

```
diplomski/
├── App/              Entry point and root views
├── Components/       Reusable UI (home screen, navigation bar)
├── Config/           Local credentials (Secrets.swift — not committed)
├── Data/Model/       Domain models, including the signed ticket pass
├── DesignSystem/     Theme, typography, shared components
├── Diagnostics/      Logging and per-stage timing instrumentation
├── Features/
│   ├── Admin/        Ticket scanning, verification, catalogue, marketplace setup
│   ├── Auth/         Sign-in and sign-up
│   ├── Checkout/     Seat selection and purchase
│   ├── Home/         Catalogue
│   ├── Marketplace/  Resale listings
│   ├── Vault/        The user's tickets and entry pass
│   └── Wallet/       Keys, signing, minting, on-chain reads
└── Networking/       Supabase, Shyft, Pinata, TMDB and RPC clients
supabase/migrations/  Database schema changes and RLS policies
```

## Running locally

Requires Xcode 26 and iOS 26.

1. **Credentials.** Copy the template and fill in your own values:

   ```bash
   cp Secrets.example.swift diplomski/Config/Secrets.swift
   ```

   `diplomski/Config/Secrets.swift` is listed in `.gitignore`. See the template for where
   to obtain each key. Helius and the dedicated Pinata gateway are optional.

2. **Database.** The migrations in `supabase/migrations/` apply Row Level Security,
   server-side functions and marketplace support on top of the base tables (`profiles`,
   `active_movies`, `showtimes`, `tickets`, `marketplace_listings`). Run them in order in
   the Supabase SQL editor.

3. **Build** the `diplomski` scheme. For a physical device, set your own development team
   under *Signing & Capabilities*.

4. **Marketplace (once).** Sign in with an account whose `profiles.role` is `admin`
   (assigned in the SQL editor), then open **Marketplace Setup** and create the
   marketplace.

## Security notes and limitations

- **Client-side credentials.** Values compiled into an iOS app can be extracted from the
  binary. Keeping them out of version control prevents accidental publication but does
  not make them secret. A production system would proxy Pinata and Shyft calls through a
  server holding those keys. The Supabase publishable key is designed to be public; data
  access is enforced by RLS.
- **Third-party transaction building.** Minting and marketplace transactions are built by
  Shyft and signed locally; Shyft never holds a key. The app does not decode these
  transactions for the user before signing. Verification does not depend on Shyft.
- **Primary purchase is not atomic.** Payment is a separate transaction from minting, so a
  mint failure after payment leaves the user owed a refund (the app reports the exact
  amount). Resale has no such gap, because the Auction House settles payment and transfer
  in one instruction.
- **Redemption is off-chain.** `is_used` is protected by RLS and a one-way RPC, not by
  cryptography.
- **Devnet only.** The cluster has no persistence guarantee and may be reset.
