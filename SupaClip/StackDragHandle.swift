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
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        view.makeItems = makeItems
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {
        nsView.makeItems = makeItems
        nsView.onDragEnded = onDragEnded
    }
}

final class DragSourceView: NSView, NSDraggingSource {
    var makeItems: (() -> [NSDraggingItem])?
    var onDragEnded: (() -> Void)?

    /// Without this the first click just focuses the window and the drag is
    /// swallowed — which matters a lot here, because the panel isn't active.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Swallow the press so `mouseDragged` follows. Doing nothing here is
    /// deliberate: a click that never becomes a drag should do nothing.
    override func mouseDown(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        guard let items = makeItems?(), !items.isEmpty else { return }
        beginDraggingSession(with: items, event: event, source: self)
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
