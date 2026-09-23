import AppKit
import SwiftUI

/// The hosting view every Cache panel uses. It fixes three AppKit defaults
/// that are wrong for panels that hang from the notch.
///
/// **First click.** Cache never becomes the active app, and macOS treats the
/// first click on an inactive app's window as "bring it forward" rather than
/// delivering it. `NSHostingView` accepts that default, so every button would
/// eat the user's first click — usually the only one they make.
///
/// **Safe area.** These panels sit over the menu bar and notch, exactly the
/// region safe-area insets describe. Recomputing them on a frame change calls
/// `setNeedsUpdateConstraints:` mid-layout, which throws and aborts the
/// process. The panels place themselves, so the insets buy nothing.
///
/// **Sizing.** By default the hosting view pushes its content's ideal size
/// onto the window. The notch window is a fixed size and must never be
/// resized while it is on screen — the same layout-time abort — so the
/// content is not allowed to ask.
final class PanelHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        safeAreaRegions = []
        sizingOptions = []
    }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) is not used — these views are created in code")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
