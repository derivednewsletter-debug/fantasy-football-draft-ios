import SwiftUI

@main
struct FantasyDraftAssistantApp: App {
    @State private var viewModel = DraftViewModel()

    var body: some Scene {
        WindowGroup {
            LeagueListView()
                .environment(viewModel)
                .preferredColorScheme(.dark)
        }
    }
}
