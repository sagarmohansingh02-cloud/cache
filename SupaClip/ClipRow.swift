import AppKit
import SwiftUI

/// A single clip card in the list.
struct ClipRow: View {
    let clip: Clip
    var isSelected: Bool = false
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    private var kind: ClipKind {
        ClipKind(rawValue: clip.kind) ?? .text
    }

    private var isImage: Bool { kind == .image }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                leadingPreview

                VStack(alignment: .leading, spacing: 4) {
                    title
                    metadata
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Theme.rowPaddingH)
            .padding(.vertical, Theme.rowPaddingV)
            .frame(height: isImage ? Theme.imageRowHeight : Theme.textRowHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                // A 1px hairline, never a drop shadow. Keyboard selection is the
                // only thing that gets the accent colour here.
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent : Theme.cardBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        // Strips the default macOS push-button chrome — the card *is* the button.
        .buttonStyle(.plain)
        .onHover { hovering in
            // Hover states are mandatory on macOS; without them the list feels dead.
            withAnimation(Theme.hoverFade) { isHovering = hovering }
        }
        .onDrag { dragProvider() }
    }

    private var backgroundFill: Color {
        if isSelected { return Theme.accent.opacity(0.18) }
        return isHovering ? Theme.hoverFill : Color.clear
    }

    /// What lands in the drop target when the row is dragged out.
    ///
    /// `NSItemProvider` is the system's "here is a thing, in whatever format you
    /// can handle" wrapper. Handing over a file URL rather than raw bytes is what
    /// lets an image dropped into Finder arrive as an actual file. Dragging files
    /// out is also why the app sandbox is off.
    private func dragProvider() -> NSItemProvider {
        switch kind {
        case .image:
            if let filename = clip.imageFilename {
                let url = FileStorage.clipsDirectory.appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: url.path),
                   let provider = NSItemProvider(contentsOf: url) {
                    return provider
                }
            }

        case .file:
            if let first = (clip.text ?? "").split(separator: "\n").first {
                let url = URL(fileURLWithPath: String(first))
                if FileManager.default.fileExists(atPath: url.path),
                   let provider = NSItemProvider(contentsOf: url) {
                    return provider
                }
            }

        default:
            break
        }

        return NSItemProvider(object: (clip.text ?? "") as NSString)
    }

    // MARK: - Leading preview

    @ViewBuilder
    private var leadingPreview: some View {
        switch kind {
        case .image:
            if let thumbnail = ThumbnailCache.thumbnail(named: clip.thumbnailFilename) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 88, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                placeholderTile(symbol: "photo")
            }

        case .color:
            // The single exception to the one-accent-colour rule: a colour clip
            // renders the colour it actually holds.
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(nsColor: ClipColorParser.color(from: clip.text) ?? .textBackgroundColor))
                .frame(width: 24, height: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Theme.cardBorder, lineWidth: 1)
                )

        case .file:
            placeholderTile(symbol: "doc")

        default:
            EmptyView()
        }
    }

    private func placeholderTile(symbol: String) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.primary.opacity(0.06))
            .frame(width: 24, height: 24)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            )
    }

    // MARK: - Text

    private var title: some View {
        Text(displayTitle)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .lineLimit(isImage ? 1 : 2)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var displayTitle: String {
        switch kind {
        case .image:
            return "Image"
        case .file:
            // Show filenames, not full paths — the path is still what gets copied.
            let paths = (clip.text ?? "").split(separator: "\n")
            let names = paths.map { ($0 as NSString).lastPathComponent }
            return names.joined(separator: ", ")
        default:
            return clip.text ?? ""
        }
    }

    private var metadata: some View {
        HStack(spacing: 4) {
            if let icon = AppIconCache.icon(forBundleID: clip.sourceAppBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }

            Text(clip.sourceAppName ?? "Unknown")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            if isHovering {
                // Row actions appear on hover so the resting state stays quiet.
                iconButton(
                    symbol: clip.isPinned ? "pin.slash" : "pin",
                    help: clip.isPinned ? "Unpin" : "Pin",
                    action: onTogglePin
                )
                iconButton(symbol: "trash", help: "Delete", action: onDelete)
            } else if clip.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.accent)
            }

            Text(Self.relativeTime(clip.createdAt))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func iconButton(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Compact relative timestamps: "now", "2m", "1h", "yesterday", "3d".
    static func relativeTime(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)

        if seconds < 60 { return "now" }
        if seconds < 3_600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))h" }
        if Calendar.current.isDateInYesterday(date) { return "yesterday" }
        return "\(Int(seconds / 86_400))d"
    }
}

/// Turns a colour clip's text back into an actual colour for the swatch.
enum ClipColorParser {
    static func color(from string: String?) -> NSColor? {
        guard let raw = string?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }

        if raw.lowercased().hasPrefix("rgb") { return rgbColor(from: raw) }
        return hexColor(from: raw)
    }

    private static func hexColor(from string: String) -> NSColor? {
        var hex = string.hasPrefix("#") ? String(string.dropFirst()) : string

        // #RGB shorthand expands to #RRGGBB.
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }

        return NSColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func rgbColor(from string: String) -> NSColor? {
        guard let open = string.firstIndex(of: "("),
              let close = string.lastIndex(of: ")")
        else { return nil }

        let components = string[string.index(after: open)..<close]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        guard components.count >= 3,
              let red = Double(components[0]),
              let green = Double(components[1]),
              let blue = Double(components[2])
        else { return nil }

        let alpha = components.count >= 4 ? (Double(components[3]) ?? 1) : 1

        return NSColor(
            red: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: CGFloat(alpha)
        )
    }
}
