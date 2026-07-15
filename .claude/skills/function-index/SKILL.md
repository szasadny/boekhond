---
name: function-index
description: >
  Scan the Bamel codebase for all Python and TypeScript/TSX function definitions, build a compact
  index of function_name → file:line, then use it to (1) identify which files to read or change for
  the current task and (2) spot existing functions that could be reused or extended instead of
  reimplemented. When duplication risk is found, propose a shared base function before writing new
  code. Use this skill at the start of every new feature request, any time you are about to create a
  new service function, hook, or utility, or when asked to "add", "implement", "build", "create",
  "extend", or "refactor" anything in the codebase. Also trigger when you notice yourself reaching
  for a new helper that might already exist.
---

# Function Index Skill

The most common source of duplication is writing a new function without knowing a similar one
already exists. This skill builds a full index once, then queries it — reason about reuse before a
single line of new code is written.

## Step 1 — Build the index (once per session)

```
python scripts/function_index.py > <scratchpad>/function-index.txt
```

Writes one line per definition (`pad:regel: naam`, backend + frontend, tests excluded) and prints a
count to stderr. Add `--tests` only when the task itself lives in tests. **Never cat or dump the
whole file into context** — query it with grep.

## Step 2 — Query the index against the task

Grep the index file case-insensitively for 2–4 keywords from the task, including Dutch domain terms
and synonyms (e.g. `keuring|inspection`, `aanbrenger|makelaar`, `factuur|invoice`). Both name hits
and path hits are signal. Iterate keywords until you can name the 3–6 most relevant files to read —
no more. This replaces a blind folder scan.

## Step 3 — Classify reuse before reading any file

- **Direct reuse** — an existing function already does it: import and call it.
- **Near-reuse** — it does 70–90%: add an optional parameter with a default so existing callers are
  unaffected, instead of writing a filtered/variant copy.
- **Duplication risk** — the new function would share a non-trivial body with an existing one:
  extract a shared base instead of copying.
  1. Identify the parameters that differ between the two use cases.
  2. Put the base in the lowest shared location — Python: a leading private helper in the same
     service file; TypeScript: `frontend/src/lib/` for pure utilities, `frontend/src/hooks/` for
     React hooks.
  3. Refactor the **existing** function to delegate to the base (same external signature, no
     callers broken) and verify its tests still pass before continuing.
  4. Implement the new function on the base.

Be specific in the response: "`create_inspection` (inspection_service.py:45) already handles X;
the new function only differs in Y — parameterize Y instead of copying."

## Step 4 — Confirm plan with the user (only when refactoring existing code)

If Step 3 requires changing an **existing** function's signature or extracting it into a base,
state the plan (what gets extracted, which files and tests it touches) and confirm before touching
anything. This is the only gate — once confirmed, execute without further pauses.

## What this skill does NOT do

- It does not read full file bodies — that happens after Step 2 names the relevant files.
- It does not refactor unrelated code found in the index — flag observed duplication, scope the
  change to the current task.
