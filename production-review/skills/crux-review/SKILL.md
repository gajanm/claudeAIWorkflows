---
name: crux-review
description: Review an Amazon CRUX code review (code.amazon.com/reviews/CR-...) — apply CRUX-specific triage, comment formatting, and posting rules. Use when reviewing a CR, drafting CR comments, doing a pre-publish self-review of your own diff, or whenever a code.amazon.com/reviews URL is shared with a review request. Triggers include "review this CR", "review CR-...", "/crux-review", or any code.amazon.com/reviews/CR-... link. Also handles the "clean" argument to delete pulled CR workspaces.
---

# CRUX Code Review

Apply this flow before producing review feedback for any Amazon CRUX code review — including the pre-publish self-review of your own CR in the self-loop. CRUX is not GitHub — the built-in `/review` skill is GitHub-shaped and misses CRUX-specific context (the CR description, prior-CR follow-up callouts, severity tag conventions, server-side AI marker handling). Follow these rules in order, then proceed with normal review.

## 0. The `clean` argument — delete pulled CR workspaces

If the only argument is `clean` (no CR id), do not run any review flow. Instead, delete every `cr-pull`-created workspace under `$HOME/workspace/CR-*` and stop:

1. Enumerate candidates: `ls -d $HOME/workspace/CR-* 2>/dev/null`. If none, report "No CR workspaces to clean." and stop.
2. List them to the user before deleting (one tool call, no per-workspace confirmation prompt — `clean` is the explicit ask).
3. For each path, run `cd <path> && yes | brazil ws --delete` in a single Bash call. `brazil ws --delete` interactively asks for confirmation, and may ask a second time when the workspace has unpushed commits — piping `yes` answers both. Verify with `ls -d <path> 2>&1` after each delete.
4. Only delete directories matching the literal `CR-<digits>` pattern (and `CR-<digits>.r<n>bak` backup variants). Do not touch any other workspace.
5. Report the deleted set when finished.

Skip every other section when `clean` is the argument.

## 1. Read the description first — it is authoritative context

Before triaging the diff or drafting any comment, fetch the CR description and read it end-to-end. The description frequently:

- Calls out which changes are **follow-ups to prior CRs or comments**. Treat these as authoritative justification — do **not** raise a comment questioning a change the description already explains.
- Documents intentional behavior changes that look like bugs out of context.
- Lists assumptions the author wants reviewers to validate — these deserve a comment if you disagree, not silence.
- Names the testing strategy — use it to assess whether new test coverage actually exercises the new code paths.

If a draft comment you're about to post is already addressed by the description, drop it.

To fetch the description, use `mcp__builder-mcp__ReadInternalWebsites` against `https://code.amazon.com/reviews/CR-<id>` and read the `revisionDetails.revision.cr_revision.description` field.

## 2. Pull the CR locally — default to `cr-pull`, not the web diff

For any non-trivial CR (more than a couple of files, or a diff that may need cross-referencing sibling files / dependency code), pull the CR into a temporary workspace and review locally:

```bash
cd $HOME/workspace && cr-pull -w CR-<id>:<rev>
```

This clones the CR into `$HOME/workspace/CR-<id>/src/<PackageName>/` on a branch with base and tip set up for `git diff`. From there:

- **Diffs:** `git -P diff <base>...<head>`. Use `--stat` first to size the change.
- **Cross-file lookups:** `grep`/`find`/`Explore` across the workspace catches sibling-file inconsistencies the web diff hides.
- **Dependency source:** if the diff touches types defined in dependency packages, look them up in the pulled workspace.

Only fall back to `ReadInternalWebsites` against `code.amazon.com/reviews/...` for data not reconstructible locally — the description, structured comment threads, reviewer assignments, `next_actions`, the analyzer signal panel.

When *not* to pull: trivial single-file diffs where the web diff is enough.

### Verify before claiming "this is the only place"

When drafting a comment that asserts a pattern is *unique* to one location, grep across the whole pulled workspace before posting — including unit-test directories. Scope claims are easy to make from a small sample and embarrassing to retract.

## 3. Pick the right revision

CRUX URLs often pin a specific revision (`/revisions/N`). The latest revision is the source of truth — review against the latest unless the user explicitly asks about an older one. If the link points to an earlier revision, fetch the latest and note the discrepancy.

## 4. Write CR comments behaviorally, not by line reference

Focus on behavioral expectations and invariants, not implementation details that may drift during the same CR cycle:

- Prefer "this method must return X when Y" over "line 42 should call `foo.bar()`".
- Prefer "the contract is broken when Z" over "the if-block on line 17 is wrong".

**Comment on the system, not the author.** "The design lacks an error path for X" lands better than "You forgot to handle X". Non-blocking framing should sound like an invitation ("consider", "would it be worth"); blocking framing should sound like a declaration ("this breaks the contract").

**Ask, don't allege.** A question opens a dialogue and lets the author explain or self-correct without losing face.

- ❌ "This code does not do what you think it does." → ✅ "Will this still produce the right output when input is `(x, y)`?"
- ❌ "You're requesting the service multiple times, which is inefficient." → ✅ "This is requesting the service multiple times — is there a reason it can't be cached?"

Reserve declarations for findings you've verified against file:line evidence where the right answer is unambiguous.

**Cite a principle, or it's just taste.** Every substantive comment should tie back to something concrete — a convention used elsewhere, a documented standard, a behavioral failure mode, a measurable cost. If the only justification is your preference, find the principle or drop the comment.

**Aim for a letter-grade improvement, not perfection.** A CR has to leave better than it arrived, not at A+. Pick the lifts that matter; let the rest go.

## 5. Severity labels (required)

Every comment MUST open with a bolded severity tag on its own line. Use exactly one of:

