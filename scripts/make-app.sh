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
# on every build. Select by SHA-1 hash and skip any revoked cert — a
# revoked identity makes Gatekeeper flag the app as malware and trash
# it, and name-based selection is ambiguous when a stale revoked cert
# shares its name with the current one.
IDENTITY=$(security find-identity -v -p codesigning \
  | grep "Apple Development" | grep -v "CSSMERR" \
  | head -1 | awk '{print $2}')
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed: ${IDENTITY:-ad-hoc})"
