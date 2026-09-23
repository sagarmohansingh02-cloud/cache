import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The open panel: search and actions in the menu bar band, collections
/// beneath, then the strip of everything you copied.
struct NotchContentView: View {
    @Bindable var model: NotchModel
    let actions: ClipActions
    let watcher: ScreenshotWatcher
    @Bindable var settings: AppSettings

    /// The whole history, newest first. Filtering happens in one pass below;
    /// the cards themselves are built lazily, only as they scroll into view.
    @Query(sort: \Clip.createdAt, order: .reverse, animation: Theme.select)
    private var clips: [Clip]

    var body: some View {
        let index = ClipIndex(clips: clips, filter: model.filter, starredOnly: model.starredOnly, query: model.query)
        let metrics = model.metrics
        let inset = Theme.Notch.shoulderRadius + Theme.Notch.sidePadding

        VStack(alignment: .leading, spacing: 0) {
            TopBar(model: model, actions: actions, isPaused: settings.isPaused)
                .frame(height: metrics.bandHeight + Theme.Notch.topRowExtra)
                .padding(.horizontal, inset)

            ChipBar(model: model, actions: actions, index: index, collections: collectionNames(index))
                .frame(height: Theme.Notch.chipHeight)
                .padding(.top, Theme.Notch.chipTopGap)

            CardStrip(
                clips: index.visible,
                model: model,
                actions: actions,
                notice: notice,
                emptyMessage: emptyMessage
            )
            .frame(height: Theme.Notch.card.height + 8)
            .padding(.top, Theme.Notch.cardTopGap - 4)

            Spacer(minLength: 0)
        }
        .onDrop(of: [.fileURL, .image, .plainText, .url], isTargeted: nil) { providers in
            actions.importDrops(providers)
        }
        .onChange(of: model.commandCount) { _, _ in
            perform(model.command, visible: index.visible)
        }
        .onChange(of: model.query) { _, _ in model.selection = nil }
        .onChange(of: model.filter) { _, _ in model.selection = nil }
    }

    // MARK: - Collections

    /// User collections first in the order they were made, then any names
    /// only found on clips (made on another version, say).
    private func collectionNames(_ index: ClipIndex) -> [String] {
        var names = settings.collections
        for name in index.collections.keys.sorted() where !names.contains(name) {
            names.append(name)
        }
        return names
    }

    // MARK: - Empty and blocked states

    private var notice: StripNotice? {
        switch watcher.status {
        case .needsAccess(let folder):
            StripNotice(
                symbol: "lock",
                title: "Screenshots can't be read",
                detail: "Allow Cache to open \(Self.displayPath(folder)) in Privacy & Security.",
                button: "Allow Access",
                action: actions.openPrivacySettings
            )
        case .folderMissing(let folder):
            StripNotice(
                symbol: "folder.badge.questionmark",
                title: "Screenshot folder not found",
                detail: "\(Self.displayPath(folder)) doesn't exist. Choose another in Settings.",
                button: "Open Settings",
                action: actions.openSettings
            )
        case .off where clips.isEmpty:
            StripNotice(
                symbol: "camera.viewfinder",
                title: "Screenshots are off",
                detail: "Turn them on and every screenshot you take lands here, with its text searchable.",
                button: "Turn On",
                action: actions.turnOnScreenshots
            )
        default:
            nil
        }
    }

    private var emptyMessage: String {
        if !model.query.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Nothing matches “\(model.query)”. Search reads the text inside screenshots too."
        }
        if model.starredOnly { return "No starred clips here. Star a card to keep it through Clear History." }
        switch model.filter {
        case .all:
            return settings.isPaused
                ? "Capture is paused. Resume it with the pause button."
                : "Copy anything — text, links, colours, images — or take a screenshot, and it lands here."
        case .screenshots: return "No screenshots yet. Take one with ⇧⌘3 or ⇧⌘4."
        case .kind(let kind): return "No \(kind.pluralName.lowercased()) copied yet."
        case .collection(let name): return "“\(name)” is empty. Right-click a card to file it here."
        }
    }

    static func displayPath(_ url: URL) -> String {
        url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    // MARK: - Keyboard

    private func perform(_ command: NotchModel.Command?, visible: [Clip]) {
        guard let command, !visible.isEmpty else { return }
        let current = model.selection.flatMap { id in visible.firstIndex { $0.id == id } }

        switch command {
        case .move(let step):
            let next = current.map { min(max($0 + step, 0), visible.count - 1) } ?? 0
            withAnimation(Theme.select) { model.selection = visible[next].id }
        case .copySelection:
            actions.copyAndClose(visible[current ?? 0])
        case .previewSelection:
            if let current { actions.preview(visible[current]) }
        case .deleteSelection:
            guard let current else { return }
            let following = visible.indices.contains(current + 1) ? visible[current + 1].id
                : (current > 0 ? visible[current - 1].id : nil)
            actions.delete(visible[current])
            model.selection = following
        case .copyNumber(let number):
            if visible.indices.contains(number - 1) { actions.copyAndClose(visible[number - 1]) }
        }
    }
}

