import CoreLocation
import Foundation
import H3
import MapKit
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

    enum Outcome: Equatable {
        case sent
        /// Saved on the device; it goes out when the phone is back online.
        case queued
        case alreadyReported
        case dailyLimit
    }

    private(set) var pending: [Report]
    private static let key = "reports.pending"
    /// One report per story per device (remembered for 90 days), and at most 5 reports a day.
    nonisolated static let limit = SendLimit(storeKey: "reports.sent", perDay: 5, window: 90)

    init() {
        let data = UserDefaults.standard.data(forKey: Self.key)
        pending = data.flatMap { try? JSONDecoder().decode([Report].self, from: $0) } ?? []
    }

    /// Queues a report and tries to send everything waiting.
    @discardableResult
    func submit(factID: String, reason: Reason, message: String) async -> Outcome {
        switch Self.limit.take(factID) {
        case .alreadySent: return .alreadyReported
        case .dailyLimit: return .dailyLimit
        case .allowed: break
        }
        let report = Report(factID: factID, reason: reason,
                            message: String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000)),
                            appVersion: PsstAPI.appVersion)
        pending.append(report)
        save()
        await flush()
        return pending.contains(report) ? .queued : .sent
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

/// "No stories here yet" signals, so research can go where people look. Sends one thing: the id of the
/// H3 cell (resolution 5, about 250 km²) at the middle of an empty, city-sized map view. Never the
/// person's location: nothing is sent while their own position is inside the view. Off when they turn
/// off "Help choose new areas".
enum DemandSignal {
    static let settingKey = "privacy.helpChooseAreas"
    nonisolated static let resolution = 5
    /// One signal per cell per day, and at most 10 cells a day, so one device can't skew the counts.
    nonisolated static let limit = SendLimit(storeKey: "demand.sent", perDay: 10, window: 1)

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
    }

    /// The cell to report for a view, or nil when this view shouldn't be reported.
    nonisolated static func cell(center: CLLocationCoordinate2D, span: MKCoordinateSpan, hasPlaces: Bool,
                                 userLocation: CLLocationCoordinate2D?) -> String? {
        guard !hasPlaces, (0.03...0.8).contains(span.latitudeDelta) else { return nil }
        if let user = userLocation,
           abs(user.latitude - center.latitude) <= span.latitudeDelta / 2,
           abs(user.longitude - center.longitude) <= span.longitudeDelta / 2 {
            return nil
        }
        return H3.cell(latitude: center.latitude, longitude: center.longitude, resolution: resolution)
    }

    static func send(cell: String) {
        guard isEnabled, limit.take(cell) == .allowed else { return }
        Task.detached(priority: .background) {
            try? await PsstAPI.post("demand", body: ["cell": cell])
        }
    }
}
