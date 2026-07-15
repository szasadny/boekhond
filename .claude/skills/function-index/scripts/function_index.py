#!/usr/bin/env python3
"""Bouw een compacte index van elke Doge-definitie in de codebase.

Een regel per definitie: `pad:regel: naam much params`, gesorteerd op pad.
Telt naar stderr. Query het resultaat met grep — nooit de hele file dumpen.

Doge-eigenaardigheid: `such` opent zowel functies (`such f much a:`) als lokale
variabelen (`such x = ...`). Discriminator: een definitie-header eindigt na het
strippen van een trailing comment op `:`. `many Name:` definieert een object;
methods staan geïnindenteerd binnen zo'n object en verschijnen als gewone
`such`-entries (het pad wijst het object aan).

Gebruik:
    python3 .claude/skills/function-index/scripts/function_index.py [--tests] [root]

    --tests   neem ook tests/ mee (default: overgeslagen)
    root      scan-wortel (default: cwd)
"""
import os
import re
import sys

# `such naam` of `many Naam`, onthoudt indent + keyword + naam + de rest van de header.
DEF = re.compile(r"^(?P<indent>\s*)(?P<kw>such|many)\s+(?P<naam>[A-Za-z_][A-Za-z0-9_]*)(?P<rest>.*)$")

# Mappen die nooit code-definities bevatten die je wilt hergebruiken.
SKIP_DIRS = {".git", "data", "static", "node_modules", "target"}


def strip_comment(regel):
    """Verwijder een trailing `# comment`, buiten strings om (grof maar voldoende)."""
    in_str = None
    for i, c in enumerate(regel):
        if in_str:
            if c == in_str and regel[i - 1] != "\\":
                in_str = None
        elif c in ("'", '"'):
            in_str = c
        elif c == "#":
            return regel[:i]
    return regel


def is_definitie(rest):
    """True als de header op `:` eindigt — dus een functie/object, geen variabele."""
    return strip_comment(rest).rstrip().endswith(":")


def scan(root, met_tests):
    treffers = []
    for dirpad, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.startswith(".")]
        if not met_tests and os.path.basename(dirpad) == "tests":
            dirs[:] = []
            continue
        for naam in files:
            if not naam.endswith(".doge"):
                continue
            if not met_tests and naam.startswith("test_"):
                continue
            pad = os.path.join(dirpad, naam)
            rel = os.path.relpath(pad, root)
            with open(pad, encoding="utf-8") as fh:
                for nr, regel in enumerate(fh, 1):
                    m = DEF.match(regel.rstrip("\n"))
                    if not m or not is_definitie(m.group("rest")):
                        continue
                    kw = m.group("kw")
                    # `much` na de naam = parameters; laat die zien voor hergebruik-afweging.
                    header = strip_comment(m.group("rest")).rstrip().rstrip(":").rstrip()
                    label = m.group("naam") + header if kw == "such" else m.group("naam") + " (object)"
                    treffers.append((rel, nr, label))
    return treffers


def main():
    argv = [a for a in sys.argv[1:]]
    met_tests = "--tests" in argv
    argv = [a for a in argv if a != "--tests"]
    root = argv[0] if argv else os.getcwd()

    treffers = scan(root, met_tests)
    treffers.sort(key=lambda t: (t[0], t[1]))
    for rel, nr, label in treffers:
        print(f"{rel}:{nr}: {label}")
    print(f"{len(treffers)} definities", file=sys.stderr)


if __name__ == "__main__":
    main()
