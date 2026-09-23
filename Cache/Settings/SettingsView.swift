import AppKit
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

/// Cache's settings, as a native grouped form.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    let watcher: ScreenshotWatcher
    let store: ClipStore

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginNeedsApproval = LaunchAtLogin.needsApproval
    @State private var recentApps: [SourceApp] = []
    @State private var clearableCount = 0
    @State private var isConfirmingClear = false

    var body: some View {
        Form {
            generalSection
            screenshotsSection
            captureSection
            historySection
            privacySection
        }
        .formStyle(.grouped)
        .frame(minWidth: 540, minHeight: 640)
        .onAppear(perform: refresh)
        .confirmationDialog("Clear \(clearableCount) clips?", isPresented: $isConfirmingClear) {
            Button("Clear History", role: .destructive) {
                store.clearHistory()
                refresh()
            }
        } message: {
            Text("Every clip that isn't starred is removed. Saved images go to the Trash.")
        }
    }

    // MARK: - Sections

    private var generalSection: some View {
        Section("General") {
            Toggle("Open at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    guard enabled != LaunchAtLogin.isEnabled else { return }
                    LaunchAtLogin.setEnabled(enabled)
                    refreshLoginItem()
                }
            if loginNeedsApproval {
                LabeledContent("macOS is waiting for your approval") {
                    Button("Open Login Items…", action: LaunchAtLogin.openLoginItemsSettings)
                }
            }
            Toggle("Open when the pointer reaches the notch", isOn: $settings.opensOnHover)
            Toggle("Flash the notch when something is copied", isOn: $settings.showsCopyPeek)
            Toggle("Show in menu bar", isOn: $settings.showsMenuBarIcon)
            KeyboardShortcuts.Recorder("Open Cache from anywhere", name: .toggleNotch)
        }
    }

    private var screenshotsSection: some View {
        Section {
            Toggle("Save new screenshots", isOn: $settings.capturesScreenshots)

            if settings.capturesScreenshots {
                LabeledContent("Folder") {
                    Text(folderDescription)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                screenshotStatus
                HStack {
                    Button("Choose Folder…", action: chooseScreenshotFolder)
                    if settings.screenshotFolderPath != nil {
                        Button("Use the macOS Location") { settings.screenshotFolderPath = nil }
                    }
                }
            }
        } header: {
            Text("Screenshots")
        } footer: {
            Text("Cache follows the folder set in the Screenshot app (⇧⌘5 → Options). The text in each screenshot is read on this Mac, so you can search for it.")
        }
    }

    @ViewBuilder
    private var screenshotStatus: some View {
        switch watcher.status {
        case .watching:
            Label("Watching for new screenshots", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .connecting:
            Label("Waiting for access to the folder…", systemImage: "clock")
                .foregroundStyle(.secondary)
        case .needsAccess:
            LabeledContent {
                Button("Allow Access…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } label: {
                Label("macOS is blocking this folder", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        case .folderMissing:
            Label("This folder doesn't exist", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .off:
            EmptyView()
        }
    }

    private var captureSection: some View {
        Section {
            Toggle("Pause capture", isOn: $settings.isPaused)

            LabeledContent("Never save") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(ClipKind.allCases, id: \.self) { kind in
                        Toggle(kind.pluralName, isOn: ignoreBinding(for: kind))
                            .toggleStyle(.checkbox)
                    }
                }
            }

            LabeledContent("Ignored apps") {
                VStack(alignment: .trailing, spacing: 8) {
                    ForEach(settings.ignoredBundleIDs, id: \.self) { bundleID in
                        HStack(spacing: 8) {
                            if let icon = AppIconCache.icon(forBundleID: bundleID) {
                                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                            }
                            Text(Self.appName(for: bundleID))
                            Button {
                                settings.ignoredBundleIDs.removeAll { $0 == bundleID }
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Stop ignoring")
                        }
                    }
                    Menu("Add App") {
                        ForEach(recentApps.filter { !settings.ignoredBundleIDs.contains($0.bundleID ?? "") }, id: \.bundleID) { app in
                            Button(app.name ?? app.bundleID ?? "App") { ignore(app.bundleID) }
                        }
                        if !recentApps.isEmpty { Divider() }
                        Button("Choose…", action: chooseAppToIgnore)
                    }
                    .fixedSize()
                }
            }
        } header: {
            Text("Capture")
        } footer: {
            Text("Nothing copied from an ignored app, or of a type you never save, is recorded.")
        }
    }

    private var historySection: some View {
        Section {
            Picker("Keep up to", selection: $settings.historyLimit) {
                ForEach(AppSettings.historyLimitOptions, id: \.self) { limit in
                    Text("\(limit.formatted()) clips").tag(limit)
                }
            }
            LabeledContent("\(clearableCount.formatted()) clips can be cleared") {
                Button("Clear History…", role: .destructive) { isConfirmingClear = true }
                    .disabled(clearableCount == 0)
            }
        } header: {
            Text("History")
        } footer: {
            Text("Starred clips are never removed — not by the limit, and not by clearing.")
        }
    }

    private var privacySection: some View {
        Section("Privacy") {
            privacyLine("lock.fill", "Passwords are never saved. Anything a password manager marks as concealed is skipped before it is read.")
            privacyLine("internaldrive.fill", "Everything stays on this Mac. Clips live in Application Support; images live beside them.")
            privacyLine("wifi.slash", "No network access. No account, no sync, no analytics.")
            privacyLine("keyboard", "No keystroke monitoring. History comes from the system clipboard, not from watching you type.")
        }
    }

    private func privacyLine(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
        }
    }

    // MARK: - Actions

    private var folderDescription: String {
        let folder = ScreenshotWatcher.resolvedFolder(settings: settings)
        let path = folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        return settings.screenshotFolderPath == nil ? "\(path) (macOS setting)" : path
    }

    private func ignoreBinding(for kind: ClipKind) -> Binding<Bool> {
        Binding(
            get: { settings.ignoredKinds.contains(kind.rawValue) },
            set: { ignored in
                settings.ignoredKinds.removeAll { $0 == kind.rawValue }
                if ignored { settings.ignoredKinds.append(kind.rawValue) }
            }
        )
    }

    private func ignore(_ bundleID: String?) {
        guard let bundleID, !settings.ignoredBundleIDs.contains(bundleID) else { return }
        settings.ignoredBundleIDs.append(bundleID)
    }

    private func chooseScreenshotFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Watch Folder"
        panel.message = "Choose the folder your screenshots are saved to."
        panel.directoryURL = ScreenshotWatcher.resolvedFolder(settings: settings)
        if panel.runModal() == .OK, let url = panel.url {
            settings.screenshotFolderPath = url.path
        }
    }

    private func chooseAppToIgnore() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Ignore App"
        if panel.runModal() == .OK, let url = panel.url {
            ignore(Bundle(url: url)?.bundleIdentifier)
        }
    }

    private func refresh() {
        refreshLoginItem()
        clearableCount = store.unstarredCount()
        recentApps = store.recentSources()
    }

    private func refreshLoginItem() {
        launchAtLogin = LaunchAtLogin.isEnabled
        loginNeedsApproval = LaunchAtLogin.needsApproval
    }

    static func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
