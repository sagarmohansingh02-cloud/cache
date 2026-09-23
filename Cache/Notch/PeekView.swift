import SwiftUI

/// The copy confirmation: a glimpse of what was copied in the notch's left
/// ear, and what happened in the right one. The hardware notch sits between
/// them, which is why the middle is left empty.
struct PeekView: View {
    let peek: Peek
    let metrics: NotchMetrics

    @State private var thumbnail: CGImage?

    var body: some View {
        let height = metrics.hasNotch ? metrics.notchSize.height : 32

        HStack(spacing: 0) {
            glimpse
                .frame(width: Theme.Notch.peekEar, alignment: .leading)
                .padding(.leading, 14)

            Spacer(minLength: 0)

            Text(peek.label)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.label.opacity(0.9))
                .lineLimit(1)
                .fixedSize()
                .padding(.trailing, 16)
        }
        .frame(width: NotchSilhouette.peek(metrics).width, height: height)
        .task(id: peek.clipID) {
            guard let key = peek.thumbnailKey else { thumbnail = nil; return }
            thumbnail = ThumbnailLoader.shared.cached(key)
            if thumbnail == nil {
                thumbnail = await ThumbnailLoader.shared.image(candidates: peek.thumbnailCandidates, maxPixelSize: 96, key: key + "@peek")
            }
        }
    }

    @ViewBuilder
    private var glimpse: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)

        Group {
            if let thumbnail {
                Image(decorative: thumbnail, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let color = ClipColor.color(from: peek.colorText) {
                Color(nsColor: color)
            } else {
                Image(systemName: peek.isScreenshot ? "camera.viewfinder" : peek.kind.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.label)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.raisedHover)
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.hairline))
    }
}
