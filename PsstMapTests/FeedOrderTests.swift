import XCTest
@testable import PsstMap

final class FeedOrderTests: XCTestCase {
    private func makePlaces() -> [Place] {
        func area(_ id: String, spots: Int) -> Area {
            let list = (0..<spots).map { index in
                Spot(id: "s\(index)", name: "Spot \(index)", localName: nil, kind: .building, size: nil,
                     coordinate: .init(latitude: 51.5, longitude: -0.1),
                     coordinateSource: .init(type: .osm, id: "node/\(index + 1)"),
                     facts: [Fact(id: "f", category: .history, status: .fact, headline: "h", short: "s", long: "l",
                                  sources: [])])
            }
            return Area(schemaVersion: 1, id: id, name: id, city: "London", countryCode: "GB", summary: "",
                        researchedOn: "2026-09-28",
                        bounds: .init(south: 51, west: -1, north: 52, east: 1), spots: list)
        }
        return Catalog(areas: [area("london-a", spots: 5), area("london-b", spots: 5), area("london-c", spots: 2)]).places
    }

    func testSameSeedGivesSameOrder() {
        let places = makePlaces()
        XCTAssertEqual(FeedOrder.order(places, seen: [], seed: 42).map(\.id),
                       FeedOrder.order(places, seen: [], seed: 42).map(\.id))
    }

    func testEveryPlaceAppearsOnce() {
        let places = makePlaces()
        let ordered = FeedOrder.order(places, seen: [], seed: 7)
        XCTAssertEqual(Set(ordered.map(\.id)), Set(places.map(\.id)))
        XCTAssertEqual(ordered.count, places.count)
    }

    func testUnseenPlacesComeFirst() {
        let places = makePlaces()
        let seen = Set(places.prefix(4).map(\.id))
        let ordered = FeedOrder.order(places, seen: seen, seed: 3)
        XCTAssertTrue(ordered.prefix(places.count - 4).allSatisfy { !seen.contains($0.id) })
    }

    func testAreasTakeTurns() {
        let ordered = FeedOrder.order(makePlaces(), seen: [], seed: 11)
        // With three areas, the first three cards come from three different areas.
        XCTAssertEqual(Set(ordered.prefix(3).map(\.areaID)).count, 3)
    }
}
