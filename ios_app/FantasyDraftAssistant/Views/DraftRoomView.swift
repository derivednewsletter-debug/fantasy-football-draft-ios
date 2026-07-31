import SwiftUI

/// The live draft room — banner, quick-pick bar, and the three tabs.
struct DraftRoomView: View {
    @Environment(DraftViewModel.self) private var vm
    let leagueName: String

    @State private var selectedTab: DraftTab = .board
    @State private var showAISheet = false

    enum DraftTab: String, CaseIterable, Identifiable {
        case board = "Draft Board"
        case roster = "My Roster"
        case ai = "AI Picks"
        var id: String { rawValue }
    }

    var body: some View {
        @Bindable var vm = vm
        Group {
            if let state = vm.state {
                VStack(spacing: 0) {
                    onTheClockBanner(state)
                    quickPickBar(state)
                    TabView(selection: $selectedTab) {
                        DraftBoardGridView(state: state)
                            .tabItem { Label("Board", systemImage: "rectangle.grid.2x2") }
                            .tag(DraftTab.board)
                        MyRosterView(state: state)
                            .tabItem { Label("My Roster", systemImage: "person.crop.circle") }
                            .tag(DraftTab.roster)
                        AIRecommendationView(state: state, showAISheet: $showAISheet)
                            .tabItem { Label("AI Picks", systemImage: "sparkles") }
                            .tag(DraftTab.ai)
                    }
                }
            } else {
                ProgressView("Loading draft state…")
            }
        }
        .navigationTitle(stateTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 10) {
                    if vm.isLiveConnected {
                        HStack(spacing: 4) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 8))
                            Text("LIVE")
                                .font(.caption2.weight(.heavy))
                        }
                        .foregroundStyle(.green)
                        .transition(.opacity)
                    }
                    Button {
                        Task { await vm.loadState() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(vm.isRefreshing)
                }
            }
        }
        .task { await vm.openLeague(leagueName) }
        .onDisappear { vm.disconnectLive() }
        .sheet(isPresented: $showAISheet) {
            AISuggestionSheet()
        }
        .overlay(alignment: .bottom) { NoticeBanner(vm: vm) }
    }

    private var stateTitle: String {
        guard let s = vm.state else { return leagueName }
        return "\(leagueName) · \(s.pickHeader)"
    }

    // MARK: - On the Clock banner

    @ViewBuilder
    private func onTheClockBanner(_ state: LeagueState) -> some View {
        let onClock = state.teams.first { $0.number == state.teamOnClock }

        VStack(alignment: .leading, spacing: 12) {
            if state.isUserOnClock {
                HStack(spacing: 8) {
                    Image(systemName: "alarm.waves.left.and.right.fill")
                    Text("YOU ARE ON THE CLOCK")
                        .font(.headline.weight(.heavy))
                    Spacer()
                    LiveDot()
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.green)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                HStack {
                    Text("ON THE CLOCK")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if state.picksBeforeUser == 0 {
                        Text("Next: you pick!")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.green)
                    } else {
                        Text("\(state.picksBeforeUser) pick(s) until you draft")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.pickHeader)
                        .font(.title3.weight(.bold))
                    Text("Overall pick #\(state.overallPick) · \(state.scoringFormat)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(onClock?.name ?? "Team \(state.teamOnClock)")
                        .font(.headline)
                    HStack(spacing: 4) {
                        Image(systemName: "football.fill")
                            .foregroundStyle(state.isUserOnClock ? .green : .blue)
                        Text("Team #\(state.teamOnClock)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Quick pick bar

    private func quickPickBar(_ state: LeagueState) -> some View {
        @Bindable var vm = vm
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Auto-complete field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Quick pick a player…", text: $vm.quickPickText)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                }

                Button {
                    let name = vm.quickPickText.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    Task { await vm.makePick(name) }
                } label: {
                    Text("Draft")
                        .fontWeight(.bold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                }
                .disabled(vm.quickPickText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !vm.filteredSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.filteredSuggestions) { player in
                            Button {
                                Task { await vm.makePick(player.name) }
                            } label: {
                                suggestionChip(player)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    Task { await vm.undoLastPick() }
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Button {
                    showAISheet = true
                    Task { await vm.loadRecommendations() }
                } label: {
                    Label("AI Insight", systemImage: "sparkles")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.purple.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private func suggestionChip(_ player: Player) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(player.positionEnum?.color ?? .gray)
                .frame(width: 8, height: 8)
            Text(player.name)
                .font(.footnote.weight(.medium))
            Text(player.position)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemBackground))
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        }
    }
}

/// Pulsing green live dot.
struct LiveDot: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: 10, height: 10)
            .opacity(pulsing ? 0.3 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    pulsing.toggle()
                }
            }
    }
}

/// The AI recommendation sheet shown from the quick pick bar.
struct AISuggestionSheet: View {
    @Environment(DraftViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let recs = vm.recommendations {
                    List {
                        if let analysis = recs.aiAnalysis, !analysis.isEmpty {
                            Section {
                                Text(analysis)
                                    .font(.subheadline)
                            } header: {
                                Label("AI Analysis", systemImage: "sparkles")
                            }
                        }
                        if let top = recs.aiTopTarget {
                            Section {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(top.name).font(.headline)
                                        PositionBadge(position: top.position)
                                        Spacer()
                                        Text("TOP TARGET")
                                            .font(.caption2.weight(.heavy))
                                            .foregroundStyle(.purple)
                                    }
                                    if let r = top.rationale {
                                        Text(r).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            } header: {
                                Label("Best Pick Right Now", systemImage: "target")
                            }
                        }
                        recommendationSection("Safe Floor", recs.safePicks, icon: "shield.checkered")
                        recommendationSection("High Upside", recs.upsidePicks, icon: "chart.line.uptrend.xyaxis")
                        recommendationSection("Sleeper Values", recs.sleepers, icon: "eye")
                    }
                } else {
                    ProgressView("Consulting the draft engine…")
                        .task { await vm.loadRecommendations() }
                }
            }
            .navigationTitle("AI Smart Picks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func recommendationSection(_ title: String, _ recs: [Recommendation],
                                       icon: String) -> some View {
        Section {
            ForEach(recs) { rec in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(rec.positionEnum?.color ?? .gray)
                        .frame(width: 10, height: 10)
                        .padding(.top, 5)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(rec.name).font(.subheadline.weight(.semibold))
                            PositionBadge(position: rec.position)
                        }
                        HStack(spacing: 8) {
                            Text("\(rec.team)")
                            if let pts = rec.vbd {
                                Text("VBD +\(pts, specifier: "%.1f")")
                            }
                            if let pct = rec.turnLossPct {
                                Text("\(Int(pct))% gone risk")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if let rationale = rec.rationale {
                            Text(rationale)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Label(title, systemImage: icon)
        }
    }
}

/// Small rounded position tag.
struct PositionBadge: View {
    let position: String

    var body: some View {
        Text(position)
            .font(.caption2.weight(.heavy))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((Position(rawValue: position)?.color ?? .gray).opacity(0.25))
            .clipShape(Capsule())
    }
}