// MARK: - Top bar

/// Search on the left of the notch, actions on the right of it. The hardware
/// notch sits between the two, black on black, so the row lines up with the
/// menu bar either side of it.
private struct TopBar: View {
    @Bindable var model: NotchModel
    let actions: ClipActions
    let isPaused: Bool

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        let metrics = model.metrics
        let notchGap = metrics.hasNotch ? metrics.notchSize.width + 24 : 0
        let earWidth = max(160, (metrics.panelSize.width - notchGap) / 2 - Theme.Notch.shoulderRadius - Theme.Notch.sidePadding)

        HStack(spacing: 0) {
            searchField
                .frame(width: earWidth, alignment: .leading)

            Spacer(minLength: notchGap)

            HStack(spacing: 8) {
                RoundButton(
                    symbol: model.starredOnly ? "star.fill" : "star",
                    isActive: model.starredOnly,
                    help: model.starredOnly ? "Show everything" : "Show starred only"
                ) {
                    withAnimation(Theme.select) { model.starredOnly.toggle() }
                }
                RoundButton(
                    symbol: isPaused ? "play.fill" : "pause.fill",
                    isActive: isPaused,
                    help: isPaused ? "Capture is paused — resume" : "Pause capture"
                ) {
                    actions.togglePause()
                }
                RoundButton(symbol: "gearshape", isActive: false, help: "Settings") {
                    actions.openSettings()
                }
            }
        }
        .onChange(of: model.searchFocusRequests) { _, _ in isSearchFocused = true }
        .onChange(of: model.phase) { _, phase in
            if phase != .open { isSearchFocused = false }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isSearchFocused ? Theme.label : Theme.secondaryLabel)

            TextField("Search", text: $model.query)
                .textFieldStyle(.plain)
                .font(Theme.search)
                .foregroundStyle(Theme.label)
                .focused($isSearchFocused)
                .onSubmit { model.send(.copySelection) }

            if !model.query.isEmpty {
                Button {
                    model.query = ""
                    actions.focusSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.tertiaryLabel)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { actions.focusSearch() }
    }
}

/// The round buttons on the right of the notch.
private struct RoundButton: View {
    let symbol: String
    let isActive: Bool
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isActive ? Theme.ink : Theme.label)
                .frame(width: Theme.Notch.roundButton, height: Theme.Notch.roundButton)
                .background(
                    Circle().fill(isActive ? Theme.label : (isHovered ? Theme.controlHover : Theme.control))
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering in withAnimation(Theme.hover) { isHovered = hovering } }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A slight give under the pointer — the one piece of tactility every
/// control shares.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Chips

private struct ChipBar: View {
    @Bindable var model: NotchModel
    let actions: ClipActions
    let index: ClipIndex
    let collections: [String]

    @Namespace private var selection
    @State private var newName = ""
    @FocusState private var isNaming: Bool

    private struct Chip: Identifiable {
        let title: String
        let filter: ClipFilter
        var id: ClipFilter { filter }
    }

