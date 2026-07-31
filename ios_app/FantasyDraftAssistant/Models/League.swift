import Foundation

/// Lightweight league descriptor for the dashboard list.
struct LeagueSummary: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let numTeams: Int
    let userTeamNumber: Int
    let scoringFormat: String
    let currentRound: Int
    let overallPick: Int
    let isActive: Bool
    let completed: Bool
    let totalPicks: Int
    let teamOnClock: Int

    /// "Drafting — Pick 3.04"-style status badge text.
    var statusText: String {
        if completed { return "Completed" }
        if isActive { return "Drafting — Pick \(currentRound).\(min(overallPick, 99))" }
        return "Setup"
    }

    var isUserOnClock: Bool { teamOnClock == userTeamNumber }
}

/// Payload for creating a new league.
struct LeagueCreate: Codable {
    let name: String
    let numTeams: Int
    let userTeamNumber: Int
    let scoringFormat: String
}

/// One team's roster within the state payload.
struct Team: Codable, Identifiable, Hashable {
    var id: Int { number }
    let number: Int
    let name: String
    let roster: [Player]
    let rosterSlots: [String: Int]
    let waiverMoves: Int
    let faabBudget: Double
    let waiverPriority: Int
}

/// A row of the draft board matrix.
struct MatrixRow: Codable, Identifiable, Hashable {
    var id: Int { number }
    let number: Int
    let name: String
    let roster: [MatrixPlayer]
    let pickCount: Int
}

struct MatrixPlayer: Codable, Hashable {
    let name: String
    let position: String
    let team: String
    let projectedPoints: Double
}

/// Full snapshot of a league's live draft state.
struct LeagueState: Codable, Hashable {
    let name: String
    let numTeams: Int
    let userTeamNumber: Int
    let scoringFormat: String
    let rosterSlots: [String: Int]
    let currentRound: Int
    let currentPickInRound: Int
    let overallPick: Int
    let isActive: Bool
    let completed: Bool
    let teamOnClock: Int
    let isUserOnClock: Bool
    let picksBeforeUser: Int
    let draftLog: [Pick]
    let teams: [Team]
    let availablePlayers: [Player]
    let matrix: [MatrixRow]

    var userTeam: Team? { teams.first { $0.number == userTeamNumber } }

    /// "R 1 · Pick 3 of 12" header text.
    var pickHeader: String { "R\(currentRound) · Pick \(currentPickInRound) of \(numTeams)" }
}
