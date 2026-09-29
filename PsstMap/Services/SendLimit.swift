import Foundation

/// Caps what one device sends, without any identifier: the device remembers what it sent, and when.
/// A key (a cell, a story) can be sent once per `window` days, and at most `perDay` keys go out a day.
nonisolated struct SendLimit {
    let storeKey: String
    let perDay: Int
    let window: Int

    enum Outcome: Equatable {
        case allowed
        case alreadySent
        case dailyLimit
    }

    /// Checks the limit and, if the key may be sent, records it as sent.
    func take(_ key: String, now: Date = Date(), defaults: UserDefaults = .standard) -> Outcome {
        let today = Self.day(now)
        var sent = defaults.dictionary(forKey: storeKey) as? [String: String] ?? [:]
        let oldest = Self.day(now.addingTimeInterval(-Double(window - 1) * 86_400))
        sent = sent.filter { $0.value >= oldest }
        defer { defaults.set(sent, forKey: storeKey) }
        if sent[key] != nil { return .alreadySent }
        if sent.values.filter({ $0 == today }).count >= perDay { return .dailyLimit }
        sent[key] = today
        return .allowed
    }

    /// Undoes `take` for a key that ended up not being sent.
    func release(_ key: String, defaults: UserDefaults = .standard) {
        var sent = defaults.dictionary(forKey: storeKey) as? [String: String] ?? [:]
        sent[key] = nil
        defaults.set(sent, forKey: storeKey)
    }

    private static func day(_ date: Date) -> String {
        ISO8601DateFormatter.string(from: date, timeZone: .gmt, formatOptions: [.withFullDate])
    }
}
