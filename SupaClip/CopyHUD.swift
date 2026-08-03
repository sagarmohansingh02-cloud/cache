import AppKit
import SwiftUI

/// The `⌘ C` flash at the bottom of the screen when something is captured.
///
/// Worth being precise about what triggers this: **nothing watches the
/// keyboard**. The HUD fires off the pasteboard `changeCount` we already poll,
/// so it appears whenever a copy actually lands — including copies made from a
/// menu or a right-click, which a ⌘C key watcher would miss. Same effect as the
/// reference, without observing a single keystroke.
@MainActor
final class CopyHUDController {
    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?
    private let visible = HUDVisibility()

    private static let size = CGSize(width: 168, height: 76)
    private static let bottomMargin: CGFloat = 140
    private static let dwell: TimeInterval = 0.9

    /// Show the flash, restarting the timer if it's already up — copying five
    /// things quickly should read as one continuous confirmation, not a stutter.
    func flash() {
        guard let screen = NotchGeometry.screenUnderCursor() else { return }

        let panel = panel ?? makePanel()
        self.panel = panel

        panel.setFrame(
            CGRect(
                x: (screen.frame.midX - Self.size.width / 2).rounded(),
                y: (screen.visibleFrame.minY + Self.bottomMargin).rounded(),
                width: Self.size.width,
                height: Self.size.height
            ),
            display: false
        )
        panel.orderFrontRegardless()

        withAnimation(.easeOut(duration: 0.12)) { visible.isVisible = true }

        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dwell, execute: work)
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.18)) { visible.isVisible = false }

        // Order the window out only after the fade has actually played.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.visible.isVisible == false else { return }
                self.panel?.orderOut(nil)
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
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
        // Purely a notification — it must never intercept a click.
        panel.ignoresMouseEvents = true

        panel.contentView = FirstMouseHostingView(rootView: CopyHUDView(visibility: visible))
        return panel
    }
}

/// Tiny observable box so the controller can drive the SwiftUI fade.
@MainActor
@Observable
final class HUDVisibility {
    var isVisible = false
}

private struct CopyHUDView: View {
    @Bindable var visibility: HUDVisibility

    var body: some View {
        HStack(spacing: 10) {
            key("⌘")
            key("C")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LiquidGlass(cornerRadius: 22, style: .clear))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        )
        .opacity(visibility.isVisible ? 1 : 0)
        .scaleEffect(visibility.isVisible ? 1 : 0.92)
        .animation(Theme.standardSpring, value: visibility.isVisible)
    }

    private func key(_ glyph: String) -> some View {
        Text(glyph)
            .font(.system(size: 24, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 48, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.10))
            )
    }
}
