import SwiftUI

/// Fantasy position with the draft-board color coding used across the app.
enum Position: String, Codable, CaseIterable, Identifiable {
    case qb = "QB"
    case rb = "RB"
    case wr = "WR"
    case te = "TE"
    case k = "K"
    case dst = "DST"
    case flex = "FLEX"
    case bench = "BENCH"

    var id: String { rawValue }

    /// Board color per the draft-day spec: QB red, RB green, WR blue, TE yellow.
    var color: Color {
        switch self {
        case .qb: return .red
        case .rb: return .green
        case .wr: return .blue
        case .te: return .yellow
        case .k: return .orange
        case .dst: return .purple
        case .flex, .bench: return .gray
        }
    }

    init?(rawValue: String) {
        switch rawValue.uppercased() {
        case "QB": self = .qb
        case "RB": self = .rb
        case "WR": self = .wr
        case "TE": self = .te
        case "K": self = .k
        case "DST", "DEF": self = .dst
        case "FLEX": self = .flex
        case "BENCH": self = .bench
        default: return nil
        }
    }
}
