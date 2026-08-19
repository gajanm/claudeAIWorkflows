#!/bin/bash
# lane.sh — launch a MOSAIC parallel lane in its own tmux window.
#
# Usage:
#   lane.sh <lane-name> [start-dir] [--no-attach]
#
#   <lane-name>   the OpenSpec change name — becomes the tmux window name AND `claude --name`.
#   [start-dir]   optional dir to cd into. Defaults to the workspace root (/Volumes/workplace).
#                 For a package-isolated lane, pass its worktree/package path.
#   --no-attach   create the window but do NOT attach (used by the generated multi-lane
#                 launcher, which creates every window then attaches ONCE at the end).
#
# Behavior:
#   - Ensures a tmux session "mosaic" exists (creates it detached if not).
#   - Opens a new window named <lane-name> in that session, cd'd to start-dir.
#   - Starts `claude --name <lane-name>` in the window.
#   - Attaches you to the session (unless --no-attach), or switches if already inside tmux.
#
# Each lane's cwd = its window's dir, so the notification/lock/log hooks identify the
# lane correctly, and `git diff` in that window shows only that lane's package changes.

set -euo pipefail

proj="/Volumes/workplace"
session="mosaic"

# Parse args: first non-flag = lane, second non-flag = start-dir, --no-attach = flag.
lane=""; startdir=""; no_attach=0
for a in "$@"; do
  case "$a" in
    --no-attach) no_attach=1 ;;
    *) if [ -z "$lane" ]; then lane="$a"; elif [ -z "$startdir" ]; then startdir="$a"; fi ;;
  esac
done

if [ -z "$lane" ]; then
  echo "usage: lane.sh <lane-name> [start-dir] [--no-attach]" >&2
  exit 1
fi

[ -z "$startdir" ] && startdir="$proj"
# Resolve relative start-dir against the project root.
case "$startdir" in
  /*) : ;;                       # absolute — keep
  *)  startdir="$proj/$startdir" ;;
esac
if [ ! -d "$startdir" ]; then
  echo "lane.sh: start-dir does not exist: $startdir" >&2
  exit 1
fi

command -v tmux >/dev/null 2>&1 || { echo "lane.sh: tmux not installed (brew install tmux)" >&2; exit 1; }

# Cockpit look: status bar shows lane count + deploy-lock holder; windows are named +
# color-coded (active window highlighted) so you can tell lanes apart at a glance.
configure_cockpit() {
  tmux set-option -t "$session" status-interval 5 2>/dev/null || true
  tmux set-option -t "$session" status-right " #(~/.claude/scripts/lane-status.sh) " 2>/dev/null || true
  tmux set-option -t "$session" status-right-length 60 2>/dev/null || true
  tmux set-option -t "$session" status-left "[mosaic] " 2>/dev/null || true
  # Per-window: plain for inactive, bright/reverse for the current lane.
  tmux set-option -t "$session" window-status-format " #W " 2>/dev/null || true
  tmux set-option -t "$session" window-status-current-format " #W " 2>/dev/null || true
  tmux set-option -t "$session" window-status-current-style "bg=colour4,fg=colour15,bold" 2>/dev/null || true
  tmux set-option -t "$session" window-status-style "fg=colour245" 2>/dev/null || true
}

# Ensure the session exists (detached).
if ! tmux has-session -t "$session" 2>/dev/null; then
  tmux new-session -d -s "$session" -n "$lane" -c "$startdir"
  configure_cockpit
  tmux send-keys -t "$session:$lane" "claude --name '$lane'" C-m
else
  # New window for this lane.
  tmux new-window -t "$session" -n "$lane" -c "$startdir"
  configure_cockpit
  tmux send-keys -t "$session:$lane" "claude --name '$lane'" C-m
fi

# Attach unless told not to (the multi-lane launcher attaches once at the end itself).
if [ "$no_attach" -eq 1 ]; then
  echo "lane '$lane' created in session '$session' (not attached)"
  exit 0
fi
if [ -n "${TMUX:-}" ]; then
  tmux switch-client -t "$session"
else
  tmux attach-session -t "$session"
fi
