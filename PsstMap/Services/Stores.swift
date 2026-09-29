import Foundation
import Observation

/// Places the person has saved, newest first. Persisted in UserDefaults by global place id.
@Observable
final class SavedStore {
    private(set) var ids: [String]
    private let defaults: UserDefaults
    private static let key = "saved.placeIDs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.ids = defaults.stringArray(forKey: Self.key) ?? []
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    func toggle(_ id: String) {
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.insert(id, at: 0)
        }
        defaults.set(ids, forKey: Self.key)
    }

    func remove(_ id: String) {
        ids.removeAll { $0 == id }
        defaults.set(ids, forKey: Self.key)
    }

    /// Rewrites old ids to current ones. Ids that no longer resolve are kept, in case the place returns.
    func migrate(using catalog: Catalog) {
        var seen = Set<String>()
        let migrated = ids.compactMap { id -> String? in
            let current = catalog.resolve(id) ?? id
            return seen.insert(current).inserted ? current : nil
        }
        if migrated != ids {
            ids = migrated
            defaults.set(ids, forKey: Self.key)
        }
    }
}

/// Which places have already appeared in the feed, so it can keep showing new ones first.
/// Not observed by views on purpose: marking a card as seen should never re-render the feed.
final class SeenStore {
    private(set) var ids: Set<String>
    private let defaults: UserDefaults
    private static let key = "feed.seenPlaceIDs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.ids = Set(defaults.stringArray(forKey: Self.key) ?? [])
    }

    func markSeen(_ id: String) {
        guard ids.insert(id).inserted else { return }
        defaults.set(Array(ids), forKey: Self.key)
    }

    func migrate(using catalog: Catalog) {
        let migrated = Set(ids.map { catalog.resolve($0) ?? $0 })
        if migrated != ids {
            ids = migrated
            defaults.set(Array(ids), forKey: Self.key)
        }
    }

    func forget(_ idsToForget: some Sequence<String>) {
        ids.subtract(idsToForget)
        defaults.set(Array(ids), forKey: Self.key)
    }
}
