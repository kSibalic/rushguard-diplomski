//
//  UserProfile.swift
//  diplomski
//

import Foundation

nonisolated struct UserProfile: Identifiable, Codable {
    let id: UUID
    let solanaPublicKey: String?
    let role: String?
    let createdAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case solanaPublicKey = "solana_public_key"
        case role
        case createdAt = "created_at"
    }
}
