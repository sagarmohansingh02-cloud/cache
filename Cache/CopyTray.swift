import AppKit
import Observation

/// The staging shelf behind the notch pill.
///
/// This is the thing that makes the app feel alive rather than static: every
/// capture pushes onto the tray, the notch shows a running count, and the whole
/// stack can be dragged off as a unit. Copying five things in a row and dropping
/// them somewhere together replaces any notion of checkbox multi-select.
///
/// The tray holds the same `Clip` objects the store owns — it is a view onto
/// recent history, not a second copy of it. Clearing the tray never deletes
/// anything.
@MainActor
@Observable
final class CopyTray {
    static let shared = CopyTray()

    /// Most recent first.
    private(set) var items: [Clip] = []

    /// Set by whoever owns the notch windows, so they can react to the count
    /// changing without polling. A plain callback rather than observation
    /// tracking because the observer here is an AppKit controller, not a View.
    @ObservationIgnored var onChange: (() -> Void)?

    /// Fired only on a genuine new capture, so the confirmation flash doesn't
    /// replay when the shelf is merely cleared or pruned.
    @ObservationIgnored var onCapture: (() -> Void)?

    /// Past this the pill stops counting up and the oldest fall off — the tray
    /// is a shelf for a handful of things, not a second history.
    static let capacity = 12

    private init() {}

    func add(_ clip: Clip) {
        items.removeAll { $0.id == clip.id }
        items.insert(clip, at: 0)

        if items.count > Self.capacity {
            items.removeLast(items.count - Self.capacity)
        }
        onChange?()
        onCapture?()
    }

    /// Drop a clip that no longer exists, so deleting from history doesn't
    /// leave the tray pointing at a dead row.
    func remove(_ clip: Clip) {
        items.removeAll { $0.id == clip.id }
        onChange?()
    }

    func clear() {
        items.removeAll()
        onChange?()
    }

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }

    /// "5 items · Text, Image"
    var summary: String {
        let noun = count == 1 ? "item" : "items"
        guard !kindNames.isEmpty else { return "\(count) \(noun)" }
        return "\(count) \(noun) · \(kindNames.joined(separator: ", "))"
    }

    /// Distinct kinds present, in the order they appear.
    private var kindNames: [String] {
        var seen = Set<String>()
        var names: [String] = []

        for clip in items {
            guard let kind = ClipKind(rawValue: clip.kind), !seen.contains(clip.kind) else { continue }
            seen.insert(clip.kind)
            // Singular reads better here than the plural filter-chip label.
            names.append(kind.singularName)
        }
        return names
    }

    // MARK: - Dragging the stack out

    /// One dragging item per clip, so a drop lands five files rather than one
    /// blob. Images and files go out as URLs — that's what makes Finder write
    /// real files — and everything else as plain text.
    func draggingItems() -> [NSDraggingItem] {
        items.compactMap { clip in
            guard let provider = Self.provider(for: clip) else { return nil }

            let item = NSDraggingItem(pasteboardWriter: provider)
            item.setDraggingFrame(
                NSRect(x: 0, y: 0, width: 64, height: 64),
                contents: Self.dragImage(for: clip)
            )
            return item
        }
    }

    private static func provider(for clip: Clip) -> NSPasteboardWriting? {
        switch ClipKind(rawValue: clip.kind) ?? .text {
        case .image:
            guard let filename = clip.imageFilename else { return nil }
            let url = FileStorage.clipsDirectory.appendingPathComponent(filename)
            return FileManager.default.fileExists(atPath: url.path) ? url as NSURL : nil

        case .file:
            guard let first = (clip.text ?? "").split(separator: "\n").first else { return nil }
            let url = URL(fileURLWithPath: String(first))
            return FileManager.default.fileExists(atPath: url.path) ? url as NSURL : nil

        default:
            guard let text = clip.text, !text.isEmpty else { return nil }
            return text as NSString
        }
    }

    private static func dragImage(for clip: Clip) -> NSImage? {
        if let thumbnail = ThumbnailCache.thumbnail(named: clip.thumbnailFilename) {
            return thumbnail
        }
        return NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
    }
}

extension ClipKind {
    /// "Text", "Image" — for the tray summary line.
    var singularName: String {
        switch self {
        case .file:  "File"
        case .image: "Image"
        case .color: "Color"
        case .code:  "Code"
        case .link:  "Link"
        case .text:  "Text"
        }
    }
}
