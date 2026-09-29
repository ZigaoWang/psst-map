import Foundation
@testable import PsstMap

/// Small hand-made catalogs for tests that shouldn't depend on the bundled content.
enum Fixtures {
    static let bounds = CityRecord.Bounds(south: 51, west: -1, north: 52, east: 1)

    static func spot(_ id: String, _ name: String, local: String? = nil, names: [String: String] = [:],
                     neighborhood: String? = nil, story: String = "A story", tags: [String] = []) -> Spot {
        Spot(id: id, name: name, localName: local, names: names, kind: .building, size: nil,
             coordinate: .init(latitude: 51.5, longitude: -0.1),
             coordinateSource: .init(type: "osm", id: "node/1", license: "ODbL-1.0"), countryCode: "GB",
             neighborhoodID: neighborhood,
             facts: [Fact(id: "fa_\(id)", category: .pop, status: .fact, headline: story, short: story, long: "",
                          sources: [], tags: tags)])
    }

    static func catalog(cities: [CityRecord], areas: [AreaRecord] = [], tags: [Tag] = [],
                        legacyIds: [String: String] = [:], packs: [CityPack]) -> Catalog {
        Catalog(common: CommonPack(cities: cities, areas: areas, tags: tags, legacyIds: legacyIds), packs: packs)
    }
}
