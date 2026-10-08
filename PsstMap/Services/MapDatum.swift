import CoreLocation
import MapKit
import OSLog

/// Which coordinate system Apple Maps is currently drawing mainland China in.
///
/// On devices using Apple's China map provider (in practice, when the device is in mainland China), the map
/// and all MapKit results are in GCJ-02. Everywhere else, Apple Maps draws China in WGS-84. There is no
/// public API for this, so Psst asks MapKit to find a landmark whose true position is known and checks
/// which system the answer is in. The last answer is remembered for the next launch.
@MainActor
@Observable
final class MapDatum {
    static let shared = MapDatum()

    /// True when China coordinates must be shifted to GCJ-02 before handing them to MapKit.
    private(set) var chinaUsesGCJ02: Bool
    /// Bumps whenever `chinaUsesGCJ02` changes, so maps can redraw their pins.
    private(set) var version = 0

    private static let key = "map.chinaUsesGCJ02"
    private let logger = Logger(subsystem: "app.psstmap", category: "datum")
    private var isCalibrating = false

    /// Oriental Pearl Tower, OpenStreetMap way 40778038, in WGS-84.
    private static let landmark = CLLocationCoordinate2D(latitude: 31.2419464, longitude: 121.4952604)

    private init() {
        if UserDefaults.standard.object(forKey: Self.key) != nil {
            chinaUsesGCJ02 = UserDefaults.standard.bool(forKey: Self.key)
        } else {
            chinaUsesGCJ02 = Self.likelyInChina
        }
    }

    /// Before the first calibration: a device set up for mainland China most likely gets the China map.
    private static var likelyInChina: Bool {
        if #available(iOS 16, *), Locale.current.region == .chinaMainland { return true }
        return ["Asia/Shanghai", "Asia/Urumqi", "Asia/Chongqing", "Asia/Harbin"].contains(TimeZone.current.identifier)
    }

    func mapCoordinate(for wgs84: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard chinaUsesGCJ02, ChinaCoordinates.isInMainlandChina(wgs84) else { return wgs84 }
        return ChinaCoordinates.gcj02(fromWGS84: wgs84)
    }

    /// A point read off the map (the middle of the view) in WGS-84, the system content and H3 use.
    func wgs84(fromMap point: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard chinaUsesGCJ02, ChinaCoordinates.isInMainlandChina(point) else { return point }
        return ChinaCoordinates.wgs84(fromGCJ02: point)
    }

    /// Runs one small MapKit search and updates the answer. Safe to call often.
    func calibrate() async {
        guard !isCalibrating else { return }
        isCalibrating = true
        defer { isCalibrating = false }

        let wgs = Self.landmark
        let gcj = ChinaCoordinates.gcj02(fromWGS84: wgs)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "东方明珠"
        request.region = MKCoordinateRegion(center: wgs, latitudinalMeters: 4_000, longitudinalMeters: 4_000)
        request.resultTypes = .pointOfInterest
        do {
            let response = try await MKLocalSearch(request: request).start()
            let candidates = response.mapItems.compactMap { item -> CLLocation? in
                let coordinate = Self.coordinate(of: item)
                return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            }
            let wgsLocation = CLLocation(latitude: wgs.latitude, longitude: wgs.longitude)
            let gcjLocation = CLLocation(latitude: gcj.latitude, longitude: gcj.longitude)
            guard let best = candidates.min(by: {
                min($0.distance(from: wgsLocation), $0.distance(from: gcjLocation))
                    < min($1.distance(from: wgsLocation), $1.distance(from: gcjLocation))
            }) else { return }
            let toWGS = best.distance(from: wgsLocation)
            let toGCJ = best.distance(from: gcjLocation)
            // The two candidates are about 500 m apart. Only trust a clear answer.
            guard min(toWGS, toGCJ) < 200 else { return }
            update(usesGCJ02: toGCJ < toWGS)
            logger.info("Calibrated: \(toGCJ < toWGS ? "GCJ-02" : "WGS-84", privacy: .public) (\(Int(toWGS)) m / \(Int(toGCJ)) m)")
        } catch {
            logger.info("Calibration search failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func update(usesGCJ02: Bool) {
        UserDefaults.standard.set(usesGCJ02, forKey: Self.key)
        guard usesGCJ02 != chinaUsesGCJ02 else { return }
        chinaUsesGCJ02 = usesGCJ02
        version += 1
    }

    private static func coordinate(of item: MKMapItem) -> CLLocationCoordinate2D {
        if #available(iOS 26.0, *) {
            return item.location.coordinate
        }
        return item.placemark.coordinate
    }
}
