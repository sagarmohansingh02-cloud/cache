import AppKit

/// Sizes and positions of the notch surface on one screen.
///
/// AppKit's screen coordinates start at the bottom-left of the primary display
/// with y growing upward — so "the top of the screen" is `frame.maxY`.
struct NotchMetrics: Equatable {
    let screenFrame: CGRect
    let hasNotch: Bool
    /// The hardware notch, or a stand-in at the top centre of a display
    /// without one (zero tall, so the panel unrolls from the top edge).
    let notchSize: CGSize
    /// Height of the menu bar band the top row lines up with.
    let bandHeight: CGFloat
    /// The window, which is also the open panel.
    let panelSize: CGSize

    init(screen: NSScreen) {
        screenFrame = screen.frame
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        bandHeight = max(menuBar, screen.safeAreaInsets.top, 24)

        if let notch = NotchGeometry.notchRect(on: screen) {
            hasNotch = true
            notchSize = notch.size
        } else {
            hasNotch = false
            notchSize = CGSize(width: 220, height: 0)
        }

        let width = min(Theme.Notch.maxWidth, screen.frame.width - 2 * Theme.Notch.screenMargin)
        panelSize = CGSize(width: width.rounded(), height: Theme.Notch.panelHeight(band: bandHeight).rounded())
    }

    /// Hangs from the top edge, centred on the notch.
    var panelFrame: CGRect {
        CGRect(
            x: (screenFrame.midX - panelSize.width / 2).rounded(),
            y: screenFrame.maxY - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )
    }
}

enum NotchGeometry {
    /// A notched MacBook reports a top safe-area inset, and the usable menu
    /// bar either side of the notch as two auxiliary areas. The notch is
    /// what's left between them. External displays report neither.
    static func notchRect(on screen: NSScreen) -> CGRect? {
        guard screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else { return nil }

        let width = screen.frame.width - left.width - right.width
        guard width > 0 else { return nil }
        let height = screen.safeAreaInsets.top
        return CGRect(x: screen.frame.minX + left.width, y: screen.frame.maxY - height, width: width, height: height)
    }

    /// Where the pointer opens the panel: the notch itself, or on a display
    /// without one, the same width at the top centre of the menu bar.
    static func hotZone(on screen: NSScreen) -> CGRect {
        if let notch = notchRect(on: screen) {
            return notch.insetBy(dx: -2, dy: 0)
        }
        let height = max(screen.frame.maxY - screen.visibleFrame.maxY, 4)
        return CGRect(x: screen.frame.midX - 110, y: screen.frame.maxY - height, width: 220, height: height)
    }

    /// The display the pointer is on. The top edge counts as inside — that is
    /// exactly where the pointer rests when it is in the notch.
    static func screenWithPointer() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            let frame = screen.frame
            return point.x >= frame.minX && point.x <= frame.maxX && point.y >= frame.minY && point.y <= frame.maxY
        } ?? NSScreen.main
    }
}
