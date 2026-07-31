import Foundation
import Observation

/// Drives authentication: sign in / create account / logout, and the
/// backend URL the app talks to (editable on the sign-in screen so the app
/// can be pointed at a local dev server or a deployed Vercel backend).
@Observable
@MainActor
final class AuthViewModel {

    // MARK: - State

    var email = ""
    var password = ""
    var isCreatingAccount = false
    var isBusy = false
    var errorMessage: String?

    private(set) var isAuthenticated: Bool
    private(set) var currentUserEmail: String?

    /// Backend base URL; persisted to UserDefaults so APIService and the
    /// WebSocket manager pick it up on every request.
    var backendURL: String {
        didSet { UserDefaults.standard.set(backendURL, forKey: "apiBaseURL") }
    }

    private let api = APIService()

    // MARK: - Init

    init() {
        backendURL = UserDefaults.standard.string(forKey: "apiBaseURL") ?? "http://127.0.0.1:8000"
        isAuthenticated = UserDefaults.standard.string(forKey: "authToken") != nil
        currentUserEmail = UserDefaults.standard.string(forKey: "authEmail")
    }

    // MARK: - Actions

    func signIn() async {
        await submit { [api] in
            try await api.login(email: email, password: password)
        }
    }

    func createAccount() async {
        await submit { [api] in
            try await api.signup(email: email, password: password)
        }
    }

    func signOut() {
        Task {
            try? await api.logout()  // best-effort server-side revoke
        }
        UserDefaults.standard.removeObject(forKey: "authToken")
        UserDefaults.standard.removeObject(forKey: "authEmail")
        isAuthenticated = false
        currentUserEmail = nil
        email = ""
        password = ""
        errorMessage = nil
    }

    /// Shared submit path: clears stale errors, calls the action, and on
    /// success persists the token/email and flips to authenticated.
    private func submit(_ action: () async throws -> AuthResponse) async {
        errorMessage = nil
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty,
              !password.isEmpty else {
            errorMessage = "Enter your email and password"
            return
        }
        guard let url = URL(string: backendURL), url.scheme != nil else {
            errorMessage = "That backend URL isn't valid (include http:// or https://)"
            return
        }

        isBusy = true
        defer { isBusy = false }
        do {
            let auth = try await action()
            UserDefaults.standard.set(auth.token, forKey: "authToken")
            UserDefaults.standard.set(auth.email, forKey: "authEmail")
            isAuthenticated = true
            currentUserEmail = auth.email
            email = ""
            password = ""
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    private func friendlyError(_ error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .http(let code, let detail):
                if code == 401 { return "Invalid email or password" }
                if code == 409 { return "An account with that email already exists — try signing in" }
                // "Cannot reach the draft server" style — help the user point
                // at the right URL.
                if code == 404 || code == 502 || code == 503 {
                    return "Can't reach that server — check the backend URL, then try again."
                }
                return "Server error (\(code)): \(detail)"
            case .network:
                return "Can't connect to the draft server — is the backend running at \(backendURL)?"
            default:
                return apiError.localizedDescription
            }
        }
        return error.localizedDescription
    }
}
