---
name: crux-author
description: Author an Amazon CRUX code review — size the CR, write a great description, choose reviewers, self-review before publish, and address feedback well. Use when the user says "create a CR", "make a CR", "push this for review", "address CR comments", or any time work is moving from local commit toward review. Covers the *quality* layer; mechanical commit/CRUX steps (squash, conventional commits, CRRevisionCreator, never auto-publish/auto-merge) follow the global git/Brazil rules and the user's amazon-builder-context rules.
---

# CRUX Author Flow

Apply this when preparing a CR for review or iterating on one in response to feedback. Mechanical rules — squash to one commit, conventional commit format, never set `autoPublish`/`autoMerge` unsolicited, never push to remote unless asked — are owned by the global git/Brazil rules. This skill is about *what makes the CR worth a reviewer's time*.

> Self-loop note: CR creation and publish are hard gates in the loop. This skill produces the *draft* — description, sizing, self-review — but the actual push/create (`CRRevisionCreator`) and publish only happen on the user's explicit approval.

## 0. Hard requirements — the CR will be blocked without these

These are enforced by analyzers (CR Detective, commit-lint) and will **block the merge** if missing. Check them *before* drafting anything else.

### 0.1 Exactly one commit, conventional-commit subject

- **Exactly 1 commit** per CR — squash/amend, never stack. (`git log --oneline origin/mainline..HEAD` must show one line.)
- The subject MUST start with one of these valid types, optionally with a gitmoji (gitmoji.dev) prefix:
  `build`, `chore`, `ci`, `docs`, `feat`, `fix`, `perf`, `refactor`, `revert`, `style`, `test`
  - Valid: `feat: add SignOffModel` · `🐛 fix: color bug` · `refactor: split FooService`
  - Invalid: anything else → commit-lint fails the CR (`❌ Invalid commit subject`).

### 0.2 CR Detective — a SIM/ticket link is MANDATORY in the description

The **CR Detective** analyzer scans the description for a tracking link and posts a **critical (merge-blocking)** comment if none is found. Every CR description MUST include a supported link.

- **This team's ticket folder:** `SPIG` → link issues as `https://issues.amazon.com/issues/SPIG-XXXX`.
- Supported link domains include: `issues.amazon.com`, `sim.amazon.com`, `t.corp.amazon.com`, `tt.amazon.com`, `taskei.amazon.dev`, `quip-amazon.com`, `tiny.amazon.com`, `sas.corp.amazon.com`, `mcm.amazon.com`, and the Jira variants — see CR Detective docs for the full list.
- If the link is missing at publish, the fix is: update the description → hit **retry** on the analyzer.

### 0.3 Description structure this team expects

Every CR description should lead with:
1. **The problem** — what's broken / missing / needed.
2. **What this CR solves and why** — the change and its motivation.
3. **Relevant links** — the SIM (0.2) *and* any design/artifact links, e.g. the design-doc review artifact:
   `https://pippin.amazon.dev/reviews/ms9hmCVAZPB1/artifacts/...`

Then the quality sections in §3 (What / Testing / Risk / Assumptions).

### 0.4 MOSAIC / SVS full-CI-CD template (this project) — MANDATORY sections

This project's pipeline is **full CI/CD — code deploys to prod without an MCM**, so every CR
description MUST use the team's fixed template (not just free-form prose). Reproduce these exact
headings:

- `**Note: This pipeline is full CI/CD…**` banner at the top.
- `### Details` → `#### Context of the problem` (situation, expected vs actual) · `#### How does this CR address the problem?` · `#### Relevant Links` (SIM mandatory — `SPIG` folder).
- `### Documentation` → doc-update Y/N.
- `### Testing` → how tested · `#### Unit / Integ Tests`.
- `### CI/CD Checklist` → 3 readiness checkboxes + 3 MCM-trigger checkboxes (db schema change / backwards-incompatible / deploy-order dependency — any "yes" ⇒ consider an MCM).
- `### Project Green` → `#### Seller Data <YES/NO>` and `#### Retail Decisions <YES/NO>` (keep the full policy question text; for storewide selection-vending both are normally NO).

Fill every checkbox and both Project Green answers — leaving them blank blocks review. `###` headings
and `**` emphasis are part of the expected format.

## 1. Size — 150-150-CR is the north star

