import AppKit
import Observation
import SwiftUI

/// Whether the pill is currently on screen, and whether the pointer is on it.
///
/// The pill is deliberately transient: it announces a copy and then gets out of
/// the way. Nothing of SupaClip's should sit on the desktop permanently.
@MainActor
@Observable
final class TrayPresentation {
    var isVisible = false
    var isHovering = false
}

/// The count pill that hangs from the notch as you copy.
///
/// Collapsed it is a single line — "5 items · Text, Image" — with the stack
/// fanned behind it. Hovering expands it into the thumbnails, and dragging from
/// anywhere on it pulls the whole stack out at once.
struct NotchTrayView: View {
    private let tray = CopyTray.shared

    /// Drives the fade. Owned by the controller so the timer and the animation
    /// agree about when the pill is on screen.
    @Bindable var presentation: TrayPresentation

    /// Click-through to the full notch strip.
    let onOpenStrip: () -> Void

    private var isHovering: Bool { presentation.isHovering }

    var body: some View {
        VStack(spacing: 0) {
            // The window itself is already positioned clear of the notch, so no
            // spacer is needed — and no transparent area sits over the hot zone
            // to block hover detection.
            if !tray.isEmpty {
                pill
                    // Drops in from behind the notch and retreats back into it.
                    .offset(y: presentation.isVisible ? 0 : -14)
                    .opacity(presentation.isVisible ? 1 : 0)
                    .scaleEffect(presentation.isVisible ? 1 : 0.9, anchor: .top)
                    .blur(radius: presentation.isVisible ? 0 : 3)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Theme.standardSpring, value: tray.count)
        .animation(Theme.standardSpring, value: isHovering)
        .animation(Theme.standardSpring, value: presentation.isVisible)
    }


    // MARK: - Pill

    private var pill: some View {
        HStack(spacing: 8) {
            // The draggable half: the stack and what it says.
            //
            // The drag handle covers only this, never the buttons. It is an
            // AppKit view that swallows `mouseDown` so a press can become a
            // drag — laid over the whole pill, as it used to be, that swallow
            // also ate every click on ✕ and the open button, which is why
            // neither worked. Scoping it to the content leaves the controls
            // reachable and still lets a drag start from the pill's body.
            HStack(spacing: 8) {
                if isHovering {
                    thumbnails
                } else {
                    fannedStack
                }

                Text(tray.summary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize()
            }
            .overlay(
                StackDragHandle(
                    makeItems: { tray.draggingItems() },
                    // A press that never became a drag is a click, and a click
                    // on the pill opens the strip. Handled inside the AppKit
                    // view because it is the thing receiving the event —
                    // `.onTapGesture` out here never sees it.
                    onClick: { onOpenStrip() },
                    onDragEnded: { tray.clear() }
                )
            )

            if isHovering {
                Divider().frame(height: 14).overlay(.white.opacity(0.15))

                iconButton("rectangle.stack") { onOpenStrip() }
                    .help("Open clipboard")

                iconButton("xmark") { tray.clear() }
                    .help("Clear shelf")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(LiquidGlass(cornerRadius: 22, style: .regular))
        .clipShape(Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        )
        // Lifts toward the pointer, the way Apple's glass controls do.
        .scaleEffect(isHovering ? 1.03 : 1.0)
        // Hovering holds the pill open — the fade timer checks this before it
        // retracts, so reaching for the stack never has it vanish mid-reach.
        .onHover { hovering in presentation.isHovering = hovering }
    }

    /// Collapsed state: the stack peeking out from behind itself, so the pill
    /// reads as holding things rather than just counting them.
    private var fannedStack: some View {
        ZStack(alignment: .leading) {
            ForEach(Array(tray.items.prefix(3).enumerated()), id: \.element.id) { index, clip in
                miniTile(for: clip)
                    .offset(x: CGFloat(index) * 7)
                    .zIndex(Double(3 - index))
            }
        }
        .frame(width: 18 + CGFloat(min(tray.count, 3) - 1) * 7, height: 18, alignment: .leading)
    }

    private var thumbnails: some View {
        HStack(spacing: 4) {
            ForEach(tray.items.prefix(8), id: \.id) { clip in
                miniTile(for: clip)
            }
        }
    }

    @ViewBuilder
    private func miniTile(for clip: Clip) -> some View {
        let kind = ClipKind(rawValue: clip.kind) ?? .text

        Group {
            switch kind {
            case .image:
                if let thumbnail = ThumbnailCache.thumbnail(named: clip.thumbnailFilename) {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                } else {
                    tileSymbol("photo")
                }
            case .color:
                Color(nsColor: ClipColorParser.color(from: clip.text) ?? .black)
            case .file:
                tileSymbol("doc")
            case .link:
                tileSymbol("link")
            case .code:
                tileSymbol("chevron.left.forwardslash.chevron.right")
            case .text:
                tileSymbol("text.alignleft")
            }
        }
        .frame(width: 18, height: 18)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        )
    }

    private func tileSymbol(_ name: String) -> some View {
        ZStack {
            Color.white.opacity(0.10)
            Image(systemName: name)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
