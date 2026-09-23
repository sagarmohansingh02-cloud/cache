import Foundation
import Observation

/// User preferences, persisted in `UserDefaults`.
///
/// `@Observable` makes SwiftUI views that read these re-render when they
/// change. The clipboard monitor reads `isPaused` on every copy, which is a
/// plain property read, not a defaults lookup.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    /// Absolute ceiling, whatever the user picks.
    static let maxHistoryLimit = 2_000
    static let historyLimitOptions = [100, 500, 1_000, 2_000]

    private enum Keys {
        static let isPaused = "isPaused"
        static let historyLimit = "historyLimit"
        static let capturesScreenshots = "capturesScreenshots"
        static let screenshotFolderPath = "screenshotFolderPath"
        static let lastScreenshotFiledAt = "lastScreenshotFiledAt"
        static let ignoredBundleIDs = "ignoredBundleIDs"
        static let ignoredKinds = "ignoredKinds"
        static let collections = "collections"
        static let showsMenuBarIcon = "showsMenuBarIcon"
        static let opensOnHover = "opensOnHover"
        static let showsCopyPeek = "showsCopyPeek"
        static let didSetUpLaunchAtLogin = "didSetUpLaunchAtLogin"
    }

    @ObservationIgnored private let defaults = UserDefaults.standard

    /// Nothing new is recorded while paused. The poll keeps running so
    /// resuming doesn't grab whatever was copied in the meantime.
    var isPaused: Bool {
        didSet { defaults.set(isPaused, forKey: Keys.isPaused) }
    }

    var historyLimit: Int {
        didSet {
            let clamped = min(max(historyLimit, 1), Self.maxHistoryLimit)
            guard clamped == historyLimit else { historyLimit = clamped; return }
            defaults.set(historyLimit, forKey: Keys.historyLimit)
        }
    }

    /// Screenshots are half of what Cache is for, so this is on unless the
    /// user turns it off. The first time it runs, macOS asks for access to the
    /// screenshot folder — the prompt names the reason.
    var capturesScreenshots: Bool {
        didSet {
            defaults.set(capturesScreenshots, forKey: Keys.capturesScreenshots)
            // Switching back on starts from now: screenshots taken while it
            // was off were deliberately not wanted.
            if capturesScreenshots { lastScreenshotFiledAt = Date() }
            onScreenshotSettingsChanged?()
        }
    }

    /// A folder chosen in Settings; nil follows the macOS screenshot location.
    var screenshotFolderPath: String? {
        didSet {
            defaults.set(screenshotFolderPath, forKey: Keys.screenshotFolderPath)
            onScreenshotSettingsChanged?()
        }
    }

    /// When the last screenshot was filed, so screenshots taken while Cache
    /// was not running can be picked up on the next launch.
    var lastScreenshotFiledAt: Date? {
        get { defaults.object(forKey: Keys.lastScreenshotFiledAt) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastScreenshotFiledAt) }
    }

    @ObservationIgnored var onScreenshotSettingsChanged: (() -> Void)?

    /// Apps whose copies are never recorded — a banking app, a private notes
    /// app. Password managers are already covered by the concealed-type guard.
    var ignoredBundleIDs: [String] {
        didSet { defaults.set(ignoredBundleIDs, forKey: Keys.ignoredBundleIDs) }
    }

    /// `ClipKind` raw values that are never recorded.
    var ignoredKinds: [String] {
        didSet { defaults.set(ignoredKinds, forKey: Keys.ignoredKinds) }
    }

    /// Collections the user has made, in the order they were made. Kept here
    /// so a new, still-empty collection has a chip to drop things into.
    var collections: [String] {
        didSet { defaults.set(collections, forKey: Keys.collections) }
    }

    var showsMenuBarIcon: Bool {
        didSet { defaults.set(showsMenuBarIcon, forKey: Keys.showsMenuBarIcon) }
    }

    /// Open when the pointer reaches the notch. Off means click to open.
    var opensOnHover: Bool {
        didSet {
            defaults.set(opensOnHover, forKey: Keys.opensOnHover)
            onOpensOnHoverChanged?()
        }
    }

    @ObservationIgnored var onOpensOnHoverChanged: (() -> Void)?

    /// The notch widens for a moment to confirm each copy.
    var showsCopyPeek: Bool {
        didSet { defaults.set(showsCopyPeek, forKey: Keys.showsCopyPeek) }
    }

    var didSetUpLaunchAtLogin: Bool {
        get { defaults.bool(forKey: Keys.didSetUpLaunchAtLogin) }
        set { defaults.set(newValue, forKey: Keys.didSetUpLaunchAtLogin) }
    }

    private init() {
        defaults.register(defaults: [
            Keys.historyLimit: Self.maxHistoryLimit,
            Keys.capturesScreenshots: true,
            Keys.showsMenuBarIcon: true,
            Keys.opensOnHover: true,
            Keys.showsCopyPeek: true,
        ])

        isPaused = defaults.bool(forKey: Keys.isPaused)
        historyLimit = min(max(defaults.integer(forKey: Keys.historyLimit), 1), Self.maxHistoryLimit)
        capturesScreenshots = defaults.bool(forKey: Keys.capturesScreenshots)
        screenshotFolderPath = defaults.string(forKey: Keys.screenshotFolderPath)
        ignoredBundleIDs = defaults.stringArray(forKey: Keys.ignoredBundleIDs) ?? []
        ignoredKinds = defaults.stringArray(forKey: Keys.ignoredKinds) ?? []
        collections = defaults.stringArray(forKey: Keys.collections) ?? []
        showsMenuBarIcon = defaults.bool(forKey: Keys.showsMenuBarIcon)
        opensOnHover = defaults.bool(forKey: Keys.opensOnHover)
        showsCopyPeek = defaults.bool(forKey: Keys.showsCopyPeek)
    }
}
