import AppKit
import CoreServices
import Foundation

/// Files new screenshots as image clips, even though they were never copied.
///
/// Two ways to do this exist: an `NSMetadataQuery` on `kMDItemIsScreenCapture`,
/// or watching the folder screenshots land in. This watches the folder, because
/// a live Spotlight query keeps an indexing session open for the whole life of
/// the process — too much for an app that's supposed to be invisible. Spotlight
/// is still used, but only once per new file, to confirm it really is a
/// screen capture rather than any image someone dropped on the Desktop.
@MainActor
final class ScreenshotWatcher {
    private let store: ClipStore
    private let settings: AppSettings

    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1

    /// The folder currently being watched, so a change of location can be
    /// noticed and followed.
    private var watchedDirectory: URL?
    private var activationObserver: NSObjectProtocol?

    /// Filenames seen at start-up, so existing screenshots aren't back-filled.
    private var knownFiles: Set<String> = []

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "tiff", "heic"]

    init(store: ClipStore, settings: AppSettings = .shared) {
        self.store = store
        self.settings = settings
    }

    // MARK: - Lifecycle

    /// Start or stop to match the setting. Called at launch and whenever the
    /// toggle changes.
    func syncWithSettings() {
        if settings.capturesScreenshots { start() } else { stop() }
    }

    /// Follow the user's screenshot location if it has changed.
    ///
    /// People move this — to `~/Screenshots`, to a Dropbox folder, to an
    /// external drive — and some do it *because* the app asked for Desktop
    /// access. Resolving the path once at launch would leave the app watching a
    /// folder nothing is being written to, silently capturing nothing.
    func refreshLocation() {
        guard settings.capturesScreenshots else { return }

        let current = Self.screenshotDirectory()
        guard current != watchedDirectory else { return }

        NSLog("Cache: screenshot folder moved to \(current.path) — following it")
        stop()
        start()
    }

    func start() {
        guard source == nil else { return }

        // Opening a descriptor on the screenshot folder is itself what triggers
        // the Desktop privacy prompt, so this must not run until the feature is
        // switched on. Checking only at ingest time would be too late — the
        // prompt would already have appeared.
        guard settings.capturesScreenshots else { return }

        let directory = Self.screenshotDirectory()
        watchedDirectory = directory
        knownFiles = Self.imageFilenames(in: directory)

        // A file descriptor opened `O_EVTONLY` is a watch handle, not a read
        // handle — it lets the kernel tell us about the directory without us
        // holding it open for I/O.
        descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            NSLog("Cache: could not watch \(directory.path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            // `.write` catches new files. `.delete` and `.rename` catch the
            // folder itself disappearing — which is what happens when someone
            // points macOS at a different location, or renames the old one.
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let source = self.source else { return }
                if source.data.contains(.delete) || source.data.contains(.rename) {
                    // The folder we were watching is gone. Re-resolve and
                    // re-attach rather than sitting on a dead descriptor.
                    self.stop()
                    self.start()
                    return
                }
                self.directoryChanged(directory)
            }
        }
        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }
        source.resume()

        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
        descriptor = -1
        watchedDirectory = nil
    }

    /// Re-check the location whenever the app comes forward. Changing the
    /// screenshot folder is a System Settings action, so the user is elsewhere
    /// when it happens and we would otherwise not hear about it until relaunch.
    func observeActivation() {
        guard activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshLocation() }
        }
    }

    // MARK: - Reacting

    private func directoryChanged(_ directory: URL) {
        let current = Self.imageFilenames(in: directory)
        let added = current.subtracting(knownFiles)
        knownFiles = current

        guard settings.capturesScreenshots, !added.isEmpty else { return }

        for filename in added {
            // The kernel tells us the directory changed the moment the file
            // appears — which can be before macOS has finished writing it, and
            // before Spotlight has tagged it. A short delay avoids reading a
            // half-written PNG.
            let url = directory.appendingPathComponent(filename)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                MainActor.assumeIsolated { self?.ingest(url) }
            }
        }
    }

    /// Delays between retries of the Spotlight check, in seconds.
    ///
    /// Spotlight does not tag a file the instant it is written — measured here,
    /// `kMDItemIsScreenCapture` was still null a second after the file appeared
    /// and only became true several seconds later. Checking once and giving up
    /// dropped real screenshots on the floor, and did it intermittently, which
    /// is the worst kind of bug: it works whenever Spotlight happens to be quick.
    private static let retryDelays: [TimeInterval] = [1.0, 2.0, 4.0]

    private func ingest(_ url: URL, attempt: Int = 0) {
        guard settings.capturesScreenshots,
              FileManager.default.fileExists(atPath: url.path)
        else { return }

        if needsScreenCaptureProof && !Self.isScreenCapture(url) {
            // Not tagged *yet*. Come back rather than discarding it.
            guard attempt < Self.retryDelays.count else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelays[attempt]) { [weak self] in
                MainActor.assumeIsolated { self?.ingest(url, attempt: attempt + 1) }
            }
            return
        }

        guard let image = NSImage(contentsOf: url) else { return }

        // The original stays where the user put it; we keep our own copy, so
        // deleting the Desktop file doesn't empty the clip.
        //
        // Filed into the Screenshots collection on the way in, so the chip is
        // populated without anyone having to sort anything by hand. OCR is
        // queued by `insertImage`, so the text inside is searchable shortly
        // after the file lands.
        store.insertImage(
            image,
            sourceAppName: "Screenshot",
            sourceAppBundleID: nil,
            category: Self.collectionName
        )
    }

    /// Whether a new image has to prove it is a screen capture.
    ///
    /// Only when the watched folder is one people keep other things in. If the
    /// user has pointed macOS at a folder of its own — which most people who
    /// move it do — then everything landing there *is* a screenshot, and
    /// demanding Spotlight confirm it just adds a way to fail.
    private var needsScreenCaptureProof: Bool {
        guard let watchedDirectory else { return true }
        return Self.isSharedFolder(watchedDirectory)
    }

    private static func isSharedFolder(_ directory: URL) -> Bool {
        let fm = FileManager.default
        var shared: [URL] = [URL(fileURLWithPath: NSHomeDirectory())]
        for which in [FileManager.SearchPathDirectory.desktopDirectory,
                      .downloadsDirectory,
                      .documentDirectory,
                      .picturesDirectory] {
            if let url = fm.urls(for: which, in: .userDomainMask).first { shared.append(url) }
        }
        return shared.contains { $0.standardizedFileURL.path == directory.standardizedFileURL.path }
    }

    /// The auto-assigned collection every screenshot lands in.
    static let collectionName = "Screenshots"

    // MARK: - Helpers

    /// Screenshots go wherever `com.apple.screencapture location` says, and to
    /// the Desktop when that's unset.
    static func screenshotDirectory() -> URL {
        if let location = UserDefaults(suiteName: "com.apple.screencapture")?
            .string(forKey: "location"),
           !location.isEmpty {
            return URL(fileURLWithPath: (location as NSString).expandingTildeInPath)
        }

        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    private static func imageFilenames(in directory: URL) -> Set<String> {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        return Set(names.filter { imageExtensions.contains(($0 as NSString).pathExtension.lowercased()) })
    }

    /// Spotlight tags real screen captures with `kMDItemIsScreenCapture`. This
    /// is what keeps every image saved to the Desktop out of the history.
    private static func isScreenCapture(_ url: URL) -> Bool {
        guard let item = MDItemCreate(nil, url.path as CFString) else { return false }
        let value = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString)
        return (value as? Bool) ?? false
    }
}
