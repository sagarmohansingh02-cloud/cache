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
    }

    /// `~/Library/Application Support/<BundleID>/SupaClip.store`
    private static func storeURL() -> URL {
        let fileManager = FileManager.default
        let bundleID = Bundle.main.bundleIdentifier ?? "com.sagarmohansingh.supaclip"

        let directory = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)

        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("SupaClip.store")
    }

    var body: some Scene {
        MenuBarExtra("SupaClip", systemImage: "doc.on.clipboard") {
            ContentView(monitor: monitor)
                .modelContainer(container)
        }
        .menuBarExtraStyle(.window)
    }
}
