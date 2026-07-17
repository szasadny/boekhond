# Boekhond — Architecture

Authoritative reference for the system's shape. Jump to the section you need and **update it when you change what it describes**. The data model lives in [DATA-MODEL.md](./DATA-MODEL.md); phasing and language-blockers in [PLAN.md](./PLAN.md).

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
| Rekeningschema: seed, lookup, unique-nummer validation, deactiveren | `app/services/rekeningen.doge` — master-data; owns the `REK_*` constants `journaal.doge` binds to |
| Mollie-inkomsten ophalen + boeken (idempotent per `mollie_payment_id`) | `app/services/mollie.doge` — bouwt gebalanceerde omzet-posten, roept `journaal.doge` |
| Terugkerende maandkosten genereren | `app/services/terugkerend.doge` — kostensjablonen → maandpost via `journaal.doge` |
| Bijlagen: upload-validatie (ext-allowlist + size-cap), opslag `uploads/{jaar}/{id}{ext}`, import-inbox, koppelen | `app/services/bijlagen.doge` — owns de allow-list/size-cap/mime-constanten; roept `journaal.koppel_bijlage` voor de post-kant (single writer) |
| Een `multipart/form-data` body (binaire upload) parsen | `web/multipart.doge` — domeinvrij; native `bytes.find`/`split`; input = rauwe Bytes-body + boundary uit Content-Type |
| Een geüploade bijlage terugserveren (download) | een router-route (`app/handlers/bijlagen_h.doge` `download`), **nooit** onder `/static/` — leest de bytes uit de `bijlagen.dson`-metadata (§5.6) |
| Balans / winst & verlies aggregation | `app/services/rapporten.doge` — reads the journaal, never writes |
| A new page or form endpoint | `app/handlers/<resource>_h.doge` — shape: parse request → call service → render via `web/html.doge`. Copy an existing handler. Shared view-schil (nav, foutbanner) in `app/handlers/weergave.doge`. |
| A route registration | `main.doge` route table — handlers never self-register |
| A read/write of any `data/` file | `app/store/store.doge` (atomic write + audit append) — Hard Rule 4 |
| A new entity / JSON collection | `app/store/` load/save pair + [DATA-MODEL.md](./DATA-MODEL.md) entry + a migration note if the shape of an existing file changes |
| HTML structure, escaping, form/table builders | `web/html.doge` — handlers compose builders, never concatenate raw HTML |
| HTTP parsing, cookies, static files | `web/` — must stay domain-free (no `app/` imports) |
| Client-side gedrag (progressive enhancement: +regel, upload-UX) | `static/djs/boekhond.djs` (Dogescript) → `npm run build` → `static/js/boekhond.js`, site-wide deferred geladen door `html.pagina`. Feature-detected; baseline blijft no-JS (§5.3) |
| Date math (kwartaal, vervaldatum, maand-increment) | `lib/datum.doge` |
| Money parsing/formatting (`"1.234,56"` ↔ Decimal) | `lib/geld.doge` |
| A CSV export | `lib/csv.doge` (generic writer) + the shaping in the owning service |
| A user-facing (Dutch) error or label string | constants at the top of the owning handler/service — one home per string, no duplicates |
| A config value / secret | `.env`, read once at boot in `main.doge` into a config Dict passed down — never `env.get` scattered through the code |
| A background/periodic action | the scheduler pup in `main.doge` → loopback POST `/internal/<naam>` handler (§5.2) — never a sleep loop inside the request path |
| A language-gap stopgap | `lib/` with a `# stopgap for doge#NN` comment + PLAN.md §3 row (Hard Rule 10) |
| A test | `tests/test_<module>.doge` — table-driven for fiscal rules |

---

## 1. Guiding Principles

1. **Modular by contract.** Handlers do HTTP, services do behaviour, store does persistence, `web/` is a reusable domain-free framework. No layer reaches across.
2. **Single source of truth.** Fiscal rules in `btw.doge`, persistence in `store.doge`, escaping in `html.doge`. Duplication of a fiscal rule is a compliance bug, not just debt.
3. **Boring beats clever.** One user, tiny data volume: sequential request handling, JSON files, server-rendered HTML. Complexity needs a demonstrated reason.
4. **Audit-first.** Every mutation is an append to `audit.dsonl` before it is state. The administratie must be reconstructable (bewaarplicht).
5. **The language is young — push gaps upstream.** A missing primitive becomes a DogeLanguage/doge ticket + minimal marked stopgap (Hard Rule 10), so this app makes the language better instead of accumulating workarounds.

---

## 2. Topology & Request Lifecycle

