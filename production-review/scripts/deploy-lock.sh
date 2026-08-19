#!/bin/bash
# deploy-lock.sh — PreToolUse hook. Enforces serialized `aps deploy` across MOSAIC lanes.
# One personal stack per pipeline, so only ONE lane may deploy at a time.
#
# Reads the hook payload on stdin. If the Bash command is an `aps deploy` and another
# lane already holds the lock, DENY (exit 2 with a PreToolUse block). Otherwise acquire
# the lock (write lane+pid+time) and allow. The lock is released by the Stop hook.
#
# Lock file: <project>/.claude/deploy.lock

set -euo pipefail

payload="$(cat 2>/dev/null || true)"
[ -z "$payload" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -z "$cwd" ] && cwd="$(pwd)"

# Only act on `aps deploy` commands.
case "$cmd" in
  *"aps deploy"*) ;;
  *) exit 0 ;;
esac

# Project root = git-tracked workspace root; fall back to /Volumes/workplace.
proj="/Volumes/workplace"
lock="$proj/.claude/deploy.lock"

# Lane identity from cwd (worktree name or dir basename).
lane="$(basename "$cwd")"
case "$cwd" in */worktrees/*) lane="$(printf '%s' "$cwd" | sed -E 's#.*/worktrees/([^/]+)/.*#\1#')" ;; esac

if [ -f "$lock" ]; then
  holder="$(head -n1 "$lock" 2>/dev/null || echo unknown)"
  # If this same lane holds it, allow (re-deploy). Else block.
  if [ "$holder" != "$lane" ]; then
    reason="Deploy blocked: lane '$holder' holds the deploy lock ($lock). Only one aps deploy runs at a time (single personal stack). Wait for '$holder' to finish, or remove the lock if stale."
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$(printf '%s' "$reason" | jq -Rs .)"
    exit 0
  fi
else
  # Acquire the lock.
  printf '%s\n%s\n' "$lane" "pid=$$ cwd=$cwd" > "$lock" 2>/dev/null || true
fi
exit 0
