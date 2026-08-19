---
name: spec
description: Load one or more relevant sections of the MOSAIC master spec into context on demand. Read-only. Use when you need design detail for a feature without loading the whole 57KB doc. Accepts multiple topics at once.
---

Load only the relevant section(s) of the MOSAIC design spec into context. **Read-only — never edits the spec.**

**Spec location:** `/Volumes/workplace/mosaic_project_specs.md`
**Section index:** the `<!-- SPEC-INDEX ... -->` block near the top of that file maps topics → header → line range.

## Input

The argument is one or more space-separated topics, e.g.:

```
/spec ddb-schema
/spec ddb-schema sign-off-api checker-barrier
```

One milestone often needs several sections — load them **together**, not one at a time.

## Steps

1. **Read the section index.** Read the first ~90 lines of `/Volumes/workplace/mosaic_project_specs.md` to get the `SPEC-INDEX` table (topic → section header → line range).

2. **Resolve each requested topic to a section header.**
   - Exact topic match → take its `section header` string from the index.
   - No exact match → pick the closest section by header text and say which you chose.
   - Unknown topic with no reasonable match → list the available topics from the index and ask which one (do not dump the whole spec).

3. **Find the real line range and read it.** The index's line numbers are *hints only* — they drift when the doc is edited. Resolve the true range by header:
   - `grep -n '^#' /Volumes/workplace/mosaic_project_specs.md` to get all headers with current line numbers.
   - The section runs from its header line to the line before the next header of the same or higher level.
   - Read only that range with the Read tool's `offset`/`limit`. Batch reads for multiple topics; merge adjacent/overlapping ranges into one read.

4. **Present the loaded sections** with their headers, so it's clear what's now in context. Keep it verbatim — this is design source material, not a summary.

## Rules

- **Never** load the entire spec. If a request would pull more than ~40% of the file, stop and ask the user to narrow the topic.
- Read-only. This command does not modify the spec or any other file.
- If the SPEC-INDEX block is missing (spec not yet indexed), fall back to grepping headers (`grep -n '^#' mosaic_project_specs.md`), show the header list, and ask which section — then read that section's range.
