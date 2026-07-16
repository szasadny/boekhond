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
- **Phase 2b — Bijlagen: upload + import-inbox (no client JS). ✅ DONE.** Toolchain naar **Doge v0.3.3** (doge#67 + doge#68 geland, §3). `web/multipart.doge` (native `bytes.find`/`split`; body komt als rauwe Bytes uit `http.doge`), `web/html.doge` (`bestand`-file-field + `enctype` op `formulier`), `app/store/store.doge` (`bewaar_bestand`/`laad_bestand`, atomic binaire write via `fetch.write_bytes`), `app/services/bijlagen.doge` (validatie: ext-allowlist + size-cap als domein-constanten, mime uit de gevalideerde extensie; opslag onder `uploads/{jaar}/{id}{ext}`; import-inbox), `journaal.koppel_bijlage` (single writer + tijdvak-lock), `app/handlers/bijlagen_h.doge` (upload-form, inbox, koppel, session-gated download). Dashboard toont de inbox-count. CRLF-stopgap (doge#67) verwijderd. 92 tests groen; end-to-end geverifieerd (login → multipart-upload → disk/dson/audit → inbox → download → koppel).
- **Phase 2c — Dogescript.** Dogescript-buildstap (`.djs` → `static/js/`, npm-toolchain + Docker node-stage): progressive "+regel"-knop op de memoriaalform en upload-UX. Baseline blijft no-JS (alles werkt server-rendered zonder deze stap).
- **Phase 3 — Aangifte + reports.** Rubriekenoverzicht per kwartaal, "markeer ingediend" + vergrendeling + storno/suppletie-flow (DATA-MODEL.md §3); reports uit het journaal: balans + winst & verlies; exports: aangifte print-view + CSV, journaal-CSV per tijdvak, jaaroverzicht.
- **Phase 4 — Mollie-koppeling (inkomsten).** Mollie API via `howl.request` (key uit `.env`): betaalde payments + refunds ophalen sinds de laatste sync, elk als journaalpost boeken (omzet 1a + af te dragen btw), idempotent per `mollie_payment_id`. Getriggerd door de scheduler-pup (§Phase 5) én een handmatige "sync nu"-knop. Refund → tegenboeking.
- **Phase 5 — Terugkerende kosten + import + deploy.** Kostensjablonen (Resend/Claude/OpenAI) + scheduler-pup → loopback `/internal/run-recurring` (idempotent per maand): genereert de maandelijkse kosten-journaalposten; handmatige knop voor een losse inkoopfactuur; dagelijkse scan van de gemounte `data/import/`-map → inbox; Docker-deploy afronden (Dockerfile/compose staan als skelet vanaf de setup).

## 3. Language gaps

Open taalgaten:

- **doge#70 — geen sequence-repeat `*`** (`Str * Int`, `List * Int`): `"a" * 5` geeft een `TypeError` i.p.v. `"aaaaa"` (Python-stijl). Louter ergonomie, laag prioriteit; alleen geraakt in een test (een grote `Bytes` bouwen). Geen productie-stopgap nodig — de test verdubbelt een `Bytes` (`b = b + b`). Ticket op DogeLanguage/doge.

Gesloten in **v0.3.3** (waren open in 0.3.2):

- ~~**doge#67 — string-escapes kennen geen `\r`**~~ **GESLOTEN (0.3.3):** `"\r"` werkt nu. De CRLF-stopgap in `web/http.doge`/`tests/test_http.doge` is vervangen door `so CRLF = "\r\n"`.
- ~~**doge#68 — `Bytes` heeft geen substring-search**~~ **GESLOTEN (0.3.3):** `bytes.find(sub)` → Int-offset of `-1`, `bytes.split(sep)` → `List<Bytes>`, `bytes.contains(sub)` → Bool. `web/multipart.doge` gebruikt deze native; er is nooit een byte-scan-stopgap geschreven. (`bytes.index` bestaat niet.)

De stdlib dekt verder alles wat fase 0–1 nodig had: binaire sockets (`howl.recv_bytes`/`send_bytes`), `crypto` (sha256/hmac/token/same), de volledige HTTP-client (`howl.request` met headers/methods), en base64/hex (`bytes.b64()`, `str.from_b64()`/`from_hex()`).

Loop je tegen een nieuw gat aan, dan geldt Hard Rule 10: ticket op DogeLanguage/doge + de kleinste `# stopgap for doge#NN`-workaround, en hier één regel bij. **Bewust *niet* gevraagd** aan de taal: SQLite/DB-driver (DSON-bestanden zijn de juiste maat), date-arithmetic (`lib/datum.doge` hoort in userland), TLS-server (reverse proxy is het standaardantwoord), HTML-templating (userland).

## 4. What we build ourselves (and why it's ours, not the language's)

`web/` HTTP micro-framework, `lib/datum.doge`, `lib/geld.doge`, `lib/csv.doge`, `app/store/` persistence, all fiscal logic (`btw.doge`), the double-entry journaal-service + balans/W&V-rapporten, de Mollie-import (`mollie.doge`) en de terugkerende-kosten-generator (`terugkerend.doge`). Each is application-shaped, pure Doge, and a decent stress-test of the language.

## 5. Skills

Repo-scoped skills live canonically in `.agents/skills/` (Codex scans them from cwd up to the repo root): **`writing-doge`** (load-bearing — never write Doge from memory), **`modern-web-guidance`** (web UI patterns, npx-driven), and **`maintaining-agents-md`** (keeps the single source of truth and its dependent inventories current). Claude Code discovers the same three skills through name-matching relative symlinks in `.claude/skills/`; never maintain duplicate copies. The old duplicated/template skills are gone, and Codex supplies the global `skill-creator` used to validate repo skills.
