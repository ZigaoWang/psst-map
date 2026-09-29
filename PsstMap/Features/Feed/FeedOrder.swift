import CoreLocation
import Foundation

/// Which places the feed draws from.
enum FeedScope: Hashable, Codable {
    case everywhere
    case nearMe
    case city(String)
    case neighborhood(String)
}

/// Decides the order of the feed. Pure, so it is easy to test.
nonisolated enum FeedOrder {
    /// New places first, then ones already seen. Within each group, areas take turns so the feed keeps
    /// moving around, and places are shuffled with `seed` so each session feels fresh but stays stable
    /// while you scroll.
    static func order(_ places: [Place], seen: Set<String>, seed: UInt64) -> [Place] {
        var generator = SeededGenerator(seed: seed)
        let unseen = places.filter { !seen.contains($0.id) }
        let alreadySeen = places.filter { seen.contains($0.id) }
        return interleaveByArea(unseen, using: &generator) + interleaveByArea(alreadySeen, using: &generator)
    }

    /// Nearest first, for the "Near me" scope.
    static func byDistance(_ places: [Place], from location: CLLocation) -> [Place] {
        places
            .map { ($0, $0.location.distance(from: location)) }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    private static func interleaveByArea(_ places: [Place], using generator: inout SeededGenerator) -> [Place] {
        var queues = Dictionary(grouping: places, by: \.areaID)
            .sorted { $0.key < $1.key }
            .map { $0.value.sorted { $0.id < $1.id }.shuffled(using: &generator) }
        queues.shuffle(using: &generator)
        var result: [Place] = []
        result.reserveCapacity(places.count)
        while !queues.isEmpty {
            for index in queues.indices.reversed() where !queues[index].isEmpty {
                result.append(queues[index].removeFirst())
            }
            queues.removeAll { $0.isEmpty }
        }
        return result
    }
}

/// SplitMix64. Deterministic, so a given seed always produces the same feed.
nonisolated struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
