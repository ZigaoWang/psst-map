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
            case area(String)
            /// Pan just enough to bring a pin into view, keeping the zoom.
            case reveal(String)
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

    /// Kinds of place the person has hidden with the map key. Applies to the map and the feed.
    var hiddenKinds: Set<Spot.Kind> = AppModel.loadHiddenKinds() {
        didSet { UserDefaults.standard.set(hiddenKinds.map(\.rawValue), forKey: Self.hiddenKindsKey) }
    }

    /// Story categories the person has hidden. A place stays visible while it has any story left.
    var hiddenCategories: Set<Fact.Category> = AppModel.loadHiddenCategories() {
        didSet { UserDefaults.standard.set(hiddenCategories.map(\.rawValue), forKey: Self.hiddenCategoriesKey) }
    }

    /// The places that pass both filters.
    var visiblePlaces: [Place] {
        guard isFiltering else { return catalog.places }
        return catalog.places.filter(isVisible)
    }

    func isVisible(_ place: Place) -> Bool {
        !hiddenKinds.contains(place.spot.kind)
            && place.spot.facts.contains { !hiddenCategories.contains($0.category) }
    }

    /// The story to lead with: the first one in a category that isn't hidden.
    func leadFact(for place: Place) -> Fact {
        place.spot.facts.first { !hiddenCategories.contains($0.category) } ?? place.leadFact
    }

    var isFiltering: Bool { !hiddenKinds.isEmpty || !hiddenCategories.isEmpty }

    func toggle(_ category: Fact.Category) {
        if hiddenCategories.contains(category) {
            hiddenCategories.remove(category)
        } else if hiddenCategories.count < Fact.Category.allCases.count - 1 {
            hiddenCategories.insert(category)
        }
    }

    func showOnly(_ category: Fact.Category) {
        hiddenCategories = Set(Fact.Category.allCases).subtracting([category])
    }

    func toggle(_ kind: Spot.Kind) {
        if hiddenKinds.contains(kind) {
            hiddenKinds.remove(kind)
        } else if hiddenKinds.count < Spot.Kind.allCases.count - 1 {
            // Hiding the last visible kind would leave an empty map, so that tap does nothing.
            hiddenKinds.insert(kind)
        }
    }

    func showOnly(_ kind: Spot.Kind) {
        hiddenKinds = Set(Spot.Kind.allCases).subtracting([kind])
    }

    func showAllKinds() {
        hiddenKinds = []
    }

    func clearFilters() {
        hiddenKinds = []
        hiddenCategories = []
    }

    /// A few words saying what the filter is doing, for the chip on the map.
    var filterSummary: String {
        switch (hiddenKinds.isEmpty, hiddenCategories.isEmpty) {
        case (false, true):
            String(localized: "\(Spot.Kind.allCases.count - hiddenKinds.count) of \(Spot.Kind.allCases.count) kinds")
        case (true, false):
            hiddenCategories.count == Fact.Category.allCases.count - 1
                ? (Set(Fact.Category.allCases).subtracting(hiddenCategories).first?.label ?? "")
                : String(localized: "\(Fact.Category.allCases.count - hiddenCategories.count) of \(Fact.Category.allCases.count) stories")
        default:
            String(localized: "Filtered")
        }
    }

    private static let hiddenKindsKey = "filter.hiddenKinds"

    private static let hiddenCategoriesKey = "filter.hiddenCategories"

    private static func loadHiddenCategories() -> Set<Fact.Category> {
        let raw = UserDefaults.standard.stringArray(forKey: hiddenCategoriesKey) ?? []
        return Set(raw.compactMap(Fact.Category.init(rawValue:)))
    }

    private static func loadHiddenKinds() -> Set<Spot.Kind> {
        let raw = UserDefaults.standard.stringArray(forKey: hiddenKindsKey) ?? []
        return Set(raw.compactMap(Spot.Kind.init(rawValue:)))
    }

    let saved = SavedStore()
    let seen = SeenStore()
    let location = LocationService()

    func load() async {
        loadState = .loading
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try ContentLoader.load()
            }.value
            catalog = result.catalog
            loadState = .loaded
            warmUpFeed()
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Starts making the first feed pictures right away, so the feed is ready by the time someone opens it.
    private func warmUpFeed() {
        let first = FeedOrder.order(catalog.places, seen: seen.ids, seed: feedSeed).prefix(3)
        let size = FeedCard.pictureSize(for: UIScreen.main.bounds.size)
        Task(priority: .utility) {
            for place in first {
                await SpotVisuals.shared.picture(for: place, size: size, scale: 2, dark: true)
            }
        }
    }

    func showOnMap(_ place: Place) {
        mapFocus = MapFocus(target: .place(place.id))
        selectedTab = .map
    }

    func showOnMap(areaID: String) {
        mapFocus = MapFocus(target: .area(areaID))
        selectedTab = .map
    }
}
