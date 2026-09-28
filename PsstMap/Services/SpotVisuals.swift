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
    private let memory = NSCache<NSString, CachedPicture>()
    private var inFlight: [String: Task<Picture?, Never>] = [:]
    private let limiter = NewestFirstLimiter(limit: 2)
    private let availability: LookAroundAvailability
    private let diskFolder: URL?

    private init() {
        availability = LookAroundAvailability()
        memory.countLimit = 24
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        diskFolder = caches?.appendingPathComponent("visuals-v2", isDirectory: true)
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

    /// A still picture for feed cards, delivered progressively: `update` is called with a map picture as
    /// soon as one is ready, then again with a Look Around picture if Apple has one. Returns the best found.
    @discardableResult
    func picture(for place: Place, size: CGSize, scale: CGFloat, dark: Bool,
                 update: ((Picture) -> Void)? = nil) async -> Picture? {
        let size = CGSize(width: size.width.rounded(), height: size.height.rounded())
        guard size.width > 10, size.height > 10 else { return nil }
        let key = cacheKey(place: place, size: size, scale: scale, dark: dark)
        if let cached = memory.object(forKey: key as NSString) {
            let picture = Picture(image: cached.image, source: cached.source)
            update?(picture)
            return picture
        }
        if let cached = await readDisk(key: key) {
            remember(cached, key: key)
            update?(cached)
            if cached.source == .lookAround || place.isInMainlandChina || place.spot.size != .small { return cached }
        }
        // Someone else (usually the launch warm-up) is already making this picture: wait for theirs.
        if let running = inFlight[key] {
            let result = await running.value
            if let result { update?(result) }
            return result
        }
        let task = Task { await generate(for: place, size: size, scale: scale, dark: dark, key: key, update: update) }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    private func generate(for place: Place, size: CGSize, scale: CGFloat, dark: Bool, key: String,
                          update: ((Picture) -> Void)?) async -> Picture? {
        await limiter.acquire()
        defer { limiter.release() }
        // Look Around faces whatever is nearest the coordinate. For a statue or a doorway that is the thing
        // itself, and it is quick; for a building it is usually a blank wall, so bigger places get the 3D map.
        var best: Picture?
        if (place.spot.size ?? .medium) == .small {
            best = await lookAroundPicture(for: place, size: size, scale: scale, dark: dark)
        }
        if best == nil, memory.object(forKey: key as NSString) == nil {
            best = await mapPicture(for: place, size: size, scale: scale, dark: dark)
        }
        if let best {
            update?(best)
            remember(best, key: key)
            writeDisk(best, key: key)
        }
        return best ?? memory.object(forKey: key as NSString).map { Picture(image: $0.image, source: $0.source) }
    }

    private func remember(_ picture: Picture, key: String) {
        memory.setObject(CachedPicture(image: picture.image, source: picture.source), forKey: key as NSString)
    }

    private func lookAroundPicture(for place: Place, size: CGSize, scale: CGFloat, dark: Bool) async -> Picture? {
        guard let scene = await lookAroundScene(for: place) else { return nil }
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

    private func mapPicture(for place: Place, size: CGSize, scale: CGFloat, dark: Bool) async -> Picture? {
        let options = MKMapSnapshotter.Options()
        options.camera = MapFraming.camera(for: place)
        options.preferredConfiguration = MapFraming.shows3D(place)
            ? MKHybridMapConfiguration(elevationStyle: .realistic)
            : MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        options.pointOfInterestFilter = .excludingAll
        options.size = size
        options.traitCollection = Self.traits(scale: scale, dark: dark)
        do {
            let snapshot = try await MKMapSnapshotter(options: options).start()
            let point = snapshot.point(for: place.mapCoordinate)
            let image = MapFraming.shows3D(place)
                ? Self.drawMarker(on: snapshot.image, at: point, kind: place.spot.kind)
                : Self.drawPin(on: snapshot.image, at: point, kind: place.spot.kind)
            return Picture(image: image, source: .map)
        } catch {
            logger.info("Map snapshot failed for \(place.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// On a flat map the place gets a proper pin with its icon, so it reads at a glance.
    private static func drawPin(on image: UIImage, at point: CGPoint, kind: Spot.Kind) -> UIImage {
        let bounds = CGRect(origin: .zero, size: image.size)
        guard bounds.insetBy(dx: -20, dy: -20).contains(point) else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            image.draw(at: .zero)
            let cg = context.cgContext
            let diameter: CGFloat = 40
            let circle = CGRect(x: point.x - diameter / 2, y: point.y - diameter - 8, width: diameter, height: diameter)
            cg.setShadow(offset: CGSize(width: 0, height: 2), blur: 8, color: UIColor.black.withAlphaComponent(0.35).cgColor)
            // Stem pointing at the exact spot.
            let stem = UIBezierPath()
            stem.move(to: CGPoint(x: point.x - 7, y: circle.maxY - 3))
            stem.addLine(to: CGPoint(x: point.x + 7, y: circle.maxY - 3))
            stem.addLine(to: CGPoint(x: point.x, y: point.y))
            stem.close()
            UIColor.white.setFill()
            stem.fill()
            cg.fillEllipse(in: circle)
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            kind.uiColor.setFill()
            cg.fillEllipse(in: circle.insetBy(dx: 3, dy: 3))
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            if let symbol = UIImage(systemName: kind.symbol, withConfiguration: symbolConfig)?
                .withTintColor(kind.onUIColor, renderingMode: .alwaysOriginal) {
                let origin = CGPoint(x: circle.midX - symbol.size.width / 2, y: circle.midY - symbol.size.height / 2)
                symbol.draw(at: origin)
            }
            UIColor.white.setFill()
            cg.fillEllipse(in: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5))
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
        let datum = place.isInMainlandChina && MapDatum.shared.chinaUsesGCJ02 ? "-gcj" : ""
        return "\(safeID)\(datum)-\(Int(size.width))x\(Int(size.height))@\(Int(scale))-\(dark ? "d" : "l")"
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
        let mapURL = diskFolder.appendingPathComponent("\(key)-map.jpg")
        let isLookAround = picture.source == .lookAround
        Task.detached(priority: .background) {
            try? data.write(to: url, options: .atomic)
            if isLookAround { try? FileManager.default.removeItem(at: mapURL) }
        }
    }
}

private final class CachedPicture {
    let image: UIImage
    let source: SpotVisuals.Source

    init(image: UIImage, source: SpotVisuals.Source) {
        self.image = image
        self.source = source
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
    /// Countries where Apple Maps has realistic 3D buildings for city centers. Elsewhere (Shanghai and
    /// Kuala Lumpur today) a tilted view is just stretched satellite imagery, so a flat map reads better.
    private static let countriesWith3D: Set<String> = ["GB", "US", "CA", "FR", "DE", "ES", "IT", "NL", "IE", "JP", "AU"]

    static func shows3D(_ place: Place) -> Bool {
        countriesWith3D.contains(place.countryCode) && (place.spot.size ?? .medium) != .small
    }

    static func distance(for place: Place) -> CLLocationDistance {
        if shows3D(place) {
            // Close enough that MapKit allows a steep tilt, far enough to show the whole thing.
            return (place.spot.size ?? .medium) == .large ? 820 : 430
        }
        switch place.spot.size ?? .medium {
        case .small: return 420
        case .medium: return 600
        case .large: return 1_100
        }
    }

    static func pitch(for place: Place) -> CGFloat { shows3D(place) ? 60 : 0 }

    /// A heading that is stable per place, so the same place always looks the same but neighbors vary.
    /// Flat maps stay north-up, which is what people expect from a map.
    static func heading(for place: Place) -> CLLocationDirection {
        guard shows3D(place) else { return 0 }
        let sum = place.id.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value }
        return CLLocationDirection(sum % 360)
    }

    static func camera(for place: Place) -> MKMapCamera {
        MKMapCamera(lookingAtCenter: place.mapCoordinate, fromDistance: distance(for: place),
                    pitch: pitch(for: place), heading: heading(for: place))
    }
}

/// Lets a few jobs run at once and starts the newest waiting job first, which is usually the one
/// the person is looking at right now rather than something prefetched earlier.
@MainActor
private final class NewestFirstLimiter {
    private let limit: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        if waiting.isEmpty {
            running -= 1
        } else {
            // The freed slot passes straight to the newest waiter.
            waiting.removeLast().resume()
        }
    }
}
