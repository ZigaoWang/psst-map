import XCTest
@testable import PsstMap

/// The extra name under a place's title is in the reader's own language, never a second language.
final class PlaceNameTests: XCTestCase {
    private func museum() -> Place {
        let catalog = Fixtures.catalog(
            cities: [CityRecord(id: "wof:london", name: "London", countryCode: "GB", bounds: Fixtures.bounds)],
            packs: [CityPack(cityId: "wof:london", places: [
                Fixtures.spot("pl_museum", "Fashion and Textile Museum", names: ["zh-Hans": "时装及纺织品博物馆"]),
            ])])
        return catalog.places[0]
    }

    func testEnglishReadersWithChineseAsASecondLanguageSeeNoChineseName() {
        XCTAssertNil(museum().name(forLanguages: ["en-US", "zh-Hans-US"]))
    }

    func testChineseReadersSeeTheChineseName() {
        XCTAssertEqual(museum().name(forLanguages: ["zh-Hans-CN", "en-US"]), "时装及纺织品博物馆")
    }
}
