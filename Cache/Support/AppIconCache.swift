import AppKit

/// Source-app icons, looked up once per bundle ID and kept — including the
/// misses, so an app that has since been deleted isn't searched for on every
/// card that mentions it.
@MainActor
enum AppIconCache {
    private static var icons: [String: NSImage?] = [:]

    static func icon(for clip: Clip) -> NSImage? {
        icon(forBundleID: clip.isScreenshot ? SourceApp.screenshot.bundleID : clip.sourceAppBundleID)
    }

    static func icon(forBundleID bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let known = icons[bundleID] { return known }

        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        icons[bundleID] = icon
        return icon
    }
}
