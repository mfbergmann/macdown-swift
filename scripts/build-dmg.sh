#!/usr/bin/env bash
#
# build-dmg.sh — package dist/MacDown.app into a drag-to-install .dmg.
#
# Run build-app.sh first (or let this script do it):
#     ./scripts/build-dmg.sh
#
# Environment overrides:
#     APP_NAME        App/display name          (default: MacDown)
#     VERSION         Marketing version string  (default: from the built app)
#     SIGN_IDENTITY   Developer ID identity     (default: auto-detected)
#     SKIP_BUILD      Set to 1 to package an existing dist/MacDown.app
#
set -euo pipefail

APP_NAME="${APP_NAME:-MacDown}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

if [ "${SKIP_BUILD:-0}" != "1" ]; then
    echo "==> Building the app first…"
    "$ROOT/scripts/build-app.sh"
fi

if [ ! -d "$APP" ]; then
    echo "!! $APP not found. Run scripts/build-app.sh first." >&2
    exit 1
fi

# Take the version from the app we're actually shipping, so the disk image and
# the bundle can never disagree.
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "$APP/Contents/Info.plist" 2>/dev/null || echo "0.0.0")}"

DMG="$DIST/$APP_NAME-$VERSION.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

echo "==> Staging $APP_NAME $VERSION…"
cp -R "$APP" "$STAGING/"
# The Applications symlink is what makes it a drag-to-install image.
ln -s /Applications "$STAGING/Applications"

echo "==> Creating disk image…"
rm -f "$DMG"
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG" >/dev/null

# Sign the image itself, so Gatekeeper is happy with the download as well as
# the app inside it.
if [ -z "${SIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" | head -1 \
        | sed -E 's/.*"(.*)".*/\1/')"
fi

if [ -n "${SIGN_IDENTITY:-}" ]; then
    echo "==> Signing disk image with: $SIGN_IDENTITY"
    codesign --force --sign "$SIGN_IDENTITY" "$DMG"
    codesign --verify --verbose=2 "$DMG"
else
    echo "==> No Developer ID found — the disk image is unsigned (local use only)."
fi

# Notarizing the .dmg staples the ticket to the image, so it opens cleanly even
# on a Mac that has never seen the app before.
if [ -n "${NOTARY_PROFILE:-}" ]; then
    if [ -z "${SIGN_IDENTITY:-}" ]; then
        echo "!! Notarization needs a Developer ID SIGN_IDENTITY. Skipping." >&2
    else
        echo "==> Submitting the disk image to Apple notary service…"
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        echo "==> Stapling ticket…"
        xcrun stapler staple "$DMG"
    fi
fi

SIZE="$(du -h "$DMG" | cut -f1)"
echo "==> Done: $DMG ($SIZE)"
