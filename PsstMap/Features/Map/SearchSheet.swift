import NaturalLanguage
import SwiftUI
@preconcurrency import Translation

/// Search, and browsing by city and neighborhood when nothing has been typed.
struct SearchSheet: View {
    let onPlace: (Place) -> Void
    let onRegion: (CityRecord.Bounds) -> Void
    let onTag: (Tag) -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var translated: (query: String, english: String)?
    @State private var translationRequest: String?
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
            .navigationDestination(for: City.self) { city in
                CityNeighborhoods(city: city, onRegion: onRegion)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .modifier(QueryTranslation(request: $translationRequest) { original, english in
                if original == trimmedQuery { translated = (original, english) }
            })
        }
        .onAppear { isFieldFocused = true }
        .onChange(of: trimmedQuery) { _, _ in
            translated = nil
            requestTranslationIfNeeded()
        }
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Places, neighborhoods, people, stories", text: $query)
                .focused($isFieldFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    if let first = currentResults?.places.first { onPlace(first.place) }
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
        Section {
            ForEach(app.catalog.cities) { city in
                NavigationLink(value: city) {
                    AreaRow(title: city.displayName, subtitle: nil, count: city.placeCount)
                }
            }
        } header: {
            Text("Cities")
        } footer: {
            Text("Choose a city to see its neighborhoods, or search for any place, person, or story.")
        }
    }

    // MARK: Results

    private var currentResults: SearchIndex.Results? {
        guard let index = app.searchIndex else { return nil }
        let direct = index.search(trimmedQuery)
        if direct.isEmpty, let translated, translated.query == trimmedQuery {
            return index.search(translated.english)
        }
        return direct
    }

    @ViewBuilder
    private var results: some View {
        if let results = currentResults {
            if results.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nothing called \u{201C}\(trimmedQuery)\u{201D} yet")
                            .font(.headline)
                        Text("Try a street, a station, a person, or a word from a story.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            } else {
                if let translated, translated.query == trimmedQuery, app.searchIndex?.search(trimmedQuery).isEmpty == true {
                    Section {
                        Label("Showing results for \u{201C}\(translated.english)\u{201D}", systemImage: "translate")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                resultSections(results)
            }
        } else {
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Getting search ready")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func resultSections(_ results: SearchIndex.Results) -> some View {
        if !results.cities.isEmpty || !results.neighborhoods.isEmpty {
            Section("Areas") {
                ForEach(results.cities) { city in
                    Button { onRegion(city.bounds) } label: {
                        AreaRow(title: city.displayName, subtitle: nil, count: city.placeCount)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(results.neighborhoods.prefix(12)) { hood in
                    Button { onRegion(hood.bounds) } label: {
                        AreaRow(title: hood.displayName,
                                subtitle: app.catalog.city(id: hood.cityID)?.displayName, count: hood.placeCount)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        if !results.tags.isEmpty {
            Section("Threads") {
                ForEach(results.tags.prefix(8)) { tag in
                    Button { onTag(tag) } label: { TagRow(tag: tag) }
                        .buttonStyle(.plain)
                }
            }
        }
        // Places, grouped by city and then neighborhood, in rank order within each.
        ForEach(groups(results.places.prefix(120)), id: \.title) { group in
            Section(group.title) {
                ForEach(group.matches) { match in
                    Button { onPlace(match.place) } label: { SearchResultRow(match: match) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func groups(_ matches: ArraySlice<SearchIndex.Match>) -> [(title: String, matches: [SearchIndex.Match])] {
        var order: [String] = []
        var grouped: [String: [SearchIndex.Match]] = [:]
        for match in matches {
            let title = [match.place.neighborhoodName, match.place.city].compactMap { $0 }.joined(separator: ", ")
            if grouped[title] == nil { order.append(title) }
            grouped[title, default: []].append(match)
        }
        return order.map { ($0, grouped[$0]!) }
    }

    // MARK: Translation fallback

    /// When nothing matches and the query looks like it isn't English, ask for an English translation.
    private func requestTranslationIfNeeded() {
        let current = trimmedQuery
        guard current.count >= 2, let index = app.searchIndex, index.search(current).isEmpty else { return }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(current)
        guard let language = recognizer.dominantLanguage, language != .english, language != .undetermined else { return }
        translationRequest = current
    }
}

/// Translates a search query to English on the device (iOS 18 and later). Silently does nothing when the
/// language isn't supported or its model isn't downloaded, so search never blocks on it.
private struct QueryTranslation: ViewModifier {
    @Binding var request: String?
    let onResult: (String, String) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.modifier(QueryTranslation18(request: $request, onResult: onResult))
        } else {
            content
        }
    }
}

@available(iOS 18.0, *)
private struct QueryTranslation18: ViewModifier {
    @Binding var request: String?
    let onResult: (String, String) -> Void
    @State private var configuration: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .translationTask(configuration) { session in
                guard let text = request else { return }
                if let response = try? await session.translate(text) {
                    await MainActor.run { onResult(text, response.targetText) }
                }
            }
            .onChange(of: request) { _, text in
                guard let text else { return }
                let recognizer = NLLanguageRecognizer()
                recognizer.processString(text)
                let source = recognizer.dominantLanguage.map { Locale.Language(identifier: $0.rawValue) }
                if configuration?.source == source {
                    configuration?.invalidate()
                } else {
                    configuration = .init(source: source, target: Locale.Language(identifier: "en"))
                }
            }
    }
}

/// A city's neighborhoods, largest collection first.
private struct CityNeighborhoods: View {
    let city: City
    let onRegion: (CityRecord.Bounds) -> Void

    var body: some View {
        List {
            Section {
                Button { onRegion(city.bounds) } label: {
                    AreaRow(title: String(localized: "All of \(city.displayName)"), subtitle: nil, count: city.placeCount)
                }
                .buttonStyle(.plain)
            }
            Section("Neighborhoods") {
                ForEach(city.neighborhoods.sorted { ($0.placeCount, $1.displayName) > ($1.placeCount, $0.displayName) }) { hood in
                    Button { onRegion(hood.bounds) } label: {
                        AreaRow(title: hood.displayName,
                                subtitle: nil, count: hood.placeCount)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(city.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SearchResultRow: View {
    let match: SearchIndex.Match

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
                Text(match.story ?? match.place.leadFact.headline)
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

struct TagRow: View {
    let tag: Tag

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: TagStyle.symbol(for: tag.type))
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(TagStyle.name(of: tag))
                    .font(.body.weight(.semibold))
                Text(tag.placeCount == 1 ? "1 place" : "\(tag.placeCount) places")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct AreaRow: View {
    let title: String
    let subtitle: String?
    let count: Int

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text("\(count)")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(localized: "\(count) places"))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
