import XCTest
@testable import PsstMap

/// Content written for a newer app must never break this one.
final class ContentDecodingTests: XCTestCase {
    private func area(spots: String) -> String {
        """
        {"schemaVersion": 1, "id": "test-area", "name": "Test", "city": "Test", "countryCode": "GB",
         "summary": "", "researchedOn": "2026-09-28",
         "bounds": {"south": 51, "west": -1, "north": 52, "east": 1},
         "spots": [\(spots)]}
        """
    }

    private func spot(id: String, kind: String = "building", facts: String) -> String {
        """
        {"id": "\(id)", "name": "\(id)", "kind": "\(kind)", "size": "medium",
         "coordinate": {"latitude": 51.5, "longitude": -0.1},
         "coordinateSource": {"type": "osm", "id": "node/1"}, "facts": [\(facts)]}
        """
    }

    private func fact(id: String, category: String = "history", status: String = "fact") -> String {
        """
        {"id": "\(id)", "category": "\(category)", "status": "\(status)", "headline": "h", "short": "s",
         "long": "l", "sources": [{"title": "t", "publisher": "p", "url": "https://example.com"}]}
        """
    }

    private func decode(_ json: String) throws -> Area {
        try JSONDecoder().decode(Area.self, from: Data(json.utf8))
    }

    func testPopCategoryDecodes() throws {
        let area = try decode(area(spots: spot(id: "a", facts: fact(id: "f", category: "pop"))))
        XCTAssertEqual(area.spots[0].facts[0].category, .pop)
    }

    func testUnknownCategoryFallsBackInsteadOfFailing() throws {
        let area = try decode(area(spots: spot(id: "a", facts: fact(id: "f", category: "food"))))
        XCTAssertEqual(area.spots[0].facts[0].category, .other)
    }

    func testUnknownKindFallsBackInsteadOfFailing() throws {
        let area = try decode(area(spots: spot(id: "a", kind: "lighthouse", facts: fact(id: "f"))))
        XCTAssertEqual(area.spots[0].kind, .other)
        XCTAssertFalse(Spot.Kind.allCases.contains(.other), "The fallback kind must not show up in filters")
    }

    func testFactWithUnknownStatusIsDropped() throws {
        let facts = fact(id: "keep") + "," + fact(id: "drop", status: "rumor")
        let area = try decode(area(spots: spot(id: "a", facts: facts)))
        XCTAssertEqual(area.spots[0].facts.map(\.id), ["keep"])
    }

    func testBrokenSpotIsSkippedAndTheRestLoads() throws {
        let spots = spot(id: "first", facts: fact(id: "f")) + #", {"id": "broken"}, "# + spot(id: "last", facts: fact(id: "f"))
        let area = try decode(area(spots: spots))
        XCTAssertEqual(area.spots.map(\.id), ["first", "last"])
    }

    func testUnknownFieldsAreIgnored() throws {
        let json = area(spots: spot(id: "a", facts: fact(id: "f"))).replacingOccurrences(
            of: "\"summary\": \"\"", with: "\"summary\": \"\", \"photos\": [{\"file\": \"x.jpg\"}]")
        XCTAssertNoThrow(try decode(json))
    }
}
