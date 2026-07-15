# Boekhond — Data Model

Split out of [ARCHITECTURE.md](./ARCHITECTURE.md) §4 so the model only loads when it is the task. **Every entity, field, or btw-code change updates this file in the same change.** Persistence rules (atomic writes, string-amounts, audit) are in ARCHITECTURE.md §4.

| § | Contents |
| --- | --- |
| 1 | Entities (one JSON collection each) |
| 2 | btw-codes → aangifte-rubrieken — the fiscal heart |
| 3 | Tijdvak & aangifte lifecycle |
| 4 | Invarianten (enforced in services, tested per Hard Rule 9) |

---

## 1. Entities

All ids are `"{prefix}-{oplopend Int}"` (`b-1`, `f-1`, …), issued by the store. All dates `"YYYY-MM-DD"`, timestamps ISO-8601 UTC (`nap.stamp`). All amounts Decimal-as-string (ARCHITECTURE.md §4).

```text
─── instellingen.dson (singleton Dict) ───────────────────────
  bedrijfsnaam, adres, kvk_nummer, btw_id, iban
  aangiftefrequentie   "kwartaal" (default; "maand"/"jaar" possible)
  kor                  Bool — Kleineondernemersregeling actief (→ §4.6)
  factuur_prefix       e.g. "" or "GB" — nummer wordt "{prefix}{jaar}-{####}"
  standaard_btw_code   default voor nieuwe boekingen/factuurregels

─── boekingen.dson (List) ────────────────────────────────────
  Boeking — één regel administratie; de bron van elke rubriek
    id, datum, type          "verkoop" | "inkoop"
    omschrijving, relatie    (klant/leverancier, vrije tekst)
    categorie                vrije-tekst kostensoort/omzetgroep (voor jaaroverzicht)
    bedrag_ex, btw_code, btw_bedrag, bedrag_incl
    bijlage_ids              [bijlage-id, …]
    factuur_id               gezet als de boeking uit een eigen factuur komt
    storno_van               boeking-id — dit ís een tegenboeking (correctie, §4.4)
    created_at

─── bijlagen.dson (List) ─────────────────────────────────────
  Bijlage — geüpload of geïmporteerd bewijsstuk; nooit verwijderd (Hard Rule 3)
    id, boeking_id           none = staat in de import-inbox, vandaaruit boeken
    bron                     "upload" | "import" (uit data/import/) | "factuur" (eigen gegenereerde)
    bestandsnaam_origineel   metadata only — nooit een pad (Hard Rule 7)
    pad                      "uploads/{jaar}/{id}{ext}"
    mime, grootte_bytes, geupload_op

─── facturen.dson (List) ─────────────────────────────────────
  Factuur — eigen verkoopfactuur
    id, nummer               none bij concept; "{prefix}{jaar}-{####}" bij definitief (§4.2)
    datum, vervaldatum
    klant                    {naam, adres, btw_id (optioneel, verplicht bij EU-levering)}
    regels                   [{omschrijving, aantal, prijs_ex, btw_code}]
    totaal_ex, btw_totaal, totaal_incl        (berekend, per btw_code gesplitst opgeslagen)
    status                   "concept" → "definitief" → "verzonden" → "betaald"
    boeking_id               gezet bij definitief (verkoop-boeking aangemaakt)
    terugkerend_id           gezet als gegenereerd uit een sjabloon
    created_at

─── terugkerend.dson (List) ──────────────────────────────────
  TerugkerendSjabloon — maandelijkse factuur-generator
    id, actief (Bool)
    klant, regels            zelfde vorm als Factuur
    dag_van_maand            1–28 (clamp — geen 29/30/31-gedoe)
    volgende_run             "YYYY-MM-DD" — na een run: +1 maand (lib/datum.doge)
    auto_definitief          Bool — direct nummeren + boeken, of als concept klaarzetten

─── aangiften.dson (List) ────────────────────────────────────
  Aangifte — één ingediend (of open berekend) tijdvak
    id, jaar, tijdvak        "Q1".."Q4" (of "01".."12" bij maandaangifte)
    status                   "open" | "ingediend"
    ingediend_op
    rubrieken                snapshot bij indienen: {rubriek: {omzet, btw}} (§2)
    saldo                    5a − 5b (te betalen; negatief = terug te vragen)

─── audit.dsonl (append-only, geen collectie) ────────────────
  {ts, actie, entiteit, id, data} — vóór elke state-write (ARCHITECTURE.md §4)
```

---

## 2. btw-codes → aangifte-rubrieken

**The fiscal heart.** Every Boeking has exactly one `btw_code`; every code maps to exactly one rubriek-behaviour. Implemented solely in `app/services/btw.doge` (Hard Rule 5); this table is its specification.

### Verkoop (type = "verkoop")

