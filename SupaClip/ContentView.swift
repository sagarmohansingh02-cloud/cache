import AppKit
import SwiftData
import SwiftUI

/// Newest 100 clips. The `fetchLimit` matters: without it SwiftData would load
/// every row in the store just to show a screenful.
private let recentClipsDescriptor: FetchDescriptor<Clip> = {
    var descriptor = FetchDescriptor<Clip>(
        sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
    )
    descriptor.fetchLimit = 100
    return descriptor
}()

struct ContentView: View {
    /// `@Query` re-runs itself whenever the store changes, so the list updates
    /// the moment the monitor inserts a clip. No manual refresh, no observers.
    @Query(recentClipsDescriptor) private var clips: [Clip]

    let monitor: ClipboardMonitor?

    var body: some View {
        VStack(spacing: 0) {
            if clips.isEmpty {
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
    }

    // MARK: - Pieces

    private var clipList: some View {
        ScrollView {
            // Lazy so off-screen rows are never built. With 100 rows this is the
            // difference between rendering 8 views and rendering 100.
            LazyVStack(spacing: Theme.rowSpacing) {
                ForEach(clips) { clip in
                    ClipRow(clip: clip) { select(clip) }
                }
            }
            .padding(Theme.windowPadding)
        }
        .animation(Theme.standardSpring, value: clips.count)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.secondary)

            Text("No clips yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)

            Text("Copy something and it'll land here.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var footer: some View {
        HStack {
            Text(clips.isEmpty ? "" : "\(clips.count) clip\(clips.count == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

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

    // MARK: - Actions

    /// Copy the clip back to the system pasteboard, then get out of the way.
    /// v1 never auto-pastes — the user presses ⌘V themselves.
    private func select(_ clip: Clip) {
        guard let text = clip.text else { return }

        let pasteboard = NSPasteboard.general
        // `clearContents()` is mandatory before writing: NSPasteboard accumulates
        // representations otherwise, and stale types from the previous item leak
        // into the new one.
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

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
