import CoreLocation
import XCTest
@testable import PsstMap

/// Guards the content snapshot bundled with the app. The content repository checks the rules in more
/// depth before anything is published; these tests make sure the app reads what was published.
/// Content is kept outside this repository, so they skip when no snapshot is installed.
final class ContentTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = ContentLibrary.bundledDirectory
        try XCTSkipIf(directory == nil, "No content snapshot in Content/v2")
    }

    private func load() throws -> ContentLibrary.Loaded {
        try ContentLibrary.load(directory: directory, source: .bundled)
    }

    func testBundledSnapshotLoadsCompletely() throws {
        let loaded = try load()
        let counts = try XCTUnwrap(loaded.manifest.counts)
        XCTAssertEqual(loaded.catalog.places.count, counts.places)
        XCTAssertEqual(loaded.catalog.factCount, counts.facts)
    }

    func testPlaceIDsArePermanentAndUnique() throws {
        let ids = try load().catalog.places.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertTrue(ids.allSatisfy { $0.hasPrefix("pl_") })
    }

    func testEveryOldPlaceIDStillResolves() throws {
        let catalog = try load().catalog
        let common: CommonPack = try ContentLibrary.decodePack(try ContentLibrary.manifest(in: directory).common,
                                                               in: directory)
        XCTAssertFalse(common.legacyIds.isEmpty)
        for (old, new) in common.legacyIds {
            XCTAssertEqual(catalog.resolve(old), new, old)
        }
    }

    func testEveryPlaceHasACityNeighborhoodAndSourcedFacts() throws {
        let catalog = try load().catalog
        for place in catalog.places {
            XCTAssertNotNil(catalog.city(id: place.cityID), place.id)
            XCTAssertNotNil(place.neighborhoodID.flatMap { catalog.neighborhood(id: $0) }, place.id)
            for fact in place.spot.facts {
                XCTAssertFalse(fact.sources.isEmpty, "\(place.id)/\(fact.id) has no sources")
                for text in [fact.headline, fact.short, fact.long] {
                    XCTAssertFalse(text.contains("\u{2014}"), "\(place.id)/\(fact.id) has an em dash")
                }
                for tag in fact.tags {
                    XCTAssertNotNil(catalog.tag(id: tag), "\(fact.id) refers to unpublished tag \(tag)")
                }
            }
        }
    }

    func testEveryCoordinateSourceHasALicense() throws {
        for place in try load().catalog.places {
            XCTAssertNotNil(place.spot.coordinateSource.license, place.id)
            XCTAssertNotNil(place.spot.coordinateSource.url, place.id)
        }
    }

    func testOnlyChinesePlacesAreInMainlandChina() throws {
        for place in try load().catalog.places {
            if place.spot.countryCode == "CN" {
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

    func testDamagedPackIsRejected() throws {
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: directory, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        let manifest = try ContentLibrary.manifest(in: copy)
        let pack = copy.appendingPathComponent(manifest.cities[0].file)
        var data = try Data(contentsOf: pack)
        data[data.count / 2] ^= 0xFF
        try data.write(to: pack)
        XCTAssertThrowsError(try ContentLibrary.load(directory: copy, source: .downloaded))
    }
}
