import AppKit

/// An invisible, click-through window pinned over the notch whose only job is to
/// notice the pointer arriving.
///
/// Why this replaces the mouse-moved monitors: detecting hover by watching move
/// events is unreliable here for two compounding reasons. A **global** monitor
/// is blind to events over our own windows, and the pill sits directly between
/// the desktop and the notch — so travelling up to the notch crosses it and the
/// events vanish. A **local** monitor only sees events actually dispatched to
/// us, which for an inactive app they often aren't. The result was a hot zone
/// that worked when nothing else was on screen and died as soon as you copied
/// something.
///
/// An `NSTrackingArea` with `.activeAlways` is the supported answer: AppKit
/// tells us the moment the pointer enters the rect, whether or not the app is
/// active and whatever is layered nearby.
///
/// The window never swallows a click — `hitTest` returns nil, so everything
/// passes straight through to whatever is beneath. Tracking areas are
/// independent of hit testing, so entry is still reported.
@MainActor
final class HotZoneWindow {
    private var window: NSPanel?
    private let onEnter: () -> Void

    init(onEnter: @escaping () -> Void) {
        self.onEnter = onEnter
    }

    /// Position (or reposition) the zone on a given screen.
    func place(on screen: NSScreen, rect: CGRect) {
        let window = window ?? makeWindow()
        self.window = window

        window.setFrame(rect, display: false)
        window.orderFrontRegardless()
    }

    func remove() {
        window?.orderOut(nil)
        window = nil
    }

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        // Above the pill and the strip, so the zone is never occluded by our
        // own windows — which is precisely the bug this class exists to fix.
        panel.level = .init(Int(CGWindowLevelForKey(.statusWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        let view = HotZoneView()
        view.onEnter = { [weak self] in self?.onEnter() }
        panel.contentView = view

        return panel
    }
}

private final class HotZoneView: NSView {
    var onEnter: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        for area in trackingAreas { removeTrackingArea(area) }

        // `.activeAlways` is the load-bearing option: without it the area only
        // reports while the app is active, and this app is never active.
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                owner: self
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        onEnter?()
    }

    /// Never intercept a click — the zone only listens.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
