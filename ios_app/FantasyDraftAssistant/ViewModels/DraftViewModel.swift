import Foundation
import Observation

/// Drives the whole draft experience: league list, live state, picks, AI recs.
@Observable
@MainActor
final class DraftViewModel {

    // MARK: - State

    private(set) var leagues: [LeagueSummary] = []
    private(set) var state: LeagueState?
    private(set) var recommendations: RecommendationsResponse?

    var selectedLeagueName: String?
    var quickPickText = ""
    var showCreateLeague = false
    var isRefreshing = false

    /// Toast-style banner message.
    var notice: String?
    var noticeIsError = false

    /// True while the live WebSocket feed for the open league is connected.
    private(set) var isLiveConnected = false

    private let api = APIService()
    private let ws = WebSocketManager()

    /// REST polling fallback for serverless deployments (Vercel has no
    /// WebSockets): refreshes state on a timer whenever the socket is down,
    /// so picks made by other devices still show up.
    private var pollTask: Task<Void, Never>?

    // MARK: - League list

    func loadLeagues() async {
        do {
            leagues = try await api.listLeagues()
        } catch {
            presentError(error)
        }
    }

    func createLeague(name: String, numTeams: Int, userTeam: Int, scoring: String) async {
        do {
            let summary = try await api.createLeague(
                LeagueCreate(name: name, numTeams: numTeams,
                             userTeamNumber: userTeam, scoringFormat: scoring)
            )
            leagues.append(summary)
            showCreateLeague = false
            presentNotice("League '\(summary.name)' created")
        } catch {
            presentError(error)
        }
    }

    // MARK: - Draft room

    func openLeague(_ name: String) async {
        selectedLeagueName = name
        recommendations = nil  // never show a previous league's AI picks
        await loadState()
        connectLive(name)
    }

    /// Subscribe to the live draft feed so picks from other devices show up
    /// in real time without pull-to-refresh.  Also starts the REST polling
    /// fallback, which only fetches while the socket isn't connected.
    private func connectLive(_ name: String) {
        ws.onState = { [weak self] state in
            self?.state = state
            self?.quickPickText = ""
        }
        ws.onStatusChange = { [weak self] connected in
            self?.isLiveConnected = connected
        }
        ws.connect(league: name)
        startPollFallback()
    }

    /// Close the live feed (called when leaving the draft room).
    func disconnectLive() {
        pollTask?.cancel()
        pollTask = nil
        ws.disconnect()
        isLiveConnected = false
    }

    // MARK: - Polling fallback (serverless deployments)

    private func startPollFallback() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard let self, !Task.isCancelled else { return }
                // Only poll while the live socket isn't keeping us in sync.
                if !self.isLiveConnected {
                    await self.refreshStateQuietly()
                }
            }
        }
    }

    /// Fetch the latest state without touching `isRefreshing` (so the
    /// spinner doesn't flash every few seconds during background polling).
    private func refreshStateQuietly() async {
        guard let name = selectedLeagueName else { return }
        do {
            state = try await api.leagueState(name)
            quickPickText = ""
        } catch {
            // Silence transient failures — the next poll retries.
        }
    }

    func loadState() async {
        guard let name = selectedLeagueName else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            state = try await api.leagueState(name)
            quickPickText = ""
        } catch {
            presentError(error)
        }
    }

    func makePick(_ playerName: String) async {
        guard let name = selectedLeagueName else { return }
        do {
            let result = try await api.makePick(name, playerName: playerName)
            if result.success {
                presentNotice("\(result.pick?.playerName ?? "Pick") drafted")
                await loadState()
            } else {
                presentError(result.error ?? "Pick failed")
            }
        } catch {
            presentError(error)
        }
    }

    func undoLastPick() async {
        guard let name = selectedLeagueName else { return }
        do {
            let result = try await api.undoPick(name)
            if result.success {
                presentNotice("Last pick undone")
                await loadState()
            } else {
                presentError(result.error ?? "Nothing to undo")
            }
        } catch {
            presentError(error)
        }
    }

    // MARK: - AI recommendations

    func loadRecommendations(forceAI: Bool = true) async {
        guard let name = selectedLeagueName else { return }
        do {
            recommendations = try await api.recommendations(name, ai: forceAI)
        } catch {
            presentError(error)
        }
    }

    // MARK: - Helpers

    /// Players matching the quick-pick text (auto-complete suggestions).
    var filteredSuggestions: [Player] {
        guard let state, !quickPickText.isEmpty else { return [] }
        let q = quickPickText.lowercased()
        return state.availablePlayers
            .filter { $0.name.lowercased().contains(q) || $0.team.lowercased().contains(q) }
            .prefix(8)
            .map { $0 }
    }

    private func presentNotice(_ message: String) {
        notice = message
        noticeIsError = false
    }

    private func presentError(_ error: Error) {
        notice = error.localizedDescription
        noticeIsError = true
    }
}
