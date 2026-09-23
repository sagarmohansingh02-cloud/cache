import AppKit
import CoreServices
import Foundation
import Observation

/// Files every new screenshot as a clip, even though nobody copied it.
///
/// Three things made the old watcher miss screenshots, and each is handled
/// here:
///
/// 1. **It waited on Spotlight.** It confirmed a file was a screenshot by
///    asking Spotlight, which tags new files seconds late — or never, when
///    indexing is busy. macOS writes the same marker straight onto the file as
///    an extended attribute at the moment of capture, so that is read instead:
///    instant, and independent of indexing.
/// 2. **It never noticed the folder moving.** The screenshot location was
///    re-read only when the app was activated, which an app that lives in the
///    notch never is. It is now re-read every few seconds.
/// 3. **It failed silently.** When macOS denied access to the folder, the
///    watcher gave up without a word. `status` now says so, and the notch
///    offers the fix.
///
/// Watching uses FSEvents with per-file events, which names the exact file
/// that appeared, where the old directory descriptor only said "something
/// changed" and left the app to diff the listing.
@MainActor
@Observable
final class ScreenshotWatcher {
    enum Status: Equatable {
        case off
        case connecting(URL)
        case watching(URL)
        /// macOS privacy settings are keeping Cache out of the folder.
        case needsAccess(URL)
        case folderMissing(URL)

        var folder: URL? {
            switch self {
            case .off: nil
            case .connecting(let url), .watching(let url), .needsAccess(let url), .folderMissing(let url): url
            }
        }
    }

    private(set) var status: Status = .off

    @ObservationIgnored private let store: ClipStore
    @ObservationIgnored private let settings: AppSettings

    @ObservationIgnored private var stream: FSEventStreamRef?
    @ObservationIgnored private var folder: URL?
    @ObservationIgnored private var folderPath = ""
    @ObservationIgnored private var isDedicatedFolder = false
    @ObservationIgnored private var isProbing = false
    @ObservationIgnored private var pending: [String: DispatchWorkItem] = [:]
    @ObservationIgnored private var attempts: [String: Int] = [:]
    /// Files already filed, by file identity rather than path, so renaming a
    /// screenshot in the Finder never files it twice.
    @ObservationIgnored private var handledFiles: [UInt64] = []
    @ObservationIgnored private var recheckTimer: Timer?

    nonisolated private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif"]

    /// macOS writes this on every screenshot as it saves it.
    nonisolated private static let captureMarker = "com.apple.metadata:kMDItemIsScreenCapture"

    /// How often to look for a moved folder or a newly granted permission.
    private static let recheckInterval: TimeInterval = 5

    init(store: ClipStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    // MARK: - Lifecycle

    /// Start, stop or re-point to match the settings and the macOS screenshot
    /// location. Cheap when nothing has changed, so it is safe to call often.
    func sync() {
        guard settings.capturesScreenshots else {
            stop()
            status = .off
            return
        }

        startRecheckTimer()
        // A permission prompt may be on screen; don't stack another probe.
        guard !isProbing else { return }

        let desired = Self.resolvedFolder(settings: settings)
        if case .watching(let url) = status, url == desired, stream != nil { return }
        connect(to: desired)
    }

    func stop() {
        detach()
        folder = nil
        recheckTimer?.invalidate()
        recheckTimer = nil
    }

    private func startRecheckTimer() {
        guard recheckTimer == nil else { return }
        let timer = Timer(timeInterval: Self.recheckInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        recheckTimer = timer
    }

    /// Checks access off the main thread. The first touch of a protected
    /// folder is what makes macOS show its permission prompt, and that call
    /// blocks until the user answers — so nothing here may touch the folder
    /// on the main thread, not even to resolve its path.
    private func connect(to desired: URL) {
        detach()
        folder = desired
        // Re-checking a folder already known to be blocked keeps its status,
        // so the notch doesn't flicker every few seconds while it waits.
        if status.folder != desired { status = .connecting(desired) }
        isProbing = true

        DispatchQueue.global(qos: .utility).async {
            let access = Self.probe(desired)
            let path = Self.canonicalPath(of: desired)
            let dedicated = !Self.isSharedFolder(desired)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.finishConnecting(to: desired, access: access, path: path, dedicated: dedicated)
                }
            }
        }
    }

