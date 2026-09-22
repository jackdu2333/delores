#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

failures=0

check_absent() {
    local label="$1"
    local pattern="$2"
    shift 2
    if rg -n "$pattern" "$@"; then
        printf 'FAIL: %s\n' "$label"
        failures=$((failures + 1))
    else
        printf 'PASS: %s\n' "$label"
    fi
}

check_present() {
    local label="$1"
    local pattern="$2"
    shift 2
    if rg -n "$pattern" "$@" >/dev/null; then
        printf 'PASS: %s\n' "$label"
    else
        printf 'FAIL: %s\n' "$label"
        failures=$((failures + 1))
    fi
}

check_absent "active target does not reference retired packs" 'Packs/LegacyFeatures' Tinycast
check_absent "active Window Management has no retired layout layer" \
    'WindowLayout(Store|Runner|Plan|Draft|Geometry|Anchor|Display|Screen|Window)' \
    Tinycast/Features/WindowManagement
check_absent "active target has no retired layout symbols" \
    'WindowLayout(Store|Runner|Display)|layoutScreens' Tinycast
check_present "README names three product surfaces" 'The Three Surfaces & Capabilities' README.md
check_present "README names Spatial Snap as a capability" 'Capability: Spatial Window Snap' README.md
check_absent "README has no fourth product surface" '### 4\. Command Surface' README.md
check_present "retired Window Management doc is archived" '^# Archived: Window Management' \
    docs/features/window-management.md
check_present "retired Window Layout doc is archived" '^# Archived: Window Layouts' \
    docs/features/window-layouts.md

if [ "$failures" -gt 0 ]; then
    printf '\n%d product-boundary check(s) failed\n' "$failures" >&2
    exit 1
fi
printf 'All product-boundary checks passed\n'
