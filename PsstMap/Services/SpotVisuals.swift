@preconcurrency import MapKit
import OSLog
import UIKit

/// Finds and caches the picture of a place: a Look Around street view where Apple has one, otherwise a
/// pitched 3D map view. Nothing here depends on services that are blocked in mainland China.
@MainActor
final class SpotVisuals {
    static let shared = SpotVisuals()

    enum Source: Sendable {
        case lookAround
        case map
    }

    struct Picture {
        let image: UIImage
        let source: Source
    }

    private let logger = Logger(subsystem: "app.psstmap", category: "visuals")
    private var scenes: [String: MKLookAroundScene] = [:]
    private var sceneTasks: [String: Task<MKLookAroundScene?, Never>] = [:]
    private var pictureTasks: [String: Task<Picture?, Never>] = [:]
    private let memory = NSCache<NSString, UIImage>()
    private let availability: LookAroundAvailability
    private let diskFolder: URL?

    private init() {
        availability = LookAroundAvailability()
        memory.countLimit = 60
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        diskFolder = caches?.appendingPathComponent("visuals-v1", isDirectory: true)
        if let diskFolder {
            try? FileManager.default.createDirectory(at: diskFolder, withIntermediateDirectories: true)
        }
    }

    // MARK: Look Around

    /// The Look Around scene for a place, or nil if there is none (always nil in mainland China).
    func lookAroundScene(for place: Place) async -> MKLookAroundScene? {
        if place.isInMainlandChina { return nil }
        if let scene = scenes[place.id] { return scene }
        if availability.knownUnavailable(place.id) { return nil }
        if let task = sceneTasks[place.id] { return await task.value }

        let coordinate = place.mapCoordinate
        let id = place.id
        let task = Task<MKLookAroundScene?, Never> { [weak self] in
            do {
                let scene = try await MKLookAroundSceneRequest(coordinate: coordinate).scene
                self?.availability.record(id, available: scene != nil)
                return scene
            } catch {
                // Network or throttling errors are not remembered, so the next attempt can succeed.
                self?.logger.info("Look Around lookup failed for \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        sceneTasks[place.id] = task
        let scene = await task.value
        sceneTasks[place.id] = nil
        if let scene { scenes[place.id] = scene }
        return scene
    }

    // MARK: Pictures

    /// A still picture for feed cards and lists.
    func picture(for place: Place, size: CGSize, scale: CGFloat, dark: Bool) async -> Picture? {
        let size = CGSize(width: size.width.rounded(), height: size.height.rounded())
        guard size.width > 10, size.height > 10 else { return nil }
        let key = cacheKey(place: place, size: size, scale: scale, dark: dark)
        if let image = memory.object(forKey: key as NSString) {
            return Picture(image: image, source: sourceFromKeyCache(key))
        }
        if let task = pictureTasks[key] { return await task.value }

        let task = Task<Picture?, Never> { [weak self] in
            guard let self else { return nil }
            if let cached = await self.readDisk(key: key) {
                return cached
            }
            var picture: Picture?
            if let scene = await self.lookAroundScene(for: place) {
                picture = await self.lookAroundSnapshot(scene: scene, size: size, scale: scale, dark: dark)
            }
            if picture == nil {
                picture = await self.mapSnapshot(for: place, size: size, scale: scale, dark: dark)
            }
            if let picture { self.writeDisk(picture, key: key) }
            return picture
        }
        pictureTasks[key] = task
        let picture = await task.value
        pictureTasks[key] = nil
        if let picture {
            memory.setObject(picture.image, forKey: key as NSString)
            sources[key] = picture.source
        }
        return picture
    }

    private var sources: [String: Source] = [:]
    private func sourceFromKeyCache(_ key: String) -> Source { sources[key] ?? .map }

    private func lookAroundSnapshot(scene: MKLookAroundScene, size: CGSize, scale: CGFloat, dark: Bool) async -> Picture? {
        let options = MKLookAroundSnapshotter.Options()
        options.size = size
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = Self.traits(scale: scale, dark: dark)
        do {
            let snapshot = try await MKLookAroundSnapshotter(scene: scene, options: options).snapshot
            return Picture(image: snapshot.image, source: .lookAround)
        } catch {
            logger.info("Look Around snapshot failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func mapSnapshot(for place: Place, size: CGSize, scale: CGFloat, dark: Bool) async -> Picture? {
        let options = MKMapSnapshotter.Options()
        options.camera = MapFraming.camera(for: place)
        options.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .realistic)
        options.pointOfInterestFilter = .excludingAll
        options.size = size
        options.traitCollection = Self.traits(scale: scale, dark: dark)
        do {
            let snapshot = try await MKMapSnapshotter(options: options).start()
            let point = snapshot.point(for: place.mapCoordinate)
            let image = Self.drawMarker(on: snapshot.image, at: point, kind: place.spot.kind)
            return Picture(image: image, source: .map)
        } catch {
            logger.info("Map snapshot failed for \(place.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func traits(scale: CGFloat, dark: Bool) -> UITraitCollection {
        UITraitCollection { traits in
            traits.displayScale = scale
            traits.userInterfaceStyle = dark ? .dark : .light
        }
    }

    /// Marks the exact spot on a map snapshot so it is clear which building the card is about.
    private static func drawMarker(on image: UIImage, at point: CGPoint, kind: Spot.Kind) -> UIImage {
        let bounds = CGRect(origin: .zero, size: image.size)
        guard bounds.insetBy(dx: -20, dy: -20).contains(point) else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            image.draw(at: .zero)
            let outer = CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18)
            let cg = context.cgContext
            cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 4, color: UIColor.black.withAlphaComponent(0.5).cgColor)
            UIColor.white.setFill()
            cg.fillEllipse(in: outer)
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            kind.uiColor.setFill()
            cg.fillEllipse(in: outer.insetBy(dx: 3.5, dy: 3.5))
        }
    }

    // MARK: Disk cache

    private func cacheKey(place: Place, size: CGSize, scale: CGFloat, dark: Bool) -> String {
        let safeID = place.id.replacingOccurrences(of: "/", with: "__")
        return "\(safeID)-\(Int(size.width))x\(Int(size.height))@\(Int(scale))-\(dark ? "d" : "l")"
    }

    private func readDisk(key: String) async -> Picture? {
        guard let diskFolder else { return nil }
        let candidates: [(URL, Source)] = [
            (diskFolder.appendingPathComponent("\(key)-la.jpg"), .lookAround),
            (diskFolder.appendingPathComponent("\(key)-map.jpg"), .map),
        ]
        return await Task.detached(priority: .utility) { () -> (Data, Source)? in
            for (url, source) in candidates {
                if let data = try? Data(contentsOf: url) { return (data, source) }
            }
            return nil
        }.value.flatMap { data, source in
            UIImage(data: data, scale: UITraitCollection.current.displayScale).map { Picture(image: $0, source: source) }
        }
    }

    private func writeDisk(_ picture: Picture, key: String) {
        guard let diskFolder, let data = picture.image.jpegData(compressionQuality: 0.82) else { return }
        let suffix = picture.source == .lookAround ? "la" : "map"
        let url = diskFolder.appendingPathComponent("\(key)-\(suffix).jpg")
        Task.detached(priority: .background) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

/// Remembers which places have no Look Around coverage so the app does not keep asking.
/// Entries expire after 30 days because Apple keeps adding coverage.
private final class LookAroundAvailability {
    private static let key = "visuals.lookAroundUnavailable"
    private var unavailable: [String: Date]

    init() {
        unavailable = (UserDefaults.standard.dictionary(forKey: Self.key) as? [String: Date]) ?? [:]
    }

    func knownUnavailable(_ id: String) -> Bool {
        guard let date = unavailable[id] else { return false }
        return date.timeIntervalSinceNow > -30 * 24 * 3600
    }

    func record(_ id: String, available: Bool) {
        if available {
            unavailable[id] = nil
        } else {
            unavailable[id] = Date()
        }
        UserDefaults.standard.set(unavailable, forKey: Self.key)
    }
}

/// Camera choices shared by the snapshotter and the live 3D view.
enum MapFraming {
    static func distance(for place: Place) -> CLLocationDistance {
        switch place.spot.size ?? .medium {
        case .small: 260
        case .medium: 480
        case .large: 1_150
        }
    }

    /// A heading that is stable per place, so the same place always looks the same but neighbors vary.
    static func heading(for place: Place) -> CLLocationDirection {
        let sum = place.id.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value }
        return CLLocationDirection(sum % 360)
    }

    static func camera(for place: Place) -> MKMapCamera {
        MKMapCamera(lookingAtCenter: place.mapCoordinate, fromDistance: distance(for: place), pitch: 60,
                    heading: heading(for: place))
    }
}
