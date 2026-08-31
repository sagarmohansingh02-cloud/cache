import SwiftUI

/// Replaces the filter chips while a multi-selection is active.
///
/// It takes the same slot rather than appearing below it, so the list never
/// jumps as the bar shows and hides.
struct BulkActionBar: View {
    let selectedCount: Int
    let onCopy: () -> Void
    let onSelectSimilar: () -> Void
    let onDelete: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("\(selectedCount) selected")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.accent)

            Spacer()

            action("Copy", symbol: "doc.on.doc", action: onCopy)
            action("Similar", symbol: "square.on.square", action: onSelectSimilar)
            action("Delete", symbol: "trash", action: onDelete)

            Divider().frame(height: 12)

            Button(action: onClear) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear selection")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: 24)
        .background(
            Capsule().fill(Theme.accent.opacity(0.12))
        )
    }

    private func action(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 9))
                Text(label).font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
