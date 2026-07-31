import Foundation

/// Envelope pushed by the backend over the live draft WebSocket.
private struct WSEnvelope: Decodable {
    let type: String
    let leagueId: String?
    let state: LeagueState?
    let detail: String?
}

/// Live draft sync over WebSocket.
///
/// Connects to `ws://<host>/leagues/<league>/ws`, immediately receives the
/// current draft state, then receives a fresh state envelope on every pick or
/// undo pushed by *any* device in the league — no pull-to-refresh needed.
@MainActor
final class WebSocketManager {

    /// Fired with each fresh `LeagueState` pushed by the server.
    var onState: ((LeagueState) -> Void)?
    /// Fired when the connection opens or drops (for the LIVE indicator).
    var onStatusChange: ((Bool) -> Void)?

    private var task: URLSessionWebSocketTask?
    /// Retained for the socket's lifetime — a deallocated session cancels its
    /// tasks, so it must live as long as the connection.
    private var session: URLSession?
    private var leagueName: String?
    private var reconnectAttempts = 0
    private var isIntentionalClose = false

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// Read fresh on every connect so the sign-in screen's backend URL field
    /// takes effect even after the manager was created at app launch.
    private var baseURL: String {
        UserDefaults.standard.string(forKey: "apiBaseURL") ?? "http://127.0.0.1:8000"
    }

    /// Open a live connection to a league's draft feed.
    func connect(league: String) {
        disconnect()  // drop any previous league's socket first

        leagueName = league
        isIntentionalClose = false
        // NOTE: reconnectAttempts is intentionally NOT reset here — it is only
        // reset on a successful message (handle), so the retry cap in
        // scheduleReconnect() actually terminates on a downed server.

        guard let url = wsURL(for: league) else {
            onStatusChange?(false)
            return
        }

        let newSession = URLSession(configuration: .default)
        session = newSession

        // Use the request-based initializer so the bearer token rides in the
        // Authorization header (the backend prefers it) instead of the query
        // string, where it could leak into proxy/access logs. The query param
        // is kept as a harmless fallback for any client that strips headers.
        var request = URLRequest(url: url)
        if let token = UserDefaults.standard.string(forKey: "authToken"), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let socket = newSession.webSocketTask(with: request)
        task = socket
        socket.resume()
        receiveLoop()
    }

    /// Close the live connection (e.g. when leaving the draft room).
    func disconnect() {
        isIntentionalClose = true
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session = nil
        onStatusChange?(false)
    }

    // MARK: - Receive loop

    private func receiveLoop() {
        // The completion handler runs on a URLSession background queue and is
        // @Sendable — hop back to the main actor before touching any state.
        task?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handle(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handle(text)
                        }
                    @unknown default:
                        break
                    }
                    // Keep listening.
                    self.receiveLoop()
                case .failure:
                    // Connection dropped — reconnect unless we closed it on
                    // purpose.
                    self.task = nil
                    self.session = nil
                    self.onStatusChange?(false)
                    if !self.isIntentionalClose {
                        self.scheduleReconnect()
                    }
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let envelope = try? Self.decoder.decode(WSEnvelope.self, from: data) else {
            return
        }
        guard envelope.type == "state", let state = envelope.state else { return }
        // Any fresh state means the socket is alive.
        reconnectAttempts = 0
        onStatusChange?(true)
        onState?(state)
    }

    // MARK: - Reconnect

    private func scheduleReconnect() {
        // Cap the backoff so we don't hammer a downed server forever.
        guard reconnectAttempts < 5 else { return }
        reconnectAttempts += 1
        let delay = Double(min(1 << reconnectAttempts, 8))  // 2s, 4s, 8s, 8s…
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !self.isIntentionalClose else { return }
            self.connect(league: self.leagueName ?? "")
        }
    }

    // MARK: - URL

    private func wsURL(for league: String) -> URL? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        let encoded = league.addingPercentEncoding(withAllowedCharacters: allowed) ?? league

        let wsBase = baseURL
            .replacingOccurrences(of: "http://", with: "ws://")
            .replacingOccurrences(of: "https://", with: "wss://")

        // The bearer token rides in the Authorization header (set above), so
        // it never appears in the URL or proxy/access logs. No query-param
        // fallback here — the iOS client can always set headers.
        return URLComponents(string: "\(wsBase)/leagues/\(encoded)/ws")?.url
    }
}
