import Foundation
import SwiftData

/// One captured pasteboard item.
///
/// `@Model` is SwiftData's macro. It rewrites this class at compile time so every
/// stored property is backed by the database — you write plain Swift, SwiftData
/// handles persistence. No schema file, no migration boilerplate for now.
///
/// Phase A only populates the text fields. The image/OCR/category fields are
/// declared now so Phase B and D don't require a schema migration.
@Model
final class Clip {
    var id: UUID
    var createdAt: Date

    /// "text" | "link" | "image" | "color" | "code" | "file".
    /// Stored as String rather than an enum because SwiftData handles primitives
    /// most predictably, and it keeps the schema stable if we add kinds later.
    var kind: String

    /// Text content, or a file path string, or a hex code — depending on `kind`.
    var text: String?

    var imageFilename: String?
    var thumbnailFilename: String?
    var ocrText: String?

    var sourceAppName: String?
    var sourceAppBundleID: String?

    var isPinned: Bool

    /// User-created category name. nil means it lives in plain History.
    var category: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        kind: String,
        text: String? = nil,
        imageFilename: String? = nil,
        thumbnailFilename: String? = nil,
        ocrText: String? = nil,
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        isPinned: Bool = false,
        category: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.text = text
        self.imageFilename = imageFilename
        self.thumbnailFilename = thumbnailFilename
        self.ocrText = ocrText
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.isPinned = isPinned
        self.category = category
    }
}
