import KeyboardShortcuts

/// Global hotkeys, registered with the system rather than with our own windows.
///
/// A global shortcut fires no matter which app is frontmost, which is why this
/// needs a real system registration — `.keyboardShortcut` in SwiftUI only works
/// while our own window already has focus, which is exactly the case we can't
/// rely on. The `KeyboardShortcuts` package wraps Carbon's `RegisterEventHotKey`
/// and persists the user's choice for us.
extension KeyboardShortcuts.Name {
    /// Default ⌃⌘V — deliberately next to ⌘V without colliding with it.
    static let togglePanel = Self(
        "togglePanel",
        default: .init(.v, modifiers: [.control, .command])
    )
}
