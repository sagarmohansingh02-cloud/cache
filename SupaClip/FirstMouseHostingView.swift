import AppKit
import SwiftUI

/// An `NSHostingView` that responds to the very first click.
///
/// This fixes a whole class of "the UI isn't clickable" bugs, and the reason is
/// subtle. SupaClip is an `LSUIElement` app whose panels are all
/// `.nonactivatingPanel`, so the app is **never the active application**. When
/// you click a window belonging to an inactive app, macOS treats that first
/// click as the one that brings the window forward and, by default, does *not*
/// deliver it to the view underneath. `NSHostingView` returns false from
/// `acceptsFirstMouse(for:)`, so every SwiftUI button in every panel silently
/// ate the user's first click — which, since the panel closes or the pointer
/// moves on, is usually the only click they make.
///
/// Returning true delivers that click straight through to SwiftUI.
///
/// Use this everywhere instead of `NSHostingView`.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
