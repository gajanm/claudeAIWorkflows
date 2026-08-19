#!/bin/bash
# lane-format.sh — PostToolUse (Write|Edit) hook. Auto-formats the edited file so
# `brazil-build release` lint doesn't fail. TS/JS → the package's local prettier+eslint;
# Python → black + isort. Silently no-ops on anything else or missing tools.
#
# Reads the hook payload on stdin; formats the single file that was written/edited.

set -euo pipefail

payload="$(cat 2>/dev/null || true)"
[ -z "$payload" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

f="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null || true)"
[ -z "$f" ] && exit 0
[ -f "$f" ] || exit 0

case "$f" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs)
    # Walk up to the package root (nearest package.json) and use its local bins.
    dir="$(dirname "$f")"
    while [ "$dir" != "/" ] && [ ! -f "$dir/package.json" ]; do dir="$(dirname "$dir")"; done
    if [ -x "$dir/node_modules/.bin/prettier" ]; then
      "$dir/node_modules/.bin/prettier" --write "$f" >/dev/null 2>&1 || true
    fi
    if [ -x "$dir/node_modules/.bin/eslint" ]; then
      "$dir/node_modules/.bin/eslint" --fix "$f" >/dev/null 2>&1 || true
    fi
    ;;
  *.py)
    command -v black >/dev/null 2>&1 && black -q "$f" >/dev/null 2>&1 || true
    command -v isort >/dev/null 2>&1 && isort "$f" >/dev/null 2>&1 || true
    ;;
esac
exit 0
