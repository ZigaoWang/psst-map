import CoreLocation
import Foundation

// Content format 2, produced by `psst publish` in the psst-content repository (format/v2/*.schema.json).
//
// Decoding is deliberately forgiving, so content written for a newer app never breaks an older one:
// - an unknown fact category or place kind decodes as `.other` and is shown in a neutral style;
// - a fact with an unknown veracity is dropped, because it can't be labeled honestly;
// - a place, fact, source, area, or tag that fails to decode is skipped instead of failing its pack;
// - a guide that fails to decode is dropped, and its place still shows its stories;
// - unknown fields are ignored.

/// The file the app downloads first. Packs are named by their hash and never change.
nonisolated struct ContentManifest: Codable, Sendable {
    let formatVersion: Int
    let contentVersion: String
    let generatedAt: String
    let common: PackReference
    let cities: [CityPackReference]
    let counts: Counts?

    nonisolated struct PackReference: Codable, Hashable, Sendable {
        let file: String
        let sha256: String
        let bytes: Int
    }

    nonisolated struct CityPackReference: Codable, Hashable, Sendable {
        let cityId: String
        let file: String
        let sha256: String
        let bytes: Int

        var pack: PackReference { PackReference(file: file, sha256: sha256, bytes: bytes) }
    }

    nonisolated struct Counts: Codable, Sendable {
        let places: Int
        let facts: Int
    }

    var packs: [PackReference] { [common] + cities.map(\.pack) }
}

/// Cities, the districts and neighborhoods places refer to, published tags, and old place ids.
nonisolated struct CommonPack: Decodable, Sendable {
    let cities: [CityRecord]
    let areas: [AreaRecord]
    let tags: [Tag]
    let legacyIds: [String: String]

    enum CodingKeys: String, CodingKey { case cities, areas, tags, legacyIds }

    init(cities: [CityRecord], areas: [AreaRecord], tags: [Tag], legacyIds: [String: String]) {
        self.cities = cities
        self.areas = areas
        self.tags = tags
        self.legacyIds = legacyIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cities = try container.decode(Lossy<CityRecord>.self, forKey: .cities).values
        areas = try container.decodeIfPresent(Lossy<AreaRecord>.self, forKey: .areas)?.values ?? []
        tags = try container.decodeIfPresent(Lossy<Tag>.self, forKey: .tags)?.values ?? []
        legacyIds = try container.decodeIfPresent([String: String].self, forKey: .legacyIds) ?? [:]
    }
}

nonisolated struct CityRecord: Decodable, Hashable, Sendable {
    let id: String
    let name: String
    let names: [String: String]
    let countryCode: String
    let bounds: Bounds

    nonisolated struct Bounds: Codable, Hashable, Sendable {
        let south: Double
        let west: Double
        let north: Double
        let east: Double

        var center: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: (south + north) / 2, longitude: (west + east) / 2)
        }
    }

    enum CodingKeys: String, CodingKey { case id, name, names, countryCode, bounds }

    init(id: String, name: String, names: [String: String] = [:], countryCode: String, bounds: Bounds) {
        self.id = id
        self.name = name
        self.names = names
        self.countryCode = countryCode
        self.bounds = bounds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        names = (try? container.decodeIfPresent([String: String].self, forKey: .names)) ?? [:]
        countryCode = (try? container.decodeIfPresent(String.self, forKey: .countryCode)) ?? ""
        bounds = try container.decode(Bounds.self, forKey: .bounds)
    }
}

/// A district or neighborhood.
nonisolated struct AreaRecord: Decodable, Hashable, Sendable {
    let id: String
    let level: String
    let name: String
    let names: [String: String]
    let cityId: String

    enum CodingKeys: String, CodingKey { case id, level, name, names, cityId }

    init(id: String, level: String, name: String, names: [String: String] = [:], cityId: String) {
        self.id = id
        self.level = level
        self.name = name
        self.names = names
        self.cityId = cityId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        level = try container.decode(String.self, forKey: .level)
        name = try container.decode(String.self, forKey: .name)
        names = (try? container.decodeIfPresent([String: String].self, forKey: .names)) ?? [:]
        cityId = try container.decode(String.self, forKey: .cityId)
    }
}

/// A thread that connects places: a person, an event, an era, a movement, or a theme.
nonisolated struct Tag: Decodable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let type: String
    let names: [String: String]
    let aliases: [String]
    let placeCount: Int

    enum CodingKeys: String, CodingKey { case id, name, type, names, aliases, placeCount }

    init(id: String, name: String, type: String, names: [String: String] = [:], aliases: [String] = [],
         placeCount: Int = 0) {
        self.id = id
        self.name = name
        self.type = type
        self.names = names
        self.aliases = aliases
        self.placeCount = placeCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? "theme"
        names = (try? container.decodeIfPresent([String: String].self, forKey: .names)) ?? [:]
        aliases = (try? container.decodeIfPresent([String].self, forKey: .aliases)) ?? []
        placeCount = (try? container.decodeIfPresent(Int.self, forKey: .placeCount)) ?? 0
    }
}

