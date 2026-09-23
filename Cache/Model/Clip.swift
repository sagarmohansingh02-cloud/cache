import Foundation
import SwiftData

/// One thing you copied, or one screenshot you took.
///
/// `@Model` is SwiftData's macro: it backs every stored property with the
/// database, so this reads as a plain class. Anything added after the first
/// release is optional, which is what lets SwiftData migrate an existing
/// store in place when the app updates instead of starting it empty.
@Model
final class Clip {
    var id: UUID
    var createdAt: Date

    /// A `ClipKind` raw value. Stored as a string so new kinds never need a
    /// schema migration.
    var kind: String

    /// The copied text — or a hex code, or newline-separated file paths.
    var text: String?

    /// Image bytes live on disk; the database only holds their filenames.
    var imageFilename: String?
    var thumbnailFilename: String?

    /// Text Vision found in an image. Empty means "looked, found nothing";
    /// nil means "not looked at yet".
    var ocrText: String?

    var sourceAppName: String?
    var sourceAppBundleID: String?

    /// Starred. Starred clips survive the history limit and Clear History.
    /// (Named `isPinned` because that is the column existing stores have.)
    var isPinned: Bool

    /// The collection this clip is filed in, if any.
    var category: String?

    // MARK: Added in 2.0

    var pixelWidth: Int?
    var pixelHeight: Int?
    var byteSize: Int?

    /// Where a screenshot was saved, for Show in Finder and so a drag-out
    /// lands with its real name rather than an internal one.
    var originalPath: String?

    init(
        kind: ClipKind,
        text: String? = nil,
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        category: String? = nil
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.kind = kind.rawValue
        self.text = text
        self.imageFilename = nil
        self.thumbnailFilename = nil
        self.ocrText = nil
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.isPinned = false
        self.category = category
        self.pixelWidth = nil
        self.pixelHeight = nil
        self.byteSize = nil
        self.originalPath = nil
    }
}

// MARK: - Reading a clip

extension Clip {
    var clipKind: ClipKind { ClipKind(rawValue: kind) ?? .text }

    /// Screenshots are recognised by where they came from, not by the
    /// collection they sit in — filing one into "Receipts" keeps it a screenshot.
    var isScreenshot: Bool {
        sourceAppBundleID == SourceApp.screenshot.bundleID
            || sourceAppName == SourceApp.screenshot.name
    }

    /// A bounded slice of the text for cards. Laying out a multi-megabyte
    /// paste just to show four lines of it is the kind of work that makes a
    /// strip stutter.
    var previewText: String {
        let raw = text ?? ""
        let slice = raw.count > 600 ? String(raw.prefix(600)) : raw
        return slice.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var filePaths: [String] {
        guard clipKind == .file else { return [] }
        return (text ?? "").split(separator: "\n").map(String.init)
    }

    var linkURL: URL? {
        guard clipKind == .link, let text else { return nil }
        return URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// "3.5 MB" for images, the way the Finder would say it.
    var sizeLabel: String? {
        guard let byteSize, byteSize > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file)
    }

    var dimensionsLabel: String? {
        guard let pixelWidth, let pixelHeight else { return nil }
        return "\(pixelWidth) × \(pixelHeight)"
    }

    /// Case- and diacritic-insensitive, like the Finder. Covers the words
    /// inside screenshots as well as the clip's own text.
    func matches(_ query: String) -> Bool {
        for field in [text, ocrText, sourceAppName, category] {
            if let field, field.localizedStandardContains(query) { return true }
        }
        return false
    }
}

/// The app a clip came from.
struct SourceApp: Equatable, Sendable {
    let name: String?
    let bundleID: String?

    /// macOS screenshots have no copying app, so they are credited to the
    /// Screenshot utility — which also gives their cards the right icon.
    static let screenshot = SourceApp(name: "Screenshot", bundleID: "com.apple.screenshot.launcher")

    /// Files and text dropped onto the notch.
    static let drop = SourceApp(name: "Drop", bundleID: nil)
}
