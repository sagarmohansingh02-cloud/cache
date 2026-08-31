import Foundation

/// How the history is ordered.
enum SortOrder: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case mostUsed
    case recentlyUsed
    case alphabetical
    case manual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newest:        "Newest first"
        case .oldest:        "Oldest first"
        case .mostUsed:      "Most used"
        case .recentlyUsed:  "Recently used"
        case .alphabetical:  "Alphabetical"
        case .manual:        "Manual"
        }
    }
}

/// How rows are laid out.
enum ViewMode: String, CaseIterable, Identifiable {
    case list
    case grid
    case board

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .list:  "List"
        case .grid:  "Grid"
        case .board: "Board"
        }
    }

    var symbolName: String {
        switch self {
        case .list:  "list.bullet"
        case .grid:  "square.grid.2x2"
        case .board: "rectangle.split.3x1"
        }
    }
}

extension Array where Element == Clip {
    /// Sorting happens in memory rather than in the fetch descriptor because
    /// several of these orders can't be expressed as a `SortDescriptor` on a
    /// single stored property — "alphabetical" has to fall back through title,
    /// text and OCR text to find something to compare.
    func sorted(by order: SortOrder) -> [Clip] {
        switch order {
        case .newest:
            return sorted { $0.createdAt > $1.createdAt }

        case .oldest:
            return sorted { $0.createdAt < $1.createdAt }

        case .mostUsed:
            // Ties break on recency, so an untouched history still reads sensibly.
            return sorted {
                $0.useCount == $1.useCount
                    ? $0.createdAt > $1.createdAt
                    : $0.useCount > $1.useCount
            }

        case .recentlyUsed:
            return sorted {
                // Never-used clips sort below used ones, by creation date.
                ($0.lastUsedAt ?? .distantPast) == ($1.lastUsedAt ?? .distantPast)
                    ? $0.createdAt > $1.createdAt
                    : ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast)
            }

        case .alphabetical:
            return sorted {
                $0.sortableText.localizedCaseInsensitiveCompare($1.sortableText) == .orderedAscending
            }

        case .manual:
            // Anything never dragged keeps its place at the end, newest first.
            return sorted {
                let left = $0.manualOrder ?? Int.max
                let right = $1.manualOrder ?? Int.max
                return left == right ? $0.createdAt > $1.createdAt : left < right
            }
        }
    }
}

extension Clip {
    /// Best available string for alphabetical sorting and titles.
    var sortableText: String {
        if let title, !title.isEmpty { return title }
        if let text, !text.isEmpty { return text }
        if let ocrText, !ocrText.isEmpty { return ocrText }
        return ""
    }
}
