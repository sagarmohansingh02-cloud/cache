import AppKit
import SwiftData
import SwiftUI

/// Owns the notch: its window, the zones that open it, and the rules for when
/// it opens and closes.
///
/// The SwiftUI content is built once, when the app starts, and kept. Opening
/// is a state change the content animates; the window itself is never resized
/// while it is on screen (that aborts the process inside AppKit's layout
/// pass), only moved while hidden when the pointer changes display.
@MainActor
final class NotchController {
    let model: NotchModel
    let actions: ClipActions

    private let settings: AppSettings
    private let watcher: ScreenshotWatcher
    private let container: ModelContainer

    private var panel: NotchPanel?
    private var hotZones: [HotZoneWindow] = []
    private let scroller = StripScroller()
    private let detail = DetailWindowController()

    /// Watches the pointer only while the panel is open. Nothing runs on
    /// mouse movement while it is closed.
    private var pointerMonitors: [Any] = []
    private var pointerHasBeenInside = false

    private var pendingOpen: DispatchWorkItem?
    private var pendingClose: DispatchWorkItem?
    private var peekTimer: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    /// Set by the app so the gear can reach the Settings window.
    var showSettings: () -> Void = {}

    /// How long the pointer must rest in the notch before it opens. Long
    /// enough that sweeping across the menu bar doesn't trigger it, short
    /// enough to feel immediate.
    private static let hoverIntent: TimeInterval = 0.07
    private static let peekDuration: TimeInterval = 1.6

    init(container: ModelContainer, store: ClipStore, monitor: ClipboardMonitor, watcher: ScreenshotWatcher, settings: AppSettings) {
        let screen = NotchGeometry.screenWithPointer() ?? NSScreen.screens[0]
        self.model = NotchModel(metrics: NotchMetrics(screen: screen))
        self.actions = ClipActions(store: store, monitor: monitor, settings: settings, watcher: watcher)
        self.settings = settings
        self.watcher = watcher
        self.container = container
        actions.controller = self
    }

