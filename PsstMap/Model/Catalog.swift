import CoreLocation
import Foundation

/// A place with the context the app needs everywhere: its city and neighborhood, and both coordinates.
nonisolated struct Place: Hashable, Identifiable, Sendable {
    /// Permanent and global (`pl_...`). Saved places and feed history are keyed by it.
    let id: String
    let spot: Spot
    let cityID: String
    /// The city's English name.
    let city: String
    let districtName: String?
    let neighborhoodID: String?
    let neighborhoodName: String?

    /// WGS-84, for distance math against Core Location.
    let coordinate: CLLocationCoordinate2D

    init(spot: Spot, cityID: String, city: String, districtName: String?, neighborhoodID: String?,
         neighborhoodName: String?) {
        self.id = spot.id
        self.spot = spot
        self.cityID = cityID
        self.city = city
        self.districtName = districtName
        self.neighborhoodID = neighborhoodID
        self.neighborhoodName = neighborhoodName
        self.coordinate = CLLocationCoordinate2D(latitude: spot.coordinate.latitude, longitude: spot.coordinate.longitude)
    }

    /// What to hand to MapKit: shifted to GCJ-02 when Apple Maps is drawing China in GCJ-02.
    @MainActor var mapCoordinate: CLLocationCoordinate2D { MapDatum.shared.mapCoordinate(for: coordinate) }

    var name: String { spot.name }
    var leadFact: Fact { spot.facts[0] }
    var location: CLLocation { CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude) }
    var isInMainlandChina: Bool { ChinaCoordinates.isInMainlandChina(coordinate) }

    /// The smallest named area the place is in: its neighborhood, else its district, else its city.
    var areaID: String { neighborhoodID ?? spot.districtID ?? cityID }
    var areaName: String { neighborhoodName ?? districtName ?? city }

    /// The place's name in the reader's language, when there is one and it adds something beyond the
    /// English and local names already shown.
    func name(forLanguages languages: [String]) -> String? {
        for language in languages {
            guard let name = Self.lookup(language, in: spot.names) else { continue }
            if name != spot.name && name != spot.localName { return name }
            return nil
        }
        return nil
    }

    /// Finds a name for a language, trying "zh-Hans-CN", then "zh-Hans", then "zh".
    static func lookup(_ language: String, in names: [String: String]) -> String? {
        let locale = Locale.Language(identifier: language)
        guard let code = locale.languageCode?.identifier else { return nil }
        if code == "en" { return nil }
        if code == "zh" {
            let traditional = locale.script?.identifier == "Hant"
                || ["TW", "HK", "MO"].contains(locale.region?.identifier ?? "")
            return names[traditional ? "zh-Hant" : "zh-Hans"] ?? names["zh-Hans"] ?? names["zh-Hant"]
        }
        return names[code]
    }

    static func == (lhs: Place, rhs: Place) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

nonisolated struct Neighborhood: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let names: [String: String]
    let cityID: String
    let placeCount: Int
    let bounds: CityRecord.Bounds
}

nonisolated struct City: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let names: [String: String]
    let countryCode: String
    let bounds: CityRecord.Bounds
    let neighborhoods: [Neighborhood]
    let placeCount: Int
}

