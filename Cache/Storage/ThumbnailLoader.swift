import Foundation
import ImageIO

/// Decodes images for the strip and the detail panel off the main thread,
/// and keeps the results.
///
/// Decoding is the expensive part of showing a picture, and by default it
/// happens lazily on the main thread the first time the image is drawn —
/// which is exactly when the user is scrolling. `kCGImageSourceShouldCacheImmediately`
/// forces it to happen here, in the background, so what reaches the card is
/// ready to draw.
final class ThumbnailLoader: @unchecked Sendable {
    static let shared = ThumbnailLoader()

    private final class Entry {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    /// `NSCache` drops entries on its own under memory pressure, which is the
    /// right behaviour for something resident all day.
    private let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.totalCostLimit = 64 * 1_024 * 1_024
        return cache
    }()

    private let queue = DispatchQueue(
        label: "com.sagarmohansingh.cache.thumbnails",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private init() {}

    func cached(_ key: String) -> CGImage? {
        cache.object(forKey: key as NSString)?.image
    }

    /// The first of `candidates` that decodes, scaled so its longest edge is
    /// at most `maxPixelSize`. Every file access happens off the main thread.
    func image(candidates: [URL], maxPixelSize: Int, key: String) async -> CGImage? {
        if let hit = cached(key) { return hit }
        guard !candidates.isEmpty else { return nil }

        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                for url in candidates {
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                          let image = ImageIngest.makeThumbnail(from: source, maxPixelSize: maxPixelSize)
                    else { continue }
                    self.cache.setObject(Entry(image), forKey: key as NSString, cost: image.bytesPerRow * image.height)
                    continuation.resume(returning: image)
                    return
                }
                continuation.resume(returning: nil)
            }
        }
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

// MARK: - Clips

extension ThumbnailLoader {
    /// Cache key for a clip's card picture, or nil when the card has none.
    @MainActor
    static func cardKey(for clip: Clip) -> String? {
        if let name = clip.thumbnailFilename ?? clip.imageFilename { return "card:\(name)" }
        if let path = clip.cardImageFilePath { return "file:\(path)" }
        return nil
    }

    /// Where a card's picture can come from, best first: the stored
    /// thumbnail, then the full image, then — for a copied picture file —
    /// the file itself.
    @MainActor
    static func cardCandidates(for clip: Clip) -> [URL] {
        var urls = [FileStorage.url(for: clip.thumbnailFilename), FileStorage.url(for: clip.imageFilename)]
            .compactMap { $0 }
        if let path = clip.cardImageFilePath { urls.append(URL(fileURLWithPath: path)) }
        return urls
    }
}

extension Clip {
    /// A copied file that is itself a picture gets a picture on its card.
    var cardImageFilePath: String? {
        let paths = filePaths
        guard paths.count == 1, let path = paths.first else { return nil }
        let ext = (path as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "tif", "bmp"].contains(ext) ? path : nil
    }
}
