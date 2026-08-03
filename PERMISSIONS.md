# Permissions

Cache asks for as little as possible, as late as possible. This is what it can
ask for, when, and why — and how to stop macOS asking twice.

---

## What Cache asks for

| Permission | When | Why |
|---|---|---|
| **Desktop folder** *(or wherever screenshots are saved)* | Only after you switch **Save screenshots** on in Settings | To notice new screenshots and file them |
| **Notifications** | Only when you set a reminder on a clip | To fire that reminder |

Nothing is requested at launch. A fresh install prompts for nothing at all.

**Cache never asks for Accessibility, Input Monitoring or Full Disk Access**, and
does not need them. It does not read keystrokes. Clipboard history is read by
polling `NSPasteboard.changeCount`, which is unprivileged.

---

## Why "Save screenshots" triggers a Desktop prompt

macOS saves screenshots to the Desktop by default, and Desktop is a protected
location. Watching that folder is what the prompt is for.

The switch is **off by default** precisely so this prompt never appears
unprompted. Turning it on and immediately being asked for the screenshot folder
is an obvious consequence; being asked on first launch, before you have done
anything, is not.

If you would rather not grant it at all, point macOS at an unprotected folder:

```bash
mkdir -p ~/Screenshots
defaults write com.apple.screencapture location ~/Screenshots
killall SystemUIServer
```

Cache follows `com.apple.screencapture location`, so it will watch the new folder
and no permission is required.

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
