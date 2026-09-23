import AppKit
import SwiftUI

/// A closer look at one clip, hanging below the notch.
///
/// For a screenshot this is where recognition earns its keep: the text Vision
/// read sits beside the picture it came from, selectable, so one line can be
/// lifted out without copying the whole image.
struct ClipDetailView: View {
    let clip: Clip
    let actions: ClipActions
    let onClose: () -> Void

    @State private var picture: CGImage?
    @State private var hasAppeared = false

    static func size(for clip: Clip) -> CGSize {
        switch clip.clipKind {
        case .image: CGSize(width: 780, height: 440)
        case .color: CGSize(width: 560, height: 300)
        case .file: CGSize(width: 560, height: 280)
        case .link: CGSize(width: 640, height: 280)
        case .text, .code: CGSize(width: 680, height: 380)
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.hairline).frame(height: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(shape.fill(Theme.ink))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.hairline))
        .scaleEffect(hasAppeared || Theme.reduceMotion ? 1 : 0.97, anchor: .top)
        .opacity(hasAppeared ? 1 : 0)
        .onAppear { withAnimation(Theme.open) { hasAppeared = true } }
        .environment(\.colorScheme, .dark)
        .task(id: clip.imageFilename ?? clip.cardImageFilePath) { await loadPicture() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: clip.isScreenshot ? "camera.viewfinder" : clip.clipKind.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.label)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.raised))

            VStack(alignment: .leading, spacing: 2) {
                Text(clip.isScreenshot ? "Screenshot" : clip.clipKind.singularName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.label)
                Text(metadata)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if let text = clip.ocrText, !text.isEmpty {
                PillButton(title: "Copy Text", isPrimary: false) { actions.copyText(text) }
            }
            if let url = clip.linkURL {
                PillButton(title: "Open", isPrimary: false) { actions.open(url) }
            }
            if actions.canShowInFinder(clip) {
                PillButton(title: "Show in Finder", isPrimary: false) { actions.showInFinder(clip) }
            }
            PillButton(title: "Copy", isPrimary: true) { actions.copyAndClose(clip) }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.secondaryLabel)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Theme.raised))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .help("Close (Esc)")
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
    }

    /// `1512 × 982 · 3.5 MB · Chrome · 5 min ago`
    private var metadata: String {
        var parts: [String] = []
        if let dimensions = clip.dimensionsLabel { parts.append(dimensions) }
        if let size = clip.sizeLabel { parts.append(size) }
        if clip.clipKind == .text || clip.clipKind == .code, let text = clip.text {
            parts.append("\(text.count.formatted()) characters")
        }
        if let app = clip.sourceAppName { parts.append(app) }
        parts.append(RelativeTime.string(for: clip.createdAt))
        return parts.joined(separator: " · ")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch clip.clipKind {
        case .image: imageContent
        case .color: colorContent
        case .file: fileContent
        case .link, .text, .code: textContent
        }
    }

    private var imageContent: some View {
        HStack(alignment: .top, spacing: 0) {
            ZStack {
                if let picture {
                    Image(decorative: picture, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .transition(.opacity)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(18)

            Rectangle().fill(Theme.hairline).frame(width: 1)

            VStack(alignment: .leading, spacing: 10) {
                Text("TEXT IN IMAGE")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.tertiaryLabel)

                if let text = clip.ocrText, !text.isEmpty {
                    ScrollView {
                        Text(text)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.label.opacity(0.9))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text(clip.ocrText == nil ? "Reading the text in this image…" : "No text found in this image.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.secondaryLabel)
                    Spacer(minLength: 0)
                }
            }
            .frame(width: 300, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(18)
        }
    }

    private var colorContent: some View {
        let color = ClipColor.color(from: clip.text) ?? .black

        return HStack(alignment: .top, spacing: 18) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: color))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
                .frame(width: 200)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(ClipColor.notations(for: color)) { notation in
                    NotationRow(notation: notation) { actions.copyText(notation.value) }
                }
                Spacer(minLength: 0)
                Text("Click a value to copy it.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryLabel)
            }
        }
        .padding(18)
    }

    private var textContent: some View {
        ScrollView {
            Text(clip.text ?? "")
                .font(clip.clipKind == .code ? .system(size: 12.5, design: .monospaced) : .system(size: 13.5))
                .foregroundStyle(Theme.label.opacity(0.92))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
    }

    private var fileContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(clip.filePaths, id: \.self) { path in
                    HStack(spacing: 12) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text((path as NSString).lastPathComponent)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.label)
                            Text((path as NSString).deletingLastPathComponent.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.secondaryLabel)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    private func loadPicture() async {
        let candidates = [FileStorage.url(for: clip.imageFilename), clip.cardImageFilePath.map { URL(fileURLWithPath: $0) }]
            .compactMap { $0 }
        guard !candidates.isEmpty else { return }
        let key = "detail:\(candidates[0].path)"
        let image = await ThumbnailLoader.shared.image(candidates: candidates, maxPixelSize: 1_600, key: key)
        withAnimation(.easeOut(duration: 0.2)) { picture = image }
    }
}

private struct PillButton: View {
    let title: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isPrimary ? Theme.ink : Theme.label)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(Capsule().fill(isPrimary ? Theme.label : Theme.raised))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

private struct NotationRow: View {
    let notation: ClipColor.Notation
    let copy: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: copy) {
            HStack(spacing: 12) {
                Text(notation.label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.tertiaryLabel)
                    .frame(width: 40, alignment: .leading)
                Text(notation.value)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.label)
                Spacer(minLength: 8)
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondaryLabel)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isHovered ? Theme.raisedHover : Theme.raised))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .onHover { hovering in withAnimation(Theme.hover) { isHovered = hovering } }
    }
}
