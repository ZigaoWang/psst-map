import Foundation
import OSLog

/// Loads the bundled area files. A broken file is skipped and logged rather than taking the app down;
/// The validator in psst-content and the unit tests are there to stop that from ever shipping.
nonisolated enum ContentLoader {
    static let supportedSchemaVersion = 1
    private static let logger = Logger(subsystem: "app.psstmap", category: "content")

    struct Result: Sendable {
        let catalog: Catalog
        let failedFiles: [String]
    }

    enum LoadError: LocalizedError {
        case missingContent
        var errorDescription: String? { "The places bundled with the app could not be found." }
    }

    static func areaFileURLs(in bundle: Bundle = .main) -> [URL] {
        guard let folder = bundle.url(forResource: "areas", withExtension: nil, subdirectory: "Content") else {
            return []
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func decodeArea(at url: URL) throws -> Area {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Area.self, from: data)
    }

    static func load(from bundle: Bundle = .main) throws -> Result {
        let urls = areaFileURLs(in: bundle)
        guard !urls.isEmpty else { throw LoadError.missingContent }
        var areas: [Area] = []
        var failed: [String] = []
        for url in urls {
            do {
                let area = try decodeArea(at: url)
                guard area.schemaVersion <= supportedSchemaVersion else {
                    logger.error("Skipping \(url.lastPathComponent, privacy: .public): schema \(area.schemaVersion)")
                    failed.append(url.lastPathComponent)
                    continue
                }
                // Facts are the product. A spot without any cannot be shown.
                let usable = area.spots.filter { !$0.facts.isEmpty }
                areas.append(Area(schemaVersion: area.schemaVersion, id: area.id, name: area.name, city: area.city,
                                  countryCode: area.countryCode, summary: area.summary,
                                  researchedOn: area.researchedOn, bounds: area.bounds, spots: usable))
            } catch {
                logger.error("Could not decode \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
                failed.append(url.lastPathComponent)
            }
        }
        if areas.isEmpty { throw LoadError.missingContent }
        return Result(catalog: Catalog(areas: areas), failedFiles: failed)
    }
}
