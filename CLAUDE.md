# CLAUDE.md — Clipboard Manager (macOS)

## What we are building

A local-first clipboard + screenshot history app for macOS. Menu bar app, no Dock icon.
Everything stored on-device. No server, no accounts, no network calls.

**Working name:** change this to whatever I decide.

## Non-negotiable rules for Claude Code

0. **You compile your own code. I do not read errors.**
   After every change run:
   `xcodebuild -project <Name>.xcodeproj -scheme <Name> build 2>&1 | tail -40`
   If it fails, fix it and run again. Loop until clean. Do not report back to me
   with a broken build or ask me to paste an error. I only open Xcode to press ⌘R.

1. **Build after every single change.** If it doesn't compile, stop and fix before moving on.
2. **One file per task.** Do not refactor three files at once.
3. **Explain the AppKit parts.** I'm a designer/editor learning Swift. SwiftUI I can follow; AppKit I cannot yet.
4. **Never auto-paste in v1.** Clicking a clip copies it to the clipboard and closes the window. The user presses ⌘V themselves. This is deliberate — see "Explicitly out of scope."
5. **Never capture concealed pasteboard items.** Check for `org.nspasteboard.ConcealedType` and `org.nspasteboard.TransientType` and skip them. Password managers set these. Without this check the database becomes a plaintext password log.
6. **git commit after every working feature.** Small commits, plain messages.

## Stack

| Layer | Choice |
|---|---|
| Language | Swift 5.9+ |
| UI | SwiftUI, `MenuBarExtra` |
| Min target | macOS 14 (Sonoma) |
| Persistence | SwiftData |
| Images/files | Written to disk in Application Support, path stored in DB |
| OCR | Vision framework (`VNRecognizeTextRequest`) |
| Global hotkey | `KeyboardShortcuts` SPM package (sindresorhus) |
| Search | In-memory Swift filter — no FTS needed at our scale |

**Do NOT use:** Electron, Tauri, GRDB, Core Data, any cloud SDK, any analytics.

## Project setup (do this first)

**Use XcodeGen — do not create the project through the Xcode GUI.** I cannot click
through Xcode config panels. Everything must be a text file you can write and I can
regenerate if it breaks.

```bash
brew install xcodegen
xcodegen generate
```

`project.yml` must set:
- Platform macOS, deployment target 14.0
- `LSUIElement: true` in Info.plist → menu bar only, no Dock icon
- **App Sandbox disabled** (blocks file drag-out and, later, Accessibility)
- `NSHumanReadableCopyright`, bundle ID `com.<me>.<appname>`
- SPM dependency: `https://github.com/sindresorhus/KeyboardShortcuts`

Also run `git init` and commit the empty project before writing any Swift.

## Data model

```swift
@Model
final class Clip {
    var id: UUID
    var createdAt: Date
    var kind: String          // "text" | "link" | "image" | "color" | "code" | "file"
    var text: String?         // text content, or file path string, or hex code
    var imageFilename: String?    // filename in Application Support/Clips/
    var thumbnailFilename: String?
    var ocrText: String?      // populated async by Vision for images
    var sourceAppName: String?
    var sourceAppBundleID: String?
    var isPinned: Bool
    var category: String?     // user-created category name, nil = History
}
```

Files live at `~/Library/Application Support/<BundleID>/Clips/`.
Thumbnails capped at 400px on the long edge.

## Architecture — build in this order

```
App.swift                 MenuBarExtra entry point, LSUIElement
ClipboardMonitor.swift    the polling engine
ClipStore.swift           SwiftData wrapper: insert, delete, prune, search
ClipKind.swift            type detection from pasteboard contents
FileStorage.swift         image/thumbnail write + delete
OCRService.swift          Vision text recognition, background queue
ContentView.swift         the list UI
ClipRow.swift             a single clip card
FilterBar.swift           type + app + category filters
Settings.swift            hotkey, history limit, pause capture
PanelController.swift     Phase C only — floating hotkey window
```

## The capture engine (the only genuinely tricky part)

`NSPasteboard` has **no** change notification API on macOS. There is no event to subscribe to.
The only approach is polling `changeCount`:

