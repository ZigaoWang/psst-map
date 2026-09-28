import CoreLocation
import Foundation

/// Converts WGS-84 coordinates to GCJ-02 for places in mainland China.
///
/// Content always stores WGS-84 (from Wikidata or OpenStreetMap). Apple Maps draws mainland China from
/// licensed map data in the GCJ-02 system, which is offset from WGS-84 by a few hundred meters. Anything
/// placed on the map (pins, cameras, snapshots, handoff to Apple Maps) must go through `mapCoordinate(for:)`.
/// Distance math against Core Location, which reports WGS-84 everywhere, uses the original coordinate.
/// Hong Kong, Macau, and Taiwan are not shifted.
nonisolated enum ChinaCoordinates {
    private static let a = 6378245.0
    private static let ee = 0.006_693_421_622_965_943_23

    /// Rough outline of mainland China as bounding rectangles (north, west, south, east).
    private static let included: [(Double, Double, Double, Double)] = [
        (49.2204, 79.4462, 42.8899, 96.3300),
        (54.1415, 109.6872, 39.3742, 135.0002),
        (42.8899, 73.1246, 29.5297, 124.1433),
        (29.5297, 82.9684, 26.7186, 97.0352),
        (29.5297, 97.0253, 20.4141, 124.3674),
        (20.4141, 107.9758, 17.8715, 111.7441),
    ]

    /// Areas inside those rectangles that are not shifted: Taiwan, Hong Kong, Macau, and slices of
    /// neighboring countries.
    private static let excluded: [(Double, Double, Double, Double)] = [
        (25.3986, 119.9213, 21.7850, 122.4976), // Taiwan
        (22.5700, 113.8200, 22.1400, 114.4500), // Hong Kong
        (22.2200, 113.5200, 22.1000, 113.6100), // Macau
        (22.2840, 101.8652, 20.0988, 106.6650),
        (21.5422, 106.4525, 20.4878, 108.0510),
        (55.8175, 109.0323, 50.3257, 119.1270),
        (55.8175, 127.4568, 49.5574, 137.0227),
        (44.8922, 131.2662, 42.5692, 137.0227),
    ]

    static func isInMainlandChina(_ coordinate: CLLocationCoordinate2D) -> Bool {
        func inside(_ box: (Double, Double, Double, Double)) -> Bool {
            coordinate.latitude <= box.0 && coordinate.latitude >= box.2
                && coordinate.longitude >= box.1 && coordinate.longitude <= box.3
        }
        return included.contains(where: inside) && !excluded.contains(where: inside)
    }

    /// The coordinate to use on Apple Maps for a WGS-84 coordinate.
    static func mapCoordinate(for wgs84: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        isInMainlandChina(wgs84) ? gcj02(fromWGS84: wgs84) : wgs84
    }

    static func gcj02(fromWGS84 wgs: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let x = wgs.longitude - 105.0
        let y = wgs.latitude - 35.0
        var dLat = transformLatitude(x: x, y: y)
        var dLon = transformLongitude(x: x, y: y)
        let radLat = wgs.latitude / 180.0 * .pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)
        dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * .pi)
        dLon = (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * .pi)
        return CLLocationCoordinate2D(latitude: wgs.latitude + dLat, longitude: wgs.longitude + dLon)
    }

    private static func transformLatitude(x: Double, y: Double) -> Double {
        var result = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        result += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        result += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        result += (160.0 * sin(y / 12.0 * .pi) + 320.0 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        return result
    }

    private static func transformLongitude(x: Double, y: Double) -> Double {
        var result = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        result += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        result += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        result += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        return result
    }
}
