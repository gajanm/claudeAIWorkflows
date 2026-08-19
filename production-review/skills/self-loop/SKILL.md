---
name: self-loop
description: The plan → build → deploy → review → respond → archive development self-loop for Amazon/Brazil projects. Use when the user asks how to use the dev loop, wants to run/drive the loop, asks "what's next" on a project, or references /milestone, /my-crs, /spec, or the milestone board. Explains how the commands, skills, and approval gates fit together and reads project-specific config (stack ids, plan/spec paths) from the workspace CLAUDE.md rather than hardcoding it.
---

# Development Self-Loop

A semi-automated loop for taking project milestones from plan to merged CR. The loop drives every
step but **stops for the user's approval at each outward-facing or costly action** (the five gates
below). Between gates, local / read-only / reversible work runs automatically.

This skill is **project-agnostic**. Operational specifics (personal-stack ids, deploy profiles,
milestone-board path, spec path, package→version-set map) are NOT hardcoded here — resolve them from:
1. the workspace `CLAUDE.md` (pointer/policy file), then
2. recalled project memory, then
3. ask the user if still unknown.

## Mental model

Three layers, each with one home:

| Layer | Conventional home | Role |
|-------|-------------------|------|
| **Milestone board** | `PROJECT_PLAN.md` | What's done / in progress / next. Status → 🟢 **only** after a CR is fully approved + merged. |
| **Per-change tracking** | `openspec/changes/<name>/` | Scoped proposal / design / tasks for one milestone. |
| **Design detail** | a large spec doc (e.g. `*_specs.md`) | The source of truth for design. Never loaded whole — sections pulled on demand via `/spec`. |

The loop reads the board to know what's next, uses OpenSpec to scope it, pulls only the relevant
spec sections, builds/deploys/reviews, then flips the board status when the CR merges.

**Milestones pipeline**: start milestone N+1 while N is still in review. Each milestone owns its
change folder + its CR, so they never collide.

## The commands (only these are typed; skills auto-trigger)

| Command | Purpose |
|---------|---------|
| `/milestone` | Start/advance a milestone — the orchestrator. |
| `/milestone status` | Day-view board of everything in flight. |
| `/my-crs` | Read-only badged list of authored CRs needing the user. |
| `/my-crs CR-xxxxxxxx` | Work one CR: address comments → amend → raise revision. |
| `/spec <topic...>` | Load specific spec section(s) into context (multiple topics allowed). |

Auto-triggered: `crux-author`, `crux-review`, `caveman-review`, and the `/opsx:*` OpenSpec commands
(invoked by `/milestone`).

## The five approval gates

| # | Gate | Fires in |
|---|------|----------|
| 1 | Approve the plan (before any code) | `/milestone` |
| 2 | Approve deploy to personal stack (real, billable AWS) | build cycle / `/my-crs` |
| 3 | Approve create + publish CR | CR authoring |
| 4 | Approve raise-revision + publish replies | `/my-crs` |
| 5 | Approve the merge | after CR approval |

Also gated: creating a brand-new package, and version-set merges. At each gate, echo the exact
command and get an explicit yes before running it.

## One milestone, end to end

**PLAN** — `/milestone`
1. Read the milestone board; pick the next non-🟢 row (or ask which — pipelining).
2. Read the row's **Description** — the authoritative relevance signal (it names packages/files/topics).
3. Load matching spec sections via `/spec <topics>` (all at once, never the whole doc).
4. Provision packages: `brazil ws show`, then `brazil ws use --package <P> --versionset <VS>` for any
   missing (existing pkg → auto; VS merge → 🟡 gate; brand-new pkg → 🔴 stop, needs creation).
5. **🔴 GATE 1** — approve the plan.
6. `/opsx:propose <name>` → writes `openspec/changes/<name>/` with a `Milestone · CR · Status` header.
7. Set the board row to 🟡 In Progress (never 🟢 yet).

**BUILD** — `/opsx:apply`
- Implement tasks, `brazil-build release`, iterate on failures. [auto]
- If the milestone touches CDK/deployable resources: **🔴 GATE 2** → deploy (full CloudFormation,
  no hotswap) to the correct personal stack with the matching profile, then verify. Resolve the
  stack id / pipeline / profile from workspace config (see top of this skill).

**REVIEW** — author the CR
- `crux-review` self-reviews the diff; `crux-author` sizes (150-150) + drafts description + reviewers. [auto]
- **🔴 GATE 3** — approve create + publish. Create as draft first (lets analyzers run), then publish.
  Fill the CR field in the change's `proposal.md`.

**PIPELINE POINT** — may `/milestone` again to start the next milestone while this CR is in review.

**RESPOND** — `/my-crs` then `/my-crs CR-xxxx`. Per CR (the make-changes → amend → `cr --update-review`
loop, semi-automated):
- Summarize each unaddressed comment. [auto, read-only]
- Draft fixes locally — 🟡 show the diff + intended replies before proceeding.
- `brazil-build release` to verify. [auto]  ·  If CDK: **🔴 GATE 2** → deploy + verify.
- Amend into the single branch commit (one commit per CR). [auto]
- **🔴 GATE 4** → `cr --update-review <CR-ID>` (raises the revision, re-notifies reviewers).
- **🔴 GATE 4** → post thread replies (drafts by default; publish on explicit ask).
- Repeat per comment until converged — one revision raised.

**CLOSE**
- CR approved → **🔴 GATE 5** — kick off the merge.
- `/opsx:archive <name>` — fold deltas into `openspec/specs/`.
- **Only now** `/milestone` flips the board row → 🟢.

## A typical day

```
/milestone status     # what's in flight everywhere
/my-crs                # who's waiting on me
```
Then: new work → `/milestone` → approve plan → `/opsx:apply`; or feedback waiting → `/my-crs CR-xxxx`
→ walk the gates; or need design detail → `/spec <topic>`. A real day often has one CR in review
(via `/my-crs`) while actively building the next milestone.

## Where the machinery lives

- Portable tooling (`~/.claude/`): commands `milestone`, `my-crs`, `spec`; skills `crux-author`,
  `crux-review`, `caveman-review`, this `self-loop`; `scripts/cr_extract.py`.
- Project data (workspace): `PROJECT_PLAN.md`, the spec doc + its `SPEC-INDEX`, `CLAUDE.md`,
  `openspec/`, and the OpenSpec commands/skills under the workspace `.claude/`.

## Adapting to a new project

When this loop is used in a workspace that isn't yet set up:
1. Ensure a milestone board exists (`PROJECT_PLAN.md`) with a Status column.
2. Ensure OpenSpec is initialized (`openspec/` + the `/opsx:*` commands).
3. Add a `SPEC-INDEX` comment block to the design doc so `/spec` can resolve sections by header.
4. Record project config in the workspace `CLAUDE.md`: spec path, personal-stack id(s), deploy
   profile(s), package→version-set map, and any deploy policy (e.g. deploy-only vs hotswap).
5. Confirm the five gates match the user's comfort level before driving outward-facing steps.
