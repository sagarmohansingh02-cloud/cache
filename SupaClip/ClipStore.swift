import AppKit
import Foundation
import SwiftData

/// Thin wrapper over SwiftData for the writes the monitor and UI perform.
///
/// Reads in the UI go through `@Query` instead — that's what gives us automatic
/// list updates. This type exists so the polling engine never has to know
/// anything about fetch descriptors, pruning rules or file cleanup.
@MainActor
final class ClipStore {
    private let context: ModelContext
    private let settings: AppSettings

    init(context: ModelContext, settings: AppSettings = .shared) {
        self.context = context
        self.settings = settings
    }

    // MARK: - Reads

    /// Newest clip, or nil on an empty store. Used for deduplication.
    /// Fetch limit 1 — never pull the whole table just to compare one string.
    func mostRecent() -> Clip? {
        var descriptor = FetchDescriptor<Clip>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Inserts

    /// Insert a text-shaped clip (text, link, code, colour, or a file path),
    /// skipping exact repeats of the most recent one.
    /// Returns false when the clip was deduplicated away.
    @discardableResult
    func insertText(
        _ text: String,
        kind: ClipKind = .text,
        sourceAppName: String?,
        sourceAppBundleID: String?
    ) -> Bool {
        // Deduplicate: re-copying the same string shouldn't stack up rows.
        if let latest = mostRecent(), latest.text == text, latest.kind == kind.rawValue {
            return false
        }

        let clip = Clip(
            kind: kind.rawValue,
            text: text,
            sourceAppName: sourceAppName,
            sourceAppBundleID: sourceAppBundleID
        )
        context.insert(clip)

        prune()
        save()
        return true
    }

    /// Insert an image clip. The bytes go to disk; only filenames are stored.
    /// No dedupe — two screenshots that look alike are still two clips.
    @discardableResult
    func insertImage(
        _ image: NSImage,
        sourceAppName: String?,
        sourceAppBundleID: String?
    ) -> Bool {
        let filenames: (image: String, thumbnail: String)
        do {
            filenames = try FileStorage.writeImage(image)
        } catch {
            NSLog("SupaClip: could not write image — \(error.localizedDescription)")
            return false
        }

        let clip = Clip(
            kind: ClipKind.image.rawValue,
            imageFilename: filenames.image,
            thumbnailFilename: filenames.thumbnail,
            sourceAppName: sourceAppName,
            sourceAppBundleID: sourceAppBundleID
        )
        context.insert(clip)

        prune()
        save()
        return true
    }

    // MARK: - Mutations

    func togglePin(_ clip: Clip) {
        clip.isPinned.toggle()
        save()
    }

    /// Assign a clip to a user-created category, or pass nil to move it back to
    /// plain History. Categories are just names on clips — there's no separate
    /// table, so a category stops existing when its last clip does.
    func setCategory(_ category: String?, on clip: Clip) {
        let trimmed = category?.trimmingCharacters(in: .whitespacesAndNewlines)
        clip.category = (trimmed?.isEmpty == false) ? trimmed : nil
        save()
    }

    /// Deleting a row must delete its files too, or Application Support grows
    /// forever.
    func delete(_ clip: Clip) {
        FileStorage.deleteFiles(
            imageFilename: clip.imageFilename,
            thumbnailFilename: clip.thumbnailFilename
        )
        context.delete(clip)
        save()
    }

    /// Wipe everything, pinned clips included, and empty the Clips folder.
    func clearAll() {
        do {
            try context.delete(model: Clip.self)
        } catch {
            NSLog("SupaClip: clear all failed — \(error.localizedDescription)")
            return
        }

        // Remove every file rather than walking rows we've already deleted.
        let directory = FileStorage.clipsDirectory
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) {
            for url in contents {
                try? FileManager.default.removeItem(at: url)
            }
        }

        save()
    }

    // MARK: - Pruning

    /// Delete everything past the user's history limit, oldest first.
    /// Pinned clips are exempt.
    ///
    /// Deliberately built on `fetchCount` + `fetchLimit` rather than
    /// `fetchOffset`. An offset-only descriptor does **not** reliably skip rows
    /// here — it came back holding the row we had just inserted, so pruning
    /// deleted every clip the moment it was saved. Counting first and then
    /// fetching only the overflow, oldest-first, avoids the trap entirely and
    /// still never loads the full history.
    private func prune() {
        let limit = min(settings.historyLimit, AppSettings.maxHistoryLimit)

        let unpinned = FetchDescriptor<Clip>(predicate: #Predicate { $0.isPinned == false })
        guard let total = try? context.fetchCount(unpinned), total > limit else { return }

        var descriptor = FetchDescriptor<Clip>(
            predicate: #Predicate { $0.isPinned == false },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]   // oldest first
        )
        descriptor.fetchLimit = total - limit

        guard let overflow = try? context.fetch(descriptor) else { return }
        for clip in overflow {
            FileStorage.deleteFiles(
                imageFilename: clip.imageFilename,
                thumbnailFilename: clip.thumbnailFilename
            )
            context.delete(clip)
        }
    }

    private func save() {
        do {
            try context.save()
        } catch {
            // A failed save shouldn't take the app down — the next capture retries.
            NSLog("SupaClip: save failed — \(error.localizedDescription)")
        }
    }
}
