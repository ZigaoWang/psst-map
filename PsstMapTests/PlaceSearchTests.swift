import XCTest
@testable import PsstMap

final class PlaceSearchTests: XCTestCase {
    private func places() -> [Place] {
        func spot(_ id: String, _ name: String, local: String? = nil, story: String = "A story") -> Spot {
            Spot(id: id, name: name, localName: local, kind: .building, size: nil,
                 coordinate: .init(latitude: 51.5, longitude: -0.1), coordinateSource: .init(type: "osm", id: "node/1"),
                 facts: [Fact(id: "f", category: .pop, status: .fact, headline: story, short: story, long: "",
                              sources: [])])
        }
        let area = Area(schemaVersion: 1, id: "london-st-johns-wood", name: "St John's Wood", city: "London",
                        countryCode: "GB", summary: "", researchedOn: "2026-09-29",
                        bounds: .init(south: 51, west: -1, north: 52, east: 1),
                        spots: [spot("crossing", "Abbey Road zebra crossing"),
                                spot("studios", "Abbey Road Studios"),
                                spot("pub", "The Clifton", story: "Near Abbey Road, the pub the band used"),
                                spot("hotel", "Peace Hotel", local: "和平饭店")])
        return Catalog(areas: [area]).places
    }

    func testNameMatchesRankAboveStoryMatches() {
        let results = PlaceSearch.search("abbey road", in: places())
        XCTAssertEqual(results.map(\.place.name).prefix(2).sorted(), ["Abbey Road Studios", "Abbey Road zebra crossing"])
        XCTAssertEqual(results.last?.place.name, "The Clifton")
        XCTAssertNotNil(results.last?.matchedStory)
    }

    func testLocalNamesAreSearchable() {
        XCTAssertEqual(PlaceSearch.search("和平", in: places()).first?.place.name, "Peace Hotel")
    }

    func testEveryWordMustMatch() {
        XCTAssertTrue(PlaceSearch.search("abbey peace", in: places()).isEmpty)
    }

    func testAreaNamesMatch() {
        XCTAssertEqual(PlaceSearch.search("john's wood", in: places()).count, 4)
    }
}
