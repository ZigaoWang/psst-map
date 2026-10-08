import CoreLocation
import Observation

/// When-in-use location, requested only when the person asks for something that needs it.
/// Reports WGS-84, like Core Location everywhere, including in China.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus
    private(set) var location: CLLocation?

    /// The last fix if it's from the last 30 minutes; older than that, the person may be somewhere else.
    var recentLocation: CLLocation? {
        guard let location, location.timestamp.timeIntervalSinceNow > -30 * 60 else { return nil }
        return location
    }
    private let manager = CLLocationManager()
    private var waiters: [CheckedContinuation<CLLocation?, Never>] = []

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    func requestPermission() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Asks for permission if needed and returns a fresh fix, or nil if unavailable.
    func currentLocation() async -> CLLocation? {
        if let location, location.timestamp.timeIntervalSinceNow > -120 { return location }
        if isDenied { return nil }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
            if authorization == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
        }
    }

    private func resumeWaiters(with location: CLLocation?) {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(returning: location) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                if !self.waiters.isEmpty { self.manager.requestLocation() }
            case .denied, .restricted:
                self.resumeWaiters(with: nil)
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            self.location = latest
            self.resumeWaiters(with: latest)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.resumeWaiters(with: self.location)
        }
    }
}
