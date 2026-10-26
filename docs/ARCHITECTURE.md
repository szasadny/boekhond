# Boekhond — Architecture

Authoritative reference for the system's shape. Jump to the section you need and **update it when you change what it describes**. The data model lives in [DATA-MODEL.md](./DATA-MODEL.md).

| § | Contents |
| --- | --- |
| 0 | Lookup table — where does X go? |
| 1 | Guiding principles |
| 2 | Topology & request lifecycle |
| 3 | The `web/` micro-framework contract |
| 4 | Persistence: store, audit, uploads |
| 5 | Cross-cutting: scheduler, exports, config |
| 6 | Doge-specific constraints that shaped this design |
| 7 | Goal architecture — NOT instructions |

---

## 0. Quick Lookup — where does X go?

| You are adding / changing… | It goes in… |
| --- | --- |
| A business rule or behaviour | `app/services/<domein>.doge` — never in a handler |
| Anything that computes btw (tarief, rubriek, afronding) | `app/services/btw.doge` — the only file that knows fiscal math (Hard Rule 5) |
| Journaalpost-creation, balans-invariant, sjabloonflows (inkoop/bank/privé/memoriaal) | `app/services/journaal.doge` — the only place that writes journaalposten |
| Rekeningschema: seed, lookup, unique-nummer validation, deactiveren en weer activeren | `app/services/rekeningen.doge` — master-data; owns the `REK_*` constants `journaal.doge` binds to |
| Mollie-inkomsten ophalen + boeken (idempotent per `mollie_payment_id`; refunds als tegenboeking, idempotent per `mollie_refund_id`) | `app/services/mollie.doge` — bouwt gebalanceerde omzet-posten (geld-been op Bank 1100), roept `journaal.doge` |
| Terugkerende maandkosten: sjabloon-beheer + maandpost genereren (idempotent per sjabloon+maand) | `app/services/terugkerend.doge` — bouwt de maandpost via `journaal.inkoop_post` (btw-splitsing hangt aan de `btw_code`); sjablonen in `valuta` EUR of USD, niet-EUR wordt bij het boeken omgerekend via een koersbron (`genereer(store, vandaag, koersbron)`, koers + vreemd bedrag als metadata op de post; geen koersbron/koersfout of een weigering van `journaal.bewaar` → fout-melding, sjabloon blijft ongeboekt tot de volgende run en de rest draait door); getriggerd door de knop (`terugkerend_h`) én door de scheduler-pup (`intern_h.run_recurring`, §5.2) |
| Wisselkoers ophalen + omrekenen (vreemde valuta → EUR) | `app/services/wisselkoers.doge` — `VALUTA` allow-list, `Wise(token).koers(van, naar)` (Wise rates-API via `howl.request`, `WISE_API_TOKEN`), pure `lees_koers` (`json.parse(body, {"numbers": "decimal"})` → rate als exacte Decimal, nooit een Float) en `omreken` (Decimal, half-up op centen via `geld.rond2`) |
| De drie terugkerende stappen samen draaien (scheduler + handmatig) | `app/handlers/intern_h.doge` `run_recurring` — token-guard (`crypto.same` op `INTERN_TOKEN`) + `mollie.sync` + `terugkerend.genereer` + `bijlagen.scan_import`, elk idempotent; de scheduler-pup in `main.doge` POSTt hier dagelijks (`datum.seconden_tot_uur` + `nap.rest`) |
| Bijlagen: upload-validatie (ext-allowlist + size-cap), opslag `uploads/{jaar}/{id}.{ext}`, import-inbox, `data/import/`-scan, koppelen | `app/services/bijlagen.doge` — owns de allow-list/size-cap/mime-constanten; `scan_import` leest de import-map via store (`import_lijst`/`import_verwijder`) en boekt elk bestand via `bewaar(..., "import")`, bronfile daarna verwijderd (idempotent); roept `journaal.koppel_bijlage` voor de post-kant (single writer) |
| Een `multipart/form-data` body (binaire upload) parsen | `web/multipart.doge` — domeinvrij; native `bytes.find`/`split`; input = rauwe Bytes-body + boundary uit Content-Type |
| Een geüploade bijlage terugserveren (download) | een router-route (`app/handlers/bijlagen_h.doge` `download`), **nooit** onder `/static/` — leest de bytes uit de `bijlagen.dson`-metadata (§5.6) |
| De read-only detailpagina van een journaalpost (regels, gekoppelde bijlagen, storno-status) | `app/handlers/journaal_h.doge` `detail` op `GET /journaal/{id}`, in `main.doge` na de vaste `/journaal/*`-routes geregistreerd (de eerste match wint); onbekend id = 404 |
| Aangifte-lifecycle: markeer ingediend (snapshot + tijdvak-lock), storno/suppletie-signaal, openstaande tijdvakken (oudste = te-doen, te laat na de deadline) + tijdvakkenlijst (journaal-keuze), saldo-uitleg per post | `app/services/aangifte.doge` — schrijft het Aangifte-record, leest rubrieken uit `btw.doge`, storno via `journaal.storno_post`; `uitleg` = `btw.specificatie` (per post op de cent) + controle of de geboekte btw (1510/1520) per post aansluit op de btw-codes; `aansluiting` = dezelfde controle over het hele tijdvak tegen de 1510/1520-beweging (btw-afrekeningen uitgezonderd) |
| Export/import van de volledige administratie tussen instances (één JSON-bundel, import alleen op een lege instance) | `app/services/overdracht.doge` — `exporteer` (alle collecties + bijlagen als base64 + `audit.dsonl`), `importeer` (valideert alles vóór de eerste write: formaat/versie, balans per post, bijlage-pad via `bijlagen.geldig_pad`, grootte; daarna audit, bestanden, collecties); handler `overdracht_h` (`/overdracht`), bundelformaat in [DATA-MODEL.md](./DATA-MODEL.md) §5 |
| Balans / winst & verlies / jaaroverzicht aggregation | `app/services/rapporten.doge` — reads the journaal, never writes |
| A new page or form endpoint | `app/handlers/<resource>_h.doge` — shape: parse request → call service → render via `web/html.doge`. Copy an existing handler. Shared view helpers (nav, foutbanner, btw-opties, bedrag-normalisatie, vorige/volgende-kwartaallinks `kwartaal_nav`, redirect-doel `tijdvak_href`) in `app/handlers/weergave.doge`. Na een geslaagde boeking redirect de handler naar de pagina van het tijdvak van de post, niet naar het huidige kwartaal. |
| A route registration | `main.doge` route table — handlers never self-register |
| A read/write of any `data/` file | `app/store/store.doge` (atomic write + audit append) — Hard Rule 4 |
| A new entity / JSON collection | `app/store/` load/save pair + [DATA-MODEL.md](./DATA-MODEL.md) entry + a migration note if the shape of an existing file changes |
| HTML structure, escaping, form/table builders | `web/html.doge` — handlers compose builders, never concatenate raw HTML |
| HTTP parsing, cookies, static files | `web/` — must stay domain-free (no `app/` imports) |
| Client-side gedrag (progressive enhancement: +regel, upload-UX) | `static/djs/boekhond.djs` (Dogescript) → `npm run build` → `static/js/boekhond.js`, site-wide deferred geladen door `html.pagina`. Feature-detected; baseline blijft no-JS (§5.3) |
| Date math (kwartaal, maandlengte, scheduler-timing) | `lib/datum.doge` |
| Money parsing/formatting/afronding (`"1.234,56"` ↔ Decimal; `rond2` = half-up met altijd precies twee decimalen) | `lib/geld.doge` |
| A CSV export | `lib/csv.doge` (generic writer) + the shaping in the owning service |
| A user-facing (Dutch) error or label string | constants at the top of the owning handler/service — one home per string, no duplicates |
| A config value / secret | `.env`, read once at boot in `main.doge` into a config Dict passed down — never `env.get` scattered through the code |
| A background/periodic action | the scheduler pup in `main.doge` → loopback POST `/internal/<naam>` handler (§5.2) — never a sleep loop inside the request path |
| A language-gap stopgap | `lib/` with a `# stopgap for doge#NN` comment (Hard Rule 11) |
| A test | `tests/test_<module>.doge` — table-driven for fiscal rules |

