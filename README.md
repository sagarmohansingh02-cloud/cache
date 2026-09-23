# Cache

A clipboard and screenshot history for macOS that lives in the notch.

Copy something and it is kept. Take a screenshot and it is kept too. Move your
pointer to the notch and it all comes back — text, links, colours, code, files,
images and screenshots, with the text inside your screenshots searchable.

Everything stays on your Mac. No account, no sync, no network requests, and
passwords are never saved.

---

## What it does

**Lives in the notch.** Move the pointer into the notch and the notch itself
grows into a black panel: search on the left, your history below, one card per
clip. On displays without a notch it unrolls from the middle of the menu bar.

**Catches every screenshot.** New screenshots are filed the moment macOS saves
them — recognised by the marker macOS writes on every capture, so nothing waits
on Spotlight. Cache follows your screenshot folder if you move it, and picks up
screenshots you took while it wasn't running.

**Reads your screenshots.** Every image goes through on-device text recognition,
so a screenshot of a receipt is findable by anything printed on it. The preview
shows that text beside the picture, ready to copy.

**Scrolls the way you do.** Swipe sideways on a trackpad, swipe up and down, or
turn a mouse wheel — the strip moves through your whole history either way.

**Confirms every copy.** The notch widens for a moment with a glimpse of what you
just copied, then settles back. Turn it off in Settings if you'd rather not see it.

**Knows what things are.** Text, links, colours, code, files and images are
detected and filtered separately. Colours show as swatches, with HEX / RGB / HSL
/ CMYK one click away.

**Collections and stars.** File clips into your own collections; star the ones
that should survive Clear History.

**Starts with your Mac.** Installed in /Applications, Cache adds itself as a login
item on first launch, so capture never silently stops after a restart. Switch
it off in Settings.

---

## Install

Requires **macOS 14 (Sonoma) or later**. Built and tested on macOS 26.

### Download

Grab the latest **`Cache-2.0.0.dmg`** from
[Releases](https://github.com/sagarmohansingh02-cloud/cache/releases), open it,
and drag Cache onto Applications.

On first launch macOS will say the app is from an unidentified developer,
because this build is not signed with a paid Apple Developer certificate.
Right-click **Cache.app → Open** and confirm. Once only.

macOS then asks whether Cache may open the folder your screenshots are saved in.
Allow it, and screenshots start arriving.

### Build the installer yourself

```bash
./scripts/make-dmg.sh
```

Builds Release and writes `dist/Cache-<version>.dmg`.

### From source

```bash
brew install xcodegen
git clone https://github.com/sagarmohansingh02-cloud/cache.git
cd cache
xcodegen generate
xcodebuild -project Cache.xcodeproj -scheme Cache -configuration Release build
cp -R ~/Library/Developer/Xcode/DerivedData/Cache-*/Build/Products/Release/Cache.app /Applications/
open /Applications/Cache.app
```

Debug builds run as `com.sagarmohansingh.cache.dev`, with their own history and
settings, so running from Xcode never touches the copy you use every day.

There is no Dock icon by design — move your pointer into the notch, press ⌃⌘V,
or use the clipboard icon in the menu bar.

### If macOS says the app is damaged or from an unidentified developer

Unsigned builds trip Gatekeeper. Either right-click the app → **Open**, or:

```bash
xattr -dr com.apple.quarantine /Applications/Cache.app
```

To stop macOS re-asking for permissions on every rebuild, see
[PERMISSIONS.md](PERMISSIONS.md) — a free self-signed certificate fixes it.

---

## Screenshots

Cache reads your macOS screenshot location from
`com.apple.screencapture location` — the folder set in the Screenshot app
(⇧⌘5 → Options) — so it follows wherever you save them: Desktop,
`~/Screenshots`, a Dropbox folder, anywhere. Move it and Cache follows within a
few seconds, without a restart. Tools that save somewhere else, like CleanShot,
can be pointed at with **Settings → Screenshots → Choose Folder…**

In a folder of its own, every new picture counts as a screenshot. In a folder
you keep other things in, like the Desktop, only real screen captures are filed.

If macOS is blocking the folder, the notch says so and **Allow Access** takes you
straight to the setting. Prefer not to grant access at all? Point macOS
somewhere unprotected and no permission is needed:

```bash
mkdir -p ~/Screenshots
defaults write com.apple.screencapture location ~/Screenshots
killall SystemUIServer
```

---

## Privacy

Passwords are never saved — items marked concealed by password managers are
skipped before they are read. Everything is stored locally. There is no network
access of any kind, and no keystroke monitoring.

Full detail in [PRIVACY.md](PRIVACY.md) and [PERMISSIONS.md](PERMISSIONS.md).

---

## Keyboard

| | |
|---|---|
| `⌃⌘V` | Open Cache with the search field ready (configurable) |
| `←` `→` | Move between cards |
| `⏎` | Copy the selected card |
| `⌘1` – `⌘9` | Copy one of the first nine cards (hold `⌘` to see which) |
| `Space` | Preview the selected card |
| `⌘⌫` | Delete the selected card |
| `⌘F` | Search |
| `Esc` | Close the preview, then clear the search, then close |

Click a card to copy it; the panel gets out of the way so `⌘V` lands where you
were working. Drag a card out to drop it into any app. Right-click for everything
else.

---

## Built with

Swift · SwiftUI · AppKit · SwiftData · Vision · FSEvents ·
[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)

Project files are generated by [XcodeGen](https://github.com/yonaskolb/XcodeGen)
from `project.yml` — do not edit the `.xcodeproj` directly, it is regenerated.

## Licence

MIT. See [LICENSE](LICENSE).
