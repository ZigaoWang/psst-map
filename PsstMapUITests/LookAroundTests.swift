import XCTest

/// Look Around opens full screen with one close button, and closing it returns to the place page.
final class LookAroundTests: XCTestCase {
    @MainActor
    func testLookAroundHasOneCloseButtonAndCloses() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed", "YES", "-debug.place", "pl_6k7hqpej99", "-debug.detail", "YES",
                               "-debug.lookAround", "YES"]
        app.launch()
        let walk = app.buttons["Walk here"]
        // Look Around opens over the page once its scene loads; the page's buttons are then hidden.
        XCTAssertTrue(walk.waitForExistence(timeout: 20))
        let deadline = Date().addingTimeInterval(30)
        while walk.isHittable && Date() < deadline { sleep(1) }
        XCTAssertFalse(walk.isHittable, "Look Around opened over the page")
        sleep(3)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "look-around"
        shot.lifetime = .keepAlways
        add(shot)

        // MapKit's own close button, the only hittable one while Look Around is open.
        let close = app.buttons.matching(NSPredicate(format: "label IN {'Close', 'Done', 'close'}")).allElementsBoundByIndex
            .filter(\.isHittable)
        XCTAssertEqual(close.count, 1, "exactly one close button over Look Around")
        close.first?.tap()
        XCTAssertTrue(walk.waitForExistence(timeout: 10) && walk.isHittable, "back on the place page")
        // At once, before anything could repaint it: the page must already be in the phone's appearance.
        let first = XCTAttachment(screenshot: app.screenshot())
        first.name = "right-after-closing"
        first.lifetime = .keepAlways
        add(first)
        sleep(2)
        let back = XCTAttachment(screenshot: app.screenshot())
        back.name = "after-closing"
        back.lifetime = .keepAlways
        add(back)
    }

    @MainActor
    func testOpeningLookAroundDoesNotDarkenThePage() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed", "YES", "-debug.place", "pl_6k7hqpej99", "-debug.detail", "YES"]
        app.launch()
        let button = app.buttons["Look Around"]
        XCTAssertTrue(button.waitForExistence(timeout: 30))
        button.tap()
        for n in 0..<4 {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "opening-\(n)"
            shot.lifetime = .keepAlways
            add(shot)
        }
    }
}
