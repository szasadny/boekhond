# Boekhond — Plan & Language Blockers

Opzet d.d. 2026-07-15. What we build, in which order, and what is blocked on the Doge language. Delete phases here as they complete; keep §3 in sync with ticket status (Hard Rule 10).

## 1. Scope decisions (confirmed with the eigenaar 2026-07-15)

- **Doel:** btw-aangifte (omzetbelasting) voor één eenmanszaak volledig voorbereiden; indienen blijft handmatig via Mijn Belastingdienst Zakelijk — er is geen publieke indien-API (Digipoort = PKIoverheid-certificaat voor softwareleveranciers, out of scope).
- **Btw-plichtig, géén KOR; aangifte per kwartaal.**
- **Dubbel boekhouden (double-entry), besloten 2026-07-15:** elke transactie is een Journaalpost met debet-/creditregels op een rekeningschema (chart of accounts); som(debet) == som(credit) is een harde invariant. De UI houdt het simpel met sjabloonflows (verkoopfactuur, inkoopfactuur, bank/privé) die gebalanceerde posten genereren; balans en winst & verlies komen gratis mee. Zie DATA-MODEL.md §1.
- **Hosting: Docker-container in een VM, alleen bereikbaar via LAN/VPN.** Interim-auth (ARCHITECTURE.md §5.1) is daarmee acceptabel tot doge#61 landt.
- **Opslag: DSON-bestanden** (`dson` stdlib) — eigenaarskeuze, on-theme; geen database (Doge heeft geen driver; sqlite-via-subprocess afgewezen). Store-laag blijft een seam.
- **Frontend: server-rendered HTML + Dogescript** (https://github.com/dogescript/dogescript, compileert naar JS) voor client-side gedrag. **Geen issues aanmaken op dogescript** — "we have what we get"; gaten vullen met gewone JS.
- **Facturen inladen, beide richtingen:** een open uploadveld + import-inbox voor (a) eigen facturen die al naar klanten zijn gestuurd en (b) facturen van abonnementen/diensten die de eigenaar gebruikt. Daarnaast blijft het genereren van eigen terugkerende maandfacturen in scope.
- **IB-aangifte (inkomstenbelasting) is out of scope** — het jaaroverzicht (omzet/kosten per categorie) is het enige gebaar die kant op.
- Naam "Boekhond" blijft de werknaam.

## 2. Phases

Each phase ends green (`doge check`/`fmt`/`test`) and usable on its own.

- **Phase 0 — Fundament (no web). ✅ DONE 2026-07-15.** Scaffold (`doge.toml` — note: the `[dependencies]` table header is required even when empty), `lib/datum.doge`, `lib/geld.doge`, `app/services/btw.doge` (DATA-MODEL.md §2 as table-driven tests), `app/store/store.doge` (atomic DSON + audit + id-uitgifte); 24 tests green (`doge test "$PWD/tests"`); Dockerfile + docker-compose skeleton. Proved Doge on the domain before any HTTP exists.
- **Phase 1 — `web/` micro-framework.** http parse/response, router, urlencoded forms, html builders + escaping, sessions, static files; tested via loopback (`howl.listen` port 0 — the stdlib echo pattern).
- **Phase 2 — Journaal + bijlagen (double-entry).** Login; rekeningschema geseed + beheer; journaalpost-invoer via sjabloonflows (verkoopfactuur/inkoopfactuur/bank/privé) + vrije memoriaalpost, balans-invariant afgedwongen; mutaties alleen in open tijdvakken; upload via base64-shim (§3) incl. het open uploadveld → import-inbox (bijlage zonder journaalpost = inbox-item, vandaaruit boeken); journaal-lijst/filter per tijdvak, dashboard. Dogescript-buildstap (`.djs` → `static/js/`) start hier. **Refactor uit fase 0:** `btw.rubrieken` gaat van platte boekingen-dicts naar journaalregels als input (zelfde code→rubriek-mapping, tests mee).
- **Phase 3 — Aangifte + reports.** Rubriekenoverzicht per kwartaal, "markeer ingediend" + vergrendeling + storno/suppletie-flow (DATA-MODEL.md §3); reports uit het journaal: balans + winst & verlies; exports: aangifte print-view + CSV, journaal-CSV per tijdvak, jaaroverzicht.
- **Phase 4 — Verkoopfacturen.** Concept → definitief (nummering + journaalpost debiteuren/omzet/btw), factuur-HTML met print-CSS, creditfactuur.
- **Phase 5 — Terugkerende facturen + import.** Sjablonen + scheduler-pup → loopback `/internal/run-recurring` (idempotent per dag); dagelijkse scan van de gemounte `data/import/`-map → inbox (abo-facturen automatisch inladen); Docker-deploy afronden (Dockerfile/compose staan als skelet vanaf de setup).
- **Phase 6 — Upstream upgrades.** As tickets land: real multipart (#60/#63, delete shims), real auth crypto (#61), API-invoer facturen (#62). Not scheduled — event-driven.

## 3. Doge language gaps — tickets filed 2026-07-15

| Ticket | Gap | Blocks | Stopgap until it lands |
| --- | --- | --- | --- |
| [doge#60](https://github.com/DogeLanguage/doge/issues/60) | `howl` has no `recv_bytes`/`send_bytes` — sockets are Str-only, binary bodies impossible | Multipart PDF-upload; byte-accurate `Content-Length` framing | Browser shim `static/upload.js`: file → base64 → hidden form field (body stays ASCII); serve downloads via `fetch.read_bytes` + hex-free ASCII framing |
| [doge#61](https://github.com/DogeLanguage/doge/issues/61) | No crypto: hash/HMAC/CSPRNG/constant-time compare | Secure sessie-tokens + wachtwoord-hash | Bind 127.0.0.1 achter reverse proxy; token uit `roll`; documented in ARCHITECTURE.md §5.1 — **not internet-safe on its own** |
| [doge#62](https://github.com/DogeLanguage/doge/issues/62) | HTTP client: no headers/methods/response-headers | Automatic invoice ingestion via supplier APIs (Goal Architecture) | None needed for MVP |
| [doge#63](https://github.com/DogeLanguage/doge/issues/63) | No base64 encode/decode on Bytes | Upload-shim decode; Basic auth | `lib/base64.doge` in userland (decode → List of Ints → `bytes(list)`), marked `# stopgap for doge#63` |
| [doge#64](https://github.com/DogeLanguage/doge/issues/64) | **Bug:** relative script paths inside a project fail (`doge check lib/x.doge` → "could not open the project directory") | Dev-workflow comfort | Use absolute paths: `doge check "$PWD/lib/x.doge"`, `doge test "$PWD/tests"` |
| [doge#65](https://github.com/DogeLanguage/doge/issues/65) | **Bug:** `so` constants declared in a test file are `none` when `doge test` runs the tests (module constants are fine) | Test fixtures | Zero-arg helper function instead of a constant — and don't let its name start with `test`, or the runner executes it as a test |

**Consciously *not* filed:** SQLite/DB driver (JSON files are the right size for this app; a DB story is a language-roadmap call, not our need), date arithmetic (`lib/datum.doge` is fine userland), TLS server (reverse proxy is the standard answer), HTML templating (userland).

## 4. What we build ourselves (and why it's ours, not the language's)

`web/` HTTP micro-framework, `lib/datum.doge`, `lib/geld.doge`, `lib/csv.doge`, `app/store/` persistence, all fiscal logic (`btw.doge`), the double-entry journaal-service + balans/W&V-rapporten, factuur-rendering. Each is application-shaped, pure Doge, and a decent stress-test of the language.

## 5. Open questions

None — alle §1-beslissingen zijn 2026-07-15 door de eigenaar bevestigd.

## 6. Reference docs from the template project

`.claude/skills/` still contains skills inherited from the Keurix template: `modern-web-guidance` (useful — web UI), `maintaining-claude`, `skill-creator` (generic), and `function-index` (**Keurix/Python-specific — its indexer script doesn't exist here; rebuild for Doge or remove when Phase 1 code exists**). `writing-doge` is copied from the Doge repo and is the load-bearing one.
