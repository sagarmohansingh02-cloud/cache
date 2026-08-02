import AppKit

/// Screen maths for the notch surface.
///
/// AppKit's coordinate space has its origin at the **bottom-left** of the
/// primary screen and y growing upward, which is the opposite of every web and
/// UIKit layout instinct. Everything here is in that space, so "the top of the
/// screen" is `frame.maxY`.
enum NotchGeometry {
    /// How far below the notch the cursor can be and still open the panel.
    /// Exposed as a setting because hitting a 32pt-tall strip exactly is fussy —
    /// this is the "pop-over sensitivity" dial.
    static let defaultHotZonePadding: CGFloat = 4

    /// Width of the hot zone on a screen with no notch, centred at the top.
    static let virtualNotchWidth: CGFloat = 180

    static let panelSize = CGSize(width: 720, height: 300)

    /// Taller variant, used while the detail card is open below the strip.
    static let expandedPanelSize = CGSize(width: 720, height: 560)
    static let dotSize = CGSize(width: 14, height: 14)

    /// Wide enough for the expanded pill's thumbnails.
    static let traySize = CGSize(width: 620, height: 56)

    /// The tray sits **below** the notch, never over it.
    ///
    /// This is load-bearing, not cosmetic. Hover detection uses a *global*
    /// event monitor, and global monitors do not observe events delivered to
    /// our own windows. When the pill covered the notch, the hot zone stopped
    /// seeing the pointer entirely and the strip could never open — the app
    /// went dead the moment you copied anything. Keeping the pill clear of the
    /// notch keeps the hot zone reachable.
    static func trayFrame(on screen: NSScreen) -> CGRect {
        let notchHeight = notchRect(on: screen)?.height
            ?? max(screen.frame.maxY - screen.visibleFrame.maxY, 24)

        return CGRect(
            x: (screen.frame.midX - traySize.width / 2).rounded(),
            y: (screen.frame.maxY - notchHeight - 4 - traySize.height).rounded(),
            width: traySize.width,
            height: traySize.height
        )
    }

    // MARK: - Notch detection

    /// A Mac laptop with a notch reports a non-zero top safe-area inset.
    /// External displays report zero, which is exactly the distinction we want.
    static func hasNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0
    }

    /// The physical notch, or nil on a screen that hasn't got one.
    ///
    /// `auxiliaryTopLeftArea` and `auxiliaryTopRightArea` are the usable menu
    /// bar strips either side of the notch — subtract them from the screen
    /// width and what's left is the notch itself.
    static func notchRect(on screen: NSScreen) -> CGRect? {
        guard hasNotch(screen),
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea
        else { return nil }

        let width = screen.frame.width - left.width - right.width
        guard width > 0 else { return nil }

        let height = screen.safeAreaInsets.top

        return CGRect(
            x: screen.frame.minX + left.width,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    /// Where the cursor has to be for the panel to open.
    ///
    /// On a notched laptop that's the notch itself. On any other display there
    /// is no notch to aim at, so we synthesise one at the top centre — the same
    /// target the blue dot marks.
    static func hotZone(on screen: NSScreen, padding: CGFloat = defaultHotZonePadding) -> CGRect {
        let base: CGRect

        if let notch = notchRect(on: screen) {
            base = notch
        } else {
            let height = max(screen.frame.maxY - screen.visibleFrame.maxY, 2)
            base = CGRect(
                x: screen.frame.midX - virtualNotchWidth / 2,
                y: screen.frame.maxY - height,
                width: virtualNotchWidth,
                height: height
            )
        }

        return base.insetBy(dx: -padding, dy: -padding)
    }

    /// The panel hangs from the very top of the screen, centred.
    static func panelFrame(on screen: NSScreen, size: CGSize = panelSize) -> CGRect {
        CGRect(
            x: (screen.frame.midX - size.width / 2).rounded(),
            y: (screen.frame.maxY - size.height).rounded(),
            width: size.width,
            height: size.height
        )
    }

    /// The blue dot for displays without a notch, centred just under the top edge.
    static func dotFrame(on screen: NSScreen) -> CGRect {
        let menuBarHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)

        return CGRect(
            x: (screen.frame.midX - dotSize.width / 2).rounded(),
            y: (screen.frame.maxY - menuBarHeight / 2 - dotSize.height / 2).rounded(),
            width: dotSize.width,
            height: dotSize.height
        )
    }

    // MARK: - Screen choice

    /// The screen the cursor is currently on.
    ///
    /// This is what makes multi-display work: the surface follows the pointer
    /// rather than being pinned to the built-in display.
    static func screenUnderCursor() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) } ?? NSScreen.main
    }
}