| btw_code | Betekenis | Rubriek | Effect |
| --- | --- | --- | --- |
| `hoog_21` | levering/dienst 21% | **1a** | omzet → 1a-omzet; btw (21%) → 1a-btw |
| `laag_9` | levering/dienst 9% | **1b** | omzet → 1b-omzet; btw (9%) → 1b-btw |
| `nul_binnenland` | 0% of niet bij u belast | **1e** | omzet → 1e; geen btw |
| `verlegd_naar_afnemer` | btw verlegd naar NL-afnemer | **1e** | omzet → 1e; geen btw; factuur vermeldt "btw verlegd" + btw-id afnemer |
| `vrijgesteld` | vrijgestelde prestatie | — | telt in geen rubriek; wel in jaaroverzicht |
| `export_buiten_eu` | levering buiten de EU | **3a** | omzet → 3a; geen btw |
| `levering_eu` | ICP: levering/dienst binnen EU (btw-id klant verplicht) | **3b** | omzet → 3b; geen btw; **flag: ICP-opgaaf vereist** (§4.7) |

### Inkoop (type = "inkoop")

| btw_code | Betekenis | Rubriek | Effect |
| --- | --- | --- | --- |
| `voorbelasting_hoog` | NL-inkoop 21% | **5b** | btw → 5b (aftrek) |
| `voorbelasting_laag` | NL-inkoop 9% | **5b** | btw → 5b |
| `verlegd_naar_mij` | btw naar mij verlegd (NL) | **2a + 5b** | bedrag_ex → 2a-grondslag; ik bereken 21% daarover → 2a-btw én dezelfde btw → 5b (per saldo 0 bij vol aftrekrecht) |
| `import_buiten_eu` | invoer van buiten de EU | **4a + 5b** | bedrag_ex → 4a-grondslag; btw daarover → 4a-btw én → 5b |
| `verwerving_eu` | verwerving binnen EU | **4b + 5b** | bedrag_ex → 4b-grondslag; btw daarover → 4b-btw én → 5b |
| `geen_btw` | zonder btw / niet aftrekbaar (kvk, verzekering, prive-deel) | — | alleen kosten, geen rubriek |

### Totalen

- **5a** = som van alle verschuldigde btw (1a + 1b + 2a + 4a + 4b).
- **5b** = som voorbelasting.
- **saldo** = 5a − 5b — positief: te betalen; negatief: terug te vragen.
- **Afronding:** rubrieken in **hele euro's** op de aangifte. De wet staat afronden in eigen voordeel toe; wij ronden per rubriek: verschuldigde btw **naar beneden**, voorbelasting (5b) **naar boven**. De onderliggende administratie blijft op de cent (Decimal).
- Btw per boeking/factuurregel: rekenkundig afronden op 2 decimalen (`dec`, half-up), per regel.

---

## 3. Tijdvak & aangifte lifecycle

1. Een tijdvak (kwartaal, `instellingen.aangiftefrequentie`) is **open** zolang er geen Aangifte met status `ingediend` voor bestaat; rubrieken worden live berekend uit de boekingen met `datum` in het tijdvak.
2. De ondernemer neemt de berekende rubrieken over in **Mijn Belastingdienst Zakelijk** (handmatig — geen publieke API; Digipoort is out of scope) en markeert het tijdvak **ingediend** → Aangifte-record met rubrieken-snapshot + `ingediend_op`.
3. Vanaf dat moment is het tijdvak **vergrendeld** (Hard Rule 3): boekingen met een datum in een ingediend tijdvak zijn immutable; nieuwe boekingen kunnen er niet in gedateerd worden.
4. **Correctie** op een vergrendeld tijdvak = storno-boeking (`storno_van`) + eventueel een nieuwe juiste boeking, beide gedateerd in het open tijdvak. De UI toont bij het volgende tijdvak een **suppletie-signaal** als het gecorrigeerde btw-effect > €1.000 is (dan is een suppletieformulier verplicht; daaronder mag verrekenen in de eerstvolgende aangifte).

---

## 4. Invarianten

Enforced in services, elk met een test (Hard Rule 9):

1. `btw_bedrag` en `bedrag_incl` zijn altijd herafleidbaar uit `bedrag_ex` + `btw_code` — de service berekent, de UI stuurt nooit een btw-bedrag in.
2. **Factuurnummers doorlopend per jaar, zonder gaten** — uitgifte alleen bij `concept → definitief`, in audit vastgelegd; een definitieve factuur kan nooit terug naar concept (wel: creditfactuur).
3. Een `definitief`-factuur heeft altijd exact één gekoppelde verkoop-boeking met identieke bedragen.
4. Een boeking in een ingediend tijdvak muteert nooit (§3.3); een storno verwijst altijd naar een bestaande boeking en spiegelt het bedrag exact.
5. Bijlagen worden nooit verwijderd; een boeking met bijlagen kan niet verwijderd worden (alleen storneren).
6. **KOR actief** (`instellingen.kor`): facturen zonder btw ("vrijgesteld van OB o.g.v. artikel 25 Wet OB"), geen rubrieken, geen aangiften; de app bewaakt de €20.000-omzetgrens per kalenderjaar en waarschuwt vanaf 80%.
7. `levering_eu` (3b) in een tijdvak → banner "ICP-opgaaf vereist" op het aangifte-overzicht (de opgaaf zelf is Goal Architecture).
8. Bedragen zijn overal Decimal (Hard Rule 1); een Float die het domein binnenkomt is een bug in de parse-laag, nergens anders.
