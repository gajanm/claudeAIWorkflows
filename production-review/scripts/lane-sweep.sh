#!/bin/bash
# lane-sweep.sh — read-only status sweep of every lane branch/worktree across all MOSAIC
# packages, reconciled against openspec/LANES.md. Answers "what's the real state of
# everything" from git truth, so you never track it by memory. Never writes.
#
# For each package git repo it reports every non-mainline branch:
#   ahead/behind vs mainline · merged? · has a worktree? · matched CR from the ledger
# Then flags drift:
#   [MERGED-UNCLEAN]  merged into mainline but branch/worktree still on disk (cleanup debt)
#   [UNTRACKED]       branch exists but no ledger row names it
#   [GHOST]           ledger names a lane whose branch no longer exists
#
# Usage: lane-sweep.sh

set -uo pipefail
proj="/Volumes/workplace"
ledger="$proj/openspec/LANES.md"

# Packages to scan (all checked-out Brazil package repos).
pkgs=$(find "$proj"/SpiMosaic*/src -maxdepth 1 -mindepth 1 -type d 2>/dev/null)

# Ledger lane names (col 1, excluding the comment template).
ledger_lanes=""
[ -f "$ledger" ] && ledger_lanes=$(awk '/<!--/{c=1}/-->/{c=0;next}c{next}/^\| *[a-z0-9]/ && $0!~/Lane \(change\)/ && $0!~/none active/ && $0!~/^\|[- ]+\|/{gsub(/^ *\| */,"");sub(/ *\|.*/,"");print}' "$ledger")

seen_branches=""

printf '\n=== MOSAIC lane sweep ===\n'
for pkg in $pkgs; do
  ( cd "$pkg" 2>/dev/null || exit 0
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
    name=$(basename "$pkg")
    branches=$(git branch --format='%(refname:short)' 2>/dev/null | grep -v '^mainline$')
    [ -z "$branches" ] && exit 0
    printf '\n%s (on: %s)\n' "$name" "$(git branch --show-current)"
    wt_list=$(git worktree list 2>/dev/null)
    for b in $branches; do
      ahead=$(git rev-list --count "mainline..$b" 2>/dev/null || echo '?')
      behind=$(git rev-list --count "$b..mainline" 2>/dev/null || echo '?')
      if git branch --merged mainline 2>/dev/null | grep -q " $b$\|^\* $b$"; then merged="MERGED"; else merged="unmerged"; fi
      wt=$(printf '%s\n' "$wt_list" | grep -q "\[$b\]" && echo "wt" || echo "no-wt")
      # CR from ledger row for this branch name
      cr=$(grep -m1 "| $b " "$ledger" 2>/dev/null | grep -oE 'CR-[0-9]+' | head -1)
      [ -z "$cr" ] && cr="(no CR in ledger)"
      # drift flags
      flag=""
      if [ "$merged" = "MERGED" ]; then flag=" [MERGED-UNCLEAN: run git worktree remove + branch -d]"; fi
      if ! printf '%s\n' "$ledger_lanes" | grep -qx "$b"; then flag="$flag [UNTRACKED: not in ledger]"; fi
      printf '  %-32s +%s/-%s  %-8s %-5s  %s%s\n' "$b" "$ahead" "$behind" "$merged" "$wt" "$cr" "$flag"
    done
  )
done

# Ghosts: ledger lanes whose branch exists in no package.
printf '\n--- ledger vs disk ---\n'
if [ -n "$ledger_lanes" ]; then
  while IFS= read -r lane; do
    [ -z "$lane" ] && continue
    found=""
    for pkg in $pkgs; do ( cd "$pkg" 2>/dev/null && git rev-parse --verify "$lane" >/dev/null 2>&1 ) && { found=1; break; }; done
    [ -z "$found" ] && printf '  [GHOST] ledger lane "%s" has no branch on disk\n' "$lane"
  done <<< "$ledger_lanes"
fi
printf '\nTip: [MERGED-UNCLEAN] → clean up; [UNTRACKED] → add a ledger row or delete; [GHOST] → remove the ledger row.\n'
