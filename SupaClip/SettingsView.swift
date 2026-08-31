import KeyboardShortcuts
import SwiftData
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

    /// How many clips are stored right now, shown on the clear button so it
    /// says what it is about to delete rather than asking you to guess.
    var clipCount: Int = 0

    /// The notch presents this in its own window, which is a different size
    /// from the Library's sheet. Defaults keep every existing caller unchanged.
    var width: CGFloat = Theme.panelWidth
    var height: CGFloat = Theme.panelHeight

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
                    historySection
                    Divider()
                    privacySection
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
        .frame(width: width, height: height)
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
                "Show copy shelf",
                detail: "The count pill that drops from the notch after each copy. It floats above other windows.",
                isOn: $settings.showsCopyShelf
            )

            toggle(
                "Save screenshots",
                detail: "New screenshots are added automatically, even if you never copy them.",
                isOn: $settings.capturesScreenshots
            )

            // Show which folder is actually being watched. People move this, and
            // an app that silently watches the wrong place looks broken rather
            // than misconfigured.
            if settings.capturesScreenshots {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(ScreenshotWatcher.screenshotDirectory().path
                            .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.leading, 2)

                Text("Detected from your macOS screenshot location. Move it and Cache follows.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
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

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("History limit", selection: $settings.historyLimit) {
                ForEach(AppSettings.historyLimitOptions, id: \.self) { limit in
                    Text("\(limit) clips").tag(limit)
                }
            }
            .font(.system(size: 13))

            Text("Older unpinned clips are deleted automatically. Pinned clips are never removed, by the limit or by clearing.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Button {
                isConfirmingClear = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                    Text(clipCount > 0 ? "Clear History (\(clipCount))" : "Clear History")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(clipCount == 0 ? Color.secondary : Color.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(Color.red.opacity(clipCount == 0 ? 0 : 0.12))
                )
                .overlay(
                    Capsule().strokeBorder(
                        clipCount == 0 ? Theme.cardBorder : Color.red.opacity(0.35),
                        lineWidth: 1
                    )
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(clipCount == 0)
            .padding(.top, 4)
            .confirmationDialog(
                "Clear history?",
                isPresented: $isConfirmingClear,
                titleVisibility: .visible
            ) {
                Button("Clear History", role: .destructive) { onClearAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Deletes every unpinned clip. Pinned clips are kept, and images go to the Trash.")
            }
        }
    }

    /// Stated plainly, in the app rather than only in a file on GitHub. A
    /// clipboard manager sees everything you copy, so the burden is on it to say
    /// what it does with that.
    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Privacy")
                .font(.system(size: 13, weight: .medium))

            privacyLine("lock.fill", "Passwords are never saved. Anything a password manager marks as concealed is skipped before it is read.")
            privacyLine("externaldrive.fill", "Everything stays on this Mac. Clips live in Application Support; images live beside them.")
            privacyLine("wifi.slash", "No network access. Cache makes no requests, has no account, and sends no analytics.")
            privacyLine("keyboard", "No keystroke monitoring. History comes from the system pasteboard, not from watching you type.")

            Text("Clearing history removes it from disk, putting saved images in the Trash. Uninstalling removes the app; delete the Application Support folder to remove the data.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    private func privacyLine(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(Theme.accent)
                .frame(width: 14)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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

/// Settings as the notch presents it.
///
/// Its own window, for the reason given in `NotchController.showSettings`. On
/// the same dark glass as the strip, but rounded on all four corners — it hangs
/// free in the desktop rather than meeting the screen edge, so there is no
/// square top to align with anything.
struct NotchSettingsSurface: View {
    @Environment(\.modelContext) private var modelContext

    let onClose: () -> Void

    @Bindable private var settings = AppSettings.shared

    /// What Clear History would delete — unpinned only, since pinned clips
    /// survive it. Counted rather than fetched: `@Query` here would materialise
    /// every Clip just to show a number, against the rule that the app never
    /// loads the full history.
    @State private var clipCount = 0

    private var store: ClipStore {
        ClipStore(context: modelContext, settings: settings)
    }

    var body: some View {
        SettingsView(
            settings: settings,
            clipCount: clipCount,
            width: NotchGeometry.settingsSize.width,
            height: NotchGeometry.settingsSize.height,
            onClearAll: {
                store.clearHistory()
                refreshCount()
            },
            onClose: onClose
        )
        .background(LiquidGlass(cornerRadius: 22, style: .regular))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .preferredColorScheme(.dark)
        .onAppear(perform: refreshCount)
    }

    private func refreshCount() {
        clipCount = store.unpinnedCount()
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
