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

        // The scope menu above the feed opens with one tap.
        let scope = app.buttons["Showing places from Everywhere"]
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        scope.tap()
        XCTAssertTrue(app.buttons["Near me"].waitForExistence(timeout: 5))
        app.buttons["Everywhere"].firstMatch.tap()
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

    @MainActor
    func testPlaceCardOpensPageAndThreeDMapInOneTap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed", "YES", "-debug.place", "london-city/tower-bridge"]
        app.launch()
        try XCTSkipIf(app.buttons["Try again"].waitForExistence(timeout: 3), "No area files in Content/areas")

        // The floating area picker above the map responds to a single tap.
        let areaPicker = app.buttons["Area: City of London"]
        XCTAssertTrue(areaPicker.waitForExistence(timeout: 10))
        areaPicker.tap()
        XCTAssertTrue(app.navigationBars["Areas"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()

        // So do the floating map buttons.
        app.buttons["Map key"].tap()
        XCTAssertTrue(app.navigationBars["Map key"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()

        // Tapping the card opens the place page.
        let card = app.staticTexts["Tower Bridge"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        let threeD = app.buttons["3D map"].firstMatch
        XCTAssertTrue(threeD.waitForExistence(timeout: 10))

        // One tap on 3D map opens it full screen, and one tap closes it again.
        threeD.tap()
        XCTAssertTrue(app.staticTexts["3D map. Drag to look around."].waitForExistence(timeout: 5))
        app.buttons["aerial.close"].tap()
        XCTAssertTrue(threeD.waitForHittable(timeout: 5))

        // Look Around, where Apple has it, opens in one tap as well.
        let lookAround = app.buttons["Look Around"].firstMatch
        if lookAround.waitForExistence(timeout: 8) {
            XCTAssertTrue(lookAround.waitForHittable(timeout: 3))
            lookAround.tap()
            sleep(2)
            XCTAssertFalse(threeD.isHittable, "Look Around should cover the place page")
        }
    }
}

private extension XCUIElement {
    func waitForHittable(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
