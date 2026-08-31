import AppKit
import SwiftUI

/// The floating detail card that hangs below the notch strip.
///
/// For an image this is the whole point of OCR: the recognised text is shown as
/// selectable text you can read and copy, not just an invisible search index.
struct ClipDetailCard: View {
    let clip: Clip
    let onCopy: () -> Void
    let onCopyText: (String) -> Void
    let onClose: () -> Void

    /// Persist an edit back onto the clip. Optional so the card still works
    /// anywhere that only wants to read.
    var onSaveText: ((String) -> Void)?

    @State private var isEditing = false
    @State private var draft = ""

    private var kind: ClipKind { ClipKind(rawValue: clip.kind) ?? .text }

    private var recognizedText: String? {
        guard let text = clip.ocrText, !text.isEmpty else { return nil }
        return text
    }

    /// What the editor works on: an image's recognised text, or the clip's own
    /// text for everything else.
    private var editableText: String? {
        kind == .image ? recognizedText : clip.text
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(.white.opacity(0.08))
            content
        }
        .background(LiquidGlass(cornerRadius: 18, style: .regular))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        )
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: kind.symbolName)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))

            Text(kind.singularName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))

            ForEach(metadata, id: \.self) { item in
                Text(item)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer(minLength: 8)

            if isEditing {
                editingActions
            } else {
                readingActions
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var readingActions: some View {
        // A screenshot of a whole window recognises the whole window. Editing is
        // how you keep the two lines you actually wanted.
        if editableText != nil {
            pillButton("Edit", symbol: "pencil") {
                draft = editableText ?? ""
                withAnimation(Theme.hoverFade) { isEditing = true }
            }
        }

        if let recognizedText {
            pillButton("Copy text", symbol: "textformat") { onCopyText(recognizedText) }
        }

        Button(action: onCopy) {
            Text("Copy")
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(.black)
                .background(Capsule().fill(.white))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var editingActions: some View {
        pillButton("Cancel", symbol: nil) {
            withAnimation(Theme.hoverFade) { isEditing = false }
        }

        // Saving is optional on purpose: usually you want to trim the text,
        // paste it, and leave the original clip alone.
        if onSaveText != nil {
            pillButton("Save", symbol: "checkmark") {
                onSaveText?(draft)
                withAnimation(Theme.hoverFade) { isEditing = false }
            }
        }

        Button {
            onCopyText(draft)
        } label: {
            Text("Copy edited")
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(.black)
                .background(Capsule().fill(.white))
        }
        .buttonStyle(.plain)
    }

    private func pillButton(_ title: String, symbol: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 10))
                }
                Text(title).font(.system(size: 11))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(.white.opacity(0.85))
            .background(Capsule().fill(.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    /// The editor itself, shared by image and text clips.
    private var textEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextEditor(text: $draft)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.9))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1)
                )

            Text("Trim this down, then Copy edited. Save keeps the change on the clip.")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    /// Size and dimensions, matching the reference's `992 × 1200 · 1.6 MB`.
    private var metadata: [String] {
        var items: [String] = []

        if let filename = clip.imageFilename {
            let url = FileStorage.clipsDirectory.appendingPathComponent(filename)

            if let image = FileStorage.loadImage(named: filename),
               let size = FileStorage.pixelSize(of: image) {
                items.append("\(Int(size.width)) × \(Int(size.height))")
            }
            if let bytes = try? FileManager.default
                .attributesOfItem(atPath: url.path)[.size] as? Int {
                items.append(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
            }
        } else if let text = clip.text {
            items.append("\(text.count) characters")
        }

        if let app = clip.sourceAppName { items.append(app) }
        return items
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .image:
            imageContent

        case .color:
            colorContent

        default:
            if isEditing {
                textEditor.padding(12)
            } else {
                ScrollView {
                    Text(clip.text ?? "")
                        .font(.system(size: 12, design: kind == .code ? .monospaced : .default))
                        .foregroundStyle(.white.opacity(0.85))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }
        }
    }

    private var imageContent: some View {
        HStack(alignment: .top, spacing: 0) {
            // Preview on the left, recognised text on the right — so you can
            // read the text against the picture it came from.
            Group {
                if let thumbnail = ThumbnailCache.thumbnail(named: clip.thumbnailFilename) {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Color.white.opacity(0.04)
                }
            }
            .frame(width: 260)
            .frame(maxHeight: .infinity)
            .padding(12)

            Divider().overlay(.white.opacity(0.08))

            VStack(alignment: .leading, spacing: 6) {
                Text(isEditing ? "EDITING RECOGNIZED TEXT" : "RECOGNIZED TEXT")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isEditing ? Theme.accent : .white.opacity(0.4))

                if isEditing {
                    textEditor
                } else if let recognizedText {
                    ScrollView {
                        Text(recognizedText)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.85))
                            // Selectable, so you can lift one line out of a
                            // screenshot without copying the whole thing.
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text(clip.ocrText == nil
                         ? "Reading text from this image…"
                         : "No text found in this image.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
        }
    }

    private var colorContent: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: ClipColorParser.color(from: clip.text) ?? .black))
                .frame(width: 220)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(colorRows, id: \.label) { row in
                    HStack(spacing: 8) {
                        Text(row.label)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                            .frame(width: 40, alignment: .leading)
                        Text(row.value)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                            .textSelection(.enabled)
                    }
                }
                Spacer()
            }
        }
        .padding(12)
    }

    /// HEX / RGB / CMYK / HSL, as the reference shows for a colour clip.
    private var colorRows: [(label: String, value: String)] {
        guard let color = ClipColorParser.color(from: clip.text),
              let rgb = color.usingColorSpace(.sRGB)
        else { return [] }

        let r = rgb.redComponent, g = rgb.greenComponent, b = rgb.blueComponent

        let hex = String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        let rgbText = "rgb(\(Int(r * 255)), \(Int(g * 255)), \(Int(b * 255)))"

        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let hsl = "hsl(\(Int(hue * 360)), \(Int(saturation * 100))%, \(Int(brightness * 100))%)"

        // CMYK, derived rather than colour-managed — enough to read off.
        let k = 1 - max(r, g, b)
        let cmyk: String
        if k >= 1 {
            cmyk = "cmyk(0%, 0%, 0%, 100%)"
        } else {
            let c = (1 - r - k) / (1 - k)
            let m = (1 - g - k) / (1 - k)
            let y = (1 - b - k) / (1 - k)
            cmyk = "cmyk(\(Int(c * 100))%, \(Int(m * 100))%, \(Int(y * 100))%, \(Int(k * 100))%)"
        }

        return [
            ("HEX", hex),
            ("RGB", rgbText),
            ("CMYK", cmyk),
            ("HSL", hsl),
        ]
    }
}
