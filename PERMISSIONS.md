# Permissions

Cache asks for as little as possible, as late as possible. This is what it can
ask for, when, and why — and how to stop macOS asking twice.

---

## What Cache asks for

| Permission | When | Why |
|---|---|---|
| **The folder your screenshots are saved in** *(usually inside Desktop)* | The first time Cache looks at it — at first launch, while **Save screenshots** is on | To notice new screenshots and file them |
| **Login item** | Registered once, on first launch from /Applications | So capture keeps running after a restart. macOS shows a notice; remove it in System Settings → General → Login Items, or switch off **Open at login** |

**Cache never asks for Accessibility, Input Monitoring, Screen Recording or Full
Disk Access**, and does not need them. It does not read keystrokes. Clipboard
history is read by polling `NSPasteboard.changeCount`, which is unprivileged.
Screenshots are the files macOS itself saved — Cache never captures your screen.

---

## Why Cache asks about your Desktop

macOS saves screenshots to the Desktop by default, and the Desktop is a protected
location, as are Documents and Downloads. Watching the screenshot folder is what
the prompt is for, and it names that reason.

Screenshots are half of what Cache is for, so saving them is on from the start,
and the prompt comes with the first launch rather than hiding behind a setting.
Turn **Save screenshots** off and Cache stops looking at the folder.

If you decline, the notch shows why screenshots aren't arriving, and **Allow
Access** opens System Settings → Privacy & Security → Files & Folders. Or, to
avoid the permission altogether, point macOS at an unprotected folder:

```bash
mkdir -p ~/Screenshots
defaults write com.apple.screencapture location ~/Screenshots
killall SystemUIServer
```

Cache follows `com.apple.screencapture location` within a few seconds, so it will
watch the new folder and no permission is required.

---

## Why macOS may ask every time you rebuild

This one catches everybody, and it is not a bug in Cache.

macOS ties a privacy grant to an app's **code signature**. With no signing
certificate, Xcode signs *ad-hoc*, which produces a different signature on every
build. macOS therefore sees each build as a brand-new app and asks again — it is
not ignoring your "Allow", it granted it to a build that no longer exists.

You will not hit this if you download a release. You will hit it constantly if
you are building from source.

### Fix: a free self-signed certificate

No Apple Developer account needed.

1. Open **Keychain Access**
2. Menu: **Keychain Access → Certificate Assistant → Create a Certificate…**
3. Name: `Cache Dev` · Identity Type: **Self Signed Root** · Certificate Type:
   **Code Signing**
4. Create, then Done
5. Build with it:

```bash
CACHE_SIGN_IDENTITY="Cache Dev" xcodegen generate
CACHE_SIGN_IDENTITY="Cache Dev" xcodebuild -project Cache.xcodeproj -scheme Cache -configuration Release build
```

The signature is now identical across rebuilds, so a granted permission stays
granted.

With no `CACHE_SIGN_IDENTITY` set the build falls back to ad-hoc, so
`xcodegen generate && xcodebuild …` still works with zero setup.

### Distributing to other people

Ad-hoc and self-signed builds trip Gatekeeper on someone else's Mac — they will
see "Cache is damaged" or "unidentified developer" and have to right-click →
Open, or clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/Cache.app
```

Shipping without that friction needs a **Developer ID certificate** (paid Apple
Developer account) plus notarisation. That is the only way to avoid it — there
is no flag that turns Gatekeeper off for one app.

---

## What is not on the table

Cache will not disable System Integrity Protection, write to the TCC database, or
otherwise pre-approve its own permissions. Those techniques weaken protection for
**every** app on the machine, not just this one, and an app that does them to
save you one click has told you exactly how much it respects the boundary.

One prompt, once, is the correct cost.
