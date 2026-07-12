#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/DropNotch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/DropNotch "$APP/Contents/MacOS/DropNotch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
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
