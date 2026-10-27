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
| Deploy | Docker container in a VM/LXC, LAN/VPN only; `data/` as volume |

## Deployment

First install:

```sh
git clone https://github.com/szasadny/boekhond.git && cd boekhond
cp .env.example .env
# Zet PUBLISH_HOST in .env op het LAN/VPN-adres van de VM/LXC voor directe netwerktoegang.
# Zet TOEGESTANE_HOSTS op de host[:port]-waarden waarmee je de app opent; leeg = alleen loopback.
mkdir -p data && sudo chown 1000:1000 data
docker compose up -d --build
```

The container runs as the non-root user `boekhond` with UID/GID `1000:1000` (build args `UID`/`GID` in the Dockerfile), so `data/` on the host must be writable by that UID. An install from before this change has root-owned files in `data/`: run `sudo chown -R 1000:1000 data` once before the update. Compose publishes `POORT` from `.env` on `PUBLISH_HOST`, runs an init process (`init: true`) so `docker stop` is immediate, and the image has a `HEALTHCHECK` on `/health`.

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
