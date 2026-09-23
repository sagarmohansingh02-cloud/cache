import AppKit
import UniformTypeIdentifiers

/// Putting a clip back on the system pasteboard — one implementation for the
/// strip, the keyboard and the detail panel, so "the wrong thing pasted" can
/// only ever be one bug.
@MainActor
enum ClipPasteboard {
    @discardableResult
    static func write(_ clip: Clip) -> Bool {
        let pasteboard = NSPasteboard.general

        switch clip.clipKind {
        case .image:
            // The original bytes, in their own format — never the thumbnail,
            // and never re-encoded.
            guard let url = FileStorage.url(for: clip.imageFilename),
                  let data = try? Data(contentsOf: url)
            else { return false }

            let type = UTType(filenameExtension: url.pathExtension) ?? .png
            let item = NSPasteboardItem()
            item.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
            // PNG is what nearly every app reads; add it when the original is
            // something else.
            if type != .png, let png = pngData(from: data) {
                item.setData(png, forType: .png)
            }
            pasteboard.clearContents()
            return pasteboard.writeObjects([item])

        case .file:
            let urls = clip.filePaths.map { URL(fileURLWithPath: $0) as NSURL }
            guard !urls.isEmpty else { return false }
            pasteboard.clearContents()
            return pasteboard.writeObjects(urls)

        case .text, .link, .code, .color:
            guard let text = clip.text, !text.isEmpty else { return false }
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string)
        }
    }

    /// Plain text only — used for "Copy Text" on a screenshot, where writing
    /// the clip itself would put the picture on the pasteboard.
    static func writePlainText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func pngData(from data: Data) -> Data? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
