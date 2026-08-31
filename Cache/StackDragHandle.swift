import AppKit
import SwiftUI

/// Lets the whole tray be dragged off as a stack.
///
/// AppKit background, and the reason this isn't SwiftUI: `.onDrag` hands the
/// system exactly **one** `NSItemProvider`. Dropping five files into Finder
/// needs five dragging items in a single session, which only
/// `beginDraggingSession(with:event:source:)` on an `NSView` can express. So
/// this is a transparent AppKit view laid over the pill that starts the real
/// drag when the mouse moves with the button down.
struct StackDragHandle: NSViewRepresentable {
    /// Built at drag time rather than up front, so the stack is whatever the
    /// tray holds at the moment you start dragging.
    let makeItems: () -> [NSDraggingItem]

    /// A press that never turned into a drag. This view swallows `mouseDown`
    /// to keep the drag possible, which also means no SwiftUI gesture behind
    /// it will ever fire — so the click has to be reported from here.
    var onClick: (() -> Void)?

    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        view.makeItems = makeItems
        view.onClick = onClick
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {
        nsView.makeItems = makeItems
        nsView.onClick = onClick
        nsView.onDragEnded = onDragEnded
    }
}

final class DragSourceView: NSView, NSDraggingSource {
    var makeItems: (() -> [NSDraggingItem])?
    var onClick: (() -> Void)?
    var onDragEnded: (() -> Void)?

    /// Whether this press has already turned into a drag, so the release can
    /// tell a click apart from the end of a drag.
    private var didDrag = false

    /// Without this the first click just focuses the window and the drag is
    /// swallowed — which matters a lot here, because the panel isn't active.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Swallow the press so `mouseDragged` follows.
    override func mouseDown(with event: NSEvent) {
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didDrag else { return }
        guard let items = makeItems?(), !items.isEmpty else { return }
        didDrag = true
        beginDraggingSession(with: items, event: event, source: self)
    }

    /// A release with no drag in between is a click. Without this the press
    /// swallowed above would simply vanish, which is what left the pill
    /// unclickable.
    override func mouseUp(with event: NSEvent) {
        guard !didDrag else { return }
        onClick?()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        // Copy, never move — the clip stays in history after you drag it out.
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        // Only clear the shelf when the drop actually landed somewhere.
        guard operation != [] else { return }
        onDragEnded?()
    }
}