Before uploading, look at `git -P diff --stat origin/mainline...HEAD`. Per the PE-stewarded **150-150-CR** guideline (venks, PE): aim for ≤150 lines of source + ≤150 lines of tests per CR. This is a soft limit, not a wall — but if you're well over it, **stop and ask whether the CR should be split** before bothering reviewers.

Signs the CR is too big:

- Mixes refactor + new feature + bug fix in one diff. Split by *purpose*, not by file.
- Touches more than one logical layer (e.g., DAO + service + handler + tests + config) for what is conceptually one change.
- Description requires more than three sentences to explain the *what*.
- You catch yourself thinking "I'll annotate the parts that aren't really related."

What to do if it's too big:

- **Split bottom-up.** Land the lowest-layer change first (data model, interface), then upper layers in follow-up CRs. Each layer's CR can stub or `// TODO` the upper layers.
- **Split by purpose.** Refactor first (no behavior change), feature second. Reviewers can speed through the refactor and focus their attention on the behavior change.
- **Don't split arbitrarily mid-feature.** A 400-line CR with a clear single purpose is better than two artificially-halved 200-line CRs that don't make sense in isolation.

> *"Don't let code fester on your machine without review. The longer you let it sit there without review the more likely it is that we all subscribe to sunk cost and give you a ship it because it took you 4 weeks, not because it's actually in a shippable state."* — Terkowit, Distinguished Engineer

## 2. Self-review before publishing — read it as a reviewer would

Once the description is drafted and the commit is staged, take 5 minutes to read the CR as if you've never seen it. This catches roughly half of what a reviewer would otherwise catch — at zero social cost. (In the self-loop, run the `crux-review` skill against your own diff here.)

For every changed file:

- **Does the diff read top-to-bottom?** If a reviewer would have to jump around to make sense of it, restructure the commit or add a description note pointing at the read order.
- **Is anything in the diff unrelated to the stated purpose?** Drive-by reformatting, opportunistic renames, an unrelated dependency bump — pull these out into separate CRs. They make the real change harder to review and harder to revert if it breaks.
- **Are there dead branches, commented-out code, or stray debug prints?** Remove them. They cost the reviewer attention and signal "not ready."
- **Are the tests asserting behavior, not implementation?** A test that breaks when you refactor without changing behavior is testing the wrong thing.
- **Did the implementation actually solve the stated problem?** Re-read the SIM/ticket; if the CR addresses a symptom rather than the root cause, say so explicitly in the description or fix it.

Add **author annotations** as inline comments on your own CR for anything non-obvious: "this branch is dead-code-pending-removal in CR-XXXXX", "kept this `synchronized` because of the deadlock found in COE-...", etc. Annotations are not a substitute for self-explanatory code — they fill the gaps code can't.

## 3. Description — make the reviewer's job easy

> *"You should make it easy (even enjoyable) for your reviewer to review your work."* — Silk CodeReviewGuidelines

The description is where a reviewer decides how much trust to extend and where to focus. Sections that pay off:

- **Why** — the motivation in two or three sentences. What problem does this solve? Link the SIM/ticket. If this is a follow-up to a prior CR comment or COE, say so explicitly: *"Follow-up to a comment in CR-279063351 about ..."*. The `crux-review` skill teaches reviewers to treat these as authoritative justification.
- **What** — the shape of the change. Not a line-by-line restatement of the diff (the diff is right there); the *organizing idea*. "Splits `FooService` into `FooReader` and `FooWriter` so the read path can be cached independently."
- **Testing** — what you tested, how, and what's still un-covered. Link logs, screenshots, dashboards. In the self-loop this is where you note *"deployed to personal stack `gajanmoh-guv`, verified GET returns correct shape"* — reviewers value seeing the personal-stack verification.
- **Risk / blast radius** — anything operational the reviewer should weigh: deployment ordering, weblab gating, backward compatibility, expected metric changes.
- **Assumptions you want validated** — if you made a call the reviewer is well-positioned to second-guess, name it. *"I assumed all assignments share the same QPC — please push back if that's wrong."*

**What NOT to put in the description:**

