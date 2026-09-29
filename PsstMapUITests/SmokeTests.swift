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
        XCTAssertTrue(app.buttons["Full-screen map"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Full-screen map"].firstMatch.waitForNonExistence(timeout: 5))

        app.tabBars.buttons["Saved"].tap()
        XCTAssertTrue(app.staticTexts["Saved"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPlaceCardOpensPageAndThreeDMapInOneTap() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed", "YES", "-debug.place", "london-city/tower-bridge"]
        app.launch()
        try XCTSkipIf(app.buttons["Try again"].waitForExistence(timeout: 3), "No area files in Content/areas")

        // Story chips filter the map in one tap, and "All stories" undoes it.
        let popChip = app.buttons["Pop culture"].firstMatch
        XCTAssertTrue(popChip.waitForExistence(timeout: 10))
        popChip.tap()
        app.buttons["All stories"].firstMatch.tap()

        // The filter sheet opens, and choosing a story type there doesn't crash.
        app.buttons["Filter"].tap()
        XCTAssertTrue(app.navigationBars["Filter"].waitForExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Pop culture, '")).firstMatch.tap()
        app.buttons["Show all"].firstMatch.tap()
        app.buttons["Done"].tap()

        // Search finds a place and shows it on the map.
        let search = app.buttons["Search places"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Tower Bridge")
        let result = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tower Bridge'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()

        // Tapping the card opens the place page.
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tower Bridge' OR label CONTAINS ', Tower Bridge'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        let threeD = app.buttons["Full-screen map"].firstMatch
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
