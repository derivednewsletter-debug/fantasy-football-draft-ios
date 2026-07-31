import XCTest

/// UI smoke tests for the Fantasy Draft Assistant app.
///
/// The app now opens on the sign-in screen.  Each test creates a fresh
/// account through the UI (unique email per run) and then verifies the
/// league dashboard renders.  Requires the backend to be running at
/// http://127.0.0.1:8000.
final class FantasyDraftAssistantUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launch the app with `-uiTestReset` so every test starts at the
    /// sign-in screen regardless of tokens persisted by earlier tests in
    /// the same run (the app's init clears its auth state on that flag).
    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()
        return app
    }

    /// Fill the auth form, switch to create-account mode, submit, and wait
    /// for the league dashboard.
    @MainActor
    private func createAccountAndReachDashboard(_ app: XCUIApplication) {
        let email = "uitest-\(UUID().uuidString.prefix(8).lowercased())@test.com"

        // Switch to create-account mode (defaults to sign-in).
        let toggle = app.buttons["New here? Create an account"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "The mode toggle should be visible")
        toggle.tap()

        let emailField = app.textFields["authEmailField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5), "The email field should be visible")
        emailField.tap()
        emailField.typeText(email)

        let passwordField = app.secureTextFields["authPasswordField"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5), "The password field should be visible")
        passwordField.tap()
        passwordField.typeText("secret123")

        app.buttons["authSubmitButton"].tap()

        // The dashboard title is always visible once signed in.
        XCTAssertTrue(
            app.navigationBars["Draft Assistant"].waitForExistence(timeout: 10),
            "The league dashboard should appear after creating an account"
        )
    }

    @MainActor
    func testAppLaunchesToLeagueList() throws {
        let app = launchApp()

        createAccountAndReachDashboard(app)

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
        let app = launchApp()

        createAccountAndReachDashboard(app)

        let createButton = app.buttons["Create league"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
    }

    @MainActor
    func testSignInRejectsWrongPassword() throws {
        let app = launchApp()

        let emailField = app.textFields["authEmailField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5), "The email field should be visible")
        emailField.tap()
        emailField.typeText("nobody-\(UUID().uuidString.prefix(8))@test.com")

        let passwordField = app.secureTextFields["authPasswordField"]
        passwordField.tap()
        passwordField.typeText("definitely-wrong")

        app.buttons["authSubmitButton"].tap()

        // Wrong credentials never reach the dashboard — the error text appears
        // and the sign-in form stays.
        XCTAssertTrue(
            app.staticTexts["Invalid email or password"].waitForExistence(timeout: 10),
            "Wrong credentials should show an error on the sign-in screen"
        )
        XCTAssertFalse(app.navigationBars["Draft Assistant"].exists)
    }
}
