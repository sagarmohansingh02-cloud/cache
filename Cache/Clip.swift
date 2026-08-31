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

    // MARK: - Added after the first schema
    //
    // Every property below is optional or carries a default. That's what lets
    // SwiftData migrate an existing store in place instead of demanding a
    // versioned migration plan — and it's why an existing history survives an
    // app update rather than being wiped.

    /// User-supplied name for the clip, shown instead of its contents.
    var title: String?

    /// How many times this clip has been pasted back. Drives "most used" sort.
    var useCount: Int = 0

    /// Last time it was pasted back, for recency sorting.
    var lastUsedAt: Date?

    /// When set, a local notification fires at this time.
    var reminderAt: Date?

    /// Position for manual sort order. Unset until the user drags something.
    var manualOrder: Int?

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
        category: String? = nil,
        title: String? = nil,
        useCount: Int = 0,
        lastUsedAt: Date? = nil,
        reminderAt: Date? = nil,
        manualOrder: Int? = nil
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
        self.title = title
        self.useCount = useCount
        self.lastUsedAt = lastUsedAt
        self.reminderAt = reminderAt
        self.manualOrder = manualOrder
    }
}
