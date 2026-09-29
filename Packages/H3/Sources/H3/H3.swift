import CH3
import Foundation

/// The H3 cell containing a WGS-84 coordinate, as the 15-character hex id H3 uses everywhere else.
public enum H3 {
    public static func cell(latitude: Double, longitude: Double, resolution: Int) -> String? {
        guard (0...15).contains(resolution), latitude.isFinite, longitude.isFinite else { return nil }
        var point = LatLng(lat: latitude * .pi / 180, lng: longitude * .pi / 180)
        var index: H3Index = 0
        guard latLngToCell(&point, Int32(resolution), &index) == 0 else { return nil }
        return String(index, radix: 16)
    }
}
