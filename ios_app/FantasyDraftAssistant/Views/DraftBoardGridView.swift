import SwiftUI

/// The draft board — every pick in order, color-coded by position.
struct DraftBoardGridView: View {
    let state: LeagueState

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                // Legend
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Position.allCases.filter { $0 != .flex && $0 != .bench }) { pos in
                            HStack(spacing: 5) {
                                Circle().fill(pos.color).frame(width: 9, height: 9)
                                Text(pos.rawValue).font(.caption2.weight(.semibold))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Rounds, pick-by-pick
                ForEach(groupedRounds(), id: \.round) { roundGroup in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Round \(roundGroup.round)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2),
                                  spacing: 6) {
                            ForEach(roundGroup.picks) { pick in
                                pickCell(pick)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }

    private struct RoundGroup: Identifiable {
        var id: Int { round }
        let round: Int
        let picks: [Pick]
    }

    private func groupedRounds() -> [RoundGroup] {
        var byRound: [Int: [Pick]] = [:]
        for pick in state.draftLog {
            byRound[pick.roundNumber, default: []].append(pick)
        }
        return byRound.keys.sorted().map { RoundGroup(round: $0, picks: byRound[$0] ?? []) }
    }

    private func pickCell(_ pick: Pick) -> some View {
        HStack(spacing: 8) {
            Text("#\(pick.overallPick)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(pick.positionEnum?.color ?? .gray)
                        .frame(width: 8, height: 8)
                    Text(pick.playerName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                Text("T\(pick.teamNumber) · \(pick.playerPosition) · \(pick.playerTeam)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(pick.teamNumber == state.userTeamNumber
                    ? Color.green.opacity(0.12)
                    : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(pick.teamNumber == state.userTeamNumber
                        ? Color.green.opacity(0.5) : Color.clear, lineWidth: 1.5)
        }
    }
}
