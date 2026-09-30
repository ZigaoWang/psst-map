import ImageIO
import OSLog
import SwiftUI
import UIKit

/// Downloads and caches place photos. Photo files are named by their hash and never change, so the disk
/// cache can keep them as long as the system allows. Decoded images are kept in memory while scrolling.
nonisolated final class PhotoLoader: Sendable {
    static let shared = PhotoLoader()

    enum Size: Sendable {
        case thumb, full
    }

    private let session: URLSession
    private let baseURL: URL
    nonisolated(unsafe) private let memory = NSCache<NSString, UIImage>()
    private let logger = Logger(subsystem: "app.psstmap", category: "photos")

    init(baseURL: URL = ContentUpdater.configuredBaseURL()) {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Photos", isDirectory: true)
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 400 << 20, directory: directory)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.httpAdditionalHeaders = ["Accept": "image/jpeg"]
        session = URLSession(configuration: configuration)
        self.baseURL = baseURL
        memory.totalCostLimit = 80 << 20
    }

    func url(for rendition: Photo.Rendition) -> URL {
        baseURL.appendingPathComponent("images").appendingPathComponent(rendition.file)
    }

    /// The photo decoded to at most `maxPixels` on its long side, or nil when it can't be loaded.
    func image(_ photo: Photo, size: Size, maxPixels: CGFloat) async -> UIImage? {
        let rendition = size == .full ? photo.full : photo.thumb
        let key = "\(rendition.file)@\(Int(maxPixels))" as NSString
        if let cached = memory.object(forKey: key) { return cached }
        do {
            let (data, response) = try await session.data(from: url(for: rendition))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            guard let image = Self.decode(data, maxPixels: maxPixels) else { return nil }
            memory.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4))
            return image
        } catch {
            if !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                logger.error("Photo \(rendition.file, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
            return nil
        }
    }

    /// Downloads a photo into the disk cache ahead of time, so it's ready when its card comes up.
    func prefetch(_ photo: Photo, size: Size = .full) async {
        _ = try? await session.data(from: url(for: size == .full ? photo.full : photo.thumb))
    }

    /// Decodes straight to the display size, which is much lighter than decoding the whole file.
    private static func decode(_ data: Data, maxPixels: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixels, 64),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

/// A place photo filling its frame, cropped around the photo's focus point, with its alt text for VoiceOver.
struct PlacePhotoImage: View {
    let photo: Photo
    var size: PhotoLoader.Size = .thumb
    var placeholder: Color = Color(.secondarySystemFill)
    /// Called once the image is on screen (or has failed), for views that fall back to something else.
    var onLoad: ((Bool) -> Void)?

    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                placeholder
                if let image {
                    let frame = Self.fill(imageSize: image.size, in: geometry.size)
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: frame.width, height: frame.height)
                        .offset(Self.offset(for: photo, filled: frame, in: geometry.size))
                        .transition(.opacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .task(id: "\(photo.id)-\(Int(max(geometry.size.width, geometry.size.height)))") {
                // The photo's long side once it fills the frame, in pixels.
                let filled = Self.fill(imageSize: CGSize(width: photo.full.width, height: photo.full.height),
                                       in: geometry.size)
                let needed = max(filled.width, filled.height) * min(displayScale, 3)
                // The thumbnail is enough for small frames even when the full size was asked for.
                let thumbLongest = CGFloat(max(photo.thumb.width, photo.thumb.height))
                let rendition: PhotoLoader.Size = size == .full && needed > thumbLongest * 1.2 ? .full : .thumb
                let loaded = await PhotoLoader.shared.image(photo, size: rendition, maxPixels: needed)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.25)) { image = loaded }
                onLoad?(loaded != nil)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(photo.alt)
        .accessibilityAddTraits(.isImage)
    }

    /// The size that fills `container` while keeping the photo's proportions.
    static func fill(imageSize: CGSize, in container: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return container }
        let scale = max(container.width / imageSize.width, container.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    /// Moves the filled photo so its focus point is as close to the center as the edges allow.
    static func offset(for photo: Photo, filled: CGSize, in container: CGSize) -> CGSize {
        let spareX = (filled.width - container.width) / 2
        let spareY = (filled.height - container.height) / 2
        let x = (0.5 - photo.focusX) * filled.width
        let y = (0.5 - photo.focusY) * filled.height
        return CGSize(width: min(max(x, -spareX), spareX), height: min(max(y, -spareY), spareY))
    }
}

extension Photo {
    /// "Photo: Jane Smith, CC BY-SA 4.0", or with the year for historic photos.
    var creditLine: String {
        let who = credit.source == "owner" ? credit.author : "\(credit.author), \(credit.license)"
        if kind == .historic, let year {
            return String(localized: "Photo \(String(year)): \(who)")
        }
        return String(localized: "Photo: \(who)")
    }
}
