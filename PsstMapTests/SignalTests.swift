import CoreLocation
import MapKit
import XCTest
@testable import PsstMap

final class SendLimitTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "SendLimitTests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    private let day = 86_400.0
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    func testEachKeyOncePerWindow() {
        let limit = SendLimit(storeKey: "t", perDay: 10, window: 1)
        XCTAssertEqual(limit.take("a", now: start, defaults: defaults), .allowed)
        XCTAssertEqual(limit.take("a", now: start, defaults: defaults), .alreadySent)
        XCTAssertEqual(limit.take("a", now: start + day, defaults: defaults), .allowed, "a new day")
    }

    func testDailyCap() {
        let limit = SendLimit(storeKey: "t", perDay: 3, window: 1)
        for key in ["a", "b", "c"] { XCTAssertEqual(limit.take(key, now: start, defaults: defaults), .allowed) }
        XCTAssertEqual(limit.take("d", now: start, defaults: defaults), .dailyLimit)
        XCTAssertEqual(limit.take("d", now: start + day, defaults: defaults), .allowed)
    }

    func testLongWindowForReports() {
        let limit = ReportOutbox.limit
        XCTAssertEqual(limit.take("fa_1", now: start, defaults: defaults), .allowed)
        XCTAssertEqual(limit.take("fa_1", now: start + 60 * day, defaults: defaults), .alreadySent)
        XCTAssertEqual(limit.take("fa_1", now: start + 91 * day, defaults: defaults), .allowed)
    }
}

final class DemandSignalTests: XCTestCase {
    private let paris = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)
    private let citySpan = MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.3)

    private let london = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.12)

    func testAnEmptyCityViewSendsItsCoarseCell() {
        let cell = DemandSignal.cell(center: paris, span: citySpan, hasPlaces: false, userLocation: london)
        XCTAssertEqual(cell, "851fb467fffffff", "must match the server's h3 for the same point")
    }

    func testNothingIsSentWithoutKnowingWhereTheUserIs() {
        XCTAssertNil(DemandSignal.cell(center: paris, span: citySpan, hasPlaces: false, userLocation: nil))
    }

    func testNothingIsSentWhileTheUserIsInView() {
        let nearby = CLLocationCoordinate2D(latitude: 48.87, longitude: 2.33)
        XCTAssertNil(DemandSignal.cell(center: paris, span: citySpan, hasPlaces: false, userLocation: nearby))
        let farAway = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.12)
        XCTAssertNotNil(DemandSignal.cell(center: paris, span: citySpan, hasPlaces: false, userLocation: farAway))
    }

    func testOnlyEmptyCitySizedViews() {
        XCTAssertNil(DemandSignal.cell(center: paris, span: citySpan, hasPlaces: true, userLocation: nil))
        XCTAssertNil(DemandSignal.cell(center: paris, span: .init(latitudeDelta: 5, longitudeDelta: 5),
                                       hasPlaces: false, userLocation: nil))
        XCTAssertNil(DemandSignal.cell(center: paris, span: .init(latitudeDelta: 0.005, longitudeDelta: 0.005),
                                       hasPlaces: false, userLocation: nil))
    }
}
