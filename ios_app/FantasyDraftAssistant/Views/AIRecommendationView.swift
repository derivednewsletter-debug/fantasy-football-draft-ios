import SwiftUI

/// AI Recommendation card view — top safe/upside/sleeper picks + turn flags.
struct AIRecommendationView: View {
    let state: LeagueState
    @Binding var showAISheet: Bool
    @Environment(DraftViewModel.self) private var vm

    private var recs: RecommendationsResponse? { vm.recommendations }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Context header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Optimizing for your Team #\(state.userTeamNumber)")
                        .font(.subheadline.weight(.semibold))
                    Text(state.isUserOnClock
                         ? "You're on the clock — here's the read:"
                         : "\(state.picksBeforeUser) pick(s) before your turn.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)

                if let recs {
                    if let analysis = recs.aiAnalysis, !analysis.isEmpty {
                        aiAnalysisCard(analysis)
                    }

                    cardSection(title: "Safe Floor", icon: "shield.checkered",
                                accent: .green, recs: recs.safePicks)
                    cardSection(title: "High Upside", icon: "chart.line.uptrend.xyaxis",
                                accent: .blue, recs: recs.upsidePicks)
                    cardSection(title: "Sleeper Values", icon: "eye",
                                accent: .purple, recs: recs.sleepers)
                } else {
                    ProgressView("Running the draft engine…")
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(.vertical, 12)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                showAISheet = true
            } label: {
                Label("Full AI Breakdown", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.purple)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
        }
        .task { await vm.loadRecommendations() }
        .refreshable { await vm.loadRecommendations() }
    }

    private func aiAnalysisCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
            Text(text)
                .font(.subheadline)
        }
        .padding(14)
        .background(Color.purple.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    private func cardSection(title: String, icon: String, accent: Color,
                             recs: [Recommendation]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(accent)
                Text(title)
                    .font(.headline)
                Spacer()
                Text("TOP 3")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(accent.opacity(0.8))
            }

            ForEach(recs) { rec in
                recommendationCard(rec, accent: accent)
            }
        }
        .padding(.horizontal, 16)
    }

    private func recommendationCard(_ rec: Recommendation, accent: Color) -> some View {
        HStack(spacing: 12) {
            // Turn probability gauge
            VStack(spacing: 2) {
                if let pct = rec.turnLossPct {
                    Text("\(Int(pct))%")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(pct <= 25 ? .green : (pct <= 50 ? .orange : .red))
                    Text("gone risk")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 48)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(rec.name)
                        .font(.subheadline.weight(.bold))
                    PositionBadge(position: rec.position)
                }
                HStack(spacing: 8) {
                    Text(rec.team)
                    if let vbd = rec.vbd {
                        Text("VBD +\(vbd, specifier: "%.1f")")
                    }
                    if let pts = rec.score {
                        Text("Score \(pts, specifier: "%.1f")")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if let flag = rec.turnProbabilityText {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                        Text(flag)
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(accent)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
