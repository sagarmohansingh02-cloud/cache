import AppKit
import SwiftData
import SwiftUI

/// Pinned clips, all of them — a pinned set is small by definition, and pinning
/// something only to have it fall off the end of a limit would be a bug.
private let pinnedClipsDescriptor = FetchDescriptor<Clip>(
    predicate: #Predicate { $0.isPinned == true },
    sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
)

/// The unpinned working window.
///
/// The performance budget says fetch with a limit, and search is specified as an
/// in-memory Swift filter — so the limit is what search can actually see. 100
/// would mean searching barely more than one screenful, so this is set to 300:
/// still a hard bound, still nowhere near the 2000 cap, and enough that search
/// feels like it covers your history. Rows are metadata only; image bytes live
/// on disk.
private let recentClipsDescriptor: FetchDescriptor<Clip> = {
    var descriptor = FetchDescriptor<Clip>(
        predicate: #Predicate { $0.isPinned == false },
        sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
    )
    descriptor.fetchLimit = 300
    return descriptor
}()

struct ContentView: View {
    @Query(pinnedClipsDescriptor) private var pinnedClips: [Clip]
    @Query(recentClipsDescriptor) private var recentClips: [Clip]

    @Environment(\.modelContext) private var modelContext

    let monitor: ClipboardMonitor?

    /// How this view closes. The hotkey panel passes its own dismissal; the
    /// menu bar window has none to give, so it falls back to closing the key
    /// window directly.
    var onDismiss: (() -> Void)?

    @State private var searchText = ""
    @State private var selectedKind: ClipKind?
    @State private var selectedAppBundleID: String?
    @State private var selectedCategory: String?
    @State private var isShowingSettings = false

    /// Multi-selection, keyed by clip id. Empty means normal click-to-paste.
    @State private var selectedIDs: Set<UUID> = []
    /// Anchor for shift-click range selection.
    @State private var anchorIndex: Int?

    @State private var editingClip: Clip?
    @State private var categoryTarget: Clip?
    @State private var newCategoryName = ""

    @FocusState private var isSearchFocused: Bool
    @State private var navigator = ListNavigator()
    @State private var keyMonitor: Any?

    @Bindable private var settings = AppSettings.shared

