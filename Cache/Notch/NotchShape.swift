import SwiftUI

/// The notch's silhouette: a top edge that meets the menu bar through two
/// concave shoulders, straight sides, and rounded bottom corners.
///
/// The same shape draws the closed notch, the copy confirmation and the open
/// panel — only its size and radii change — so opening is one continuous
/// morph of the notch rather than a window fading in over it.
struct NotchShape: Shape {
    var shoulderRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(shoulderRadius, bottomRadius) }
        set {
            shoulderRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let shoulder = max(0, min(shoulderRadius, rect.width / 4, rect.height / 2))
        let bottom = max(0, min(bottomRadius, (rect.width - 2 * shoulder) / 2, rect.height - shoulder))

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Left shoulder curves in from the menu bar.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + shoulder, y: rect.minY + shoulder),
            control: CGPoint(x: rect.minX + shoulder, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + shoulder, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + shoulder + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + shoulder, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - shoulder - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - shoulder, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - shoulder, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - shoulder, y: rect.minY + shoulder))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - shoulder, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

/// Size and curvature of the shape for each state of the notch.
struct NotchSilhouette: Equatable {
    var width: CGFloat
    var height: CGFloat
    var shoulder: CGFloat
    var bottom: CGFloat

    /// Exactly over the hardware notch, so the first frame of opening is
    /// indistinguishable from the notch itself.
    static func closed(_ metrics: NotchMetrics) -> NotchSilhouette {
        NotchSilhouette(
            width: metrics.notchSize.width + 12,
            height: metrics.notchSize.height,
            shoulder: 6,
            bottom: metrics.hasNotch ? 10 : 0
        )
    }

    /// The notch widened either side to confirm a copy.
    static func peek(_ metrics: NotchMetrics) -> NotchSilhouette {
        let height = metrics.hasNotch ? metrics.notchSize.height : 32
        return NotchSilhouette(
            width: metrics.notchSize.width + 2 * Theme.Notch.peekEar + 12,
            height: height,
            shoulder: 6,
            bottom: min(14, height / 2)
        )
    }

    static func open(_ metrics: NotchMetrics) -> NotchSilhouette {
        NotchSilhouette(
            width: metrics.panelSize.width,
            height: metrics.panelSize.height,
            shoulder: Theme.Notch.shoulderRadius,
            bottom: Theme.Notch.bottomRadius
        )
    }
}
