import Foundation

/// What the chip row is showing.
enum ClipFilter: Hashable {
    case all
    case screenshots
    case kind(ClipKind)
    case collection(String)
}

/// One pass over the history that yields both the visible clips and every
/// chip's count.
///
/// Built once per render of the strip rather than as several computed
/// properties, each of which would walk the whole history again — that
/// repetition, multiplied by every hover, is what made the old strip lag.
struct ClipIndex {
    private(set) var visible: [Clip] = []
    private(set) var total = 0
    private(set) var screenshots = 0
    private(set) var kinds: [ClipKind: Int] = [:]
    private(set) var collections: [String: Int] = [:]

    init(clips: [Clip], filter: ClipFilter, starredOnly: Bool, query: String) {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        visible.reserveCapacity(clips.count)

        for clip in clips {
            let kind = clip.clipKind
            let isScreenshot = clip.isScreenshot

            total += 1
            kinds[kind, default: 0] += 1
            if isScreenshot { screenshots += 1 }
            if let category = clip.category { collections[category, default: 0] += 1 }

            if starredOnly && !clip.isPinned { continue }

            switch filter {
            case .all: break
            case .screenshots: if !isScreenshot { continue }
            case .kind(let wanted): if kind != wanted { continue }
            case .collection(let name): if clip.category != name { continue }
            }

            if !needle.isEmpty && !clip.matches(needle) { continue }
            visible.append(clip)
        }
    }

    func count(for filter: ClipFilter) -> Int {
        switch filter {
        case .all: total
        case .screenshots: screenshots
        case .kind(let kind): kinds[kind] ?? 0
        case .collection(let name): collections[name] ?? 0
        }
    }
}
