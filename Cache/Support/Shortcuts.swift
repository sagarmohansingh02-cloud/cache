import KeyboardShortcuts

/// Global hotkeys, registered with the system so they work whatever app is in
/// front. `KeyboardShortcuts` wraps Carbon's `RegisterEventHotKey` and stores
/// the user's choice for us.
extension KeyboardShortcuts.Name {
    /// Opens the notch with the search field ready. ⌃⌘V by default — next to
    /// ⌘V without colliding with it. Stored under its 1.x name, so a shortcut
    /// someone already recorded carries over.
    static let toggleNotch = Self("togglePanel", default: .init(.v, modifiers: [.control, .command]))
}
