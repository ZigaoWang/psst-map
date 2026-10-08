import CoreLocation
import XCTest
@testable import PsstMap

final class ChinaCoordinatesTests: XCTestCase {
    func testKnownBeijingVector() {
        // Reference value used by the widely used eviltransform implementations.
        let gcj = ChinaCoordinates.gcj02(fromWGS84: .init(latitude: 39.915, longitude: 116.404))
        XCTAssertEqual(gcj.latitude, 39.91640428150164, accuracy: 1e-9)
        XCTAssertEqual(gcj.longitude, 116.41024449916938, accuracy: 1e-9)
    }

    func testShanghaiIsInMainlandChina() {
        XCTAssertTrue(ChinaCoordinates.isInMainlandChina(.init(latitude: 31.2397, longitude: 121.4998)))
    }

    func testPlacesOutsideMainlandChinaAreNotInChina() {
        let places: [CLLocationCoordinate2D] = [
            .init(latitude: 51.5007, longitude: -0.1246),  // London
            .init(latitude: 3.1466, longitude: 101.7113),  // Kuala Lumpur
            .init(latitude: 22.2855, longitude: 114.1577), // Hong Kong
            .init(latitude: 22.1987, longitude: 113.5439), // Macau
            .init(latitude: 25.0330, longitude: 121.5654), // Taipei
        ]
        for place in places {
            XCTAssertFalse(ChinaCoordinates.isInMainlandChina(place), "\(place)")
        }
    }

    @MainActor
    func testMapDatumOnlyShiftsMainlandChina() {
        let datum = MapDatum.shared
        let london = CLLocationCoordinate2D(latitude: 51.5007, longitude: -0.1246)
        let mapped = datum.mapCoordinate(for: london)
        XCTAssertEqual(mapped.latitude, london.latitude)
        XCTAssertEqual(mapped.longitude, london.longitude)
        let shanghai = CLLocationCoordinate2D(latitude: 31.2419464, longitude: 121.4952604)
        let shifted = datum.mapCoordinate(for: shanghai)
        let expected = datum.chinaUsesGCJ02 ? ChinaCoordinates.gcj02(fromWGS84: shanghai) : shanghai
        XCTAssertEqual(shifted.latitude, expected.latitude, accuracy: 1e-12)
        XCTAssertEqual(shifted.longitude, expected.longitude, accuracy: 1e-12)
    }
}

final class ChinaInverseTests: XCTestCase {
    func testReadingAPointOffAChinaMapGivesBackTheTruePosition() {
        let bund = CLLocationCoordinate2D(latitude: 31.2405, longitude: 121.4903)
        let back = ChinaCoordinates.wgs84(fromGCJ02: ChinaCoordinates.gcj02(fromWGS84: bund))
        XCTAssertEqual(back.latitude, bund.latitude, accuracy: 1e-6)
        XCTAssertEqual(back.longitude, bund.longitude, accuracy: 1e-6)
    }
}
