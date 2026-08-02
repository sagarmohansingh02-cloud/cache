import AppKit
import SwiftUI

/// Owns the notch surface and the blue dot that stands in for it on displays
/// that haven't got a notch.
///
/// Opening is by *hover*, which macOS gives no callback for outside your own
/// windows — so a global mouse-moved monitor watches the pointer and compares
/// it against a hot zone. That sounds expensive; it isn't, because the handler
/// is one rectangle test and returns immediately in the overwhelmingly common
/// case where the cursor is nowhere near the top of the screen.
@MainActor
final class NotchController {
    private let contentBuilder: (@escaping () -> Void) -> AnyView

    private var panel: FloatingPanel?
    private var dotPanel: NSPanel?
    private var mouseMonitor: Any?

    /// True while the panel is on screen, so the monitor knows whether it is
    /// looking for an entry or an exit.
    private var isShowing = false

    /// The screen the surface is currently attached to. Changes as the cursor
    /// moves between displays.
    private var currentScreen: NSScreen?

    init(content: @escaping (_ dismiss: @escaping () -> Void) -> AnyView) {
        self.contentBuilder = content
    }

    // MARK: - Lifecycle

    func start() {
        guard mouseMonitor == nil else { return }

        // Global monitors observe events headed to *other* apps. Mouse-moved
        // needs no special permission — unlike a keyboard tap, which is the
        // whole reason this is a mouse feature and not a keyboard one.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        updateDot()
    }

    func stop() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        hide()
        dotPanel?.orderOut(nil)
        dotPanel = nil
    }

    // MARK: - Hover

    private func pointerMoved() {
        let location = NSEvent.mouseLocation

        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(location) }) else {
            return
        }

        if isShowing {
            // Close once the pointer leaves the panel — but only downward past
            // its bottom edge, so travelling along the menu bar doesn't dismiss it.
            if let frame = panel?.frame, !frame.insetBy(dx: -8, dy: -8).contains(location) {
                hide()
            }
            return
        }

        if NotchGeometry.hotZone(on: screen).contains(location) {
            show(on: screen)
        }
    }

    // MARK: - Panel

    func show(on screen: NSScreen? = nil) {
        let target = screen ?? NotchGeometry.screenUnderCursor()
        guard let target else { return }

        let panel = panel ?? makePanel()
        self.panel = panel
        currentScreen = target

        panel.contentView = NSHostingView(rootView: contentBuilder { [weak self] in self?.hide() })
        panel.setFrame(NotchGeometry.panelFrame(on: target), display: false)

        panel.orderFrontRegardless()
        panel.makeKey()
        isShowing = true
    }

    func hide() {
        panel?.orderOut(nil)
        isShowing = false
    }

    func toggle() {
        isShowing ? hide() : show()
    }

    private func makePanel() -> FloatingPanel {
        let panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: NotchGeometry.panelSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        // Above the menu bar — the surface has to be able to cover it, since it
        // hangs from the very top of the screen.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        return panel
    }

    // MARK: - The dot

    /// On a display with no notch there's nothing to aim at, so we draw a small
    /// accent dot in the menu bar's dead centre. It marks the hot zone, opens
    /// the surface on click, and accepts drops.
    func updateDot() {
        guard let screen = NotchGeometry.screenUnderCursor() else { return }

        guard !NotchGeometry.hasNotch(screen) else {
            dotPanel?.orderOut(nil)
            return
        }

        let dot = dotPanel ?? makeDotPanel()
        dotPanel = dot

        dot.setFrame(NotchGeometry.dotFrame(on: screen), display: false)
        dot.orderFrontRegardless()
    }

    private func makeDotPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NotchGeometry.dotSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false

        panel.contentView = NSHostingView(
            rootView: NotchDot(
                onOpen: { [weak self] in self?.show() },
                onDrop: { [weak self] in self?.show() }
            )
        )

        return panel
    }
}

/// The blue dot. Small, quiet, and the only always-visible chrome the app has.
private struct NotchDot: View {
    let onOpen: () -> Void
    let onDrop: () -> Void

    @State private var isHovering = false
    @State private var isTargeted = false

    var body: some View {
        Circle()
            .fill(Theme.accent)
            .opacity(isHovering || isTargeted ? 1.0 : 0.55)
            .scaleEffect(isTargeted ? 1.3 : (isHovering ? 1.15 : 1.0))
            .animation(Theme.standardSpring, value: isHovering)
            .animation(Theme.standardSpring, value: isTargeted)
            .contentShape(Circle())
            .onHover { hovering in
                isHovering = hovering
                // Hovering the dot opens the surface, matching how the notch
                // behaves on a laptop that has one.
                if hovering { onOpen() }
            }
            .onTapGesture { onOpen() }
            // Dropping onto the dot opens the surface, which is then the drop
            // target proper — one continuous drag from Finder into the notch.
            .onDrop(of: [.fileURL, .image, .text], isTargeted: $isTargeted) { _ in
                onDrop()
                return true
            }
    }
}
