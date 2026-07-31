import XCTest

/// UI smoke tests for the Fantasy Draft Assistant app.
///
/// Note: the league list calls the backend on appear.  With no backend running
/// the app still renders the "Your Leagues" screen with an error toast, so the
/// launch assertions below hold either way.
final class FantasyDraftAssistantUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesToLeagueList() throws {
        let app = XCUIApplication()
        app.launch()

        // The dashboard title is always visible on first launch.
        XCTAssertTrue(
            app.navigationBars["Draft Assistant"].waitForExistence(timeout: 5),
            "The league dashboard should appear on launch"
        )
        // Section headers can be exposed as headers rather than staticTexts on
        // some OS versions, so wait and accept either kind.
        let leaguesHeader = app.staticTexts["Your Leagues"].firstMatch
        XCTAssertTrue(
            leaguesHeader.waitForExistence(timeout: 5) ||
            app.otherElements["Your Leagues"].firstMatch.waitForExistence(timeout: 2)
        )
    }

    @MainActor
    func testCreateLeagueButtonPresent() throws {
        let app = XCUIApplication()
        app.launch()

        let createButton = app.buttons["Create league"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
    }
}
