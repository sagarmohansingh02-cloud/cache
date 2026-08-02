import AppKit
import Foundation
import IOKit.ps

/// The capture engine.
///
/// AppKit background, since this is the part you said you can't follow yet:
/// `NSPasteboard` has **no** change notification. There is no delegate, no
/// KVO, no NotificationCenter event for "the user copied something". The only
/// thing Apple gives us is `changeCount` — an integer that increments every
/// time *anything* writes to the pasteboard. So we poll it.
///
/// That sounds expensive and isn't: reading `changeCount` is a single cheap
/// lookup. When it hasn't moved we return immediately without touching the
/// pasteboard contents, the database, or the UI. That's the whole reason a
/// 0.3s timer can sit at effectively 0% CPU all day.
@MainActor
final class ClipboardMonitor {
    private let store: ClipStore
    private let pasteboard: NSPasteboard = .general

    private var timer: Timer?
    private var lastChangeCount: Int

    /// Fires counted since we last re-checked the power source. See `pollsBetweenPowerChecks`.
    private var pollsSincePowerCheck = 0

    /// Poll intervals from the performance budget.
    private static let intervalOnAC: TimeInterval = 0.3
    private static let intervalOnBattery: TimeInterval = 0.5

    /// Re-check AC vs battery roughly once a minute rather than on every fire —
    /// the IOKit call is far more expensive than reading `changeCount`.
    private static let pollsBetweenPowerChecks = 200

    private var currentInterval: TimeInterval = ClipboardMonitor.intervalOnAC

    /// Pasteboard types that mean "do not record this".
    /// Password managers stamp `ConcealedType` on what they copy. Without this
    /// guard the database becomes a plaintext password log.
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    init(store: ClipStore) {
        self.store = store
        // Start from the current count so we don't capture whatever happened to
        // be on the pasteboard before launch.
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }
        currentInterval = Self.preferredInterval()
        scheduleTimer(interval: currentInterval)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Call immediately after *we* write to the pasteboard.
    ///
    /// Writing bumps `changeCount` exactly like a user copy would, so without
    /// this the next tick would re-capture our own write and push a duplicate
    /// to the top of the list. Swallowing the count here is cheaper and more
    /// reliable than trying to recognise our own content later.
    func acknowledgeSelfCopy() {
        lastChangeCount = pasteboard.changeCount
    }

    /// `Timer.scheduledTimer` would install the timer in `.default` run loop
    /// mode, which **stops firing** while a menu is being tracked — i.e. exactly
    /// while our menu bar window is open. Creating it manually and adding it in
    /// `.common` mode is what keeps it alive during menu tracking.
    private func scheduleTimer(interval: TimeInterval) {
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            // The timer block is not main-actor-isolated, so hop back explicitly.
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - The poll

    private func tick() {
        checkPowerSourceIfDue()

        // The fast path: one integer read, then out. This runs ~3x/second all
        // day and must stay this cheap.
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        capture()
    }

    private func capture() {
        let types = pasteboard.types ?? []

        // Concealed/transient guard, before we read a single byte of content.
        // We've already stored the new changeCount above, so this item is
        // skipped permanently rather than retried on the next tick.
        if types.contains(Self.concealedType) || types.contains(Self.transientType) {
            return
        }

        // Phase A captures text only. Images, files and type detection are Phase B.
        guard let text = pasteboard.string(forType: .string) else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // `frontmostApplication` is the app the user is actually working in.
        // This is correct here because our menu bar app never activates — it
        // doesn't steal focus, so whoever copied is still frontmost.
        let frontApp = NSWorkspace.shared.frontmostApplication

        store.insertText(
            text,
            sourceAppName: frontApp?.localizedName,
            sourceAppBundleID: frontApp?.bundleIdentifier
        )
    }

    // MARK: - Power

    private func checkPowerSourceIfDue() {
        pollsSincePowerCheck += 1
        guard pollsSincePowerCheck >= Self.pollsBetweenPowerChecks else { return }
        pollsSincePowerCheck = 0

        let wanted = Self.preferredInterval()
        guard wanted != currentInterval else { return }

        currentInterval = wanted
        stop()
        scheduleTimer(interval: wanted)
    }

    private static func preferredInterval() -> TimeInterval {
        (ProcessInfo.processInfo.isLowPowerModeEnabled || isOnBatteryPower())
            ? intervalOnBattery
            : intervalOnAC
    }

    /// IOKit's power-source API is the only way to ask "are we on battery?" on
    /// macOS. It hands back Core Foundation objects, hence the `takeRetainedValue`
    /// dance — that's manual memory-management bookkeeping Swift can't infer
    /// across the C boundary. Returns false (assume AC) if anything is unexpected.
    private static func isOnBatteryPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return false }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any],
                  let state = description[kIOPSPowerSourceStateKey] as? String
            else { continue }

            if state == kIOPSBatteryPowerValue { return true }
        }
        return false
    }
}
