import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Everything a card, chip or button in the notch can do, in one place.
///
/// The views stay declarative and hold no references to windows or the
/// pasteboard; they call these.
@MainActor
final class ClipActions {
    let store: ClipStore
    let settings: AppSettings
    let watcher: ScreenshotWatcher
    private let monitor: ClipboardMonitor
    weak var controller: NotchController?

    init(store: ClipStore, monitor: ClipboardMonitor, settings: AppSettings, watcher: ScreenshotWatcher) {
        self.store = store
        self.monitor = monitor
        self.settings = settings
        self.watcher = watcher
    }

    // MARK: - Copying

    /// Puts the clip on the pasteboard, confirms it on the card, and gets out
    /// of the way so ⌘V lands in the app you were using.
    func copyAndClose(_ clip: Clip) {
        guard ClipPasteboard.write(clip) else { return }
        monitor.acknowledgeSelfCopy()
        controller?.confirmCopy(of: clip.id)
    }

    /// Plain text — "Copy Text" on a screenshot, or one value off a colour.
    func copyText(_ text: String, closing: Bool = true) {
        ClipPasteboard.writePlainText(text)
        monitor.acknowledgeSelfCopy()
        if closing { controller?.confirmCopy(of: nil) }
    }

    // MARK: - Changing clips

    func toggleStar(_ clip: Clip) {
        withAnimation(Theme.select) { store.toggleStar(clip) }
    }

    func delete(_ clip: Clip) {
        controller?.hideDetail()
        withAnimation(Theme.select) { store.delete(clip) }
    }

    func file(_ clip: Clip, in collection: String?) {
        withAnimation(Theme.select) { store.setCollection(collection, on: clip) }
    }

    /// Makes a collection, and files the clip into it when there is one.
    func createCollection(named rawName: String, adding clip: Clip? = nil) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if !settings.collections.contains(name) { settings.collections.append(name) }
        if let clip { file(clip, in: name) }
    }

    /// Removes the collection; its clips stay in the history.
    func removeCollection(_ name: String) {
        settings.collections.removeAll { $0 == name }
        store.removeCollection(name)
        if controller?.model.filter == .collection(name) { controller?.model.filter = .all }
    }

    // MARK: - Looking closer

    func preview(_ clip: Clip) {
        controller?.showDetail(for: clip)
    }

    func showInFinder(_ clip: Clip) {
        let path = clip.originalPath ?? clip.filePaths.first
        if let path, FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else if let stored = FileStorage.url(for: clip.imageFilename) {
            NSWorkspace.shared.activateFileViewerSelecting([stored])
        }
        controller?.close()
    }

    func canShowInFinder(_ clip: Clip) -> Bool {
        clip.clipKind == .image || clip.clipKind == .file
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
        controller?.close()
    }

    /// What a card becomes when it is dragged out: the picture as a file (with
    /// its real name, when it has one), files as files, links as links.
    func dragProvider(for clip: Clip) -> NSItemProvider {
        switch clip.clipKind {
        case .image:
            if let path = clip.originalPath, FileManager.default.fileExists(atPath: path),
               let provider = NSItemProvider(contentsOf: URL(fileURLWithPath: path)) {
                return provider
            }
            if let url = FileStorage.url(for: clip.imageFilename), let provider = NSItemProvider(contentsOf: url) {
                return provider
            }
        case .file:
            if let path = clip.filePaths.first, let provider = NSItemProvider(contentsOf: URL(fileURLWithPath: path)) {
                return provider
            }
        case .link:
            if let url = clip.linkURL { return NSItemProvider(object: url as NSURL) }
        case .text, .code, .color:
            break
        }
        return NSItemProvider(object: (clip.text ?? "") as NSString)
    }

    /// Files, pictures and text dropped onto the open notch become clips.
    func importDrops(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in self.importDropped(url) }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                accepted = true
                _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                    guard let text = value as? String, !text.isEmpty else { return }
                    Task { @MainActor in
                        self.store.insertText(text, kind: ClipKind.detect(text: text), source: .drop)
                    }
                }
            }
        }
        return accepted
    }

    private func importDropped(_ url: URL) {
        guard url.isFileURL else {
            store.insertText(url.absoluteString, kind: .link, source: .drop)
            return
        }
        let isImage = UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
        guard isImage else {
            store.insertText(url.path, kind: .file, source: .drop)
            return
        }
        let store = self.store
        Task {
            guard let stored = await ImageIngest.storeFile(at: url) else { return }
            store.insertImage(stored, source: .drop, originalPath: url.path)
        }
    }

    // MARK: - The panel

    func close() { controller?.close() }
    func focusSearch() { controller?.focusSearch() }
    /// Gives the panel the keyboard without moving focus to the search field.
    func takeKeyboard() { controller?.takeKeyboard() }
    func openSettings() { controller?.openSettingsWindow() }

    func togglePause() {
        settings.isPaused.toggle()
    }

    func registerStrip(_ scrollView: NSScrollView) {
        controller?.registerStrip(scrollView)
    }

    func scrollStripToStart() {
        controller?.scrollStripToStart()
    }

    // MARK: - Screenshots

    func turnOnScreenshots() {
        settings.capturesScreenshots = true
    }

    /// Straight to the pane where the folder permission lives.
    func openPrivacySettings() {
        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
        if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
        controller?.close()
    }
}