/// Every published place in one city.
nonisolated struct CityPack: Decodable, Sendable {
    let cityId: String
    let places: [Spot]

    enum CodingKeys: String, CodingKey { case cityId, places }

    init(cityId: String, places: [Spot]) {
        self.cityId = cityId
        self.places = places
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cityId = try container.decode(String.self, forKey: .cityId)
        places = try container.decode(Lossy<Spot>.self, forKey: .places).values
    }
}

/// One physical place and its stories, as stored in a city pack.
nonisolated struct Spot: Decodable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    /// The name on the signs, in local script, when it differs from the English one.
    let localName: String?
    let localNameLanguage: String?
    /// Established names in other languages, keyed by BCP 47 code (for example "zh-Hans").
    let names: [String: String]
    let kind: Kind
    let size: Size?
    let coordinate: Coordinate
    let coordinateSource: CoordinateSource
    let countryCode: String?
    let districtID: String?
    let neighborhoodID: String?
    let facts: [Fact]
    /// Reviewed photos in display order. Empty for most places, which show the map instead.
    let photos: [Photo]
    /// What the place is, kept apart from its stories: an identifier line, an About, and key facts.
    let guide: Guide?

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

    /// Where the coordinate came from, and its license.
    nonisolated struct CoordinateSource: Codable, Hashable, Sendable {
        let type: String
        let id: String
        var license: String?

        var url: URL? {
            switch type {
            case "wikidata": URL(string: "https://www.wikidata.org/wiki/\(id)")
            case "osm": URL(string: "https://www.openstreetmap.org/\(id)")
            default: nil
            }
        }

        var isWikidata: Bool { type == "wikidata" }
        var isOpenStreetMap: Bool { type == "osm" }
    }

    init(id: String, name: String, localName: String? = nil, localNameLanguage: String? = nil,
         names: [String: String] = [:], kind: Kind, size: Size?, coordinate: Coordinate,
         coordinateSource: CoordinateSource, countryCode: String? = nil, districtID: String? = nil,
         neighborhoodID: String? = nil, facts: [Fact], photos: [Photo] = [], guide: Guide? = nil) {
        self.id = id
        self.name = name
        self.localName = localName
        self.localNameLanguage = localNameLanguage
        self.names = names
        self.kind = kind
        self.size = size
        self.coordinate = coordinate
        self.coordinateSource = coordinateSource
        self.countryCode = countryCode
        self.districtID = districtID
        self.neighborhoodID = neighborhoodID
        self.facts = facts
        self.photos = photos
        self.guide = guide
    }

    enum CodingKeys: String, CodingKey {
        case id, name, localName, names, kind, size, lat, lon, location, countryCode, districtId, neighborhoodId, facts
        case images, guide
    }

    private struct LocalName: Decodable {
        let lang: String?
        let name: String
    }

    private struct Location: Decodable {
        let source: String
        let ref: String
        let license: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        let local = try? container.decodeIfPresent(LocalName.self, forKey: .localName)
        localName = local?.name
        localNameLanguage = local?.lang
        names = (try? container.decodeIfPresent([String: String].self, forKey: .names)) ?? [:]
        kind = try container.decode(Kind.self, forKey: .kind)
        size = try? container.decodeIfPresent(Size.self, forKey: .size)
        coordinate = Coordinate(latitude: try container.decode(Double.self, forKey: .lat),
                                longitude: try container.decode(Double.self, forKey: .lon))
        let location = try container.decode(Location.self, forKey: .location)
        coordinateSource = CoordinateSource(type: location.source, id: location.ref, license: location.license)
        countryCode = try? container.decodeIfPresent(String.self, forKey: .countryCode)
        districtID = try? container.decodeIfPresent(String.self, forKey: .districtId)
        neighborhoodID = try? container.decodeIfPresent(String.self, forKey: .neighborhoodId)
        facts = try container.decode(Lossy<Fact>.self, forKey: .facts).values
        photos = (try? container.decodeIfPresent(Lossy<Photo>.self, forKey: .images))?.values ?? []
        guide = try? container.decodeIfPresent(Guide.self, forKey: .guide)
    }

    /// Current photos, for the header. Historic ones are kept for a "then and now" view.
    var currentPhotos: [Photo] { photos.filter { $0.kind == .photo } }
    var historicPhotos: [Photo] { photos.filter { $0.kind == .historic } }
}

