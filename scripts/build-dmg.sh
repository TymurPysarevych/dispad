#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-dev}"
OUT="dist/DispadHost-${VERSION}.dmg"
BUILD_DIR="build/Release"
APP="${BUILD_DIR}/DispadHost.app"

rm -rf "$BUILD_DIR" dist
mkdir -p "$BUILD_DIR" dist

./scripts/bootstrap.sh

xcodebuild \
  -workspace Dispad.xcworkspace \
  -scheme DispadHost \
  -configuration Release \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  CONFIGURATION_BUILD_DIR="$(pwd)/${BUILD_DIR}" \
  build

# Ad-hoc sign so Gatekeeper's hardened-runtime enforcement is satisfied.
codesign --force --deep --sign - "$APP"

# create-dmg refuses to overwrite an existing DMG. dist/ was just rm'd, so
# the file shouldn't exist, but guard anyway.
rm -f "$OUT"

# Lay out a 540x380 window with the .app on the left and an Applications
# symlink on the right. Users see exactly what to do: drag from left to
# right.
create-dmg \
  --volname "dispad ${VERSION}" \
  --window-pos 200 120 \
  --window-size 540 380 \
  --icon-size 128 \
  --icon "DispadHost.app" 140 200 \
  --app-drop-link 400 200 \
  --hdiutil-quiet \
  --no-internet-enable \
  "$OUT" \
  "$APP"

echo "Built: $OUT"
