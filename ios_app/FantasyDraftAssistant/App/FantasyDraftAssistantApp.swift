import SwiftUI

@main
struct FantasyDraftAssistantApp: App {
    @State private var viewModel = DraftViewModel()
    @State private var authViewModel = AuthViewModel()

    init() {
        // UI tests launch with -uiTestReset so every test starts at the
        // sign-in screen regardless of tokens persisted by earlier tests.
        if ProcessInfo.processInfo.arguments.contains("-uiTestReset") {
            UserDefaults.standard.removeObject(forKey: "authToken")
            UserDefaults.standard.removeObject(forKey: "authEmail")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authViewModel.isAuthenticated {
                    LeagueListView()
                        .environment(viewModel)
                } else {
                    AuthView()
                        .environment(authViewModel)
                }
            }
            // Both view models are available on every screen so 401s can
            // bounce back to the sign-in gate.
            .environment(authViewModel)
            .environment(viewModel)
            .preferredColorScheme(.dark)
            .onAppear {
                // Expired/revoked tokens return to the sign-in screen, and
                // any previous user's draft data is cleared first.
                viewModel.onSessionExpired = { [weak authViewModel, weak viewModel] in
                    authViewModel?.signOut()
                    viewModel?.reset()
                }
            }
        }
    }
}
