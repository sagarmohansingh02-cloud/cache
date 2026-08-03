import AppKit
import SwiftUI

/// One card in the notch strip.
///
/// Portrait, and the preview is full-bleed: the picture *is* the card, with the
/// title and metadata laid over a scrim at the bottom. That is the difference
/// between scanning a shelf and reading a list — you should recognise a clip by
/// its shape and colour before you read a word of it.
struct NotchCard: View {
    let clip: Clip
    /// 0–9 for the first ten clips, which get a ⌃⌘n badge. nil after that.
    let shortcutIndex: Int?
    let isHovered: Bool
    var isSelected: Bool = false
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    let onPreview: () -> Void

    private var kind: ClipKind { ClipKind(rawValue: clip.kind) ?? .text }

    /// True once Vision has found text in this image — the whole reason a
    /// screenshot is findable later.
    private var hasRecognizedText: Bool {
        guard let text = clip.ocrText else { return false }
        return !text.isEmpty
    }

    static let width: CGFloat = 168
    static let height: CGFloat = 196
    private static let radius: CGFloat = 14

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottom) {
                preview
                    .frame(width: Self.width, height: Self.height)
                    .clipped()

                scrim
                overlayText
            }
            .frame(width: Self.width, height: Self.height)
            .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.accent : .white.opacity(0.08),
                        lineWidth: isSelected ? 2.5 : 1
                    )
            )
            .overlay(alignment: .topTrailing) { hoverActions }
            .overlay(alignment: .topLeading) { textBadge }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.035 : 1.0)
        .animation(Theme.cardSpring, value: isHovered)
        .animation(Theme.cardSpring, value: isSelected)
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
            Color(nsColor: ClipColorParser.color(from: clip.text) ?? .black)

        case .file:
            symbolTile("doc")

        default:
            // Text kinds get their own words as the picture, large enough to
            // recognise at a glance rather than read.
            ZStack(alignment: .topLeading) {
                Color.white.opacity(0.06)
                Text(clip.text ?? "")
                    .font(.system(size: 13, weight: .medium, design: kind == .code ? .monospaced : .default))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(6)
                    .multilineTextAlignment(.leading)
                    .padding(12)
            }
        }
    }

    private func symbolTile(_ symbol: String) -> some View {
        ZStack {
            Color.white.opacity(0.06)
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    /// Darkens the bottom of the preview so white text stays legible over any
    /// image. Without it a pale screenshot makes the title disappear.
    private var scrim: some View {
        LinearGradient(
            colors: [.clear, .black.opacity(0.45), .black.opacity(0.82)],
            startPoint: .center,
            endPoint: .bottom
        )
        .frame(height: Self.height * 0.62)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }

    // MARK: - Overlaid text

    private var overlayText: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(displayTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                if let icon = AppIconCache.icon(forBundleID: clip.sourceAppBundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }

                Text(ClipRow.relativeTime(clip.createdAt))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.65))

                Spacer(minLength: 4)

                if let shortcutIndex {
                    Text("⌃⌘\(shortcutIndex)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.45)))
                }
            }
        }
        .padding(10)
        .frame(width: Self.width, alignment: .leading)
    }

    private var displayTitle: String {
        if let title = clip.title, !title.isEmpty { return title }

        switch kind {
        case .image:
            // A screenshot's first recognised line is a far better label than
            // the word "Image".
            if let ocr = clip.ocrText?
                .split(separator: "\n")
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                return String(ocr)
            }
            return "Image"
        case .file:
            let paths = (clip.text ?? "").split(separator: "\n")
            return paths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
        case .color:
            return clip.text ?? "Color"
        default:
            return clip.text ?? ""
        }
    }

    // MARK: - Chrome

    private var hoverActions: some View {
        HStack(spacing: 6) {
            if isHovered {
                circleButton("eye", action: onPreview)
                    .help("Preview and read text")
            }
            if isHovered || clip.isPinned {
                circleButton(
                    clip.isPinned ? "star.fill" : "star",
                    tint: clip.isPinned ? Theme.accent : .white.opacity(0.85),
                    action: onTogglePin
                )
            }
        }
        .padding(8)
    }

    /// Marks an image whose text has been recognised, so you can tell at a
    /// glance which screenshots are searchable by their contents.
    @ViewBuilder
    private var textBadge: some View {
        if kind == .image && hasRecognizedText && !isHovered {
            Image(systemName: "textformat")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(5)
                .background(Circle().fill(.black.opacity(0.45)))
                .padding(8)
        }
    }

    private func circleButton(
        _ symbol: String,
        tint: Color = .white.opacity(0.85),
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.black.opacity(0.55)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
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
