#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/delores-upstream-drift.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

git init -q "$TEMP_DIR"
git -C "$TEMP_DIR" config user.email "delores-test@example.invalid"
git -C "$TEMP_DIR" config user.name "Delores Test"
git -C "$TEMP_DIR" commit --allow-empty -qm "base"
BASE="$(git -C "$TEMP_DIR" rev-parse HEAD)"
git -C "$TEMP_DIR" commit --allow-empty -qm "upstream change"
git -C "$TEMP_DIR" update-ref refs/remotes/upstream/main HEAD
git -C "$TEMP_DIR" reset --hard -q "$BASE"

set +e
OUTPUT="$(DELORES_REPO_ROOT="$TEMP_DIR" UPSTREAM_REF=upstream/main \
    "$ROOT/Scripts/check-upstream-drift.sh" 2>&1)"
STATUS=$?
set -e

if [ "$STATUS" -ne 1 ]; then
    echo "$OUTPUT" >&2
    echo "expected drift check to exit 1, got $STATUS" >&2
    exit 1
fi
grep -Fq "upstream commits not yet merged: 1" <<<"$OUTPUT"
grep -Fq "upstream change" <<<"$OUTPUT"
echo "Upstream drift regression test passed"
