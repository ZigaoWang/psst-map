#if DEBUG
import Foundation

/// Debug-only launch arguments for driving the app into a given state, e.g. for screenshots:
/// `xcrun simctl launch booted app.psstmap.ios -debug.tab feed -debug.place london-city/monument`
enum DebugLaunch {
    static var tab: AppModel.Tab? {
        switch UserDefaults.standard.string(forKey: "debug.tab") {
        case "map": .map
        case "feed": .feed
        case "saved": .saved
        default: nil
        }
    }

    static var placeID: String? { UserDefaults.standard.string(forKey: "debug.place") }
    static var areaID: String? { UserDefaults.standard.string(forKey: "debug.area") }
    static var sheet: String? { UserDefaults.standard.string(forKey: "debug.sheet") }

    static func apply(to app: AppModel) {
        if let tab { app.selectedTab = tab }
        if let areaID { app.showOnMap(areaID: areaID) }
        if let placeID, let place = app.catalog.place(id: placeID) { app.showOnMap(place) }
    }
}
#endif
