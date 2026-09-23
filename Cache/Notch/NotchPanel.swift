import AppKit

/// A borderless, non-activating panel that floats over the menu bar and can
/// still take the keyboard.
///
/// **Non-activating** is what keeps the app you are working in active while
/// you use Cache, so ⌘V afterwards goes where you expect. **Borderless**
/// windows refuse to become key by default, which would leave the search field
/// deaf — `canBecomeKey` turns that back on.
///
/// The panel is also where scroll and key events are intercepted. Every event
/// bound for the window passes through `sendEvent(_:)` whether or not Cache is
/// the active app, which makes it the one reliable place to catch them — an
/// `NSEvent` monitor only sees events AppKit decides to dispatch to an app,
/// and for an app that is never active that is not something to count on.
final class NotchPanel: NSPanel {
    /// Plain key presses, before the focused text field sees them. Return
    /// true to swallow the event.
    var keyHandler: ((NSEvent) -> Bool)?

    /// ⌘-shortcuts, before the menu bar sees them.
    var shortcutHandler: ((NSEvent) -> Bool)?

    /// Modifier changes — holding ⌘ reveals the ⌘1–9 hints on the cards.
    var modifiersHandler: ((NSEvent.ModifierFlags) -> Void)?

    /// Scroll events. Return true once handled.
    var scrollHandler: ((NSEvent) -> Bool)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // Above the menu bar and its status items: the surface hangs from the
        // very top of the screen and has to be able to cover them.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        animationBehavior = .none
        isMovable = false
        isReleasedWhenClosed = false
        // Clicking a card shouldn't take the keyboard from the app you are
        // working in; clicking into the search field should.
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .scrollWheel:
            if scrollHandler?(event) == true { return }
        case .keyDown:
            if keyHandler?(event) == true { return }
        case .flagsChanged:
            modifiersHandler?(event.modifierFlags)
        default:
            break
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if shortcutHandler?(event) == true { return true }

        // The standard editing shortcuts, for the search field. An app that
        // lives in the menu bar has no Edit menu on screen to route them.
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if let editor = firstResponder as? NSText, flags == .command || flags == [.command, .shift] {
            switch (event.charactersIgnoringModifiers?.lowercased(), flags.contains(.shift)) {
            case ("a", false): editor.selectAll(nil); return true
            case ("c", false): editor.copy(nil); return true
            case ("v", false): editor.paste(nil); return true
            case ("x", false): editor.cut(nil); return true
            case ("z", false): editor.undoManager?.undo(); return true
            case ("z", true): editor.undoManager?.redo(); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Moves the strip of cards with a mouse wheel or a vertical swipe.
///
/// A scroll event carries its distance on one axis, and a scroll view only
/// spends it on the axis it was aimed at. A mouse wheel — and a trackpad swipe
/// that reads as vertical — therefore moved the horizontal strip by nothing:
/// the older clips were there, but nothing reached them. Horizontal swipes are
/// left to the scroll view, which already handles them natively with momentum
/// and rubber-banding; vertical movement is turned into horizontal here.
@MainActor
final class StripScroller: NSObject {
    /// The strip's scroll view — the one SwiftUI builds for the card row.
    weak var scrollView: NSScrollView?

    private var gestureIsVertical = false
    private var target: CGFloat?
    private var displayLink: CADisplayLink?
    private var lastFrame: CFTimeInterval = 0

    /// Points moved per line of a mouse wheel notch.
    private static let lineStep: CGFloat = 42

    func handle(_ event: NSEvent) -> Bool {
        guard let scrollView else { return false }
        let clip = scrollView.contentView
        guard let document = scrollView.documentView, document.frame.width > clip.bounds.width + 1 else { return false }

        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY

        if event.hasPreciseScrollingDeltas {
            // Trackpad or Magic Mouse. Decide once per gesture, at its start,
            // and let its momentum follow the same decision.
            if event.phase == .began || event.phase == .mayBegin {
                gestureIsVertical = abs(dy) > abs(dx)
            } else if event.phase.isEmpty && event.momentumPhase.isEmpty {
                gestureIsVertical = abs(dy) > abs(dx)
            }
            guard gestureIsVertical else { return false }
            stopAnimating()
            target = nil
            move(to: clip.bounds.origin.x - dy)
            return true
        }

        // A mouse wheel. Horizontal wheels (and Shift-scrolling) already do
        // the right thing.
        guard dx == 0, dy != 0 else { return false }
        let start = target ?? clip.bounds.origin.x
        target = clamped(start - dy * Self.lineStep)
        startAnimating()
        return true
    }

    /// Forget any glide in progress — the content under it has changed.
    func reset() {
        stopAnimating()
        target = nil
    }

    /// Back to the newest clip, with the strip's padding intact. (Scrolling
    /// to the first card instead aligns the card itself with the edge, which
    /// pushes it under the panel's rounded side and cuts it off.)
    func scrollToStart() {
        reset()
        guard let bounds else { return }
        move(to: bounds.min)
    }

    // MARK: - Moving

    private var bounds: (min: CGFloat, max: CGFloat)? {
        guard let scrollView, let document = scrollView.documentView else { return nil }
        let clip = scrollView.contentView
        let minX = document.frame.minX - clip.contentInsets.left
        let maxX = max(minX, document.frame.maxX - clip.bounds.width + clip.contentInsets.right)
        return (minX, maxX)
    }

    private func clamped(_ x: CGFloat) -> CGFloat {
        guard let bounds else { return x }
        return min(max(x, bounds.min), bounds.max)
    }

    private func move(to x: CGFloat) {
        guard let scrollView else { return }
        let clip = scrollView.contentView
        let origin = NSPoint(x: clamped(x), y: clip.bounds.origin.y)
        guard origin != clip.bounds.origin else { return }
        clip.scroll(to: origin)
        scrollView.reflectScrolledClipView(clip)
    }

    // MARK: - Wheel glide

    /// Eases toward the target on the display's own clock, so a wheel notch
    /// glides instead of jumping and a spin of the wheel reads as one motion.
    private func startAnimating() {
        guard displayLink == nil, let scrollView else { return }
        let link = scrollView.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastFrame = 0
    }

    private func stopAnimating() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let scrollView, let target else {
            stopAnimating()
            return
        }
        let now = link.timestamp
        let elapsed = lastFrame == 0 ? 1.0 / 120 : min(now - lastFrame, 1.0 / 30)
        lastFrame = now

        let current = scrollView.contentView.bounds.origin.x
        // Frame-rate independent exponential ease: about 90% of the way in 120ms.
        let progress = 1 - pow(0.1, elapsed / 0.12)
        let next = current + (target - current) * CGFloat(progress)

        if abs(target - next) < 0.5 {
            move(to: target)
            self.target = nil
            stopAnimating()
        } else {
            move(to: next)
        }
    }
}
