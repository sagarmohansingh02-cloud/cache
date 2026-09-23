import AppKit
import UniformTypeIdentifiers

/// What a clip is. Raw values are what the database stores in `Clip.kind`.
enum ClipKind: String, CaseIterable, Sendable {
    case text
    case link
    case code
    case color
    case file
    case image

    /// Chip label.
    var pluralName: String {
        switch self {
        case .text:  "Text"
        case .link:  "Links"
        case .code:  "Code"
        case .color: "Colors"
        case .file:  "Files"
        case .image: "Images"
        }
    }

    var singularName: String {
        switch self {
        case .text:  "Text"
        case .link:  "Link"
        case .code:  "Code"
        case .color: "Color"
        case .file:  "File"
        case .image: "Image"
        }
    }

    var symbolName: String {
        switch self {
        case .text:  "text.alignleft"
        case .link:  "link"
        case .code:  "chevron.left.forwardslash.chevron.right"
        case .color: "paintpalette"
        case .file:  "doc"
        case .image: "photo"
        }
    }
}

// MARK: - Detection

extension ClipKind {
    /// Image flavours worth keeping as pictures. TIFF is on the list because
    /// it is what most Cocoa apps put on the pasteboard for a copied image.
    static let imagePasteboardTypes: [NSPasteboard.PasteboardType] = [
        .png,
        .tiff,
        NSPasteboard.PasteboardType(UTType.jpeg.identifier),
        NSPasteboard.PasteboardType(UTType.heic.identifier),
        NSPasteboard.PasteboardType(UTType.gif.identifier),
        NSPasteboard.PasteboardType(UTType.webP.identifier),
    ]

    /// Rich-text flavours. Office apps and text editors put a picture of the
    /// selection on the pasteboard *alongside* the text; when these are present
    /// the text is what was copied, not the picture.
    private static let richTextTypes: [NSPasteboard.PasteboardType] = [.rtf, .rtfd]

    /// Order matters: a copied file is also offered as a string, and a copied
    /// image sometimes carries a filename — so the most specific reading wins.
    static func detect(pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> ClipKind {
        if types.contains(.fileURL) { return .file }

        let string = types.contains(.string) ? pasteboard.string(forType: .string) : nil
        let hasText = !(string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasImage = types.contains(where: imagePasteboardTypes.contains)

        if hasImage && !(hasText && types.contains(where: richTextTypes.contains)) {
            return .image
        }
        guard let string, hasText else { return .text }
        return detect(text: string)
    }

    /// The string half of detection, usable without a pasteboard.
    static func detect(text: String) -> ClipKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isColor(trimmed) { return .color }
        if isLink(trimmed) { return .link }
        if isCode(text) { return .code }
        return .text
    }

    // MARK: Rules

    /// `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`, a bare `RRGGBB` that mixes
    /// letters and digits, or a CSS `rgb()` / `hsl()`.
    ///
    /// A bare six-digit number is deliberately *not* a colour: that is what a
    /// one-time passcode looks like, and swatching someone's 2FA code is wrong.
    private static func isColor(_ string: String) -> Bool {
        let hashed = "^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"
        let bare = "^(?=[0-9A-Fa-f]*[A-Fa-f])(?=[0-9A-Fa-f]*[0-9])[0-9A-Fa-f]{6}$"
        let functional = "^(rgba?|hsla?)\\([^)]*\\)$"

        return string.range(of: hashed, options: .regularExpression) != nil
            || string.range(of: bare, options: .regularExpression) != nil
            || string.range(of: functional, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Parses as a URL *and* is web-schemed — `URL(string:)` alone happily
    /// accepts "hello" with no scheme.
    private static func isLink(_ string: String) -> Bool {
        guard !string.contains(where: \.isWhitespace),
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              url.host != nil
        else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// Conservative: a semicolon alone is a sentence, so code also has to
    /// span lines.
    private static func isCode(_ string: String) -> Bool {
        guard string.contains("\n") else { return false }
        let markers = ["{", "}", ";", "=>", "def ", "func ", "import ", "const ", "return ", "</"]
        return markers.contains { string.contains($0) }
    }
}