/// Practical information about a place, written and reviewed separately from its stories: a one-line
/// identifier ("Bronze statue, 1843, by Edward Baily"), a short neutral About, and key facts from Wikidata.
nonisolated struct Guide: Decodable, Hashable, Sendable {
    let id: String
    let identifier: String
    let about: String
    let sources: [Fact.Source]
    let keyFacts: [KeyFact]
    /// The Wikidata item the key facts come from.
    let wikidataID: String?

    /// One line of the info box. `property` is the Wikidata property the value came from.
    nonisolated struct KeyFact: Decodable, Hashable, Sendable {
        let property: String
        /// The English label, used when this version of the app has no translation for the property.
        let label: String
        let value: String
    }

    enum CodingKeys: String, CodingKey { case id, identifier, about, sources, keyFacts, wikidataId }

    init(id: String, identifier: String, about: String, sources: [Fact.Source] = [], keyFacts: [KeyFact] = [],
         wikidataID: String? = nil) {
        self.id = id
        self.identifier = identifier
        self.about = about
        self.sources = sources
        self.keyFacts = keyFacts
        self.wikidataID = wikidataID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        identifier = try container.decode(String.self, forKey: .identifier)
        about = try container.decode(String.self, forKey: .about)
        sources = (try? container.decodeIfPresent(Lossy<Fact.Source>.self, forKey: .sources))?.values ?? []
        keyFacts = (try? container.decodeIfPresent(Lossy<KeyFact>.self, forKey: .keyFacts))?.values ?? []
        wikidataID = try? container.decodeIfPresent(String.self, forKey: .wikidataId)
    }

    var wikidataURL: URL? { wikidataID.flatMap { URL(string: "https://www.wikidata.org/wiki/\($0)") } }
}

/// A freely licensed or owner's photo of a place. We host resized copies; the credit links to the original.
nonisolated struct Photo: Decodable, Hashable, Identifiable, Sendable {
    let id: String
    let kind: Kind
    let year: Int?
    /// What the photo shows, for VoiceOver.
    let alt: String
    /// The point to keep in view when cropping, from 0 to 1 with (0, 0) at the top left.
    let focusX: Double
    let focusY: Double
    let full: Rendition
    let thumb: Rendition
    let credit: Credit

    nonisolated enum Kind: String, Decodable, Sendable {
        case photo, historic
    }

    nonisolated struct Rendition: Decodable, Hashable, Sendable {
        let file: String
        let width: Int
        let height: Int

        var aspectRatio: Double { height > 0 ? Double(width) / Double(height) : 1.5 }
    }

    nonisolated struct Credit: Decodable, Hashable, Sendable {
        let author: String
        let authorUrl: URL?
        let license: String
        let licenseUrl: URL?
        let sourceUrl: URL
        let source: String?
        let title: String?

        enum CodingKeys: String, CodingKey { case author, authorUrl, license, licenseUrl, sourceUrl, source, title }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            author = try container.decode(String.self, forKey: .author)
            authorUrl = try? container.decodeIfPresent(URL.self, forKey: .authorUrl)
            license = try container.decode(String.self, forKey: .license)
            licenseUrl = try? container.decodeIfPresent(URL.self, forKey: .licenseUrl)
            sourceUrl = try container.decode(URL.self, forKey: .sourceUrl)
            source = try? container.decodeIfPresent(String.self, forKey: .source)
            title = try? container.decodeIfPresent(String.self, forKey: .title)
        }
    }

    enum CodingKeys: String, CodingKey { case id, kind, year, alt, focus, full, thumb, credit }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(Kind.self, forKey: .kind)
        year = try? container.decodeIfPresent(Int.self, forKey: .year)
        alt = try container.decode(String.self, forKey: .alt)
        let focus = (try? container.decode([Double].self, forKey: .focus)) ?? [0.5, 0.5]
        focusX = focus.count == 2 ? min(max(focus[0], 0), 1) : 0.5
        focusY = focus.count == 2 ? min(max(focus[1], 0), 1) : 0.5
        full = try container.decode(Rendition.self, forKey: .full)
        thumb = try container.decode(Rendition.self, forKey: .thumb)
        credit = try container.decode(Credit.self, forKey: .credit)
    }
}

nonisolated struct Fact: Decodable, Hashable, Identifiable, Sendable {
    let id: String
    let category: Category
    let status: Status
    let headline: String
    let short: String
    let long: String
    let sources: [Source]
    let tags: [String]
    let researchedOn: String?
    let lastVerified: String?

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
         sources: [Source], tags: [String] = [], researchedOn: String? = nil, lastVerified: String? = nil) {
        self.id = id
        self.category = category
        self.status = status
        self.headline = headline
        self.short = short
        self.long = long
        self.sources = sources
        self.tags = tags
        self.researchedOn = researchedOn
        self.lastVerified = lastVerified
    }

    enum CodingKeys: String, CodingKey {
        case id, category, veracity, headline, short, long, sources, tags, researchedOn, lastVerified
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        category = try container.decode(Category.self, forKey: .category)
        status = try container.decode(Status.self, forKey: .veracity)
        headline = try container.decode(String.self, forKey: .headline)
        short = try container.decode(String.self, forKey: .short)
        long = try container.decodeIfPresent(String.self, forKey: .long) ?? ""
        sources = try container.decode(Lossy<Source>.self, forKey: .sources).values
        tags = (try? container.decodeIfPresent([String].self, forKey: .tags)) ?? []
        researchedOn = try? container.decodeIfPresent(String.self, forKey: .researchedOn)
        lastVerified = try? container.decodeIfPresent(String.self, forKey: .lastVerified)
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
