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
        // The header uses .textCase(.uppercase), so it is exposed as
        // "YOUR LEAGUES".  Section headers can also surface as otherElements
        // rather than staticTexts on some OS versions — accept any of the
        // four combinations (case × element kind).
        let uppercased = app.staticTexts["YOUR LEAGUES"].firstMatch
        let titleCased = app.staticTexts["Your Leagues"].firstMatch
        XCTAssertTrue(
            uppercased.waitForExistence(timeout: 5) ||
            app.otherElements["YOUR LEAGUES"].firstMatch.waitForExistence(timeout: 2) ||
            titleCased.waitForExistence(timeout: 1),
            "The league dashboard should show the 'Your Leagues' section header"
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
