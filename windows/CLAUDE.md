# CLAUDE.md — Cache for Windows

## Read this first

This is the Windows port of **Cache**, a local-first clipboard + screenshot
history app. The macOS original is in this same repo at `../SupaClip/` and is
shipping at v1.0.1. **Read `../CLAUDE.md` too** — it is the original contract and
most of its reasoning still applies. This file only covers what is different.

The scaffold under `src/` was written on a Mac, so **none of it has ever been
compiled**. Assume it contains errors. Your first job is to make it build, not to
trust it.

## Non-negotiable rules

0. **You compile your own code. I do not read errors.**
   After every change:
   `dotnet build windows/src/Cache.Cli/Cache.Cli.csproj 2>&1 | Select-Object -Last 40`
   Fix and re-run until clean. Never hand me a broken build or ask me to paste an
   error.

1. **Build after every single change.** If it doesn't compile, stop and fix it.
2. **One file per task.** Do not refactor three files at once.
3. **Explain the Win32 parts.** I'm a designer/editor. C# I can follow; raw
   P/Invoke, window procedures and HGLOBAL handles I cannot yet.
4. **Never record a clip the copying app asked us not to.** See
   `ClipboardPrivacy.cs`. That guard runs before any content is read, it fails
   closed, and it is the single most important behaviour in the app. Do not
   "optimise" it.
5. **Never auto-paste without an explicit setting.** Windows lets us `SendInput`
   a Ctrl+V with no permission at all, which is exactly why it needs a user-facing
   toggle that is off by default.
6. **No network requests. None.** Same rule as macOS. If a task seems to need
   one, stop and ask me.
7. **git commit after every working feature.** Small commits, plain messages.

## Stack

