import AppKit
import SwiftUI

/// One card in the strip. Click to copy, drag to take it somewhere,
/// right-click for everything else.
///
/// The content *is* the card — a screenshot fills it, a colour floods it, text
/// sits on it at reading size — so a clip is recognised by its shape and
/// colour before a word of it is read.
struct ClipCardView: View {
    let clip: Clip
    let model: NotchModel
    let actions: ClipActions
    /// 1–9 for the first nine cards, shown while ⌘ is held.
    let shortcutNumber: Int?

    @State private var isHovered = false
    @State private var picture: CGImage?

    private let size = Theme.Notch.card
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Notch.cardRadius, style: .continuous)
    }

    init(clip: Clip, model: NotchModel, actions: ClipActions, shortcutNumber: Int?) {
        self.clip = clip
        self.model = model
        self.actions = actions
        self.shortcutNumber = shortcutNumber
        // A picture decoded earlier shows on the first frame — scrolling back
        // never flashes an empty card.
        _picture = State(initialValue: ThumbnailLoader.cardKey(for: clip).flatMap(ThumbnailLoader.shared.cached))
    }


    var body: some View {
        let isSelected = model.selection == clip.id
        let isCopied = model.copiedClipID == clip.id

        Button {
            actions.copyAndClose(clip)
        } label: {
            face
                .frame(width: size.width, height: size.height)
                .clipShape(shape)
                .overlay(
                    shape.strokeBorder(
                        isSelected ? Theme.label : (isHovered ? Theme.hairlineHover : Theme.hairline),
                        lineWidth: isSelected ? 2 : 1
                    )
                )
                .overlay {
                    if isCopied { CopiedStamp(shape: shape).transition(.opacity) }
                }
                .overlay(alignment: .topLeading) {
                    if model.showsShortcutHints, let shortcutNumber {
                        ShortcutBadge(number: shortcutNumber).padding(8).transition(.opacity)
                    }
                }
        }
        .buttonStyle(PressableStyle(scale: 0.97))
        .overlay(alignment: .topTrailing) { cornerActions }
        .scaleEffect(isHovered && !isCopied ? 1.02 : 1)
        .animation(Theme.hover, value: isHovered)
        .onHover { hovering in isHovered = hovering }
        .contextMenu { ClipContextMenu(clip: clip, model: model, actions: actions) }
        .onDrag { actions.dragProvider(for: clip) }
        .task(id: ThumbnailLoader.cardKey(for: clip)) { await loadPicture() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Copies to the clipboard")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Faces

    @ViewBuilder
    private var face: some View {
        switch clip.clipKind {
        case .image: pictureFace(caption: nil)
        case .color: colorFace
        case .link: linkFace
        case .code: textFace(monospaced: true)
        case .text: textFace(monospaced: false)
        case .file:
            if clip.cardImageFilePath != nil {
                pictureFace(caption: clip.filePaths.first.map { ($0 as NSString).lastPathComponent })
            } else {
                fileFace
            }
        }
    }

    private func pictureFace(caption: String?) -> some View {
        let letterboxed = picture.map(Self.needsLetterbox) ?? false

        return ZStack(alignment: .bottomLeading) {
            Theme.cardSurface

            if let picture {
                if letterboxed {
                    // A panorama or a thin strip cropped to fill would show a
                    // meaningless close-up. Show the whole picture instead,
                    // clear of the footer.
                    Image(decorative: picture, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 36)
                        .frame(width: size.width, height: size.height)
                        .transition(.opacity)
                } else {
                    Image(decorative: picture, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .transition(.opacity)
                }
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Theme.tertiaryLabel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Keeps white text legible over any picture, including a white one.
            if !letterboxed {
                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.28), .black.opacity(0.72)],
                    startPoint: UnitPoint(x: 0.5, y: 0.45),
                    endPoint: .bottom
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                if let caption {
                    Text(caption)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.label)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                }
                footer(tint: .white)
            }
        }
    }

    private func textFace(monospaced: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if monospaced {
                // Code reads top-down, with its indentation intact.
                Text(clip.previewText)
                    .font(Theme.cardCode)
                    .foregroundStyle(Theme.label.opacity(0.88))
                    .lineLimit(7)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 13)
                    .padding(.top, 13)
                Spacer(minLength: 6)
            } else {
                Spacer(minLength: 12)
                Text(clip.previewText)
                    .font(Theme.cardText)
                    .foregroundStyle(Theme.label.opacity(0.95))
                    .lineSpacing(1.5)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 13)
                    .padding(.bottom, 8)
            }
            footer(tint: .white)
        }
        .background(surface(monospaced ? Theme.codeSurface : Theme.cardSurface, scrim: 0.78))
    }

    private var linkFace: some View {
        let url = clip.linkURL
        let host = url?.host(percentEncoded: false).map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
        let rest = url.map { url -> String in
            let path = url.path(percentEncoded: false)
            return path.count > 1 ? path : (url.query(percentEncoded: false).map { "?" + $0 } ?? "")
        } ?? ""

        return VStack(alignment: .leading, spacing: 3) {
            Image(systemName: "link")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.tertiaryLabel)
                .padding(.horizontal, 13)
                .padding(.top, 13)
            Spacer(minLength: 8)
            Text(host ?? clip.previewText)
                .font(Theme.cardTitle)
                .foregroundStyle(Theme.label)
                .lineLimit(1)
                .padding(.horizontal, 13)
            if !rest.isEmpty {
                Text(rest)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .padding(.horizontal, 13)
            }
            footer(tint: .white)
                .padding(.top, 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface(Theme.cardSurface, scrim: 0.78))
    }

    private var colorFace: some View {
        let color = ClipColor.color(from: clip.text) ?? .black
        let ink: Color = ClipColor.isLight(color) ? .black : .white
        let value = clip.previewText
        let label = value.hasPrefix("#") || !value.contains("(") ? value.uppercased() : value

        return ZStack(alignment: .bottomLeading) {
            // Lighter scrim than the other cards: the colour is the content.
            surface(Color(nsColor: color), scrim: ink == .white ? 0.35 : 0.12)
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(Theme.swatch)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 13)
                footer(tint: ink)
            }
        }
    }

    private var fileFace: some View {
        let paths = clip.filePaths
        let names = paths.map { ($0 as NSString).lastPathComponent }
        let title = names.first ?? "File"

        return VStack(alignment: .leading, spacing: 0) {
            if let first = paths.first {
                Image(nsImage: FileIconCache.icon(forPath: first))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 44, height: 44)
                    .padding(.leading, 9)
                    .padding(.top, 9)
            }
            Spacer(minLength: 4)
            Text(title)
                .font(Theme.cardText.weight(.semibold))
                .foregroundStyle(Theme.label)
                .lineLimit(2)
                .padding(.horizontal, 13)
            if names.count > 1 {
                Text("and \(names.count - 1) more")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryLabel)
                    .padding(.horizontal, 13)
            }
            footer(tint: .white)
                .padding(.top, 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface(Theme.cardSurface, scrim: 0.78))
    }

    // MARK: - Pieces

    /// Every card darkens toward the bottom, so the footer always sits on the
    /// same ground whatever the face above it — the reference's card anatomy.
    private func surface(_ base: Color, scrim strength: Double) -> some View {
        ZStack {
            base
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0.5),
                    .init(color: .black.opacity(strength), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    /// App icon · how long ago · size — the reference's footer.
    private func footer(tint: Color) -> some View {
        HStack(spacing: 6) {
            SourceIcon(clip: clip, tint: tint)
            Text(RelativeTime.string(for: clip.createdAt, now: model.now))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let size = clip.sizeLabel {
                Text(size).lineLimit(1)
            }
        }
        .font(Theme.meta)
        .foregroundStyle(tint.opacity(0.8))
        .padding(.horizontal, 12)
        .padding(.bottom, 11)
    }

    /// Star and preview, top right. Outside the card's button, so clicking
    /// them never copies the card as well.
    private var cornerActions: some View {
        HStack(spacing: 6) {
            if isHovered {
                CornerButton(symbol: "eye", help: "Preview") { actions.preview(clip) }
            }
            if isHovered || clip.isPinned {
                CornerButton(symbol: clip.isPinned ? "star.fill" : "star", help: clip.isPinned ? "Unstar" : "Star") {
                    actions.toggleStar(clip)
                }
            }
        }
        .padding(8)
        .transition(.opacity)
    }

    /// Much wider or taller than the card: filling would crop it to a sliver.
    private static func needsLetterbox(_ image: CGImage) -> Bool {
        let aspect = CGFloat(image.width) / CGFloat(max(image.height, 1))
        let card = Theme.Notch.card.width / Theme.Notch.card.height
        return aspect > card * 1.75 || aspect < card / 2.2
    }

    private func loadPicture() async {
        guard picture == nil, let key = ThumbnailLoader.cardKey(for: clip) else { return }
        let image = await ThumbnailLoader.shared.image(
            candidates: ThumbnailLoader.cardCandidates(for: clip),
            maxPixelSize: ImageIngest.thumbnailMaxPixelSize,
            key: key
        )
        withAnimation(.easeOut(duration: 0.2)) { picture = image }
    }

    private var accessibilityText: String {
        var parts = [clip.isScreenshot ? "Screenshot" : clip.clipKind.singularName]
        if clip.clipKind != .image { parts.append(String(clip.previewText.prefix(80))) }
        if let app = clip.sourceAppName { parts.append("from \(app)") }
        parts.append(RelativeTime.string(for: clip.createdAt, now: model.now))
        if clip.isPinned { parts.append("starred") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Small parts

private struct SourceIcon: View {
    let clip: Clip
    let tint: Color

    var body: some View {
        if let icon = AppIconCache.icon(for: clip) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: Theme.Notch.footerIcon, height: Theme.Notch.footerIcon)
        } else if clip.sourceAppName == SourceApp.drop.name {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint.opacity(0.8))
                .frame(width: Theme.Notch.footerIcon, height: Theme.Notch.footerIcon)
        }
    }
}

private struct CornerButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.black.opacity(0.6)))
                .overlay(Circle().strokeBorder(.white.opacity(0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct ShortcutBadge: View {
    let number: Int

    var body: some View {
        Text("⌘\(number)")
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Capsule().fill(.black.opacity(0.7)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
    }
}

private struct CopiedStamp: View {
    let shape: RoundedRectangle

    var body: some View {
        ZStack {
            shape.fill(.black.opacity(0.62))
            VStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .bold))
                Text("Copied")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.white)
        }
    }
}

/// Right-click on a card.
private struct ClipContextMenu: View {
    let clip: Clip
    let model: NotchModel
    let actions: ClipActions

    var body: some View {
        Button("Copy") { actions.copyAndClose(clip) }
        if let text = clip.ocrText, !text.isEmpty {
            Button("Copy Text in Image") { actions.copyText(text) }
        }
        Button("Preview") { actions.preview(clip) }
        if let url = clip.linkURL {
            Button("Open Link") { actions.open(url) }
        }
        if actions.canShowInFinder(clip) {
            Button("Show in Finder") { actions.showInFinder(clip) }
        }

        Divider()

        Button(clip.isPinned ? "Unstar" : "Star") { actions.toggleStar(clip) }

        Menu("Add to Collection") {
            ForEach(actions.settings.collections, id: \.self) { name in
                Button {
                    actions.file(clip, in: name)
                } label: {
                    if clip.category == name {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Text(name)
                    }
                }
            }
            if !actions.settings.collections.isEmpty { Divider() }
            Button("New Collection…") {
                model.clipAwaitingCollection = clip
                withAnimation(Theme.select) { model.isNamingCollection = true }
                actions.takeKeyboard()
            }
            if let current = clip.category {
                Divider()
                Button("Remove from “\(current)”") { actions.file(clip, in: nil) }
            }
        }

        Divider()

        Button("Delete", role: .destructive) { actions.delete(clip) }
    }
}

/// Finder icons for copied files, looked up once per path.
@MainActor
private enum FileIconCache {
    private static var icons: [String: NSImage] = [:]

    static func icon(forPath path: String) -> NSImage {
        if let icon = icons[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        if icons.count > 200 { icons.removeAll() }
        icons[path] = icon
        return icon
    }
}
