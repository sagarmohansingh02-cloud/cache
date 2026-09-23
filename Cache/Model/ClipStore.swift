import AppKit
import Foundation
import SwiftData

/// Every write to the history goes through here, on the main actor.
///
/// Reads in the UI use `@Query`, which is what keeps the strip live. This type
/// exists so capture never has to know about fetch descriptors, pruning rules
/// or file cleanup — and there is exactly one of it, created at launch.
@MainActor
final class ClipStore {
    let context: ModelContext
    private let settings: AppSettings
    private let ocr: OCRService

    /// Fired when something new lands — or when a re-copy brings an old clip
    /// back to the front. Drives the notch's copy confirmation.
    var onCapture: ((Clip) -> Void)?

    init(context: ModelContext, settings: AppSettings) {
        self.context = context
        self.settings = settings
        self.ocr = OCRService(context: context)
    }

    // MARK: - Inserting

    /// Text, links, code, colours and file paths.
    ///
    /// Copying something already in the history brings that clip back to the
    /// front instead of adding a duplicate — the history stays a list of
    /// distinct things, most recent first.
    @discardableResult
    func insertText(_ text: String, kind: ClipKind, source: SourceApp?) -> Clip {
        if let existing = existingClip(withText: text, kind: kind) {
            existing.createdAt = Date()
            if let source {
                existing.sourceAppName = source.name
                existing.sourceAppBundleID = source.bundleID
            }
            save()
            onCapture?(existing)
            return existing
        }

        let clip = Clip(kind: kind, text: text, sourceAppName: source?.name, sourceAppBundleID: source?.bundleID)
        context.insert(clip)
        prune()
        save()
        onCapture?(clip)
        return clip
    }

    /// An image whose files `ImageIngest` has already written. Never
    /// deduplicated — two screenshots that look alike are still two moments.
    @discardableResult
    func insertImage(_ stored: StoredImage, source: SourceApp?, originalPath: String? = nil) -> Clip {
        let clip = Clip(kind: .image, sourceAppName: source?.name, sourceAppBundleID: source?.bundleID)
        clip.imageFilename = stored.imageFilename
        clip.thumbnailFilename = stored.thumbnailFilename
        clip.pixelWidth = stored.pixelWidth
        clip.pixelHeight = stored.pixelHeight
        clip.byteSize = stored.byteSize
        clip.originalPath = originalPath
        context.insert(clip)
        prune()
        save()
        onCapture?(clip)

        // Fire and forget: the clip is already saved and on screen.
        ocr.enqueue(clip)
        return clip
    }

