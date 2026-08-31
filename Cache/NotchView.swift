import AppKit
import SwiftData
import SwiftUI

/// The surface that hangs from the notch.
///
/// Deliberately a different shape from the floating panel: that one is a
/// vertical list you read down, this is a horizontal strip you scan across. It
/// is meant to be glanced at and grabbed from, so recent clips are big, and the
/// first ten carry a ⌃⌘0–9 badge you can hit without aiming.
struct NotchView: View {
    @Query(notchClipsDescriptor) private var clips: [Clip]
    @Environment(\.modelContext) private var modelContext

    let monitor: ClipboardMonitor?
    let onDismiss: () -> Void

    /// Asks the controller to show the detail card. It lives in its own window
    /// so the strip never has to resize — resizing a SwiftUI-hosting window
    /// aborts the process. See NotchController.showDetail.
    var onPreview: ((Clip) -> Void)?

    /// Opens the full library panel from the strip's expand button.
    var onOpenLibrary: (() -> Void)?

    /// Opens settings. Like the detail card it gets its own window rather than
    /// a sheet, so the strip never resizes.
    var onOpenSettings: (() -> Void)?

    @State private var searchText = ""
    @State private var selectedKind: ClipKind?
    @State private var selectedCategory: String?
    @State private var hoveredID: UUID?
    @State private var isTargetedForDrop = false

    /// Set while the "New Collection" prompt is up.
    @State private var categoryTarget: Clip?
    @State private var newCategoryName = ""

    @FocusState private var isSearchFocused: Bool
    @State private var isHoveringQuit = false
    @State private var hasAppeared = false
    @State private var showPinnedOnly = false
    @State private var showTextOnly = false

    @Bindable private var settings = AppSettings.shared

    private var store: ClipStore {
        ClipStore(context: modelContext, settings: settings)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Leaves the physical notch itself uncovered — the panel reads as
            // hanging *from* the notch rather than sitting on top of it.
            Color.clear.frame(height: notchInset)

            VStack(alignment: .leading, spacing: 14) {
                topBar
                chipRow
                dayStrip
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Liquid Glass, clipped to the strip's shape. The glass view itself
            // only does uniform corners, so its radius is left at zero and the
            // shape comes from the clip — square across the top so it meets the
            // screen edge cleanly, rounded below where it hangs into the desktop.
            .background(LiquidGlass(cornerRadius: 0, style: .regular))
            .clipShape(Self.stripShape)
            // No border. The glass edge is the edge — an outline on top of it
            // just reads as a seam. The only stroke left is the drop target,
            // which is feedback rather than decoration.
            .overlay(
                Self.stripShape
                    .strokeBorder(
                        isTargetedForDrop ? Theme.accent : .clear,
                        lineWidth: isTargetedForDrop ? 2 : 0
                    )
            )

            Spacer(minLength: 0).allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Drop anything onto the notch to file it, which is the other half of
        // why the surface is worth reaching for.
        .onDrop(of: [.fileURL, .image, .text], isTargeted: $isTargetedForDrop) { providers in
            handleDrop(providers)
        }
        .preferredColorScheme(.dark)
        // Drops out from behind the notch. This is done on the *content*, not
        // the window: animating an NSWindow's frame while it hosts SwiftUI
        // throws inside AppKit's layout pass and aborts the process.
        .offset(y: hasAppeared ? 0 : -16)
        .opacity(hasAppeared ? 1 : 0)
        .scaleEffect(hasAppeared ? 1 : 0.98, anchor: .top)
        .onAppear {
            withAnimation(Theme.surfaceSpring) { hasAppeared = true }
            isSearchFocused = true
        }
        .onExitCommand { onDismiss() }
        .animation(Theme.standardSpring, value: selectedKind)
        .animation(Theme.standardSpring, value: selectedCategory)
        .animation(Theme.standardSpring, value: filteredClips.count)
        .alert(
            "New Collection",
            isPresented: Binding(
                get: { categoryTarget != nil },
                set: { if !$0 { categoryTarget = nil } }
            )
        ) {
            TextField("Name", text: $newCategoryName)
            Button("Create") {
                if let clip = categoryTarget { store.setCategory(newCategoryName, on: clip) }
                categoryTarget = nil
            }
            Button("Cancel", role: .cancel) { categoryTarget = nil }
        }
    }

    static let stripShape = UnevenRoundedRectangle(
        topLeadingRadius: 0,
        bottomLeadingRadius: 22,
        bottomTrailingRadius: 22,
        topTrailingRadius: 0,
        style: .continuous
    )

    /// Height of the physical notch on this screen, or a small lip when there
    /// isn't one.
    private var notchInset: CGFloat {
        guard let screen = NotchGeometry.screenUnderCursor() else { return 0 }
        return NotchGeometry.notchRect(on: screen)?.height ?? 0
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            // Unboxed and large. A search field wrapped in a pill reads as a
            // control you have to go and click; this reads as the thing the
            // surface is for, and it already has focus when the strip opens.
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))

                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .focused($isSearchFocused)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        isSearchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { isSearchFocused = true }

