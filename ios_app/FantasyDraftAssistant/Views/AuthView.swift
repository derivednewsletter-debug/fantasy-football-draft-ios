import SwiftUI

/// Sign in / create-account gate shown before the league list.
///
/// Also hosts the backend URL field — the app defaults to a local dev server
/// (http://127.0.0.1:8000) but can be pointed at a deployed Vercel backend
/// here, which fixes the "can't connect to the draft server" case in-app.
struct AuthView: View {
    @Environment(AuthViewModel.self) private var auth

    var body: some View {
        @Bindable var auth = auth
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)

                // Brand
                VStack(spacing: 8) {
                    Image(systemName: "football.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.blue)
                    Text("Draft Assistant")
                        .font(.largeTitle.weight(.bold))
                    Text("Multi-league fantasy football drafts")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Form card
                VStack(spacing: 14) {
                    // Backend URL
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Backend URL")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("http://127.0.0.1:8000", text: $auth.backendURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(10)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            }
                    }

                    TextField("Email", text: $auth.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(10)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        }
                        .accessibilityIdentifier("authEmailField")

                    SecureField("Password", text: $auth.password)
                        .padding(10)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        }
                        .accessibilityIdentifier("authPasswordField")

                    if let message = auth.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Primary action
                    Button {
                        Task {
                            if auth.isCreatingAccount {
                                await auth.createAccount()
                            } else {
                                await auth.signIn()
                            }
                        }
                    } label: {
                        Group {
                            if auth.isBusy {
                                ProgressView().tint(.white)
                            } else {
                                Text(auth.isCreatingAccount ? "Create Account" : "Sign In")
                                    .fontWeight(.bold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .background(auth.isBusy ? Color.blue.opacity(0.6) : Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
                    .disabled(auth.isBusy)
                    .accessibilityIdentifier("authSubmitButton")

                    // Toggle mode
                    Button {
                        auth.isCreatingAccount.toggle()
                        auth.errorMessage = nil
                    } label: {
                        Text(auth.isCreatingAccount
                             ? "Already have an account? Sign in"
                             : "New here? Create an account")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(auth.isBusy)
                }
                .padding(16)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .background(Color(.systemBackground))
    }
}
