//
//  SupabaseConfig.swift
//  diplomski
//
//  Created by Karlo Šibalić on 25.04.2026..
//

import Foundation
import Supabase

let supabase = SupabaseClient(
    supabaseURL: URL(string: Secrets.supabaseURL)!,
    supabaseKey: Secrets.supabaseAnonKey,
    options: SupabaseClientOptions(
        auth: .init(
            emitLocalSessionAsInitialSession: true
        )
    )
)
