# claudeAIWorkflows

A collection of [Claude Code](https://docs.claude.com/en/docs/claude-code) skills, slash
commands, and hook scripts I built to run an AI-native software development loop — spec-first
planning, parallel multi-agent builds, and a gated review/merge process.

They're split into two folders by where they're meant to run:

| Folder | Use it for | Coupling |
|--------|-----------|----------|
| [`personal-projects/`](personal-projects/) | Solo / personal coding. Spec-driven development and terse code review with **no company review system in the loop.** | Project-agnostic — drop in and go. |
| [`production-review/`](production-review/) | Team work inside a company SDLC: a formal code-review tool, a build system, deploy gates, and parallel work streams. | Wired to my Amazon setup (Brazil build, CRUX reviews, Apollo/Pipelines deploys). Treat as a **template** and re-point the paths/systems to yours. |

---

## `personal-projects/` — coding only

Everything here works on any codebase with no external services.

### Skills (`personal-projects/skills/`)
- **`caveman-review/`** — ultra-compressed code-review comments. One line per finding:
  `L<line>: <problem>. <fix>.`, with optional `🔴 bug / 🟡 risk / 🔵 nit / ❓ q` severity prefixes.
  Cuts the throat-clearing out of PR feedback.
- **`openspec-propose/` · `openspec-apply-change/` · `openspec-explore/` ·
  `openspec-archive-change/` · `openspec-sync-specs/`** — a spec-driven-development workflow built
  around the [OpenSpec](https://github.com/Fission-AI/OpenSpec) framework: turn a request into a
  written proposal + design + ordered task list *before* writing code, implement task by task, then
  fold the deltas back into living specs. OpenSpec itself is a third-party CLI these skills wrap.

### Commands (`personal-projects/commands/opsx/`)
- **`propose` · `apply` · `explore` · `archive` · `sync`** — slash-command front doors for the
  OpenSpec skills above (`/opsx:propose`, `/opsx:apply`, …).

---

## `production-review/` — company SDLC (review + deploy gates)

These encode a **semi-automated loop**: the agent drives every step but stops for a human "yes" at
each outward-facing or billable action. They reference Amazon-internal systems by name (Brazil,
CRUX code reviews at `code.amazon.com`, Apollo/Pipelines deploys) and hardcode my personal
workspace paths and stack ids — **adapt these before reuse.**

### Skills (`production-review/skills/`)
- **`self-loop/`** — the umbrella `plan → build → deploy → review → respond → archive` loop, with
  its **five approval gates** (approve plan, approve deploy, create+publish review, raise revision,
  merge). Project-agnostic in design; it resolves stack ids / paths from a workspace config file
  rather than hardcoding them.
- **`crux-author/`** — author a code review well: size it, write the description, pick reviewers,
  self-review before publishing, address feedback. Encodes the analyzer hard-requirements
  (one squashed commit, conventional-commit subject).
- **`crux-review/`** — review someone else's (or your own pre-publish) diff with a severity ladder
  and a bounded finding count.

### Commands (`production-review/commands/`)
- **`milestone.md`** — the orchestrator: read a milestone board, scope the next milestone, provision
  packages, load only the relevant spec sections, hand off to planning. `/milestone status` prints
  a day-view board; `/milestone plan` proposes a set of parallel work "lanes".
- **`my-crs.md`** — audit and service the code reviews *you* authored: summarize comments → draft
  fixes → amend → raise a revision, gated at each outward step.
- **`spec.md`** — load one or more sections of a large design spec into context on demand (never the
  whole file), driven by a topic index at the top of the spec.

### Scripts / hooks (`production-review/scripts/`)
The mechanics behind running several milestones at once as a **fleet of parallel lanes**, each its
own `claude` session isolated by a git worktree keyed to the package it edits:
- **`lane.sh`** — launch one lane (a named `claude` session in its own tmux window).
- **`lane-notify.sh`** — macOS notifications when a lane hits a gate or goes idle (a `Notification`
  / `PermissionRequest` / `Stop` hook).
- **`deploy-lock.sh`** — a `PreToolUse` hook that serializes deploys (one personal stack per
  pipeline) via a lock file.
- **`lane-format.sh`** — a `PostToolUse` hook: auto-format edited files (TS → prettier + eslint,
  Python → black + isort).
- **`lane-bash-log.sh`** — a `PreToolUse` hook: per-lane bash audit log.
- **`lane-reconcile.sh`** — a `SessionStart` hook: warn when the lane ledger disagrees with the real
  worktrees / lock.
- **`lane-status.sh` · `lane-sweep.sh`** — tmux status-bar line and cleanup helpers.
- **`cr_extract.py`** — parse CRUX review pages into structured data for `my-crs`.

---

## Installing

Claude Code discovers skills and commands under `~/.claude/` (global) or a project's `.claude/`.
To use one, copy it into the matching directory:

```bash
# skills
cp -R personal-projects/skills/caveman-review        ~/.claude/skills/
cp -R production-review/skills/crux-author           ~/.claude/skills/

# commands (become /opsx:propose, /milestone, …)
mkdir -p ~/.claude/commands/opsx
cp personal-projects/commands/opsx/*.md              ~/.claude/commands/opsx/
cp production-review/commands/*.md                   ~/.claude/commands/

# hook scripts
cp production-review/scripts/*.sh production-review/scripts/*.py  ~/.claude/scripts/
```

Hook scripts also need to be registered under `hooks` in `~/.claude/settings.json` or a project
`.claude/settings.json` — see each script's header comment for the event it expects
(`SessionStart`, `PreToolUse`, `PostToolUse`, `Notification`, `Stop`).

> **Before using anything in `production-review/`:** search for `/Volumes/workplace` and the
> `gajanmoh-*` stack ids and replace them with your own paths and infrastructure. These files are a
> working template of *my* setup, not a turnkey install.

## License

MIT — see [LICENSE](LICENSE).