    private func finishConnecting(to desired: URL, access: Access, path: String, dedicated: Bool) {
        isProbing = false
        guard folder == desired, settings.capturesScreenshots else { return }
        folderPath = path
        isDedicatedFolder = dedicated

        switch access {
        case .readable:
            guard attach(to: desired) else {
                status = .folderMissing(desired)
                return
            }
            if status != .watching(desired) {
                NSLog("Cache: watching \(desired.path) for screenshots")
            }
            status = .watching(desired)
            catchUp(in: desired)
        case .denied:
            status = .needsAccess(desired)
        case .missing:
            status = .folderMissing(desired)
        }
    }

    // MARK: - FSEvents

    private func attach(to folder: URL) -> Bool {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<ScreenshotWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as NSArray
            var events: [(path: String, flags: FSEventStreamEventFlags)] = []
            events.reserveCapacity(count)
            for index in 0..<count {
                if let path = list[index] as? String { events.append((path, flags[index])) }
            }
            // The stream is scheduled on the main queue, so this is the main thread.
            MainActor.assumeIsolated { watcher.handle(events) }
        }

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagWatchRoot
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [folderPath] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.1,
            flags
        ) else { return false }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return false
        }
        self.stream = stream
        return true
    }

    private func detach() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
        attempts.removeAll()
    }

    private func handle(_ events: [(path: String, flags: FSEventStreamEventFlags)]) {
        guard let folder else { return }

        for event in events {
            let flags = Int(event.flags)

            // The folder itself was moved or deleted — look for it again.
            if flags & kFSEventStreamEventFlagRootChanged != 0 {
                connect(to: Self.resolvedFolder(settings: settings))
                return
            }
            // Events were coalesced; look at what arrived in the last minute.
            if flags & (kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped) != 0 {
                catchUp(in: folder, window: 60)
                continue
            }

            guard flags & kFSEventStreamEventFlagItemIsFile != 0,
                  (event.path as NSString).deletingLastPathComponent == folderPath
            else { continue }

            let name = (event.path as NSString).lastPathComponent
            // macOS writes a hidden temporary file first, then renames it into place.
            guard !name.hasPrefix("."),
                  Self.imageExtensions.contains((name as NSString).pathExtension.lowercased())
            else { continue }

            schedule(event.path, after: 0.25)
        }
    }

    /// Waits for a quiet moment on each file, so a picture still being
    /// written is never read half-finished.
    private func schedule(_ path: String, after delay: TimeInterval) {
        pending[path]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.inspect(path) }
        }
        pending[path] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Filing

    private struct FileFacts: Sendable {
        let identity: UInt64
        let created: Date
        let size: Int
        let isCapture: Bool
    }

    private func inspect(_ path: String) {
        pending[path] = nil
        guard folder != nil, settings.capturesScreenshots else { return }
        let dedicated = isDedicatedFolder

        DispatchQueue.global(qos: .utility).async {
            let facts = Self.facts(about: path)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.consider(path, facts: facts, dedicatedFolder: dedicated) }
            }
        }
    }

    private func consider(_ path: String, facts: FileFacts?, dedicatedFolder: Bool) {
        // Gone again — renamed away, or a temporary file.
        guard let facts else { attempts[path] = nil; return }
        guard !handledFiles.contains(facts.identity) else { return }

        let tries = attempts[path, default: 0]

        // In a folder people keep other things in, only a real screen capture
        // counts. The marker can land a beat after the file does, so look again.
        if !dedicatedFolder && !facts.isCapture {
            if tries < 3 { attempts[path] = tries + 1; schedule(path, after: 0.6) } else { attempts[path] = nil }
            return
        }
        if facts.size == 0 {
            if tries < 6 { attempts[path] = tries + 1; schedule(path, after: 0.4) } else { attempts[path] = nil }
            return
        }
        // Only fresh files. An old screenshot dragged in, or put back from the
        // Trash, is not a new capture.
        guard Date().timeIntervalSince(facts.created) < 600 else { return }

        attempts[path] = nil
        remember(facts.identity)
        file(URL(fileURLWithPath: path), identity: facts.identity)
    }

    private func file(_ url: URL, identity: UInt64) {
        let store = self.store
        let settings = self.settings
        Task {
            guard let stored = await ImageIngest.storeFile(at: url) else {
                // Unreadable right now — let a later event try again.
                self.forget(identity)
                return
            }
            store.insertImage(stored, source: .screenshot, originalPath: url.path)
            settings.lastScreenshotFiledAt = Date()
        }
    }

    /// Screenshots taken while Cache was not running: since the last one it
    /// filed, within the last few hours, at most a handful.
    private func catchUp(in folder: URL, window: TimeInterval = 6 * 3_600) {
        guard let lastFiled = settings.lastScreenshotFiledAt else {
            // First run: start from now rather than importing a backlog.
            settings.lastScreenshotFiledAt = Date()
            return
        }
        let since = max(lastFiled, Date().addingTimeInterval(-window))
        let dedicated = isDedicatedFolder

        DispatchQueue.global(qos: .utility).async {
            let found = Self.recentScreenshots(in: folder, since: since, dedicatedFolder: dedicated)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    for (url, identity) in found where !self.handledFiles.contains(identity) {
                        self.remember(identity)
                        self.file(url, identity: identity)
                    }
                }
            }
        }
    }

    private func remember(_ identity: UInt64) {
        handledFiles.append(identity)
        if handledFiles.count > 500 { handledFiles.removeFirst(handledFiles.count - 500) }
    }

    private func forget(_ identity: UInt64) {
        handledFiles.removeAll { $0 == identity }
    }

    // MARK: - File system (any thread)

    private enum Access { case readable, denied, missing }

    private nonisolated static func probe(_ folder: URL) -> Access {
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            return .readable
        } catch let error as NSError {
            let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
            let missing = error.code == NSFileReadNoSuchFileError
                || error.code == NSFileNoSuchFileError
                || (underlying?.domain == NSPOSIXErrorDomain
                    && (underlying?.code == Int(ENOENT) || underlying?.code == Int(ENOTDIR)))
            return missing ? .missing : .denied
        }
    }

    private nonisolated static func facts(about path: String) -> FileFacts? {
        var info = stat()
        guard stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        let created = Date(timeIntervalSince1970: TimeInterval(info.st_birthtimespec.tv_sec))
        let isCapture = getxattr(path, captureMarker, nil, 0, 0, 0) > 0
        return FileFacts(identity: UInt64(info.st_ino), created: created, size: Int(info.st_size), isCapture: isCapture)
    }

    private nonisolated static func recentScreenshots(
        in folder: URL,
        since: Date,
        dedicatedFolder: Bool
    ) -> [(URL, UInt64)] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }

        let recent = names.compactMap { name -> (URL, FileFacts)? in
            guard !name.hasPrefix("."), imageExtensions.contains((name as NSString).pathExtension.lowercased()) else { return nil }
            let url = folder.appendingPathComponent(name)
            guard let facts = facts(about: url.path),
                  facts.created > since, facts.size > 0,
                  dedicatedFolder || facts.isCapture
            else { return nil }
            return (url, facts)
        }

        // Oldest first, so the newest ends up at the front of the strip.
        return recent
            .sorted { $0.1.created < $1.1.created }
            .suffix(20)
            .map { ($0.0, $0.1.identity) }
    }

    /// The path FSEvents will report: symlinks resolved, `/tmp` spelled
    /// `/private/tmp`. `URL.resolvingSymlinksInPath()` does the opposite for
    /// `/private`, which is why this goes to `realpath` directly.
    private nonisolated static func canonicalPath(of url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    // MARK: - Locations

    /// The user's choice in Settings, or wherever macOS saves screenshots.
    static func resolvedFolder(settings: AppSettings) -> URL {
        if let custom = settings.screenshotFolderPath, !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true).standardizedFileURL
        }
        return systemScreenshotFolder()
    }

    /// `com.apple.screencapture location`, falling back to the Desktop, as
    /// macOS itself does. Read fresh each time — another process owns this
    /// preference, so a cached copy would miss the user changing it.
    nonisolated static func systemScreenshotFolder() -> URL {
        let domain = "com.apple.screencapture" as CFString
        CFPreferencesAppSynchronize(domain)
        if let location = CFPreferencesCopyAppValue("location" as CFString, domain) as? String,
           !location.trimmingCharacters(in: .whitespaces).isEmpty {
            return URL(fileURLWithPath: (location as NSString).expandingTildeInPath, isDirectory: true)
                .standardizedFileURL
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0].standardizedFileURL
    }

    /// A folder people keep other things in. Only proven screen captures are
    /// filed from these; from a folder of its own, every new picture counts.
    private nonisolated static func isSharedFolder(_ folder: URL) -> Bool {
        let fm = FileManager.default
        var shared = [URL(fileURLWithPath: NSHomeDirectory())]
        for directory in [FileManager.SearchPathDirectory.desktopDirectory, .downloadsDirectory, .documentDirectory, .picturesDirectory] {
            if let url = fm.urls(for: directory, in: .userDomainMask).first { shared.append(url) }
        }
        let path = canonicalPath(of: folder)
        return shared.contains { canonicalPath(of: $0) == path }
    }
}