    func start() {
        makePanel()
        rebuildHotZones()

        settings.onOpensOnHoverChanged = { [weak self] in self?.rebuildHotZones() }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        })
    }

    private func makePanel() {
        let panel = NotchPanel(contentRect: model.metrics.panelFrame)
        panel.acceptsMouseMovedEvents = true
        panel.contentView = PanelHostingView(
            rootView: NotchRootView(model: model, actions: actions, watcher: watcher, settings: settings)
                .modelContainer(container)
        )
        panel.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
        panel.shortcutHandler = { [weak self] event in self?.handleShortcut(event) ?? false }
        panel.modifiersHandler = { [weak self] flags in self?.modifiersChanged(flags) }
        panel.scrollHandler = { [weak self] event in self?.scroller.handle(event) ?? false }
        self.panel = panel
    }

    func registerStrip(_ scrollView: NSScrollView) {
        scroller.scrollView = scrollView
    }

    func scrollStripToStart() {
        scroller.scrollToStart()
    }

    // MARK: - Opening

    /// From the global shortcut or the menu bar: opens with the search field
    /// ready, or closes if already open.
    func toggleFromKeyboard() {
        if model.phase == .open {
            close()
        } else {
            open(focusSearch: true)
        }
    }

    func open(on screen: NSScreen? = nil, focusSearch: Bool = false) {
        guard let panel else { return }
        cancelPending()

        if model.phase == .open {
            if focusSearch { self.focusSearch() }
            return
        }

        let target = screen ?? NotchGeometry.screenWithPointer() ?? NSScreen.main
        let metrics = target.map(NotchMetrics.init(screen:)) ?? model.metrics
        if metrics != model.metrics || !panel.isVisible {
            // Only a hidden window is ever moved or resized.
            panel.orderOut(nil)
            model.phase = .closed
            model.metrics = metrics
            panel.setFrame(metrics.panelFrame, display: false)
        }

        panel.ignoresMouseEvents = false
        model.now = Date()
        model.openCount += 1
        scroller.scrollToStart()
        // A folder granted access a moment ago starts filing now.
        watcher.sync()

        let wasVisible = panel.isVisible
        panel.orderFrontRegardless()
        installPointerMonitors()
        pointerHasBeenInside = pointerIsOverPanel()

        // From closed, let the notch-sized shape reach the screen first, so
        // what the eye sees is the notch itself growing.
        if wasVisible {
            expand()
        } else {
            DispatchQueue.main.async { [weak self] in self?.expand() }
        }

        if focusSearch { self.focusSearch() }
    }

    private func expand() {
        guard model.phase != .open else { return }
        withAnimation(Theme.open) { model.phase = .open }
    }

    func close() {
        cancelPending()
        removePointerMonitors()
        detail.hide()
        guard model.phase == .open else { return }

        model.showsShortcutHints = false
        withAnimation(Theme.close) {
            model.phase = .closed
        } completion: { [weak self] in
            guard let self, self.model.phase == .closed else { return }
            self.panel?.orderOut(nil)
            self.model.resetTransientState()
            self.model.copiedClipID = nil
        }
    }

    /// Flash "Copied" on the card, then close.
    func confirmCopy(of clipID: UUID?) {
        withAnimation(Theme.hover) { model.copiedClipID = clipID }
        DispatchQueue.main.asyncAfter(deadline: .now() + (clipID == nil ? 0.05 : 0.32)) { [weak self] in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func focusSearch() {
        takeKeyboard()
        model.searchFocusRequests += 1
    }

    func takeKeyboard() {
        guard let panel, panel.isVisible else { return }
        panel.makeKey()
    }

    func openSettingsWindow() {
        close()
        showSettings()
    }

    private func cancelPending() {
        pendingOpen?.cancel()
        pendingOpen = nil
        pendingClose?.cancel()
        pendingClose = nil
        peekTimer?.cancel()
        peekTimer = nil
    }

    // MARK: - Detail

    func showDetail(for clip: Clip) {
        guard model.phase == .open, let panel else { return }
        let view = ClipDetailView(clip: clip, actions: actions) { [weak self] in self?.detail.hide() }
            .modelContainer(container)
        detail.show(view, size: ClipDetailView.size(for: clip), below: panel.frame, keyHandler: { [weak self] event in
            // Escape or Space puts the preview away, like Quick Look.
            guard event.keyCode == 53 || event.keyCode == 49 else { return false }
            self?.detail.hide()
            return true
        })
    }

    func hideDetail() {
        detail.hide()
    }

    // MARK: - Copy confirmation

    /// The notch widens for a moment with a glimpse of what was just copied —
    /// so a copy is confirmed where you already look, without a window
    /// appearing somewhere else on screen.
    func didCapture(_ clip: Clip) {
        guard settings.showsCopyPeek, let panel, model.phase != .open else { return }
        let peek = Peek(clip)

        if model.phase == .closed {
            let screen = NotchGeometry.screenWithPointer() ?? NSScreen.main
            let metrics = screen.map(NotchMetrics.init(screen:)) ?? model.metrics
            if metrics != model.metrics || !panel.isVisible {
                panel.orderOut(nil)
                model.metrics = metrics
                panel.setFrame(metrics.panelFrame, display: false)
            }
            model.peek = peek
            // Purely a confirmation: clicks pass straight through it.
            panel.ignoresMouseEvents = true
            panel.orderFrontRegardless()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.model.phase == .closed else { return }
                withAnimation(Theme.peek) { self.model.phase = .peek }
            }
        } else {
            withAnimation(Theme.select) { model.peek = peek }
        }

        peekTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.endPeek() }
        }
        peekTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.peekDuration, execute: work)
    }

    private func endPeek() {
        peekTimer = nil
        guard model.phase == .peek else { return }
        withAnimation(Theme.close) {
            model.phase = .closed
        } completion: { [weak self] in
            guard let self, self.model.phase == .closed else { return }
            self.panel?.orderOut(nil)
            self.model.peek = nil
        }
    }

    // MARK: - Hover

    private func rebuildHotZones() {
        hotZones.forEach { $0.remove() }
        hotZones = NSScreen.screens.map { screen in
            let zone = HotZoneWindow(
                onEnter: { [weak self] in self?.pointerEnteredNotch(on: screen) },
                onExit: { [weak self] in self?.pointerLeftNotch() },
                onClick: { [weak self] in self?.open(on: screen) }
            )
            zone.opensOnClick = !settings.opensOnHover
            zone.place(at: NotchGeometry.hotZone(on: screen))
            return zone
        }
    }

    private func pointerEnteredNotch(on screen: NSScreen) {
        guard settings.opensOnHover, model.phase != .open else { return }
        pendingOpen?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.open(on: screen) }
        }
        pendingOpen = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverIntent, execute: work)
    }

    private func pointerLeftNotch() {
        pendingOpen?.cancel()
        pendingOpen = nil
    }

    private func screensChanged() {
        close()
        if model.phase == .peek {
            panel?.orderOut(nil)
            model.phase = .closed
        }
        rebuildHotZones()
    }

    // MARK: - Closing when the pointer leaves

    private func installPointerMonitors() {
        guard pointerMonitors.isEmpty else { return }

        let moved = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }
        let movedInside = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }
        // A click anywhere outside Cache's own windows means "done".
        let clickedAway = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        pointerMonitors = [moved, movedInside, clickedAway].compactMap { $0 }
    }

    private func removePointerMonitors() {
        pointerMonitors.forEach(NSEvent.removeMonitor)
        pointerMonitors.removeAll()
    }

    private func pointerMoved() {
        guard model.phase == .open else { return }

        if pointerIsOverPanel() {
            pointerHasBeenInside = true
            pendingClose?.cancel()
            pendingClose = nil
            return
        }

        // Stay open while typing, mid-drag, or while naming a collection —
        // and when it was opened from the keyboard and the pointer has never
        // come near it.
        guard pointerHasBeenInside,
              NSEvent.pressedMouseButtons == 0,
              panel?.isKeyWindow != true,
              !model.isNamingCollection,
              pendingClose == nil
        else { return }

        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pendingClose = nil
                if !self.pointerIsOverPanel(), NSEvent.pressedMouseButtons == 0 { self.close() }
            }
        }
        pendingClose = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func pointerIsOverPanel() -> Bool {
        guard let panel else { return false }
        var region = panel.frame
        if let preview = detail.frame { region = region.union(preview) }
        return region.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation)
    }

    // MARK: - Keyboard

    private func handleKey(_ event: NSEvent) -> Bool {
        guard model.phase == .open else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let naming = model.isNamingCollection

        switch event.keyCode {
        case 53: // Escape backs out one layer at a time.
            if detail.isVisible { detail.hide() }
            else if naming { model.isNamingCollection = false }
            else if !model.query.isEmpty { model.query = "" }
            else { close() }
            return true
        case 36, 76: // Return, Enter
            guard modifiers.isEmpty, !naming else { return false }
            model.send(.copySelection)
            return true
        case 123, 126: // Left, Up
            guard modifiers.isEmpty, !naming else { return false }
            model.send(.move(-1))
            return true
        case 124, 125: // Right, Down
            guard modifiers.isEmpty, !naming else { return false }
            model.send(.move(1))
            return true
        case 49: // Space previews, when there is nothing typed to add a space to.
            guard modifiers.isEmpty, !naming, model.query.isEmpty, model.selection != nil else { return false }
            model.send(.previewSelection)
            return true
        default:
            return false
        }
    }

    private func handleShortcut(_ event: NSEvent) -> Bool {
        guard model.phase == .open,
              event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command
        else { return false }

        if event.keyCode == 51 { // ⌘⌫
            model.send(.deleteSelection)
            return true
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case let key? where Int(key).map({ (1...9).contains($0) }) == true:
            model.send(.copyNumber(Int(key) ?? 1))
            return true
        case "f":
            focusSearch()
            return true
        case ",":
            openSettingsWindow()
            return true
        default:
            return false
        }
    }

    private func modifiersChanged(_ flags: NSEvent.ModifierFlags) {
        let showHints = flags.intersection([.command, .option, .control, .shift]) == .command && model.phase == .open
        if showHints != model.showsShortcutHints {
            withAnimation(Theme.hover) { model.showsShortcutHints = showHints }
        }
    }
}
