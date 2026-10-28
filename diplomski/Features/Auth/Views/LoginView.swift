//
//  LoginView.swift
//  diplomski
//

import SwiftUI

struct LoginView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @Environment(\.theme) var theme
    
    @State private var isSignUp = false
    @FocusState private var focusedField: Field?
    
    enum Field { case email, password }
    
    var body: some View {
        ZStack {
            // Background
            theme.colors.background.ignoresSafeArea()
            
            // Subtle gradient accent
            VStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [theme.colors.primary.opacity(0.25), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 250
                        )
                    )
                    .frame(width: 400, height: 400)
                    .offset(x: 100, y: -80)
                Spacer()
            }
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: Layout.Spacing.xl) {
                    Spacer().frame(height: 60)
                    
                    // MARK: — Logo & Title
                    VStack(spacing: Layout.Spacing.md) {
                        Image(systemName: "shield.checkered")
                            .font(theme.typography.iconHero)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [theme.colors.primary, theme.colors.secondary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text("Rushguard")
                            .font(theme.typography.displayLarge)
                            .foregroundColor(theme.colors.onSurface)
                        
                        Text("Web3 Movie Tickets on Solana")
                            .font(theme.typography.bodyMedium)
                            .foregroundColor(theme.colors.onSurfaceVariant)
                    }
                    
                    // MARK: — Input Fields
                    VStack(spacing: Layout.Spacing.md) {
                        // Email
                        HStack(spacing: Layout.Spacing.sm) {
                            Image(systemName: "envelope.fill")
                                .foregroundColor(theme.colors.onSurfaceVariant)
                                .frame(width: 20)
                            TextField("Email", text: $authViewModel.email)
                                .textContentType(.emailAddress)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .keyboardType(.emailAddress)
                                .foregroundColor(theme.colors.onSurface)
                                .focused($focusedField, equals: .email)
                        }
                        .padding()
                        .background(theme.colors.surfaceContainerHigh)
                        .cornerRadius(Layout.Radius.xl)
                        .overlay(
                            RoundedRectangle(cornerRadius: Layout.Radius.xl)
                                .stroke(
                                    focusedField == .email
                                        ? theme.colors.primary
                                        : theme.colors.outlineVariant,
                                    lineWidth: 1
                                )
                        )
                        
                        // Password
                        HStack(spacing: Layout.Spacing.sm) {
                            Image(systemName: "lock.fill")
                                .foregroundColor(theme.colors.onSurfaceVariant)
                                .frame(width: 20)
                            SecureField("Password", text: $authViewModel.password)
                                .textContentType(isSignUp ? .newPassword : .password)
                                .foregroundColor(theme.colors.onSurface)
                                .focused($focusedField, equals: .password)
                        }
                        .padding()
                        .background(theme.colors.surfaceContainerHigh)
                        .cornerRadius(Layout.Radius.xl)
                        .overlay(
                            RoundedRectangle(cornerRadius: Layout.Radius.xl)
                                .stroke(
                                    focusedField == .password
                                        ? theme.colors.primary
                                        : theme.colors.outlineVariant,
                                    lineWidth: 1
                                )
                        )
                    }
                    .padding(.horizontal, Layout.Spacing.lg)
                    
                    // MARK: — Error Message
                    if let error = authViewModel.errorMessage {
                        Text(error)
                            .font(theme.typography.bodySmall)
                            .foregroundColor(theme.colors.error)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Layout.Spacing.lg)
                            .transition(.opacity)
                    }
                    
                    // MARK: — Primary Action Button
                    Button(action: {
                        Task {
                            if isSignUp {
                                await authViewModel.signUp()
                            } else {
                                await authViewModel.signIn()
                            }
                        }
                    }) {
                        HStack(spacing: Layout.Spacing.sm) {
                            if authViewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text(isSignUp ? "Create Account" : "Sign In")
                                    .font(theme.typography.bodyLarge)
                                    .bold()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [theme.colors.primary, theme.colors.primary.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(Layout.Radius.xl)
                    }
                    .disabled(authViewModel.isLoading)
                    .padding(.horizontal, Layout.Spacing.lg)
                    
                    // MARK: — Toggle Sign In / Sign Up
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSignUp.toggle()
                            authViewModel.errorMessage = nil
                        }
                    }) {
                        HStack(spacing: 4) {
                            Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                                .foregroundColor(theme.colors.onSurfaceVariant)
                            Text(isSignUp ? "Sign In" : "Sign Up")
                                .foregroundColor(theme.colors.secondary)
                                .bold()
                        }
                        .font(theme.typography.bodyMedium)
                    }
                    
                    Spacer()
                }
            }
        }
        .animation(.easeInOut, value: authViewModel.errorMessage)
    }
}
