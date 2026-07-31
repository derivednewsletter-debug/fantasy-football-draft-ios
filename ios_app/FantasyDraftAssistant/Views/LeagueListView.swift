import SwiftUI

/// Dashboard listing all leagues with status badges and quick-create.
struct LeagueListView: View {
    @Environment(DraftViewModel.self) private var vm

    @State private var newName = ""
    @State private var newTeams = 12
    @State private var newUserTeam = 1
    @State private var newScoring = "PPR"
    @State private var path: [String] = []

    private let scoringOptions = ["PPR", "0.5_PPR", "Standard", "2QB/Superflex"]

    var body: some View {
        @Bindable var vm = vm
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(vm.leagues) { league in
                        NavigationLink(value: league.name) {
                            leagueRow(league)
                        }
                    }
                } header: {
                    Text("Your Leagues")
                        .textCase(.uppercase)
                        .font(.caption.weight(.semibold))
                }
            }
            .navigationTitle("Draft Assistant")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        vm.showCreateLeague = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Create league")
                }
            }
            .navigationDestination(for: String.self) { leagueName in
                DraftRoomView(leagueName: leagueName)
            }
            .refreshable { await vm.loadLeagues() }
            .task { await vm.loadLeagues() }
            .sheet(isPresented: $vm.showCreateLeague) {
                createSheet
            }
            .overlay(alignment: .bottom) { NoticeBanner(vm: vm) }
        }
    }

    private func leagueRow(_ league: LeagueSummary) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(league.isUserOnClock ? Color.green.opacity(0.2) : Color.blue.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "football.fill")
                    .foregroundStyle(league.isUserOnClock ? .green : .blue)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(league.name)
                    .font(.headline)
                Text(league.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if league.isUserOnClock {
                Text("ON THE CLOCK")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .clipShape(Capsule())
                    .foregroundStyle(.green)
            } else {
                Text("Team \(league.userTeamNumber)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    private var createSheet: some View {
        NavigationStack {
            Form {
                Section("League Name") {
                    TextField("e.g. Friday Night Legends", text: $newName)
                }

                Section("Settings") {
                    Stepper("Teams: \(newTeams)", value: $newTeams, in: 2...32)
                    Stepper("Your pick: #\(newUserTeam)", value: $newUserTeam, in: 1...newTeams)
                    Picker("Scoring", selection: $newScoring) {
                        ForEach(scoringOptions, id: \.self) { Text($0) }
                    }
                }
            }
            .navigationTitle("New League")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { vm.showCreateLeague = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await vm.createLeague(name: newName, numTeams: newTeams,
                                                     userTeam: newUserTeam, scoring: newScoring) }
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Small toast banner used on every screen.
struct NoticeBanner: View {
    let vm: DraftViewModel

    var body: some View {
        if let message = vm.notice {
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(vm.noticeIsError ? Color.red.opacity(0.9) : Color.green.opacity(0.9))
                .clipShape(Capsule())
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task {
                    try? await Task.sleep(for: .seconds(2.5))
                    vm.notice = nil
                }
        }
    }
}
