import AppKit
import SwiftUI

/// The grid/board counterpart to `ClipRow`.
///
/// Same information, different priority: a card leads with the content itself
/// (thumbnail or a block of text) and demotes the metadata to a single footer
/// line, because in a grid you're scanning visually rather than reading down a
/// column.
struct ClipCard: View {
    let clip: Clip
    var isSelected: Bool = false
    var isMultiSelected: Bool = false
    let onSelect: () -> Void

    @State private var isHovering = false

    private var kind: ClipKind { ClipKind(rawValue: clip.kind) ?? .text }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                preview
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                Text(displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    if let icon = AppIconCache.icon(forBundleID: clip.sourceAppBundleID) {
                        Image(nsImage: icon).resizable().frame(width: 12, height: 12)
                    }
                    if clip.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.accent)
                    }
                    Spacer(minLength: 0)
                    Text(ClipRow.relativeTime(clip.createdAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .frame(height: Theme.cardHeight, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected || isMultiSelected ? Theme.accent : Theme.cardBorder,
                        lineWidth: 1
                    )
            )
            .overlay(alignment: .topTrailing) {
                if isMultiSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.accent)
                        .padding(4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Theme.hoverFade) { isHovering = hovering }
        }
    }

    private var backgroundFill: Color {
        if isMultiSelected { return Theme.accent.opacity(0.14) }
        if isSelected { return Theme.accent.opacity(0.18) }
        return isHovering ? Theme.hoverFill : Color.primary.opacity(0.03)
    }

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
            Color(nsColor: ClipColorParser.color(from: clip.text) ?? .textBackgroundColor)

        case .file:
            symbolTile("doc")

        default:
            // Text kinds preview as their own first few lines — closer to what
            // the clip actually is than a generic icon would be.
            Text(clip.text ?? "")
                .font(.system(size: 10, design: kind == .code ? .monospaced : .default))
                .foregroundStyle(.secondary)
                .lineLimit(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(6)
                .background(Color.primary.opacity(0.04))
        }
    }

    private func symbolTile(_ symbol: String) -> some View {
        ZStack {
            Color.primary.opacity(0.06)
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.secondary)
        }
    }

    private var displayTitle: String {
        if let title = clip.title, !title.isEmpty { return title }

        switch kind {
        case .image: return "Image"
        case .file:
            let paths = (clip.text ?? "").split(separator: "\n")
            return paths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
        default: return clip.text ?? ""
        }
    }
}