```text
Browser (LAN/VPN) ──HTTP──▶ VM ▸ Docker container ▸ boekhond binary
                                                              │
                                    ┌─────────────────────────┤
                                    ▼                         ▼
                              main accept-loop          scheduler pup (pack.zoom)
                              (sequential)               sleeps until 06:00,
                                    │                    POST /internal/run-recurring
                                    ▼                    via howl.connect loopback
                          web/http.doge parse            (terugkerende facturen +
                                    ▼                     scan data/import/ → inbox)
                          router → handler → service → store
                                    ▼                      │
                          web/html.doge render        data/*.dson (atomic)
                                    ▼                 data/audit.dsonl (append)
                          howl.send response          data/uploads/ (bijlagen)
                                                      data/import/ (gemounte inbox-map)
```

The container is only reachable on LAN/VPN (decided 2026-07-15) — no public exposure, no TLS terminator needed; `data/` is a mounted volume (the entire state, trivially backupable).

- **Sequential accept-loop, deliberately single-threaded.** `howl.listen` → `accept` → handle → close, one request at a time. One user; no concurrent mutation, no locking, no races. Do not "fix" this with a pup-per-connection: Doge pups deep-copy all state (§6), so a threaded server could not share the store anyway.
- **Request lifecycle:** read request line + headers via `recv_line`; read the body with byte-accurate `Content-Length` framing — `recv_bytes` for binary (multipart PDF-upload), `recv` for text forms; dispatch on `(method, path)`; every handler runs inside one outer `pls`/`oh no` that renders a clean 500 and logs the error — internals never reach the response.
- **Responses** are built as full strings (status line, headers incl. `Content-Length`, body) and sent in one `howl.send`. Static files under `static/` are served with correct content types; uploads are served back via a download handler (router route), never as static files.

---

## 3. The `web/` Micro-framework Contract

`web/` is a generic package: it may import stdlib only, never `app/`. Modules (all built in Phase 1):

| Module | Owns |
| --- | --- |
| `http.doge` | request parse (`{method, path, query, headers, body, cookies}` Dict), response build, status/content-type constants |
| `router.doge` | route table `[method, pattern, handler]`, path params (`/journaal/{id}`), 404/405 |
| `forms.doge` | `application/x-www-form-urlencoded` decode (incl. percent + `+`), multi-value fields |
| `multipart.doge` | `multipart/form-data` parse van een rauwe Bytes-body → `{velden, bestanden}`; boundary uit Content-Type; native `bytes.find`/`split` (0.3.3), file-bytes nooit gedecodeerd |
| `html.doge` | `escape(s)` + page/layout/form/table builders; the **only** place HTML strings are assembled (Hard Rule 6) |
| `static.doge` | static file serving with an extension → content-type map, path-traversal safe (reject `..`) |

Handlers receive the request Dict + the loaded state, return a response Dict; `main.doge` owns the socket. Keep the framework small — it exists because Doge has no HTTP server story yet; if that ever ships upstream, `web/` is the seam to delete.

