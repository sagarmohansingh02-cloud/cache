import AppKit
import SwiftUI

/// A single clip card in the list.
struct ClipRow: View {
    let clip: Clip
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                Text(clip.text ?? "")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    if let icon = AppIconCache.icon(forBundleID: clip.sourceAppBundleID) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                    }

                    Text(clip.sourceAppName ?? "Unknown")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(Self.relativeTime(clip.createdAt))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.rowPaddingH)
            .padding(.vertical, Theme.rowPaddingV)
            .frame(height: Theme.textRowHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(isHovering ? Theme.hoverFill : Color.clear)
            )
            .overlay(
                // A 1px hairline, never a drop shadow.
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        // Strips the default macOS push-button chrome — the card *is* the button.
        .buttonStyle(.plain)
        .onHover { hovering in
            // Hover states are mandatory on macOS; without them the list feels dead.
            withAnimation(Theme.hoverFade) { isHovering = hovering }
        }
    }

    /// Compact relative timestamps: "now", "2m", "1h", "yesterday", "3d".
    static func relativeTime(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)

        if seconds < 60 { return "now" }
        if seconds < 3_600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))h" }
        if Calendar.current.isDateInYesterday(date) { return "yesterday" }
        return "\(Int(seconds / 86_400))d"
    }
}
