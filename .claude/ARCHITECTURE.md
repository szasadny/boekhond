# Boekhond — Architecture

Authoritative reference for the system's shape. Jump to the section you need and **update it when you change what it describes**. The data model lives in [DATA-MODEL.md](./DATA-MODEL.md); phasing and language-blockers in [PLAN.md](./PLAN.md).

| § | Contents |
| --- | --- |
| 0 | Lookup table — where does X go? |
| 1 | Guiding principles |
| 2 | Topology & request lifecycle |
| 3 | The `web/` micro-framework contract |
| 4 | Persistence: store, audit, uploads |
| 5 | Cross-cutting: auth, scheduler, exports, config |
| 6 | Doge-specific constraints that shaped this design |
| 7 | Goal architecture — NOT instructions |

---

## 0. Quick Lookup — where does X go?

| You are adding / changing… | It goes in… |
| --- | --- |
| A business rule or behaviour | `app/services/<domein>.doge` — never in a handler |
| Anything that computes btw (tarief, rubriek, afronding) | `app/services/btw.doge` — the only file that knows fiscal math (Hard Rule 5) |
| A new page or form endpoint | `app/handlers/<resource>.doge` — shape: parse request → call service → render via `web/html.doge`. Copy an existing handler. |
| A route registration | `main.doge` route table — handlers never self-register |
| A read/write of any `data/` file | `app/store/store.doge` (atomic write + audit append) — Hard Rule 4 |
| A new entity / JSON collection | `app/store/` load/save pair + [DATA-MODEL.md](./DATA-MODEL.md) entry + a migration note if the shape of an existing file changes |
| HTML structure, escaping, form/table builders | `web/html.doge` — handlers compose builders, never concatenate raw HTML |
| HTTP parsing, cookies, sessions, static files | `web/` — must stay domain-free (no `app/` imports) |
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
4. **Audit-first.** Every mutation is an append to `audit.jsonl` before it is state. The administratie must be reconstructable (bewaarplicht).
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
- **Request lifecycle:** read request line + headers via `recv_line`; read body via `recv` with `Content-Length` framing (ASCII-safe for urlencoded forms — see §6 for why binary bodies are blocked on doge#60); dispatch on `(method, path)`; every handler runs inside one outer `pls`/`oh no` that renders a clean 500 and logs the error — internals never reach the response.
- **Responses** are built as full strings (status line, headers incl. `Content-Length`, body) and sent in one `howl.send`. Static files under `static/` are served with correct content types; uploads are served back via a download handler that checks the session, never as static files.

---

## 3. The `web/` Micro-framework Contract

`web/` is a generic package: it may import stdlib only, never `app/`. Target modules:

| Module | Owns |
| --- | --- |
| `http.doge` | request parse (`{method, path, query, headers, body, cookies}` Dict), response build, status/content-type constants |
| `router.doge` | route table `[method, pattern, handler]`, path params (`/boekingen/{id}`), 404/405 |
| `forms.doge` | `application/x-www-form-urlencoded` decode (incl. percent + `+`), multi-value fields |
| `html.doge` | `escape(s)` + page/layout/form/table builders; the **only** place HTML strings are assembled (Hard Rule 6) |
| `session.doge` | cookie sessions: token issue/check/expiry. Token quality is blocked on doge#61 — see §5.1 |
| `static.doge` | static file serving with an extension → content-type map, path-traversal safe (reject `..`) |

Handlers receive the request Dict + the loaded state, return a response Dict; `main.doge` owns the socket. Keep the framework small — it exists because Doge has no HTTP server story yet; if that ever ships upstream, `web/` is the seam to delete.

---

## 4. Persistence

- **One DSON file per collection** in `data/` (see [DATA-MODEL.md](./DATA-MODEL.md)): `instellingen.dson`, `boekingen.dson`, `facturen.dson`, `bijlagen.dson`, `terugkerend.dson`, `aangiften.dson`. DSON (`dson` stdlib, mirrors `json` member-for-member) is the eigenaarskeuze — on-theme, and ints round-trip fine (octal is only the surface syntax).
- **Atomic write:** `store.bewaar(naam, waarde)` writes `data/<naam>.dson.tmp` then `fetch.rename` over the real file — a crash never half-writes state. `store.laad(naam, standaard)` returns the default when the file is absent (first boot).
- **Audit log:** every mutation appends one DSON line to `data/audit.dsonl` — `{ts, actie, entiteit, id, data}` — *before* the collection save. Append-only, never rewritten, never rotated (bewaarplicht).
- **Amounts are strings in DSON** (`"bedrag_ex" is "1250.00"`); `dec()` at load, `str()` at save. `dson.emit` of a Decimal is a catchable `TypeError` (DSON has no faithful Decimal form) — the store never sees a bare Decimal (Hard Rule 1).
- **In-memory model:** the accept-loop holds the collections as Dicts/Lists loaded at boot; a mutation updates memory + audit + file in that request. Sequential handling makes this trivially consistent.
- **Uploads:** `data/uploads/{jaar}/{bijlage_id}{ext}` — generated names only (Hard Rule 7); metadata in `bijlagen.json`. Deletion does not exist (Hard Rule 3).
- **Backups are external** (the whole `data/` dir is the state — restic/borg on a timer); the app itself never deletes or rewrites history.

---

## 5. Cross-cutting

### 5.1 Auth (single user)

Login form → wachtwoord check against `.env` → session token in an http-only cookie; every non-static route except `/login` and `/internal/*` requires the session. **Interim posture until doge#61 (crypto) lands:** token from `roll` is not cryptographically secure and the wachtwoord is compared in plain text — acceptable *only* because the app is LAN/VPN-only (decided 2026-07-15); never expose it publicly in this state. When doge#61 lands: hashed wachtwoord, CSPRNG tokens, constant-time compare — tracked in PLAN.md §3.

### 5.2 Scheduler (terugkerende facturen)

A single pup (`pack.zoom`) at boot: loop { sleep until next 06:00 (`nap`), `howl.connect` loopback, POST `/internal/run-recurring` with `INTERN_TOKEN` from `.env`, read response }. The handler (main loop, so it *does* share state) does two things, both **idempotent per day**: (1) walks `terugkerend.dson`, generates due facturen + boekingen, advances `volgende_run`; (2) scans the mounted `data/import/` map — every new file becomes a Bijlage (`bron = "import"`) in the inbox and the source file is moved to `data/uploads/` (so import never double-ingests). `/internal/*` accepts only the token + loopback peer. Pups share no state (§6): loopback HTTP is the only correct channel; never give the pup its own store access.

### 5.3 Frontend — Dogescript

Pages stay server-rendered (`web/html.doge`); client-side gedrag (upload-shim, dynamische factuurregels, kleine UX) is written in **Dogescript** (https://github.com/dogescript/dogescript — doge-dialect that compiles to JS). Sources in `static/djs/`, compiled to `static/js/` by an npm build step (`dogescript` package); compiled output is gitignored and rebuilt in the Docker image. Rules: **never file issues on dogescript** ("we have what we get") — where Dogescript can't express something, drop to plain JS in the same file (Dogescript passes unknown lines through) or a vanilla `.js` file; no SPA framework unless a page genuinely needs one.

### 5.4 Exports

All exports are GET endpoints rendering from the same services that render pages: aangifte-overzicht (print-CSS HTML + CSV), boekingen-CSV per tijdvak, jaaroverzicht. Factuur-PDF = print-CSS HTML (browser print); a real PDF pipeline is §7 territory.

### 5.5 Config

`.env` read once at boot → config Dict → passed down explicitly. Keys: `WACHTWOORD`, `INTERN_TOKEN`, `POORT`, `DATA_DIR`. Bedrijfsgegevens (naam, KvK, btw-id, IBAN, adres) are *not* secrets and live in `instellingen.json`, editable in the UI.

---

## 6. Doge-specific Constraints That Shaped This Design

Read this before proposing structural changes — these are language facts, not preferences:

1. **Pups (threads) deep-copy everything and share no mutable state.** A shared in-memory store across threads is impossible by design → sequential accept-loop + loopback HTTP for the scheduler. Bowls/sockets are the only shared handles.
2. **`howl.recv` is Str-typed and errors on non-UTF-8** → binary request bodies (multipart PDF upload) are impossible until doge#60. Stopgap: file → base64 in the browser (`static/upload.js`), body stays ASCII urlencoded; decode via `lib/base64.doge` → `bytes(list)` → `fetch.write_bytes`. `Content-Length` framing is byte-based and `recv` counts characters — safe only because ASCII bodies make them equal; do not stream non-ASCII bodies through `recv` counting.
3. **Decimal/Float never mix** (`TypeError`) and `json.emit(Decimal)` → Float on re-parse → amounts serialize as strings (§4).
4. **`nap` has stamps only, no date arithmetic** → `lib/datum.doge` owns YYYY-MM-DD math (kwartalen, maand-increment, schrikkeljaren) in pure string/Int code.
5. **No crypto in stdlib** (doge#61) → §5.1 interim posture.
6. **Keyword args don't work on methods/stored functions** — pass positionally in handler tables.
7. **Module files hold only definitions** — all boot/wiring lives in `main.doge`.
8. **A `so` import resolves stdlib → dependency → sibling `.doge`**; subdirectory modules via string-path imports (`so "web/http.doge"`).

---

## 7. Goal Architecture — NOT instructions

Ideas parked until explicitly asked for; do not implement on your own initiative:

- Real multipart upload + drag-and-drop once doge#60/#63 land (delete the upload-shim + `lib/base64.doge`).
- Automatic invoice ingestion beyond the import-map: pull from a supplier API (needs doge#62 headers); e-mail (IMAP) ingestion.
- Server-side PDF generation (chase → weasyprint) for facturen.
- ICP-opgaaf export view when 3b-omzet ever occurs.
- Jaarafsluiting/IB-hulp: afschrijvingen, KIA, urenregistratie.
- Multi-year archive compaction (audit stays append-only regardless).
