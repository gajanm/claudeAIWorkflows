---
name: my-crs
description: Audit and service the CRs YOU authored on code.amazon.com. With no argument, prints a read-only badged action list. With a CR id, drives the address-comments → amend → raise-revision loop (all outward-facing steps gated on explicit approval). Adapted from Vincente_AI_Prompts' check-crs, narrowed to authored CRs.
---

Service your **authored** code reviews. Two modes: audit (no arg, read-only) and work-one (CR id).

Uses the static helper `~/.claude/scripts/cr_extract.py` to parse CRUX pages. Do NOT use inline
Python heredocs (`python3 -c` / `<< EOF`) — they trip shape-based security warnings. Only call
the static script.

## Step 1 — Identify me  [auto]
Run `git config user.email` and strip `@amazon.com`. Bind to `$ME`. Do not run `whoami`.

## Step 2 — Fetch my authored queue  [auto, read-only]
Single `mcp__builder-mcp__ReadInternalWebsites` call to:
- `https://code.amazon.com/reviews/from-user/$ME`   (CRs I authored)

Extract `CR-<id>` ids via regex on the inline content. If empty → `No authored CRs. All clear.` and stop.

(Scope note: this command is authored-CR only — the `to-user/$ME` reviewer queue is intentionally
out of scope. That's the deferred `/auto-cr` side.)

## Step 3 — Fetch each CR's detail page  [auto, read-only]
For every CR id, call `ReadInternalWebsites` with
`https://code.amazon.com/reviews/<CR-ID>?include-all-comments=true`. Batch all URLs in one call.
Capture the persisted JSON path per CR (if a small CR comes back inline, write it to `/tmp/cr_<id>.json`).

## Step 4 — Extract structured data  [auto]
For each persisted path run:
```
python3 ~/.claude/scripts/cr_extract.py <path> $ME
```
Parse the compact JSON: `cr_id, title, author, current_revision, url, i_approved_current,
next_actions, comments[]`. `next_actions` is CRUX's authoritative "whose turn" map. **Ignore
`CANCEL_STALE_CR`** entirely (latent capability, not a real action).

---

## Mode A — audit (no CR id given): read-only action list

Apply filtering for CRs I authored:

**From `next_actions` (drop `CANCEL_STALE_CR`), entries where `user == $ME`:**
- `MERGE_CR` → 🟢 **ME → merge** (approved, ready to ship)
- `ADDRESS_FAILED_ANALYZERS` → 🟠 **ME → fix analyzers**
- `ADDRESS_COMMENTS` → continue to comment scan
- `ASSIGN_REVIEWERS` → 🔴 **ME → assign reviewers**
- any other → 🔴 with the action name

**Comment-based soft signals** (scan non-CoverlayWorker comments, ordered by `created_at` within
each `location` bucket):
- `fixed` true → skip.
- author is me AND no later comment from someone else in that bucket → skip (my own note).
- author is someone else (human or AutoSDE) AND I have not replied later in that bucket →
  🔵 **ME → reply**.

Output — single punch list, no prose before/after:
```
## Action items — authored CRs

Mine — N:
- 🟢 [CR-xxxxxxxx](https://code.amazon.com/reviews/CR-xxxxxxxx) — approved, ready to merge
- 🟠 [CR-xxxxxxxx](https://code.amazon.com/reviews/CR-xxxxxxxx) — fix failing analyzers
- 🔵 [CR-xxxxxxxx](https://code.amazon.com/reviews/CR-xxxxxxxx) — N comment(s) to reply to

Awaiting others — N:
- ⏳ [CR-xxxxxxxx](https://code.amazon.com/reviews/CR-xxxxxxxx) — <reviewer> hasn't replied to N comment(s)
```
Rules: markdown links with full URLs (clickable). Omit empty groups. Both empty → `All clear.`
Do not narrate the filtering. This mode is READ-ONLY — no posting, no edits.

---

## Mode B — work one CR (`/my-crs CR-xxxxxxxx`)

Drive the respond loop for that one CR. Correlate it to a milestone by matching its URL against the
`CR:` header in `openspec/changes/*/proposal.md` (report which milestone it belongs to).

### B1 — Summarize each unaddressed comment  [auto, read-only]
For each open reviewer comment (not `fixed`, not mine, no later reply from me), state: location,
what the reviewer wants, and whether it's a code change, a question, or a discussion point.

### B2 — Draft the fixes locally  🟡 soft gate
- For comments that are clear code changes, make the edits in the CR's local branch.
- **Show the diff and the intended reply per thread before proceeding.** This is a soft checkpoint —
  the user eyeballs the changes before anything is amended or sent.

### B3 — Verify  [auto]
Run `brazil-build release` in the affected package(s). Iterate on failures. If the change touches
CDK/deployable resources, note that a redeploy is needed (see B4).

### B4 — Redeploy if CDK  🔴 GATE (deploy)
Only if the fix changed deployable resources. Echo the exact command, get approval, then:
`aps deploy <stack-id> --pipeline <pipeline> --stack <STACK_NAME> --profile <profile>`
(`gajanmoh-guv` / `gajanmoh-guv-admin-creds` for SpiMosaicVending; `gajanmoh-dis` /
`gajanmoh-dis-admin-creds` for SpiMosaic). Full CloudFormation deploy — no hotswap. Verify success.

### B5 — Amend the commit  [auto]
Amend into the single branch commit (one commit per CR — never add `fix(...)` commits). Local, reversible.

### B6 — Raise the revision  🔴 GATE (outward-facing)
Echo the exact command, get explicit approval, then run:
```
cr --update-review <CR-ID>
```
This publishes a new revision and re-notifies reviewers. Never run without a yes.

### B7 — Post replies to threads  🔴 GATE (outward-facing)
Draft replies for each addressed thread (e.g. "done in r<n>", or a reasoned push-back). Post as
**drafts by default** (`publish=false`). Only publish on explicit "publish" instruction. No AI-marker
in the body (CRUX appends one server-side).

### B8 — Report
Summarize what was addressed, the new revision number, and remaining open threads. If the CR is now
fully approved, remind the user: merge is a separate 🔴 gate, and only after merge does the milestone
flip to 🟢 (via `/milestone`).

---

## Constraints (recap)
- Authored CRs only (`from-user/$ME`).
- Gates: B2 soft (show before amend); B4, B6, B7 hard (deploy, raise revision, publish replies).
- Everything read-only until a gate is passed. Echo exact commands before running gated ones.
- One commit per CR. No `python3 -c` / heredocs — only the static script. Batch tool calls.
- Never self-approve or self-merge. Identity via `git config user.email` only.
