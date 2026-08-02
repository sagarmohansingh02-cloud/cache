import AppKit
import SwiftUI

/// Design tokens. Every magic number in the UI comes from here so the 8px grid
/// and the single-accent rule can't drift.
enum Theme {
    /// The one accent colour in the whole app. Used only for selection state,
    /// active filter chips and the pinned indicator. Nothing else is coloured.
    /// `.accentColor` follows the user's System Settings choice, which is the
    /// most native answer available.
    static let accent = Color.accentColor

    // Spacing — only ever 4, 8, 12, 16, 24.
    static let windowPadding: CGFloat = 12
    static let rowSpacing: CGFloat = 6
    static let rowPaddingH: CGFloat = 12
    static let rowPaddingV: CGFloat = 8

    // Shape
    static let windowCornerRadius: CGFloat = 12
    static let cardCornerRadius: CGFloat = 8

    // Rows
    static let textRowHeight: CGFloat = 56

    // Surfaces — hairlines and hover fills, never drop shadows.
    static let cardBorder = Color.white.opacity(0.08)
    static let hoverFill = Color.white.opacity(0.06)

    // Motion
    static let standardSpring = Animation.spring(response: 0.3, dampingFraction: 0.8)
    static let hoverFade = Animation.easeOut(duration: 0.12)

    static let panelWidth: CGFloat = 360
    static let panelHeight: CGFloat = 420
}

/// SwiftUI has no native equivalent of `NSVisualEffectView`, so we bridge it.
///
/// AppKit background: `NSViewRepresentable` is the adapter protocol that lets an
/// old AppKit view live inside a SwiftUI hierarchy. You implement `makeNSView`
/// (build it once) and `updateNSView` (re-apply state when SwiftUI re-renders).
///
/// The material itself is what makes a Mac app feel native — it's a real-time
/// blur of whatever is behind the window, composited on the GPU, so it's
/// essentially free. `.behindWindow` blending is what samples the desktop
/// rather than the app's own content.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        // `.active` keeps the blur live even when the window isn't key —
        // without it the material greys out the moment focus moves away.
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

/// Source-app icons, looked up once per bundle ID and kept.
///
/// `NSWorkspace` is AppKit's window into the rest of the system — installed
/// apps, their locations, their icons. We resolve the bundle ID to an app URL
/// and ask for the real icon, so rows show the actual Notes/Xcode/Safari icon
/// rather than a generic placeholder.
@MainActor
enum AppIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(forBundleID bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }
}