---

## 1. Guiding Principles

1. **Modular by contract.** Handlers do HTTP, services do behaviour, store does persistence, `web/` is a reusable domain-free framework. No layer reaches across.
2. **Single source of truth.** Fiscal rules in `btw.doge`, persistence in `store.doge`, escaping in `html.doge`. Duplication of a fiscal rule is a compliance bug, not just debt.
3. **Boring beats clever.** One user, tiny data volume: sequential request handling, JSON files, server-rendered HTML. Complexity needs a demonstrated reason.
4. **Audit-first.** Every mutation is an append to `audit.dsonl` before it is state. The administratie must be reconstructable (bewaarplicht).
5. **The language is young — push gaps upstream.** A missing primitive becomes a DogeLanguage/doge ticket + minimal marked stopgap (Hard Rule 11), so this app makes the language better instead of accumulating workarounds.

---

## 2. Topology & Request Lifecycle

```text
Browser (LAN/VPN) ──HTTP──▶ VM/LXC ▸ Docker container ▸ boekhond binary
                                                              │
                                    ┌─────────────────────────┤
                                    ▼                         ▼
                              accept pup → pup per       scheduler pup (pack.zoom)
                              verbinding (http.serveer)  sleeps until 06:00,
                              parse, ──bowl──▶ main      POST /internal/run-recurring
                                    │   (sequential)     via howl.request loopback
                                    ▼                    (Mollie-sync + terugkerende
                          static / herkomst check         kosten + scan data/import/)
                          router → handler → service → store
                                    ▼                      │
                          web/html.doge render        data/*.dson (atomic)
                                    ▼                 data/audit.dsonl (append)
                          response-Bytes ──bowl──▶    data/uploads/ (bijlagen)
                          verbinding-pup send/close
                                                      data/import/ (gemounte inbox-map)
```