- **`🛑 Blocking:`** — critical; must be fixed before merging. The CR is wrong, unsafe, or breaks a contract/invariant. Reserve for things you'd withhold approval over.
- **`Optional:`** — a suggestion; the author can take it or leave it without justification.
- **`Nit:`** — minor cosmetic/stylistic (naming, formatting, wording).
- **`ℹ️ FYI:`** — informational only; no action required.

Rules:
- The tag is the first thing in the comment. Don't bury severity in prose.
- One severity per comment. Split if a location has both a blocker and a nit.
- Default to `Optional:` when unsure; escalate to `🛑 Blocking:` only when you'd actually withhold approval.
- If posting a draft set with zero `🛑 Blocking:` comments, say so explicitly ("all non-blocking — approve-with-suggestions").

## 5a. The pedantry gate — does this comment earn the author's time?

Before any draft survives, answer: **does the author's day get better if I post this?** If the honest answer is "no, but I'm technically right," drop it.

Pedantry tells:
- **Technically right, behaviorally irrelevant.** The code works, the reader understands it, the comment exists only because you noticed.
- **Teaching where no teaching is needed.** The author is not your student.
- **Precision-demanding on the wrong axis.** Null-checks where nulls can't reach; error handling on paths that can't fail.

## 5b. What NOT to comment on

Drop the draft if it falls into any of these:
- **Speculation without evidence.** Can't point at the file:line? Drop, or downgrade to a `ℹ️ FYI:` question.
- **Pre-existing patterns the CR follows.** Grep the package. If the diff matches the prevailing convention, don't punish the author for inheriting it.
- **Out-of-diff issues.** Belongs in a separate CR (unless *this change* makes pre-existing code observably worse).
- **Style a linter owns.** If `brazil-build release` would catch it, don't comment.
- **Already-said findings.** Description called it out, an analyzer already flagged it, or another reviewer beat you to it. A `+1` reply is the whole comment.

**Default to dropping.** A borderline comment that survives revision is almost always one that should have been cut.

## 5c. Volume cap — 5–7 substantive findings, max

Past 5–7 comments, the author starts tuning out.
- **Soft cap: 5–7 substantive findings** (`🛑 Blocking:` + `Optional:`). `Nit:`/`ℹ️ FYI:` don't count but shouldn't dominate.
- **More than 7? Prune to the highest-impact set.** Group repeats into one comment with multiple citations ("same issue at A, B, C").
- **Zero substantive findings? Say so.** "No issues found — approving with the suggestions inline" is a complete review. Don't invent findings.
- **Praise costs nothing and calibrates the rest.** One-line `ℹ️ FYI:` on a genuinely good idea. Sincere only.
- **Order structural before stylistic.** Lead with comments that could change the shape of the CR.
- **Suggest fixes sparingly, as gifts.** A short fix snippet for a clear-cut suggestion. Cap ~2–3 per review.

## 6. Keep comments terse — verbosity reads as bot output

CR comments are read by humans clearing a queue. AI-drafted feedback defaults to paragraph-shaped output — preamble, restated context, hedged caveats, closing summary — when a couple of sentences would do.

- **Lead with the substantive point.** No preamble. The first sentence is the comment.
- **Don't restate the diff.** Point at the *issue*.
- **A comment longer than the hunk it covers is a tell.** Cut.
- **Drop hedges.** "I think it might be worth considering whether…" → either say it or drop it.
- **One thread per comment.** Split a fused blocker+aside+question into separate comments (or drop the weaker ones).

A long comment is fine when it's earning the length: a meaty design point, or a top-level summary laying out cross-file context.

## 7. Self-review every draft before calling CRAddComment

Before posting any draft, do a second pass with the actual diff open:

- **Is the factual claim correct?** Re-open the file and verify values, types, behavior. If you can't re-cite the file:line that proves the finding, it's not ready.
- **Does the ask match the framing?** Pick one — assertion change or documentation change — and rewrite the lead to match.
- **Is the severity honest?** Urgent lead → `🛑 Blocking:`. Optional lead → `Optional:`.
- **Did you check whether the pattern is pre-existing?** Grep before flagging.
- **Is it short enough to read?** Over a paragraph → apply section 6.
- **Did the description already address it?** Re-check against the final draft list.
- **Did an analyzer already flag it?** Drop your version.
- **Would I want to receive this?** If it'd irritate you, drop it.

**Default to dropping**, not softening.

**Three-filter gate before posting:** for each surviving draft — (1) Is it productive? (2) Is the expectation clear? (3) Is it kind? A "no" on any means rewrite or drop.

## 7a. Take it offline when threads heat up

CR comment threads are the wrong venue for disagreement past one round-trip. If tone goes terse/defensive, notes-per-revision aren't trending down, or the same point is being re-explained — stop adding comments and surface it to the user to take offline.

## 8. Never append the AI-assisted marker

When posting via `CRAddComment` (or any plugin variant), do NOT include `🤖 *AI-assisted comment* 🤖` or any AI-disclosure marker. CRUX appends one automatically server-side; adding one yourself makes it appear twice. Write the comment body as substantive content only.

## 9. Drafts by default; never publish without an explicit ask

`CRAddComment` posts drafts when `publish=false` (the default). Keep that default — let the user review drafts in the CRUX UI and publish themselves. Only set `publish=true` if the user explicitly says "publish" in the current session.

---

## Sources

Distilled from Amazon-internal CR guidance: Vosshall PE-canonical (`w.amazon.com/index.php/SoftwareStandards/CodeReviewGuidelines`), 150-150-CR, arjunkhr Code Review Etiquette, ManagedFleets CR tenets (three-filter gate), Silk/GFT/ShipWithAmazon guidelines (severity ladder, dedup), and Mike Lynch's & Blake Smith's code-review writing. Companion author-side skill: `crux-author`.
