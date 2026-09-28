import CoreLocation
import XCTest
@testable import PsstMap

/// Guards the bundled content from the app's side. The Python validator checks the rules in more depth.
final class ContentTests: XCTestCase {
    func testEveryBundledAreaFileDecodes() throws {
        let urls = ContentLoader.areaFileURLs()
        XCTAssertFalse(urls.isEmpty, "No area files were bundled")
        for url in urls {
            XCTAssertNoThrow(try ContentLoader.decodeArea(at: url), "\(url.lastPathComponent) does not decode")
        }
    }

    func testCatalogLoadsWithoutFailures() throws {
        let result = try ContentLoader.load()
        XCTAssertTrue(result.failedFiles.isEmpty, "Failed files: \(result.failedFiles)")
        XCTAssertFalse(result.catalog.places.isEmpty)
    }

    func testPlaceIDsAreUnique() throws {
        let catalog = try ContentLoader.load().catalog
        let ids = catalog.places.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testEverySpotSitsInsideItsAreaAndHasSourcedFacts() throws {
        let catalog = try ContentLoader.load().catalog
        for area in catalog.areas {
            XCTAssertEqual(area.schemaVersion, ContentLoader.supportedSchemaVersion)
            for spot in area.spots {
                let coordinate = CLLocationCoordinate2D(latitude: spot.coordinate.latitude,
                                                        longitude: spot.coordinate.longitude)
                XCTAssertTrue(area.bounds.contains(coordinate), "\(area.id)/\(spot.id) is outside its area")
                XCTAssertFalse(spot.facts.isEmpty, "\(area.id)/\(spot.id) has no facts")
                for fact in spot.facts {
                    XCTAssertFalse(fact.sources.isEmpty, "\(area.id)/\(spot.id)/\(fact.id) has no sources")
                    XCTAssertFalse(fact.short.contains("\u{2014}"), "\(area.id)/\(spot.id)/\(fact.id) has an em dash")
                    XCTAssertFalse(fact.long.contains("\u{2014}"), "\(area.id)/\(spot.id)/\(fact.id) has an em dash")
                }
            }
        }
    }

    func testOnlyChinesePlacesAreInMainlandChina() throws {
        let catalog = try ContentLoader.load().catalog
        for place in catalog.places {
            if place.city == "Shanghai" {
                XCTAssertTrue(place.isInMainlandChina, place.id)
                let gcj = ChinaCoordinates.gcj02(fromWGS84: place.coordinate)
                let moved = place.location.distance(from: CLLocation(latitude: gcj.latitude, longitude: gcj.longitude))
                XCTAssertGreaterThan(moved, 100, place.id)
                XCTAssertLessThan(moved, 1_000, place.id)
            } else {
                XCTAssertFalse(place.isInMainlandChina, place.id)
            }
        }
    }
}
