import XCTest
@testable import PsstMap

final class SearchIndexTests: XCTestCase {
    private lazy var index = SearchIndex(catalog: Fixtures.catalog(
        cities: [CityRecord(id: "wof:london", name: "London", names: ["zh-Hans": "伦敦"], countryCode: "GB",
                            bounds: Fixtures.bounds),
                 CityRecord(id: "wof:shanghai", name: "Shanghai", names: ["zh-Hans": "上海"], countryCode: "CN",
                            bounds: Fixtures.bounds)],
        areas: [AreaRecord(id: "wof:sjw", level: "neighborhood", name: "St John's Wood", cityId: "wof:london"),
                AreaRecord(id: "osm:bund", level: "neighborhood", name: "Waitan", names: ["zh-Hans": "外滩"],
                           cityId: "wof:shanghai")],
        tags: [Tag(id: "tg_beatles", name: "The Beatles", type: "group", aliases: ["Fab Four"], placeCount: 3)],
        packs: [CityPack(cityId: "wof:london", places: [
                    Fixtures.spot("pl_crossing", "Abbey Road zebra crossing", neighborhood: "wof:sjw",
                                  tags: ["tg_beatles"]),
                    Fixtures.spot("pl_studios", "Abbey Road Studios", neighborhood: "wof:sjw"),
                    Fixtures.spot("pl_pub", "The Clifton", neighborhood: "wof:sjw",
                                  story: "Near Abbey Road, the pub the band used"),
                    Fixtures.spot("pl_bigben", "Big Ben", names: ["zh-Hans": "大本钟", "zh-Hant": "大笨鐘", "fr": "Big Ben"]),
                    Fixtures.spot("pl_cafe", "Café Rouge")]),
                CityPack(cityId: "wof:shanghai", places: [
                    Fixtures.spot("pl_peace", "Peace Hotel", local: "和平饭店", neighborhood: "osm:bund")])]))

    private func names(_ query: String) -> [String] { index.search(query).places.map(\.place.name) }

    func testNameMatchesRankAboveStoryMatches() {
        let results = index.search("abbey road").places
        XCTAssertEqual(results.prefix(2).map(\.place.name).sorted(), ["Abbey Road Studios", "Abbey Road zebra crossing"])
        XCTAssertEqual(results.last?.place.name, "The Clifton")
        XCTAssertNotNil(results.last?.story)
    }

    func testNamesInOtherLanguagesMatch() {
        XCTAssertEqual(names("大本钟"), ["Big Ben"])
        XCTAssertEqual(names("和平"), ["Peace Hotel"])
    }

    func testTraditionalChineseMatchesSimplified() {
        XCTAssertEqual(names("和平飯店"), ["Peace Hotel"])
    }

    func testPinyinMatchesWithOrWithoutSpaces() {
        XCTAssertEqual(names("heping fandian"), ["Peace Hotel"])
        XCTAssertEqual(names("hepingfandian"), ["Peace Hotel"])
    }

    func testAccentsAndCaseAreIgnored() {
        XCTAssertEqual(names("CAFE"), ["Café Rouge"])
    }

    func testEveryWordMustMatch() {
        XCTAssertTrue(index.search("abbey peace").isEmpty)
    }

    func testAreasMatchPlacesAndThemselves() {
        XCTAssertEqual(names("john's wood").count, 3)
        XCTAssertEqual(index.search("外滩").neighborhoods.map(\.id), ["osm:bund"])
        XCTAssertEqual(names("外滩"), ["Peace Hotel"])
        XCTAssertEqual(index.search("伦敦").cities.map(\.id), ["wof:london"])
    }

    func testTagsMatchByNameAndAlias() {
        XCTAssertEqual(index.search("fab four").tags.map(\.id), ["tg_beatles"])
        XCTAssertEqual(names("beatles"), ["Abbey Road zebra crossing"])
    }

    func testKindMatches() {
        XCTAssertEqual(names("building").count, 6)
    }
}
