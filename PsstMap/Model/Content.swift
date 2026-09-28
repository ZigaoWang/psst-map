import CoreLocation
import Foundation

// The content format is defined by the psst-content repository (CONTENT_GUIDE.md there).
//
// Decoding is deliberately forgiving, so content written for a newer app never breaks an older one:
// - an unknown fact category or place kind decodes as `.other` and is shown in a neutral style;
// - a fact with an unknown status is dropped, because it can't be labeled honestly;
// - a spot, fact, or source that fails to decode is skipped instead of failing the whole area.
// Only a broken area-level field (id, bounds, and so on) makes the loader skip a file.

/// One researched area, decoded from `Content/areas/<id>.json`.
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

    init(schemaVersion: Int, id: String, name: String, city: String, countryCode: String, summary: String,
         researchedOn: String, bounds: Bounds, spots: [Spot]) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.city = city
        self.countryCode = countryCode
        self.summary = summary
        self.researchedOn = researchedOn
        self.bounds = bounds
        self.spots = spots
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        city = try container.decode(String.self, forKey: .city)
        countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode) ?? ""
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        researchedOn = try container.decodeIfPresent(String.self, forKey: .researchedOn) ?? ""
        bounds = try container.decode(Bounds.self, forKey: .bounds)
        spots = try container.decode(Lossy<Spot>.self, forKey: .spots).values
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
        /// A kind this version of the app doesn't know yet.
        case other

        /// The kinds content can use. `.other` is only a fallback, so it never appears in filters.
        static var allCases: [Kind] {
            [.transit, .crossing, .street, .building, .worship, .memorial, .green, .water, .culture]
        }

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .other
        }
    }

    nonisolated enum Size: String, Codable, Sendable {
        case small, medium, large
    }

    nonisolated struct Coordinate: Codable, Hashable, Sendable {
        let latitude: Double
        let longitude: Double
    }

    nonisolated struct CoordinateSource: Codable, Hashable, Sendable {
        let type: String
        let id: String

        var url: URL? {
            switch type {
            case "wikidata": URL(string: "https://www.wikidata.org/wiki/\(id)")
            case "osm": URL(string: "https://www.openstreetmap.org/\(id)")
            default: nil
            }
        }

        var isWikidata: Bool { type == "wikidata" }
    }

    init(id: String, name: String, localName: String?, kind: Kind, size: Size?, coordinate: Coordinate,
         coordinateSource: CoordinateSource, facts: [Fact]) {
        self.id = id
        self.name = name
        self.localName = localName
        self.kind = kind
        self.size = size
        self.coordinate = coordinate
        self.coordinateSource = coordinateSource
        self.facts = facts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        localName = try container.decodeIfPresent(String.self, forKey: .localName)
        kind = try container.decode(Kind.self, forKey: .kind)
        size = try? container.decodeIfPresent(Size.self, forKey: .size)
        coordinate = try container.decode(Coordinate.self, forKey: .coordinate)
        coordinateSource = try container.decode(CoordinateSource.self, forKey: .coordinateSource)
        facts = try container.decode(Lossy<Fact>.self, forKey: .facts).values
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
        case name, hidden, history, design, engineering, people, pop, quirk
        /// A category this version of the app doesn't know yet.
        case other

        /// The categories content can use. `.other` is only a fallback, so it never appears in filters.
        static var allCases: [Category] {
            [.name, .hidden, .history, .design, .engineering, .people, .pop, .quirk]
        }

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Category(rawValue: raw) ?? .other
        }
    }

    /// Strict on purpose: a fact that can't say whether it's a fact or a legend is not shown.
    nonisolated enum Status: String, Codable, Sendable {
        case fact, legend, disputed
    }

    nonisolated struct Source: Codable, Hashable, Sendable {
        let title: String
        let publisher: String
        let url: URL
    }

    init(id: String, category: Category, status: Status, headline: String, short: String, long: String,
         sources: [Source]) {
        self.id = id
        self.category = category
        self.status = status
        self.headline = headline
        self.short = short
        self.long = long
        self.sources = sources
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        category = try container.decode(Category.self, forKey: .category)
        status = try container.decode(Status.self, forKey: .status)
        headline = try container.decode(String.self, forKey: .headline)
        short = try container.decode(String.self, forKey: .short)
        long = try container.decodeIfPresent(String.self, forKey: .long) ?? ""
        sources = try container.decode(Lossy<Source>.self, forKey: .sources).values
    }
}

/// Decodes an array, keeping the elements that decode and skipping the ones that don't.
nonisolated struct Lossy<Element: Decodable>: Decodable {
    let values: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var values: [Element] = []
        while !container.isAtEnd {
            if let value = try? container.decode(Element.self) {
                values.append(value)
            } else {
                // Step over the broken element so the rest of the array still loads.
                _ = try? container.decode(Skipped.self)
            }
        }
        self.values = values
    }

    private struct Skipped: Decodable {
        init(from decoder: Decoder) throws {}
    }
}
