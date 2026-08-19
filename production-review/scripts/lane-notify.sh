#!/bin/bash
# lane-notify.sh — macOS notification for MOSAIC parallel lanes.
# Wired to Claude Code PermissionRequest + Stop hooks (see .claude/settings.json).
#
# Hooks pass their JSON payload on stdin. The lane's custom --name is NOT available
# to these hook events, so we derive the lane identity from `cwd`: each lane runs in
# its own package/worktree dir, so the directory name IS the lane.
#
# Usage (from a hook):  lane-notify.sh <kind>
#   input   — PermissionRequest: a gate is waiting → banner (Ping)
#   idle    — Notification/idle_prompt: lane done, waiting for you → banner (Glass)
#   release — Stop: every turn end → SILENT, only releases the deploy-lock (no banner,
#             so a 20-turn auto-mode lane doesn't spam 20 notifications)

set -euo pipefail

kind="${1:-release}"

# Read the hook payload from stdin (may be empty if invoked manually).
payload="$(cat 2>/dev/null || true)"

cwd=""
if [ -n "$payload" ] && command -v jq >/dev/null 2>&1; then
  cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true)"
fi
[ -z "$cwd" ] && cwd="$(pwd)"

# Lane label: prefer a worktree lane name (worktrees/<lane>/<Pkg>), else the dir basename.
lane="$(basename "$cwd")"
case "$cwd" in
  */worktrees/*) lane="$(printf '%s' "$cwd" | sed -E 's#.*/worktrees/([^/]+)/.*#\1#')" ;;
esac

# Every turn end (release) frees this lane's deploy lock if it holds it.
if [ "$kind" = "release" ] || [ "$kind" = "idle" ]; then
  lock="/Volumes/workplace/.claude/deploy.lock"
  if [ -f "$lock" ] && [ "$(head -n1 "$lock" 2>/dev/null)" = "$lane" ]; then
    rm -f "$lock" 2>/dev/null || true
  fi
fi

# release fires on EVERY turn end — silent (lock release only), no banner spam.
[ "$kind" = "release" ] && exit 0

case "$kind" in
  input) title="MOSAIC lane — needs input"; msg="$lane is waiting at a gate/permission"; sound="Ping" ;;
  idle)  title="MOSAIC lane — done";         msg="$lane finished, waiting for you";       sound="Glass" ;;
  *)     title="MOSAIC lane";                msg="$lane: $kind";                          sound="Glass" ;;
esac

# Escape double quotes for AppleScript.
esc() { printf '%s' "$1" | sed 's/"/\\"/g'; }

# Visual banner — works when Do Not Disturb / Focus is OFF.
osascript -e "display notification \"$(esc "$msg")\" with title \"$(esc "$title")\" sound name \"$sound\"" 2>/dev/null || true

# Audible fallback — plays even when DND/Focus suppresses the banner. `afplay` writes
# to the audio device directly, which Focus does not gate like notification banners.
# Different sound per event so you can tell "needs input" from "done" without looking.
case "$kind" in
  input) sfile="/System/Library/Sounds/Ping.aiff" ;;
  idle)  sfile="/System/Library/Sounds/Glass.aiff" ;;
  *)     sfile="/System/Library/Sounds/Glass.aiff" ;;
esac
[ -f "$sfile" ] && ( afplay "$sfile" >/dev/null 2>&1 & )
exit 0
