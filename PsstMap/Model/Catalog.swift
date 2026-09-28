import CoreLocation
import Foundation

/// A spot with the context the app needs everywhere: its area, a globally unique id, and both coordinates.
nonisolated struct Place: Hashable, Identifiable, Sendable {
    /// `areaId/spotId`. Stable across releases; saved places and seen history are keyed by it.
    let id: String
    let spot: Spot
    let areaID: String
    let areaName: String
    let city: String

    /// WGS-84, for distance math against Core Location.
    let coordinate: CLLocationCoordinate2D
    /// What to hand to MapKit. GCJ-02 in mainland China, otherwise the same as `coordinate`.
    let mapCoordinate: CLLocationCoordinate2D

    init(spot: Spot, area: Area) {
        self.id = "\(area.id)/\(spot.id)"
        self.spot = spot
        self.areaID = area.id
        self.areaName = area.name
        self.city = area.city
        let wgs = CLLocationCoordinate2D(latitude: spot.coordinate.latitude, longitude: spot.coordinate.longitude)
        self.coordinate = wgs
        self.mapCoordinate = ChinaCoordinates.mapCoordinate(for: wgs)
    }

    var name: String { spot.name }
    var leadFact: Fact { spot.facts[0] }
    var location: CLLocation { CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude) }
    var isInMainlandChina: Bool { ChinaCoordinates.isInMainlandChina(coordinate) }

    static func == (lhs: Place, rhs: Place) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Everything bundled with the app, indexed for lookup.
nonisolated struct Catalog: Sendable {
    let areas: [Area]
    let places: [Place]
    let cities: [City]
    private let placesByID: [String: Place]
    private let areasByID: [String: Area]

    nonisolated struct City: Identifiable, Hashable, Sendable {
        var id: String { name }
        let name: String
        let areas: [Area]
        var placeCount: Int { areas.reduce(0) { $0 + $1.spots.count } }
    }

    init(areas: [Area]) {
        let sortedAreas = areas.sorted { ($0.city, $0.name) < ($1.city, $1.name) }
        self.areas = sortedAreas
        self.places = sortedAreas.flatMap { area in area.spots.map { Place(spot: $0, area: area) } }
        self.placesByID = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.areasByID = Dictionary(sortedAreas.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let grouped = Dictionary(grouping: sortedAreas, by: \.city)
        // Cities with the most places first, so the biggest collections lead the pickers.
        self.cities = grouped
            .map { City(name: $0.key, areas: $0.value) }
            .sorted { ($0.placeCount, $1.name) > ($1.placeCount, $0.name) }
    }

    static let empty = Catalog(areas: [])

    var factCount: Int { places.reduce(0) { $0 + $1.spot.facts.count } }

    func place(id: String) -> Place? { placesByID[id] }
    func area(id: String) -> Area? { areasByID[id] }

    func places(inArea areaID: String) -> [Place] { places.filter { $0.areaID == areaID } }
    func places(inCity city: String) -> [Place] { places.filter { $0.city == city } }

    /// Places within `radius` meters of a WGS-84 location, nearest first. Ready for nearby features later.
    func places(near location: CLLocation, within radius: CLLocationDistance) -> [Place] {
        places
            .map { ($0, $0.location.distance(from: location)) }
            .filter { $0.1 <= radius }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }
}
