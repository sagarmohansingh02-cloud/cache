import KeyboardShortcuts
import SwiftUI

/// The settings sheet, shown from the footer gear.
///
/// Scrolls rather than paginates: there are now enough switches that a fixed
/// panel can't hold them, and a scroll keeps everything one gesture away
/// instead of hidden behind tabs.
struct SettingsView: View {
    @Bindable var settings: AppSettings

    /// Apps seen in the history, offered as candidates for the ignore list.
    var knownApps: [FilterBar.SourceApp] = []

    let onClearAll: () -> Void
    let onClose: () -> Void

    @State private var isConfirmingClear = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    shortcutSection
                    Divider()
                    captureSection
                    Divider()
                    rulesSection
                    Divider()
                    expansionSection
                    Divider()
                    historySection
                }
                .padding(16)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: Theme.panelWidth, height: Theme.panelHeight)
    }

    // MARK: - Sections

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The package's own recorder view: click it, press a combination,
            // and it registers the global hotkey and persists it for us. Press
            // delete while recording to clear it.
            KeyboardShortcuts.Recorder("Global hotkey", name: .togglePanel)
                .font(.system(size: 13))

            Text("Opens the floating panel from any app. Press ⌫ while recording to remove it.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            toggle(
                "Pause capture",
                detail: "Nothing new is recorded while paused.",
                isOn: $settings.isPaused
            )

            toggle(
                "Save screenshots",
                detail: "New screenshots are added automatically, even if you never copy them.",
                isOn: $settings.capturesScreenshots
            )
        }
    }

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rules")
                .font(.system(size: 13, weight: .medium))

            Text("Nothing copied from an ignored app, or of an ignored type, is ever recorded.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text("Ignored types")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            // Wraps because six chips don't fit one line at this width.
            FlowRow(spacing: 4) {
                ForEach(ClipKind.allCases, id: \.self) { kind in
                    ruleChip(
                        label: kind.displayName,
                        isOn: settings.ignoredKinds.contains(kind.rawValue)
                    ) {
                        toggleMembership(of: kind.rawValue, in: \.ignoredKinds)
                    }
                }
            }

            if !knownApps.isEmpty {
                Text("Ignored apps")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                FlowRow(spacing: 4) {
                    ForEach(knownApps) { app in
                        ruleChip(
                            label: app.name,
                            isOn: settings.ignoredBundleIDs.contains(app.bundleID)
                        ) {
                            toggleMembership(of: app.bundleID, in: \.ignoredBundleIDs)
                        }
                    }
                }
            }
        }
    }

    private var expansionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            toggle(
                "Inline text expansion",
                detail: "Type a snippet's trigger anywhere and it expands. Requires Accessibility permission.",
                isOn: $settings.textExpansionEnabled
            )

            if settings.textExpansionEnabled {
                Label(
                    "While this is on, SupaClip observes your keystrokes system-wide to detect triggers. Nothing is stored or sent anywhere.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("History limit", selection: $settings.historyLimit) {
                ForEach(AppSettings.historyLimitOptions, id: \.self) { limit in
                    Text("\(limit) clips").tag(limit)
                }
            }
            .font(.system(size: 13))

            Text("Older unpinned clips are deleted automatically.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                isConfirmingClear = true
            } label: {
                Text("Clear all clips").font(.system(size: 13))
            }
            .padding(.top, 4)
            .confirmationDialog(
                "Delete every clip?",
                isPresented: $isConfirmingClear,
                titleVisibility: .visible
            ) {
                Button("Delete all", role: .destructive) { onClearAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your entire history, including pinned clips and saved images. It can't be undone.")
            }
        }
    }

    // MARK: - Pieces

    private func toggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .tint(Theme.accent)
    }

    private func ruleChip(label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(isOn ? Color.white : Color.secondary)
                .background(Capsule().fill(isOn ? Theme.accent : Color.primary.opacity(0.06)))
                .overlay(Capsule().strokeBorder(isOn ? Color.clear : Theme.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func toggleMembership(of value: String, in keyPath: ReferenceWritableKeyPath<AppSettings, [String]>) {
        var current = settings[keyPath: keyPath]
        if let index = current.firstIndex(of: value) {
            current.remove(at: index)
        } else {
            current.append(value)
        }
        settings[keyPath: keyPath] = current
    }
}

/// A minimal wrapping stack.
///
/// SwiftUI on macOS 14 has no `WrappingHStack`, and a horizontal `ScrollView`
/// of chips hides items off-screen where the user can't see what's enabled.
/// `Layout` lets us do the line-breaking arithmetic directly.
struct FlowRow: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: CGFloat = 1
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                rows += 1
                x = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: rows * rowHeight + (rows - 1) * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
