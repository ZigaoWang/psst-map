import CryptoKit
import Foundation
import OSLog

/// Finds, checks, and loads content in format 2: either the snapshot bundled with the app or a newer
/// version downloaded by `ContentUpdater`. The newest copy that fully checks out wins; a copy that fails
/// its hashes or doesn't decode is thrown away, so the app always falls back to the last good content.
nonisolated enum ContentLibrary {
    static let formatVersion = 2
    private static let logger = Logger(subsystem: "app.psstmap", category: "content")

    enum Source: Sendable, Equatable {
        case bundled
        case downloaded
    }

    struct Loaded: Sendable {
        let catalog: Catalog
        let manifest: ContentManifest
        let directory: URL
        let source: Source
    }

    enum LoadError: LocalizedError {
        case missing
        case corrupt(String)

        var errorDescription: String? {
            switch self {
            case .missing: "The places bundled with the app could not be found."
            case .corrupt(let detail): "The places could not be read (\(detail))."
            }
        }
    }

    static var bundledDirectory: URL? {
        Bundle.main.url(forResource: "v\(formatVersion)", withExtension: nil, subdirectory: "Content")
    }

    static var cacheRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Content/v\(formatVersion)", isDirectory: true)
    }

    private static var pointer: URL { cacheRoot.appendingPathComponent("current") }

    static func downloadedDirectory() -> URL? {
        guard let version = try? String(contentsOf: pointer, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !version.isEmpty else { return nil }
        let directory = cacheRoot.appendingPathComponent(version, isDirectory: true)
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent("manifest.json").path)
            ? directory : nil
    }

    /// Records a downloaded version as the one to load next time. Atomic: a crash leaves the old pointer.
    static func makeCurrent(version: String) throws {
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        try Data(version.utf8).write(to: pointer, options: .atomic)
    }

    /// The best content available, newest first, skipping (and removing) any downloaded copy that's broken.
    static func loadBest() throws -> Loaded {
        let bundled = bundledDirectory
        let bundledVersion = bundled.flatMap { try? manifest(in: $0).contentVersion } ?? ""
        if let downloaded = downloadedDirectory() {
            do {
                let loaded = try load(directory: downloaded, source: .downloaded)
                if loaded.manifest.contentVersion >= bundledVersion { return loaded }
            } catch {
                logger.error("Discarding downloaded content: \(error.localizedDescription, privacy: .public)")
                try? FileManager.default.removeItem(at: pointer)
                try? FileManager.default.removeItem(at: downloaded)
            }
        }
        guard let bundled else { throw LoadError.missing }
        return try load(directory: bundled, source: .bundled)
    }

    static func manifest(in directory: URL) throws -> ContentManifest {
        let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        let manifest = try JSONDecoder().decode(ContentManifest.self, from: data)
        guard manifest.formatVersion == formatVersion else {
            throw LoadError.corrupt("format \(manifest.formatVersion)")
        }
        return manifest
    }

    static func load(directory: URL, source: Source) throws -> Loaded {
        let manifest = try manifest(in: directory)
        let common: CommonPack = try decodePack(manifest.common, in: directory)
        let packs: [CityPack] = try manifest.cities.map { try decodePack($0.pack, in: directory) }
        let catalog = Catalog(common: common, packs: packs, contentVersion: manifest.contentVersion)
        guard !catalog.places.isEmpty else { throw LoadError.corrupt("no places") }
        return Loaded(catalog: catalog, manifest: manifest, directory: directory, source: source)
    }

    static func decodePack<T: Decodable>(_ reference: ContentManifest.PackReference, in directory: URL) throws -> T {
        let data = try Data(contentsOf: directory.appendingPathComponent(reference.file))
        try verify(data, against: reference)
        return try JSONDecoder().decode(T.self, from: try Gzip.decompress(data))
    }

    static func verify(_ data: Data, against reference: ContentManifest.PackReference) throws {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard data.count == reference.bytes, digest == reference.sha256 else {
            throw LoadError.corrupt("\(reference.file) doesn't match its hash")
        }
    }
}

/// Just enough gzip to read the packs: skip the header, inflate the deflate stream.
nonisolated enum Gzip {
    enum Failure: Error { case notGzip, truncated, inflate }

    static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else { throw Failure.notGzip }
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 {  // FEXTRA
            guard offset + 2 <= bytes.count else { throw Failure.truncated }
            offset += 2 + Int(bytes[offset]) + Int(bytes[offset + 1]) << 8
        }
        for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 {  // FNAME, FCOMMENT: zero-terminated
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 }  // FHCRC
        guard offset < bytes.count - 8 else { throw Failure.truncated }
        let deflated = data.subdata(in: offset..<(data.count - 8))
        guard let inflated = try? (deflated as NSData).decompressed(using: .zlib) as Data else {
            throw Failure.inflate
        }
        return inflated
    }
}
