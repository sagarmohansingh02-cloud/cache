import AppKit
import KeyboardShortcuts
import SwiftData
import SwiftUI

/// Builds everything once at launch and keeps it alive for the life of the app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var container: ModelContainer?
    private var store: ClipStore?
    private var monitor: ClipboardMonitor?
    private var watcher: ScreenshotWatcher?
    private var notch: NotchController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before anything reads the data folder or a preference — reading
        // either is what creates the empty replacement for an old install.
        FileStorage.migrateLegacyInstallIfNeeded()

        let settings = AppSettings.shared
        let container = Self.makeContainer()
        let store = ClipStore(context: container.mainContext, settings: settings)
        let monitor = ClipboardMonitor(store: store, settings: settings)
        let watcher = ScreenshotWatcher(store: store, settings: settings)
        let notch = NotchController(container: container, store: store, monitor: monitor, watcher: watcher, settings: settings)
        let settingsWindow = SettingsWindowController {
            AnyView(SettingsView(settings: settings, watcher: watcher, store: store).modelContainer(container))
        }

        store.onCapture = { [weak notch] clip in notch?.didCapture(clip) }
        settings.onScreenshotSettingsChanged = { [weak watcher] in watcher?.sync() }
        notch.showSettings = { [weak settingsWindow] in settingsWindow?.show() }

        // Capture runs from launch, whether or not anything is ever opened.
        monitor.start()
        watcher.sync()
        notch.start()
        store.performLaunchMaintenance()

        KeyboardShortcuts.onKeyUp(for: .toggleNotch) { [weak notch] in
            MainActor.assumeIsolated { notch?.toggleFromKeyboard() }
        }

        LaunchAtLogin.enableOnFirstRun(settings: settings)

        self.container = container
        self.store = store
        self.monitor = monitor
        self.watcher = watcher
        self.notch = notch
        self.settingsWindow = settingsWindow
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher?.stop()
        monitor?.stop()
    }

    /// Reopening the app from Finder or Spotlight while it runs opens the notch —
    /// the app has no window of its own to bring forward.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openNotch()
        return false
    }

    func openNotch() {
        notch?.open(focusSearch: true)
    }

    func openSettings() {
        settingsWindow?.show()
    }

    /// The store, next to the `Clips/` folder. If it won't open — a failed
    /// migration, a damaged file — it is set aside rather than deleted, and the
    /// app starts with a fresh one instead of crashing on every launch.
    private static func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration(url: FileStorage.storeURL)
        do {
            return try ModelContainer(for: Clip.self, configurations: configuration)
        } catch {
            NSLog("Cache: the clip store would not open (\(error)); setting it aside and starting a new one")
            FileStorage.setAsideUnreadableStore()
            do {
                return try ModelContainer(for: Clip.self, configurations: configuration)
            } catch {
                fatalError("Cache: could not create a clip store — \(error)")
            }
        }
    }
}
