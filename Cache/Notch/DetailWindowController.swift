import AppKit
import SwiftUI

/// The preview card that hangs below the open notch.
///
/// It gets a window of its own because the notch window must never change
/// size while it is on screen. A second window, built at the size its content
/// needs, never has to.
@MainActor
final class DetailWindowController {
    private var panel: NotchPanel?
    private(set) var isVisible = false

    /// Where it is on screen, while it is — the notch counts it as part of
    /// itself when deciding whether the pointer has left.
    var frame: CGRect? { isVisible ? panel?.frame : nil }

    func show<Content: View>(
        _ content: Content,
        size: CGSize,
        below anchor: CGRect,
        keyHandler: @escaping (NSEvent) -> Bool
    ) {
        let panel = self.panel ?? NotchPanel(contentRect: CGRect(origin: .zero, size: size))
        self.panel = panel

        // Hidden windows can be rearranged freely; visible ones cannot. So
        // order out first, every time, even when swapping one preview for another.
        panel.orderOut(nil)
        // Cancel a fade-out still in flight from the last preview.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
        panel.keyHandler = keyHandler
        panel.contentView = PanelHostingView(rootView: content)
        panel.setFrame(
            CGRect(
                x: (anchor.midX - size.width / 2).rounded(),
                y: (anchor.minY - 10 - size.height).rounded(),
                width: size.width,
                height: size.height
            ),
            display: false
        )
        panel.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        guard isVisible, let panel else { return }
        isVisible = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                guard !self.isVisible else { return }
                panel.orderOut(nil)
                panel.alphaValue = 1
                // Drop the SwiftUI tree so a closed preview holds no image.
                panel.contentView = nil
            }
        })
    }
}
