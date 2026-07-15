---
name: function-index
description: >
  Scan the codebase for all Doge function, method, and object definitions, build a compact index
  of naam → pad:regel, then use it to (1) identify which files to read or change for the current
  task and (2) spot existing definitions that could be reused or extended instead of reimplemented.
  When duplication risk is found, propose a shared base function before writing new code. Use this
  skill at the start of every new feature request, any time you are about to create a new service
  function, store method, lib-helper, or handler, or when asked to "add", "implement", "build",
  "create", "extend", or "refactor" anything in the codebase. Also trigger when you notice yourself
  reaching for a new helper that might already exist.
---

# Function Index Skill

The most common source of duplication is writing a new function without knowing a similar one
already exists. This skill builds a full index once, then queries it — reason about reuse before a
single line of new Doge is written.

## Step 1 — Build the index (once per session)

```
python3 .claude/skills/function-index/scripts/function_index.py > <scratchpad>/function-index.txt
```

Writes one line per definition (`pad:regel: naam much params`, objects tagged `(object)`, `tests/`
and `test_*.doge` excluded) and prints a count to stderr. Add `--tests` only when the task itself
lives in tests. The scanner skips `data/`, `static/`, and dotfolders, and correctly ignores
`such x = …` variable declarations — only `such f much …:` / `such f:` headers and `many Name:`
objects are indexed. **Never cat or dump the whole file into context** — query it with grep.

## Step 2 — Query the index against the task

Grep the index file case-insensitively for 2–4 keywords from the task, using the Dutch domain terms
the wet uses (`rubriek`, `btw`, `boeking`, `tijdvak`, `bijlage`, `kwartaal`, `storno`). Both name
hits and path hits are signal — the path tells you the layer (`lib/` domain-free helpers,
`app/services/` business logic, `app/store/` persistence, `web/` framework, `app/handlers/` HTTP).
Iterate keywords until you can name the 3–6 most relevant files to read — no more. This replaces a
blind folder scan and complements the ARCHITECTURE.md §0 lookup table.

## Step 3 — Classify reuse before reading any file

- **Direct reuse** — an existing function already does it: `so` the module and call it.
- **Near-reuse** — it does 70–90%: add an optional parameter with a literal default so existing
  callers are unaffected, instead of writing a filtered/variant copy.
- **Duplication risk** — the new function would share a non-trivial body with an existing one:
  extract a shared base instead of copying.
  1. Identify the parameters that differ between the two use cases.
  2. Put the base in the lowest shared location per ARCHITECTURE.md §0 — a domain-free helper goes in
     `lib/`; shared business logic stays in the owning `app/services/` file; a btw rule lives **only**
     in `app/services/btw.doge` (Hard Rule 5); a store concern in `app/store/` (Hard Rule 4).
  3. Refactor the **existing** function to delegate to the base (same external signature, no callers
     broken) and verify `doge test tests` still passes before continuing.
  4. Implement the new function on the base.

Be specific in the response: "`btw_bedrag` (app/services/btw.doge:38) already handles X; the new
function only differs in Y — parameterize Y instead of copying."

## Step 4 — Confirm plan with the user (only when refactoring existing code)

If Step 3 requires changing an **existing** function's signature or extracting it into a base, state
the plan (what gets extracted, which files and tests it touches) and confirm before touching
anything. This is the only gate — once confirmed, execute without further pauses.

## What this skill does NOT do

- It does not read full file bodies — that happens after Step 2 names the relevant files.
- It does not refactor unrelated code found in the index — flag observed duplication, scope the
  change to the current task.
- It does not cross layers on its own: `web/` never imports from `app/` (Conventions), so a helper
  shared between them belongs in neither — reconsider the boundary before extracting.
