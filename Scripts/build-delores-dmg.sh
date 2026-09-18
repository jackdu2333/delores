#!/usr/bin/env bash
# Build a signed Delores.app into build/Delores-<version>.dmg.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
IDENTITY="${DELORES_CODE_SIGN_IDENTITY:-HuaciGongju CodeSign}"
DERIVED="build/DeloresDerivedData"

if ! security find-identity -p codesigning | grep -Fq "$IDENTITY"; then
    echo "✗ '$IDENTITY' code-signing identity not found — see docs/delores-release.md." >&2
    exit 1
fi

BUILD_ARGS=(
    -project Tinycast.xcodeproj
    -scheme Delores
    -configuration Release
    -derivedDataPath "$DERIVED"
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$IDENTITY"
    OTHER_CODE_SIGN_FLAGS=--timestamp=none
)
if [ "$#" -gt 0 ]; then
    BUILD_ARGS+=("MARKETING_VERSION=$1")
fi

echo "▸ Building signed Delores.app (Release)…"
xcodebuild "${BUILD_ARGS[@]}" build

APP="$DERIVED/Build/Products/Release/Delores.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/Delores-${VERSION}.dmg"

# The verifier owns every signature rule, so it runs before anything is packaged: a DMG carrying a
# build it would reject is worse than no DMG, because the failure only shows up at launch.
echo "▸ Verifying ${APP##*/}…"
./Scripts/verify-signature.sh "$APP"

echo "▸ Packaging ${DMG}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
diskutil image create from "$STAGE" --format UDZO --volumeName "Delores" "$DMG" >/dev/null

echo "✓ $DMG"
