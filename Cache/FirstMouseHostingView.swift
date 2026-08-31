import AppKit
import SwiftUI

/// The hosting view every Cache panel uses. It fixes two AppKit behaviours
/// that are wrong for a menu bar utility.
///
/// **1. First click.** Cache is an `LSUIElement` app whose panels are all
/// `.nonactivatingPanel`, so the app is never the active application. macOS
/// treats the first click on an inactive app's window as the click that brings
/// it forward and, by default, does *not* deliver it to the view underneath.
/// `NSHostingView` returns false from `acceptsFirstMouse(for:)`, so every
/// SwiftUI button in every panel silently ate the user's first click — usually
/// the only click they make.
///
/// **2. Safe area.** Our notch panels sit deliberately over the notch and menu
/// bar, which is precisely the region safe-area insets describe. Any frame
/// change makes SwiftUI recompute them, which calls
/// `setNeedsUpdateConstraints:` on the window mid-layout, which throws an
/// exception and aborts the process. That was the crash on opening a preview:
///
///     NSHostingView.invalidateSafeAreaInsets()
///       → -[NSView setNeedsUpdateConstraints:]
///         → -[NSWindow _postWindowNeedsUpdateConstraints]
///           → NSException → abort()
///
/// These panels are borderless and position themselves by hand, so safe-area
/// insets buy us nothing — opting out removes the whole code path.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        disableSafeAreaHandling()
    }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) is not used — these views are created in code")
    }

    private func disableSafeAreaHandling() {
        // We lay these windows out against the physical screen ourselves.
        safeAreaRegions = []
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
