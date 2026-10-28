//
//  NavigationTab.swift
//  diplomski
//
//  Created by Karlo Šibalić on 20.04.2026..
//

import Foundation

enum NavigationTab: String, CaseIterable {
    case home = "Home"
    case vault = "Vault"
    case marketplace = "Marketplace"
    case profile = "Profile"
    
    var iconName: String {
        switch self {
        case .home: return "house.fill"
        case .vault: return "ticket.fill"
        case .marketplace: return "cart.fill"
        case .profile: return "person.fill"
        }
    }
}
