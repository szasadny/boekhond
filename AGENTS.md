# Boekhond — Agent instructions

Self-hosted boekhouding voor één Nederlandse **eenmanszaak** (single user, LAN/VPN-only), written entirely in **Doge** (https://github.com/DogeLanguage/doge) — this is the language's first real application. Goal: de **btw-aangifte** (omzetbelasting) per kwartaal volledig voorbereiden zonder handwerk; indienen blijft handmatig via Mijn Belastingdienst Zakelijk.

This file is the single source of truth and loads into every turn — keep it lean. Depth lives in [docs/](docs/), pulled in on demand via the routing table. When you change what a section describes, update it here in the same change; never let this file and the code drift.

## Agents: sol plans, luna builds

This repo is set up for a two-model workflow via `.codex/config.toml` and `.codex/agents/`:

- **Main session / orchestrator = GPT-5.6-Sol** — understands the task, produces the plan, delegates implementation, and reviews results. Never implements large diffs itself when an executor can.
- **`executor` = GPT-5.6-Luna (high)** — implements one well-scoped plan step at a time (files named, approach decided). Delegate implementation here; give it the exact files, the pattern to copy, and the tests to run.

Delegation rules: plan first, then hand the executor self-contained steps (it does not see your conversation). Review every executor diff against the Hard Rules before reporting done. Trivial one-file fixes: just do them in the main session, no delegation overhead.

## Start here — task routing

Match the task, do the action **before** reading code or writing anything:

| Task involves… | First… |
| --- | --- |
| Writing, editing, or debugging **any `.doge` file** | Load the **`writing-doge`** skill — Python instincts get Doge wrong; never write Doge from memory |
| A new UI element (form, table, dialog) | Use the **`modern-web-guidance`** skill (`search "<topic>"`) — server-rendered HTML, no JS framework |
| `AGENTS.md`, repo layout, or skill inventory is stale | Load the **`maintaining-agents-md`** skill — keep dependent inventories and the Claude import bridge aligned |
| Entities, btw-codes, or rubriek-mapping | Read [docs/DATA-MODEL.md](docs/DATA-MODEL.md) — and update it in the same change |
| A change crossing layers or a new shared module | Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) §0/§2/§5 — and update it in the same change |
| Roadmap, phasing, "what's blocked on the language" | Read [docs/PLAN.md](docs/PLAN.md) |
| Where any new piece of code belongs | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) §0 lookup table — every concern has exactly one home |
| Adding/removing a folder | Update the Project map below in the same change |

## Hard Rules

Never acceptable to break — including during debugging or hot fixes.

1. **Money is `Decimal`, never `Float`.** Amounts enter via `dec(str)`, are stored in DSON as strings (`dson.emit` of a Decimal is a deliberate `TypeError` — DSON numbers are octal), and never touch a Float. Mixing Decimal and Float is a Doge `TypeError` — a feature; fix the source, never `float()` around it.
2. **Every imported/generated boeking lands exactly once.** A Mollie-payment maps to at most one journaalpost (unique `mollie_payment_id`); a kostensjabloon to at most one post per month. Re-running the sync/scheduler never double-books, and every import is an audit event. Boekhond issues **no** verkoopfacturen — the SaaS-app already generates and retains the numbered btw-verkoopfacturen; income is booked from Mollie.
3. **Fiscale bewaarplicht (7 jaar): nothing in an ingediend tijdvak is ever mutated or deleted** — no journaalpost edit, no bijlage delete. Corrections are a new tegenboeking (storno) in the current open tijdvak, flagged for suppletie. Attachments are never deleted at all.
4. **Every write to `data/` goes through `app/store/`** — atomic tmp-file + rename, plus an append to `audit.dsonl`. Never a direct `fetch.write` from a handler or service.
5. **All btw logic lives in `app/services/btw.doge`** — tarieven, btw-code → rubriek mapping, afronding. No other file computes btw.
6. **Every piece of user input rendered into HTML goes through the escaping helpers in `web/html.doge`** — never raw string interpolation of stored data (XSS).
7. **Uploads are validated** (extension allow-list, size cap) and stored under a generated name; the original filename is metadata only, never a path.
8. **Secrets and instance config in `.env` only** — never in source, not even as fallback defaults.
9. **Everything the wet touches gets a test with a known-good outcome** — rubriek sums, afronding, import-idempotentie, tijdvak boundaries. `doge test tests` must stay green.
10. **A Doge language gap becomes a ticket on DogeLanguage/doge, plus the smallest possible userland stopgap** — clearly marked `# stopgap for doge#NN` so it can be deleted when the ticket lands. Never silently build a permanent workaround for something that belongs in the language. Open gaps: [docs/PLAN.md](docs/PLAN.md) §3.

## Domain in one screen

Dubbel boekhouden: elke transactie is een **Journaalpost** met debet-/creditregels op een rekeningschema (chart of accounts); som(debet) == som(credit) altijd. Omzet-/kostenregels dragen een `btw_code` die exact op één aangifte-rubriek mapt (1a/1b/1e/2a/3a/3b/4a/4b/5b — [docs/DATA-MODEL.md](docs/DATA-MODEL.md) §2). Posten ontstaan automatisch (Mollie-import = omzet 21% → 1a, idempotent per `mollie_payment_id`; terugkerende maandabonnementen van buiten de EU → 4a + 5b) of via een sjabloonflow (inkoop, bank/privé) of een vrije memoriaalpost. Inkoopbewijs komt via een open uploadveld of `data/import/` in de import-inbox; 7 jaar bewaard. Per kwartaal berekent de app alle rubrieken; de ondernemer neemt ze over in Mijn Belastingdienst Zakelijk en markeert het tijdvak ingediend → snapshot + slot (Hard Rule 3).

