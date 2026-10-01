import XCTest
@testable import PsstMap

/// Matching a place to its Apple Maps entry by name.
@MainActor
final class VisitorInfoTests: XCTestCase {
    private func matches(_ apple: String, _ ours: String) -> Bool {
        VisitorInfoLookup.matches(VisitorInfoLookup.normalize(apple), [VisitorInfoLookup.normalize(ours)])
    }

    func testSameThingUnderSlightlyDifferentNames() {
        XCTAssertTrue(matches("The George Inn", "George Inn"))
        XCTAssertTrue(matches("Belsize Park", "Belsize Park station"))
        XCTAssertTrue(matches("Shakespeare’s Globe Theatre", "Shakespeare's Globe"))
        XCTAssertTrue(matches("Café Royal", "Cafe Royal"))
        XCTAssertTrue(matches("和平饭店北楼", "和平饭店"))
    }

    func testNeighborsAreNotMatched() {
        XCTAssertFalse(matches("HSBC Bank", "Bank"))
        XCTAssertFalse(matches("Pret A Manger", "Bank station"))
        XCTAssertFalse(matches("", "Bank"))
    }
}