- `Timer` on the main run loop, interval `0.3` seconds
- Compare `NSPasteboard.general.changeCount` to the last seen value
- If unchanged, return immediately — this is why polling is cheap
- If changed:
  1. Check `types` for `org.nspasteboard.ConcealedType` / `TransientType` → if present, update the stored changeCount and **return without saving**
  2. Read content, preferring in this order: file URLs → image → string
  3. Capture source app via `NSWorkspace.shared.frontmostApplication` (name + bundle ID + icon). Our menu bar app does not activate, so frontmostApplication is correct at poll time.
  4. Deduplicate: if identical text to the most recent clip, skip
  5. Insert into SwiftData
  6. If image → dispatch OCR to a background queue, write `ocrText` back when done

Prune to a max history count (default 2000) on insert, deleting orphaned image files too.

## Type detection rules

| Kind | Rule |
|---|---|
| `color` | String matches `^#?([0-9A-Fa-f]{6}\|[0-9A-Fa-f]{3})$` or `rgb(...)` / `rgba(...)` |
| `link` | `URL(string:)` parses and scheme is `http`/`https` |
| `file` | Pasteboard contains `.fileURL` |
| `image` | Pasteboard contains `.tiff` or `.png` |
| `code` | Heuristic: contains `{ }` / `;` / `=>` / `def ` / `func ` / `import ` AND has newlines |
| `text` | Everything else (default) |

Order matters — check file, then image, then color, then link, then code, then text.

## Design system — follow this exactly

Do not invent your own styling. Do not use default SwiftUI chrome. The target is a
native-feeling, quiet, expensive Mac utility — think Raycast, Linear, Things 3.
Not a web app in a window.

**Surface**
- Window background: `NSVisualEffectView` with material `.hudWindow`, blending
  `.behindWindow`. This is what makes Mac apps feel native, and it's GPU-composited
  so it costs nothing. Wrap it in an `NSViewRepresentable`.
- Corner radius 12 on the window, 8 on cards.
- Cards separated by a 1px border at `white.opacity(0.08)` — **never drop shadows**.
  Shadows are the #1 tell of an AI-generated Mac UI.

**Color**
- Base is the material, not a flat fill. Do not paint a solid dark rectangle over it.
- Text: `.primary` and `.secondary`. Use the semantic colors so light/dark mode
  work for free.
- **Exactly one accent color** across the whole app, used only for: selection state,
  active filter chip, pinned indicator. Nothing else is colored.
- The only exception: `color` kind clips render their own swatch.

**Type**
- System font (SF Pro) throughout. It is the correct choice for a Mac utility.
- Row title: 13pt medium. Metadata: 11pt regular, `.secondary`.
- Line limit 2 on text clips, truncate tail.
- Tracking: default. Do not letter-space UI text.

**Spacing**
- 8px grid. Padding values are only ever 4, 8, 12, 16, 24.
- Row height 56px for text, 88px for image clips.
- 12px window padding, 6px between rows.

**Motion**
- Every state change animates with `.spring(response: 0.3, dampingFraction: 0.8)`.
- Hover on a row: background lifts to `white.opacity(0.06)` in 0.12s. Hover states
  are mandatory on macOS — an app without them feels dead.
- No bounce, no scale-on-tap, no confetti, no gradients that move.
- Panel open/close: fade + 4px upward offset. Nothing more.

**Details that separate good from award-winning**
- Focus ring follows keyboard nav, and ↑↓ scrolls the selection into view.
- Source app icon on every row, 16px, rendered from the real app bundle.
- Relative timestamps ("2m", "1h", "yesterday"), right-aligned, `.secondary`.
- Real empty states with a line of copy, never a blank rectangle.
- The search field is focused the instant the panel opens. Always.

## Performance budget — hard limits

This runs 24/7 in the background. It must be invisible in Activity Monitor.

- **Idle CPU must be under 0.1%.** The poll timer reads a single `Int`
  (`changeCount`) and returns. It must not touch the pasteboard contents, the
  database, or the UI unless the count actually changed.
- **Idle RAM under 80MB.** Never hold full-size images in memory. The list renders
  thumbnails only (400px max edge); full images load on demand.
- Poll interval 0.3s on AC, **0.5s on battery** (check `ProcessInfo.processInfo
  .isLowPowerModeEnabled` and battery state).