    private var store: ClipStore {
        ClipStore(context: modelContext, settings: settings)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if visibleClips.isEmpty {
                emptyState
            } else {
                clipList
            }

            Divider()
            footer
        }
        .frame(width: Theme.panelWidth, height: Theme.panelHeight)
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.windowCornerRadius, style: .continuous))
        .onAppear {
            // The search field is focused the instant the panel opens. Always.
            isSearchFocused = true
            navigator.count = visibleClips.count
            keyMonitor = KeyboardNavigationMonitor.install(navigator: navigator)
        }
        .onDisappear {
            // When the window closes, stop all UI work — only the poll timer
            // should survive. A leaked key monitor would keep eating arrow keys
            // for every other app.
            KeyboardNavigationMonitor.remove(keyMonitor)
            keyMonitor = nil
        }
        .onChange(of: visibleClips.count) { _, newCount in navigator.count = newCount }
        .onChange(of: navigator.activationRequests) { _, _ in activateSelection() }
        .onChange(of: navigator.dismissRequests) { _, _ in handleEscape() }
        .onChange(of: searchText) { _, _ in navigator.resetSelection() }
        .onChange(of: selectedKind) { _, _ in navigator.resetSelection() }
        .onChange(of: selectedAppBundleID) { _, _ in navigator.resetSelection() }
        .onChange(of: selectedCategory) { _, _ in navigator.resetSelection() }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(
                settings: settings,
                knownApps: availableApps,
                onClearAll: {
                    store.clearAll()
                    isShowingSettings = false
                },
                onClose: { isShowingSettings = false }
            )
        }
        .sheet(item: $editingClip) { clip in
            ClipEditor(clip: clip, store: store) { editingClip = nil }
        }
        .alert(
            "New Category",
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

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if selectedIDs.isEmpty {
            FilterBar(
                searchText: $searchText,
                selectedKind: $selectedKind,
                selectedAppBundleID: $selectedAppBundleID,
                selectedCategory: $selectedCategory,
                availableKinds: availableKinds,
                availableApps: availableApps,
                availableCategories: availableCategories,
                isSearchFocused: $isSearchFocused
            )
        } else {
            BulkActionBar(
                selectedCount: selectedIDs.count,
                onCopy: bulkCopy,
                onSelectSimilar: selectSimilar,
                onDelete: bulkDelete,
                onClear: { selectedIDs.removeAll() }
            )
            .padding(.horizontal, Theme.windowPadding)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Filtering & ordering

    private func matches(_ clip: Clip) -> Bool {
        if let selectedKind, clip.kind != selectedKind.rawValue { return false }
        if let selectedAppBundleID, clip.sourceAppBundleID != selectedAppBundleID { return false }
        if let selectedCategory, clip.category != selectedCategory { return false }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        // `localizedStandardContains` is the case- and diacritic-insensitive
        // comparison the Finder uses — the behaviour a Mac user expects.
        // Titles and OCR text are searched alongside the contents.
        let haystacks = [clip.title, clip.text, clip.ocrText, clip.sourceAppName].compactMap { $0 }
        return haystacks.contains { $0.localizedStandardContains(query) }
    }

    /// Sorting is applied inside each group, so pinned clips stay on top
    /// whatever order the rest is in.
    private var filteredPinned: [Clip] {
        pinnedClips.filter(matches).sorted(by: settings.sortOrder)
    }

    private var filteredRecent: [Clip] {
        recentClips.filter(matches).sorted(by: settings.sortOrder)
    }

    /// Pinned first, then history — the same order the list renders, so a single
    /// index can address any visible row for keyboard navigation.
    private var visibleClips: [Clip] { filteredPinned + filteredRecent }

    private var availableKinds: [ClipKind] {
        let present = Set((pinnedClips + recentClips).map(\.kind))
        return ClipKind.allCases.filter { present.contains($0.rawValue) }
    }

    private var availableApps: [FilterBar.SourceApp] {
        var seen = Set<String>()
        var apps: [FilterBar.SourceApp] = []

        for clip in pinnedClips + recentClips {
            guard let bundleID = clip.sourceAppBundleID,
                  let name = clip.sourceAppName,
                  !seen.contains(bundleID)
            else { continue }

            seen.insert(bundleID)
            apps.append(FilterBar.SourceApp(bundleID: bundleID, name: name))
        }
        return apps.sorted { $0.name < $1.name }
    }

    private var availableCategories: [String] {
        Array(Set((pinnedClips + recentClips).compactMap(\.category))).sorted()
    }

    // MARK: - List

    private var clipList: some View {
        // `ScrollViewReader` is what lets ↑↓ scroll the selection into view.
        ScrollViewReader { proxy in
            ScrollView {
                Group {
                    switch settings.viewMode {
                    case .list:  listLayout
                    case .grid:  gridLayout
                    case .board: boardLayout
                    }
                }
                .padding(Theme.windowPadding)
            }
            .animation(Theme.standardSpring, value: visibleClips.count)
            .onChange(of: navigator.selectedIndex) { _, _ in
                guard let selection = navigator.selection, selection < visibleClips.count else { return }
                withAnimation(Theme.standardSpring) {
                    proxy.scrollTo(visibleClips[selection].id, anchor: .center)
                }
            }
        }
    }

    private var listLayout: some View {
        // Lazy so off-screen rows are never built.
        LazyVStack(spacing: Theme.rowSpacing, pinnedViews: [.sectionHeaders]) {
            if !filteredPinned.isEmpty {
                Section {
                    ForEach(Array(filteredPinned.enumerated()), id: \.element.id) { index, clip in
                        row(for: clip, at: index)
                    }
                } header: {
                    sectionHeader("Pinned")
                }
            }

            if !filteredRecent.isEmpty {
                Section {
                    ForEach(Array(filteredRecent.enumerated()), id: \.element.id) { index, clip in
                        row(for: clip, at: filteredPinned.count + index)
                    }
                } header: {
                    if !filteredPinned.isEmpty { sectionHeader("History") }
                }
            }
        }
    }

    private var gridLayout: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.rowSpacing)],
            spacing: Theme.rowSpacing
        ) {
            ForEach(Array(visibleClips.enumerated()), id: \.element.id) { index, clip in
                card(for: clip, at: index)
            }
        }
    }

    /// Board groups by kind into columns — the "what kind of thing am I looking
    /// for" view, as opposed to the chronological one.
    private var boardLayout: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Theme.rowSpacing) {
                ForEach(availableKinds, id: \.self) { kind in
                    let clips = visibleClips.filter { $0.kind == kind.rawValue }
                    if !clips.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                            sectionHeader(kind.displayName)
                            ForEach(clips, id: \.id) { clip in
                                card(for: clip, at: visibleClips.firstIndex { $0.id == clip.id } ?? 0)
                            }
                        }
                        .frame(width: Theme.boardColumnWidth)
                    }
                }
            }
        }
    }

    private func row(for clip: Clip, at index: Int) -> some View {
        ClipRow(
            clip: clip,
            isSelected: navigator.selection == index && selectedIDs.isEmpty,
            isMultiSelected: selectedIDs.contains(clip.id),
            onSelect: { handleTap(on: clip, at: index) },
            onTogglePin: { withAnimation(Theme.standardSpring) { store.togglePin(clip) } },
            onDelete: { withAnimation(Theme.standardSpring) { store.delete(clip) } }
        )
        .id(clip.id)
        .contextMenu { contextMenu(for: clip) }
    }

    private func card(for clip: Clip, at index: Int) -> some View {
        ClipCard(
            clip: clip,
            isSelected: navigator.selection == index && selectedIDs.isEmpty,
            isMultiSelected: selectedIDs.contains(clip.id),
            onSelect: { handleTap(on: clip, at: index) }
        )
        .id(clip.id)
        .contextMenu { contextMenu(for: clip) }
    }

    @ViewBuilder
    private func contextMenu(for clip: Clip) -> some View {
        Button("Edit…") { editingClip = clip }

        Button(clip.isPinned ? "Unpin" : "Pin") {
            withAnimation(Theme.standardSpring) { store.togglePin(clip) }
        }

        Button(selectedIDs.contains(clip.id) ? "Deselect" : "Select") {
            toggleSelection(of: clip)
        }

        Menu("Category") {
            ForEach(availableCategories, id: \.self) { category in
                Button {
                    store.setCategory(category, on: clip)
                } label: {
                    Text(clip.category == category ? "✓ \(category)" : category)
                }
            }

            if !availableCategories.isEmpty { Divider() }

            Button("New Category…") {
                newCategoryName = ""
                categoryTarget = clip
            }

            if clip.category != nil {
                Divider()
                Button("Remove from \(clip.category ?? "")") { store.setCategory(nil, on: clip) }
            }
        }

        Divider()

        Button("Delete", role: .destructive) {
            withAnimation(Theme.standardSpring) { store.delete(clip) }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: hasActiveFilter ? "magnifyingglass" : "doc.on.clipboard")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.secondary)

            Text(hasActiveFilter ? "No matches" : "No clips yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)

            Text(hasActiveFilter
                 ? "Try a different search or clear the filters."
                 : "Copy something and it'll land here.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var hasActiveFilter: Bool {
        !searchText.isEmpty
            || selectedKind != nil
            || selectedAppBundleID != nil
            || selectedCategory != nil
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if settings.isPaused {
                HStack(spacing: 4) {
                    Image(systemName: "pause.fill").font(.system(size: 9))
                    Text("Paused").font(.system(size: 11))
                }
                .foregroundStyle(Theme.accent)
            } else {
                Text(countLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            sortMenu
            viewModeButton

            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, Theme.windowPadding)
        .padding(.vertical, 8)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortOrder.allCases) { order in
                Button {
                    settings.sortOrder = order
                } label: {
                    Text(settings.sortOrder == order ? "✓ \(order.displayName)" : order.displayName)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 20)
        .help("Sort order")
    }

    private var viewModeButton: some View {
        Button {
            // Cycles list → grid → board, so it stays one control rather than
            // a segmented picker eating the footer.
            let all = ViewMode.allCases
            let next = (all.firstIndex(of: settings.viewMode).map { $0 + 1 } ?? 0) % all.count
            withAnimation(Theme.standardSpring) { settings.viewMode = all[next] }
        } label: {
            Image(systemName: settings.viewMode.symbolName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("View: \(settings.viewMode.displayName)")
    }

    private var countLabel: String {
        let total = visibleClips.count
        guard total > 0 else { return "" }
        return "\(total) clip\(total == 1 ? "" : "s")"
    }

    // MARK: - Selection

    /// Click behaviour depends on modifiers, which SwiftUI doesn't hand to a
    /// Button action — `NSEvent.modifierFlags` reads the live keyboard state at
    /// the moment of the click, which is what AppKit itself does.
    private func handleTap(on clip: Clip, at index: Int) {
        let flags = NSEvent.modifierFlags

        if flags.contains(.shift), let anchor = anchorIndex {
            let range = min(anchor, index)...max(anchor, index)
            for position in range where position < visibleClips.count {
                selectedIDs.insert(visibleClips[position].id)
            }
            return
        }

        if flags.contains(.command) || !selectedIDs.isEmpty {
            toggleSelection(of: clip)
            anchorIndex = index
            return
        }

        anchorIndex = index
        paste(clip)
    }

    private func toggleSelection(of clip: Clip) {
        if selectedIDs.contains(clip.id) {
            selectedIDs.remove(clip.id)
        } else {
            selectedIDs.insert(clip.id)
        }
    }

    private var selectedClips: [Clip] {
        visibleClips.filter { selectedIDs.contains($0.id) }
    }

    /// Extend the selection to everything of the same kind — "grab all the
    /// screenshots" without clicking each one.
    private func selectSimilar() {
        guard let first = selectedClips.first else { return }
        for clip in visibleClips where clip.kind == first.kind {
            selectedIDs.insert(clip.id)
        }
    }

    private func bulkCopy() {
        let clips = selectedClips
        guard !clips.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // Files keep their URLs so they paste as files; everything else is
        // joined into one text block, newest-first as displayed.
        let fileURLs = clips
            .filter { $0.kind == ClipKind.file.rawValue }
            .flatMap { ($0.text ?? "").split(separator: "\n").map { URL(fileURLWithPath: String($0)) as NSURL } }

        if !fileURLs.isEmpty, fileURLs.count == clips.count {
            pasteboard.writeObjects(fileURLs)
        } else {
            let combined = clips.map(\.sortableText).joined(separator: "\n")
            pasteboard.setString(combined, forType: .string)
        }

        monitor?.acknowledgeSelfCopy()
        for clip in clips { store.recordUse(of: clip) }
        selectedIDs.removeAll()
        dismissPanel()
    }

    private func bulkDelete() {
        let clips = selectedClips
        guard !clips.isEmpty else { return }
        withAnimation(Theme.standardSpring) {
            store.deleteMany(clips)
            selectedIDs.removeAll()
        }
    }

    // MARK: - Keyboard

    private func activateSelection() {
        if !selectedIDs.isEmpty {
            bulkCopy()
            return
        }
        guard let selection = navigator.selection, selection < visibleClips.count else { return }
        paste(visibleClips[selection])
    }

    /// Escape backs out one layer at a time rather than always closing: clear a
    /// selection, then a search, then the window.
    private func handleEscape() {
        if !selectedIDs.isEmpty {
            selectedIDs.removeAll()
            return
        }
        if !searchText.isEmpty {
            searchText = ""
            return
        }
        dismissPanel()
    }

    // MARK: - Actions

    /// Copy the clip back to the system pasteboard, then get out of the way.
    /// v1 never auto-pastes — the user presses ⌘V themselves.
    private func paste(_ clip: Clip) {
        let pasteboard = NSPasteboard.general
        // `clearContents()` is mandatory before writing: NSPasteboard accumulates
        // representations otherwise, and stale types from the previous item leak
        // into the new one.
        pasteboard.clearContents()

        switch ClipKind(rawValue: clip.kind) ?? .text {
        case .image:
            // Full resolution goes back out, not the 400px thumbnail.
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

        // Tell the monitor this write was ours so it isn't captured as new.
        monitor?.acknowledgeSelfCopy()
        store.recordUse(of: clip)

        dismissPanel()
    }

    /// AppKit background: `MenuBarExtra(style: .window)` exposes no SwiftUI
    /// dismissal — `@Environment(\.dismiss)` is a no-op inside it. The panel is
    /// a real `NSWindow` that holds key focus while open, so closing the key
    /// window is the reliable way out.
    private func dismissPanel() {
        if let onDismiss {
            onDismiss()
            return
        }

        if let keyWindow = NSApp.keyWindow {
            keyWindow.close()
            return
        }
        for window in NSApp.windows where window.isVisible && window.level != .normal {
            window.close()
        }
    }
}
