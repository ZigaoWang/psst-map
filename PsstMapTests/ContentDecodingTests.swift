import XCTest
@testable import PsstMap

/// Content written for a newer app must never break this one.
final class ContentDecodingTests: XCTestCase {
    private func pack(places: String) -> String {
        #"{"cityId": "wof:london", "places": [\#(places)]}"#
    }

    private func place(id: String, kind: String = "building", facts: String) -> String {
        """
        {"id": "\(id)", "name": "\(id)", "kind": "\(kind)", "size": "medium", "lat": 51.5, "lon": -0.1,
         "location": {"source": "osm", "ref": "node/1", "license": "ODbL-1.0"},
         "localName": {"lang": "en", "name": "Local \(id)"}, "names": {"zh-Hans": "名字"},
         "countryCode": "GB", "neighborhoodId": "wof:1", "facts": [\(facts)]}
        """
    }

    private func fact(id: String, category: String = "history", veracity: String = "fact") -> String {
        """
        {"id": "\(id)", "category": "\(category)", "veracity": "\(veracity)", "headline": "h", "short": "s",
         "long": "l", "tags": ["tg_1"], "researchedOn": "2026-09-28",
         "sources": [{"title": "t", "publisher": "p", "url": "https://example.com"}]}
        """
    }

    private func decode(_ json: String) throws -> CityPack {
        try JSONDecoder().decode(CityPack.self, from: Data(json.utf8))
    }

    func testFullPlaceDecodes() throws {
        let spot = try decode(pack(places: place(id: "pl_a", facts: fact(id: "fa_1")))).places[0]
        XCTAssertEqual(spot.coordinate.latitude, 51.5)
        XCTAssertEqual(spot.coordinateSource, .init(type: "osm", id: "node/1", license: "ODbL-1.0"))
        XCTAssertEqual(spot.localName, "Local pl_a")
        XCTAssertEqual(spot.names["zh-Hans"], "名字")
        XCTAssertEqual(spot.neighborhoodID, "wof:1")
        XCTAssertEqual(spot.facts[0].status, .fact)
        XCTAssertEqual(spot.facts[0].tags, ["tg_1"])
        XCTAssertEqual(spot.facts[0].sources.count, 1)
    }

    func testPopCategoryDecodes() throws {
        let pack = try decode(pack(places: place(id: "a", facts: fact(id: "f", category: "pop"))))
        XCTAssertEqual(pack.places[0].facts[0].category, .pop)
    }

    func testUnknownCategoryFallsBackInsteadOfFailing() throws {
        let pack = try decode(pack(places: place(id: "a", facts: fact(id: "f", category: "food"))))
        XCTAssertEqual(pack.places[0].facts[0].category, .other)
    }

    func testUnknownKindFallsBackInsteadOfFailing() throws {
        let pack = try decode(pack(places: place(id: "a", kind: "lighthouse", facts: fact(id: "f"))))
        XCTAssertEqual(pack.places[0].kind, .other)
        XCTAssertFalse(Spot.Kind.allCases.contains(.other), "The fallback kind must not show up in filters")
    }

    func testFactWithUnknownVeracityIsDropped() throws {
        let facts = fact(id: "keep") + "," + fact(id: "drop", veracity: "rumor")
        let pack = try decode(pack(places: place(id: "a", facts: facts)))
        XCTAssertEqual(pack.places[0].facts.map(\.id), ["keep"])
    }

    func testBrokenPlaceIsSkippedAndTheRestLoads() throws {
        let places = place(id: "first", facts: fact(id: "f")) + #", {"id": "broken"}, "#
            + place(id: "last", facts: fact(id: "f"))
        XCTAssertEqual(try decode(pack(places: places)).places.map(\.id), ["first", "last"])
    }

    func testUnknownFieldsAreIgnored() throws {
        let json = pack(places: place(id: "a", facts: fact(id: "f")))
            .replacingOccurrences(of: #""size": "medium""#, with: #""size": "medium", "photos": [{"file": "x.jpg"}]"#)
        XCTAssertNoThrow(try decode(json))
    }

    func testCommonPackToleratesMissingOptionalParts() throws {
        let json = #"{"cities": [{"id": "wof:1", "name": "London", "bounds": {"south": 51, "west": -1, "north": 52, "east": 1}}]}"#
        let common = try JSONDecoder().decode(CommonPack.self, from: Data(json.utf8))
        XCTAssertEqual(common.cities.map(\.id), ["wof:1"])
        XCTAssertTrue(common.tags.isEmpty)
        XCTAssertTrue(common.legacyIds.isEmpty)
    }
}
