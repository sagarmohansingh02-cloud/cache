import KeyboardShortcuts
import SwiftUI

/// The entry point. Cache has no main window: it lives in the notch, with a
/// small native menu in the menu bar. `LSUIElement` in Info.plist is what
/// keeps it out of the Dock.
@main
struct CacheApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Bindable private var settings = AppSettings.shared

    var body: some Scene {
        MenuBarExtra("Cache", systemImage: "doc.on.clipboard", isInserted: $settings.showsMenuBarIcon) {
            Button("Open Cache") { appDelegate.openNotch() }
                .globalKeyboardShortcut(.toggleNotch)

            Divider()

            Toggle("Pause Capture", isOn: $settings.isPaused)
            Toggle("Save Screenshots", isOn: $settings.capturesScreenshots)

            Divider()

            Button("Settings…") { appDelegate.openSettings() }
                .keyboardShortcut(",")
            Button("Quit Cache") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
