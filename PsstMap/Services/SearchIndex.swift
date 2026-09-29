import Foundation

/// Search over everything on the device, so it works offline. Built once per catalog, off the main thread.
///
/// Matching ignores case and accents, treats Traditional and Simplified Chinese as the same, and also
/// matches Chinese names by toneless pinyin, with or without spaces ("heping fandian" finds 和平饭店).
/// Every word of the query has to match somewhere. Names rank above places' areas, areas above tags,
/// and tags above the words of the stories.
nonisolated struct SearchIndex: Sendable {
    struct Match: Sendable, Identifiable {
        let place: Place
        let rank: Int
        /// The story that matched, when the match wasn't the name or the area.
        let story: String?
        var id: String { place.id }
    }

    struct Results: Sendable {
        let places: [Match]
        let tags: [Tag]
        let cities: [City]
        let neighborhoods: [Neighborhood]

        var isEmpty: Bool { places.isEmpty && tags.isEmpty && cities.isEmpty && neighborhoods.isEmpty }
    }

    private struct Entry: Sendable {
        let place: Place
        let names: [String]
        let areas: [String]
        let tags: [String]
        let kind: String
        let stories: [(headline: String, text: String)]
    }

    private let entries: [Entry]
    private let tags: [(tag: Tag, keys: [String])]
    private let cities: [(city: City, keys: [String])]
    private let neighborhoods: [(hood: Neighborhood, keys: [String])]

    init(catalog: Catalog) {
        let tagKeys = Dictionary(catalog.tags.map { tag in
            (tag.id, Self.keys(for: [tag.name] + tag.aliases + Array(tag.names.values)))
        }, uniquingKeysWith: { first, _ in first })
        tags = catalog.tags.map { ($0, tagKeys[$0.id] ?? []) }
        cities = catalog.cities.map { ($0, Self.keys(for: [$0.name] + Array($0.names.values))) }
        let hoods = catalog.cities.flatMap(\.neighborhoods)
        neighborhoods = hoods.map { ($0, Self.keys(for: [$0.name] + Array($0.names.values))) }
        let hoodKeys = Dictionary(neighborhoods.map { ($0.hood.id, $0.keys) }, uniquingKeysWith: { first, _ in first })
        let cityKeys = Dictionary(cities.map { ($0.city.id, $0.keys) }, uniquingKeysWith: { first, _ in first })

        entries = catalog.places.map { place in
            let spot = place.spot
            var areas = cityKeys[place.cityID] ?? []
            areas += place.neighborhoodID.flatMap { hoodKeys[$0] } ?? []
            if let district = place.districtName { areas += Self.keys(for: [district]) }
            let factTags = Set(spot.facts.flatMap(\.tags))
            return Entry(
                place: place,
                names: Self.keys(for: [spot.name] + [spot.localName].compactMap { $0 } + Array(spot.names.values)),
                areas: areas,
                tags: factTags.flatMap { tagKeys[$0] ?? [] },
                kind: Self.normalize("\(spot.kind.label) \(spot.kind.rawValue)"),
                stories: spot.facts.map { ($0.headline, Self.normalize("\($0.headline) \($0.short) \($0.long)")) })
        }
    }

    func search(_ query: String) -> Results {
        let terms = Self.normalize(query).split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return Results(places: [], tags: [], cities: [], neighborhoods: []) }
        let whole = terms.joined(separator: " ")

        var matches: [Match] = []
        for entry in entries {
            let all = entry.names + entry.areas + entry.tags + [entry.kind]
            guard terms.allSatisfy({ term in
                all.contains { $0.contains(term) } || entry.stories.contains { $0.text.contains(term) }
            }) else { continue }
            let rank: Int
            var story: String?
            if entry.names.contains(where: { $0.hasPrefix(whole) }) {
                rank = 0
            } else if terms.allSatisfy({ term in entry.names.contains { $0.contains(term) } }) {
                rank = 1
            } else if terms.allSatisfy({ term in (entry.names + entry.areas).contains { $0.contains(term) } }) {
                rank = 2
            } else if terms.allSatisfy({ term in (entry.names + entry.areas + entry.tags + [entry.kind])
                .contains { $0.contains(term) } }) {
                rank = 3
            } else {
                rank = 4
                story = entry.stories.first { s in terms.contains { s.text.contains($0) } }?.headline
            }
            matches.append(Match(place: entry.place, rank: rank, story: story))
        }
        matches.sort { ($0.rank, $0.place.name) < ($1.rank, $1.place.name) }

        func matching<T>(_ items: [(T, [String])]) -> [T] {
            items.filter { _, keys in terms.allSatisfy { term in keys.contains { $0.contains(term) } } }.map(\.0)
        }
        return Results(places: matches, tags: matching(tags.map { ($0.tag, $0.keys) }),
                       cities: matching(cities.map { ($0.city, $0.keys) }),
                       neighborhoods: matching(neighborhoods.map { ($0.hood, $0.keys) }))
    }

    // MARK: Normalization

    /// Lowercase, no accents, full-width folded, Traditional Chinese as Simplified, punctuation as spaces.
    static func normalize(_ text: String) -> String {
        var folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                  locale: nil)
        if folded.unicodeScalars.contains(where: isHan) {
            folded = folded.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? folded
        }
        let cleaned = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || isHan(scalar) ? Character(scalar) : " "
        }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    /// Every searchable form of some names: normalized, plus toneless pinyin (spaced and joined) for Chinese.
    static func keys(for names: [String]) -> [String] {
        var keys: [String] = []
        for name in names {
            let normalized = normalize(name)
            guard !normalized.isEmpty else { continue }
            keys.append(normalized)
            if normalized.unicodeScalars.contains(where: isHan),
               let latin = normalized.applyingTransform(.mandarinToLatin, reverse: false) {
                let pinyin = normalize(latin)
                keys.append(pinyin)
                keys.append(pinyin.replacingOccurrences(of: " ", with: ""))
            }
        }
        return keys
    }

    static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
            || (0xF900...0xFAFF).contains(scalar.value) || (0x20000...0x2A6DF).contains(scalar.value)
    }
}
