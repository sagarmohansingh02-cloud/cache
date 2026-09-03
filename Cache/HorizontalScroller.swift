import AppKit
import Observation
import SwiftUI

/// Horizontal scrolling that a mouse and a trackpad can both reach.
///
/// AppKit background: a scroll event carries its distance on one axis, and an
/// `NSScrollView` only spends that distance on the axis it was aimed at. A
/// wheel — and a trackpad swipe that reads as vertical — therefore moves a
/// horizontal strip by nothing at all: the clips past the right edge exist, but
/// nothing the user does brings them into view. SwiftUI's `ScrollView` gives no
/// access to the `NSScrollView` underneath it, so there is no way to fix that
/// from SwiftUI alone.
///
/// This bridges to it and does two things: turns a vertical scroll into
/// horizontal movement, and reports whether there is anything further to either
/// side, so the view can show an arrow only when it leads somewhere.
///
/// It is a class rather than view state because the scroll handler is an
/// `NSEvent` monitor installed once. A closure capturing a SwiftUI `View` — a
/// struct — would read a frozen copy of its state forever; a reference type
/// keeps it live. Same reasoning as `ListNavigator`.
@MainActor
@Observable
final class HorizontalScroller {
    enum Direction {
        case back, forward

        var sign: CGFloat { self == .back ? -1 : 1 }
    }

    /// Whether there is off-screen content to either side.
    private(set) var canScrollBack = false
    private(set) var canScrollForward = false

    @ObservationIgnored private weak var scrollView: NSScrollView?
    @ObservationIgnored private var scrollMonitor: Any?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    /// Whether the scroll in progress belongs to the strip. Nil while there is
    /// nothing to decide from yet — see `handle`.
    @ObservationIgnored private var isClaimed: Bool?

    /// One press of an arrow moves most of a screenful, leaving a card or two
    /// behind as an anchor so the jump doesn't lose the user's place.
    private static let pageFraction: CGFloat = 0.8

    /// A wheel reports its distance in lines rather than points, so a notch
    /// needs scaling up. At this size three notches move about a card.
    private static let wheelStep: CGFloat = 40

    // MARK: - Wiring

    fileprivate func attach(to scrollView: NSScrollView?) {
        guard let scrollView, scrollView !== self.scrollView else { return }
        detach()
        self.scrollView = scrollView

        // The clip view's bounds move as the strip scrolls; the document view's
        // frame changes as clips are filtered in and out. Both decide whether an
        // arrow has anywhere to go, and AppKit only posts either notification
        // for views that have been asked to send them.
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        scrollView.documentView?.postsFrameChangedNotifications = true

        observers = [
            observe(NSView.boundsDidChangeNotification, on: clipView),
            observe(NSView.frameDidChangeNotification, on: scrollView.documentView),
        ].compactMap { $0 }

        // A *local* monitor sees events on their way to our own windows and can
        // swallow one by returning nil — the only way to claim a scroll before
        // the scroll view discards it as off-axis.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handle(event) ?? event
        }

