import AppKit
import Observation
import SwiftUI

/// A horizontal strip of SwiftUI content on an AppKit scroll view we own.
///
/// AppKit background: a scroll event carries its distance on one axis, and a
/// scroll view only spends that distance on the axis it was aimed at. A mouse
/// wheel — and a trackpad swipe that reads as vertical — therefore moves a
/// horizontal strip by nothing at all: the clips past the right edge exist, but
/// nothing the user does brings them into view.
///
/// The place to fix that is inside the scroll view's own `scrollWheel(with:)`,
/// which is how AppKit hands a wheel event to a scroll view. SwiftUI's
/// `ScrollView` offers no such hook and no access to the `NSScrollView` it is
/// built on, so this hosts the content in one we control instead. That also
/// gives the arrows something honest to ask: whether there is any strip left to
/// either side.
///
/// An earlier attempt did this with a local `NSEvent` monitor. It never fired —
/// the same lesson `HotZoneWindow` records: a local monitor only sees events
/// actually dispatched to us, and for an app that is never the active
/// application that is not something to rely on. The responder chain is.
struct HorizontalStrip<Content: View>: NSViewRepresentable {
    let scroller: HorizontalScroller

    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> WheelAxisScrollView {
        let scrollView = WheelAxisScrollView()

        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.automaticallyAdjustsContentInsets = false

        // The document view is a `FirstMouseHostingView` for the reason that
        // class exists: Cache is never the active app, so an ordinary hosting
        // view would swallow the first click on every card.
        let hosting = FirstMouseHostingView(rootView: content())
        hosting.frame = .zero
        scrollView.documentView = hosting

        scroller.attach(to: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: WheelAxisScrollView, context: Context) {
        (scrollView.documentView as? FirstMouseHostingView<Content>)?.rootView = content()
        scrollView.sizeDocumentToContent()
        scroller.attach(to: scrollView)
    }

    /// Report the content's own height so the strip sits at its natural size,
    /// the way the SwiftUI stack it replaced did.
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: WheelAxisScrollView,
        context: Context
    ) -> CGSize? {
        // Nil means "size me the ordinary way" — the right answer before the
        // content has measured itself, rather than collapsing the strip to
        // nothing.
        guard let hosting = nsView.documentView, hosting.fittingSize.height > 0 else { return nil }
        return CGSize(width: proposal.width ?? hosting.fittingSize.width,
                      height: hosting.fittingSize.height)
    }

    static func dismantleNSView(_ nsView: WheelAxisScrollView, coordinator: ()) {
        nsView.onScroll = nil
    }
}

/// The scroll view behind `HorizontalStrip`. Its whole job is the wheel.
final class WheelAxisScrollView: NSScrollView {
    /// Called whenever the visible slice moves or the content is resized.
    var onScroll: (() -> Void)?

    /// A wheel reports its distance in lines rather than points, so a notch
    /// needs scaling up. At this size three notches move about a card.
    private static let wheelStep: CGFloat = 40

    /// Turns a vertical scroll into horizontal movement.
    ///
    /// A mostly-horizontal swipe is left to `super`, which rubber-bands and
    /// carries momentum properly — it was already aimed at the right axis.
    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX), maxOffset > minOffset else {
            super.scrollWheel(with: event)
            return
        }

        let distance = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY
            : event.scrollingDeltaY * Self.wheelStep

        // AppKit's sign convention: a positive delta moves content toward the
        // beginning. Subtracting it means scrolling down walks forward through
        // older clips, which is the direction the strip reads in.
        setOffset(offset - distance, animated: false)
    }

    override func layout() {
        super.layout()
        sizeDocumentToContent()
    }

    /// The document is as wide as its content and as tall as the strip. Sizing
    /// it by hand rather than by constraints keeps SwiftUI's frame-based layout
    /// and Auto Layout from disagreeing about who owns the document view.
    func sizeDocumentToContent() {
        guard let documentView else { return }

        let fitting = documentView.fittingSize
        let height = max(fitting.height, contentView.bounds.height)
        let size = NSSize(width: fitting.width, height: height)
        guard documentView.frame.size != size else { return }

        documentView.setFrameSize(size)
        clampOffset()
        onScroll?()
    }

    // MARK: - Offsets

    var offset: CGFloat { contentView.bounds.origin.x }

    var minOffset: CGFloat { documentView?.frame.minX ?? 0 }

    var maxOffset: CGFloat {
        guard let documentView else { return 0 }
        return max(minOffset, documentView.frame.maxX - contentView.bounds.width)
    }

    func setOffset(_ x: CGFloat, animated: Bool) {
        let target = NSPoint(x: min(max(x, minOffset), maxOffset), y: contentView.bounds.origin.y)
        guard target.x != contentView.bounds.origin.x else { return }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                contentView.animator().setBoundsOrigin(target)
                reflectScrolledClipView(contentView)
            }
        } else {
            contentView.setBoundsOrigin(target)
            reflectScrolledClipView(contentView)
        }

        onScroll?()
    }

    /// Content shrinking — a filter chip, a deleted clip — can leave the strip
    /// scrolled past its own end.
    private func clampOffset() {
        let clamped = min(max(offset, minOffset), maxOffset)
        guard clamped != offset else { return }
        contentView.setBoundsOrigin(NSPoint(x: clamped, y: contentView.bounds.origin.y))
        reflectScrolledClipView(contentView)
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        onScroll?()
    }
}

/// Whether the strip has anywhere left to go, and the arrows' way of moving it.
///
/// A class rather than view state because the answer changes from AppKit — a
/// scroll, a resize — rather than from a SwiftUI update, and a `View` is a
/// struct whose copy a callback would freeze. Same reasoning as `ListNavigator`.
@MainActor
@Observable
final class HorizontalScroller {
    enum Direction {
        case back, forward

        var sign: CGFloat { self == .back ? -1 : 1 }
    }

    private(set) var canScrollBack = false
    private(set) var canScrollForward = false

    @ObservationIgnored private weak var scrollView: WheelAxisScrollView?

    /// One press of an arrow moves most of a screenful, leaving a card or two
    /// behind as an anchor so the jump doesn't lose the user's place.
    private static let pageFraction: CGFloat = 0.8

    fileprivate func attach(to scrollView: WheelAxisScrollView) {
        if self.scrollView !== scrollView {
            self.scrollView = scrollView
            scrollView.onScroll = { [weak self] in self?.refresh() }
        }
        refresh()
    }

    func page(_ direction: Direction) {
        guard let scrollView else { return }
        let distance = max(scrollView.contentView.bounds.width * Self.pageFraction, 160)
        scrollView.setOffset(scrollView.offset + direction.sign * distance, animated: true)
    }

    /// A point of slack either side: a sub-pixel remainder is not somewhere to
    /// go, and an arrow that does nothing is worse than no arrow.
    private func refresh() {
        guard let scrollView else {
            canScrollBack = false
            canScrollForward = false
            return
        }
        canScrollBack = scrollView.offset > scrollView.minOffset + 1
        canScrollForward = scrollView.offset < scrollView.maxOffset - 1
    }
}
