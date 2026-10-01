import XCTest

/// Typing in search keeps the keyboard up and every character, and finds places.
final class SearchTests: XCTestCase {
    @MainActor
    func testTypingAWholeWordFindsThePlace() {
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed", "YES", "-debug.tab", "map", "-debug.sheet", "search"]
        app.launch()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("harrods")
        XCTAssertEqual(field.value as? String, "harrods", "every character typed stays in the field")
        XCTAssertTrue(app.staticTexts["Harrods"].waitForExistence(timeout: 5), "the place is found")
    }
}
