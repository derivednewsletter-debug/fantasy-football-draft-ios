import Foundation

/// One recommended player from the engine (VBD or AI).
struct Recommendation: Codable, Identifiable, Hashable {
    var id: String { "\(name)-\(position)" }
    let name: String
    let position: String
    let team: String
    let projectedPoints: Double
    let adp: Double
    let vbd: Double?
    let score: Double?
    let turnLossPct: Double?
    let rationale: String?

    var positionEnum: Position? { Position(rawValue: position) }

    /// "Turn Probability" flag text shown on the AI card.
    var turnProbabilityText: String? {
        guard let pct = turnLossPct else { return nil }
        if pct <= 20 { return "Safe — likely still on the board" }
        if pct <= 50 { return "Reasonable chance he's gone" }
        return "At risk — draft him now"
    }
}

/// Response of GET /leagues/{id}/recommendations.
struct RecommendationsResponse: Codable, Hashable {
    let safePicks: [Recommendation]
    let upsidePicks: [Recommendation]
    let sleepers: [Recommendation]
    let allRanked: [Recommendation]
    let picksBeforeUser: Int
    let aiAnalysis: String?
    let aiTopTarget: Recommendation?
}