- `LazyVStack` inside `ScrollView` — never render off-screen rows.
- Fetch with a limit (100 rows) + pagination. Never fetch all clips.
- OCR runs on a `.utility` QoS background queue, one image at a time, never on the
  main thread, and never blocks insert.
- When the window is closed, **stop all UI work**. Keep only the poll timer alive.
- Timer must be on `RunLoop.main` in `.common` mode or it stalls during menu tracking.
- Hard cap history at 2000 clips; prune on insert and delete orphaned image files.

If any of these are violated, fix it before adding features.

## Phases

### Phase A — Day 1: it works
- [ ] Menu bar icon with `MenuBarExtra(style: .window)`
- [ ] `ClipboardMonitor` polling and saving text clips
- [ ] Concealed-type guard in place from the very first commit
- [ ] SwiftData store + list of the last 100 clips, newest first
- [ ] Click a clip → writes to `NSPasteboard.general`, window closes
- [ ] Source app name + icon shown on each row
- [ ] Quit button

**At the end of Day 1 I should be able to use this instead of nothing. Ugly is fine.**

### Phase B — Day 2: it's good
- [ ] Image clips: write to disk, thumbnail, render in list
- [ ] Type detection wired up, colored swatch for `color` kind
- [ ] Search field, filters over text + ocrText
- [ ] Filter chips: by kind, by source app
- [ ] Pin / unpin, pinned section at top
- [ ] Delete a clip (and its files), clear all
- [ ] Settings: history limit, pause capture toggle

### Phase C — Day 3: it feels native
- [ ] `KeyboardShortcuts` global hotkey (default ⌃⌘V)
- [ ] Hotkey opens a floating `NSPanel` — borderless, `.floating` level,
      `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`,
      centered like Spotlight. Esc closes.
- [ ] Full keyboard nav: ↑↓ to move, Enter to copy+close, Esc to dismiss
- [ ] Drag-out via SwiftUI `.onDrag` with `NSItemProvider`
- [ ] Custom categories: create, assign, filter

### Phase D — Day 4: the impressive stuff
- [ ] Vision OCR on every image clip, indexed into search
- [ ] Screenshot history: `NSMetadataQuery` for `kMDItemIsScreenCapture == 1`,
      or watch the folder from `defaults read com.apple.screencapture location`
- [ ] Empty states, animations, icon, app polish

### Later / optional
- Auto-paste (requires non-activating `NSPanel` + Accessibility permission + `CGEvent` ⌘V, virtual key `0x09` with `.maskCommand`)
- Multi-clip combine
- Notch UI
- iCloud sync

## Explicitly out of scope — do not build these

- **Inline text expansion** (`;welcome` → text). Requires a system-wide `CGEventTap`
  reading every keystroke. Architecturally a keylogger. Not worth it.
- **iCloud / any sync.** Single device.
- **Auto-paste in v1.** Deliberately deferred — see rule 4.
- **Licensing, payments, notarization, App Store.** Personal build.
- **Any network request whatsoever.** If a task seems to need one, stop and ask me.

## Known gotchas

- If a window ever *activates*, the previously focused app loses focus. Irrelevant in v1 (manual ⌘V), critical if auto-paste is added later.
- Deleting a `Clip` row must also delete its image + thumbnail files, or Application Support grows forever.
- OCR must run off the main thread or the UI stutters on every screenshot.
- `MenuBarExtra` cannot be reliably opened programmatically — that's why the hotkey gets its own `NSPanel` in Phase C rather than reusing the menu bar window.
- Timer must be added to `.common` run loop mode or it stops firing during menu tracking.

## Cost discipline (I'm on limited API credit)

- Default to Sonnet. Only escalate to Opus for a bug that has survived two attempts.
- Don't re-read the whole project every turn. Read only the files you're editing.
- Keep files small so you never need to load 800 lines to change 10.
- When something breaks badly, tell me to `git checkout .` rather than debugging
  your way out of it.

## First prompt to give Claude Code

> Read CLAUDE.md. Install xcodegen, write project.yml per the setup section,
> generate the project, git init, and verify it builds with xcodebuild before
> writing any app code. Then build Phase A only — start with
> ClipboardMonitor.swift, including the concealed-type guard. Compile and fix
> your own errors; don't ask me to paste anything. Stop when Phase A builds
> and runs. Do not touch Phase B.
