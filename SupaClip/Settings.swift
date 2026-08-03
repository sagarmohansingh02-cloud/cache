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
        static let capturesScreenshots = "capturesScreenshots"
        static let sortOrder = "sortOrder"
        static let viewMode = "viewMode"
        static let ignoredBundleIDs = "ignoredBundleIDs"
        static let ignoredKinds = "ignoredKinds"
        static let textExpansionEnabled = "textExpansionEnabled"
        static let didMigrateScreenshotDefault = "didMigrateScreenshotDefault"
    }

    /// Screenshot capture used to default to ON. Turning the default off is
    /// right for new installs — nobody should meet a Desktop permission prompt
    /// before asking for the feature — but for someone already running with it
    /// on, a silent switch-off just looks like the app broke.
    ///
    /// So: anyone who has never expressed a preference *and* already has a
    /// history keeps the old behaviour. A genuinely new install gets the new
    /// default. Runs once.
    func migrateScreenshotDefaultIfNeeded(hasExistingHistory: Bool) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Keys.didMigrateScreenshotDefault) else { return }
        defaults.set(true, forKey: Keys.didMigrateScreenshotDefault)

        // An explicit choice is never overridden.
        //
        // This must read the *persistent* domain, not `object(forKey:)`.
        // `object(forKey:)` also consults the registration domain, so it
        // returns the registered fallback rather than nil and makes it look as
        // though every user has already chosen — which silently skipped the
        // migration entirely.
        let domain = UserDefaults.standard
            .persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        guard domain?[Keys.capturesScreenshots] == nil else { return }

        if hasExistingHistory {
            capturesScreenshots = true
            NSLog("Cache: kept screenshot capture on for an existing install")
        }
    }

    var sortOrder: SortOrder {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: Keys.sortOrder) }
    }

    var viewMode: ViewMode {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: Keys.viewMode) }
    }

    /// Rules: apps whose copies are never recorded. Password managers already
    /// handle themselves via the concealed-type guard; this is for the user's
    /// own choices, like a banking app or a private notes app.
    var ignoredBundleIDs: [String] {
        didSet { UserDefaults.standard.set(ignoredBundleIDs, forKey: Keys.ignoredBundleIDs) }
    }

    /// Rules: kinds of content never recorded, stored as `ClipKind` raw values.
    var ignoredKinds: [String] {
        didSet { UserDefaults.standard.set(ignoredKinds, forKey: Keys.ignoredKinds) }
    }

    /// Inline text expansion. Off by default — it needs Accessibility and
    /// watches every keystroke system-wide, so it must be a deliberate choice.
    var textExpansionEnabled: Bool {
        didSet { UserDefaults.standard.set(textExpansionEnabled, forKey: Keys.textExpansionEnabled) }
    }

    /// Watch the system screenshot folder and file new screenshots as clips.
    ///
    /// **Off by default, deliberately.** The screenshot folder usually lives in
    /// Desktop, which macOS protects — so switching this on is what triggers the
    /// "would like to access files in your Desktop folder" prompt. Defaulting it
    /// on meant every new user got that prompt on first launch, before they had
    /// asked for anything, which is the fastest way to make someone distrust an
    /// app. Now the prompt only appears once someone has deliberately turned
    /// screenshot capture on, where it reads as an obvious consequence.
    var capturesScreenshots: Bool {
        didSet {
            UserDefaults.standard.set(capturesScreenshots, forKey: Keys.capturesScreenshots)
            onCapturesScreenshotsChanged?()
        }
    }

    /// Lets the watcher start and stop with the toggle rather than only at launch.
    @ObservationIgnored var onCapturesScreenshotsChanged: (() -> Void)?

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
        defaults.register(defaults: [
            Keys.historyLimit: Self.maxHistoryLimit,
            Keys.capturesScreenshots: false,
        ])

        capturesScreenshots = defaults.bool(forKey: Keys.capturesScreenshots)
        isPaused = defaults.bool(forKey: Keys.isPaused)
        historyLimit = min(defaults.integer(forKey: Keys.historyLimit), Self.maxHistoryLimit)

        sortOrder = SortOrder(rawValue: defaults.string(forKey: Keys.sortOrder) ?? "") ?? .newest
        viewMode = ViewMode(rawValue: defaults.string(forKey: Keys.viewMode) ?? "") ?? .list
        ignoredBundleIDs = defaults.stringArray(forKey: Keys.ignoredBundleIDs) ?? []
        ignoredKinds = defaults.stringArray(forKey: Keys.ignoredKinds) ?? []
        textExpansionEnabled = defaults.bool(forKey: Keys.textExpansionEnabled)
    }
}

