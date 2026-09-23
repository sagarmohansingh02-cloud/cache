import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The files behind a new image clip, ready to be inserted.
struct StoredImage: Sendable {
    let imageFilename: String
    let thumbnailFilename: String
    let pixelWidth: Int
    let pixelHeight: Int
    let byteSize: Int
}

/// Turns a copied image or a screenshot file into stored files — entirely off
/// the main thread.
///
/// The old path decoded and re-encoded every image as PNG on the main thread,
/// which froze the app for a few hundred milliseconds on each Retina
/// screenshot. Here a screenshot is copied byte-for-byte (it is already a
/// PNG), and the thumbnail is made by ImageIO, which decodes at the reduced
/// size instead of decoding the whole picture and scaling it down.
enum ImageIngest {
    /// Longest edge of a thumbnail, in pixels. Enough to fill a card crisply
    /// on a Retina display.
    static let thumbnailMaxPixelSize = 640

    private static let queue = DispatchQueue(label: "com.sagarmohansingh.cache.image-ingest", qos: .utility)

    /// A screenshot, or any image file, copied as-is.
    static func storeFile(at source: URL) async -> StoredImage? {
        await run {
            let ext = source.pathExtension.lowercased()
            let id = UUID().uuidString
            let destination = FileStorage.clipsDirectory.appendingPathComponent("\(id).\(ext.isEmpty ? "png" : ext)")
            do {
                try FileManager.default.copyItem(at: source, to: destination)
            } catch {
                NSLog("Cache: could not copy \(source.lastPathComponent) — \(error.localizedDescription)")
                return nil
            }
            return finish(imageAt: destination, id: id)
        }
    }

    /// Bytes read off the pasteboard. PNG, JPEG, HEIC, GIF and WebP are kept
    /// in their own format; TIFF — large and uncompressed — is re-encoded as PNG.
    static func storePasteboardData(_ data: Data, type: UTType) async -> StoredImage? {
        await run {
            let id = UUID().uuidString
            let keepsFormat = type != .tiff && type.preferredFilenameExtension != nil
            let ext = keepsFormat ? (type.preferredFilenameExtension ?? "png") : "png"
            let destination = FileStorage.clipsDirectory.appendingPathComponent("\(id).\(ext)")

            if keepsFormat {
                do { try data.write(to: destination, options: .atomic) } catch { return nil }
            } else {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let target = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil)
                else { return nil }
                CGImageDestinationAddImageFromSource(target, source, 0, nil)
                guard CGImageDestinationFinalize(target) else { return nil }
            }
            return finish(imageAt: destination, id: id)
        }
    }

    /// Recreates the thumbnail and measurements for an image stored by an
    /// older version, which made smaller thumbnails and recorded no size.
    static func refreshMetadata(imageFilename: String, thumbnailFilename: String?) async -> StoredImage? {
        await run {
            guard let image = FileStorage.url(for: imageFilename),
                  FileManager.default.fileExists(atPath: image.path)
            else { return nil }
            let id = (imageFilename as NSString).deletingPathExtension
            if let old = FileStorage.url(for: thumbnailFilename) { try? FileManager.default.removeItem(at: old) }
            return finish(imageAt: image, id: id)
        }
    }

    // MARK: - Work

    private static func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    /// Thumbnail + measurements for an image already in the Clips folder.
    /// Removes the image again if it turns out not to be readable, so a
    /// half-written file never becomes a clip.
    private static func finish(imageAt url: URL, id: String) -> StoredImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let thumbnail = makeThumbnail(from: source)
        else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        let thumbnailName = "\(id)-thumb.png"
        let thumbnailURL = FileStorage.clipsDirectory.appendingPathComponent(thumbnailName)
        guard let target = CGImageDestinationCreateWithURL(thumbnailURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(target, thumbnail, nil)
        guard CGImageDestinationFinalize(target) else { return nil }

        let (width, height) = pixelSize(of: source)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0

        return StoredImage(
            imageFilename: url.lastPathComponent,
            thumbnailFilename: thumbnailName,
            pixelWidth: width,
            pixelHeight: height,
            byteSize: bytes
        )
    }

    static func makeThumbnail(from source: CGImageSource, maxPixelSize: Int = thumbnailMaxPixelSize) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func pixelSize(of source: CGImageSource) -> (Int, Int) {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return (0, 0) }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        // EXIF orientations 5–8 are rotated a quarter turn.
        if let orientation = properties[kCGImagePropertyOrientation] as? Int, orientation >= 5 {
            return (height, width)
        }
        return (width, height)
    }
}
