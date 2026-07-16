---
name: maintaining-agents-md
description: Keep Boekhond's root AGENTS.md and its dependent agent-facing inventory accurate and lean. Use after adding, removing, renaming, or repurposing folders; changing repo-scoped skills or agent workflow; changing facts described by AGENTS.md; or when the routing table, Project map, docs/PLAN.md skill inventory, README structure, or Claude import bridge feels stale.
---

# Maintaining AGENTS.md

Keep `AGENTS.md` accurate and lean. It is Boekhond's single source of truth and loads into every future agent session. Keep `.claude/CLAUDE.md` as an import-only bridge; never duplicate project instructions there.

## Workflow

### 1. Read the source of truth

Read the root `AGENTS.md` in full. Identify the exact section whose claims may be stale. Follow its routing table before inspecting or changing code:

- Load `writing-doge` before any `.doge` work.
- Use `modern-web-guidance` before adding a UI element.
- Read `docs/DATA-MODEL.md`, `docs/ARCHITECTURE.md`, or `docs/PLAN.md` when the routing table requires it.

### 2. Compare claims with the repository

Grep before scanning. Inspect only the relevant folder layer and use `git status`/`git diff` to distinguish current user changes from committed state. For the Project map, verify the actual top-level layout and the relevant children of `web/`, `app/`, `lib/`, `static/`, `tests/`, `docs/`, `.agents/`, `.claude/`, and `.codex/`.

Check related discovery rules when applicable:

- Canonical repo skills live in `.agents/skills/`.
- Shared Claude Code skills are name-matching relative symlinks in `.claude/skills/`.
- `.claude/CLAUDE.md` contains only the Boekhond heading and `@../AGENTS.md` import.
- Planner and executor are sibling children of the root session because `.codex/config.toml` sets `max_depth = 1`.

Identify additions, removals, renames, repurposed folders, and statements that no longer match the codebase. Adding a file inside an existing folder normally does not require a Project map change.

### 3. Update only stale claims

Edit the smallest relevant section of `AGENTS.md`. Keep existing house style and one-line Project map comments. Top-level files may remain in the map when they are important discovery entry points.

Never weaken or silently reinterpret a Hard Rule. If code and a Hard Rule disagree, report the conflict instead of rewriting the rule to match the code.

When the change affects entities or layer boundaries, update the routed reference doc in the same change. When it adds or removes a folder, update the Project map in the same change.

### 4. Sync dependent inventories

Avoid duplicated instruction bodies:

- Keep `.claude/CLAUDE.md` import-only.
- If the skill inventory changed, update `docs/PLAN.md` §5 and the skill lines in `AGENTS.md` and `README.md`.
- If the repository layout changed, update the corresponding structure line in `README.md` when present.
- Keep canonical skill content in `.agents/skills/`; Claude Code gets the same content through name-matching symlinks.

### 5. Validate

Run checks proportional to the edit:

- Resolve every Claude skill symlink and validate each changed skill with `quick_validate.py` from the global `skill-creator` skill.
- Parse changed TOML with Python `tomllib`.
- Check local Markdown links and run `git diff --check` plus `git diff --cached --check`.
- If `.doge` files changed, run `doge check`, a non-mutating formatter audit using temporary copies, and `doge test tests`.
- Confirm the Git index and `HEAD` remain unchanged when the task forbids staging or commits.

### 6. Report compactly

Report the claims and inventories updated, validation results, and any unresolved mismatch. Do not output a full diff.

## Rules

- Keep `AGENTS.md` lean; no changelogs, task notes, or transient status.
- Preserve unrelated user changes and avoid broad cleanup.
- Describe the current repository, not a target layout that does not exist yet.
- Keep technical terms in English and user-facing Dutch copy short and businesslike.
- Never maintain duplicate project instructions or duplicate skill directories.
