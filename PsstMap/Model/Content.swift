import CoreLocation
import Foundation

/// One researched area, decoded from `Content/areas/<id>.json`. See CONTENT_GUIDE.md for the format.
nonisolated struct Area: Codable, Hashable, Identifiable, Sendable {
    let schemaVersion: Int
    let id: String
    let name: String
    let city: String
    let countryCode: String
    let summary: String
    let researchedOn: String
    let bounds: Bounds
    let spots: [Spot]

    nonisolated struct Bounds: Codable, Hashable, Sendable {
        let south: Double
        let west: Double
        let north: Double
        let east: Double

        var center: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: (south + north) / 2, longitude: (west + east) / 2)
        }

        func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
            (south...north).contains(coordinate.latitude) && (west...east).contains(coordinate.longitude)
        }
    }
}

nonisolated struct Spot: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let localName: String?
    let kind: Kind
    let size: Size?
    let coordinate: Coordinate
    let coordinateSource: CoordinateSource
    let facts: [Fact]

    nonisolated enum Kind: String, Codable, CaseIterable, Sendable {
        case transit, crossing, street, building, worship, memorial, green, water, culture
    }

    nonisolated enum Size: String, Codable, Sendable {
        case small, medium, large
    }

    nonisolated struct Coordinate: Codable, Hashable, Sendable {
        let latitude: Double
        let longitude: Double
    }

    nonisolated struct CoordinateSource: Codable, Hashable, Sendable {
        let type: SourceType
        let id: String

        nonisolated enum SourceType: String, Codable, Sendable {
            case wikidata, osm
        }

        var url: URL? {
            switch type {
            case .wikidata: URL(string: "https://www.wikidata.org/wiki/\(id)")
            case .osm: URL(string: "https://www.openstreetmap.org/\(id)")
            }
        }
    }
}

nonisolated struct Fact: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let category: Category
    let status: Status
    let headline: String
    let short: String
    let long: String
    let sources: [Source]

    nonisolated enum Category: String, Codable, CaseIterable, Sendable {
        case name, hidden, history, design, engineering, people, quirk
    }

    nonisolated enum Status: String, Codable, Sendable {
        case fact, legend, disputed
    }

    nonisolated struct Source: Codable, Hashable, Sendable {
        let title: String
        let publisher: String
        let url: URL
    }
}
