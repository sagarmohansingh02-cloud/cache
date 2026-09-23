import AppKit
import SwiftUI

/// Design tokens. Every colour, size and curve in the UI comes from here.
///
/// The idea the whole palette hangs on: the panel is the notch's own black, so
/// opening it reads as the notch growing rather than a window appearing.
/// Everything else is a step of grey on that black, and the only colour on
/// screen comes from what you copied — screenshots, swatches, app icons.
enum Theme {
    // MARK: Palette

    // Values measured off the reference design, not eyeballed.

    /// The panel. Pure black, the same as the hardware notch.
    static let ink = Color.black
    /// Chips at rest — #222222.
    static let raised = Color(white: 0.133)
    static let raisedHover = Color(white: 0.19)
    /// Round buttons — #323232, a step lighter than the chips.
    static let control = Color(white: 0.196)
    static let controlHover = Color(white: 0.25)
    /// Text, link and file cards — #323232, darkening to near-black at the
    /// bottom where the footer sits.
    static let cardSurface = Color(white: 0.196)
    static let codeSurface = Color(white: 0.15)
    /// Card edge — #4C4C4C against the card.
    static let hairline = Color.white.opacity(0.12)
    static let hairlineHover = Color.white.opacity(0.3)

    static let label = Color.white
    static let secondaryLabel = Color.white.opacity(0.62)
    static let tertiaryLabel = Color.white.opacity(0.38)

    // MARK: Type — SF Pro, the Mac's own voice, sized for a glance

    static let search = Font.system(size: 17, weight: .regular)
    static let chip = Font.system(size: 15, weight: .medium)
    static let chipCount = Font.system(size: 15, weight: .regular).monospacedDigit()
    static let cardText = Font.system(size: 14, weight: .medium)
    static let cardTitle = Font.system(size: 16, weight: .semibold)
    static let cardCode = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let meta = Font.system(size: 12, weight: .medium)
    static let swatch = Font.system(size: 16, weight: .semibold).monospacedDigit()

    // MARK: Motion

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// The notch growing into the panel. A touch of overshoot, like a drop of
    /// ink settling — the one flourish in the app.
    static var open: Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.42, dampingFraction: 0.8)
    }

    /// Going away is quicker than arriving, and never bounces.
    static var close: Animation {
        reduceMotion ? .easeIn(duration: 0.12) : .spring(response: 0.3, dampingFraction: 1)
    }

    static var peek: Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.36, dampingFraction: 0.72)
    }

    static let hover = Animation.easeOut(duration: 0.14)
    static let select = Animation.spring(response: 0.3, dampingFraction: 0.84)

    // MARK: Notch layout, in points

    enum Notch {
        static let maxWidth: CGFloat = 1_000
        /// Room left between the panel and the screen edges.
        static let screenMargin: CGFloat = 80

        /// The concave curves where the panel's top edge meets the menu bar.
        static let shoulderRadius: CGFloat = 14
        static let bottomRadius: CGFloat = 30

        static let sidePadding: CGFloat = 20
        /// Soft edge where the strip meets the panel's sides.
        static let edgeFade: CGFloat = 18
        /// The top row starts in the menu bar band and hangs a little below
        /// it, the way the reference sits just under the menu bar's text.
        static let topRowExtra: CGFloat = 12
        static let chipHeight: CGFloat = 38
        static let chipTopGap: CGFloat = 10
        static let cardTopGap: CGFloat = 22
        static let bottomPadding: CGFloat = 18
        static let roundButton: CGFloat = 34
        static let footerIcon: CGFloat = 18

        static let card = CGSize(width: 204, height: 153)
        static let cardRadius: CGFloat = 16
        static let cardSpacing: CGFloat = 12

        /// How far the notch widens either side to confirm a copy.
        static let peekEar: CGFloat = 76

        static func panelHeight(band: CGFloat) -> CGFloat {
            (band + topRowExtra) + chipTopGap + chipHeight + cardTopGap + card.height + bottomPadding
        }
    }
}
