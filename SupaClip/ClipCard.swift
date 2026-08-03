import AppKit
import SwiftUI

/// A tile in the library grid.
///
/// Landscape and full-bleed: the content fills the tile and the metadata sits
/// over a scrim along the bottom — app icon and age on the left, size on the
/// right. A grid of these is scanned, not read, which is why nothing here is a
/// label sitting beside a thumbnail.
struct ClipCard: View {
    let clip: Clip
    var isSelected: Bool = false
    var isMultiSelected: Bool = false
    let onSelect: () -> Void

    @State private var isHovering = false

    private var kind: ClipKind { ClipKind(rawValue: clip.kind) ?? .text }

    static let minWidth: CGFloat = 184
    static let height: CGFloat = 124
    private static let radius: CGFloat = 12

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottom) {
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.55), .black.opacity(0.8)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(height: 52)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

                footer
            }
            .frame(height: Self.height)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isSelected || isMultiSelected ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if isMultiSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.accent)
                        .padding(6)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(Theme.cardSpring, value: isHovering)
        .onHover { hovering in isHovering = hovering }
    }

    private var borderColor: Color {
        if isSelected || isMultiSelected { return Theme.accent }
        return isHovering ? .white.opacity(0.22) : .white.opacity(0.08)
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
            // The swatch is the tile — a colour clip should read as its colour
            // from across the grid.
            ZStack(alignment: .topLeading) {
                Color(nsColor: ClipColorParser.color(from: clip.text) ?? .black)
                Text((clip.text ?? "").uppercased())
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.35), radius: 2)
                    .padding(10)
            }

        case .file:
            symbolTile("doc")

        default:
            ZStack(alignment: .topLeading) {
                Color.white.opacity(0.05)
                Text(clip.title ?? clip.text ?? "")
                    .font(.system(size: 12, weight: .regular, design: kind == .code ? .monospaced : .default))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .padding(10)
            }
        }
    }

    private func symbolTile(_ symbol: String) -> some View {
        ZStack {
            Color.white.opacity(0.05)
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            if let icon = AppIconCache.icon(forBundleID: clip.sourceAppBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }

            Text(ClipRow.relativeTime(clip.createdAt))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))

            if clip.isPinned {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.accent)
            }

            Spacer(minLength: 4)

            if let size = sizeLabel {
                Text(size)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    /// Byte size, the way the Finder would report it. Images and files use the
    /// file on disk; text uses its UTF-8 length.
    private var sizeLabel: String? {
        if let filename = clip.imageFilename {
            let url = FileStorage.clipsDirectory.appendingPathComponent(filename)
            if let bytes = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int {
                return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            }
            return nil
        }

        guard let text = clip.text, !text.isEmpty else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(text.utf8.count), countStyle: .file)
    }
}
