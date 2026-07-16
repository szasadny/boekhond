# Boekhond — Plan

What we build, in which order. Delete phases here as they complete; this file describes the target, not a history.

## 1. Scope decisions (eigenaar)

- **Wie:** de eenmanszaak levert een SaaS. Klanten betalen via **Mollie**; dat is de enige omzetstroom.
- **Doel:** btw-aangifte (omzetbelasting) volledig voorbereiden; indienen blijft handmatig via Mijn Belastingdienst Zakelijk — er is geen publieke indien-API (Digipoort = PKIoverheid-certificaat voor softwareleveranciers, out of scope).
- **Btw-plichtig, géén KOR; aangifte per kwartaal.**
- **Dubbel boekhouden (double-entry):** elke transactie is een Journaalpost met debet-/creditregels op een rekeningschema (chart of accounts); som(debet) == som(credit) is een harde invariant. De UI houdt het simpel met sjabloonflows die gebalanceerde posten genereren; balans en winst & verlies komen gratis mee. Zie DATA-MODEL.md §1.
- **Inkomsten = automatische Mollie-import.** Boekhond haalt betaalde Mollie-payments (en refunds) op via de Mollie API (`howl.request`, API-key uit `.env`) en boekt ze als omzet (21% → rubriek 1a) tegen debiteuren/bank. Idempotent per `mollie_payment_id`. **Boekhond maakt zelf geen verkoopfacturen:** de SaaS-app genereert en bewaart de genummerde btw-verkoopfacturen (PDF) al; de fiscale bewaarplicht voor uitgaande facturen ligt daar. Boekhond boekt alleen de omzet.
- **Uitgaven = terugkerend + handmatig.** Vaste maandabonnementen (Resend, Claude/Anthropic, OpenAI — digitale diensten van buiten de EU, btw verlegd naar mij → rubriek 4a + 5b) worden per sjabloon maandelijks automatisch geboekt. Daarnaast een **handmatige knop** om een losse inkoopfactuur toe te voegen. Inkoopbewijs (PDF's van die diensten) komt binnen via een open uploadveld of de `data/import/`-map → import-inbox.
- **Hosting: Docker-container in een VM, alleen bereikbaar via LAN/VPN.**
- **Opslag: DSON-bestanden** (`dson` stdlib) — eigenaarskeuze, on-theme; geen database (Doge heeft geen driver; sqlite-via-subprocess afgewezen). Store-laag blijft een seam.
- **Frontend: server-rendered HTML + Dogescript** (https://github.com/dogescript/dogescript, compileert naar JS) voor client-side gedrag. **Geen issues aanmaken op dogescript** — "we have what we get"; gaten vullen met gewone JS.
- **IB-aangifte (inkomstenbelasting) is out of scope** — het jaaroverzicht (omzet/kosten per categorie) is het enige gebaar die kant op.

## 2. Phases

Each phase ends green (`doge check`, non-mutating `doge fmt` audit, `doge test`) and usable on its own. Doge v0.3.2 has no `doge fmt --check`; format temporary copies and compare them with the sources.

- **Phase 0 — Fundament (no web). ✅ DONE.** Scaffold (`doge.toml` — note: the `[dependencies]` table header is required even when empty), `lib/datum.doge`, `lib/geld.doge`, `app/services/btw.doge` (DATA-MODEL.md §2 as table-driven tests), `app/store/store.doge` (atomic DSON + audit + id-uitgifte); 24 tests green; Dockerfile + docker-compose skeleton.
- **Phase 1 — `web/` micro-framework. ✅ DONE.** `web/forms.doge` (urlencoded decode, UTF-8, multi-value), `web/html.doge` (escape + page/form/table/link builders, Hard Rule 6), `web/session.doge` (server-side in-memory `Sessies` met `crypto.token`-id + `nap`-expiry, plus `hash_wachtwoord`/`wachtwoord_klopt` met `crypto.same`), `web/static.doge` (ext→content-type, traversal-safe), `web/http.doge` (parse/response, byte-accurate Content-Length), `web/router.doge` (path-params + 404/405); alle modules getest via loopback (`howl.listen` port 0), 34 web-tests + 24 uit fase 0 groen. `main.doge` draait een dunne server (`/health` + static; login/domein-routes volgen in fase 2). Sibling-imports binnen `web/` per bare name (`so http`); `main`/tests per string-pad. Eén taalgat gevonden: `\r`-escape ontbreekt (doge#67, §3).
- **Phase 2a — Journaal + double-entry (no upload). ✅ DONE.** Login + session-gate (`afhandel`, wachtwoord-hash uit `.env`); `app/services/rekeningen.doge` (geseed standaardschema + beheer, `REK_*`-constanten); `app/services/journaal.doge` (de enige schrijver: balans-invariant, tijdvak-open-guard, audit-before-save, sjabloonflows inkoop/bank-privé/memoriaal); handlers `app/handlers/*_h.doge` + `weergave.doge` (server-rendered, geen JS); journaal-lijst/filter per tijdvak + dashboard; `main.doge` wiring (Store bij boot, ctx-op-`req`, routes). **Refactor uit fase 0 gedaan:** `btw.rubrieken` consumeert nu journaalposten en leidt de btw af (invariant 1). 75 tests groen. Twee taalfeiten vastgelegd: geen import-alias → handler-modules met `_h`-suffix; nested string-literals in `{…}`-interpolatie kunnen niet (bind eerst aan een local).
- **Phase 2b — Bijlagen + upload + Dogescript.** Binaire upload (native `recv_bytes`/`send_bytes`) via een `web/multipart.doge`-parser (op de native Bytes-search van doge#68 — §3) incl. het open uploadveld → import-inbox (bijlage zonder journaalpost = inbox-item, vandaaruit boeken); `app/services/bijlagen.doge` + handler. Dogescript-buildstap (`.djs` → `static/js/`) start hier (progressive "+regel"-knop op de memoriaalform, upload-UX; baseline blijft no-JS).
- **Phase 3 — Aangifte + reports.** Rubriekenoverzicht per kwartaal, "markeer ingediend" + vergrendeling + storno/suppletie-flow (DATA-MODEL.md §3); reports uit het journaal: balans + winst & verlies; exports: aangifte print-view + CSV, journaal-CSV per tijdvak, jaaroverzicht.
- **Phase 4 — Mollie-koppeling (inkomsten).** Mollie API via `howl.request` (key uit `.env`): betaalde payments + refunds ophalen sinds de laatste sync, elk als journaalpost boeken (omzet 1a + af te dragen btw), idempotent per `mollie_payment_id`. Getriggerd door de scheduler-pup (§Phase 5) én een handmatige "sync nu"-knop. Refund → tegenboeking.
- **Phase 5 — Terugkerende kosten + import + deploy.** Kostensjablonen (Resend/Claude/OpenAI) + scheduler-pup → loopback `/internal/run-recurring` (idempotent per maand): genereert de maandelijkse kosten-journaalposten; handmatige knop voor een losse inkoopfactuur; dagelijkse scan van de gemounte `data/import/`-map → inbox; Docker-deploy afronden (Dockerfile/compose staan als skelet vanaf de setup).

## 3. Language gaps

Open taalgaten:

- **doge#67 — string-escapes kennen geen `\r`** (known set: `\n \t \" \\ \{ \}`). CRLF-wireprotocollen (HTTP/1.1) kun je niet als literal schrijven. Stopgap: `so CRLF = bytes([13, 10]).decode()` in `web/http.doge` (+ `tests/test_http.doge`), gemarkeerd `# stopgap for doge#67` — weg zodra de ticket landt.
- **doge#68 — `Bytes` heeft geen substring-search** (`find`/`split`/`contains`): een `multipart/form-data`-body (binaire upload) parsen betekent de boundary in een rauwe `Bytes` zoeken, en dat kan alleen met een hand-rolled O(n·m) byte-scan. Nog geen stopgap in de codebase — de upload komt pas in **fase 2b**; de aanname is dat #68 dan geland is (anders wordt de byte-scan de gemarkeerde `# stopgap for doge#68`).

De stdlib dekt verder alles wat fase 0–1 nodig had: binaire sockets (`howl.recv_bytes`/`send_bytes`), `crypto` (sha256/hmac/token/same), de volledige HTTP-client (`howl.request` met headers/methods), en base64/hex (`bytes.b64()`, `str.from_b64()`/`from_hex()`).

Loop je tegen een nieuw gat aan, dan geldt Hard Rule 10: ticket op DogeLanguage/doge + de kleinste `# stopgap for doge#NN`-workaround, en hier één regel bij. **Bewust *niet* gevraagd** aan de taal: SQLite/DB-driver (DSON-bestanden zijn de juiste maat), date-arithmetic (`lib/datum.doge` hoort in userland), TLS-server (reverse proxy is het standaardantwoord), HTML-templating (userland).

## 4. What we build ourselves (and why it's ours, not the language's)

`web/` HTTP micro-framework, `lib/datum.doge`, `lib/geld.doge`, `lib/csv.doge`, `app/store/` persistence, all fiscal logic (`btw.doge`), the double-entry journaal-service + balans/W&V-rapporten, de Mollie-import (`mollie.doge`) en de terugkerende-kosten-generator (`terugkerend.doge`). Each is application-shaped, pure Doge, and a decent stress-test of the language.

## 5. Skills

Repo-scoped skills live canonically in `.agents/skills/` (Codex scans them from cwd up to the repo root): **`writing-doge`** (load-bearing — never write Doge from memory), **`modern-web-guidance`** (web UI patterns, npx-driven), and **`maintaining-agents-md`** (keeps the single source of truth and its dependent inventories current). Claude Code discovers the same three skills through name-matching relative symlinks in `.claude/skills/`; never maintain duplicate copies. The old duplicated/template skills are gone, and Codex supplies the global `skill-creator` used to validate repo skills.
