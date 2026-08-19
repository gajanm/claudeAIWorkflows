#!/bin/bash
# lane-bash-log.sh — PreToolUse (Bash) hook. Appends every bash command to a per-lane
# audit log. Cheap trail for unattended auto-mode lanes. Never blocks.
#
# Log: <project>/.claude/logs/bash-<lane>.log

set -euo pipefail

payload="$(cat 2>/dev/null || true)"
[ -z "$payload" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -z "$cmd" ] && exit 0
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -z "$cwd" ] && cwd="$(pwd)"

lane="$(basename "$cwd")"
case "$cwd" in */worktrees/*) lane="$(printf '%s' "$cwd" | sed -E 's#.*/worktrees/([^/]+)/.*#\1#')" ;; esac

logdir="/Volumes/workplace/.claude/logs"
mkdir -p "$logdir" 2>/dev/null || true
# Timestamp without Date.now issues — `date` in the shell is fine here.
printf '%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$cmd" >> "$logdir/bash-$lane.log" 2>/dev/null || true
exit 0
