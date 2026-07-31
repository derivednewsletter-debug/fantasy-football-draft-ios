import XCTest
@testable import FantasyDraftAssistant

/// Unit tests for the Codable models that mirror the backend JSON contract.
final class ModelDecodingTests: XCTestCase {

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    private func decode<T: Decodable>(_ json: String, as: T.Type,
                                      file: StaticString = #filePath, line: UInt = #line) throws -> T {
        try decoder.decode(T.self, from: Data(json.utf8))
    }

    // MARK: - LeagueSummary

    func testLeagueSummaryDecoding() throws {
        let json = """
        {"name":"Friday Night Legends","num_teams":12,"user_team_number":4,
         "scoring_format":"PPR","current_round":3,"overall_pick":31,
         "is_active":true,"completed":false,"total_picks":30,"team_on_clock":7}
        """
        let summary: LeagueSummary = try decode(json, as: LeagueSummary.self)
        XCTAssertEqual(summary.name, "Friday Night Legends")
        XCTAssertEqual(summary.numTeams, 12)
        XCTAssertEqual(summary.userTeamNumber, 4)
        XCTAssertEqual(summary.currentRound, 3)
        XCTAssertEqual(summary.overallPick, 31)
        XCTAssertEqual(summary.totalPicks, 30)
        XCTAssertEqual(summary.teamOnClock, 7)
        XCTAssertTrue(summary.isActive)
        XCTAssertFalse(summary.completed)
    }

    func testStatusTextDuringDraft() throws {
        let json = """
        {"name":"L","num_teams":12,"user_team_number":4,"scoring_format":"PPR",
         "current_round":3,"overall_pick":31,"is_active":true,"completed":false,
         "total_picks":30,"team_on_clock":7}
        """
        let summary: LeagueSummary = try decode(json, as: LeagueSummary.self)
        XCTAssertTrue(summary.statusText.contains("Drafting"), summary.statusText)
        XCTAssertTrue(summary.statusText.contains("3"), summary.statusText)
    }

    func testStatusTextCompleted() throws {
        let json = """
        {"name":"L","num_teams":12,"user_team_number":4,"scoring_format":"PPR",
         "current_round":15,"overall_pick":180,"is_active":false,"completed":true,
         "total_picks":180,"team_on_clock":1}
        """
        let summary: LeagueSummary = try decode(json, as: LeagueSummary.self)
        XCTAssertEqual(summary.statusText, "Completed")
    }

    func testUserOnClockDetection() throws {
        let json = """
        {"name":"L","num_teams":12,"user_team_number":7,"scoring_format":"PPR",
         "current_round":1,"overall_pick":7,"is_active":true,"completed":false,
         "total_picks":6,"team_on_clock":7}
        """
        let summary: LeagueSummary = try decode(json, as: LeagueSummary.self)
        XCTAssertTrue(summary.isUserOnClock)
    }

    // MARK: - LeagueState

    func testLeagueStateDecoding() throws {
        let json = """
        {"name":"L","num_teams":2,"user_team_number":1,"scoring_format":"PPR",
         "roster_slots":{"QB":1,"RB":2,"WR":2,"TE":1,"FLEX":1,"K":1,"DST":1,"BENCH":6},
         "current_round":1,"current_pick_in_round":1,"overall_pick":1,
         "is_active":true,"completed":false,"team_on_clock":1,"is_user_on_clock":true,
         "picks_before_user":0,
         "draft_log":[],
         "teams":[
           {"number":1,"name":"Team 1","roster":[],
            "roster_slots":{"QB":1,"RB":2,"WR":2,"TE":1,"FLEX":1,"K":1,"DST":1,"BENCH":6},
            "waiver_moves":0,"faab_budget":100.0,"waiver_priority":999},
           {"number":2,"name":"Team 2","roster":[],
            "roster_slots":{"QB":1,"RB":2,"WR":2,"TE":1,"FLEX":1,"K":1,"DST":1,"BENCH":6},
            "waiver_moves":0,"faab_budget":100.0,"waiver_priority":999}
         ],
         "available_players":[
           {"name":"Patrick Mahomes","position":"QB","team":"KC","projected_points":385.2,
            "adp":12.4,"tier":1,"is_drafted":false,"drafted_by":null,"drafted_at_pick":null}
         ],
         "matrix":[
           {"number":1,"name":"Team 1","roster":[],"pick_count":0},
           {"number":2,"name":"Team 2","roster":[],"pick_count":0}
         ]}
        """
        let state: LeagueState = try decode(json, as: LeagueState.self)
        XCTAssertEqual(state.name, "L")
        XCTAssertEqual(state.numTeams, 2)
        XCTAssertEqual(state.currentRound, 1)
        XCTAssertEqual(state.teamOnClock, 1)
        XCTAssertTrue(state.isUserOnClock)
        XCTAssertEqual(state.picksBeforeUser, 0)
        XCTAssertEqual(state.teams.count, 2)
        XCTAssertEqual(state.availablePlayers.count, 1)
        XCTAssertEqual(state.availablePlayers[0].name, "Patrick Mahomes")
        XCTAssertEqual(state.availablePlayers[0].projectedPoints, 385.2, accuracy: 0.001)
        XCTAssertEqual(state.matrix.count, 2)
        XCTAssertEqual(state.userTeam?.number, 1)
        XCTAssertEqual(state.pickHeader, "R1 · Pick 1 of 2")
    }

