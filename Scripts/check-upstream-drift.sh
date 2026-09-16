#!/usr/bin/env bash
set -euo pipefail

ROOT="${DELORES_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

UPSTREAM_REF="${UPSTREAM_REF:-upstream/main}"
REF="refs/remotes/$UPSTREAM_REF"

if [ -n "$(git status --porcelain)" ]; then
    echo "注意：工作区存在未提交变更；漂移结果按当前 HEAD 计算。正式同步前必须先清洁工作区。" >&2
fi

if ! git show-ref --verify --quiet "$REF"; then
    echo "上游引用不存在: $UPSTREAM_REF" >&2
    echo "请先执行: git fetch upstream" >&2
    exit 2
fi

BASE="$(git merge-base HEAD "$UPSTREAM_REF")"
AHEAD="$(git rev-list --count "$UPSTREAM_REF..HEAD")"
BEHIND="$(git rev-list --count "HEAD..$UPSTREAM_REF")"

echo "upstream: $UPSTREAM_REF"
echo "merge-base: $BASE"
echo "Delores commits ahead: $AHEAD"
echo "upstream commits not yet merged: $BEHIND"

if [ "$BEHIND" -gt 0 ]; then
    echo
    echo "待同步的上游提交:"
    git log --oneline --decorate "HEAD..$UPSTREAM_REF"
    exit 1
fi

echo "上游已同步到当前 HEAD。"
