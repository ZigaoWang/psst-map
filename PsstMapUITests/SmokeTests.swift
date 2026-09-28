import XCTest

/// Launches the app and walks through the main screens.
final class SmokeTests: XCTestCase {
    @MainActor
    func testFirstLaunchShowsWelcomeThenTabs() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed", "NO"]
        app.launch()
        let start = app.buttons["Start exploring"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        XCTAssertTrue(app.tabBars.buttons["Map"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testTabsAndFeedOpenDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed", "YES"]
        app.launch()
        // Without content installed the app shows its load error instead of tabs.
        try XCTSkipIf(app.buttons["Try again"].waitForExistence(timeout: 3), "No area files in Content/areas")

        let feedTab = app.tabBars.buttons["Feed"]
        XCTAssertTrue(feedTab.waitForExistence(timeout: 10))
        feedTab.tap()
        let card = app.descendants(matching: .any).matching(identifier: "feed.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        XCTAssertTrue(app.buttons["3D map"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["3D map"].firstMatch.waitForNonExistence(timeout: 5))

        app.tabBars.buttons["Saved"].tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 5))
        app.buttons["About Psst"].tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 5))
    }
}