    /// History first, then the kinds actually present, then collections.
    private var chips: [Chip] {
        var chips = [Chip(title: "History", filter: .all)]
        if index.screenshots > 0 || model.filter == .screenshots {
            chips.append(Chip(title: "Screenshots", filter: .screenshots))
        }
        for kind in [ClipKind.image, .link, .color, .text, .code, .file]
        where index.count(for: .kind(kind)) > 0 || model.filter == .kind(kind) {
            chips.append(Chip(title: kind.pluralName, filter: .kind(kind)))
        }
        for name in collections { chips.append(Chip(title: name, filter: .collection(name))) }
        return chips
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    chipButton(chip.title, filter: chip.filter)
                }
                if model.isNamingCollection {
                    namingField
                } else {
                    addButton
                }
            }
            .padding(.horizontal, Theme.Notch.shoulderRadius + Theme.Notch.sidePadding)
            .frame(height: Theme.Notch.chipHeight)
        }
        .scrollClipDisabled()
        .onChange(of: model.isNamingCollection) { _, naming in
            if naming {
                newName = ""
                // Once the field exists, give it the cursor.
                DispatchQueue.main.async { isNaming = true }
            } else {
                model.clipAwaitingCollection = nil
            }
        }
    }

    private func chipButton(_ title: String, filter: ClipFilter) -> some View {
        let isActive = model.filter == filter
        let count = index.count(for: filter)

        return Button {
            withAnimation(Theme.select) { model.filter = filter }
        } label: {
            HStack(spacing: 7) {
                Text(title).font(Theme.chip)
                Text("\(count)")
                    .font(Theme.chipCount)
                    .foregroundStyle(isActive ? Theme.ink.opacity(0.45) : Theme.tertiaryLabel)
                    .contentTransition(.numericText())
            }
            .foregroundStyle(isActive ? Theme.ink : Theme.label.opacity(0.92))
            .padding(.horizontal, 16)
            .frame(height: Theme.Notch.chipHeight)
            .background {
                if isActive {
                    // One white pill that slides from chip to chip.
                    Capsule().fill(Theme.label).matchedGeometryEffect(id: "active", in: selection)
                } else {
                    Capsule().fill(Theme.raised)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(scale: 0.96))
        .contextMenu {
            if case .collection(let name) = filter {
                Button("Delete Collection “\(name)”", role: .destructive) { actions.removeCollection(name) }
            }
        }
    }

    private var addButton: some View {
        Button {
            model.clipAwaitingCollection = nil
            withAnimation(Theme.select) { model.isNamingCollection = true }
            actions.takeKeyboard()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.label.opacity(0.92))
                .frame(width: Theme.Notch.chipHeight, height: Theme.Notch.chipHeight)
                .background(Circle().fill(Theme.raised))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help("New collection")
    }

    private var namingField: some View {
        TextField("Collection name", text: $newName)
            .textFieldStyle(.plain)
            .font(Theme.chip)
            .foregroundStyle(Theme.label)
            .focused($isNaming)
            .frame(width: 150)
            .padding(.horizontal, 14)
            .frame(height: Theme.Notch.chipHeight)
            .background(Capsule().strokeBorder(Theme.hairlineHover, lineWidth: 1))
            .onSubmit {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                actions.createCollection(named: name, adding: model.clipAwaitingCollection)
                model.clipAwaitingCollection = nil
                withAnimation(Theme.select) {
                    model.isNamingCollection = false
                    if !name.isEmpty { model.filter = .collection(name) }
                }
            }
    }
}

// MARK: - Strip

struct StripNotice {
    let symbol: String
    let title: String
    let detail: String
    let button: String
    let action: () -> Void
}

private struct CardStrip: View {
    let clips: [Clip]
    @Bindable var model: NotchModel
    let actions: ClipActions
    let notice: StripNotice?
    let emptyMessage: String

    var body: some View {
        let inset = Theme.Notch.shoulderRadius + Theme.Notch.sidePadding

        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Notch.cardSpacing) {
                    if let notice {
                        NoticeCard(notice: notice)
                    }
                    if clips.isEmpty {
                        EmptyCard(message: emptyMessage)
                    }
                    ForEach(Array(clips.enumerated()), id: \.element.id) { position, clip in
                        ClipCardView(
                            clip: clip,
                            model: model,
                            actions: actions,
                            shortcutNumber: position < 9 ? position + 1 : nil
                        )
                        .id(clip.id)
                    }
                }
                .padding(.horizontal, inset)
                .padding(.vertical, 4)
                .background(EnclosingScrollViewReader { actions.registerStrip($0) })
            }
            // Cards passing the panel's sides dissolve instead of being chopped
            // off. The fade sits inside the padding, so at rest nothing is faded.
            .mask {
                HStack(spacing: 0) {
                    Color.clear.frame(width: Theme.Notch.shoulderRadius)
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: Theme.Notch.edgeFade)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: Theme.Notch.edgeFade)
                    Color.clear.frame(width: Theme.Notch.shoulderRadius)
                }
            }
            .onChange(of: model.filter) { _, _ in actions.scrollStripToStart() }
            .onChange(of: model.starredOnly) { _, _ in actions.scrollStripToStart() }
            .onChange(of: model.query) { _, _ in actions.scrollStripToStart() }
            .onChange(of: model.selection) { _, selection in
                guard let selection else { return }
                withAnimation(Theme.select) { proxy.scrollTo(selection, anchor: .center) }
            }
        }
    }
}

/// A card-shaped message where the strip would otherwise be blank.
private struct EmptyCard: View {
    let message: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.tertiaryLabel)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380, alignment: .leading)
        }
        .padding(.horizontal, 22)
        .frame(height: Theme.Notch.card.height)
        .background(
            RoundedRectangle(cornerRadius: Theme.Notch.cardRadius, style: .continuous)
                .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
    }
}

/// Something is stopping screenshots from arriving, and how to fix it.
private struct NoticeCard: View {
    let notice: StripNotice

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: notice.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.label)
            Text(notice.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.label)
            Text(notice.detail)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondaryLabel)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: notice.action) {
                Text(notice.button)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(Capsule().fill(Theme.label))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(14)
        .frame(width: 260, height: Theme.Notch.card.height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Notch.cardRadius, style: .continuous)
                .fill(Theme.cardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Notch.cardRadius, style: .continuous)
                .strokeBorder(Theme.hairlineHover)
        )
    }
}

/// Hands back the `NSScrollView` SwiftUI builds for the strip, so the panel
/// can steer it with a mouse wheel.
private struct EnclosingScrollViewReader: NSViewRepresentable {
    let found: (NSScrollView) -> Void

    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.found = found
        return probe
    }

    func updateNSView(_ probe: Probe, context: Context) {
        probe.found = found
        probe.report()
    }

    final class Probe: NSView {
        var found: ((NSScrollView) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            report()
        }

        func report() {
            if let scrollView = enclosingScrollView { found?(scrollView) }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
