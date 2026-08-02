import AppKit
import Observation

/// Keyboard navigation state, deliberately a *class*.
///
/// The key handler is an `NSEvent` monitor whose closure is installed once, on
/// appear. A SwiftUI `View` is a struct, so a closure that captured the view
/// would be reading a frozen snapshot of its state forever. Routing everything
/// through this reference type means the handler always sees — and mutates —
/// live values.
///
/// Enter and Escape are exposed as counters rather than closures for the same
/// reason: the handler only bumps a number, and the view reacts with `onChange`,
/// where `self` is current.
@MainActor
@Observable
final class ListNavigator {
    var selectedIndex = 0

    /// Number of rows currently on screen; kept in sync by the view.
    var count = 0 {
        didSet { clamp() }
    }

    var activationRequests = 0
    var dismissRequests = 0

    var selection: Int? {
        guard count > 0 else { return nil }
        return min(max(selectedIndex, 0), count - 1)
    }

    func move(by delta: Int) {
        guard count > 0 else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), count - 1)
    }

    func resetSelection() {
        selectedIndex = 0
    }

    private func clamp() {
        guard count > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(max(selectedIndex, 0), count - 1)
    }
}

/// Installs a local key handler for the arrow keys, Return and Escape.
///
/// AppKit background: a *local* monitor sees events on their way to our own
/// windows and can swallow them by returning nil. This is the only reliable
/// way to claim the arrow keys here — the search field is focused, and a
/// focused text field consumes arrow presses before SwiftUI's `onKeyPress`
/// ever sees them.
enum KeyboardNavigationMonitor {
    private enum KeyCode {
        static let returnKey: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let escape: UInt16 = 53
        static let arrowUp: UInt16 = 126
        static let arrowDown: UInt16 = 125
    }

    static func install(navigator: ListNavigator) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                switch event.keyCode {
                case KeyCode.arrowDown:
                    navigator.move(by: 1)
                    return nil
                case KeyCode.arrowUp:
                    navigator.move(by: -1)
                    return nil
                case KeyCode.returnKey, KeyCode.keypadEnter:
                    navigator.activationRequests += 1
                    return nil
                case KeyCode.escape:
                    navigator.dismissRequests += 1
                    return nil
                default:
                    // Everything else carries on to the search field.
                    return event
                }
            }
        }
    }

    static func remove(_ monitor: Any?) {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
    }
}
