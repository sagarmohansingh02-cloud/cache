import AppKit
import Foundation

/// Disk side of image clips.
///
/// The database never holds image bytes — it stores filenames, and the actual
/// PNGs live in `Application Support/<BundleID>/Clips/`. That's what keeps the
/// store small and lets the list render thumbnails without ever loading a
/// full-resolution screenshot into memory.
enum FileStorage {
    /// Longest edge of a generated thumbnail, in pixels.
    static let thumbnailMaxEdge: CGFloat = 400

    enum StorageError: Error {
        case notAnImage
        case encodingFailed
    }

    // MARK: - Locations

    /// `~/Library/Application Support/<BundleID>/` — the one place this app owns.
    static var containerDirectory: URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.sagarmohansingh.supaclip"
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static var clipsDirectory: URL {
        let directory = containerDirectory.appendingPathComponent("Clips", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - Writing

    /// Write the full image and a thumbnail, returning both filenames.
    static func writeImage(_ image: NSImage) throws -> (image: String, thumbnail: String) {
        guard let fullData = pngData(from: image) else { throw StorageError.encodingFailed }

        let identifier = UUID().uuidString
        let imageName = "\(identifier).png"
        let thumbnailName = "\(identifier)-thumb.png"

        try fullData.write(to: clipsDirectory.appendingPathComponent(imageName))

        let thumbnail = makeThumbnail(from: image, maxEdge: thumbnailMaxEdge)
        guard let thumbnailData = pngData(from: thumbnail) else {
            // The full image landed; without a thumbnail the row would render
            // nothing, so don't leave a half-written pair behind.
            try? FileManager.default.removeItem(at: clipsDirectory.appendingPathComponent(imageName))
            throw StorageError.encodingFailed
        }
        try thumbnailData.write(to: clipsDirectory.appendingPathComponent(thumbnailName))

        return (imageName, thumbnailName)
    }

    // MARK: - Reading

    /// Load an image off disk by filename. Callers pass thumbnail names for the
    /// list and the full name only when the user actually wants full size.
    static func loadImage(named filename: String?) -> NSImage? {
        guard let filename else { return nil }
        let url = clipsDirectory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    // MARK: - Deleting

    /// Deleting a clip row must delete its files too, or Application Support
    /// grows forever. Safe to call with nils and with already-missing files.
    static func deleteFiles(imageFilename: String?, thumbnailFilename: String?) {
        for filename in [imageFilename, thumbnailFilename].compactMap({ $0 }) {
            let url = clipsDirectory.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Helpers

    /// AppKit note, and the trap here: `NSImage.size` is in *points*, not pixels.
    /// On a Retina display a 1800px-wide image reports a size of 900. Going
    /// through `NSBitmapImageRep` gives the true pixel dimensions, which is what
    /// the 400px cap must be measured against.
    ///
    /// Drawing is the other half of the trap. `NSImage.lockFocus()` allocates a
    /// backing store at the *screen's* scale factor, so drawing into a
    /// 400-point image on a 2x display silently produces an 800-pixel file —
    /// four times the bytes we asked for, on disk and in the thumbnail cache.
    /// Building an `NSBitmapImageRep` at explicit pixel dimensions and setting
    /// its `size` to match pins one point to one pixel, so 400 means 400.
    private static func makeThumbnail(from image: NSImage, maxEdge: CGFloat) -> NSImage {
        guard let source = bitmapRepresentation(of: image) else { return image }

        let pixelWidth = CGFloat(source.pixelsWide)
        let pixelHeight = CGFloat(source.pixelsHigh)
        let longestEdge = max(pixelWidth, pixelHeight)

        // Never upscale — a small image is already its own thumbnail.
        guard longestEdge > maxEdge else { return image }

        let scale = maxEdge / longestEdge
        let targetWidth = Int((pixelWidth * scale).rounded())
        let targetHeight = Int((pixelHeight * scale).rounded())

        guard let target = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: targetWidth,
            pixelsHigh: targetHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return image }

        // 1 point == 1 pixel for this representation.
        target.size = NSSize(width: targetWidth, height: targetHeight)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        guard let context = NSGraphicsContext(bitmapImageRep: target) else { return image }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high

        image.draw(
            in: NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight),
            from: .zero,           // .zero means "the whole source image"
            operation: .copy,
            fraction: 1.0
        )
        context.flushGraphics()

        let thumbnail = NSImage(size: NSSize(width: targetWidth, height: targetHeight))
        thumbnail.addRepresentation(target)
        return thumbnail
    }

    private static func bitmapRepresentation(of image: NSImage) -> NSBitmapImageRep? {
        if let existing = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first {
            return existing
        }
        guard let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let representation = bitmapRepresentation(of: image) else { return nil }
        return representation.representation(using: .png, properties: [:])
    }
}

/// Keeps recently-shown thumbnails in memory so scrolling doesn't hit the disk
/// on every row that scrolls back into view.
///
/// `NSCache` is Foundation's self-evicting cache: unlike a Dictionary it drops
/// entries automatically under memory pressure, which is exactly what we want
/// for something sitting in the background all day. The count limit is small on
/// purpose — the list only ever shows a handful of rows, and 400px images add
/// up fast against the 80MB budget.
@MainActor
enum ThumbnailCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 40
        return cache
    }()

    static func thumbnail(named filename: String?) -> NSImage? {
        guard let filename else { return nil }

        if let cached = cache.object(forKey: filename as NSString) { return cached }
        guard let image = FileStorage.loadImage(named: filename) else { return nil }

        cache.setObject(image, forKey: filename as NSString)
        return image
    }
}
