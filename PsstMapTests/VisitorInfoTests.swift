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

    func testHalfANameIsOnlyALooseMatch() {
        let ours = [VisitorInfoLookup.normalize("The George Inn")]
        XCTAssertEqual(VisitorInfoLookup.match(VisitorInfoLookup.normalize("The George"), ours), .loose)
        XCTAssertEqual(VisitorInfoLookup.match(VisitorInfoLookup.normalize("National Trust - George Inn"), ours), .loose)
        XCTAssertEqual(VisitorInfoLookup.match(VisitorInfoLookup.normalize("George Inn"), ours), .strong)
    }

    func testNeighborsAreNotMatched() {
        XCTAssertFalse(matches("HSBC Bank", "Bank"))
        XCTAssertFalse(matches("Pret A Manger", "Bank station"))
        XCTAssertFalse(matches("", "Bank"))
    }
}
