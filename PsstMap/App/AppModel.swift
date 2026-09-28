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

    /// The places that pass the kind filter.
    var visiblePlaces: [Place] {
        hiddenKinds.isEmpty ? catalog.places : catalog.places.filter { !hiddenKinds.contains($0.spot.kind) }
    }

    var isFiltering: Bool { !hiddenKinds.isEmpty }

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

    private static let hiddenKindsKey = "filter.hiddenKinds"

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
