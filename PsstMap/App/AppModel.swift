import Foundation
import UIKit
import Observation

/// App-wide state shared by the tabs.
@Observable
final class AppModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    enum Tab: Hashable {
        case map, feed, saved
    }

    /// Something the map should move to, set from other tabs ("Show on map") or the area picker.
    struct MapFocus: Equatable {
        enum Target: Equatable {
            case place(String)
            /// Frame a region: a city or a neighborhood.
            case bounds(CityRecord.Bounds)
        }
        let target: Target
        let token = UUID()
    }

    private(set) var loadState: LoadState = .loading
    private(set) var catalog: Catalog = .empty
    var selectedTab: Tab = .map
    var mapFocus: MapFocus?
    /// Shuffles the feed once per session, so it stays put while you scroll and can be warmed up early.
    var feedSeed = UInt64.random(in: 0...UInt64.max)

    /// Kinds of place to show. Empty means every kind. Choosing one shows only that kind; choosing more
    /// adds them; choosing all of them, or the last one again, goes back to everything.
    var shownKinds: Set<Spot.Kind> = AppModel.load(key: AppModel.shownKindsKey) {
        didSet { UserDefaults.standard.set(shownKinds.map(\.rawValue), forKey: Self.shownKindsKey) }
    }

    /// Story categories to show, with the same rules. A place shows while it has a story in one of them.
    var shownCategories: Set<Fact.Category> = AppModel.load(key: AppModel.shownCategoriesKey) {
        didSet { UserDefaults.standard.set(shownCategories.map(\.rawValue), forKey: Self.shownCategoriesKey) }
    }

    /// The places that pass both filters.
    var visiblePlaces: [Place] {
        guard isFiltering else { return catalog.places }
        return catalog.places.filter(isVisible)
    }

    func isVisible(_ place: Place) -> Bool {
        isShown(place.spot.kind) && place.spot.facts.contains { isShown($0.category) }
    }

    func isShown(_ kind: Spot.Kind) -> Bool { shownKinds.isEmpty || shownKinds.contains(kind) }
    func isShown(_ category: Fact.Category) -> Bool { shownCategories.isEmpty || shownCategories.contains(category) }

    /// The story to lead with: the first one in a category being shown.
    func leadFact(for place: Place) -> Fact {
        place.spot.facts.first { isShown($0.category) } ?? place.leadFact
    }

    var isFiltering: Bool { !shownKinds.isEmpty || !shownCategories.isEmpty }

    func toggle(_ kind: Spot.Kind) {
        shownKinds = Self.toggled(kind, in: shownKinds, all: Spot.Kind.allCases)
    }

    func toggle(_ category: Fact.Category) {
        shownCategories = Self.toggled(category, in: shownCategories, all: Fact.Category.allCases)
    }

    private static func toggled<Value: Hashable>(_ value: Value, in set: Set<Value>, all: [Value]) -> Set<Value> {
        var result = set
        if result.contains(value) {
            result.remove(value)
        } else {
            result.insert(value)
        }
        // Everything chosen is the same as nothing chosen: show all.
        return result.count == all.count ? [] : result
    }

    func clearFilters() {
        shownKinds = []
        shownCategories = []
    }

    /// A few words saying what the filter is doing, for the chip on the map.
    var filterSummary: String {
        switch (shownKinds.count, shownCategories.count) {
        case (1, 0): shownKinds.first!.label
        case (_, 0): String(localized: "\(shownKinds.count) kinds")
        case (0, 1): shownCategories.first!.label
        case (0, _): String(localized: "\(shownCategories.count) story types")
        default: String(localized: "Filtered")
        }
    }

    private static let shownKindsKey = "filter.shownKinds"
    private static let shownCategoriesKey = "filter.shownCategories"

    private static func load<Value: RawRepresentable & Hashable>(key: String) -> Set<Value> where Value.RawValue == String {
        Set((UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap(Value.init(rawValue:)))
    }

    let saved = SavedStore()
    let seen = SeenStore()
    let location = LocationService()
    let reports = ReportOutbox()

    private(set) var content: ContentLibrary.Loaded?
    /// Built in the background whenever the catalog changes; nil for the moment in between.
    private(set) var searchIndex: SearchIndex?
    private var lastUpdateCheck: Date?
    private let updater = ContentUpdater()

    func load() async {
        loadState = .loading
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try ContentLibrary.loadBest()
            }.value
            install(loaded)
            loadState = .loaded
            warmUpFeed()
            Task { await checkForUpdates() }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    private func install(_ loaded: ContentLibrary.Loaded) {
        content = loaded
        catalog = loaded.catalog
        searchIndex = nil
        let catalog = loaded.catalog
        Task {
            let index = await Task.detached(priority: .utility) { SearchIndex(catalog: catalog) }.value
            if self.catalog.contentVersion == catalog.contentVersion { self.searchIndex = index }
        }
        // Places saved before ids became permanent ("areaId/spotId") are moved to their new ids.
        saved.migrate(using: loaded.catalog)
        seen.migrate(using: loaded.catalog)
    }

    /// Looks for newer content when the app opens or comes back, at most every 15 minutes. It costs one tiny
    /// request when nothing changed. New content replaces the current catalog only once it has fully
    /// downloaded and checked out; any failure leaves everything as it was.
    func checkForUpdates(force: Bool = false) async {
        // The first load installs content itself; an update check before that would race it.
        guard loadState == .loaded else { return }
        if !force, let lastUpdateCheck, lastUpdateCheck.timeIntervalSinceNow > -15 * 60 { return }
        lastUpdateCheck = Date()
        await reports.flush()
        do {
            if let newer = try await updater.update(current: content) {
                install(newer)
            }
        } catch {
            // Offline or a bad download: keep what we have and try again later.
        }
    }

    /// Starts making the first feed pictures right away, so the feed is ready by the time someone opens it.
    private func warmUpFeed() {
        let first = FeedOrder.order(catalog.places, seen: seen.ids, seed: feedSeed).prefix(3)
        let size = FeedCard.pictureSize(for: UIScreen.main.bounds.size)
        Task(priority: .utility) {
            for place in first {
                if let photo = place.spot.currentPhotos.first {
                    await PhotoLoader.shared.prefetch(photo)
                } else {
                    await SpotVisuals.shared.picture(for: place, size: size, scale: 2, dark: true)
                }
            }
        }
    }

    func showOnMap(_ place: Place) {
        // Someone who picks a place wants to see it, even if the map's filters would hide it.
        if !isVisible(place) { clearFilters() }
        mapFocus = MapFocus(target: .place(place.id))
        selectedTab = .map
    }

    func showOnMap(bounds: CityRecord.Bounds) {
        mapFocus = MapFocus(target: .bounds(bounds))
        selectedTab = .map
    }
}
