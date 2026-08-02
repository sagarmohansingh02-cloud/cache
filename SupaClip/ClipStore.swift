import Foundation
import SwiftData

/// Thin wrapper over SwiftData for the writes the monitor performs.
///
/// Reads in the UI go through `@Query` instead — that's what gives us automatic
/// list updates. This type exists so the polling engine never has to know
/// anything about fetch descriptors or pruning rules.
@MainActor
final class ClipStore {
    /// Hard cap from the performance budget. Older unpinned clips are deleted on insert.
    static let maxHistory = 2000

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Newest clip, or nil on an empty store. Used for deduplication.
    /// Fetch limit 1 — never pull the whole table just to compare one string.
    func mostRecent() -> Clip? {
        var descriptor = FetchDescriptor<Clip>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Insert a text clip, skipping exact repeats of the most recent one.
    /// Returns false when the clip was deduplicated away.
    @discardableResult
    func insertText(
        _ text: String,
        sourceAppName: String?,
        sourceAppBundleID: String?
    ) -> Bool {
        // Deduplicate: re-copying the same string shouldn't stack up rows.
        if let latest = mostRecent(), latest.kind == "text", latest.text == text {
            return false
        }

        let clip = Clip(
            kind: "text",
            text: text,
            sourceAppName: sourceAppName,
            sourceAppBundleID: sourceAppBundleID
        )
        context.insert(clip)

        prune()
        save()
        return true
    }

    /// Delete everything past `maxHistory`, oldest first. Pinned clips are exempt.
    ///
    /// Deliberately built on `fetchCount` + `fetchLimit` rather than
    /// `fetchOffset`. An offset-only descriptor does **not** reliably skip rows
    /// here — it came back holding the row we had just inserted, so pruning
    /// deleted every clip the moment it was saved. Counting first and then
    /// fetching only the overflow, oldest-first, avoids the trap entirely and
    /// still never loads the full history.
    private func prune() {
        let unpinned = FetchDescriptor<Clip>(predicate: #Predicate { $0.isPinned == false })
        guard let total = try? context.fetchCount(unpinned), total > Self.maxHistory else {
            return
        }

        var descriptor = FetchDescriptor<Clip>(
            predicate: #Predicate { $0.isPinned == false },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]   // oldest first
        )
        descriptor.fetchLimit = total - Self.maxHistory

        guard let overflow = try? context.fetch(descriptor) else { return }
        for clip in overflow {
            // Phase B: also delete the clip's image + thumbnail files here,
            // or Application Support grows forever.
            context.delete(clip)
        }
    }

    func delete(_ clip: Clip) {
        context.delete(clip)
        save()
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
