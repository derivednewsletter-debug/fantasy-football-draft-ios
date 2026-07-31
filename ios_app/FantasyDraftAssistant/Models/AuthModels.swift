import Foundation

/// Payload for creating an account.
struct SignupRequest: Encodable {
    let email: String
    let password: String
}

/// Payload for signing in.
struct LoginRequest: Encodable {
    let email: String
    let password: String
}

/// Response from /auth/signup and /auth/login.
struct AuthResponse: Decodable {
    let token: String
    let email: String
}

/// Response from /auth/me.
struct MeResponse: Decodable {
    let email: String
}
