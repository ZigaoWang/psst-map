import Foundation
import OSLog

/// Downloads newer content in the background. Only packs whose hash changed are downloaded; the rest
/// are copied from the content already on the device. The new version is used only after every pack
/// matches its hash and the whole set decodes, so a bad or partial download can never reach the screen.
actor ContentUpdater {
    static let productionBaseURL = URL(string: "https://psst.zigao.wang")!

    private let baseURL: URL
    private let session: URLSession
    private let logger = Logger(subsystem: "app.psstmap", category: "content")

    init(baseURL: URL = ContentUpdater.configuredBaseURL(), session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    nonisolated static func configuredBaseURL() -> URL {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "debug.contentBaseURL"), let url = URL(string: override) {
            return url
        }
        #endif
        return productionBaseURL
    }

    private var channelURL: URL {
        baseURL.appendingPathComponent("content/production/v\(ContentLibrary.formatVersion)")
    }

    /// Returns newly installed content, or nil when the current content is already the newest.
    func update(current: ContentLibrary.Loaded?) async throws -> ContentLibrary.Loaded? {
        var request = URLRequest(url: channelURL.appendingPathComponent("manifest.json"),
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let manifest = try JSONDecoder().decode(ContentManifest.self, from: data)
        guard manifest.formatVersion == ContentLibrary.formatVersion,
              manifest.contentVersion > (current?.manifest.contentVersion ?? "") else { return nil }

        let fileManager = FileManager.default
        let incoming = ContentLibrary.cacheRoot.appendingPathComponent(".incoming-\(manifest.contentVersion)")
        try? fileManager.removeItem(at: incoming)
        try fileManager.createDirectory(at: incoming.appendingPathComponent("packs"), withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: incoming) }

        var downloaded = 0
        for pack in manifest.packs {
            let destination = incoming.appendingPathComponent(pack.file)
            if let current, fileManager.fileExists(atPath: current.directory.appendingPathComponent(pack.file).path) {
                try fileManager.copyItem(at: current.directory.appendingPathComponent(pack.file), to: destination)
                continue
            }
            let (packData, packResponse) = try await session.data(from: channelURL.appendingPathComponent(pack.file))
            guard (packResponse as? HTTPURLResponse)?.statusCode == 200 else {
                throw ContentLibrary.LoadError.corrupt("\(pack.file) is unavailable")
            }
            try ContentLibrary.verify(packData, against: pack)
            try packData.write(to: destination, options: .atomic)
            downloaded += 1
        }
        try data.write(to: incoming.appendingPathComponent("manifest.json"), options: .atomic)

        // Decode everything before switching over.
        _ = try ContentLibrary.load(directory: incoming, source: .downloaded)
        let final = ContentLibrary.cacheRoot.appendingPathComponent(manifest.contentVersion, isDirectory: true)
        try? fileManager.removeItem(at: final)
        try fileManager.moveItem(at: incoming, to: final)
        try ContentLibrary.makeCurrent(version: manifest.contentVersion)
        removeOldVersions(keeping: [manifest.contentVersion, current?.manifest.contentVersion].compactMap { $0 })
        logger.info("Installed content \(manifest.contentVersion, privacy: .public), \(downloaded) packs downloaded")
        return try ContentLibrary.load(directory: final, source: .downloaded)
    }

    private func removeOldVersions(keeping versions: [String]) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(atPath: ContentLibrary.cacheRoot.path) else { return }
        for entry in entries where entry != "current" && !versions.contains(entry) {
            try? fileManager.removeItem(at: ContentLibrary.cacheRoot.appendingPathComponent(entry))
        }
    }
}
