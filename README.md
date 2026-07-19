# Boekhond 🐕

**Self-hosted boekhouding voor een Nederlandse eenmanszaak.**

Boekhond is een volwaardige dubbel-boekhoudapp: inkomsten komen automatisch binnen via Mollie, kosten boek je via sjablonen of terugkerende posten, en elke boeking draagt een btw-code die één-op-één op een aangifte-rubriek mapt. Inkoopbewijzen upload je erbij en blijven 7 jaar bewaard. Aan het eind van het kwartaal neem je de rubrieken over in Mijn Belastingdienst Zakelijk.

## Stack

| Layer | Technology |
| --- | --- |
| Backend | [Doge](https://github.com/DogeLanguage/doge) transpiles to Rust, `doge build` yields a single binary |
| Web server | Inhouse micro-framework built on `doge howl` (raw TCP) |
| Frontend | Server-rendered HTML + [Dogescript](https://github.com/dogescript/dogescript) for client-side behaviour |
| Storage | [DSON](https://github.com/dogescript/DSON) files in `data/` |
| Deploy | Docker container in a VM, LAN/VPN only; `data/` as volume |

## Deployment

First install:

```sh
git clone https://github.com/szasadny/boekhond.git && cd boekhond
cp .env.example .env
docker compose up -d --build 
```

Update:

```sh
git pull && docker compose up -d --build
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
