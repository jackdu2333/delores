#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/delores-geometry-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

swiftc \
    -swift-version 6 \
    -O \
    -o "$TEMP_DIR/delores-geometry-test" \
    "$ROOT/Tinycast/Features/WindowManagement/Model/WindowCommand.swift" \
    "$ROOT/Tinycast/Features/WindowManagement/Model/WindowCycle.swift" \
    "$ROOT/Tinycast/Features/WindowManagement/Model/WindowPlacementEngine.swift" \
    "$ROOT/Tinycast/Features/Delores/Model/DeloresSnapGeometry.swift" \
    "$ROOT/Tinycast/Features/Delores/Model/DeloresDividerGeometry.swift" \
    "$ROOT/Tests/delores-geometry-test.swift"

"$TEMP_DIR/delores-geometry-test"
