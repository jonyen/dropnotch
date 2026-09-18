#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/DropNotch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DropNotch "$APP/Contents/MacOS/DropNotch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# The icon is committed, not generated here: regenerate with `swift run IconGen`.
# Missing it is fatal — an icon-less bundle looks untrustworthy in exactly the
# System Settings panes where the user grants screen and accessibility access,
# and that failure stays invisible until someone opens them.
if [ ! -f Resources/DropNotch.icns ]; then
  echo "error: Resources/DropNotch.icns missing (run: swift run IconGen)" >&2
  exit 1
fi
cp Resources/DropNotch.icns "$APP/Contents/Resources/DropNotch.icns"
# Prefer a real identity: its designated requirement is stable across
# rebuilds, so TCC permission grants survive. Ad-hoc (-) resets them
# on every build. Select by SHA-1 hash. spctl can't gate candidates —
# it rejects every non-notarized app, dev-signed included, which
# silently forced ad-hoc on every build. Instead verify the signed
# leaf cert over OCSP: `security find-identity` shows locally-revoked
# certs but not server-revoked ones, and a server-revoked cert makes
# Gatekeeper kill the app at spawn and trash the bundle (macOS 15.1+).
# A revoked cert also signs without embedding a chain, so extraction
# yielding no leaf is itself a rejection.
SIGNED=false
CERTDIR=$(mktemp -d)
trap 'rm -rf "$CERTDIR"' EXIT
for IDENTITY in $(security find-identity -v -p codesigning \
  | grep "Apple Development" | grep -v "CSSMERR" | awk '{print $2}'); do
  rm -f "$CERTDIR"/leaf_*
  if codesign --force --sign "$IDENTITY" "$APP" 2>/dev/null \
    && codesign -d --extract-certificates="$CERTDIR/leaf_" "$APP" 2>/dev/null \
    && [ -f "$CERTDIR/leaf_0" ] \
    && security verify-cert -c "$CERTDIR/leaf_0" -p codeSign -R ocsp >/dev/null 2>&1; then
    echo "Built $APP (signed: $IDENTITY)"
    SIGNED=true
    break
  fi
done
if [ "$SIGNED" = false ]; then
  codesign --force --sign - "$APP"
  echo "Built $APP (signed: ad-hoc — no valid Apple Development cert; TCC grants reset on rebuild)"
fi