            Spacer(minLength: 8)

            circleAction("square.and.pencil", help: "New collection") {
                newCategoryName = ""
                categoryTarget = clips.first
            }
            circleAction("doc.text.viewfinder", help: "Only clips with recognised text") {
                withAnimation(Theme.standardSpring) { showTextOnly.toggle() }
            }
            circleAction("eyedropper", help: "Only colours") {
                withAnimation(Theme.standardSpring) {
                    selectedKind = selectedKind == .color ? nil : .color
                }
            }
            circleAction("arrow.up.forward", help: "Open full library") {
                onOpenLibrary?()
                onDismiss()
            }
            circleAction("gearshape", help: "Settings") {
                onOpenSettings?()
            }

            quitButton
            closeButton
        }
    }

    /// The circular buttons along the top right.
    private func circleAction(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 34, height: 34)
                .background(Circle().fill(.white.opacity(0.09)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Quitting from the notch. Red on hover and separated from close by the
    /// other actions, so it can never be a near-miss of dismissing the strip.
    private var quitButton: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Image(systemName: "power")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isHoveringQuit ? Color.red : .white.opacity(0.55))
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(isHoveringQuit ? Color.red.opacity(0.18) : .white.opacity(0.09))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Theme.hoverFade) { isHoveringQuit = hovering }
        }
        .help("Quit Cache — capture stops until you open it again")
    }

    private var closeButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 34, height: 34)
                .background(Circle().fill(.white.opacity(0.09)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Close (Esc)")
    }

    /// Filter chips. A round star for pinned, then All, collections and kinds,
    /// then a plus that makes a new collection.
    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                iconChip("star.fill", isActive: showPinnedOnly) {
                    withAnimation(Theme.standardSpring) { showPinnedOnly.toggle() }
                }

                chip(label: "All", count: clips.count, isActive: !hasFilter) {
                    selectedKind = nil
                    selectedCategory = nil
                    showTextOnly = false
                    showPinnedOnly = false
                }

                ForEach(availableCategories, id: \.name) { collection in
                    chip(
                        label: collection.name,
                        count: collection.count,
                        isActive: selectedCategory == collection.name
                    ) {
                        selectedKind = nil
                        selectedCategory = selectedCategory == collection.name ? nil : collection.name
                    }
                }

                ForEach(availableKinds, id: \.kind) { entry in
                    chip(
                        label: entry.kind.displayName,
                        count: entry.count,
                        isActive: selectedKind == entry.kind
                    ) {
                        selectedCategory = nil
                        selectedKind = selectedKind == entry.kind ? nil : entry.kind
                    }
                }

                iconChip("plus", isActive: false) {
                    newCategoryName = ""
                    categoryTarget = clips.first
                }
            }
            .padding(.horizontal, 1)
        }
        .frame(height: 38)
    }

    private func iconChip(_ symbol: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? .black : .white.opacity(0.7))
                .frame(width: 38, height: 38)
                .background(Circle().fill(isActive ? .white : .white.opacity(0.09)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var hasFilter: Bool {
        selectedKind != nil || selectedCategory != nil || showPinnedOnly || showTextOnly
    }

    /// Chips carry their count, so you can see what is in a collection without
    /// opening it. The active one is a solid white pill — the strongest
    /// contrast available on a dark glass surface.
    private func chip(
        label: String,
        count: Int,
        symbol: String? = nil,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(Theme.standardSpring) { action() }
        } label: {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11))
                }
                Text(label)
                    .font(.system(size: 14, weight: isActive ? .semibold : .regular))
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .opacity(0.55)
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
            .foregroundStyle(isActive ? .black : .white.opacity(0.72))
            .background(Capsule().fill(isActive ? .white : .white.opacity(0.09)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Strip

    @ViewBuilder
    private var dayStrip: some View {
        if filteredClips.isEmpty {
            emptyState
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(groupedByDay, id: \.label) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.55))

                            HStack(spacing: 12) {
                                ForEach(group.clips, id: \.id) { clip in
                                    NotchCard(
                                        clip: clip,
                                        shortcutIndex: shortcutIndex(for: clip),
                                        isHovered: hoveredID == clip.id,
                                        onSelect: { paste(clip) },
                                        onTogglePin: { store.togglePin(clip) },
                                        onPreview: { openDetail(clip) }
                                    )
                                    .onHover { hovering in
                                        hoveredID = hovering ? clip.id : nil
                                    }
                                    .contextMenu { cardMenu(for: clip) }
                                    .transition(
                                        .scale(scale: 0.9).combined(with: .opacity)
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: searchText.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.35))

            Text(searchText.isEmpty
                 ? "Nothing here yet — copy something, or drop a file on the notch."
                 : "No clips match “\(searchText)”.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }

    // MARK: - Data

    private var filteredClips: [Clip] {
        clips.filter { clip in
            if let selectedKind, clip.kind != selectedKind.rawValue { return false }
            if let selectedCategory, clip.category != selectedCategory { return false }
            if showPinnedOnly && !clip.isPinned { return false }
            if showTextOnly && (clip.ocrText ?? "").isEmpty { return false }

            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }

            return [clip.title, clip.text, clip.ocrText, clip.sourceAppName]
                .compactMap { $0 }
                .contains { $0.localizedStandardContains(query) }
        }
    }

    private var availableKinds: [(kind: ClipKind, count: Int)] {
        ClipKind.allCases.compactMap { kind in
            let count = clips.filter { $0.kind == kind.rawValue }.count
            return count > 0 ? (kind, count) : nil
        }
    }

    /// User-made collections, with how many clips are in each.
    private var availableCategories: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for clip in clips {
            guard let category = clip.category else { continue }
            counts[category, default: 0] += 1
        }
        return counts.map { (name: $0.key, count: $0.value) }.sorted { $0.name < $1.name }
    }

    private struct DayGroup {
        let label: String
        let clips: [Clip]
    }

    /// "Today", "Yesterday", then dates — the same grouping the eye already
    /// uses when scanning back through a day's work.
    private var groupedByDay: [DayGroup] {
        let calendar = Calendar.current
        var order: [Date] = []
        var buckets: [Date: [Clip]] = [:]

        for clip in filteredClips {
            let day = calendar.startOfDay(for: clip.createdAt)
            if buckets[day] == nil {
                buckets[day] = []
                order.append(day)
            }
            buckets[day]?.append(clip)
        }

        return order.map { day in
            DayGroup(label: Self.dayLabel(for: day, calendar: calendar), clips: buckets[day] ?? [])
        }
    }

    private static func dayLabel(for day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: day)
    }

    /// The first ten visible clips get a ⌃⌘0–9 badge.
    private func shortcutIndex(for clip: Clip) -> Int? {
        guard let index = filteredClips.firstIndex(where: { $0.id == clip.id }), index < 10 else {
            return nil
        }
        return index
    }

    /// Right-click on a card. This is where a clip gets filed into a
    /// collection — the chips only filter, they don't assign.
    // MARK: - Detail

    private func openDetail(_ clip: Clip) {
        onPreview?(clip)
    }

    /// Copy recognised text without touching the clip's own contents.
    private func copyPlainText(_ text: String) {
        ClipPasteboard.writePlainText(text)
        monitor?.acknowledgeSelfCopy()
        onDismiss()
    }

    @ViewBuilder
    private func cardMenu(for clip: Clip) -> some View {
        Button("Paste") { paste(clip) }

        if let ocrText = clip.ocrText, !ocrText.isEmpty {
            Button("Copy Recognized Text") { copyPlainText(ocrText) }
        }

        Button("Preview") { openDetail(clip) }

        Button(clip.isPinned ? "Unstar" : "Star") {
            withAnimation(Theme.standardSpring) { store.togglePin(clip) }
        }

        Menu("Add to Collection") {
            ForEach(availableCategories, id: \.name) { collection in
                Button {
                    withAnimation(Theme.standardSpring) {
                        store.setCategory(collection.name, on: clip)
                    }
                } label: {
                    Text(clip.category == collection.name ? "✓ \(collection.name)" : collection.name)
                }
            }

            if !availableCategories.isEmpty { Divider() }

            Button("New Collection…") {
                newCategoryName = ""
                categoryTarget = clip
            }

            if let current = clip.category {
                Divider()
                Button("Remove from \(current)") {
                    withAnimation(Theme.standardSpring) { store.setCategory(nil, on: clip) }
                }
            }
        }

        Divider()

        Button("Delete", role: .destructive) {
            withAnimation(Theme.standardSpring) { store.delete(clip) }
        }
    }

    // MARK: - Actions

    private func paste(_ clip: Clip) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch ClipKind(rawValue: clip.kind) ?? .text {
        case .image:
            guard let image = FileStorage.loadImage(named: clip.imageFilename) else { return }
            pasteboard.writeObjects([image])
        case .file:
            let urls = (clip.text ?? "")
                .split(separator: "\n")
                .map { URL(fileURLWithPath: String($0)) as NSURL }
            guard !urls.isEmpty else { return }
            pasteboard.writeObjects(urls)
        default:
            guard let text = clip.text else { return }
            pasteboard.setString(text, forType: .string)
        }

        monitor?.acknowledgeSelfCopy()
        store.recordUse(of: clip)
        onDismiss()
    }

    /// Files, images and text dropped on the notch become clips, filed as
    /// coming from "Drop" rather than from whatever app happened to be in front.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        if let image = NSImage(contentsOf: url) {
                            store.insertImage(image, sourceAppName: "Drop", sourceAppBundleID: nil)
                        } else {
                            store.insertText(
                                url.path,
                                kind: .file,
                                sourceAppName: "Drop",
                                sourceAppBundleID: nil
                            )
                        }
                    }
                }
                continue
            }

            if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                    guard let text = value as? String else { return }
                    Task { @MainActor in
                        store.insertText(
                            text,
                            kind: ClipKind.detect(text: text),
                            sourceAppName: "Drop",
                            sourceAppBundleID: nil
                        )
                    }
                }
            }
        }
        return true
    }
}

/// Newest clips only — the notch is a glance surface, not the full archive.
private let notchClipsDescriptor: FetchDescriptor<Clip> = {
    var descriptor = FetchDescriptor<Clip>(
        sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
    )
    descriptor.fetchLimit = 60
    return descriptor
}()
