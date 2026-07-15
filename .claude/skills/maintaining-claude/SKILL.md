---
name: maintaining-claude
description: Sync CLAUDE.md with the current codebase state. Use after adding or removing folders, or when CLAUDE.md feels stale. Triggered by /maintaining-claude.
tools: Read, Glob, Grep, Edit
---

# Maintaining CLAUDE.md

Keep CLAUDE.md accurate and lean. Every line must earn its place in every future prompt — nothing stale, nothing missing, nothing redundant.

## When to run

- A new **folder** was added or removed in `backend/app/`, `frontend/src/`, or their subfolders
- A folder's purpose changed significantly
- CLAUDE.md feels out of sync with reality

Adding a file inside an existing folder does **not** require a CLAUDE.md update.

## Workflow

### 1. Read current CLAUDE.md

Read `.claude/CLAUDE.md` in full. Note what the Project Structure section claims exists.

### 2. Diff against actual folder structure

Glob only the folder layer — do not list individual files:

```
backend/app/*/          (core, api, models, schemas, services, reports)
backend/app/api/*/      (deps.py counts as the api/ folder; check for v1/ and any new versions)
frontend/src/*/         (lib, types, hooks, components, pages)
frontend/src/components/*/
frontend/src/pages/*/
```

Identify:
- **New folders** not in the Project Structure section
- **Deleted or renamed folders** still listed
- **Changed purpose** — a folder that was repurposed

### 3. Update Project Structure

Edit only the `## Project Structure` section in `.claude/CLAUDE.md`:
- Add new folders with a one-line role comment (≤8 words)
- Remove deleted/renamed entries
- Update comments if a folder's role changed

**Format rule:** folder paths only — no individual filenames inside them. The comment describes what kind of files live there, not which specific files.

### 4. Check for stale situational .md files

List `.claude/*.md` files (excluding the permanent docs CLAUDE.md, MEMORY.md, ARCHITECTURE.md, DATA-MODEL.md, and PRODUCTION.md). For each one referenced in CLAUDE.md:
- Is it still relevant? If not, remove the file and its reference line from CLAUDE.md.

### 5. Report changes

Output a compact summary:
- Folders added to Project Structure
- Folders removed from Project Structure
- Situational .md files added/removed

Do not output a full diff of CLAUDE.md.

## Rules

- **Folder-level only** — never list individual files in the Project Structure section
- **Never add changelogs or task notes** — git tracks history
- **One-line folder comments max** — describe the kind of files, not the specific files
- **Do not restructure CLAUDE.md** — only update the Project Structure section and add/remove specific lines; leave all other sections intact
- **Situational .md files** are for temporary context only — delete when no longer relevant