    // MARK: - Pick

    func testPickDecoding() throws {
        let json = """
        {"overall_pick":1,"round_number":1,"team_number":1,"player_name":"Patrick Mahomes",
         "player_position":"QB","player_team":"KC","projected_points":385.2}
        """
        let pick: Pick = try decode(json, as: Pick.self)
        XCTAssertEqual(pick.overallPick, 1)
        XCTAssertEqual(pick.playerName, "Patrick Mahomes")
        XCTAssertEqual(pick.positionEnum, .qb)
    }

    // MARK: - Recommendations

    func testRecommendationDecoding() throws {
        let json = """
        {"name":"Bijan Robinson","position":"RB","team":"ATL","projected_points":301.1,
         "adp":3.2,"vbd":45.1,"score":48.9,"turn_loss_pct":35.0,"rationale":"Workhorse."}
        """
        let rec: Recommendation = try decode(json, as: Recommendation.self)
        XCTAssertEqual(rec.name, "Bijan Robinson")
        XCTAssertEqual(rec.vbd ?? 0, 45.1, accuracy: 0.001)
        XCTAssertEqual(rec.turnProbabilityText, "Reasonable chance he's gone")
    }

    func testRecommendationOptionalFieldsNil() throws {
        // AI top-target dicts omit vbd/score/turn_loss_pct — must decode to nil.
        let json = """
        {"name":"Zay Flowers","position":"WR","team":"BAL","projected_points":0,
         "adp":0,"rationale":"Breakout camp."}
        """
        let rec: Recommendation = try decode(json, as: Recommendation.self)
        XCTAssertNil(rec.vbd)
        XCTAssertNil(rec.score)
        XCTAssertNil(rec.turnLossPct)
        XCTAssertEqual(rec.rationale, "Breakout camp.")
    }

    func testRecommendationsResponseDecoding() throws {
        let json = """
        {"safe_picks":[],"upside_picks":[],"sleepers":[],
         "all_ranked":[
           {"name":"Patrick Mahomes","position":"QB","team":"KC","projected_points":385.2,
            "adp":12.4,"vbd":10.0,"score":12.0,"turn_loss_pct":10.0,"rationale":null}
         ],
         "picks_before_user":3,"ai_analysis":null,"ai_top_target":null}
        """
        let resp: RecommendationsResponse = try decode(json, as: RecommendationsResponse.self)
        XCTAssertEqual(resp.picksBeforeUser, 3)
        XCTAssertNil(resp.aiAnalysis)
        XCTAssertNil(resp.aiTopTarget)
        XCTAssertEqual(resp.allRanked.count, 1)
    }

    // MARK: - Position enum

    func testPositionRawValueMapping() {
        XCTAssertEqual(Position(rawValue: "QB"), .qb)
        XCTAssertEqual(Position(rawValue: "RB"), .rb)
        XCTAssertEqual(Position(rawValue: "WR"), .wr)
        XCTAssertEqual(Position(rawValue: "TE"), .te)
        XCTAssertEqual(Position(rawValue: "K"), .k)
        XCTAssertEqual(Position(rawValue: "DST"), .dst)
        XCTAssertEqual(Position(rawValue: "FLEX"), .flex)
        // Case-insensitive custom init
        XCTAssertEqual(Position(rawValue: "qb"), .qb)
        // Backend DEF alias
        XCTAssertEqual(Position(rawValue: "DEF"), .dst)
        // Unknown -> nil
        XCTAssertNil(Position(rawValue: "ZZZ"))
    }

    func testPositionColorCoding() {
        XCTAssertEqual(Position.qb.color, .red)
        XCTAssertEqual(Position.rb.color, .green)
        XCTAssertEqual(Position.wr.color, .blue)
        XCTAssertEqual(Position.te.color, .yellow)
    }

    // MARK: - Turn probability flags

    func testTurnProbabilityBands() {
        let low = Recommendation(name: "A", position: "QB", team: "KC",
                                 projectedPoints: 300, adp: 5, vbd: 10, score: 12,
                                 turnLossPct: 10, rationale: nil)
        let mid = Recommendation(name: "B", position: "RB", team: "ATL",
                                 projectedPoints: 300, adp: 5, vbd: 10, score: 12,
                                 turnLossPct: 45, rationale: nil)
        let high = Recommendation(name: "C", position: "WR", team: "MIN",
                                  projectedPoints: 300, adp: 5, vbd: 10, score: 12,
                                  turnLossPct: 80, rationale: nil)
        XCTAssertEqual(low.turnProbabilityText, "Safe — likely still on the board")
        XCTAssertEqual(mid.turnProbabilityText, "Reasonable chance he's gone")
        XCTAssertEqual(high.turnProbabilityText, "At risk — draft him now")
    }
}
