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
# on every build.
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $2; exit}')
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed: ${IDENTITY:-ad-hoc})"