Concrete contract as built: `parse_request(conn)` → `{method, path, query, headers, body, cookies, params}` (header names lowercased, each value a List; `query` decoded via `forms`); `bouw_response(resp)` → Bytes for one `send_bytes`, where `resp` is `{status, headers, set_cookie?, body}` and Content-Length is `len(bytes(body))` (byte count, never char). The `Router` (object) matches `[methode, patroon, handler]`, captures `/pad/{id}` params, and returns a 404 (no path) vs 405 (`Allow`) response; handlers are called positionally with the single request Dict. Response CRLF is the literal `so CRLF = "\r\n"` (the doge#67 stopgap is retired in 0.3.3). A `multipart/form-data` body arrives as raw **Bytes** (`http.is_tekst` returns false), so `web/multipart.doge` parses it directly — no `http.doge`/`router` change was needed for upload.

---

## 4. Persistence

- **One DSON file per collection** in `data/` (see [DATA-MODEL.md](./DATA-MODEL.md)): `instellingen.dson`, `rekeningen.dson`, `journaal.dson`, `bijlagen.dson`, `terugkerend.dson`, `aangiften.dson`. DSON (`dson` stdlib, mirrors `json` member-for-member) is the eigenaarskeuze — on-theme, and ints round-trip fine (octal is only the surface syntax).
- **Atomic write:** `store.bewaar(naam, waarde)` writes `data/<naam>.dson.tmp` then `fetch.rename` over the real file — a crash never half-writes state. `store.laad(naam, standaard)` returns the default when the file is absent (first boot).
- **Audit log:** every mutation appends one DSON line to `data/audit.dsonl` — `{ts, actie, entiteit, id, data}` — *before* the collection save. Append-only, never rewritten, never rotated (bewaarplicht).
- **Amounts are strings in DSON** (`"bedrag_ex" is "1250.00"`); `dec()` at load, `str()` at save. `dson.emit` of a Decimal is a catchable `TypeError` (DSON has no faithful Decimal form) — the store never sees a bare Decimal (Hard Rule 1).
- **In-memory model:** collections are **loaded per request through `store.laad`** and written back through `store.bewaar` (the store already does per-call file I/O). Chosen over a boot-loaded cache (Phase 2a): single-user + strictly sequential + tiny volume means a DSON parse per request is free, and it avoids a dual-write invariant (memory *and* file) with no upside. Handlers get the `Store` instance via `req["ctx"]["store"]`. Revisit only if profiling ever shows a hot read.
- **Uploads:** `data/uploads/{jaar}/{bijlage_id}{ext}` — generated names only (Hard Rule 7); metadata in `bijlagen.dson`. Deletion does not exist (Hard Rule 3).
- **Backups are external** (the whole `data/` dir is the state — restic/borg on a timer); the app itself never deletes or rewrites history.

---

## 5. Cross-cutting

### 5.1 Access (single user, no app auth)

**There is no login and no wachtwoord.** Single-user app; the only access boundary is the network — LAN/VPN-only (decided 2026-07-15), meant to sit behind a reverse proxy. An application password was deliberately dropped: with the plaintext already on the same host and no TLS in-app, a fast unsalted hash added no real protection, and Doge's `crypto` has no KDF (only `sha256`/`hmac`/`token`/`same`) to do it properly. Every route is served directly; `web/http.doge` still parses cookies generically, but nothing gates on them. `/internal/*` (Phase 5) will still guard on `INTERN_TOKEN` + loopback peer — that is service-to-service auth, not user login.

### 5.2 Scheduler (Mollie-sync + terugkerende kosten)

A single pup (`pack.zoom`) at boot: loop { sleep until next 06:00 (`nap`), `howl.connect` loopback, POST `/internal/run-recurring` with `INTERN_TOKEN` from `.env`, read response }. The handler (main loop, so it *does* share state) does three things, all **idempotent**: (1) `mollie.doge` calls the Mollie API (`howl.request`, `MOLLIE_API_KEY`) for paid payments + refunds since `instellingen.mollie_laatste_sync`, boekt elke als omzet-post (idempotent per `mollie_payment_id`), advances the hoogwatermerk; (2) `terugkerend.doge` walks `terugkerend.dson`, generates due kosten-journaalposten (idempotent per sjabloon+maand), advances `volgende_run`; (3) scans the mounted `data/import/` map — every new file becomes a Bijlage (`bron = "import"`) in the inbox and the source file is moved to `data/uploads/` (so import never double-ingests). The same run is also triggerable by hand ("sync nu"). `/internal/*` accepts only the token + loopback peer. Pups share no state (§6): loopback HTTP is the only correct channel; never give the pup its own store access.

### 5.3 Frontend — Dogescript

Pages stay server-rendered (`web/html.doge`); client-side gedrag is progressive enhancement written in **Dogescript** (https://github.com/dogescript/dogescript — doge-dialect that compiles to JS). Sources in `static/djs/`, compiled to `static/js/` by `npm run build` → `build-js.mjs`, which calls the dogescript **library API** (`package.json` pins `dogescript`); the packaged CLI-bin is broken in 2.4.3, so we never invoke it. Compiled output is gitignored and rebuilt in the Docker `assets` node-stage, then overlaid into the final image. `html.pagina` loads `static/js/boekhond.js` **site-wide, deferred**; every enhancement feature-detects its target (`form[action$="/journaal/memoriaal"]`, `input[type=file][name=bestand]`) and no-ops when absent, so a missing/un-built file 404's harmlessly and the baseline works. Rules: **never file issues on dogescript** ("we have what we get") — Dogescript's keyword-syntax mis-compiles real DOM code, so the `.djs` is authored as pass-through plain JS with `shh` line-comments (the "gaps → plain JS" rule); no SPA framework. Built in Phase 2c: memoriaal "+ regel" (clones a row; the server already accepts N regels) and upload-UX (filename display, client-side ext/size check mirroring `bijlagen.doge`, drag-and-drop) — client checks are UX only, `bijlagen.bewaar` stays the security boundary (Hard Rule 7).

### 5.4 Exports

All exports are GET endpoints rendering from the same services that render pages: aangifte-overzicht (print-CSS HTML + CSV), journaal-CSV per tijdvak, balans + winst & verlies (`rapporten.doge`), jaaroverzicht.

### 5.5 Config

`.env` read once at boot → config Dict → passed down explicitly. `main.doge` loads `.env` itself (a small parser; real environment variables win, so `docker compose env_file`/exports override the file). Keys: `INTERN_TOKEN`, `MOLLIE_API_KEY`, `POORT`, `DATA_DIR`. Bedrijfsgegevens (naam, KvK, btw-id, IBAN, adres) are *not* secrets and live in `instellingen.dson`, editable in the UI.

### 5.6 Bijlagen — upload & download

The upload form posts `multipart/form-data`; the body arrives as raw Bytes and `web/multipart.doge` extracts the file part(s). `app/services/bijlagen.doge` validates (extension allow-list + size-cap — domain constants, *not* `.env`), derives the mime from the trusted extension (never the client header), issues a `b-<n>` id, and writes the blob atomically via `store.bewaar_bestand` under `data/uploads/{jaar}/{id}{ext}` (generated name; original filename is metadata only — Hard Rule 7). A bijlage with `journaalpost_id == none` is an inbox item; `bijlagen.koppel` links it through `journaal.koppel_bijlage` (the single journaalpost writer, which enforces the tijdvak-lock). **Download is a router route** (`GET /bijlagen/{id}`), never served from `/static/` (bijlagen live outside the static root): the handler looks up the metadata, reads the bytes with `store.laad_bestand`, and returns them with the stored mime + a sanitised `Content-Disposition` filename. Nothing is ever deleted (Hard Rule 3). The size-cap is checked after the full body is in memory (no streaming) — acceptable for a LAN/VPN single-user app.

---

## 6. Doge-specific Constraints That Shaped This Design

Read this before proposing structural changes — these are language facts, not preferences:

1. **Pups (threads) deep-copy everything and share no mutable state.** A shared in-memory store across threads is impossible by design → sequential accept-loop + loopback HTTP for the scheduler. Bowls/sockets are the only shared handles.
2. **Binary bodies use `recv_bytes`/`send_bytes`, not `recv`.** `recv` is Str-typed and errors on non-UTF-8, and its `Content-Length` framing counts characters not bytes — so multipart PDF-upload reads the body with `recv_bytes` (byte-accurate) and downloads reply with `send_bytes`. `recv` stays for ASCII urlencoded forms only.
3. **Decimal/Float never mix** (`TypeError`) and `json.emit(Decimal)` → Float on re-parse → amounts serialize as strings (§4).
4. **`nap` has stamps only, no date arithmetic** → `lib/datum.doge` owns YYYY-MM-DD math (kwartalen, maand-increment, schrikkeljaren) in pure string/Int code.
5. **Keyword args don't work on methods/stored functions** — pass positionally in handler tables.
6. **Module files hold only definitions** — all boot/wiring lives in `main.doge`.
7. **A `so` import resolves stdlib → dependency → sibling `.doge`.** Same-directory siblings import by **bare name** (`web/router.doge` uses `so http`); cross-directory modules by string path (`main.doge` uses `so "web/http.doge"`, a test uses `so "../web/http.doge"`). Verified in Phase 1. **There is no import alias, and two modules with the same basename collide** (`foo is already defined`) — so handler modules that `main.doge` imports next to a same-named service carry an `_h` suffix (`app/handlers/rekeningen_h.doge` next to `app/services/rekeningen.doge`). Verified in Phase 2a.
9. **Handlers reach boot state via `req["ctx"]`, not closures.** The router calls `handler(req)` positionally and handlers are top-level (registered before `start()` builds the store), so they cannot lexically capture it. `afhandel` sets `req["ctx"] = {store, config}` before dispatch; handlers read `req["ctx"]["store"]`. `afhandel` only splits `/static/*` (served directly) from everything else (routed) — there is no auth gate (§5.1).
8. **Dict keys must be Str** (an Int key is a `TypeError`) — a status-code map is `{"404": …}`, looked up via `str(code)`. **v0.3.3 closed two gaps that shaped Phase 1–2a:** `\r` is now a valid string escape (`so CRLF = "\r\n"`, doge#67), and `Bytes` gained `find(sub)`→Int|`-1` / `split(sep)`→`List<Bytes>` / `contains(sub)`→Bool (doge#68) — used natively by `web/multipart.doge` (no `bytes.index`). Still true: a **literal `{`/`}` in a string is `\{`/`\}`** — an unescaped `{id}` is interpolation, so route patterns are written `"/journaal/\{id\}"`; and a **`{…}` interpolation can't contain a nested string literal** (`"{html.knop(\"x\")}"` fails — the interpolation "never closes"), so bind the call to a local first. **`Str * Int` sequence-repeat does not exist** (doge#70). Verified through Phase 2b.

---

## 7. Goal Architecture — NOT instructions

Ideas parked until explicitly asked for; do not implement on your own initiative:

- Invoice ingestion beyond Mollie + the import-map: pull inkoop-PDF's from a supplier API (`howl.request`); e-mail (IMAP) ingestion.
- ICP-opgaaf export view when 3b-omzet ever occurs.
- Jaarafsluiting/IB-hulp: afschrijvingen, KIA, urenregistratie.
- Multi-year archive compaction (audit stays append-only regardless).
