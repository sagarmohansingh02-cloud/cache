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

    @Bindable private var settings = AppSettings.shared

    private var store: ClipStore {
        ClipStore(context: modelContext, settings: settings)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Leaves the physical notch itself uncovered — the panel reads as
            // hanging *from* the notch rather than sitting on top of it.
            Color.clear.frame(height: notchInset)

            VStack(alignment: .leading, spacing: 10) {
                topBar
                dayStrip
            }
            .padding(12)
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
        .offset(y: hasAppeared ? 0 : -26)
        .opacity(hasAppeared ? 1 : 0)
        .scaleEffect(hasAppeared ? 1 : 0.97, anchor: .top)
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
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))

                // Without `focused` + focusing on appear the field never becomes
                // first responder, so typing went nowhere and search looked
                // broken. The panel is non-activating, so nothing else is going
                // to hand it focus for us.
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .focused($isSearchFocused)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        isSearchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(.white.opacity(0.08)))
            .frame(width: 200)
            .contentShape(Capsule())
            // Clicking anywhere on the pill focuses the field, not just the
            // few pixels of text baseline.
            .onTapGesture { isSearchFocused = true }

            // Chips scroll rather than wrap — collections plus kinds can easily
            // outgrow the strip's width.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    chip(label: "All", count: clips.count, isActive: !hasFilter) {
                        selectedKind = nil
                        selectedCategory = nil
                    }

                    ForEach(availableCategories, id: \.name) { collection in
                        chip(
                            label: collection.name,
                            count: collection.count,
                            symbol: "folder",
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
                }
                .padding(.horizontal, 1)
            }
            // A horizontal ScrollView has no intrinsic width and will happily
            // consume the entire row, squeezing the close button off the edge —
            // which is exactly why the cross could not be clicked. Yielding
            // layout priority lets the button claim its size first.
            .layoutPriority(-1)

            quitButton

            // Visual separation so quitting is never a near-miss of "close".
            Divider().frame(height: 14).overlay(.white.opacity(0.15))

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    // A 10pt glyph is a 10pt target. Padding gives it a real one.
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Close (Esc)")
        }
    }

    /// Quitting from the notch, since the strip is the surface most people
    /// actually use and the only other Quit is buried in the menu bar panel.
    ///
    /// A plain button rather than a menu: menus inside a non-activating,
    /// borderless panel are unreliable, and this needs to work every time.
    /// It reads red on hover so it can't be mistaken for the close button, and
    /// it sits behind a divider so a near-miss lands on nothing.
    private var quitButton: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Image(systemName: "power")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isHoveringQuit ? Color.red : .white.opacity(0.45))
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(isHoveringQuit ? Color.red.opacity(0.15) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovering in
            withAnimation(Theme.hoverFade) { isHoveringQuit = hovering }
        }
        .help("Quit SupaClip — clipboard capture stops until you open it again")
    }

    private var hasFilter: Bool { selectedKind != nil || selectedCategory != nil }

    /// Chips carry their count, so you can see what's in a collection without
    /// opening it.
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
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 9))
                }
                Text(label)
                    .font(.system(size: 11, weight: isActive ? .medium : .regular))
                Text("\(count)")
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .opacity(0.6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(isActive ? .black : .white.opacity(0.65))
            .background(Capsule().fill(isActive ? .white : .white.opacity(0.08)))
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
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.4))

                            HStack(spacing: 8) {
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
