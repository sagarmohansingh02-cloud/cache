import AppKit
import Foundation

/// What a clip actually is. The raw values match `Clip.kind` exactly.
enum ClipKind: String, CaseIterable {
    case file
    case image
    case color
    case code
    case link
    case text

    /// Label used in the filter bar.
    var displayName: String {
        switch self {
        case .file:  "Files"
        case .image: "Images"
        case .color: "Colors"
        case .code:  "Code"
        case .link:  "Links"
        case .text:  "Text"
        }
    }

    var symbolName: String {
        switch self {
        case .file:  "doc"
        case .image: "photo"
        case .color: "paintpalette"
        case .code:  "chevron.left.forwardslash.chevron.right"
        case .link:  "link"
        case .text:  "textformat"
        }
    }
}

extension ClipKind {
    /// Detection order is deliberate: file → image → color → link → code → text.
    /// A file URL is also a valid `link`, and a hex colour is also valid `text`,
    /// so the most specific test has to run first.
    static func detect(pasteboard: NSPasteboard) -> ClipKind {
        let types = pasteboard.types ?? []

        if types.contains(.fileURL) { return .file }
        if types.contains(.tiff) || types.contains(.png) { return .image }

        guard let string = pasteboard.string(forType: .string) else { return .text }
        return detect(text: string)
    }

    /// The string-only half of detection, split out so it can be reasoned about
    /// (and tested) without a pasteboard.
    static func detect(text: String) -> ClipKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if isColor(trimmed) { return .color }
        if isLink(trimmed) { return .link }
        if isCode(text) { return .code }
        return .text
    }

    // MARK: - Rules

    /// `#RGB`, `#RRGGBB` (hash optional), or `rgb(...)` / `rgba(...)`.
    private static func isColor(_ string: String) -> Bool {
        let hex = "^#?([0-9A-Fa-f]{6}|[0-9A-Fa-f]{3})$"
        let rgb = "^rgba?\\([^)]*\\)$"

        return string.range(of: hex, options: [.regularExpression]) != nil
            || string.range(of: rgb, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Parses as a URL *and* is web-schemed. The scheme check is what stops
    /// every ordinary word from being treated as a link — `URL(string:)` alone
    /// happily accepts "hello" and just leaves the scheme nil.
    private static func isLink(_ string: String) -> Bool {
        guard !string.contains(where: \.isWhitespace),
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased()
        else { return false }

        return scheme == "http" || scheme == "https"
    }

    /// Heuristic, and deliberately conservative: a code marker on its own isn't
    /// enough (a sentence can contain a semicolon), so we also require the clip
    /// to span multiple lines.
    private static func isCode(_ string: String) -> Bool {
        guard string.contains("\n") else { return false }

        let markers = ["{", "}", ";", "=>", "def ", "func ", "import "]
        return markers.contains { string.contains($0) }
    }
}