- A paraphrased commit message. The commit message is already in the CR.
- An exhaustive line-by-line walkthrough. The diff exists. If you need to explain it, the code should be clearer.
- Apologies, hedges, or "I know this is rough, sorry." Either it's ready for review or it's a draft — say which.
- AI-generated boilerplate ("This CR introduces a comprehensive enhancement to..."). Reviewers tune out instantly. Write it yourself.

## 4. Choose reviewers deliberately

> *"The developers that you select to review your code are now equal owners of that code."* — Silk

- **Required (at least one):** someone on your team who will be co-owner of the code long-term. This is the person who'll fix bugs in this code at 2am.
- **Rotate.** Don't always pick the same person. Use `code.amazon.com/packages/<pkg>/permissions` if you're unsure who's familiar.
- **For non-trivial changes, add a domain expert** if your team has one — a PE, an SDE3 with deep history in the package, or the original author of the code you're modifying.
- **Don't stack reviewers for safety.** Three reviewers each doing 30% of a review is worse than one doing 90%. Pick few; pick well.
- **Avoid the "rubber stamp" trap.** If you only ask people who'll wave it through, you're not getting a review.

## 5. Publish — and then leave it alone for a beat

After `CRRevisionCreator` returns with the CR URL, **do not immediately publish a draft revision**. Draft revisions let analyzers (AutoSDE, Coverlay, dry-run, LLM-Code-Reviewer) run first. Read what they catch *before* a human reviewer is on the hook. Fix what's worth fixing, push a new revision into the same draft (it upserts into revision 1), then publish. (Both create and publish are explicit user gates in the self-loop.)

When you do publish, ping reviewers explicitly only if there's an SLA risk or it's blocking other work — otherwise let CRUX's notification do the work.

## 6. Address feedback — fix or push back, but don't go silent

> *"The author and the reviewer must reach consensus on all code review feedback and expected changes."* — Vosshall, PE-canonical Code Review Guidelines

For every published reviewer comment, the author owes one of three responses:

1. **Fix it.** Make the change. Reply `done` or `fixed in r2` with a one-line summary if it isn't obvious from the next diff.
2. **Push back, with reasoning.** *"I considered that — kept it as-is because <specific reason tied to a constraint, contract, or measurement>."*
3. **Defer.** *"Agreed, but out of scope for this CR. Filed as <SIM-id> / will follow up in <next CR>."* Only valid if you'll actually do it.

Silence is not a response. A comment with no reply blocks the merge from the reviewer's perspective even if CRUX shows the CR as approvable.

**On disagreement specifically:**

- One round of back-and-forth in CR comments is fine; the second round is usually a sign to take it offline. If a thread has gone past two replies on each side without converging, ping the reviewer on chat or set up 15 minutes.
- If you genuinely can't reach agreement, **pull in a tiebreaker** — a third reviewer, your manager if necessary. Don't drop the thread.

**Iteration hygiene:**

- New revisions upsert into the existing draft until the first publish; don't try to "force a new revision" by re-running `CRRevisionCreator`.
- Don't add `fix(...)` commits per revision. Squash and re-upload — one commit per CR.
- When you push a new revision in response to comments, leave a top-level summary: *"r3: addressed comments from <reviewer> about X and Y; deferred Z to <follow-up CR>."*

## 7. When to ship-it your own work — never

The author never approves their own CR. Even when you've addressed every comment and tests are green, the merge decision is the reviewer's. If a reviewer is unresponsive past the team SLA, ping them once, then escalate — don't self-approve.

## 8. The mindset check

> *"Don't fear getting comments on the CR; think of it as an opportunity to either learn or make someone learn."* — GFT Code Review Guidelines

A CR with no comments is not a sign of a perfect CR; it's often a sign the reviewer didn't engage. The goal is not "zero feedback" — it's "the right feedback, addressed well."

---

## Sources

Distilled from Amazon-internal CR guidance: Vosshall PE-canonical (`w.amazon.com/index.php/SoftwareStandards/CodeReviewGuidelines`), 150-150-CR (`w.amazon.com/bin/view/150-150-CR/`), Silk CodeReviewGuidelines, Economic Selling / ShipWithAmazon / GFT CR best practices, and Mike Lynch's *How to Do Code Reviews Like a Human*. Companion reviewer-side skill: `crux-review`. Mechanical commit/CRUX rules live in the user's global git/Brazil rules (`~/.claude/rules/`).