## Stack

- **Language:** Doge (`doge.toml` project; update via `cargo install dogelang` — the local binary goes stale). Doge is now v0.3.4.
- **Web:** own micro-framework on `howl` raw TCP in `web/` (HTTP/1.1 parse, router, cookies, forms, html escaping, static). No JS framework.
- **Frontend:** server-rendered HTML + **Dogescript** (compiles to JS; source `static/djs/`, build → `static/js/`). **Never file issues on dogescript** — gaps → plain JS.
- **Persistence:** DSON files in `data/` via `app/store/` (atomic writes + append-only `audit.dsonl`). No database — volume is tiny.
- **Geen app-auth:** single user, geen login/wachtwoord. De enige toegangsgrens is het netwerk (LAN/VPN-only, achter een reverse proxy) — bewuste keuze, geen zwakke auth. `.env` houdt alleen niet-user-secrets (`INTERN_TOKEN`, `MOLLIE_API_KEY`).
- **Scheduler:** one `pack.zoom` pup (daily ~06:00) POSTs loopback `/internal/run-recurring` — guarded on `INTERN_TOKEN` (`crypto.same`) + a loopback-peer-check (`howl.peer`), runs Mollie-sync + terugkerende kosten + import-scan (each idempotent). Pups share no state — loopback HTTP is the only channel.
- **Deploy:** `doge build` → single binary in a Docker container inside a VM (`data/` as volume), LAN/VPN only. The container binds `0.0.0.0` via `BIND_HOST` (compose overrides the loopback default) so the published port reaches it.

## Project map

Read only the folder relevant to the task; grep before scanning.

```text
doge.toml               # manifest, entry = main.doge ([dependencies] header required even when empty)
package.json            # npm-toolchain voor de Dogescript-build (build-js.mjs → static/js/; dogescript library-API)
main.doge               # boot: config (.env), store load, scheduler pup, accept-loop, route table
web/                    # generic HTTP micro-framework (HTTP/1.1 parse, router, cookies, forms, multipart, html escaping, static; never imports app/)
app/handlers/           # one <resource>_h.doge per resource + weergave.doge (shared nav/foutbanner); _h avoids the service-import name clash
app/services/           # business logic: btw, journaal, rekeningen, bijlagen, mollie, aangifte, rapporten, terugkerend
app/store/              # store.doge (atomic DSON + audit), one load/save per collection
lib/                    # domain-free helpers: datum, geld, csv
static/djs/ , static/js/, static/   # Dogescript source, compiled output (gitignored), css/favicon
tests/                  # doge test — mirrors app/: test_btw.doge, test_store.doge, …
data/                   # runtime state (gitignored): *.dson, uploads/, import/, audit.dsonl
docs/                   # ARCHITECTURE, DATA-MODEL, PLAN — the on-demand reference set
.agents/skills/         # canonical repo skills: writing-doge, modern-web-guidance, maintaining-agents-md
.claude/                # CLAUDE.md imports AGENTS.md; skills/ symlinks to .agents/skills/
.codex/                 # config.toml + agents/ (executor)
```

## Conventions

- **Doge style:** four-space indent, `doge fmt` clean, `doge check` before every run; module files hold only definitions; every function/object and the file itself closes with `wow`.
- **Layers:** handlers do HTTP (parse → service → render), services do behaviour, store does persistence. `web/` never imports from `app/`.
- **Errors:** services `bonk` domain errors; the outer request loop catches everything and renders a 500 without leaking internals.
- **Language:** identifiers in Dutch domain terms where the wet uses them (boeking, rubriek, tijdvak); user-facing copy in het Nederlands — kort en zakelijk, geen em-dashes of AI-marketingtoon. **Technical terms and jargon stay English** — never verdutchen (no "opslag", "persistentie", "domeinvrij"); mixed Dutch prose with English jargon is the house style.
- **Dates:** `YYYY-MM-DD` strings everywhere; all date math via `lib/datum.doge` (`nap` has no date arithmetic).
- **No magic values:** tarieven/limieten → `app/services/btw.doge` (fiscaal); paden/secrets → `.env`.

## Testing

- `doge check <file>` — fastest syntax/semantic feedback; run it constantly.
- `doge test tests` — full suite; runs every zero-arg `test_*` function (`amaze` assertions). Fixture helpers must **not** start with `test` (the runner would execute them).
- `doge fmt "$PWD/<file>"` — canonical in-place formatting. Doge v0.3.2 has no `--check`; audit without mutations by formatting temporary copies and comparing them with the sources.
- Fiscale rekenregels (Hard Rule 9) get table-driven tests with hand-checked expected values.

## Definition of done

`doge check` + non-mutating `doge fmt` audit + `doge test tests` green; [docs/DATA-MODEL.md](docs/DATA-MODEL.md) / [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) updated in the same change when entities or layer boundaries changed; Hard Rules intact. Scope tightly — a bug fix changes the bug, a feature adds the feature; flag observed debt instead of silently fixing it.
