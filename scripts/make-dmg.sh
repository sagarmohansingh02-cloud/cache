#!/bin/bash
#
# Builds Cache and packages it as a drag-to-install DMG.
#
#   ./scripts/make-dmg.sh            build Release, then package
#   ./scripts/make-dmg.sh --no-build package whatever is already built
#
# Output: dist/Cache-<version>.dmg
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
DIST="$ROOT/dist"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

APP_NAME="Cache"
VERSION="$(/usr/bin/awk -F'"' '/CFBundleShortVersionString/ {print $2; exit}' project.yml)"
VERSION="${VERSION:-0.0.0}"
DMG="$DIST/${APP_NAME}-${VERSION}.dmg"

if [[ "${1:-}" != "--no-build" ]]; then
  echo "==> Generating the Xcode project"
  xcodegen generate

  echo "==> Building Release"
  xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "$APP_NAME" \
             -configuration Release build >/dev/null
fi

# Ask xcodebuild where it put things rather than guessing the DerivedData hash.
BUILD_DIR="$(xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "$APP_NAME" \
             -configuration Release -showBuildSettings 2>/dev/null \
             | awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $2; exit}')"
APP="$BUILD_DIR/${APP_NAME}.app"

if [[ ! -d "$APP" ]]; then
  echo "error: ${APP_NAME}.app not found at $APP" >&2
  echo "       run without --no-build, or build in Xcode first." >&2
  exit 1
fi

echo "==> Staging"
mkdir -p "$DIST"
cp -R "$APP" "$STAGE/"
# The Applications symlink is what makes it a drag-to-install disk image.
ln -s /Applications "$STAGE/Applications"

# A short read-me on the image itself, because the Gatekeeper warning on an
# unsigned build is the single thing most likely to make someone give up.
cat > "$STAGE/READ ME FIRST.txt" <<'TXT'
Cache — clipboard and screenshot history for macOS

INSTALL
  Drag Cache.app onto the Applications folder shown here.

FIRST LAUNCH
  This build is not signed with a paid Apple Developer certificate, so macOS
  will say it is from an unidentified developer.

  Right-click Cache.app in Applications and choose Open, then confirm.
  You only need to do this once.

  Or, in Terminal:
      xattr -dr com.apple.quarantine /Applications/Cache.app

THERE IS NO DOCK ICON
  Cache lives in the menu bar and the notch.
    - Move your pointer into the notch, or
    - Click the clipboard icon in the menu bar, or
    - Press Control-Command-V

  A Dock icon appears while the Library window is open.

PRIVACY
  Passwords are never saved. Everything stays on your Mac. No network
  requests, no account, no keystroke monitoring. Nothing is asked for at
  launch. See PRIVACY.md in the repository.

  https://github.com/sagarmohansingh02-cloud/cache
TXT

echo "==> Building the disk image"
rm -f "$DMG"
# UDZO is zlib-compressed and read-only, which is what a distributed DMG wants.
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" >/dev/null

echo "==> Verifying"
hdiutil verify "$DMG" >/dev/null && echo "    image verifies"

SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"

echo
echo "    $DMG"
echo "    size    $SIZE"
echo "    sha256  $SHA"