The container is only reachable on LAN/VPN (decided 2026-07-15) — no public exposure, no TLS terminator needed; `data/` is a mounted volume (the entire state, trivially backupable).

- **Socket-I/O per verbinding in a pup, request handling single-threaded on main.** `main.doge` `start` moves the listener into an accept pup (`web/http.doge` `serveer`), which zooms one pup per connection (`verbinding`): it parses the request, sets `req["peer_host"]`, drops `[req, antwoord-bowl]` into the shared `verzoeken` bowl, waits for the response-Bytes, sends and closes. The main thread loops `pack.sniff(verzoeken)` → `afhandel` → `pack.drop(antwoord, bytes)`, one request at a time on the only store: no concurrent mutation, no locking, no races. An idle or slow client (preconnect socket, body shorter than `Content-Length`) only blocks its own pup. `howl` has no read-timeout, so such a pup lives until the client closes. Never run handlers inside the connection pups: pups deep-copy all state (§6), so they could not share the store.
- **Request lifecycle:** read request line + headers via `recv_line`; read the body with byte-accurate `Content-Length` framing — `recv_bytes` for binary (multipart PDF-upload), `recv` for text forms; dispatch on `(method, path)`; every handler runs inside one outer `pls`/`oh no` that renders a clean 500 and logs the error — internals never reach the response.
- **Responses** are built as full Bytes (status line, headers incl. `Content-Length`, body) by `bouw_response` on main and sent in one `howl.send_bytes` by the connection pup. Static files under `static/` are served with correct content types; uploads are served back via a download handler (router route), never as static files.

---

## 3. The `web/` Micro-framework Contract

`web/` is a generic package: it may import stdlib only, never `app/`. Modules (all built in Phase 1):

| Module | Owns |
| --- | --- |
| `http.doge` | request parse (`{method, path, query, headers, body, cookies}` Dict), response build, status/content-type constants |
| `router.doge` | route table `[method, pattern, handler]`, path params (`/journaal/{id}`), 404/405 |
| `forms.doge` | `application/x-www-form-urlencoded` decode (incl. percent + `+`), multi-value fields |
| `multipart.doge` | `multipart/form-data` parse van een rauwe Bytes-body → `{velden, bestanden}`; boundary uit Content-Type; native `bytes.find`/`split`, file-bytes nooit gedecodeerd |
| `html.doge` | `escape(s)` + page/layout/form/table builders; the **only** place HTML strings are assembled (Hard Rule 6) |
| `static.doge` | static file serving with an extension → content-type map, path-traversal safe (reject `..`) |

