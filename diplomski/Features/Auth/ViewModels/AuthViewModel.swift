//
//  AuthViewModel.swift
//  diplomski
//

import SwiftUI
import Supabase
import Combine

@MainActor
class AuthViewModel: ObservableObject {
    
    enum AuthState: Equatable {
        case loading
        case unauthenticated
        case authenticated(isAdmin: Bool)
    }
    
    @Published var authState: AuthState = .loading
    @Published var email = ""
    @Published var password = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    init() {
        Task {
            await checkSession()
        }
    }
    
    // MARK: - Session Check
    
    /// Checks if there is an existing valid session on launch.
    func checkSession() async {
        authState = .loading
        do {
            let session = try await supabase.auth.session
            await fetchRole(for: session.user.id)
            // Initialize wallet for this specific user
            await WalletViewModel.shared.initializeWallet(for: session.user.id.uuidString)
        } catch {
            authState = .unauthenticated
        }
    }
    
    // MARK: - Sign Up
    
    func signUp() async {
        guard validateInput() else { return }
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await supabase.auth.signUp(
                email: email,
                password: password
            )
            
            // Create a profile row for the new user
            let profile = UserProfile(
                id: response.user.id,
                solanaPublicKey: nil,
                role: "user",    // Default role
                createdAt: nil
            )
            try await supabase
                .from("profiles")
                .insert(profile)
                .execute()
            
            authState = .authenticated(isAdmin: false)
            // Generate a new wallet for this user and save to profile
            await WalletViewModel.shared.initializeWallet(for: response.user.id.uuidString)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    // MARK: - Sign In
    
    func signIn() async {
        guard validateInput() else { return }
        isLoading = true
        errorMessage = nil
        
        do {
            let session = try await supabase.auth.signIn(
                email: email,
                password: password
            )
            await fetchRole(for: session.user.id)
            // Initialize wallet for this specific user (loads from profile or creates new)
            await WalletViewModel.shared.initializeWallet(for: session.user.id.uuidString)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    // MARK: - Sign Out
    
    func signOut() async {
        do {
            try await supabase.auth.signOut()
        } catch {
            Log.error("Sign out error: \(error)")
        }
        // Clear wallet state so the next user starts fresh
        WalletViewModel.shared.clearWalletState()
        authState = .unauthenticated
        email = ""
        password = ""
    }
    
    // MARK: - Helpers
    
    private func fetchRole(for userId: UUID) async {
        do {
            let profile: UserProfile = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value
            
            authState = .authenticated(isAdmin: profile.role == "admin")
        } catch {
            // Profile might not exist yet; treat as regular user
            authState = .authenticated(isAdmin: false)
        }
    }
    
    private func validateInput() -> Bool {
        if email.trimmingCharacters(in: .whitespaces).isEmpty ||
            password.trimmingCharacters(in: .whitespaces).isEmpty {
            errorMessage = "Email and password cannot be empty."
            return false
        }
        if password.count < 6 {
            errorMessage = "Password must be at least 6 characters."
            return false
        }
        return true
    }
}
