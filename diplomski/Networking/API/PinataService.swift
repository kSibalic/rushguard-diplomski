//
//  PinataService.swift
//  diplomski
//

import Foundation

class PinataService {
    static let shared = PinataService()

    /// IPFS gateway used to build the `metadata_uri` written into each NFT.
    ///
    /// This choice affects mint reliability directly: Shyft downloads this URL
    /// server-side while building the mint transaction and gives up after 25 seconds.
    /// Pinata's shared gateway (`gateway.pinata.cloud`) is rate-limited per client IP,
    /// and Shyft calls it from a single IP on behalf of all its customers, so requests
    /// through it intermittently exceed that limit. A dedicated gateway is rate-limited
    /// per account instead.
    ///
    /// The URI is permanent once written into an NFT.
    private var gatewayBase: String {
        Secrets.pinataGatewayDomain.isEmpty
            ? "https://gateway.pinata.cloud/ipfs"
            : "https://\(Secrets.pinataGatewayDomain)/ipfs"
    }

    private let jwtToken = Secrets.pinataJWT

    private init() {}

    /// Uploads standard Metaplex JSON metadata to IPFS via Pinata.
    ///
    /// `showtime` is written into the attributes so the on-chain record is
    /// self-sufficient: verification can confirm the seat *and* the screening a ticket
    /// is for without consulting the database. Metadata without a `Showtime` attribute
    /// is treated by the verifier as unavailable rather than as a mismatch.
    ///
    /// - Returns: A gateway URL for the pinned JSON.
    func uploadJSONMetadata(
        name: String,
        symbol: String,
        description: String,
        imageURL: String,
        row: Int,
        seat: Int,
        showtime: Date,
        walletAddress: String
    ) async throws -> String {
        let endpoint = URL(string: "https://api.pinata.cloud/pinning/pinJSONToIPFS")!

        let showtimeString = ISO8601DateFormatter().string(from: showtime)

        let metadata: [String: Any] = [
            "name": name,
            "symbol": symbol,
            "description": description,
            "image": imageURL,
            "seller_fee_basis_points": 0,
            "attributes": [
                ["trait_type": "Row", "value": "\(row)"],
                ["trait_type": "Seat", "value": "\(seat)"],
                ["trait_type": "Showtime", "value": showtimeString]
            ],
            "properties": [
                "files": [
                    [
                        "uri": imageURL,
                        "type": "image/png"
                    ]
                ],
                "category": "image",
                "creators": [
                    [
                        "address": walletAddress,
                        "share": 100
                    ]
                ]
            ]
        ]
        
        let pinataPayload: [String: Any] = [
            "pinataContent": metadata,
            "pinataMetadata": [
                "name": "\(name.replacingOccurrences(of: " ", with: "_"))_Row\(row)_Seat\(seat).json"
            ]
        ]
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(jwtToken)", forHTTPHeaderField: "Authorization")
        
        let jsonData = try JSONSerialization.data(withJSONObject: pinataPayload)
        request.httpBody = jsonData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown Pinata Error"
            Log.error("Pinata upload failed: \(errorMsg)")
            throw URLError(.badServerResponse)
        }
        
        struct PinataResponse: Decodable {
            let IpfsHash: String
        }
        
        let result = try JSONDecoder().decode(PinataResponse.self, from: data)
        let uri = "\(gatewayBase)/\(result.IpfsHash)"

        // Diagnostic only, and deliberately not awaited: if the gateway cannot serve the
        // metadata, Shyft will not be able to either, and this log explains the timeout
        // that follows. Blocking on it would add the gateway's latency to every mint.
        Task.detached(priority: .utility) { [uri] in
            await Self.checkReadable(uri)
        }

        return uri
    }

    private static func checkReadable(_ uri: String) async {
        guard let url = URL(string: uri) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if !(200...299).contains(status) {
                Log.error("Metadata is not readable at the gateway (HTTP \(status)) — Shyft will not be able to fetch it either.")
            }
        } catch {
            Log.error("Metadata gateway check failed: \(error.localizedDescription) — Shyft fetches this same URL and will likely time out.")
        }
    }

}