Handlers receive the request Dict + the loaded state, return a response Dict; `main.doge` owns the socket. Keep the framework small — it exists because Doge has no HTTP server story yet; if that ever ships upstream, `web/` is the seam to delete.

Concrete contract as built: `parse_request(conn, caps = {})` → `{method, path, query, headers, body, cookies, params}` (header names lowercased, each value a List; `query` decoded via `forms`; body above `MAX_BODY` (12 MiB) → `{oversize}` → 413, unless `caps` gives that path a larger cap — `main.doge` does this only for `/overdracht/import`); `bouw_response(resp)` → Bytes for one `send_bytes`, where `resp` is `{status, headers, set_cookie?, body}` and Content-Length is `len(bytes(body))` (byte count, never char). The `Router` (object) matches `[methode, patroon, handler]`, captures `/pad/{id}` params, and returns a 404 (no path) vs 405 (`Allow`) response; handlers are called positionally with the single request Dict. Response CRLF is the literal `so CRLF = "\r\n"`. A `multipart/form-data` body arrives as raw **Bytes** (`http.is_tekst` returns false), so `web/multipart.doge` parses it directly — no `http.doge`/`router` change was needed for upload.

---

## 4. Persistence

- **One DSON file per collection** in `data/` (see [DATA-MODEL.md](./DATA-MODEL.md)): `instellingen.dson`, `rekeningen.dson`, `journaal.dson`, `bijlagen.dson`, `terugkerend.dson`, `aangiften.dson`, `tellers.dson`. DSON (`dson` stdlib, mirrors `json` member-for-member) is the eigenaarskeuze — on-theme, and ints round-trip fine (octal is only the surface syntax).
- **Atomic write:** `store.bewaar(naam, waarde)` writes `data/<naam>.dson.tmp` then `fetch.rename` over the real file — a crash never half-writes state. `store.laad(naam, standaard)` returns the default when the file is absent (first boot).
- **Audit log:** every mutation appends one DSON line to `data/audit.dsonl` — `{ts, actie, entiteit, id, data}` — *before* the collection save. Append-only, never rewritten, never rotated (bewaarplicht).
- **Amounts are strings in DSON** (`"bedrag_ex" is "1250.00"`); `dec()` at load, `str()` at save. `dson.emit` of a Decimal is a catchable `TypeError` (DSON has no faithful Decimal form) — the store never sees a bare Decimal (Hard Rule 1).
- **In-memory model:** collections are **loaded per request through `store.laad`** and written back through `store.bewaar` (the store already does per-call file I/O). Chosen over a boot-loaded cache (Phase 2a): single-user + strictly sequential + tiny volume means a DSON parse per request is free, and it avoids a dual-write invariant (memory *and* file) with no upside. Handlers get the `Store` instance via `req["ctx"]["store"]`. Revisit only if profiling ever shows a hot read.
- **Uploads:** `data/uploads/{jaar}/{bijlage_id}.{ext}` — generated names only (Hard Rule 7); metadata in `bijlagen.dson`. Deletion does not exist (Hard Rule 3).
- **Backups are external** (the whole `data/` dir is the state — restic/borg on a timer); the app itself never deletes or rewrites history.
- **Overdracht naar een andere instance** loopt via `/overdracht`: export = één JSON-bundel (DATA-MODEL §5), import alleen op een instance zonder administratie (geen journaal, bijlagen, sjablonen of aangiften), dus nooit overschrijven (Hard Rule 3) en nooit dubbel (Hard Rule 2). De audit-historie uit de bundel wordt achter het bestaande log aangevuld (`store.audit_aanvullen`), gevolgd door één `geimporteerd`-event. De import-upload heeft een eigen bodycap (`overdracht.MAX_IMPORT_BYTES`, 256 MiB); de hele body staat in memory.

---

## 5. Cross-cutting

### 5.1 Access (single user, no app auth)

