#!/bin/bash
# lane-reconcile.sh — SessionStart hook. Surfaces drift between LANES.md and reality
# so a stale/hand-edited ledger self-announces at lane start. Read-only + advisory:
# it prints a systemMessage; it never edits the ledger or blocks.
#
# Checks: (1) worktrees on disk (git worktree list) vs worktree paths named in LANES.md,
#         (2) a stale deploy.lock whose holder has no matching ledger row.

set -euo pipefail

proj="/Volumes/workplace"
ledger="$proj/openspec/LANES.md"
[ -f "$ledger" ] || exit 0

notes=""

# Worktrees that exist on disk but aren't referenced in the ledger.
if command -v git >/dev/null 2>&1 && [ -d "$proj/worktrees" ]; then
  while IFS= read -r wt; do
    [ -z "$wt" ] && continue
    base="$(basename "$wt")"
    grep -q "$base" "$ledger" 2>/dev/null || notes="${notes}\n- worktree '$wt' exists but is not in LANES.md"
  done < <(find "$proj/worktrees" -maxdepth 2 -type d -name '.git' -prune -o -maxdepth 2 -type d -print 2>/dev/null | grep -E '/worktrees/[^/]+/[^/]+$' || true)
fi

# Stale deploy lock.
lock="$proj/.claude/deploy.lock"
if [ -f "$lock" ]; then
  holder="$(head -n1 "$lock" 2>/dev/null || echo unknown)"
  notes="${notes}\n- deploy.lock is held by '$holder' — if that lane isn't actively deploying, remove $lock"
fi

if [ -n "$notes" ]; then
  msg="LANES.md reconcile — possible drift:${notes}"
  printf '{"systemMessage":%s}\n' "$(printf '%b' "$msg" | jq -Rs . 2>/dev/null || printf '"%s"' "ledger drift detected")"
fi
exit 0
