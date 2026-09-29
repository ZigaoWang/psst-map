import CoreLocation
import Foundation
import Observation

/// The two things the app ever sends: problem reports and "no stories here yet" signals.
/// See the privacy policy (Settings > Privacy policy) for exactly what each contains.
nonisolated enum PsstAPI {
    static func post(_ path: String, body: [String: String]) async throws {
        var request = URLRequest(url: ContentUpdater.configuredBaseURL().appendingPathComponent("api/v1/\(path)"),
                                 timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // 422 means the server understood and refused (for example, a story that was since removed):
        // retrying won't help, so it counts as delivered.
        guard (200..<300).contains(status) || status == 422 else { throw URLError(.badServerResponse) }
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }
}

/// Problem reports, kept on the device until the server has them.
@Observable
final class ReportOutbox {
    enum Reason: String, CaseIterable, Codable, Identifiable {
        case wrong, outdated, location, offensive, other
        var id: String { rawValue }

        var label: String {
            switch self {
            case .wrong: String(localized: "Something in it is wrong")
            case .outdated: String(localized: "It's out of date")
            case .location: String(localized: "The pin is in the wrong place")
            case .offensive: String(localized: "It's offensive or inappropriate")
            case .other: String(localized: "Something else")
            }
        }
    }

    struct Report: Codable, Equatable {
        let factID: String
        let reason: Reason
        let message: String
        let appVersion: String
    }

    private(set) var pending: [Report]
    private static let key = "reports.pending"

    init() {
        let data = UserDefaults.standard.data(forKey: Self.key)
        pending = data.flatMap { try? JSONDecoder().decode([Report].self, from: $0) } ?? []
    }

    /// Queues a report and tries to send everything waiting. Returns true if this one went out now.
    @discardableResult
    func submit(factID: String, reason: Reason, message: String) async -> Bool {
        let report = Report(factID: factID, reason: reason,
                            message: String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000)),
                            appVersion: PsstAPI.appVersion)
        pending.append(report)
        save()
        await flush()
        return !pending.contains(report)
    }

    func flush() async {
        for report in pending {
            do {
                try await PsstAPI.post("reports", body: ["factId": report.factID, "reason": report.reason.rawValue,
                                                         "message": report.message, "appVersion": report.appVersion])
                pending.removeAll { $0 == report }
                save()
            } catch {
                return  // Offline: try again next time.
            }
        }
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(pending), forKey: Self.key)
    }
}

/// "No stories here yet" signals that help choose where to research next. Off when the person turns off
/// "Help choose new areas". Sends only a coordinate rounded to a tenth of a degree (about 10 km); the
/// server keeps only a daily count for a much larger area.
enum DemandSignal {
    static let settingKey = "privacy.helpChooseAreas"
    private static let sentKey = "demand.sent"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
    }

    static func send(center: CLLocationCoordinate2D) {
        guard isEnabled else { return }
        let lat = (center.latitude * 10).rounded() / 10
        let lon = (center.longitude * 10).rounded() / 10
        let key = "\(lat),\(lon)"
        let today = ISO8601DateFormatter.string(from: Date(), timeZone: .gmt, formatOptions: [.withFullDate])
        var sent = UserDefaults.standard.dictionary(forKey: sentKey) as? [String: String] ?? [:]
        guard sent[key] != today else { return }
        sent = sent.filter { $0.value == today }
        sent[key] = today
        UserDefaults.standard.set(sent, forKey: sentKey)
        Task.detached(priority: .background) {
            try? await PsstAPI.post("demand", body: ["lat": String(lat), "lon": String(lon)])
        }
    }
}
