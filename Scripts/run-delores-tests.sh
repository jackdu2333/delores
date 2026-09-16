#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/delores-context-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

swiftc \
    -O \
    -o "$TEMP_DIR/delores-context-test" \
    "$ROOT/Tinycast/Features/QuickActions/Model/BuiltInQuickAction.swift" \
    "$ROOT/Tinycast/Features/Delores/Model/InvocationContext.swift" \
    "$ROOT/Tinycast/Features/Delores/Model/ContextAction.swift" \
    "$ROOT/Tinycast/Features/Delores/Model/SelectionContextPolicy.swift" \
    "$ROOT/Tinycast/Features/Delores/Model/ContextIslandPlacement.swift" \
    "$ROOT/Tinycast/Features/Delores/Model/SelectionGesturePolicy.swift" \
    "$ROOT/Tinycast/Features/Delores/Model/OwnSurfaceHitPolicy.swift" \
    "$ROOT/Tinycast/Features/QuickActions/Model/QuickActionStartResult.swift" \
    "$ROOT/Tests/delores-context-test.swift"

"$TEMP_DIR/delores-context-test"
