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
    private var trayPanel: FloatingPanel?
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?

    private var isDetailOpen = false
    private var detailPanel: FloatingPanel?

    /// Builds the detail card for a clip. Supplied by the app so the card can
    /// reach the store and the monitor.
    var detailBuilder: ((Clip, @escaping () -> Void) -> AnyView)?

    private var hotZone: HotZoneWindow?
    private var hotZoneScreen: NSScreen?

    private let trayPresentation = TrayPresentation()
    private var trayHideWorkItem: DispatchWorkItem?

    /// How long the pill lingers after the last copy.
    private static let trayDwell: TimeInterval = 3.5

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

        // Opening is driven by a tracking area, not by watching move events —
        // see HotZoneWindow for why the monitor approach could not work once
        // the pill was on screen.
        placeHotZone()

        // The monitors remain, but only to notice the pointer *leaving* an open
        // strip and to keep the zone on the right display. They are no longer
        // responsible for opening anything.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }


        // The tray drives itself off the shelf's contents rather than being
        // polled, so the pill appears the instant a copy lands.
        CopyTray.shared.onChange = { [weak self] in self?.updateTray() }

        updateDot()
        updateTray()
    }

    /// Keep the hot zone over the notch of whichever display the pointer is on.
    private func placeHotZone() {
        guard let screen = NotchGeometry.screenUnderCursor() else { return }

        let zone = hotZone ?? HotZoneWindow { [weak self] in
            MainActor.assumeIsolated { self?.show() }
        }
        hotZone = zone
        zone.place(on: screen, rect: NotchGeometry.hotZone(on: screen))
        hotZoneScreen = screen
    }

    func stop() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        localMouseMonitor = nil
        CopyTray.shared.onChange = nil
        hotZone?.remove()
        hotZone = nil
        hide()
        dotPanel?.orderOut(nil)
        dotPanel = nil
        trayPanel?.orderOut(nil)
        trayPanel = nil
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
            var region = panel?.frame ?? .zero
            if isDetailOpen, let detail = detailPanel?.frame {
                // Union, so moving from the strip down into the detail card
                // doesn't read as leaving.
                region = region.union(detail)
            }
            if !region.insetBy(dx: -8, dy: -8).contains(location) {
                hide()
            }
            return
        }

        // Follow the pointer between displays. Opening itself is the tracking
        // area's job, not this one's.
        if screen !== hotZoneScreen {
            placeHotZone()
            updateDot()
        }
    }

    // MARK: - Panel

    func show(on screen: NSScreen? = nil) {
        let target = screen ?? NotchGeometry.screenUnderCursor()
        guard let target else { return }

        let panel = panel ?? makePanel()
        self.panel = panel
        currentScreen = target

        panel.contentView = FirstMouseHostingView(rootView: contentBuilder { [weak self] in self?.hide() })
        hideDetail()
        panel.setFrame(NotchGeometry.panelFrame(on: target), display: false)

        // The strip would sit on top of the pill, so get the pill out of the way
        // while the full surface is open.
        trayPanel?.orderOut(nil)

        panel.orderFrontRegardless()
        panel.makeKey()
        isShowing = true
    }

    /// Grow or shrink the strip so the detail card has room. Animated, because
    /// the panel resizing is the transition the user actually sees.
    /// Show the detail card in its **own window** below the strip.
    ///
    /// It used to be rendered inside the strip, which meant growing the panel to
    /// make room. Resizing a window that hosts an `NSHostingView` makes AppKit
    /// throw from `_postWindowNeedsUpdateConstraints` and abort the process —
    /// first via safe-area invalidation, then, once that was disabled, via
    /// `geometryInWindowDidChange`. Two different SwiftUI properties, one cause:
    /// the resize itself. A second window sized to its content never resizes,
    /// so the whole failure mode is gone rather than patched.
    func showDetail(for clip: Clip) {
        guard let builder = detailBuilder, let screen = currentScreen else { return }

        let panel = detailPanel ?? makeDetailPanel()
        detailPanel = panel

        panel.contentView = FirstMouseHostingView(
            rootView: builder(clip) { [weak self] in self?.hideDetail() }
        )
        panel.setFrame(NotchGeometry.detailFrame(on: screen), display: false)
        panel.orderFrontRegardless()
        panel.makeKey()
        isDetailOpen = true
    }

    func hideDetail() {
        detailPanel?.orderOut(nil)
        isDetailOpen = false
    }

    private func makeDetailPanel() -> FloatingPanel {
        let panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: NotchGeometry.detailSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true

        return panel
    }

    func hide() {
        hideDetail()
        panel?.orderOut(nil)
        isShowing = false
        updateTray()
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
        panel.acceptsMouseMovedEvents = true

        return panel
    }

    // MARK: - The tray pill

    /// Shows the pill on a copy, then retracts it.
    ///
    /// The pill is transient by design: it confirms the capture, offers a few
    /// seconds to grab the stack, and then leaves. Nothing belonging to this app
    /// should sit on the desktop permanently. The shelf's *contents* survive —
    /// hovering the notch still shows them — only the pill goes away.
    private func updateTray() {
        guard !CopyTray.shared.isEmpty, !isShowing else {
            retractTray(animated: false)
            return
        }

        guard let screen = NotchGeometry.screenUnderCursor() else { return }

        let tray = trayPanel ?? makeTrayPanel()
        trayPanel = tray

        tray.setFrame(NotchGeometry.trayFrame(on: screen), display: false)
        // `orderFrontRegardless` and never `makeKey`: the pill must never take
        // focus from whatever you're copying out of.
        tray.orderFrontRegardless()
        trayPresentation.isVisible = true

        scheduleTrayRetract()
    }

    /// Each new copy restarts the clock, so a burst of copies reads as one
    /// continuous pill rather than a flicker.
    private func scheduleTrayRetract() {
        trayHideWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }

                // Don't yank it away from under the pointer.
                if self.trayPresentation.isHovering {
                    self.scheduleTrayRetract()
                    return
                }
                self.retractTray(animated: true)
            }
        }
        trayHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.trayDwell, execute: work)
    }

    private func retractTray(animated: Bool) {
        trayHideWorkItem?.cancel()
        trayHideWorkItem = nil
        trayPresentation.isVisible = false

        guard animated else {
            trayPanel?.orderOut(nil)
            return
        }

        // Order out only once the retract animation has played.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.trayPresentation.isVisible == false else { return }
                self.trayPanel?.orderOut(nil)
            }
        }
    }

    private func makeTrayPanel() -> FloatingPanel {
        let panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: NotchGeometry.traySize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true

        panel.contentView = FirstMouseHostingView(
            rootView: NotchTrayView(
                presentation: trayPresentation,
                onOpenStrip: { [weak self] in self?.show() }
            )
        )

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

        panel.contentView = FirstMouseHostingView(
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

/// Breaks the construction cycle between the controller and the SwiftUI content
/// it builds: the content needs to call back into the controller, but the
/// controller needs the content closure to exist first.
@MainActor
final class WeakBox<T: AnyObject> {
    weak var value: T?
    init() {}
}
