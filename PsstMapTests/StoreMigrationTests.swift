import XCTest
@testable import PsstMap

/// Saved places and feed history from before permanent ids must survive the move.
@MainActor
final class StoreMigrationTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "StoreMigrationTests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private let catalog = Fixtures.catalog(
        cities: [CityRecord(id: "wof:london", name: "London", countryCode: "GB", bounds: Fixtures.bounds)],
        legacyIds: ["london-st-johns-wood/abbey-road-crossing": "pl_crossing",
                    "london-westminster/big-ben": "pl_bigben"],
        packs: [CityPack(cityId: "wof:london", places: [Fixtures.spot("pl_crossing", "Abbey Road zebra crossing"),
                                                        Fixtures.spot("pl_bigben", "Big Ben")])])

    func testSavedPlacesMoveToPermanentIDsInOrder() {
        defaults.set(["london-westminster/big-ben", "pl_crossing", "london-st-johns-wood/abbey-road-crossing",
                      "gone/place"], forKey: "saved.placeIDs")
        let store = SavedStore(defaults: defaults)
        store.migrate(using: catalog)
        XCTAssertEqual(store.ids, ["pl_bigben", "pl_crossing", "gone/place"])
        XCTAssertEqual(SavedStore(defaults: defaults).ids, store.ids, "The migration is saved")
    }

    func testSeenPlacesMoveToPermanentIDs() {
        defaults.set(["london-westminster/big-ben"], forKey: "feed.seenPlaceIDs")
        let store = SeenStore(defaults: defaults)
        store.migrate(using: catalog)
        XCTAssertEqual(store.ids, ["pl_bigben"])
    }
}