    private func existingClip(withText text: String, kind: ClipKind) -> Clip? {
        let kindValue = kind.rawValue
        var descriptor = FetchDescriptor<Clip>(predicate: #Predicate { $0.kind == kindValue && $0.text == text })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Changing

    func toggleStar(_ clip: Clip) {
        clip.isPinned.toggle()
        save()
    }

    /// File a clip into a collection, or pass nil to take it out.
    func setCollection(_ name: String?, on clip: Clip) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        clip.category = (trimmed?.isEmpty == false) ? trimmed : nil
        save()
    }

    /// Deleting a collection only removes the label; its clips stay in the history.
    func removeCollection(_ name: String) {
        let descriptor = FetchDescriptor<Clip>(predicate: #Predicate { $0.category == name })
        for clip in (try? context.fetch(descriptor)) ?? [] {
            clip.category = nil
        }
        save()
    }

    func delete(_ clip: Clip) {
        FileStorage.deleteFiles(of: clip)
        context.delete(clip)
        save()
    }

    /// How many clips Clear History would remove. Counted, never fetched.
    func unstarredCount() -> Int {
        let descriptor = FetchDescriptor<Clip>(predicate: #Predicate { $0.isPinned == false })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    func hasAnyClips() -> Bool {
        ((try? context.fetchCount(FetchDescriptor<Clip>())) ?? 0) > 0
    }

    /// Apps that clips have come from lately — offered when choosing apps to ignore.
    func recentSources(limit: Int = 400) -> [SourceApp] {
        var descriptor = FetchDescriptor<Clip>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = limit

        var seen: Set<String> = [SourceApp.screenshot.bundleID ?? "", Bundle.main.bundleIdentifier ?? ""]
        var apps: [SourceApp] = []
        for clip in (try? context.fetch(descriptor)) ?? [] {
            guard let bundleID = clip.sourceAppBundleID, !seen.contains(bundleID) else { continue }
            seen.insert(bundleID)
            apps.append(SourceApp(name: clip.sourceAppName, bundleID: bundleID))
        }
        return apps.sorted { ($0.name ?? "").localizedCaseInsensitiveCompare($1.name ?? "") == .orderedAscending }
    }

    /// Every unstarred clip goes, with its pictures moved to the Trash.
    /// Starring is the user saying "keep this", and a bulk clear does not
    /// get to override that.
    ///
    /// Row by row on purpose: `context.delete(model:)` works on the store
    /// underneath the context, so `@Query` never hears that its rows died and
    /// the strip goes on showing them.
    func clearHistory() {
        let descriptor = FetchDescriptor<Clip>(predicate: #Predicate { $0.isPinned == false })
        let doomed = (try? context.fetch(descriptor)) ?? []
        for clip in doomed {
            FileStorage.trashFiles(of: clip)
            context.delete(clip)
        }
        ThumbnailLoader.shared.removeAll()
        save()
        NSLog("Cache: cleared \(doomed.count) clip(s)")
    }

    // MARK: - Launch maintenance

    /// Catch older history up with this version, in the background.
    func performLaunchMaintenance() {
        releaseLegacyScreenshotCollection()
        ocr.backfill()
        refreshOldImages()
    }

    /// 1.x filed every screenshot into a "Screenshots" collection. Screenshots
    /// are now their own filter, so that label would only duplicate it.
    private func releaseLegacyScreenshotCollection() {
        let name = "Screenshots"
        let descriptor = FetchDescriptor<Clip>(predicate: #Predicate { $0.category == name })
        let filed = ((try? context.fetch(descriptor)) ?? []).filter(\.isScreenshot)
        guard !filed.isEmpty else { return }
        filed.forEach { $0.category = nil }
        save()
    }

    /// Images stored by 1.x have small thumbnails and no recorded size.
    /// Rebuild both, one at a time.
    private func refreshOldImages() {
        let descriptor = FetchDescriptor<Clip>(predicate: #Predicate { $0.kind == "image" && $0.pixelWidth == nil })
        guard let stale = try? context.fetch(descriptor), !stale.isEmpty else { return }

        let jobs = stale.compactMap { clip -> (PersistentIdentifier, String, String?)? in
            guard let image = clip.imageFilename else { return nil }
            return (clip.persistentModelID, image, clip.thumbnailFilename)
        }

        Task {
            for (identifier, image, thumbnail) in jobs {
                guard let stored = await ImageIngest.refreshMetadata(imageFilename: image, thumbnailFilename: thumbnail),
                      let clip = context.model(for: identifier) as? Clip, !clip.isDeleted
                else { continue }
                clip.thumbnailFilename = stored.thumbnailFilename
                clip.pixelWidth = stored.pixelWidth
                clip.pixelHeight = stored.pixelHeight
                clip.byteSize = stored.byteSize
                save()
            }
        }
    }

    // MARK: - Housekeeping

    /// Oldest unstarred clips past the history limit go, files included.
    ///
    /// Counts first and fetches only the overflow, oldest first — never the
    /// whole history. (`fetchOffset` alone does not reliably skip rows here; it
    /// once handed back the clip that had just been inserted.)
    private func prune() {
        let limit = min(settings.historyLimit, AppSettings.maxHistoryLimit)
        let unstarred = FetchDescriptor<Clip>(predicate: #Predicate { $0.isPinned == false })
        guard let total = try? context.fetchCount(unstarred), total > limit else { return }

        var descriptor = FetchDescriptor<Clip>(
            predicate: #Predicate { $0.isPinned == false },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = total - limit
        for clip in (try? context.fetch(descriptor)) ?? [] {
            FileStorage.deleteFiles(of: clip)
            context.delete(clip)
        }
    }

    private func save() {
        do {
            try context.save()
        } catch {
            // A failed save shouldn't take the app down; the next write retries.
            NSLog("Cache: save failed — \(error.localizedDescription)")
        }
    }
}
