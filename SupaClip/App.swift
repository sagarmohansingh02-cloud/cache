import KeyboardShortcuts
import SwiftData
import SwiftUI

// The entry point. `@main` tells Swift this struct owns the app lifecycle —
// there is no `main.swift`, no AppDelegate, no NSApplication subclass.
//
// `MenuBarExtra` is SwiftUI's menu bar item. With `style: .window` it drops a
// floating panel below the icon instead of a classic NSMenu, which is what
// lets us put a real SwiftUI list in there.
//
// Info.plist sets `LSUIElement: true`, and that flag — not any code here — is
// what removes the Dock icon and the app menu bar.
@main
struct SupaClipApp: App {
    private let container: ModelContainer
    private let monitor: ClipboardMonitor
    private let panelController: PanelController
    private let screenshotWatcher: ScreenshotWatcher
    private let notchController: NotchController
    private let copyHUD: CopyHUDController

    init() {
        let container: ModelContainer
        do {
            // Left to itself SwiftData drops a shared `default.store` straight
            // into Application Support, alongside every other SwiftData app's.
            // Pointing it at our own bundle-ID folder keeps the database next
            // to the Clips/ directory Phase B will write images into.
            container = try ModelContainer(
                for: Clip.self,
                configurations: ModelConfiguration(url: Self.storeURL())
            )
        } catch {
            // If the store can't be opened there is no app — capture would have
            // nowhere to go. Failing loudly beats silently dropping every clip.
            fatalError("Cache: could not open the clip store — \(error)")
        }
        self.container = container

        let store = ClipStore(context: container.mainContext)

        // Images captured before OCR existed are invisible to search until they
        // are recognised. Catch them up in the background at launch.
        store.recognizeTextInOlderImages()
        store.backfillScreenshotCollection()
        let monitor = ClipboardMonitor(store: store)
        self.monitor = monitor

        // The poll timer starts with the app and outlives the window. Capture
        // must keep working whether or not the panel is open.
        monitor.start()

        // Screenshots are filed even when they're never copied.
        let screenshotWatcher = ScreenshotWatcher(store: store)
        self.screenshotWatcher = screenshotWatcher
        // Only watches if the user has asked for it — see AppSettings.
        screenshotWatcher.syncWithSettings()
        AppSettings.shared.onCapturesScreenshotsChanged = { [weak screenshotWatcher] in
            screenshotWatcher?.syncWithSettings()
        }

        // The hotkey window. It gets its own `ContentView` — same list, but it
        // knows how to close itself, which the menu bar window can't do.
        let panelController = PanelController { dismiss in
            AnyView(
                ContentView(layout: .library, monitor: monitor, onDismiss: dismiss)
                    .modelContainer(container)
            )
        }
        self.panelController = panelController

        // The notch surface: opens on hover, or from the accent dot on any
        // display that hasn't got a notch to hover over.
        // The controller needs to be referenced from the content it builds, so
        // the box is filled in immediately after construction.
        let notchControllerBox = WeakBox<NotchController>()
        let notchController = NotchController { dismiss in
            AnyView(
                NotchView(
                    monitor: monitor,
                    onDismiss: dismiss,
                    onPreview: { clip in notchControllerBox.value?.showDetail(for: clip) },
                    onOpenLibrary: { panelController.toggle() }
                )
                .modelContainer(container)
            )
        }
        // The detail card renders in its own window, built here so it can reach
        // the monitor for self-copy acknowledgement.
        notchController.detailBuilder = { clip, dismiss in
            AnyView(
                ClipDetailCard(
                    clip: clip,
                    onCopy: {
                        ClipPasteboard.write(clip)
                        monitor.acknowledgeSelfCopy()
                        dismiss()
                    },
                    onCopyText: { text in
                        ClipPasteboard.writePlainText(text)
                        monitor.acknowledgeSelfCopy()
                        dismiss()
                    },
                    onClose: dismiss,
                    onSaveText: { edited in store.updateEditedText(edited, on: clip) }
                )
                .modelContainer(container)
            )
        }
        notchControllerBox.value = notchController
        self.notchController = notchController
        notchController.start()

        // The capture-confirmation flash. Driven by the pasteboard, not the
        // keyboard — see CopyHUD.
        let copyHUD = CopyHUDController()
        self.copyHUD = copyHUD
        CopyTray.shared.onCapture = { [weak copyHUD] in copyHUD?.flash() }

        // Fires on key *up* so the panel doesn't open while ⌃⌘ is still held.
        // The handler runs on the main thread; `assumeIsolated` states that to
        // the compiler rather than hopping and losing the keystroke's timing.
        KeyboardShortcuts.onKeyUp(for: .togglePanel) {
            MainActor.assumeIsolated { panelController.toggle() }
        }
    }


    /// `~/Library/Application Support/<BundleID>/SupaClip.store`, alongside the
    /// `Clips/` folder. One definition of that path lives in `FileStorage`.
    private static func storeURL() -> URL {
        FileStorage.containerDirectory.appendingPathComponent("SupaClip.store")
    }

    var body: some Scene {
        MenuBarExtra("Cache", systemImage: "doc.on.clipboard") {
            ContentView(monitor: monitor)
                .modelContainer(container)
        }
        .menuBarExtraStyle(.window)
    }
}