**There is no login and no wachtwoord.** Single-user app; the only access boundary is the network — LAN/VPN-only (decided 2026-07-15), meant to sit behind a reverse proxy. An application password was deliberately dropped: with the plaintext already on the same host and no TLS in-app, a fast unsalted hash added no real protection, and Doge's `crypto` has no KDF (only `sha256`/`hmac`/`token`/`same`) to do it properly. Every route is served directly; `web/http.doge` still parses cookies generically, but nothing gates on them. `/internal/*` guards on `INTERN_TOKEN` (constant-time `crypto.same`) **plus** a loopback-peer-check (`howl.peer` → host must be loopback; helpers `is_loopback`/`peer_host` in `web/http.doge`, `req["peer_host"]` set in `main.doge`) — service-to-service auth, not user login. De reverse-proxy hoort `/internal/` extern te blokkeren.

Every request first passes `web/herkomst.doge` `weiger_reden` (hooked in `main.doge` `afhandel`, before static and router): 403 when the `Host` isn't in `TOEGESTANE_HOSTS` (DNS rebinding; loopback hosts always pass, so an unset list means loopback-only), and for unsafe methods 403 when `Sec-Fetch-Site` is present and not `same-origin`/`none`, or `Origin` is present and doesn't match `Host` (CSRF without tokens). Non-browser clients (curl, the scheduler) send neither header and pass.

### 5.2 Scheduler (Mollie-sync + terugkerende kosten)

A single pup (`pack.zoom(scheduler_lus, [cfg])`) started in `main.doge` `start()` (only when `INTERN_TOKEN` is set): loop { `nap.rest(datum.seconden_tot_uur(6))` (sleep to the next 06:00 Europe/Amsterdam; timing is pure/tested via `seconden_tot_uur_vanaf`), `howl.request("POST", ...)` loopback with an `X-Intern-Token` header, log the status }. The handler `app/handlers/intern_h.doge` `run_recurring` runs on the main loop (so it *does* share the store), first guards the token with `crypto.same` (403 on missing/wrong), then does three things — each in its own `pls`/`oh no` so one failure doesn't stop the rest — all **idempotent**: (1) `mollie.sync(store, key)` (skipped when no key) calls the Mollie API (`howl.request`, `MOLLIE_API_KEY`) and pages through **all** payments (`/v2/payments`) and all refunds (`/v2/refunds`) via `_links.next` (`haal_alle`, 250 per page; more than `MAX_PAGINAS` pages bonks instead of silently truncating). There is no early stop on a date: a payment created before the last sync can still become paid after it, so idempotency (not a cursor) prevents double booking. Each paid payment becomes an omzet-post (idempotent per `mollie_payment_id`), each refunded refund a tegenboeking (idempotent per `mollie_refund_id`); non-EUR payments/refunds are refused, audited as `mollie-geweigerd` and reported as `geweigerd` on every sync. A paid 0.00 payment is skipped; a post that `journaal.bewaar` refuses is audited as `mollie-mislukt`, reported as `mislukt` and the batch continues. Afterwards it records `instellingen.mollie_laatste_sync` (display only, never a filter); (2) `terugkerend.genereer(store, datum.vandaag(), koersbron)` walks `terugkerend.dson`, generates due kosten-journaalposten (idempotent per sjabloon+maand); USD-sjablonen are converted with the live Wise-koers (`wisselkoers.Wise`, only when `WISE_API_TOKEN` is set — otherwise reported as fout and left unbooked for the next run); a post that `journaal.bewaar` refuses is audited as `terugkerend-mislukt`, reported as fout and the run continues; (3) `bijlagen.scan_import(store)` scans the mounted `data/import/` map (via de store-methods `import_lijst`/`import_verwijder`) — every new file becomes a Bijlage (`bron = "import"`) in the inbox via `bijlagen.bewaar` (which already copies the bytes to `uploads/{jaar}/{id}.{ext}` + audit), and the **source file in `data/import/` is then deleted** (so import never double-ingests — idempotency is by source-file removal, not a stored key). An invalid file (ext/size) stays put and is reported skipped. Each step is ook los met de hand te draaien (`POST /mollie/sync`, `/terugkerend/genereer`, `/inbox/scan`). `/internal/*` accepts a request only when both the token en een loopback-peer (`howl.peer`) kloppen; de reverse-proxy blokkeert `/internal/` extern. Pups share no state (§6): loopback HTTP is the only correct channel; never give the pup its own store access.