/// Everything the app has, indexed for lookup.
nonisolated struct Catalog: Sendable {
    let places: [Place]
    let cities: [City]
    let tags: [Tag]
    let contentVersion: String?
    private let placesByID: [String: Place]
    private let citiesByID: [String: City]
    private let neighborhoodsByID: [String: Neighborhood]
    private let tagsByID: [String: Tag]
    private let legacyIDs: [String: String]

    init(common: CommonPack, packs: [CityPack], contentVersion: String? = nil) {
        let areas = Dictionary(common.areas.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let records = Dictionary(common.cities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var places: [Place] = []
        for pack in packs {
            guard let city = records[pack.cityId] else { continue }
            for spot in pack.places where !spot.facts.isEmpty {
                let neighborhood = spot.neighborhoodID.flatMap { areas[$0] }
                places.append(Place(spot: spot, cityID: city.id, city: city.name,
                                    districtName: spot.districtID.flatMap { areas[$0]?.name },
                                    neighborhoodID: neighborhood?.id, neighborhoodName: neighborhood?.name))
            }
        }
        places.sort { ($0.city, $0.name) < ($1.city, $1.name) }
        self.places = places
        self.placesByID = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.contentVersion = contentVersion

        let byCity = Dictionary(grouping: places, by: \.cityID)
        var neighborhoods: [String: Neighborhood] = [:]
        var cities: [City] = []
        for (cityID, cityPlaces) in byCity {
            guard let record = records[cityID] else { continue }
            let byNeighborhood = Dictionary(grouping: cityPlaces.filter { $0.neighborhoodID != nil },
                                            by: { $0.neighborhoodID! })
            var cityNeighborhoods: [Neighborhood] = []
            for (id, hoodPlaces) in byNeighborhood {
                guard let area = areas[id] else { continue }
                let hood = Neighborhood(id: id, name: area.name, names: area.names, cityID: cityID,
                                        placeCount: hoodPlaces.count, bounds: Self.bounds(of: hoodPlaces))
                neighborhoods[id] = hood
                cityNeighborhoods.append(hood)
            }
            cityNeighborhoods.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            cities.append(City(id: cityID, name: record.name, names: record.names, countryCode: record.countryCode,
                               bounds: record.bounds, neighborhoods: cityNeighborhoods, placeCount: cityPlaces.count))
        }
        // Cities with the most places first, so the biggest collections lead the pickers.
        self.cities = cities.sorted { ($0.placeCount, $1.name) > ($1.placeCount, $0.name) }
        self.citiesByID = Dictionary(cities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.neighborhoodsByID = neighborhoods
        let usedTags = Set(places.flatMap { $0.spot.facts.flatMap(\.tags) })
        self.tags = common.tags.filter { usedTags.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.tagsByID = Dictionary(tags.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.legacyIDs = common.legacyIds
    }

    static let empty = Catalog(common: CommonPack(cities: [], areas: [], tags: [], legacyIds: [:]), packs: [])

    var factCount: Int { places.reduce(0) { $0 + $1.spot.facts.count } }

    /// A place by its id, or by an id from before the move to permanent ids ("areaId/spotId").
    func place(id: String) -> Place? { placesByID[id] ?? legacyIDs[id].flatMap { placesByID[$0] } }

    /// The current id for an old or current id, if the place still exists.
    func resolve(_ id: String) -> String? { place(id: id)?.id }

    func city(id: String) -> City? { citiesByID[id] }
    func neighborhood(id: String) -> Neighborhood? { neighborhoodsByID[id] }
    func tag(id: String) -> Tag? { tagsByID[id] }

    func places(inCity cityID: String) -> [Place] { places.filter { $0.cityID == cityID } }
    func places(inNeighborhood id: String) -> [Place] { places.filter { $0.neighborhoodID == id } }
    func places(tagged tagID: String) -> [Place] {
        places.filter { $0.spot.facts.contains { $0.tags.contains(tagID) } }
    }

    /// Places within `radius` meters of a WGS-84 location, nearest first.
    func places(near location: CLLocation, within radius: CLLocationDistance) -> [Place] {
        places
            .map { ($0, $0.location.distance(from: location)) }
            .filter { $0.1 <= radius }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    static func bounds(of places: [Place]) -> CityRecord.Bounds {
        let lats = places.map(\.coordinate.latitude)
        let lons = places.map(\.coordinate.longitude)
        return CityRecord.Bounds(south: lats.min() ?? 0, west: lons.min() ?? 0,
                                 north: lats.max() ?? 0, east: lons.max() ?? 0)
    }
}
