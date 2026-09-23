import AppKit
import Observation

/// Everything the notch UI shows that isn't in the database.
///
/// One instance for the life of the app. The notch's SwiftUI tree is built
/// once and kept, and this is what changes underneath it — which is why
/// opening the panel costs a state change, not a rebuild of every view and a
/// fresh database fetch on each hover, as it used to.
@MainActor
@Observable
final class NotchModel {
    enum Phase: Equatable {
        case closed
        /// The notch widened for a moment to confirm a copy.
        case peek
        case open
    }

    var phase: Phase = .closed
    var metrics: NotchMetrics
    var peek: Peek?

    var query = ""
    var filter: ClipFilter = .all
    var starredOnly = false

    /// The card the keyboard is on.
    var selection: UUID?
    /// The card that was just copied, showing its confirmation.
    var copiedClipID: UUID?
    /// ⌘ is held: the first nine cards show their ⌘1–9 shortcut.
    var showsShortcutHints = false
    /// Frozen when the panel opens, so every card's "5 min ago" agrees.
    var now = Date()

    /// Bumped on each open, so the strip goes back to the newest clip.
    var openCount = 0
    /// Bumped to put the cursor in the search field.
    var searchFocusRequests = 0
    var isNamingCollection = false
    /// A card waiting to be filed into the collection being named.
    @ObservationIgnored var clipAwaitingCollection: Clip?

    /// Keyboard commands from the panel, acted on by the strip, which is the
    /// part that knows which clips are visible and in what order.
    private(set) var command: Command?
    private(set) var commandCount = 0

    enum Command: Equatable {
        case move(Int)
        case copySelection
        case previewSelection
        case deleteSelection
        case copyNumber(Int)
    }

    func send(_ command: Command) {
        self.command = command
        commandCount += 1
    }

    var silhouette: NotchSilhouette {
        switch phase {
        case .closed: .closed(metrics)
        case .peek: .peek(metrics)
        case .open: .open(metrics)
        }
    }

    init(metrics: NotchMetrics) {
        self.metrics = metrics
    }

    /// Back to a clean slate after the panel closes.
    func resetTransientState() {
        query = ""
        selection = nil
        showsShortcutHints = false
        isNamingCollection = false
        clipAwaitingCollection = nil
    }
}

/// What the notch shows while confirming a copy.
struct Peek: Equatable {
    let clipID: UUID
    let kind: ClipKind
    let isScreenshot: Bool
    let colorText: String?
    let thumbnailKey: String?
    let thumbnailCandidates: [URL]

    @MainActor
    init(_ clip: Clip) {
        clipID = clip.id
        kind = clip.clipKind
        isScreenshot = clip.isScreenshot
        colorText = clip.clipKind == .color ? clip.text : nil
        thumbnailKey = ThumbnailLoader.cardKey(for: clip)
        thumbnailCandidates = ThumbnailLoader.cardCandidates(for: clip)
    }

    /// Short enough for the notch's right ear.
    var label: String {
        isScreenshot ? "Saved" : "Copied"
    }
}