### 5.3 Frontend — Dogescript

Pages stay server-rendered (`web/html.doge`); client-side gedrag is progressive enhancement written in **Dogescript** (https://github.com/dogescript/dogescript — doge-dialect that compiles to JS). Sources in `static/djs/`, compiled to `static/js/` by `npm run build` → `build-js.mjs`, which calls the dogescript **library API** (`package.json` pins `dogescript`); the packaged CLI-bin is broken, so we never invoke it. Compiled output is gitignored and rebuilt in the Docker `assets` node-stage, then overlaid into the final image. `html.pagina` loads `static/js/boekhond.js` **site-wide, deferred**; every enhancement feature-detects its target (`form[action$="/journaal/memoriaal"]`, `input[type=file][name=bestand]`) and no-ops when absent, so a missing/un-built file 404's harmlessly and the baseline works. Rules: **never file issues on dogescript** ("we have what we get") — Dogescript's keyword-syntax mis-compiles real DOM code, so the `.djs` is authored as pass-through plain JS with `shh` line-comments (the "gaps → plain JS" rule); no SPA framework. Built in Phase 2c: memoriaal "+ regel" (clones a row; the server already accepts N regels) and upload-UX (filename display, client-side ext/size check mirroring `bijlagen.doge`, drag-and-drop) — client checks are UX only, `bijlagen.bewaar` stays the security boundary (Hard Rule 7).

### 5.4 Exports

All exports are GET endpoints rendering from the same services that render pages, met `lib/csv.doge` (generieke writer, `;`-gescheiden voor Excel-NL) en `http.csv_response` als download-schil: aangifte-overzicht (`/aangifte`, print-view `/aangifte/print` + `/aangifte/export.csv`), journaal-CSV per tijdvak (`/journaal/export.csv`), balans + winst & verlies + jaaroverzicht (`rapporten.doge`, `/rapporten/balans|winst-verlies|jaaroverzicht` elk met een `.csv`-variant; elk rapport linkt de andere rapporten, de jaren binnen `aangifte.jaar_bereik` en zijn eigen CSV). De volledige export voor overdracht (`/overdracht/export.json`) is geen CSV maar een JSON-bundel (§4).

### 5.5 Config

`.env` read once at boot → config Dict → passed down explicitly. `main.doge` loads `.env` itself (a small parser; real environment variables win, so `docker compose env_file`/exports override the file). App keys: `INTERN_TOKEN` (none → scheduler-pup niet gestart, `/internal/*` weigert alles), `MOLLIE_API_KEY`, `WISE_API_TOKEN` (read-only Wise API token voor de USD→EUR-koers; none → USD-sjablonen worden niet geboekt), `POORT`, `DATA_DIR`, `TOEGESTANE_HOSTS` (comma-separated `host[:port]` allow-list for the `Host` header; an entry without port matches any port; unset → loopback-only plus a startup warning), `BIND_HOST` (listener-bind; default `127.0.0.1`, in de container zet `docker-compose.yml` dit op `0.0.0.0` zodat de gepubliceerde poort/reverse-proxy hem bereikt — `main.doge` bindt `cfg["bind_host"]`). Compose consumes `PUBLISH_HOST` separately: default `127.0.0.1`; set the VM/LXC's LAN/VPN address for direct network access. Bedrijfsgegevens (naam, KvK, btw-id, IBAN, adres) are *not* secrets and live in `instellingen.dson`, editable in the UI.

### 5.6 Bijlagen — upload & download

The upload form posts `multipart/form-data`; the body arrives as raw Bytes and `web/multipart.doge` extracts the file part(s). `app/services/bijlagen.doge` validates (extension allow-list + size-cap — domain constants, *not* `.env`), derives the mime from the trusted extension (never the client header), issues a `b-<n>` id, and writes the blob atomically via `store.bewaar_bestand` under `data/uploads/{jaar}/{id}.{ext}` (generated name; original filename is metadata only — Hard Rule 7). A bijlage with `journaalpost_id == none` is an inbox item; `bijlagen.koppel` links it through `journaal.koppel_bijlage` (the single journaalpost writer, which enforces the tijdvak-lock). **Download is a router route** (`GET /bijlagen/{id}`), never served from `/static/` (bijlagen live outside the static root): the handler looks up the metadata, reads the bytes with `store.laad_bestand`, and returns them with the stored mime + a sanitised `Content-Disposition` filename. Nothing is ever deleted (Hard Rule 3). The size-cap is checked after the full body is in memory (no streaming) — acceptable for a LAN/VPN single-user app.

---

## 6. Doge-specific Constraints That Shaped This Design

Read this before proposing structural changes — these are language facts, not preferences:

1. **Pups (threads) deep-copy everything and share no mutable state.** A shared in-memory store across threads is impossible by design → connection pups only do socket-I/O and hand requests to the single-threaded main loop over a bowl (§2); the scheduler uses loopback HTTP. Bowls are the only shared handles; a socket passed in `pack.zoom` args is moved (the sender's handle is closed). A pup *does* see the top-level snapshot (imported modules incl. `nap`/`howl`/`datum` are usable inside `scheduler_lus` — verified). `/internal/*` is gated on the token (`crypto.same`) + a loopback-peer-check (`howl.peer`).
2. **Binary bodies use `recv_bytes`/`send_bytes`, not `recv`.** `recv` is Str-typed and errors on non-UTF-8, and its `Content-Length` framing counts characters not bytes — so multipart PDF-upload reads the body with `recv_bytes` (byte-accurate) and downloads reply with `send_bytes`. `recv` stays for ASCII urlencoded forms only.
3. **Decimal/Float never mix** (`TypeError`) and `json.emit(Decimal)` → Float on re-parse → amounts serialize as strings (§4).
4. **`nap` has stamps only, no date arithmetic** → `lib/datum.doge` owns YYYY-MM-DD math (kwartalen, maandlengtes, schrikkeljaren) in pure string/Int code.
5. **Keyword args don't work on methods/stored functions** — pass positionally in handler tables.
6. **Module files hold only definitions** — all boot/wiring lives in `main.doge`.
7. **A `so` import resolves stdlib → dependency → sibling `.doge`.** Same-directory siblings import by **bare name** (`web/router.doge` uses `so http`); cross-directory modules by string path (`main.doge` uses `so "web/http.doge"`, a test uses `so "../web/http.doge"`). Verified in Phase 1. **There is no import alias, and two modules with the same basename collide** (`foo is already defined`) — so handler modules that `main.doge` imports next to a same-named service carry an `_h` suffix (`app/handlers/rekeningen_h.doge` next to `app/services/rekeningen.doge`). Verified in Phase 2a.
8. **Dict keys must be Str** (an Int key is a `TypeError`) — a status-code map is `{"404": …}`, looked up via `str(code)`. A **literal `{`/`}` in a string is `\{`/`\}`** — an unescaped `{id}` is interpolation, so route patterns are written `"/journaal/\{id\}"`; and a **`{…}` interpolation can't contain a nested string literal** (`"{html.knop(\"x\")}"` fails — the interpolation "never closes"), so bind the call to a local first. Verified through Phase 2b.
9. **Handlers reach boot state via `req["ctx"]`, not closures.** The router calls `handler(req)` positionally and handlers are top-level (registered before `start()` builds the store), so they cannot lexically capture it. `afhandel` sets `req["ctx"] = {store, config}` before dispatch; handlers read `req["ctx"]["store"]`. `afhandel` only splits `/static/*` (served directly) from everything else (routed) — there is no auth gate (§5.1).

---

## 7. Goal Architecture — NOT instructions

Ideas parked until explicitly asked for; do not implement on your own initiative:

- Invoice ingestion beyond Mollie + the import-map: pull inkoop-PDF's from a supplier API (`howl.request`); e-mail (IMAP) ingestion.
- ICP-opgaaf export view when 3b-omzet ever occurs.
- Jaarafsluiting/IB-hulp: afschrijvingen, KIA, urenregistratie.
- Multi-year archive compaction (audit stays append-only regardless).
