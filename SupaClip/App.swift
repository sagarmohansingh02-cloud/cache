import SwiftUI

// The entry point. `@main` tells Swift this struct owns the app lifecycle —
// there is no `main.swift`, no AppDelegate, no NSApplication subclass.
//
// `MenuBarExtra` is SwiftUI's menu bar item. With `style: .window` it drops a
// small floating panel below the icon instead of a classic NSMenu, which is
// what lets us put a real SwiftUI list in there later.
//
// Info.plist sets `LSUIElement: true`, which is what removes the Dock icon and
// the menu bar (File/Edit/View...) — that flag, not any code here, is what
// makes this a menu-bar-only app.
@main
struct SupaClipApp: App {
    var body: some Scene {
        MenuBarExtra("SupaClip", systemImage: "doc.on.clipboard") {
            ScaffoldView()
        }
        .menuBarExtraStyle(.window)
    }
}

/// Placeholder shell so the project builds and runs before Phase A lands.
struct ScaffoldView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SupaClip")
                .font(.system(size: 13, weight: .medium))

            Text("Scaffold only — clipboard capture not wired up yet.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Divider()

            Button("Quit SupaClip") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(16)
        .frame(width: 280)
    }
}
