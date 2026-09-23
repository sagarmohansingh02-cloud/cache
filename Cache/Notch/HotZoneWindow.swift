import AppKit

/// An invisible window over the notch whose only job is to notice the pointer
/// arriving.
///
/// Why a window and not a mouse monitor: a *global* `NSEvent` monitor is blind
/// to events over Cache's own windows, and a *local* one only sees events
/// dispatched to Cache, which an app that is never active mostly doesn't get.
/// An `NSTrackingArea` with `.activeAlways` is the supported answer — AppKit
/// reports the pointer entering whether or not the app is active, and it costs
/// nothing while the pointer is elsewhere. Unlike a monitor, it does no work
/// on every mouse movement across the whole screen.
@MainActor
final class HotZoneWindow {
    private let panel: NSPanel
    private let zone: HotZoneView

    init(onEnter: @escaping () -> Void, onExit: @escaping () -> Void, onClick: @escaping () -> Void) {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // Above the notch panel, so opening never depends on what else is
        // layered over the notch.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false

        zone = HotZoneView()
        zone.onEnter = onEnter
        zone.onExit = onExit
        zone.onClick = onClick
        panel.contentView = zone
    }

    /// With hover off, the notch opens on a click instead — which means this
    /// window has to take clicks rather than let them fall through.
    var opensOnClick: Bool {
        get { zone.takesClicks }
        set { zone.takesClicks = newValue }
    }

    func place(at rect: CGRect) {
        panel.setFrame(rect, display: false)
        panel.orderFrontRegardless()
    }

    func remove() {
        panel.orderOut(nil)
    }
}

private final class HotZoneView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var onClick: (() -> Void)?
    var takesClicks = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // `.activeAlways` is the load-bearing option: without it the area
        // only reports while the app is active, and this app never is.
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }

    /// Usually the zone only listens: returning nil lets every click through
    /// to whatever is underneath. Tracking areas work regardless.
    override func hitTest(_ point: NSPoint) -> NSView? {
        takesClicks ? super.hitTest(point) : nil
    }
}
