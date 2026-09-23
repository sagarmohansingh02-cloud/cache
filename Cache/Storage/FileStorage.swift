import Foundation

/// Where Cache keeps things on disk.
///
/// The database never holds image bytes — it stores filenames, and the images
/// live in `Application Support/<BundleID>/Clips/`. That keeps the store small
/// and means the strip can render thumbnails without ever loading a
/// full-resolution screenshot into memory.
///
/// Safe to use from any thread: nothing here touches UI state.
enum FileStorage {
    static let defaultBundleID = "com.sagarmohansingh.cache"

    /// `~/Library/Application Support/<BundleID>/`, created on first use.
    /// A constant, so the directory is resolved once rather than on every
    /// thumbnail the strip draws.
    static let containerDirectory: URL = {
        let directory = applicationSupport
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? defaultBundleID, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    static let clipsDirectory: URL = {
        let directory = containerDirectory.appendingPathComponent("Clips", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    static let storeName = "Cache.store"

    static var storeURL: URL { containerDirectory.appendingPathComponent(storeName) }

    static func url(for filename: String?) -> URL? {
        guard let filename, !filename.isEmpty else { return nil }
        return clipsDirectory.appendingPathComponent(filename)
    }

    private static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Recovery

    /// Moves a store that will not open out of the way, with its SQLite
    /// sidecars, so the app can start with a fresh one instead of crashing on
    /// every launch. Nothing is deleted — the old files stay beside the new
    /// store, named with the date they were set aside.
    static func setAsideUnreadableStore() {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        for suffix in ["", "-shm", "-wal"] {
            let source = containerDirectory.appendingPathComponent(storeName + suffix)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let target = containerDirectory.appendingPathComponent("Unreadable-\(stamp)-\(storeName)\(suffix)")
            try? FileManager.default.moveItem(at: source, to: target)
        }
    }

    // MARK: - Migration from SupaClip

    /// The app was called SupaClip while it was being built, and its data
    /// folder and preferences were keyed to that name. Carry an install across
    /// once. Must run before anything touches `containerDirectory` or
    /// `UserDefaults`, because reading either creates the empty replacement.
    static func migrateLegacyInstallIfNeeded() {
        let legacyBundleID = "com.sagarmohansingh.supaclip"
        let currentBundleID = Bundle.main.bundleIdentifier ?? defaultBundleID
        guard currentBundleID != legacyBundleID else { return }

        let fm = FileManager.default
        let legacy = applicationSupport.appendingPathComponent(legacyBundleID, isDirectory: true)
        let current = applicationSupport.appendingPathComponent(currentBundleID, isDirectory: true)

        if fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: current.path),
           (try? fm.moveItem(at: legacy, to: current)) != nil {
            // SQLite keeps unflushed writes in -wal; all three files travel together.
            for suffix in ["", "-shm", "-wal"] {
                let old = current.appendingPathComponent("SupaClip.store" + suffix)
                let new = current.appendingPathComponent(storeName + suffix)
                if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) {
                    try? fm.moveItem(at: old, to: new)
                }
            }
            NSLog("Cache: moved existing data over from \(legacyBundleID)")
        }

        let defaults = UserDefaults.standard
        if let old = defaults.persistentDomain(forName: legacyBundleID), !old.isEmpty {
            var merged = defaults.persistentDomain(forName: currentBundleID) ?? [:]
            var carried = 0
            for (key, value) in old where merged[key] == nil {
                merged[key] = value
                carried += 1
            }
            if carried > 0 { defaults.setPersistentDomain(merged, forName: currentBundleID) }
        }
    }

    // MARK: - Deleting

    /// Deleting a clip deletes its files too, or Application Support grows
    /// forever. Safe with nils and with files that are already gone.
    static func deleteFiles(of clip: Clip) {
        for url in [url(for: clip.imageFilename), url(for: clip.thumbnailFilename)].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Clear History moves pictures to the Trash rather than destroying them —
    /// a bulk, unattended action should cost a trip to the Finder, not the
    /// pictures. Thumbnails are derived and simply removed.
    static func trashFiles(of clip: Clip) {
        if let image = url(for: clip.imageFilename), FileManager.default.fileExists(atPath: image.path) {
            try? FileManager.default.trashItem(at: image, resultingItemURL: nil)
        }
        if let thumbnail = url(for: clip.thumbnailFilename) {
            try? FileManager.default.removeItem(at: thumbnail)
        }
    }
}
