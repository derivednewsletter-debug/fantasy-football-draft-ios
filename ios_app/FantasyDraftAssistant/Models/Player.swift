import Foundation

/// A fantasy-relevant player (or DST) as returned by the backend.
struct Player: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let position: String
    let team: String
    let projectedPoints: Double
    let adp: Double
    let tier: Int
    var isDrafted: Bool
    var draftedBy: Int?
    var draftedAtPick: Int?

    var positionEnum: Position? { Position(rawValue: position) }
}

/// A pick recorded in the draft log.
struct Pick: Codable, Identifiable, Hashable {
    var id: Int { overallPick }
    let overallPick: Int
    let roundNumber: Int
    let teamNumber: Int
    let playerName: String
    let playerPosition: String
    let playerTeam: String
    let projectedPoints: Double

    var positionEnum: Position? { Position(rawValue: playerPosition) }
}
