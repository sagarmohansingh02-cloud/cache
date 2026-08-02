import KeyboardShortcuts
import Observation
import SwiftUI

/// User preferences, persisted in `UserDefaults`.
///
/// `@Observable` is the Observation framework — SwiftUI views that read these
/// properties re-render when they change, with no `@Published` or ObservableObject
/// boilerplate. The monitor reads `isPaused` from here on every tick, which is a
/// plain property read rather than a UserDefaults lookup.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    /// Absolute ceiling regardless of what the user picks.
    static let maxHistoryLimit = 2_000
    static let historyLimitOptions = [100, 500, 1_000, 2_000]

    private enum Keys {
        static let isPaused = "isPaused"
        static let historyLimit = "historyLimit"
    }

    /// When paused the poll timer keeps running but nothing is recorded — the
    /// timer stays alive so we don't miss the changeCount baseline on resume.
    var isPaused: Bool {
        didSet { UserDefaults.standard.set(isPaused, forKey: Keys.isPaused) }
    }

    var historyLimit: Int {
        didSet {
            let clamped = min(historyLimit, Self.maxHistoryLimit)
            if clamped != historyLimit {
                historyLimit = clamped
                return
            }
            UserDefaults.standard.set(historyLimit, forKey: Keys.historyLimit)
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Keys.historyLimit: Self.maxHistoryLimit])

        isPaused = defaults.bool(forKey: Keys.isPaused)
        historyLimit = min(defaults.integer(forKey: Keys.historyLimit), Self.maxHistoryLimit)
    }
}

/// The settings sheet, shown from the footer gear.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    let onClearAll: () -> Void
    let onClose: () -> Void

    @State private var isConfirmingClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.system(size: 13, weight: .medium))

            VStack(alignment: .leading, spacing: 4) {
                // The package's own recorder view: click it, press a combination,
                // and it registers the global hotkey and persists it for us.
                KeyboardShortcuts.Recorder("Global hotkey", name: .togglePanel)
                    .font(.system(size: 13))

                Text("Opens the floating panel from any app.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: $settings.isPaused) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pause capture")
                        .font(.system(size: 13))
                    Text("Nothing new is recorded while paused.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .tint(Theme.accent)

            VStack(alignment: .leading, spacing: 4) {
                Picker("History limit", selection: $settings.historyLimit) {
                    ForEach(AppSettings.historyLimitOptions, id: \.self) { limit in
                        Text("\(limit) clips").tag(limit)
                    }
                }
                .font(.system(size: 13))

                Text("Older unpinned clips are deleted automatically.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button(role: .destructive) {
                isConfirmingClear = true
            } label: {
                Text("Clear all clips")
                    .font(.system(size: 13))
            }
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

            Spacer()

            HStack {
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: Theme.panelWidth, height: Theme.panelHeight)
    }
}
