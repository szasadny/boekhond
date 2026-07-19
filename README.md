# Boekhond 🐕

**Self-hosted boekhouding voor een Nederlandse eenmanszaak.**

Boekhond is een volwaardige dubbel-boekhoudapp: inkomsten komen automatisch binnen via Mollie, kosten boek je via sjablonen of terugkerende posten, en elke boeking draagt een btw-code die één-op-één op een aangifte-rubriek mapt. Inkoopbewijzen upload je erbij en blijven 7 jaar bewaard. Aan het eind van het kwartaal neem je de rubrieken over in Mijn Belastingdienst Zakelijk.

## Stack

This project is built entirely on the doge stack:

| Layer | Technology |
| --- | --- |
| Backend | [Doge](https://github.com/DogeLanguage/doge) transpiles to Rust, `doge build` yields a single binary |
| Web server | Inhouse micro-framework built on `howl` (raw TCP) |
| Frontend | Server-rendered HTML + [Dogescript](https://github.com/dogescript/dogescript) for client-side behaviour |
| Storage | [DSON](https://github.com/dogescript/DSON) files in `data/` — atomic writes and append-only audit log |
| Deploy | Docker container in a VM, LAN/VPN only; `data/` as volume |

## Structuur

```text
main.doge        # entrypoint: config, routes, accept loop (fase 1+)
lib/             # domain-free helpers: datum (kwartalen), geld (NL-notatie ↔ Decimal)
app/services/    # business logic — btw.doge is de enige plek met fiscale rekenregels
app/store/       # persistence: atomic DSON + audit + doorlopende id's
web/             # HTTP-framework (fase 1)
static/          # css + Dogescript sources (djs/ → js/)
tests/           # doge test — table-driven tests voor alles wat de wet raakt
AGENTS.md        # agent-instructies (single source of truth)
docs/            # projectdocs: ARCHITECTURE, DATA-MODEL, PLAN
.agents/skills/  # canonical skills: writing-doge, modern-web-guidance, maintaining-agents-md
.claude/skills/  # Claude Code symlinks naar dezelfde skills
```

## Development

```sh
cargo install dogelang            # toolchain
doge bark                         # run (project entry)
doge check lib/datum.doge         # snelle syntax check
doge test tests                   # volledige suite
doge fmt <file>                   # canonical formatting
npm ci && npm run build           # Dogescript static/djs/ → static/js/ 
docker compose up -d --build      # full build
```

## Deployment

Eerste install:

```sh
git clone https://github.com/szasadny/boekhond.git && cd boekhond
cp .env.example .env              # secrets (INTERN_TOKEN, MOLLIE_API_KEY) invullen
docker compose up -d --build      # app op poort 8085, administratie in ./data
```

Update:

```sh
git pull && docker compose up -d --build
```