# The Workflow Guide

An in-depth guide to the AI-native development system in this repo: the philosophy behind it, how
the pieces fit together, and exactly how to drive each skill, command, and hook.

There are two systems here, and they nest:

- **Personal (`personal-projects/`)** — a spec-first coding loop for solo work. No review tool, no
  deploy, no gates. Just: think → write a spec → implement against it → keep the spec alive.
- **Production (`production-review/`)** — the personal loop *plus* everything a company SDLC adds:
  a code-review tool, a build system, personal-stack deploys, human approval gates, and the ability
  to run several changes at once as isolated parallel "lanes."

If you only ever code alone, read [Part 1](#part-1--the-personal-loop) and stop. If you work inside
a review-and-deploy pipeline, read both — Part 2 assumes Part 1.

> **Attribution.** The `openspec-*` skills and the OpenSpec CLI they wrap are the third-party
> [OpenSpec](https://github.com/Fission-AI/OpenSpec) project (MIT, `author: openspec` in each
> skill's frontmatter). Everything else — `caveman-review`, `crux-author`, `crux-review`,
> `self-loop`, `milestone`, `my-crs`, `spec`, and the `lane*` / `deploy-lock` / `cr_extract` scripts
> — I wrote, mostly by distilling Amazon-internal code-review and build guidance into skill form.

---

## Table of contents

- [The core idea](#the-core-idea)
- [Skills vs commands vs hooks — how Claude Code loads each](#skills-vs-commands-vs-hooks)
- [Part 1 — the personal loop](#part-1--the-personal-loop)
  - [The OpenSpec change lifecycle](#the-openspec-change-lifecycle)
  - [`/opsx:explore` — think before you build](#opsxexplore)
  - [`/opsx:propose` — turn an idea into artifacts](#opsxpropose)
  - [`/opsx:apply` — implement task by task](#opsxapply)
  - [`/opsx:sync` and `/opsx:archive` — keep specs alive](#opsxsync--opsxarchive)
  - [`caveman-review` — terse review comments](#caveman-review)
  - [A full personal-project session](#a-full-personal-project-session)
- [Part 2 — the production loop](#part-2--the-production-loop)
  - [The three-layer mental model](#the-three-layer-mental-model)
  - [The five gates](#the-five-gates)
  - [`/milestone` — the orchestrator (3 modes)](#milestone--the-orchestrator)
  - [`/spec` — scoped context loading](#spec--scoped-context-loading)
  - [`crux-author` — author a review worth someone's time](#crux-author)
  - [`crux-review` — review someone else's diff (or your own)](#crux-review)
  - [`/my-crs` — service your open reviews](#my-crs--service-your-open-reviews)
  - [Parallel lanes — running N changes at once](#parallel-lanes)
  - [The hook scripts — what runs automatically](#the-hook-scripts)
  - [A full production day, end to end](#a-full-production-day)
- [Adapting this to your own setup](#adapting-this-to-your-own-setup)

---

## The core idea

Every workflow here is built on three convictions:

1. **Write the spec before the code.** The expensive mistakes are scope and design mistakes, and
   they're cheapest to catch in prose. So the loop always produces a written proposal + design +
   task list *before* the first line of implementation, and it keeps that spec as a living artifact,
   not a throwaway.

2. **Keep judgment with the human; give the mechanics to the agent.** The agent drafts, implements,
   builds, formats, and self-reviews. It never independently does anything outward-facing or
   irreversible — publishing a review, deploying, merging. Those are **gates**: the agent stops,
   echoes the exact command, and waits for an explicit "yes." In personal mode there are no gates
   because nothing is outward-facing; in production mode there are five.

3. **Isolate parallel work so it can't collide.** Multiple changes run at once, each in its own
   Claude session, its own git branch, and — when two touch the same package — its own git worktree.
   A shared ledger file records who's touching what and in what order things must merge.

The payoff, in the words of the framing doc that shipped alongside this: understanding an unfamiliar
codebase went from *days* to *hours*, and parallelism (several changes in flight without conflicts)
was the single biggest multiplier during implementation.

---

## Skills vs commands vs hooks

Claude Code has three extension points, and this repo uses all three. Knowing which is which tells
you where each file goes and how it fires:

| Mechanism | Lives in | How it triggers | Examples here |
|-----------|----------|-----------------|---------------|
| **Skill** | `~/.claude/skills/<name>/SKILL.md` (or a project `.claude/`) | *Model-decided.* Claude reads the `description` and invokes it when the task matches. Can also be forced. | `crux-author`, `crux-review`, `caveman-review`, `self-loop`, `openspec-*` |
| **Slash command** | `~/.claude/commands/<name>.md` | *User-typed.* You type `/name`. Subcommands via `commands/<ns>/<name>.md` → `/ns:name`. | `/milestone`, `/my-crs`, `/spec`, `/opsx:propose`, … |
| **Hook** | a script + a registration in `settings.json` | *Event-driven.* The harness runs it on `SessionStart` / `PreToolUse` / `PostToolUse` / `Notification` / `Stop`. | `deploy-lock.sh`, `lane-format.sh`, `lane-notify.sh`, `lane-reconcile.sh` |

The distinction that trips people up: a **skill auto-triggers** (Claude decides `crux-review` is
relevant when you paste a CR link), while a **command is something you type**. In this system the
five typed commands are the whole surface — everything else (the CRUX skills, the OpenSpec commands
invoked *by* `/milestone`, the hooks) fires on its own.

See [Adapting this to your own setup](#adapting-this-to-your-own-setup) for the exact `settings.json`
hook registration.

---

# Part 1 — the personal loop

Everything in this part works on **any codebase**, needs **no external services**, and has **no
approval gates**. The only dependency is the [OpenSpec CLI](https://github.com/Fission-AI/OpenSpec)
(`npm i -g openspec` or per its README) plus these skill/command files.

## The OpenSpec change lifecycle

A "change" is a folder — `openspec/changes/<name>/` — holding three artifacts:

```
openspec/changes/add-user-auth/
├── proposal.md   # WHAT & WHY  — the problem, the change, the scope
├── design.md     # HOW         — architecture, alternatives, trade-offs, failure modes
└── tasks.md      # STEPS       — an ordered, checkbox task list you implement against
```

The lifecycle is a straight line with one optional front door:

```
        (optional)
  /opsx:explore ─────┐
                     ▼
   idea ─▶ /opsx:propose ─▶ /opsx:apply ─▶ (code merged) ─▶ /opsx:archive
                │                │                                  │
           writes the       implements          folds the change's spec deltas
           3 artifacts      tasks.md,           into openspec/specs/ (the living,
                            checking boxes      "as-built" spec) and retires the change
```

`/opsx:sync` is the same fold as archive but *without* retiring the change — use it mid-flight to
update the living spec while you keep working.

## `/opsx:explore`

**When:** you have a fuzzy idea, a problem you don't fully understand, or a "Postgres or SQLite?"
kind of decision. **This is thinking mode — it will not write application code.** It can read your
codebase, draw ASCII diagrams, build trade-off tables, challenge your assumptions, and (only if you
ask) capture conclusions into OpenSpec artifacts.

```
/opsx:explore
> I'm thinking about adding real-time collaboration but I'm not sure how deep to go
```

It'll map the space (presence vs cursors vs full CRDT sync), ground it in what your code already
does, and follow the threads that resonate. There's no required output — sometimes the clarity *is*
the deliverable. When something crystallizes it offers: *"This feels solid enough to start a change.
Want a proposal?"* — and if you say yes, it hands off to propose.

**The one hard rule:** it never implements. Ask it to build something and it reminds you to exit
explore and create a proposal first. That guardrail is the point — explore is where you're allowed
to be vague without the agent racing ahead into code.

## `/opsx:propose`

**When:** you know what you want to build. **What it does:** creates the change and generates all
three artifacts in one pass.

```
/opsx:propose add-user-auth
# or just describe it and let it derive the kebab-case name:
/opsx:propose
> add token-bucket rate limiting to the public API
```

Under the hood it runs `openspec new change`, reads `openspec status --json` to learn the artifact
dependency order and the *schema* (e.g. `spec-driven`), then for each artifact pulls
`openspec instructions <artifact> --json` — which hands back a `template`, `rules`, and `context`
for that artifact type — and fills the template. It reads each completed artifact before writing the
next (so `design.md` is informed by `proposal.md`, and `tasks.md` by both).

**Nuance worth knowing:**
- The `context`/`rules` blocks from the CLI are *constraints for the agent*, not content — they
  never get copied into your files.
- It uses a todo list to track artifact progress and re-checks `openspec status` after each write,
  stopping once everything in `applyRequires` is `done`.
- If scope is genuinely unclear it'll ask (via a question prompt) rather than guess — but it's tuned
  to prefer momentum over interrogation.

Output: "All artifacts created. Run `/opsx:apply` to implement."

## `/opsx:apply`

**When:** the proposal exists and you're ready to build. **What it does:** walks `tasks.md`
top-to-bottom, implementing each task and flipping its checkbox `- [ ]` → `- [x]` as it goes.

```
/opsx:apply add-user-auth
# name optional — it infers from context or, if ambiguous, lists active changes and asks
```

It first reads *all* the context files the CLI reports (proposal, design, specs, tasks), shows you
`N/M tasks complete`, then loops. Key behaviors:

- **Keeps going until done or blocked** — it doesn't stop after one task and wait.
- **Pauses (doesn't guess) when** a task is ambiguous, implementation reveals a *design* problem
  (it'll suggest updating `design.md` rather than plowing ahead), or it hits an error.
- **Minimal, scoped edits per task** — it's explicitly told not to sprawl.
- There's a **workspace guard**: if the change's schema reports it can't safely edit here, it treats
  linked repos as read-only and stops rather than editing the wrong thing.

This is where personal mode ends: implement, run your own tests, commit. No gates, because nothing
leaves your machine.

## `/opsx:sync` & `/opsx:archive`

Both fold a change's *spec deltas* — the new/changed requirements it introduced — into
`openspec/specs/`, which is your **living, as-built spec** (distinct from the per-change proposal).

- **`/opsx:sync`** — do this mid-flight when you want the living spec updated but the change is still
  active. Useful on long changes so `openspec/specs/` never drifts far from reality.
- **`/opsx:archive`** — do this *after* the change is done/merged. Same fold, plus it retires the
  change folder. This is the "close the loop" step.

Skipping these is the classic failure mode: specs rot, and six months later nobody trusts them.
Archiving on completion is what keeps the spec directory authoritative.

## `caveman-review`

**When:** reviewing a diff or PR and you want feedback with zero fluff. It auto-triggers on "review
this PR" / "review the diff" / "/review", or you can invoke it directly.

**The format is the whole point** — one line per finding:

```
L<line>: <problem>. <fix>.
<file>:L<line>: <problem>. <fix>.     (when multi-file)
```

Optional severity prefixes when findings are mixed:

- `🔴 bug:` — broken behavior, will cause an incident
- `🟡 risk:` — works but fragile (race, missing null-check, swallowed error)
- `🔵 nit:` — style/naming/micro-optimization; author can ignore
- `❓ q:` — a genuine question, not a veiled suggestion

Example output:

```
🔴 bug: auth.ts:L42: token expiry compared in ms vs s — always expired. Divide Date.now() by 1000.
🟡 risk: cache.ts:L88: no eviction — unbounded map. Add an LRU cap.
🔵 nit: user.ts:L15: `usr` → `user`.
```

It's deliberately terse because paragraph-shaped AI review comments read as bot output and get tuned
out. Note: this is the *generic* review skill. In a company setting the far richer `crux-review`
(below) supersedes it, because CRUX reviews carry context — descriptions, severity conventions,
analyzer signals — that a generic diff review misses.

## A full personal-project session

```
# 1. Not sure of the shape yet
/opsx:explore
> I want offline support in the note-taking app but sync scares me

# ...diagrams, trade-offs, you settle on last-write-wins with a vector clock...

# 2. Formalize it
/opsx:propose offline-sync
# → writes proposal.md / design.md / tasks.md

# 3. Build it
/opsx:apply offline-sync
# → implements tasks 1..N, checking boxes, pausing only if a task is unclear

# 4. Review your own diff before committing
> /caveman-review

# 5. Commit, then close the loop so the living spec stays true
/opsx:archive offline-sync
```

---

# Part 2 — the production loop

This is the personal loop wrapped in a company SDLC. It's what I ran day-to-day on an Amazon intern
project, so the files name Amazon systems — **Brazil** (build system + version sets), **CRUX**
(code review at `code.amazon.com`), **Apollo/Pipelines** (deploy), and **APS** (personal deploy
stacks). The *shape* transfers to any equivalent stack; see [adaptation](#adapting-this-to-your-own-setup).

## The three-layer mental model

Everything hangs off three files, each with exactly one job — nothing duplicated:

| Layer | Home | Role |
|-------|------|------|
| **Milestone board** | `PROJECT_PLAN.md` | The truth for *status*. A row goes 🟢 **only** after its CR is fully approved **and merged** — never on "code done" or "CR published." In-flight work is 🟡. |
| **Per-change tracking** | `openspec/changes/<name>/` | The scoped proposal/design/tasks for one milestone (same OpenSpec artifacts as Part 1). |
| **Design detail** | a big spec doc (e.g. `*_specs.md`) | The design source of truth. **Never loaded whole** — sections pulled on demand via `/spec`, driven by a `SPEC-INDEX` topic map at the top of the doc. |

The loop: **read the board → scope the next milestone with OpenSpec → pull only the relevant spec
sections → build → deploy (if infra) → review → respond → merge → archive → flip the board 🟢.**

**Milestones pipeline.** You start milestone N+1 while N is still in review. Each milestone owns its
own change folder and its own CR, so they never collide. This is what makes the parallel-lane system
(below) possible.

## The five gates

The loop is *semi-automated*: it drives everything, but stops at each outward-facing or billable
action for an explicit yes. Between gates, all local/read-only/reversible work runs on its own.

| # | Gate | Fires in | Why it's a gate |
|---|------|----------|-----------------|
| 1 | **Approve the plan** (before any code) | `/milestone` step 5 | Scope/design is the human's call. |
| 2 | **Approve deploy** to a personal stack | build cycle / `/my-crs` B4 | Real, billable AWS. Also **serialized** (one stack per pipeline) by `deploy-lock.sh`. |
| 3 | **Approve create + publish CR** | CR authoring | Puts reviewers on the hook. Created as a *draft* first so analyzers run. |
| 4 | **Approve raise-revision + publish replies** | `/my-crs` B6/B7 | Re-notifies reviewers. |
| 5 | **Approve the merge** | after CR approval | Merging auto-promotes to Beta — it ships. |

Two more soft gates: creating a brand-new package, and version-set merges. And one hard rule that
isn't a gate because it's simply *never done by the agent*: `git push` to a shared remote.

## `/milestone` — the orchestrator

The single command that drives the loop. It has **three modes**.

### Mode A — `/milestone status` (read-only board)

Prints a day-view of everything in flight: CRs open (→ run `/my-crs`), changes in build, proposed
but not started, and next-up rows from the plan. It also reads the lanes ledger (`openspec/LANES.md`)
and prints active parallel lanes, and it **flags two specific problems**:

1. Two active lanes share a package but the newer one still shows worktree `—` (an un-isolated
   collision — fix before both build).
2. A lane is ready to merge but its **Depends-on** lane hasn't merged (a merge-order violation).

This mode never writes anything. It's the "where am I?" glance.

### Mode P — `/milestone plan` (propose a parallel lane set)

This is how you fan out. It:

1. Reads the board, takes all non-🟢 rows as candidates (skips active lanes).
2. Resolves each into a **change name** (= lane name, kebab-case, no prefix), the **packages** it
   touches, and a **start-dir**.
3. Computes the **collision + dependency graph**: which candidates share a package (the later one
   needs a worktree), which consume another's output (Depends-on → merge-order), and which literally
   can't build until another exists (deferred).
4. Presents a **multi-select** — you check the lanes you want to launch now.
5. For each approved lane: creates the worktree if needed, appends a row to `LANES.md`, and
   **generates `.claude/launch-lanes.sh`** — a script that opens one tmux window per lane.

You then run `!bash .claude/launch-lanes.sh` and drive each lane in its own window. Mode P never
builds anything itself — it sets up the fleet and stops.

### Mode B — `/milestone [name]` (drive one milestone)

The workhorse. Eight steps, gated once:

1. **Pick the target** — the named row, or ask which (pipelining means "next" isn't always topmost).
2. **Extract scope from the Description column** — it names the packages, files, and spec topics.
   Derive the spec topics, the package set, and the kebab-case change name. *The change name is the
   lane name — one identity everywhere* (folder, ledger row, `claude --name`, tmux window,
   notifications).
3. **Load spec sections** — `/spec <topic1> <topic2> …` with all topics at once, never the whole doc.
4. **Provision packages** — `brazil ws show`, then for each missing package: `brazil ws use` (auto if
   the version set is known), a **soft gate** if it needs a version-set merge, or a **hard stop** if
   the package doesn't exist yet (must be created via BuilderHub).
5. **4b — Lane isolation** — read `LANES.md`, compute this lane's packages; if no overlap, make a
   feature branch `git checkout -b <change-name> mainline` in each package (worktree `—`); if it
   overlaps an active lane's package, `git worktree add -b <change-name>` a worktree of that package;
   set **Depends-on** if this lane consumes the incumbent's output; rebase onto latest mainline +
   `brazil ws sync --md` for freshness; append the ledger row.
6. **🔴 GATE 1** — summarize the plan (milestone, change name, spec sections, packages, approach) and
   get explicit approval before any code.
7. **Hand off to `/opsx:propose <change-name>`**, feeding it the milestone description + loaded spec
   as scoping context, then stamp the `Milestone · CR · Status` header into `proposal.md`.
8. **Set the board row to 🟡** (never 🟢 yet) and point to the next action (`/opsx:apply`, or
   `/milestone` again to pipeline the next one).

From there `/opsx:apply` builds (same as Part 1, but followed by `brazil-build release` and, if the
change touches infra, **Gate 2** deploy-to-personal-stack). A nice extra: within a lane, if
`tasks.md` has independent slices (e.g. one test suite per Lambda), apply can fan out a subagent per
slice to build them concurrently, then merge.

## `/spec` — scoped context loading

**The anti-drift tool.** A big design doc blows out the context window and makes the agent vague. So
the design spec carries a `SPEC-INDEX` comment block near the top mapping *topics → header → line
range*, and `/spec` loads only what you ask for:

```
/spec ddb-schema
/spec ddb-schema sign-off-api checker-barrier    # several at once — do this, not one at a time
```

It reads the index, resolves each topic to a section (exact match, or the closest header and it says
which it chose), and loads just those line ranges. It's **read-only — it never edits the spec.** If
a topic has no reasonable match it lists the available topics rather than dumping the whole file.
`/milestone` step 3 calls this for you; you also call it directly whenever you need a design detail.

## `crux-author`

**When:** work is moving from local commit toward review — "create a CR", "push this for review", or
addressing feedback on one. It's the *quality* layer; the mechanical bits (squash to one commit,
conventional-commit subject, never auto-publish/merge) are enforced elsewhere. The heart of it:

- **§0 Hard requirements** that will *block the merge* if missing — check these first:
  - **Exactly one commit** with a conventional-commit subject (`feat`/`fix`/`refactor`/… optionally
    gitmoji-prefixed). More than one line in `git log origin/mainline..HEAD` fails commit-lint.
  - **A tracking-ticket link in the description** — an analyzer posts a merge-blocking comment if
    there's no supported link (SIM/Jira/Quip/etc.).
  - **The team's description template** (for a full-CI/CD pipeline that deploys to prod without a
    manual change-management ticket): fixed `### Details / Documentation / Testing / CI-CD Checklist /
    Project Green` headings, every checkbox filled — blanks block review.
- **§1 Size — the "150-150" north star.** Aim for ≤150 source + ≤150 test lines per CR. A soft
  limit, but if you're well over it, *stop and ask whether to split* — bottom-up (land the data model
  before the handler) or by purpose (refactor CR, then feature CR), never arbitrarily mid-feature.
- **§2 Self-review as a reviewer would** — does the diff read top-to-bottom? Anything unrelated to
  the stated purpose (drive-by reformatting, opportunistic renames) pulled out? Dead code / debug
  prints gone? Tests asserting *behavior*, not implementation? Add author annotations for anything
  non-obvious. (In the loop this is where `crux-review` runs against your own diff.)
- **§3 Description** — lead with *why* (+ ticket), then the *organizing idea* of the change (not a
  line-by-line restatement of the diff), then *testing* (including "verified on personal stack …"),
  *risk/blast-radius*, and *assumptions you want validated*. Explicitly **no** AI boilerplate.
- **§4 Reviewers** — pick few, pick well; at least one long-term co-owner; add a domain expert for
  non-trivial changes; rotate; don't stack reviewers for false safety.
- **§5 Publish as a draft first** so analyzers (AutoSDE, Coverlay, dry-run, LLM reviewer) run *before*
  a human is on the hook — then publish. (Create and publish are both Gate 3.)
- **§6 Address feedback** — every comment owes one of: *fix it*, *push back with reasoning*, or
  *defer with a ticket*. Silence blocks the merge. Past two round-trips, take it offline.

The skill is stuffed with PE-canonical quotes for the *why* behind each rule — it's as much a
code-review education as a checklist.

## `crux-review`

**When:** reviewing any CRUX review (auto-triggers on a `code.amazon.com/reviews/CR-…` link), *and*
for the pre-publish self-review of your own diff. It exists because the built-in generic `/review` is
GitHub-shaped and misses CRUX context. The flow, in order:

- **§0 `clean` argument** — `/crux-review clean` deletes pulled CR workspaces and does nothing else.
- **§1 Read the description first** — it's authoritative. If the description already explains a
  change (or flags it as a prior-CR follow-up), *don't* raise a comment questioning it.
- **§2 Pull the CR locally** (`cr-pull`) for anything non-trivial, so you can grep sibling files and
  dependency source — the web diff hides cross-file inconsistencies. Verify "this is the only place"
  claims with an actual grep before asserting them.
- **§3 Review the latest revision** unless asked otherwise.
- **§4 Write behaviorally** — "this returns X when Y" over "line 42 is wrong"; comment on the system,
  not the author; ask rather than allege; cite a principle or it's just taste.
- **§5 Severity tag on every comment** — exactly one of `🛑 Blocking:` / `Optional:` / `Nit:` /
  `ℹ️ FYI:`, as the first thing in the comment. Default to `Optional:`; reserve `🛑 Blocking:` for
  things you'd withhold approval over.
- **§5a–c The pedantry gate + volume cap** — before any comment survives: *does the author's day get
  better if I post this?* Drop speculation, pre-existing patterns the CR merely inherits, style a
  linter owns, and anything already flagged. **Soft cap 5–7 substantive findings** — past that the
  author tunes out; group repeats; "no issues found" is a complete review.
- **§6 Terse** — lead with the point, no preamble; a comment longer than the hunk it covers is a
  tell.
- **§7 Self-review every draft** against the open diff (re-cite the file:line, honest severity,
  grep for pre-existing), then a three-filter gate: *productive? clear? kind?*
- **§8–9 Posting** — never add an "AI-assisted" marker (CRUX appends one server-side), and comments
  post as **drafts by default** — never published without you explicitly saying "publish."

## `/my-crs` — service your open reviews

Audits and works the CRs *you authored*. It uses a static helper, `cr_extract.py`, to parse CRUX
pages (never inline Python heredocs — those trip security warnings). **Two modes:**

**Mode A — `/my-crs` (no argument): read-only punch list.** Identifies you via `git config
user.email`, fetches your authored queue and each CR's detail page, and prints a badged action list
built from CRUX's authoritative `next_actions` map plus a comment scan:

```
## Action items — authored CRs
Mine — 3:
- 🟢 CR-… — approved, ready to merge
- 🟠 CR-… — fix failing analyzers
- 🔵 CR-… — 2 comment(s) to reply to
Awaiting others — 1:
- ⏳ CR-… — <reviewer> hasn't replied to 1 comment
```

No prose, no edits — just "who's waiting on me."

**Mode B — `/my-crs CR-xxxxxxxx`: drive the respond loop for one CR.** It correlates the CR to a
milestone (matching the URL against the `CR:` header in the change proposals), then walks:

- **B1** summarize each unaddressed comment (location, what's wanted, is it a code change / question
  / discussion). [read-only]
- **B2** draft the fixes locally and **show you the diff + intended replies before touching
  anything** [🟡 soft gate].
- **B3** `brazil-build release` to verify. [auto]
- **B4** if the fix changed infra: **🔴 Gate 2** deploy + verify.
- **B5** amend into the single branch commit — never stack `fix(...)` commits. [auto]
- **B6** **🔴 Gate 4** `cr --update-review <CR-ID>` (raises the revision, re-notifies).
- **B7** **🔴 Gate 4** post thread replies — **drafts by default**, published only on explicit ask.
- **B8** report the new revision and remaining open threads; remind you merge is a separate Gate 5.

Everything is read-only until a gate; gated commands are always echoed exactly before running.
It never self-approves or self-merges.

## Parallel lanes

The force multiplier. The rule set:

- **One row = one lane = one `claude --name` session = one tmux window = one row in `LANES.md`.**
  The lane name *is* the OpenSpec change name — one identity everywhere.
- **Each lane works on its own branch `<change-name>`, never on mainline.** The CR is raised from it.
- **Isolation is keyed on the package, not the lane.** Two lanes editing *different* packages share
  the base workspace freely. Two lanes editing the *same* package → the newer gets a **git worktree**
  of that one package (each package is its own git repo; the workspace root is not).
- **No boss agent.** Lanes self-coordinate through `LANES.md`, whose **Depends-on** column records
  merge order (the lane that produces code another imports must merge first — because merging
  auto-promotes to Beta).
- **Deploy is serialized** — one personal stack per pipeline, enforced by `deploy-lock.sh`.

The launch flow (all from a plain terminal — tmux need not be open):

```
claude
> /milestone plan          # propose lanes → you check the set → it writes LANES.md + worktrees + launcher
!bash .claude/launch-lanes.sh   # creates the `mosaic` tmux session, one window per lane, attaches once
# inside each window:
> /milestone <change-name>      # drive that lane: Gate 1 → /opsx:apply → Gate 3 (CR)
# a second terminal:
claude agents                   # the dashboard — notifications tap you at gates
```

tmux keys you actually need: `Ctrl-b w` (pick a lane), `Ctrl-b n/p` (next/prev), `Ctrl-b d`
(detach — lanes keep running), `tmux attach -t mosaic` (re-attach).

## The hook scripts

Registered in `settings.json`, these run automatically and are what make the fleet safe and
low-friction. All identify the lane from the session's `cwd` (the worktree/package dir), because a
custom `--name` isn't available to hook events.

| Script | Hook event | What it does |
|--------|-----------|--------------|
| **`lane.sh`** | *(not a hook — a launcher)* | Ensures the `mosaic` tmux session exists, opens a window per lane cd'd to its dir, starts `claude --name <lane>`, and configures a status bar showing lane count + deploy-lock holder. `--no-attach` lets the multi-lane launcher create all windows then attach once. |
| **`deploy-lock.sh`** | `PreToolUse` (Bash) | Serializes deploys. On an `aps deploy`, if another lane holds `.claude/deploy.lock` it returns a `deny` decision with a reason; otherwise it acquires the lock. Same lane re-deploying is allowed. |
| **`lane-notify.sh`** | `PermissionRequest` / `Notification` / `Stop` | macOS banners: `input` (a gate is waiting, Ping sound) and `idle` (lane finished, Glass sound). `release` fires on *every* turn end — **silent**, it only frees the deploy-lock so a 20-turn auto-mode lane doesn't spam 20 notifications. Has an `afplay` audible fallback for when Focus/DND suppresses banners. |
| **`lane-format.sh`** | `PostToolUse` (Write\|Edit) | Auto-formats the edited file so build-lint won't fail: TS/JS → the *package-local* prettier + eslint (walks up to the nearest `package.json`); Python → black + isort. No-ops silently on anything else. |
| **`lane-bash-log.sh`** | `PreToolUse` (Bash) | Per-lane bash audit log at `.claude/logs/bash-<lane>.log`. |
| **`lane-reconcile.sh`** | `SessionStart` | Advisory only: prints a `systemMessage` if `LANES.md` disagrees with reality (a worktree on disk with no ledger row, or a stale deploy-lock holder). Never edits or blocks. |
| **`lane-status.sh`** | *(called by tmux status bar)* | Renders the `lanes:N  deploy:<holder>` line. |
| **`lane-sweep.sh`** | *(manual cleanup helper)* | Housekeeping over stale lanes/worktrees. |
| **`cr_extract.py`** | *(called by `/my-crs`)* | Parses a CRUX page's persisted JSON into the compact structure `/my-crs` filters on (`next_actions`, `comments[]`, `i_approved_current`, …). |

There's also a `SessionStart:compact` hook (a plain `echo` in `settings.json`, not a script) that
**re-injects the five gates + the never-push rule after the context window compacts** — so the
guardrails survive summarization.

## A full production day

```bash
# ── glance ──
/milestone status      # what's in flight everywhere; flags collisions / merge-order violations
/my-crs                 # who's waiting on me

# ── fan out new work ──
/milestone plan         # propose lanes → check the set → writes ledger + worktrees + launcher
!bash .claude/launch-lanes.sh

# ── in each lane window ──
/milestone <change-name>   # Gate 1 (plan) → /opsx:apply (build + Gate 2 deploy if infra)
                           #   → crux-review self-pass → crux-author → Gate 3 (create+publish CR)
# turn on auto mode (shift+tab) so the lane flies between gates and only stops to tap you

# ── service feedback (often while the next milestone builds) ──
/my-crs CR-xxxxxxxx     # B1 summarize → B2 draft+show → B3 build → B5 amend
                        #   → Gate 4 raise revision → Gate 4 post replies

# ── close, in Depends-on order ──
# Gate 5 merge → /opsx:archive <name> → ledger row + worktree removed → board flips 🟢
```

The rhythm that emerges: one CR in review (serviced via `/my-crs`) while you actively build the next
milestone in another lane — which is exactly what pipelining is for.

---

## Adapting this to your own setup

The `personal-projects/` half is portable as-is (just install the OpenSpec CLI). The
`production-review/` half is a **template of my Amazon setup** — to reuse it:

1. **Replace the hardcoded paths.** Search the `production-review/` tree for `/Volumes/workplace`
   and the `gajanmoh-*` stack ids and point them at your workspace root and infrastructure.
2. **Swap the systems.** The commands name Brazil (build), CRUX (review), Apollo/APS (deploy). Map
   each to your equivalent — e.g. GitHub PRs for CRUX, your CI for `brazil-build release`, your
   deploy tool for `aps deploy`. The `self-loop` skill is written to resolve these from a workspace
   `CLAUDE.md` rather than hardcoding, so start there.
3. **Set up the three layers.** A `PROJECT_PLAN.md` with a Status column; `openspec/` initialized;
   and a `SPEC-INDEX` comment block in your design doc so `/spec` can resolve sections.
4. **Register the hooks.** In `~/.claude/settings.json` (or a project `.claude/settings.json`), wire
   the scripts to their events and gate the outward-facing commands. A minimal version:

   ```jsonc
   {
     "permissions": {
       "ask":  ["Bash(aps deploy *)", "Bash(cr *)", "Bash(brazil vs merge *)"],
       "deny": ["Bash(git push *)", "Bash(git push)"]
     },
     "hooks": {
       "SessionStart":      [{ "matcher": "*", "hooks": [{ "type": "command", "command": "~/.claude/scripts/lane-reconcile.sh" }] }],
       "PreToolUse":        [{ "matcher": "Bash", "hooks": [
                                { "type": "command", "command": "~/.claude/scripts/deploy-lock.sh" },
                                { "type": "command", "command": "~/.claude/scripts/lane-bash-log.sh" }] }],
       "PostToolUse":       [{ "matcher": "Write|Edit", "hooks": [{ "type": "command", "command": "~/.claude/scripts/lane-format.sh" }] }],
       "PermissionRequest": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "~/.claude/scripts/lane-notify.sh input" }] }],
       "Notification":      [{ "matcher": "idle_prompt", "hooks": [{ "type": "command", "command": "~/.claude/scripts/lane-notify.sh idle" }] }],
       "Stop":              [{ "matcher": "*", "hooks": [{ "type": "command", "command": "~/.claude/scripts/lane-notify.sh release" }] }]
     }
   }
   ```

   The `deny` on `git push` is deliberate — publishing to a shared remote stays a human action, full
   stop.
5. **Confirm the gates match your comfort level** before letting a lane run in auto mode.

The through-line, whatever the stack: **spec before code, judgment stays human at the gates, and
isolate parallel work so it can't collide.**
