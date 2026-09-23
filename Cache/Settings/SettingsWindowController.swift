import AppKit
import SwiftUI

/// Settings in a standard window, with a title bar and a close button.
///
/// While it is open Cache shows in the Dock and the menu bar like any app —
/// which also brings the Edit menu that makes ⌘C/⌘V work in its fields — and
/// goes back to living in the notch when it closes.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let makeContent: () -> AnyView

    init(content: @escaping () -> AnyView) {
        self.makeContent = content
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 640),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Cache Settings"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: makeContent())
        window.center()
        return window
    }

    func windowWillClose(_ notification: Notification) {
        // Back to a notch-only app once the window is really gone.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
