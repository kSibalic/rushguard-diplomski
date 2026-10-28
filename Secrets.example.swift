//
//  Secrets.example.swift
//  diplomski
//
//  Template for local credentials.
//
//  Copy this file to `diplomski/Config/Secrets.swift` and fill in your own values.
//  That path is listed in .gitignore and must never be committed.
//
//  Note: values compiled into an iOS app can be extracted from the binary. Keeping
//  them out of version control prevents accidental publication; it does not make
//  them secret from someone holding the built app. A production deployment would
//  proxy the Pinata and Shyft calls through a server that holds these keys.
//

enum Secrets {
    /// Supabase project URL, e.g. "https://<project-ref>.supabase.co"
    static let supabaseURL = ""

    /// Supabase publishable (anon) key. Safe to ship in a client by design;
    /// data access is enforced by Row Level Security.
    static let supabaseAnonKey = ""

    /// TMDB API Read Access Token (v4 auth). https://www.themoviedb.org/settings/api
    static let tmdbReadAccessToken = ""

    /// Shyft API key, used for NFT minting and marketplace transactions. https://shyft.to
    static let shyftAPIKey = ""

    /// Pinata JWT, used to pin ticket metadata to IPFS. https://app.pinata.cloud
    static let pinataJWT = ""

    /// Dedicated Pinata gateway domain, e.g. "example-name-123.mypinata.cloud".
    /// Leave empty to fall back to the shared public gateway (slower, heavily rate-limited).
    static let pinataGatewayDomain = ""

    /// Helius API key for a dedicated Solana Devnet RPC endpoint. https://dashboard.helius.dev
    /// Leave empty to use only the public Devnet endpoint.
    static let heliusAPIKey = ""
}