| Layer | Choice |
|---|---|
| Language | C# 13 / .NET 9 |
| UI | WinUI 3 (Windows App SDK) |
| Min target | Windows 10 2004 (build 19041) |
| Persistence | SQLite via `Microsoft.Data.Sqlite`, hand-written SQL |
| Images/files | Written to `%LOCALAPPDATA%\Cache\Clips\`, filename stored in DB |
| OCR | `Windows.Media.Ocr` — on-device, built into Windows, free |
| Clipboard notify | `AddClipboardFormatListener` → `WM_CLIPBOARDUPDATE` |
| Clipboard read | WinRT `Windows.ApplicationModel.DataTransfer.Clipboard` |
| Global hotkey | `RegisterHotKey` (Win32) |
| Tray icon | `H.NotifyIcon.WinUI` — WinUI 3 has no built-in tray |
| Search | In-memory LINQ filter, same as macOS. No FTS at our scale |

**Do NOT use:** Electron, Tauri, WPF, WinForms, Entity Framework, any cloud SDK,
any analytics, any telemetry.

## How Windows differs from macOS — read before porting anything

This is the map. Most porting mistakes come from assuming the macOS shape.

| macOS | Windows | Note |
|---|---|---|
| Poll `changeCount` every 0.3s | `WM_CLIPBOARDUPDATE` push notification | **Delete the polling design.** No timer, no interval, no AC-vs-battery tuning. ~80 lines of `ClipboardMonitor.swift` have no counterpart |
| `org.nspasteboard.ConcealedType` | `ExcludeClipboardContentFromMonitorProcessing` + two DWORD flags | Same intent, three formats instead of one. Already implemented |
| `NSWorkspace.frontmostApplication` | `GetForegroundWindow` → `GetWindowThreadProcessId` → `Process` | `MainModule` throws for elevated processes. Handle it |
| Vision `VNRecognizeTextRequest` | `OcrEngine.TryCreateFromUserProfileLanguages()` | Equivalent quality. Needs a `SoftwareBitmap`, not a file path |
| SwiftData `@Model` | Hand-written SQLite | Keep column names identical to the Swift property names |
| `MenuBarExtra` | `H.NotifyIcon` tray icon | No SwiftUI-native equivalent |
| The notch | **Nothing.** No notch exists | See "The UI question" below |
| `NSVisualEffectView` `.hudWindow` | Mica / Acrylic backdrop | Direct analogue, same design intent |
| Accessibility permission for auto-paste | `SendInput`, no permission | We can actually ship auto-paste here |
| `LSUIElement: true` | No window shown at startup + tray icon | Different mechanism, same result |
| App Sandbox off | No sandbox unless packaged as MSIX | Ship unpackaged first |

## The UI question — decide this before writing any XAML

Cache's whole macOS identity is *hover the notch, the shelf drops down*. **There
is no notch on Windows and no anchor for that gesture.** Do not try to fake one.

Ship in this order:

1. **Hotkey flyout first** — `Ctrl+Shift+V`, a centered Spotlight-style panel.
   Windows users already have Win+V muscle memory, so this is the familiar shape
   and the fastest route to something usable.
2. **Top-edge hover strip second** — the closest thing to the notch feel, and the
   differentiator. Add it as an option, not the default.

Windows ships its own clipboard history on Win+V. It is weak: no OCR, no search
inside images, no collections, 25-item cap. **Searchable screenshot text is the
entire pitch.** Prioritise it.

## Design system

`../DESIGN.md` holds the visual spec. Translate it, don't reinvent it:

- **Surface:** Mica backdrop (`MicaBackdrop`) on the main window, Acrylic on the
  flyout. Never a flat painted rectangle over it.
- **Corner radius:** 8 on the window (Windows 11 convention — *not* macOS's 12),
  4 on cards.
- **No drop shadows on cards.** 1px border at `White 8%`. Same rule as macOS, and
  the same reason: shadows are the tell of a generated UI.
- **Type:** Segoe UI Variable throughout. Row title 13px semibold, metadata 11px
  regular secondary. Do not use SF Pro; it is wrong here.
- **Spacing:** 8px grid. Padding only ever 4, 8, 12, 16, 24.
- **One accent colour**, and use the user's Windows accent colour rather than
  inventing one. Selection, active filter chip, pinned indicator. Nothing else.
- **Motion:** 150ms cubic ease-out. Windows motion is flatter and faster than
  macOS spring — do not port the spring curves literally, they will feel sluggish.
- **Hover states are mandatory** on every interactive row.

## Performance budget — hard limits

Runs 24/7 in the background. Must be invisible in Task Manager.

- **Idle CPU 0.00%.** Not "low" — actually zero. The listener thread blocks in
  `GetMessage`. If you ever add a timer, justify it in a comment or delete it.
- **Idle RAM under 80MB.** *Note the macOS app fails this* — Vision's models add
  85MB once loaded. Windows OCR has the same risk. Run OCR in a **separate
  short-lived process** and let it exit; that is the fix macOS never got, and
  doing it here from the start is much cheaper than retrofitting.
- Thumbnails capped at 400px on the long edge. Never hold full images in memory.
- Virtualised list (`ItemsRepeater`), never render off-screen rows.
- Page fetches at 100 rows. Never `SELECT *` the whole history.
- Hard cap history at 2000 clips; prune on insert and delete orphaned files.

## Current state of the scaffold

Written but **never compiled** — treat as a draft:

- `Directory.Build.props` — shared settings, warnings-as-errors
- `src/Cache.Core/Clip.cs` — the model, field-for-field with macOS
- `src/Cache.Core/ClipKind.cs` — type detection, ported rule-for-rule. Pure logic
- `src/Cache.Core/Interop/Win32.cs` — the P/Invoke surface
- `src/Cache.Core/ClipboardPrivacy.cs` — the password guard
- `src/Cache.Core/ClipboardMonitor.cs` — message-only window + listener

Not written yet:

- `ClipboardReader.cs` — read text/image/file off the clipboard via WinRT
- `ClipStore.cs` — SQLite schema, insert, dedupe, prune, delete
- `FileStorage.cs` — PNG + thumbnail write, thumbnail cache
- `OcrService.cs` — out-of-process OCR
- `ScreenshotWatcher.cs` — `FileSystemWatcher` on the Screenshots folder
- `AppSettings.cs` — hotkey, history limit, pause, ignore rules
- `Cache.Cli` — the console harness
- The entire WinUI app

## Build order

**Phase W0 — make the scaffold real.**
Install .NET 9 SDK. Get `Cache.Core` compiling. Fix everything the Mac-written
code got wrong. Do not add features. Commit when green.

**Phase W1 — Day 1: it captures.**
`ClipboardReader`, `ClipStore` (text only), and a console app that prints every
captured clip live. Privacy guard verified by copying from a password manager and
confirming nothing is recorded. **Ugly is fine — but it must actually work.**

**Phase W2 — Day 2: it persists properly.**
Images to disk + thumbnails, type detection wired up, dedupe, prune, search,
settings.

**Phase W3 — Day 3: it has a face.**
WinUI 3 app, tray icon, `RegisterHotKey` flyout, keyboard nav, drag-out.

**Phase W4 — Day 4: the pitch.**
Out-of-process OCR, screenshot watcher, collections, empty states, icon.

**Phase W5 — optional.** Auto-paste (off by default), top-edge hover strip, MSIX
packaging, code signing.

## Known gotchas

- **The `WndProc` delegate must be held in a field.** If only passed to
  `RegisterClassEx`, the GC collects it and the first clipboard change calls into
  freed memory and kills the process. Already handled — do not "clean it up".
- **Never let an exception escape a window procedure.** Crossing back into native
  code with a live exception terminates the process. Every handler is wrapped.
- **`OpenClipboard` fails routinely.** Only one process may hold it, and the app
  that just wrote is often still holding it. Retry with backoff; never assume.
- **Clipboard handles from `GetClipboardData` are owned by the clipboard.** Do not
  free them, and do not use them after `CloseClipboard`.
- **`GetMessage` returns `-1` on error, not `0`.** Treating it as a bool spins the
  CPU at 100%.
- **WinRT clipboard reads are async and throw** when another app holds the lock.
  Wrap in try/catch and retry.
- **`Process.MainModule` throws** for elevated or protected processes.
- **WinUI 3 unpackaged apps** need `<WindowsPackageType>None</WindowsPackageType>`
  and the Windows App SDK bootstrapper. Packaged-only APIs will fail at runtime,
  not compile time.
- **ARM64 vs x64.** If this is being built in a VM on Apple Silicon, it is ARM64.
  Build both; never hardcode a RID.

## Explicitly out of scope

- Inline text expansion (needs a system-wide keyboard hook — architecturally a
  keylogger)
- Any sync, cloud, or account
- Microsoft Store submission
- Telemetry of any kind

## First prompt for the Windows session

> Read `windows/CLAUDE.md` and `CLAUDE.md`. Install the .NET 9 SDK if it is
> missing. Then do Phase W0 only: get `windows/src/Cache.Core` to compile clean.
> The scaffold was written on a Mac and has never been built, so expect errors —
> fix them yourself and do not ask me to paste anything. Report what was wrong
> when it is green. Do not start Phase W1.
