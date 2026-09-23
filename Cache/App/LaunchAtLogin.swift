import Foundation
import ServiceManagement

/// Starting with the Mac.
///
/// A clipboard history that stops recording after a restart looks like one
/// that is broken — which is exactly how screenshots were being "missed".
/// `SMAppService` registers the app itself as a login item; the user can see
/// and remove it in System Settings → General → Login Items.
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// macOS is holding the login item until the user approves it.
    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Cache: could not change the login item — \(error.localizedDescription)")
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Turned on once, the first time an installed copy runs. Only for a copy
    /// in /Applications — a build running out of Xcode or a Downloads folder
    /// has no business registering itself to start at login.
    static func enableOnFirstRun(settings: AppSettings) {
        guard !settings.didSetUpLaunchAtLogin,
              Bundle.main.bundleURL.path.hasPrefix("/Applications/")
        else { return }
        settings.didSetUpLaunchAtLogin = true
        setEnabled(true)
    }
}
