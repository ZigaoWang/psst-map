import XCTest
@testable import PsstMap

final class FeedOrderTests: XCTestCase {
    private func makePlaces() -> [Place] {
        let hoods = ["a": 5, "b": 5, "c": 2]
        let spots = hoods.flatMap { hood, count in
            (0..<count).map { Fixtures.spot("pl_\(hood)\($0)", "Spot \(hood)\($0)", neighborhood: "wof:\(hood)") }
        }
        return Fixtures.catalog(
            cities: [CityRecord(id: "wof:london", name: "London", countryCode: "GB", bounds: Fixtures.bounds)],
            areas: hoods.keys.map { AreaRecord(id: "wof:\($0)", level: "neighborhood", name: $0, cityId: "wof:london") },
            packs: [CityPack(cityId: "wof:london", places: spots)]).places
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

    func testNeighborhoodsTakeTurns() {
        let ordered = FeedOrder.order(makePlaces(), seen: [], seed: 11)
        // With three neighborhoods, the first three cards come from three different ones.
        XCTAssertEqual(Set(ordered.prefix(3).map(\.areaID)).count, 3)
    }
}
