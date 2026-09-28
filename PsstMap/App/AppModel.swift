import Foundation
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
        } catch {
            loadState = .failed(error.localizedDescription)
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
