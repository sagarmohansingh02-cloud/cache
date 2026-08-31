import AppKit
import SwiftUI

/// A borderless panel that can still take keyboard focus.
///
/// AppKit background: `NSWindow` refuses to become the key window when it has no
/// title bar — the default `canBecomeKey` returns false for borderless windows.
/// Without overriding it the search field would never receive a keystroke.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the Spotlight-style window the global hotkey opens.
///
/// This exists because `MenuBarExtra` cannot be opened programmatically — there
/// is no public API to pop its window, so the hotkey needs a window of its own
/// rather than reusing the menu bar one.
@MainActor
final class PanelController {
    /// Builds the SwiftUI content, handed a closure that closes the panel.
    private let contentBuilder: (@escaping () -> Void) -> AnyView

    private var panel: FloatingPanel?
    private var resignObserver: NSObjectProtocol?

    init(content: @escaping (_ dismiss: @escaping () -> Void) -> AnyView) {
        self.contentBuilder = content
    }

    // MARK: - Visibility

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel

        // Rebuild the content on every open so the list starts at the top and
        // the search field's focus-on-appear fires again.
        panel.contentView = FirstMouseHostingView(rootView: contentBuilder { [weak self] in self?.hide() })

        position(panel)

        // `orderFrontRegardless` shows the window without activating the app.
        // Combined with `.nonactivatingPanel` this means the app you copied
        // from keeps its focus — so ⌘V still goes where you expect after the
        // panel closes. This is also the groundwork auto-paste would need.
        // Show a Dock icon while the Library is open.
        //
        // The app is `LSUIElement`, so normally it has no Dock presence at all —
        // which is right for something that lives in the notch, but means a new
        // user has no idea it is running or where it went. Switching the
        // activation policy to `.regular` puts it in the Dock and the app
        // switcher for as long as the Library window is up, then drops back to
        // `.accessory` when it closes. That gives the app a face when you are
        // actually working in it, without leaving an icon parked in your Dock
        // the rest of the time.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func hide() {
        panel?.orderOut(nil)
        // Back to a menu bar utility. Deferred so the window is really gone
        // before the policy flips — changing it mid-teardown makes the Dock
        // icon linger.
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Construction

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: Theme.libraryWidth, height: Theme.libraryHeight),
            // `.nonactivatingPanel` is the important one: the panel accepts key
            // input without making Cache the active application.
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating

        // Follow the user across Spaces and appear over full-screen apps,
        // the way Spotlight does.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // The SwiftUI content paints its own material and rounds its own
        // corners, so the window itself must be transparent — otherwise a white
        // rectangle shows through behind the rounded corners.
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow

        // Dismiss when focus goes elsewhere — Spotlight behaviour.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }

        return panel
    }

    /// Centred horizontally, and high on the screen rather than dead centre —
    /// Spotlight sits around the upper third, which reads as "search" instead
    /// of "modal dialog".
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else {
            panel.center()
            return
        }

        let visible = screen.visibleFrame
        let size = panel.frame.size

        let originX = visible.midX - size.width / 2
        // AppKit's y axis grows upward from the bottom of the screen.
        let originY = visible.midY - size.height / 2

        panel.setFrameOrigin(NSPoint(x: originX.rounded(), y: originY.rounded()))
    }

    deinit {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
    }
}
