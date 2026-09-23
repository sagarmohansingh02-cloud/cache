import AppKit

/// Turns a colour clip's text into a colour, and back into every notation a
/// designer might want to paste.
enum ClipColor {
    static func color(from string: String?) -> NSColor? {
        guard let raw = string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let lower = raw.lowercased()
        if lower.hasPrefix("rgb") { return rgb(from: raw) }
        if lower.hasPrefix("hsl") { return hsl(from: raw) }
        return hex(from: raw)
    }

    /// True for colours light enough that white text on them would vanish.
    static func isLight(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.sRGB) else { return false }
        // Relative luminance, WCAG weighting.
        func channel(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * channel(rgb.redComponent)
            + 0.7152 * channel(rgb.greenComponent)
            + 0.0722 * channel(rgb.blueComponent)
        return luminance > 0.45
    }

    struct Notation: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    /// HEX, RGB, HSL and CMYK for the detail panel.
    static func notations(for color: NSColor) -> [Notation] {
        guard let c = color.usingColorSpace(.sRGB) else { return [] }
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent

        let hex = String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
        let rgb = "rgb(\(Int((r * 255).rounded())), \(Int((g * 255).rounded())), \(Int((b * 255).rounded())))"

        // HSL proper — lightness is the midpoint of the extremes, not HSB's brightness.
        let maxC = max(r, g, b), minC = min(r, g, b)
        let lightness = (maxC + minC) / 2
        let delta = maxC - minC
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        if delta > 0 {
            saturation = delta / (1 - abs(2 * lightness - 1))
            switch maxC {
            case r: hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            case g: hue = (b - r) / delta + 2
            default: hue = (r - g) / delta + 4
            }
            hue *= 60
            if hue < 0 { hue += 360 }
        }
        let hsl = "hsl(\(Int(hue.rounded())), \(Int((saturation * 100).rounded()))%, \(Int((lightness * 100).rounded()))%)"

        let k = 1 - maxC
        let cmyk: String
        if k >= 1 {
            cmyk = "cmyk(0%, 0%, 0%, 100%)"
        } else {
            let cy = (1 - r - k) / (1 - k), m = (1 - g - k) / (1 - k), y = (1 - b - k) / (1 - k)
            cmyk = "cmyk(\(Int((cy * 100).rounded()))%, \(Int((m * 100).rounded()))%, \(Int((y * 100).rounded()))%, \(Int((k * 100).rounded()))%)"
        }

        return [
            Notation(label: "HEX", value: hex),
            Notation(label: "RGB", value: rgb),
            Notation(label: "HSL", value: hsl),
            Notation(label: "CMYK", value: cmyk),
        ]
    }

    // MARK: - Parsing

    private static func hex(from string: String) -> NSColor? {
        var hex = string.hasPrefix("#") ? String(string.dropFirst()) : string
        if hex.count == 3 || hex.count == 4 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }

        let hasAlpha = hex.count == 8
        let r = CGFloat((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = CGFloat((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = CGFloat((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? CGFloat(value & 0xFF) / 255 : 1
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    private static func components(of string: String) -> [String] {
        guard let open = string.firstIndex(of: "("), let close = string.lastIndex(of: ")"), open < close else { return [] }
        return string[string.index(after: open)..<close]
            .replacingOccurrences(of: "/", with: " ")
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func number(_ token: String, percentScale: CGFloat) -> CGFloat? {
        if token.hasSuffix("%") {
            guard let v = Double(token.dropLast()) else { return nil }
            return CGFloat(v) / 100 * percentScale
        }
        return Double(token).map { CGFloat($0) }
    }

    private static func rgb(from string: String) -> NSColor? {
        let parts = components(of: string)
        guard parts.count >= 3,
              let r = number(parts[0], percentScale: 255),
              let g = number(parts[1], percentScale: 255),
              let b = number(parts[2], percentScale: 255)
        else { return nil }
        let a = parts.count >= 4 ? (number(parts[3], percentScale: 1) ?? 1) : 1
        return NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    private static func hsl(from string: String) -> NSColor? {
        let parts = components(of: string).map { $0.replacingOccurrences(of: "deg", with: "") }
        guard parts.count >= 3,
              let h = number(parts[0], percentScale: 360),
              let s = number(parts[1], percentScale: 1),
              let l = number(parts[2], percentScale: 1)
        else { return nil }
        let a = parts.count >= 4 ? (number(parts[3], percentScale: 1) ?? 1) : 1

        let chroma = (1 - abs(2 * l - 1)) * s
        let hPrime = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let x = chroma * (1 - abs(hPrime.truncatingRemainder(dividingBy: 2) - 1))
        let (r1, g1, b1): (CGFloat, CGFloat, CGFloat)
        switch hPrime {
        case 0..<1: (r1, g1, b1) = (chroma, x, 0)
        case 1..<2: (r1, g1, b1) = (x, chroma, 0)
        case 2..<3: (r1, g1, b1) = (0, chroma, x)
        case 3..<4: (r1, g1, b1) = (0, x, chroma)
        case 4..<5: (r1, g1, b1) = (x, 0, chroma)
        default:    (r1, g1, b1) = (chroma, 0, x)
        }
        let m = l - chroma / 2
        return NSColor(srgbRed: r1 + m, green: g1 + m, blue: b1 + m, alpha: a)
    }
}
