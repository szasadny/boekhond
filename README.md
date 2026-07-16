# Boekhond 🐕

Self-hosted boekhoudapp voor een Nederlandse eenmanszaak, volledig geschreven met de doge stack. Boekhond bereidt de btw-aangifte (omzetbelasting) per kwartaal volledig voor: dubbel boekhouden met btw-codes die één-op-één op de aangifte-rubrieken mappen, automatische inkomsten-import uit Mollie, terugkerende en handmatige kostenboekingen, en inkoopbewijs-uploads met 7 jaar bewaarplicht.

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
```

## Deployment

```sh
cp .env.example .env              # wachtwoord e.d. invullen
docker compose up -d              # app op poort 8085, administratie in ./data
```

Back-up = het `data/`-pad extern veiligstellen (volledige administratie, bewaarplicht 7 jaar).
