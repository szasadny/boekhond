# Boekhond 🐕

Self-hosted boekhoudapp voor een Nederlandse eenmanszaak, volledig geschreven in [Doge](https://github.com/DogeLanguage/doge). Boekhond bereidt de btw-aangifte (omzetbelasting) per kwartaal volledig voor: boekingen met btw-codes die één-op-één op de aangifte-rubrieken mappen, factuur-uploads met 7 jaar bewaarplicht, eigen verkoopfacturen met doorlopende nummering, en een import-inbox voor terugkerende facturen. Indienen doe je zelf via Mijn Belastingdienst Zakelijk — de app levert de exacte rubriekbedragen.

## Stack

| Layer | Technology |
| --- | --- |
| Backend | [Doge](https://github.com/DogeLanguage/doge) — transpiles to Rust, `doge build` yields a single binary |
| Web server | Own micro-framework on `howl` (raw TCP), deliberately single-threaded — one user |
| Frontend | Server-rendered HTML + [Dogescript](https://github.com/dogescript/dogescript) for client-side behaviour |
| Storage | DSON files in `data/` — atomic writes, append-only audit log, no database |
| Money | Doge `Decimal`, never floats; stored as strings |
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
.claude/         # projectdocs: ARCHITECTURE, DATA-MODEL, PLAN + skills
```

## Development

```sh
cargo install dogelang            # toolchain
doge bark                         # run (project entry)
doge check "$PWD/lib/datum.doge"  # snelle syntax check — absolute paths (doge#64)
doge test "$PWD/tests"            # volledige suite
doge fmt "$PWD/<file>"            # canonical formatting
```

## Deployment

```sh
cp .env.example .env              # wachtwoord e.d. invullen
docker compose up -d              # app op poort 8085, administratie in ./data
```

Back-up = het `data/`-pad extern veiligstellen (volledige administratie, bewaarplicht 7 jaar).

## Status

Fase 0 (fundament: datum, geld, btw-rubrieken, store — 24 tests) is af; fase 1 (webframework) is de volgende stap. Roadmap en taal-blockers: [.claude/PLAN.md](./.claude/PLAN.md).
