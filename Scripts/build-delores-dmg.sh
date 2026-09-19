#!/usr/bin/env bash
# Build a signed Delores.app into build/Delores-<version>.dmg.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
IDENTITY="${DELORES_CODE_SIGN_IDENTITY:-HuaciGongju CodeSign}"
DERIVED="build/DeloresDerivedData"

# Build is the source's serial number rather than a counter (docs/delores-versioning.md), so it is
# derived here instead of hand-written in `project.yml` — that value is only a fallback for a build
# that skips this script, and nothing asserts it. Full history is the whole point of the number: a
# shallow clone counts 1, which is why that is an error rather than a smaller number.
if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
    echo "✗ shallow clone — CFBundleVersion would be 1 instead of the commit count. Unshallow first." >&2
    exit 1
fi
BUILD_NUMBER="$(git rev-list --count HEAD)"

if ! security find-identity -p codesigning | grep -Fq "$IDENTITY"; then
    echo "✗ '$IDENTITY' code-signing identity not found — see docs/delores-release.md." >&2
    exit 1
fi

BUILD_ARGS=(
    -project Tinycast.xcodeproj
    -scheme Delores
    -configuration Release
    -derivedDataPath "$DERIVED"
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$IDENTITY"
    OTHER_CODE_SIGN_FLAGS=--timestamp=none
)
if [ "$#" -gt 0 ]; then
    BUILD_ARGS+=("MARKETING_VERSION=$1")
fi

echo "▸ Building signed Delores.app (Release, build $BUILD_NUMBER)…"
xcodebuild "${BUILD_ARGS[@]}" build

APP="$DERIVED/Build/Products/Release/Delores.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/Delores-${VERSION}.dmg"

# The Build reached the product or it did not, and a DMG that carries the fallback instead of the
# commit count is the exact failure this asserts against: the injection is a command-line argument, so
# nothing else in the build would notice it going missing.
BUILT_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
if [ "$BUILT_BUILD" != "$BUILD_NUMBER" ]; then
    echo "✗ built CFBundleVersion is $BUILT_BUILD, injected $BUILD_NUMBER — the Build did not reach the product." >&2
    exit 1
fi

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
