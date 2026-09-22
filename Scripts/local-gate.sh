#!/usr/bin/env bash
# Run, on this machine, everything `.github/workflows/ci.yml` runs — plus the two checks it does not.
#
# Why this exists: on 2026-09-19 GitHub stopped starting jobs here, because the repository is private
# and its Actions minutes are metered (the run at 08:20Z did not fail a check, it never got a runner —
# docs/delores-verification.md). The checks were never about building the app; the DMG has always been
# built on this Mac. What CI contributed was a *second executor on a clean checkout*, and only its
# second half can be reproduced locally — `--clean` is that half.
#
# Usage:
#   ./Scripts/local-gate.sh              # everything below, in the local working tree
#   ./Scripts/local-gate.sh --clean      # same, in a throwaway worktree of HEAD
#   ./Scripts/local-gate.sh --no-build   # skip the Debug build while iterating
#
# Unlike CI, this does not stop at the first failure: a local run should tell you everything that is
# wrong at once. The exit status is 1 if any check that ran failed.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

CLEAN=0
BUILD=1
for arg in "$@"; do
    case "$arg" in
        --clean) CLEAN=1 ;;
        --no-build) BUILD=0 ;;
        *) echo "✗ unknown argument: $arg" >&2; exit 2 ;;
    esac
done

if [ -d /Applications/Xcode.app/Contents/Developer ]; then
    DELORES_DEFAULT_DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
else
    DELORES_DEFAULT_DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-$DELORES_DEFAULT_DEVELOPER_DIR}"

if [ "$CLEAN" = 1 ]; then
    # A worktree of HEAD shares the object database and carries *nothing* untracked, which is the
    # property under test: a file that exists only in the working tree, an uncommitted edit, or a
    # script whose exec bit was never added all pass in place and fail here. That last one is not
    # hypothetical — `Tests/upstream-drift-test.sh` had no exec bit and the regression it guards had
    # never run anywhere.
    ORIGIN="$(pwd)"
    ROOT="$(mktemp -d)"
    WORKTREE="$ROOT/delores-clean"
    trap 'cd "$ORIGIN" 2>/dev/null; git worktree remove --force "$WORKTREE" >/dev/null 2>&1; rm -rf "$ROOT"' EXIT
    if ! PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:$PATH" git worktree add --detach "$WORKTREE" HEAD >/dev/null; then
        echo "✗ could not create a worktree of HEAD" >&2
        exit 1
    fi
    cd "$WORKTREE" || exit 1
    echo "▸ Clean worktree of $(git rev-parse --short HEAD) — nothing uncommitted, nothing untracked"
else
    echo "▸ Working tree at $(git rev-parse --short HEAD 2>/dev/null || echo 'not a git tree')"
fi

TOOLCHAIN_VERSION="$(xcodebuild -version 2>/dev/null | head -1 || true)"
[ -n "$TOOLCHAIN_VERSION" ] || TOOLCHAIN_VERSION="Xcode unavailable ($DEVELOPER_DIR)"
echo "▸ $TOOLCHAIN_VERSION, SDK $(xcrun --sdk macosx --show-sdk-version)"
echo

FAILED=()
CANNOT=()

step() {
    local name="$1"; shift
    printf '▸ %s\n' "$name"
    if "$@"; then
        printf '✓ %s\n\n' "$name"
    else
        printf '✗ %s\n\n' "$name"
        FAILED+=("$name")
    fi
}

step "Harnesses"        ./Scripts/run-tests.sh
step "Delores harness"  ./Scripts/run-delores-tests.sh
step "Delores geometry" ./Scripts/run-delores-geometry-tests.sh
step "Upstream drift"   ./Tests/upstream-drift-test.sh
step "Product boundaries" ./Scripts/check-product-boundaries.sh

# CI skips this harness when its runner's SDK is older than the one the vendored snapshot needs. The
# guard is kept rather than dropped: this machine has SDK 27 today, and the check is worth running the
# day it does not.
SDK="$(xcrun --sdk macosx --show-sdk-version)"
if [ "${SDK%%.*}" -lt 27 ]; then
    echo "▸ Vendored Huaci harness"
    echo "— skipped: needs the macOS 27 SDK, this machine has $SDK"
    CANNOT+=("Vendored Huaci harness (SDK $SDK)")
else
    step "Vendored Huaci harness" ./Scripts/run-huaci-integration-tests.sh
fi

# The purity grep is in the definition of done (docs/testing.md) and CI has never run it.
printf '▸ Pure-layer purity\n'
if grep -rln 'import AppKit\|import SwiftUI\|import Cocoa' Tinycast/Features/*/Model/ 2>/dev/null; then
    printf '✗ Pure-layer purity — the files above import a UI framework in Model/\n\n'
    FAILED+=("Pure-layer purity")
else
    printf '✓ Pure-layer purity\n\n'
fi

if [ "$BUILD" = 1 ]; then
    printf '▸ Debug build\n'
    # Same flags CI uses: unsigned and Debug, because this proves the target compiles and nothing here
    # ships. Every harness compiles a *subset* of the sources, so target membership, a missing
    # resource and a broken generated project are invisible to a green harness run.
    if xcodebuild -project Tinycast.xcodeproj -scheme Delores -configuration Debug \
        -derivedDataPath build/DerivedData ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
        CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS="" \
        CODE_SIGNING_ALLOWED=NO build > /tmp/local-gate-build.log 2>&1; then
        WARNINGS="$(grep -c ' warning: ' /tmp/local-gate-build.log || true)"
        printf '✓ Debug build (%s warning line(s), full log /tmp/local-gate-build.log)\n\n' "$WARNINGS"
    else
        printf '✗ Debug build — last lines:\n'
        tail -20 /tmp/local-gate-build.log
        printf '\n'
        FAILED+=("Debug build")
    fi
fi

# Lint is a *script*, and it checks three things: SwiftLint, the settings-search catalog and the
# localization catalogs. Only the first needs installing, so a missing SwiftLint is reported as a
# check that could not run rather than as a pass — the two node checks are run directly instead of
# being lost with it.
if command -v swiftlint >/dev/null; then
    step "Lint" env TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-$DEVELOPER_DIR}" ./Scripts/lint.sh
else
    echo "▸ Lint"
    echo "— cannot run: swiftlint is not installed.  brew install swiftlint"
    echo "  Running the two checks inside lint.sh that do not need it:"
    CANNOT+=("Lint (swiftlint not installed)")
    step "Settings search" node Scripts/check-settings-search.js
    step "Localization"    node Scripts/check-localization.js
fi

echo "────────────────────────────────────────"
if [ ${#CANNOT[@]} -gt 0 ]; then
    echo "Could not run:"
    printf '  — %s\n' "${CANNOT[@]}"
fi
if [ ${#FAILED[@]} -gt 0 ]; then
    echo "Failed:"
    printf '  ✗ %s\n' "${FAILED[@]}"
    exit 1
fi
echo "✓ every check that ran passed"
