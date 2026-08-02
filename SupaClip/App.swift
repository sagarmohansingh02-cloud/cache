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
            fatalError("SupaClip: could not open the clip store — \(error)")
        }
        self.container = container

        let store = ClipStore(context: container.mainContext)
        let monitor = ClipboardMonitor(store: store)
        self.monitor = monitor

        // The poll timer starts with the app and outlives the window. Capture
        // must keep working whether or not the panel is open.
        monitor.start()

        // The hotkey window. It gets its own `ContentView` — same list, but it
        // knows how to close itself, which the menu bar window can't do.
        let panelController = PanelController { dismiss in
            AnyView(
                ContentView(monitor: monitor, onDismiss: dismiss)
                    .modelContainer(container)
            )
        }
        self.panelController = panelController

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
        MenuBarExtra("SupaClip", systemImage: "doc.on.clipboard") {
            ContentView(monitor: monitor)
                .modelContainer(container)
        }
        .menuBarExtraStyle(.window)
    }
}
