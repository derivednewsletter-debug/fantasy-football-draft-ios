import SwiftUI

/// League hub — the landing screen when you open a league from the list.
///
/// Shows the league's overview (scoring, on-the-clock team, your roster)
/// and a single prominent action to *enter* the draft room, so the draft
/// is a deliberate step rather than an automatic jump.
struct LeagueHubView: View {
    @Environment(DraftViewModel.self) private var vm
    let leagueName: String

    var body: some View {
        Group {
            if let state = vm.state {
                content(state)
            } else {
                ProgressView("Loading league…")
            }
        }
        .navigationTitle(leagueName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await vm.loadLeagueOverview(leagueName) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(vm.isRefreshing)
            }
        }
        .task { await vm.loadLeagueOverview(leagueName) }
        .overlay(alignment: .bottom) { NoticeBanner(vm: vm) }
    }

    // MARK: - Content

    private func content(_ state: LeagueState) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // League info card
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(state.scoringFormat, systemImage: "list.number")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(state.numTeams) teams")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        statusBadge(state)
                        Text("You're Team #\(state.userTeamNumber)")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // On the clock card
                onTheClockCard(state)

                // Enter draft button
                NavigationLink {
                    DraftRoomView(leagueName: leagueName)
                } label: {
                    Label("Enter Draft Room", systemImage: "football.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                // My roster preview
                rosterCard(state)
            }
            .padding(16)
        }
    }

    private func statusBadge(_ state: LeagueState) -> some View {
        let title: String
        let color: Color
        if state.completed {
            title = "Completed"
            color = .gray
        } else if state.isActive {
            title = "Drafting"
            color = .green
        } else {
            title = "Setup"
            color = .orange
        }
        return Text(title)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .clipShape(Capsule())
            .foregroundStyle(color)
    }

    private func onTheClockCard(_ state: LeagueState) -> some View {
        let onClock = state.teams.first { $0.number == state.teamOnClock }
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(state.isUserOnClock ? Color.green.opacity(0.2) : Color.blue.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: "clock.fill")
                    .foregroundStyle(state.isUserOnClock ? .green : .blue)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(state.isUserOnClock ? "You're on the clock!" : "On the clock")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(state.isUserOnClock ? .green : .primary)
                Text(onClock?.name ?? "Team \(state.teamOnClock)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(state.pickHeader)
                    .font(.subheadline.weight(.semibold))
                Text("Overall pick #\(state.overallPick)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func rosterCard(_ state: LeagueState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MY ROSTER")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            if let userTeam = state.userTeam {
                if userTeam.roster.isEmpty {
                    Text("No players drafted yet — the draft is just getting started.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(userTeam.roster) { player in
                        HStack(spacing: 10) {
                            PositionBadge(position: player.position)
                            Text(player.name)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(player.team)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
