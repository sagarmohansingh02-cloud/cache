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
    private let ocr: OCRService

    init(context: ModelContext, settings: AppSettings = .shared) {
        self.context = context
        self.settings = settings
        self.ocr = OCRService(context: context)
    }

    /// Catch up any images captured before OCR existed.
    func recognizeTextInOlderImages() {
        ocr.backfill()
    }

    /// File screenshots captured before the Screenshots collection existed, so
    /// the chip shows the full history rather than only new captures.
    func backfillScreenshotCollection() {
        let name = ScreenshotWatcher.collectionName
        let descriptor = FetchDescriptor<Clip>(
            predicate: #Predicate { $0.sourceAppName == "Screenshot" && $0.category == nil }
        )

        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return }

        for clip in pending {
            clip.category = name
        }
        save()
        NSLog("SupaClip: filed \(pending.count) existing screenshot(s) into \(name)")
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
        CopyTray.shared.add(clip)
        return true
    }

    /// Insert an image clip. The bytes go to disk; only filenames are stored.
    /// No dedupe — two screenshots that look alike are still two clips.
    @discardableResult
    func insertImage(
        _ image: NSImage,
        sourceAppName: String?,
        sourceAppBundleID: String?,
        category: String? = nil
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
            sourceAppBundleID: sourceAppBundleID,
            category: category
        )
        context.insert(clip)

        prune()
        save()

        CopyTray.shared.add(clip)

        // Fire-and-forget: the clip is already saved and visible: OCR only adds
        // searchable text to it later.
        ocr.enqueue(clip)
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

    /// Replace a clip's text after the user edits it.
    func updateText(_ text: String, on clip: Clip) {
        clip.text = text
        // Re-detect: editing "hello" into "#FF0000" should make it a colour.
        clip.kind = ClipKind.detect(text: text).rawValue
        save()
    }

    /// Save an edit made in the detail card.
    ///
    /// For an image that means rewriting the recognised text, which is also the
    /// search index — so trimming a full-screen screenshot down to the two lines
    /// that mattered makes it *easier* to find later, not harder. For everything
    /// else it edits the clip's own text.
    func updateEditedText(_ text: String, on clip: Clip) {
        if ClipKind(rawValue: clip.kind) == .image {
            clip.ocrText = text
            save()
        } else {
            updateText(text, on: clip)
        }
    }

    /// A user-supplied name shown instead of the clip's contents.
    func updateTitle(_ title: String?, on clip: Clip) {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        clip.title = (trimmed?.isEmpty == false) ? trimmed : nil
        save()
    }

    /// Called when a clip is pasted back, so "most used" and "recently used"
    /// sorting have something to sort on.
    func recordUse(of clip: Clip) {
        clip.useCount += 1
        clip.lastUsedAt = Date()
        save()
    }

    func setReminder(_ date: Date?, on clip: Clip) {
        clip.reminderAt = date
        save()
    }

    /// Persist a hand-arranged order. Only the clips passed in are renumbered.
    func applyManualOrder(_ clips: [Clip]) {
        for (index, clip) in clips.enumerated() {
            clip.manualOrder = index
        }
        save()
    }

    func deleteMany(_ clips: [Clip]) {
        for clip in clips {
            FileStorage.deleteFiles(
                imageFilename: clip.imageFilename,
                thumbnailFilename: clip.thumbnailFilename
            )
            context.delete(clip)
        }
        save()
    }

    /// Deleting a row must delete its files too, or Application Support grows
    /// forever.
    func delete(_ clip: Clip) {
        CopyTray.shared.remove(clip)
        FileStorage.deleteFiles(
            imageFilename: clip.imageFilename,
            thumbnailFilename: clip.thumbnailFilename
        )
        context.delete(clip)
        save()
    }

    /// Wipe everything, pinned clips included, and empty the Clips folder.
    ///
    /// Deliberately deletes row by row rather than with
    /// `context.delete(model: Clip.self)`. That batch form operates on the store
    /// underneath the context, so the objects the context already has registered
    /// — which is exactly what `@Query` is showing — are never told they died.
    /// The database emptied while the list carried on displaying the old clips,
    /// which is why Clear All looked like it did nothing. Worse, the tray went on
    /// holding deleted models.
    func clearAll() {
        // The shelf points at rows that are about to stop existing.
        CopyTray.shared.clear()

        let all = (try? context.fetch(FetchDescriptor<Clip>())) ?? []
        for clip in all {
            context.delete(clip)
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

        // Thumbnails are cached in memory by filename; without this the list
        // would still render pictures whose files are gone.
        ThumbnailCache.clear()

        save()
        NSLog("SupaClip: cleared \(all.count) clip(s)")
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
