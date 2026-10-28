//
//  diplomskiApp.swift
//  diplomski
//
//  Created by Karlo Šibalić on 19.04.2026..
//

import SwiftUI

@main
struct diplomskiApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.theme, .dark)
                .preferredColorScheme(.dark)
                // Wallet is now initialized per-user in AuthViewModel after authentication.
        }
    }
}
