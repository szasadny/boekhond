# Boekhond — Self-hosted boekhouding voor een Nederlandse eenmanszaak

> **Boekhond** (boekhouden → boek·hond). Written entirely in **Doge** (https://github.com/DogeLanguage/doge) — this is the language's first real application, so when you hit a language gap, file it as a ticket on DogeLanguage/doge instead of working around it silently (Hard Rule 10). None are open right now — see [PLAN.md](./PLAN.md) §3.

## Start Here — Task Routing

Match the task against this table and do the listed action **before** reading code or writing anything:

| If the task involves… | Then first… |
| --- | --- |
| Writing, editing, or debugging **any `.doge` file** | Run `/writing-doge` — Python instincts get Doge wrong; never write Doge from memory |
| A new UI element (form, table, dialog) in the web interface | Run `/modern-web-guidance search "<topic>"` — server-rendered HTML, no JS framework |
| A change to entities, btw-codes, or rubriek-mapping | Read [DATA-MODEL.md](./DATA-MODEL.md) — and update it in the same change |
| A change crossing layers or a new shared module | Read [ARCHITECTURE.md](./ARCHITECTURE.md) §0/§2/§5 — and update it in the same change |
| Adding or removing a folder | Run `/maintaining-claude` afterwards |
| Roadmap, phasing, or "what's blocked on the language" | Read [PLAN.md](./PLAN.md) |
| Deciding where any new piece of code belongs | [ARCHITECTURE.md](./ARCHITECTURE.md) §0 lookup table — every concern has exactly one home |

## Hard Rules

Breaking any of these is never acceptable — including during debugging or hot fixes.

1. **Money is `Decimal`, never `Float`.** Amounts enter via `dec(str)`, are stored in DSON as strings (`dson.emit` of a Decimal is a deliberate `TypeError` — DSON numbers are octal), and never touch a Float. Mixing Decimal and Float is a Doge `TypeError` — that error is a feature, fix the source, never `float()` around it.
2. **Every imported/generated boeking lands exactly once.** A Mollie-payment maps to at most one journaalpost (unique `mollie_payment_id`); a kostensjabloon to at most one post per month. Re-running the sync or scheduler never double-books, and every import is an audit event. Boekhond does **not** issue its own verkoopfacturen — the SaaS-app already generates and retains the numbered btw-verkoopfacturen; income is booked from Mollie.
3. **Fiscale bewaarplicht (7 jaar): nothing in an ingediend tijdvak is ever mutated or deleted** — no journaalpost edit, no bijlage delete. Corrections are a new tegenboeking (storno) in the current open tijdvak, flagged for suppletie. Attachments are never deleted at all.
4. **Every write to `data/` goes through `app/store/`** — atomic tmp-file + rename, plus an append to `audit.dsonl`. Never a direct `fetch.write` from a handler or service.
5. **All btw logic lives in `app/services/btw.doge`** — tarieven, btw-code → rubriek mapping, afronding. No other file computes btw.
6. **Every piece of user input rendered into HTML goes through the escaping helpers in `web/html.doge`** — never raw string interpolation of stored data (XSS).
7. **Uploads are validated** (extension allow-list, size cap) and stored under a generated name; the original filename is metadata only, never a path.
8. **Secrets and instance config in `.env` only** — never in source, not even as fallback defaults.
9. **Everything the wet touches gets a test with a known-good outcome** — rubriek sums, afronding, import-idempotentie, tijdvak boundaries. `doge test tests` must stay green.
10. **A Doge language gap becomes a ticket on DogeLanguage/doge, plus the smallest possible userland stopgap** — clearly marked `# stopgap for doge#NN` so it can be deleted when the ticket lands. Never silently build a permanent workaround for something that belongs in the language.

## Domain

Self-hosted ledger/boekhoudapp voor één Nederlandse **eenmanszaak** (single user) die een SaaS levert. Doel: de **btw-aangifte** (omzetbelasting) volledig voorbereiden zonder handwerk.

- **Dubbel boekhouden (double-entry)** — elke transactie is een **Journaalpost** met debet-/creditregels op een rekeningschema (chart of accounts); som(debet) == som(credit) altijd. Omzet-/kostenregels dragen een `btw_code` die exact op één aangifte-rubriek mapt (1a/1b/1e/2a/3a/3b/4a/4b/5b — zie [DATA-MODEL.md](./DATA-MODEL.md) §2). Posten ontstaan automatisch (Mollie, terugkerend) of via een sjabloonflow (inkoop, bank/privé) of een vrije memoriaalpost.
- **Inkomsten uit Mollie** — Boekhond haalt betaalde Mollie-payments (+ refunds) op via de Mollie API (`howl.request`) en boekt ze als omzet (21% → rubriek 1a), idempotent per `mollie_payment_id`. **Geen eigen verkoopfacturen:** de SaaS-app maakt en bewaart de genummerde verkoopfacturen al (Hard Rule 2).
- **Uitgaven: terugkerend + handmatig** — vaste maandabonnementen (Resend, Claude/Anthropic, OpenAI — diensten van buiten de EU, btw verlegd → rubriek 4a + 5b) worden per sjabloon maandelijks automatisch geboekt; een handmatige knop voegt een losse inkoopfactuur toe.
- **Bijlagen + import-inbox** — inkoopbewijs (PDF's/afbeeldingen van gebruikte diensten) geüpload via de webinterface (open uploadveld) of automatisch ingeladen uit `data/import/`. Een bijlage zonder journaalpost staat in de inbox en wordt vandaaruit geboekt; 7 jaar bewaard.
- **Aangifte** — per kwartaal berekent de app alle rubrieken; de ondernemer neemt ze over in Mijn Belastingdienst Zakelijk (er is géén publieke indien-API — Digipoort vereist een PKIoverheid-certificaat en is out of scope). Daarna: tijdvak "ingediend" markeren → snapshot + slot (Hard Rule 3).
- **Exports & reports** — aangifte-overzicht (print/CSV), journaal-CSV per tijdvak, balans + winst & verlies, jaaroverzicht (input voor de IB-aangifte).

## Stack

| Layer | Technology |
| --- | --- |
| Language | Doge (`doge.toml` project; install/update via `cargo install dogelang` — check the local binary is current, it goes stale) |
| Web server | Own micro-framework on `howl` raw TCP — `web/` (HTTP/1.1 parsing, router, cookies, forms, html escaping, static) |
| Frontend | Server-rendered HTML + **Dogescript** (compileert naar JS; bron in `static/djs/`, build → `static/js/`). **Never file issues on dogescript** — "we have what we get"; gaps → plain JS |
| Persistence | DSON files in `data/` via `app/store/` (atomic writes + append-only `audit.dsonl`) — no database; volume is tiny |
| File storage | `data/uploads/{jaar}/`; import-inbox via `data/import/` (mounted volume, daily scan) |
| Auth | Single user, wachtwoord uit `.env` (plaintext secret, door de app bij inladen gehasht), sessie-cookie. `crypto` stdlib: `token` sessie-id, `sha256` hash, `same` constant-time compare. App is **LAN/VPN-only** (decided) |
| Scheduler | One `pack.zoom` pup that POSTs loopback `/internal/run-recurring` (terugkerende kosten + Mollie-sync; pups share no state — loopback HTTP is the only channel to the main loop) |
| Deploy | `doge build` → single binary in a **Docker container inside a VM** (Dockerfile + docker-compose, `data/` as volume), LAN/VPN only |

## Project Structure (target — see PLAN.md for phasing)

```text
doge.toml               # package manifest, entry = main.doge
main.doge               # boot: config, store load, scheduler pup, accept-loop
web/                    # generic HTTP micro-framework (no domain knowledge)
  http.doge, router.doge, forms.doge, html.doge, static.doge, session.doge
app/
  handlers/             # one file per resource: journaal, bijlagen, kosten, aangifte, rekeningen, instellingen, intern
  services/             # business logic: btw.doge, journaal.doge (balans-invariant + sjabloonflows), mollie.doge (inkomsten-import), aangifte.doge, rapporten.doge (balans/W&V), terugkerend.doge (kostensjablonen)
  store/                # store.doge (atomic DSON + audit), one load/save per collection
lib/                    # domain-free helpers: datum.doge, geld.doge, csv.doge
static/djs/             # Dogescript sources (client-side gedrag)
static/js/              # compiled output van djs — gegenereerd, niet handmatig bewerken
static/                 # css, favicon
templates in code       # HTML via web/html.doge builders — no template files
tests/                  # doge test — mirrors app/: test_btw.doge, test_store.doge, …
data/                   # runtime state — gitignored; instellingen.dson, rekeningen.dson, journaal.dson, …, uploads/, import/, audit.dsonl
Dockerfile, docker-compose.yml   # deploy: container in VM, data/ als volume
.env                    # secrets: WACHTWOORD, INTERN_TOKEN, MOLLIE_API_KEY, POORT, DATA_DIR
```

**Navigation rule:** read only the folder relevant to the task. Grep before scanning.

## Conventions

- **Doge style:** four-space indent, `doge fmt` clean, `doge check` before every run; module files hold only definitions; every function/object closes with `wow`.
- **Layers:** handlers do HTTP (parse → service → render), services do behaviour, store does persistence. `web/` never imports from `app/`.
- **Errors:** services `bonk` domain errors; the outer request loop catches everything and renders a 500 without leaking internals.
- **Language:** code + identifiers in Dutch domain terms where the wet uses them (boeking, rubriek, tijdvak); user-facing copy in het Nederlands — kort en zakelijk, geen em-dashes of AI-marketingtoon. **Technical terms and jargon always stay English** — never translate them into Dutch (no "opslag" for storage, no "persistentie", no "domeinvrij"); mixed Dutch prose with English jargon is the house style (owner preference).
- **Dates:** `YYYY-MM-DD` strings everywhere; all date math via `lib/datum.doge` (Doge's `nap` has no date arithmetic).
- **No magic values:** tarieven/limieten/paden → `app/services/btw.doge` (fiscaal) or config uit `.env`.

## Testing

- `doge check <file>` — fastest syntax/semantic feedback, run it constantly.
- `doge test tests` — full suite; discovers `test_*.doge` files, runs every zero-arg `test_*` function (`amaze` assertions). Fixture helpers must not start with `test` (the runner would execute them).
- `doge fmt "$PWD/<file>"` — canonical formatting (`--check` in CI).
- Fiscale rekenregels (Hard Rule 9) get table-driven tests with hand-checked expected values.

## Working Approach

- **Before writing:** `/writing-doge` first for any `.doge` work; grep `web/` and `app/` for the existing pattern and match it.
- **Blocked on the language?** File the ticket (Hard Rule 10), implement the smallest marked stopgap, record it in [PLAN.md](./PLAN.md) §3. (No gaps are open right now — the stdlib covers binary sockets, `crypto`, the HTTP client, and base64/hex.)
- **Scope tightly:** a bug fix changes the bug, a feature adds the feature; flag observed debt instead of silently fixing it.
- **Definition of done:** `doge check` + `doge fmt --check` + `doge test` green; DATA-MODEL.md/ARCHITECTURE.md updated in the same change when entities or layer boundaries changed; Hard Rules intact.
- **Maintaining these docs:** never add changelogs here; complex multi-prompt context gets a `.claude/<topic>.md` + one reference line, deleted when stale.
