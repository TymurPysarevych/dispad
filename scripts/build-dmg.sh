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

hdiutil create \
  -volname "dispad ${VERSION}" \
  -srcfolder "$APP" \
  -ov -format UDZO \
  "$OUT"

echo "Built: $OUT"
