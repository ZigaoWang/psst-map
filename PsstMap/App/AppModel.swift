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
