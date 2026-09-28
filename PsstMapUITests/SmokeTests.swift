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
        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testTabsAndFeedOpenDetail() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed", "YES"]
        app.launch()

        let feedTab = app.buttons["Feed"]
        XCTAssertTrue(feedTab.waitForExistence(timeout: 10))
        feedTab.tap()
        let card = app.descendants(matching: .any).matching(identifier: "feed.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        XCTAssertTrue(app.buttons["Read more"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Close"].tap()

        app.buttons["Saved"].tap()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 5))
        app.buttons["About Psst"].tap()
        XCTAssertTrue(app.navigationBars["About"].waitForExistence(timeout: 5))
    }
}
