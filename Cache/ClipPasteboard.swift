import AppKit

/// Writing a clip back to the system pasteboard, in one place.
///
/// The notch strip, the detail card and the list all need identical behaviour
/// here, and getting it subtly different between them is how "the wrong thing
/// pasted" bugs happen.
enum ClipPasteboard {
    /// Returns false when the clip had nothing to offer.
    @discardableResult
    static func write(_ clip: Clip) -> Bool {
        let pasteboard = NSPasteboard.general
        // Mandatory before writing: NSPasteboard accumulates representations
        // otherwise, and stale types from the previous item leak into this one.
        pasteboard.clearContents()

        switch ClipKind(rawValue: clip.kind) ?? .text {
        case .image:
            // Full resolution goes back out, not the 400px thumbnail.
            guard let image = FileStorage.loadImage(named: clip.imageFilename) else { return false }
            pasteboard.writeObjects([image])

        case .file:
            let urls = (clip.text ?? "")
                .split(separator: "\n")
                .map { URL(fileURLWithPath: String($0)) as NSURL }
            guard !urls.isEmpty else { return false }
            pasteboard.writeObjects(urls)

        default:
            guard let text = clip.text, !text.isEmpty else { return false }
            pasteboard.setString(text, forType: .string)
        }

        return true
    }

    /// Plain text, used for "Copy recognized text" — deliberately separate from
    /// `write`, which would put an image on the pasteboard for an image clip.
    static func writePlainText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