        refresh()
    }

    fileprivate func detach() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil

        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []

        scrollView = nil
        isClaimed = nil
        canScrollBack = false
        canScrollForward = false
    }

    private func observe(_ name: Notification.Name, on object: NSView?) -> (any NSObjectProtocol)? {
        guard let object else { return nil }
        return NotificationCenter.default.addObserver(
            forName: name,
            object: object,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    // MARK: - Scrolling

    /// Moves the strip a page in `direction`, animated — this is what the arrows
    /// call.
    func page(_ direction: Direction) {
        guard let scrollView else { return }
        let distance = max(scrollView.contentView.bounds.width * Self.pageFraction, 160)
        scroll(to: offset + direction.sign * distance, animated: true)
    }

    /// Returns nil once it has spent the event itself, which is how a local
    /// monitor says "don't deliver this".
    ///
    /// A trackpad sends a scroll as a phased gesture — began, a run of changes,
    /// ended, then momentum — and the first event of one usually carries no
    /// distance at all. So the decision is made once, on the first event that
    /// actually moves, and held for the rest of the gesture; a swipe that drifts
    /// diagonally then can't flip axis halfway through. A wheel has no phases,
    /// so each notch is judged on its own.
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let scrollView, event.window === scrollView.window else { return event }

        let isGesture = !event.phase.isEmpty || !event.momentumPhase.isEmpty
        if !isGesture || event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            isClaimed = nil
        }

        if isClaimed == nil {
            guard event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 else { return event }
            isClaimed = claims(event, in: scrollView)
        }

        guard isClaimed == true else { return event }

        // A trackpad measures in points already; a wheel measures in lines.
        let distance = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY
            : event.scrollingDeltaY * Self.wheelStep

        // AppKit's sign convention: a positive delta moves content toward the
        // beginning. Subtracting it means scrolling down walks forward through
        // older clips, which is the direction the strip reads in.
        scroll(to: offset - distance, animated: false)
        return nil
    }

    private func claims(_ event: NSEvent, in scrollView: NSScrollView) -> Bool {
        guard maxOffset > 0 else { return false }

        // A mostly-horizontal swipe is already aimed at the right axis. Leave it
        // to AppKit, which rubber-bands and carries momentum properly.
        guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else { return false }

        // And only claim scrolls over the strip itself — anything else on the
        // surface belongs to whatever is under the pointer.
        let point = scrollView.convert(event.locationInWindow, from: nil)
        return scrollView.bounds.contains(point)
    }

    private func scroll(to x: CGFloat, animated: Bool) {
        guard let scrollView else { return }
        let clipView = scrollView.contentView
        let target = NSPoint(x: min(max(x, 0), maxOffset), y: clipView.bounds.origin.y)
        guard target.x != clipView.bounds.origin.x else { return }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                clipView.animator().setBoundsOrigin(target)
                scrollView.reflectScrolledClipView(clipView)
            }
        } else {
            clipView.setBoundsOrigin(target)
            scrollView.reflectScrolledClipView(clipView)
        }

        refresh()
    }

    private var offset: CGFloat {
        scrollView?.contentView.bounds.origin.x ?? 0
    }

    private var maxOffset: CGFloat {
        guard let scrollView, let documentView = scrollView.documentView else { return 0 }
        return max(0, documentView.frame.width - scrollView.contentView.bounds.width)
    }

    /// A point of slack either side: a sub-pixel remainder is not somewhere to
    /// go, and an arrow that does nothing is worse than no arrow.
    private func refresh() {
        guard scrollView != nil else {
            canScrollBack = false
            canScrollForward = false
            return
        }
        canScrollBack = offset > 1
        canScrollForward = offset < maxOffset - 1
    }
}

extension View {
    /// Hands the enclosing horizontal `ScrollView` to `scroller`.
    ///
    /// Apply it to the stack *inside* the scroll view — the bridge finds the
    /// scroll view by walking up the view hierarchy from where it is planted.
    func horizontalScroller(_ scroller: HorizontalScroller) -> some View {
        background(HorizontalScrollerBridge(scroller: scroller))
    }
}

/// A zero-size AppKit view whose only job is to find the `NSScrollView` that
/// SwiftUI built around it and hand it over. `NSViewRepresentable` is the
/// adapter that lets an AppKit view live inside a SwiftUI hierarchy.
private struct HorizontalScrollerBridge: NSViewRepresentable {
    let scroller: HorizontalScroller

    func makeNSView(context: Context) -> NSView { BridgeView(scroller: scroller) }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class BridgeView: NSView {
    private let scroller: HorizontalScroller

    init(scroller: HorizontalScroller) {
        self.scroller = scroller
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used — these views are created in code")
    }

    /// AppKit calls this whenever the view joins or leaves a window, which is
    /// exactly the lifetime the monitor and observers should have. Leaving —
    /// the panel rebuilds its content view on every open — tears them down, so
    /// nothing is left listening for a strip that is gone.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard window != nil else {
            scroller.detach()
            return
        }

        if let scrollView = enclosingScrollView {
            scroller.attach(to: scrollView)
        } else {
            // SwiftUI can install the background before the scroll view around
            // it exists; one turn of the run loop is enough for it to appear.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.window != nil else { return }
                    self.scroller.attach(to: self.enclosingScrollView)
                }
            }
        }
    }
}
