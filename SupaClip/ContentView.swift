import AppKit
import SwiftData
import SwiftUI

/// Pinned clips, all of them — a pinned set is small by definition, and pinning
/// something only to have it fall off the end of a limit would be a bug.
private let pinnedClipsDescriptor: FetchDescriptor<Clip> = {
    var descriptor = FetchDescriptor<Clip>(
        predicate: #Predicate { $0.isPinned == true },
        sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
    )
    return descriptor
}()

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
    /// `@Query` re-runs itself whenever the store changes, so the list updates
    /// the moment the monitor inserts a clip. No manual refresh, no observers.
    @Query(pinnedClipsDescriptor) private var pinnedClips: [Clip]
    @Query(recentClipsDescriptor) private var recentClips: [Clip]

    @Environment(\.modelContext) private var modelContext

    let monitor: ClipboardMonitor?

    @State private var searchText = ""
    @State private var selectedKind: ClipKind?
    @State private var selectedAppBundleID: String?
    @State private var isShowingSettings = false
    @FocusState private var isSearchFocused: Bool

    @Bindable private var settings = AppSettings.shared

    private var store: ClipStore {
        ClipStore(context: modelContext, settings: settings)
    }

    var body: some View {
        VStack(spacing: 0) {
            FilterBar(
                searchText: $searchText,
                selectedKind: $selectedKind,
                selectedAppBundleID: $selectedAppBundleID,
                availableKinds: availableKinds,
                availableApps: availableApps,
                isSearchFocused: $isSearchFocused
            )

            Divider()

            if filteredPinned.isEmpty && filteredRecent.isEmpty {
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
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(
                settings: settings,
                onClearAll: {
                    store.clearAll()
                    isShowingSettings = false
                },
                onClose: { isShowingSettings = false }
            )
        }
    }

    // MARK: - Filtering (in memory, per the spec — no FTS at this scale)

    private func matches(_ clip: Clip) -> Bool {
        if let selectedKind, clip.kind != selectedKind.rawValue { return false }
        if let selectedAppBundleID, clip.sourceAppBundleID != selectedAppBundleID { return false }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        // `localizedStandardContains` is the case- and diacritic-insensitive
        // comparison the Finder uses — the behaviour a Mac user expects.
        // ocrText is searched too; it stays nil until Phase D fills it in.
        let haystacks = [clip.text, clip.ocrText, clip.sourceAppName].compactMap { $0 }
        return haystacks.contains { $0.localizedStandardContains(query) }
    }

    private var filteredPinned: [Clip] { pinnedClips.filter(matches) }
    private var filteredRecent: [Clip] { recentClips.filter(matches) }

    /// Chips only offer what's actually present, so you never tap a filter that
    /// can't match anything.
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

    // MARK: - Pieces

    private var clipList: some View {
        ScrollView {
            // Lazy so off-screen rows are never built.
            LazyVStack(spacing: Theme.rowSpacing, pinnedViews: [.sectionHeaders]) {
                if !filteredPinned.isEmpty {
                    Section {
                        ForEach(filteredPinned) { row(for: $0) }
                    } header: {
                        sectionHeader("Pinned")
                    }
                }

                if !filteredRecent.isEmpty {
                    Section {
                        ForEach(filteredRecent) { row(for: $0) }
                    } header: {
                        if !filteredPinned.isEmpty { sectionHeader("History") }
                    }
                }
            }
            .padding(Theme.windowPadding)
        }
        .animation(Theme.standardSpring, value: filteredRecent.count)
        .animation(Theme.standardSpring, value: filteredPinned.count)
    }

    private func row(for clip: Clip) -> some View {
        ClipRow(
            clip: clip,
            onSelect: { select(clip) },
            onTogglePin: { withAnimation(Theme.standardSpring) { store.togglePin(clip) } },
            onDelete: { withAnimation(Theme.standardSpring) { store.delete(clip) } }
        )
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
        !searchText.isEmpty || selectedKind != nil || selectedAppBundleID != nil
    }

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

            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .keyboardShortcut("q")
        }
        .padding(.horizontal, Theme.windowPadding)
        .padding(.vertical, 8)
    }

    private var countLabel: String {
        let total = filteredPinned.count + filteredRecent.count
        guard total > 0 else { return "" }
        return "\(total) clip\(total == 1 ? "" : "s")"
    }

    // MARK: - Actions

    /// Copy the clip back to the system pasteboard, then get out of the way.
    /// v1 never auto-pastes — the user presses ⌘V themselves.
    private func select(_ clip: Clip) {
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

        dismissPanel()
    }

    /// AppKit background: `MenuBarExtra(style: .window)` exposes no SwiftUI
    /// dismissal — `@Environment(\.dismiss)` is a no-op inside it. The panel is
    /// a real `NSWindow` that holds key focus while open, so closing the key
    /// window is the reliable way out. The fallback scan handles the case where
    /// the panel somehow isn't key.
    private func dismissPanel() {
        if let keyWindow = NSApp.keyWindow {
            keyWindow.close()
            return
        }
        for window in NSApp.windows where window.isVisible && window.level != .normal {
            window.close()
        }
    }
}
