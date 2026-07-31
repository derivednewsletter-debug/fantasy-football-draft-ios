import Foundation

/// Errors surfaced by the API layer.
enum APIError: LocalizedError {
    case invalidURL
    case http(Int, String)
    case decoding(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid request URL"
        case .http(let code, let detail): return "Server error (\(code)): \(detail)"
        case .decoding(let msg): return "Could not parse response: \(msg)"
        case .network(let msg): return msg
        }
    }
}

/// Async/await networking layer for the Fantasy Draft backend.
///
/// The base URL is read from `UserDefaults["apiBaseURL"]` on every request so
/// the sign-in screen's backend URL field takes effect immediately.  When an
/// account is signed in, its bearer token is attached to every request.
struct APIService {
    /// Point this at your backend (simulator: http://127.0.0.1:8000,
    /// physical device: http://<your-mac-LAN-IP>:8000, or the deployed URL).
    var baseURL: String {
        UserDefaults.standard.string(forKey: "apiBaseURL") ?? "http://127.0.0.1:8000"
    }

    private var authToken: String? {
        UserDefaults.standard.string(forKey: "authToken")
    }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    private func percentEncode(_ leagueName: String) -> String {
        // urlPathAllowed keeps "/" which would split the path segment;
        // strip it (and other separators) so league names can't break routes.
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return leagueName.addingPercentEncoding(withAllowedCharacters: allowed) ?? leagueName
    }

    private func request<T: Decodable>(_ path: String, method: String = "GET",
                                       body: (any Encodable)? = nil,
                                       authenticated: Bool = true) async throws -> T {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated, let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            req.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.network("Cannot reach the draft server. Is the backend running? (\(error.localizedDescription))")
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.network("Invalid response from server")
        }

        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "unknown error"
            throw APIError.http(http.statusCode, detail)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    // MARK: - Auth

    func signup(email: String, password: String) async throws -> AuthResponse {
        try await request("/auth/signup", method: "POST",
                          body: SignupRequest(email: email, password: password),
                          authenticated: false)
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        try await request("/auth/login", method: "POST",
                          body: LoginRequest(email: email, password: password),
                          authenticated: false)
    }

    func logout() async throws {
        let _: EmptyResponse = try await request("/auth/logout", method: "POST")
    }

    func me() async throws -> MeResponse {
        try await request("/auth/me")
    }

    // MARK: - Endpoints

    func health() async throws -> Health {
        try await request("/", authenticated: false)
    }

    func listLeagues() async throws -> [LeagueSummary] {
        try await request("/leagues")
    }

    func createLeague(_ payload: LeagueCreate) async throws -> LeagueSummary {
        try await request("/leagues", method: "POST", body: payload)
    }

    func leagueState(_ league: String) async throws -> LeagueState {
        try await request("/leagues/\(percentEncode(league))/state")
    }

    func makePick(_ league: String, playerName: String) async throws -> PickResult {
        struct Body: Encodable { let playerName: String }
        return try await request("/leagues/\(percentEncode(league))/pick",
                                 method: "POST", body: Body(playerName: playerName))
    }

    func undoPick(_ league: String) async throws -> UndoResult {
        try await request("/leagues/\(percentEncode(league))/undo", method: "POST")
    }

    func recommendations(_ league: String, ai: Bool = true) async throws -> RecommendationsResponse {
        let flag = ai ? "true" : "false"
        return try await request("/leagues/\(percentEncode(league))/recommendations?ai=\(flag)")
    }
}

// MARK: - Result types

struct Health: Decodable {
    let status: String
    let leagues: Int
    let aiAvailable: Bool
}

struct PickResult: Decodable {
    let success: Bool
    let pick: Pick?
    let error: String?
}

struct UndoResult: Decodable {
    let success: Bool
    let error: String?
}

/// Placeholder for endpoints that return `{"success": true}`.
struct EmptyResponse: Decodable {}

// MARK: - Helpers

/// Erase any Encodable to a single concrete type (needed for the generic helper).
private struct AnyEncodable: Encodable {
    private let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
