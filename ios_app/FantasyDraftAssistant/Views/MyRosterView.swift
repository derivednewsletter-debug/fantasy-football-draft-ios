import SwiftUI

/// The user's roster — starters laid out by slot, bench below, gaps highlighted.
struct MyRosterView: View {
    let state: LeagueState

    private var userTeam: Team? { state.userTeam }

    /// Ordered starter slots (excluding bench), from the roster config.
    private var starterSlots: [String] {
        let order = ["QB", "RB", "WR", "TE", "FLEX", "K", "DST"]
        let slots = state.rosterSlots
        var result: [String] = []
        for pos in order {
            for _ in 0..<(slots[pos] ?? 0) {
                result.append(pos)
            }
        }
        return result
    }

    private var benchSize: Int { state.rosterSlots["BENCH"] ?? 6 }

    // NOTE: display-only heuristic — the roster is pick-ordered, so the first
    // N picks are shown as starters. A future backend could return explicit
    // start/sit designations for accuracy.
    private var starters: [Player] { Array(userTeam?.roster.prefix(starterSlots.count) ?? []) }
    private var bench: [Player] { Array(userTeam?.roster.dropFirst(starterSlots.count) ?? []) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let team = userTeam {
                    HStack {
                        Text(team.name)
                            .font(.headline)
                        Spacer()
                        Text("\(team.roster.count) drafted")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)

                    // Starters, one row per slot
                    VStack(spacing: 8) {
                        ForEach(Array(starterSlots.enumerated()), id: \.offset) { index, slot in
                            let player = index < starters.count ? starters[index] : nil
                            slotRow(slot: slot, player: player)
                        }
                    }
                    .padding(.horizontal, 16)

                    // Bench
                    VStack(alignment: .leading, spacing: 8) {
                        Text("BENCH (\(bench.count)/\(benchSize))")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)

                        ForEach(0..<benchSize, id: \.self) { index in
                            let player = index < bench.count ? bench[index] : nil
                            benchRow(player: player)
                        }
                    }
                    .padding(.horizontal, 16)
                } else {
                    ContentUnavailableView(
                        "No roster yet",
                        systemImage: "person.2.slash",
                        description: Text("Picks will appear here once the draft begins.")
                    )
                }
            }
            .padding(.vertical, 12)
        }
    }

    private func slotRow(slot: String, player: Player?) -> some View {
        HStack(spacing: 12) {
            Text(slot)
                .font(.caption.weight(.heavy))
                .foregroundStyle(.white)
                .frame(width: 46, height: 28)
                .background(Position(rawValue: slot)?.color ?? .gray)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            if let player {
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.name).font(.subheadline.weight(.semibold))
                    Text("\(player.team) · \(player.projectedPoints, specifier: "%.1f") pts")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("Empty — pick a \(slot)")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                Spacer()
                Image(systemName: "plus.circle.dashed")
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(player == nil ? Color.orange.opacity(0.08)
                                  : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(player == nil ? Color.orange.opacity(0.4) : Color.clear, lineWidth: 1)
        }
    }

    private func benchRow(player: Player?) -> some View {
        HStack(spacing: 12) {
            if let player {
                Circle()
                    .fill(player.positionEnum?.color ?? .gray)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.name).font(.subheadline.weight(.medium))
                    Text("\(player.position) · \(player.team)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                Text("Open bench slot")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
