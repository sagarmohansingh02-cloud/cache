import AppKit
import SwiftUI

/// Apple's Liquid Glass, as a SwiftUI background.
///
/// macOS 26 ships this as real AppKit: `NSGlassEffectView` embeds content in a
/// dynamic glass material that refracts and reflects what is behind the window,
/// rather than just blurring it the way `NSVisualEffectView` does. There is no
/// SwiftUI `glassEffect` modifier in this SDK — the AppKit view is the API — and
/// since every SupaClip surface is already an AppKit panel, bridging it is a
/// two-line job.
///
/// The deployment target is macOS 14, so anything older falls back to the
/// `.hudWindow` material. That fallback is not a downgrade in kind — it is what
/// the app used before, and it still looks right.
struct LiquidGlass: NSViewRepresentable {
    enum Style {
        case regular   // frosted, the default chrome material
        case clear     // more transparent, for surfaces over busy content
    }

    var cornerRadius: CGFloat = 18
    var style: Style = .regular

    /// Glass takes its character from what's behind it; a dark tint is what
    /// keeps these surfaces reading as dark chrome rather than washing out over
    /// a light desktop.
    var tint: NSColor? = NSColor.black.withAlphaComponent(0.55)

    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            apply(to: glass)
            return glass
        }
        return makeFallback()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if #available(macOS 26.0, *), let glass = nsView as? NSGlassEffectView {
            apply(to: glass)
            return
        }
        nsView.layer?.cornerRadius = cornerRadius
    }

    @available(macOS 26.0, *)
    private func apply(to glass: NSGlassEffectView) {
        glass.cornerRadius = cornerRadius
        glass.tintColor = tint
        glass.style = style == .clear ? .clear : .regular
    }

    private func makeFallback() -> NSView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }
}

/// Merges nearby glass surfaces into one, the way Apple's own chrome does when
/// controls sit close together.
///
/// Without a container each glass view is rendered independently, so two pills
/// side by side look like two panes of glass laid on top of each other. Inside a
/// container they fuse when within `spacing`, and the whole group is rendered in
/// one pass — which is cheaper as well as better looking.
struct LiquidGlassContainer<Content: View>: NSViewRepresentable {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> NSView {
        let hosted = FirstMouseHostingView(rootView: content())
        hosted.translatesAutoresizingMaskIntoConstraints = false

        guard #available(macOS 26.0, *) else { return hosted }

        let container = NSGlassEffectContainerView()
        container.spacing = spacing
        container.contentView = hosted
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if #available(macOS 26.0, *),
           let container = nsView as? NSGlassEffectContainerView,
           let hosted = container.contentView as? FirstMouseHostingView<Content> {
            hosted.rootView = content()
            container.spacing = spacing
            return
        }
        (nsView as? FirstMouseHostingView<Content>)?.rootView = content()
    }
}

extension View {
    /// Put this surface on glass, clipped to a shape.
    func liquidGlass(
        cornerRadius: CGFloat = 18,
        style: LiquidGlass.Style = .regular,
        tint: NSColor? = NSColor.black.withAlphaComponent(0.55)
    ) -> some View {
        background(
            LiquidGlass(cornerRadius: cornerRadius, style: style, tint: tint)
        )
    }

    /// True when the running system actually has Liquid Glass, for the few
    /// places that want to lay out differently rather than just look different.
    static var supportsLiquidGlass: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}
