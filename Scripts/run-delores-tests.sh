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
    "$ROOT/Tinycast/Features/Delores/Model/ContextAnswerAccumulator.swift" \
    "$ROOT/Tinycast/Features/Delores/Model/ActionSession.swift" \
    "$ROOT/Tinycast/Features/AI/Model/JSONValue.swift" \
    "$ROOT/Tinycast/Features/AI/Model/AITool.swift" \
    "$ROOT/Tinycast/Features/AI/Model/AIRequest.swift" \
    "$ROOT/Tinycast/Features/AI/Service/AIProvider.swift" \
    "$ROOT/Tinycast/Features/Delores/Service/ActionSessionRunner.swift" \
    "$ROOT/Tinycast/Features/Delores/Model/ActionConversation.swift" \
    "$ROOT/Tinycast/Features/Delores/Model/ActionDefinition.swift" \
    "$ROOT/Tinycast/Features/Delores/Model/ContextIslandPlacement.swift" \
    "$ROOT/Tinycast/Features/Delores/Model/SelectionGesturePolicy.swift" \
    "$ROOT/Tinycast/Features/Delores/Model/OwnSurfaceHitPolicy.swift" \
    "$ROOT/Tinycast/Features/QuickActions/Model/QuickActionStartResult.swift" \
    "$ROOT/Tinycast/Features/QuickActions/Model/CustomQuickAction.swift" \
    "$ROOT/Tinycast/Features/QuickActions/Model/QuickAction.swift" \
    "$ROOT/Tinycast/Features/QuickActions/Model/QuickActionPrompt.swift" \
    "$ROOT/Tests/delores-context-test.swift"

"$TEMP_DIR/delores-context-test"
