#!/bin/bash
# lane-status.sh — right-side tmux status segment for the MOSAIC cockpit.
# Shows the current deploy-lock holder (the one lane that may aps deploy right now),
# and the count of active lanes recorded in LANES.md. Cheap; runs on tmux's status
# refresh interval. Prints a single line.

set -euo pipefail

proj="/Volumes/workplace"
lock="$proj/.claude/deploy.lock"
ledger="$proj/openspec/LANES.md"

# Deploy-lock holder.
if [ -f "$lock" ]; then
  holder="$(head -n1 "$lock" 2>/dev/null || echo '?')"
  lockseg="deploy:$holder"
else
  lockseg="deploy:free"
fi

# Active lane rows in LANES.md (table rows that aren't the header/separator/placeholder).
lanes="?"
if [ -f "$ledger" ]; then
  lanes="$(awk -F'|' '
    /<!--/ { incomment=1 }
    /-->/  { incomment=0; next }
    incomment { next }
    /^\| *[a-z0-9]/ && $0 !~ /Lane \(change\)/ && $0 !~ /_\(none active\)_/ && $0 !~ /^\|[- ]+\|/ { n++ }
    END { print n+0 }
  ' "$ledger" 2>/dev/null || echo '?')"
fi

printf 'lanes:%s  %s' "$lanes" "$lockseg"
