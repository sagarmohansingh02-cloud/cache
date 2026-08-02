import AppKit
import SwiftUI

/// One card in the notch strip.
///
/// Bigger and more visual than a list row: at a glance you should recognise the
/// clip by its shape and colour, not by reading it.
struct NotchCard: View {
    let clip: Clip
    /// 0–9 for the first ten clips, which get a ⌃⌘n badge. nil after that.
    let shortcutIndex: Int?
    let isHovered: Bool
    let onSelect: () -> Void
    let onTogglePin: () -> Void

    private var kind: ClipKind { ClipKind(rawValue: clip.kind) ?? .text }

    private static let side: CGFloat = 116

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 0) {
                preview
                    .frame(width: Self.side, height: Self.side - 26)
                    .clipped()

                footer
                    .frame(width: Self.side, height: 26)
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.06)))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isHovered ? Theme.accent : .white.opacity(0.10), lineWidth: isHovered ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topTrailing) { hoverActions }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Theme.hoverFade, value: isHovered)
        .onDrag { dragProvider() }
        .help(clip.sortableText.prefix(200).description)
    }

    // MARK: - Preview

    @ViewBuilder
    private var preview: some View {
        switch kind {
        case .image:
            if let thumbnail = ThumbnailCache.thumbnail(named: clip.thumbnailFilename) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                symbolTile("photo")
            }

        case .color:
            // A colour clip shows the colour — the one place the single-accent
            // rule gives way, here as much as in the list.
            ZStack {
                Color(nsColor: ClipColorParser.color(from: clip.text) ?? .black)
                Text(clip.text ?? "")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.black.opacity(0.75))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(8)
            }

        case .file:
            symbolTile("doc")

        default:
            Text(clip.title ?? clip.text ?? "")
                .font(.system(size: 11, design: kind == .code ? .monospaced : .default))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(5)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(8)
                .background(Color.white.opacity(0.03))
        }
    }

    private func symbolTile(_ symbol: String) -> some View {
        ZStack {
            Color.white.opacity(0.05)
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 4) {
            if let icon = AppIconCache.icon(forBundleID: clip.sourceAppBundleID) {
                Image(nsImage: icon).resizable().frame(width: 11, height: 11)
            }

            Text(ClipRow.relativeTime(clip.createdAt))
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.45))

            Spacer(minLength: 0)

            if let shortcutIndex {
                // ⌃⌘n — reachable without leaving the home row, and shown so it
                // can actually be learned.
                Text("⌃⌘\(shortcutIndex)")
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.white.opacity(0.10)))
            }
        }
        .padding(.horizontal, 6)
        .background(Color.black.opacity(0.35))
    }

    private var hoverActions: some View {
        Group {
            if isHovered || clip.isPinned {
                Button(action: onTogglePin) {
                    Image(systemName: clip.isPinned ? "star.fill" : "star")
                        .font(.system(size: 9))
                        .foregroundStyle(clip.isPinned ? Theme.accent : .white.opacity(0.7))
                        .padding(4)
                        .background(Circle().fill(.black.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .padding(4)
            }
        }
    }

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
}
