import SwiftUI

/// Finds places by name (English or local), area, city, or anything in their stories, and lists the
/// areas to browse when nothing has been typed yet.
struct SearchSheet: View {
    let onPlace: (Place) -> Void
    let onArea: (String) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                if trimmedQuery.isEmpty {
                    browse
                } else {
                    results
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.immediately)
            .safeAreaInset(edge: .top, spacing: 0) { searchField }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear { isFieldFocused = true }
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Places, areas, or stories", text: $query)
                .focused($isFieldFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    if let first = matches.first { onPlace(first.place) }
                }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Clear search"))
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.screenBackground)
    }

    // MARK: Browse

    @ViewBuilder
    private var browse: some View {
        ForEach(app.catalog.cities) { city in
            Section {
                ForEach(city.areas) { area in
                    Button { onArea(area.id) } label: { AreaRow(area: area) }
                        .buttonStyle(.plain)
                }
            } header: {
                Text(city.name)
            }
        }
    }

    // MARK: Results

    @ViewBuilder
    private var results: some View {
        let places = matches
        let areas = matchingAreas
        if places.isEmpty && areas.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nothing called \u{201C}\(trimmedQuery)\u{201D} yet")
                        .font(.headline)
                    Text("Try a street, a station, or a word from a story.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
        }
        if !areas.isEmpty {
            Section("Areas") {
                ForEach(areas) { area in
                    Button { onArea(area.id) } label: { AreaRow(area: area) }
                        .buttonStyle(.plain)
                }
            }
        }
        if !places.isEmpty {
            Section(places.count == 1 ? "1 place" : "\(places.count) places") {
                ForEach(places.prefix(60), id: \.place.id) { match in
                    Button { onPlace(match.place) } label: { SearchResultRow(match: match) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private var matches: [SearchMatch] {
        PlaceSearch.search(trimmedQuery, in: app.catalog.places)
    }

    private var matchingAreas: [Area] {
        let terms = PlaceSearch.terms(trimmedQuery)
        guard !terms.isEmpty else { return [] }
        return app.catalog.areas.filter { area in
            terms.allSatisfy { PlaceSearch.contains("\(area.name) \(area.city)", $0) }
        }
    }
}

/// A place that matched, with the story text that matched when it wasn't the name.
nonisolated struct SearchMatch: Sendable {
    let place: Place
    let rank: Int
    let matchedStory: String?
}

nonisolated enum PlaceSearch {
    static func terms(_ query: String) -> [String] {
        query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Case- and accent-insensitive, so "cafe" finds "Café".
    static func contains(_ text: String, _ term: String) -> Bool {
        text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// Every word of the query must appear somewhere. Names rank above areas, areas above stories.
    static func search(_ query: String, in places: [Place]) -> [SearchMatch] {
        let terms = terms(query)
        guard !terms.isEmpty else { return [] }
        var results: [SearchMatch] = []
        for place in places {
            let name = "\(place.name) \(place.spot.localName ?? "")"
            let where_ = "\(place.areaName) \(place.city)"
            let stories = place.spot.facts.map { "\($0.headline) \($0.short)" }
            let everything = ([name, where_] + stories).joined(separator: " ")
            guard terms.allSatisfy({ contains(everything, $0) }) else { continue }

            let rank: Int
            var matchedStory: String?
            if name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil {
                rank = 0
            } else if terms.allSatisfy({ contains(name, $0) }) {
                rank = 1
            } else if terms.allSatisfy({ contains("\(name) \(where_)", $0) }) {
                rank = 2
            } else {
                rank = 3
                matchedStory = place.spot.facts.first { fact in
                    terms.contains { contains("\(fact.headline) \(fact.short)", $0) }
                }?.headline
            }
            results.append(SearchMatch(place: place, rank: rank, matchedStory: matchedStory))
        }
        return results.sorted { ($0.rank, $0.place.name) < ($1.rank, $1.place.name) }
    }
}

private struct SearchResultRow: View {
    let match: SearchMatch

    var body: some View {
        HStack(spacing: 12) {
            KindTile(kind: match.place.spot.kind, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(match.place.name)
                        .font(.body.weight(.semibold))
                    if let local = match.place.spot.localName {
                        Text(local)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                Text(match.matchedStory ?? "\(match.place.areaName), \(match.place.city)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct AreaRow: View {
    let area: Area

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(area.name)
                    .font(.body.weight(.semibold))
                Text(area.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text("\(area.spots.count)")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(localized: "\(area.spots.count) places"))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
