# Boekhond — Data Model

Split out of [ARCHITECTURE.md](./ARCHITECTURE.md) §4 so the model only loads when it is the task. **Every entity, field, or btw-code change updates this file in the same change.** Persistence rules (atomic writes, string-amounts, audit) are in ARCHITECTURE.md §4.

| § | Contents |
| --- | --- |
| 1 | Entities (one DSON collection each) |
| 2 | btw-codes → aangifte-rubrieken — the fiscal heart |
| 3 | Tijdvak & aangifte lifecycle |
| 4 | Invarianten (enforced in services, tested per Hard Rule 9) |

---

## 1. Entities

All ids are `"{prefix}-{oplopend Int}"` (`j-1` journaalpost, `b-1` bijlage, …), issued by the store. All dates `"YYYY-MM-DD"`, timestamps ISO-8601 UTC (`nap.stamp`). All amounts Decimal-as-string (ARCHITECTURE.md §4).

```text
─── instellingen.dson (singleton Dict) ───────────────────────
  bedrijfsnaam, adres, kvk_nummer, btw_id, iban
  standaard_btw_code   default btw_code voor nieuwe journaalregels
  mollie_laatste_sync  "YYYY-MM-DD" — hoogwatermerk voor de Mollie-import (§4.2)
                       (de Mollie API-key is een secret → .env, nooit hier)

─── rekeningen.dson (List) — rekeningschema (chart of accounts) ───
  Rekening — grootboekrekening; geseed met een standaard-schema voor een
  eenmanszaak, uitbreidbaar in de UI (nummer is uniek en onwijzigbaar)
    nummer                   "1300" (vrij gekozen, RGS-geïnspireerd)
    naam                     "Debiteuren"
    type                     "activa" | "passiva" | "eigen_vermogen" | "omzet" | "kosten"
    btw_code                 optionele default voor regels op deze rekening
    actief                   Bool — deactiveren i.p.v. verwijderen (historie)

─── journaal.dson (List) — dubbel boekhouden (double-entry) ──
  Journaalpost — één transactie; de bron van elke rubriek én de balans
    id, datum
    omschrijving, relatie    (klant/leverancier, vrije tekst)
    regels                   [{rekening, debet, credit, btw_code}]
                             per regel is debet óf credit gevuld (Decimal-as-string);
                             btw_code alleen op regels met fiscale betekenis
                             (omzet-/kostenregels = grondslag)
    bron                     "mollie" | "terugkerend" | "handmatig" | "bank" | "memoriaal"
    mollie_payment_id        gezet bij bron "mollie" (betaling) — idempotentie-sleutel (§4.2);
                             geld-been op Bank (1100), omzet 21% -> rubriek 1a
    mollie_refund_id         gezet bij een Mollie-refund-tegenboeking — idempotentie-sleutel (§4.3)
    terugkerend_sleutel      gezet bij bron "terugkerend" — "{sjabloon-id}-{YYYY-MM}",
                             idempotentie-sleutel per sjabloon+maand (§4.2)
    bijlage_ids              [bijlage-id, …]
    storno_van               journaalpost-id — dit ís een tegenboeking (correctie, §4.4)
    created_at
  INVARIANT: som(debet) == som(credit) — een post die niet balanceert
  wordt nooit opgeslagen (§4.0). Posten ontstaan automatisch (Mollie-import =
  omzet; terugkerend = maandkosten) of via een sjabloonflow (inkoop, bank/privé)
  of een vrije memoriaalpost.

─── bijlagen.dson (List) ─────────────────────────────────────
  Bijlage — geüpload of geïmporteerd inkoopbewijs; nooit verwijderd (Hard Rule 3)
    id, journaalpost_id      none = staat in de import-inbox, vandaaruit boeken
    bron                     "upload" | "import" (uit data/import/)
    bestandsnaam_origineel   metadata only — nooit een pad (Hard Rule 7)
    pad                      "uploads/{jaar}/{id}{ext}"
    mime, grootte_bytes, geupload_op

─── terugkerend.dson (List) ──────────────────────────────────
  KostenSjabloon — maandelijkse kosten-generator (vaste abonnementen);
  bedragen zijn instance-data, alleen hier (data/, gitignored), nooit in source
    id, actief (Bool)         deactiveren i.p.v. verwijderen (Hard Rule 3)
    leverancier               vrije tekst
    omschrijving              boekingsomschrijving
    kosten_rek                kostenrekening-nummer (bv. "4000")
    btw_code                  inkoop-code (bv. import_buiten_eu → 4a + 5b)
    bedrag_ex                 Decimal-as-string, bedrag excl. btw
    dag                       1–28 (cap — boekdatum blijft geldig in korte maanden)
    vanaf                     "YYYY-MM" — eerste maand die geboekt mag worden
  De generator boekt per lopende maand één post per actief sjabloon (op/na `dag`,
  niet vóór `vanaf`), idempotent per sjabloon+maand via `terugkerend_sleutel` op de
  journaalpost. Geen backfill van gemiste maanden. De btw-splitsing (bv. 4a + 5b bij
  import_buiten_eu) loopt via `journaal.inkoop_post` — geen btw-logica hier.

─── aangiften.dson (List) ────────────────────────────────────
  Aangifte — één ingediend (of open berekend) tijdvak
    id, jaar, tijdvak        "Q1".."Q4"
    status                   "open" | "ingediend"
    ingediend_op
    rubrieken                snapshot bij indienen: {rubriek: {bedrag, btw}} — de btw.rubrieken()-motorvorm (§2)
    5a, 5b                   verschuldigd / voorbelasting (hele euro's), samen met de snapshot bevroren
    saldo                    5a − 5b (te betalen; negatief = terug te vragen)

─── audit.dsonl (append-only, geen collectie) ────────────────
  {ts, actie, entiteit, id, data} — vóór elke state-write (ARCHITECTURE.md §4)
```

---

## 2. btw-codes → aangifte-rubrieken

**The fiscal heart.** Every journaalregel with fiscale betekenis (omzet- en kostenregels) carries exactly one `btw_code`; every code maps to exactly one rubriek-behaviour. The regel's bedrag is the grondslag (bedrag_ex); the corresponding btw-regel lands on the btw-rekening (af te dragen / voorbelasting). Implemented solely in `app/services/btw.doge` (Hard Rule 5); this table is its specification. `btw.rubrieken(posten, j, kw)` consumes the **journaalposten** of the tijdvak directly: it walks each post's `regels`, treats every regel with a `btw_code` as a grondslagregel (bedrag = debet/credit on its natural side), and **re-derives** the btw from `btw_code` + bedrag — never from a stored btw-veld (invariant 1). A storno's mirrored debet/credit nets automatically. (Verkoop-codes komen op de omzet-regels van de Mollie-import; inkoop-codes op kosten-/activa-regels van terugkerende + handmatige inkoop — Resend/Claude/OpenAI zijn diensten van buiten de EU → `import_buiten_eu`, rubriek 4a + 5b.)

### Verkoop (type = "verkoop")

| btw_code | Betekenis | Rubriek | Effect |
| --- | --- | --- | --- |
| `hoog_21` | levering/dienst 21% | **1a** | omzet → 1a-omzet; btw (21%) → 1a-btw |
| `laag_9` | levering/dienst 9% | **1b** | omzet → 1b-omzet; btw (9%) → 1b-btw |
| `nul_binnenland` | 0% of niet bij u belast | **1e** | omzet → 1e; geen btw |
| `verlegd_naar_afnemer` | btw verlegd naar NL-afnemer | **1e** | omzet → 1e; geen btw; factuur vermeldt "btw verlegd" + btw-id afnemer |
| `vrijgesteld` | vrijgestelde prestatie | — | telt in geen rubriek; wel in jaaroverzicht |
| `export_buiten_eu` | levering buiten de EU | **3a** | omzet → 3a; geen btw |
| `levering_eu` | ICP: levering/dienst binnen EU (btw-id klant verplicht) | **3b** | omzet → 3b; geen btw; **flag: ICP-opgaaf vereist** (§4.5) |
| `prive_gebruik` | btw-correctie privégebruik zakelijke zaken (alleen Q4) | **1d** | grondslag → 1d; btw (21%) → 1d; telt in 5a. Geboekt via `journaal.privegebruik_post` (self-nettend memo-paar op 0900, geen omzet-vervuiling) |

### Inkoop (type = "inkoop")

| btw_code | Betekenis | Rubriek | Effect |
| --- | --- | --- | --- |
| `voorbelasting_hoog` | NL-inkoop 21% | **5b** | btw → 5b (aftrek) |
| `voorbelasting_laag` | NL-inkoop 9% | **5b** | btw → 5b |
| `verlegd_naar_mij` | btw naar mij verlegd (NL) | **2a + 5b** | bedrag_ex → 2a-grondslag; ik bereken 21% daarover → 2a-btw én dezelfde btw → 5b (per saldo 0 bij vol aftrekrecht) |
| `import_buiten_eu` | invoer van buiten de EU | **4a + 5b** | bedrag_ex → 4a-grondslag; btw daarover → 4a-btw én → 5b |
| `verwerving_eu` | verwerving binnen EU | **4b + 5b** | bedrag_ex → 4b-grondslag; btw daarover → 4b-btw én → 5b |
| `geen_btw` | zonder btw / niet aftrekbaar (kvk, verzekering, prive-deel) | — | alleen kosten, geen rubriek |
| `horeca` | eten/drinken in de horeca (btw niet aftrekbaar) | — | kosten incl. btw, geen rubriek, geen 5b |
| `relatiegeschenk_bua` | gift/relatiegeschenk/personeel boven €227 p.p.p.j. (BUA) | — | kosten incl. btw, geen rubriek, geen 5b |

### Totalen

- **5a** = som van alle verschuldigde btw (1a + 1b + 1d + 2a + 4a + 4b).
- **5b** = som voorbelasting.
- **saldo** = 5a − 5b — positief: te betalen; negatief: terug te vragen.
- **Afronding:** rubrieken in **hele euro's** op de aangifte. De wet staat afronden in eigen voordeel toe; wij ronden per rubriek: verschuldigde btw **naar beneden**, voorbelasting (5b) **naar boven**. De onderliggende administratie blijft op de cent (Decimal).
- Btw per journaalregel: rekenkundig afronden op 2 decimalen (`dec`, half-up), per regel.
- Inclusieve bedragen (Mollie levert incl) splitsen naar `[ex, btw]` via `btw.splits_incl`
  (`btw = btw_bedrag(ex)`, gelijk aan de aangifte-afleiding); een afrondingsverschil boekt op
  rekening 8900 (Afrondingsverschillen) — afronding blijft in `btw.doge` (Hard Rule 5).

---

## 3. Tijdvak & aangifte lifecycle

1. Een kwartaaltijdvak (`Q1`..`Q4`) is **open** zolang er geen Aangifte met status `ingediend` voor bestaat; rubrieken worden live berekend uit de journaalposten met `datum` in het tijdvak.
2. De ondernemer neemt de berekende rubrieken over in **Mijn Belastingdienst Zakelijk** (handmatig — geen publieke API; Digipoort is out of scope) en markeert het tijdvak **ingediend** → Aangifte-record met rubrieken-snapshot + `ingediend_op`.
3. Vanaf dat moment is het tijdvak **vergrendeld** (Hard Rule 3): journaalposten met een datum in een ingediend tijdvak zijn immutable; nieuwe posten kunnen er niet in gedateerd worden.
4. **Correctie** op een vergrendeld tijdvak = storno-journaalpost (`storno_van`, debet/credit gespiegeld) + eventueel een nieuwe juiste post, beide gedateerd in het open tijdvak. De storno wordt gebouwd door `journaal.storno_post` (mirror + `storno_van`). De UI toont bij het volgende tijdvak een **suppletie-signaal** als het gecorrigeerde btw-effect > €1.000 is (dan is een suppletieformulier verplicht; daaronder mag verrekenen in de eerstvolgende aangifte). De drempel en het btw-effect per storno leven in `app/services/aangifte.doge` (`suppletie_signaal`), dat het effect via `btw.post_effect` afleidt — nooit btw-rekenwerk buiten `btw.doge` (Hard Rule 5).

---

## 4. Invarianten

Enforced in services, elk met een test (Hard Rule 9):

0. **Elke journaalpost balanceert:** som(debet) == som(credit), op de cent (Decimal). Een niet-balancerende post wordt geweigerd, nooit "rechtgetrokken".
1. Btw-regels zijn altijd herafleidbaar uit de grondslagregels (`bedrag` + `btw_code`) — de service berekent de btw-regel, de UI stuurt nooit een btw-bedrag in.
2. **Import is idempotent, elke bron precies één keer geboekt:** een Mollie-payment wordt hoogstens één journaalpost (uniek `mollie_payment_id`), een kostensjabloon hoogstens één post per maand (uniek `terugkerend_sleutel` = sjabloon-id + maand; alleen de lopende maand, geen backfill). Een `data/import/`-bestand wordt hoogstens één Bijlage (`bron = "import"`): `bijlagen.scan_import` verwijdert de bronfile na een geslaagde ingest, dus een tweede scan vindt 'm niet meer — idempotentie via bronfile-verwijdering (geen stored key; een Bijlage is geen boeking). Dubbel draaien van de sync/scheduler/scan boekt nooit dubbel; elke import is een audit-event (Hard Rule 2).
3. Een journaalpost in een ingediend tijdvak muteert nooit (§3.3); een storno verwijst altijd naar een bestaande post en spiegelt alle regels exact (debet ↔ credit). Een Mollie-refund is zo'n tegenboeking (gespiegelde omzet-post, gedateerd op `createdAt`), idempotent per `mollie_refund_id` — dubbel syncen boekt 'm nooit dubbel.
4. Bijlagen worden nooit verwijderd; een journaalpost met bijlagen kan niet verwijderd worden (alleen storneren). Koppelen is symmetrisch en gaat via `journaal.koppel_bijlage` (de enige schrijver van journaalposten): het zet `journaalpost_id` op de Bijlage én voegt het bijlage-id toe aan `bijlage_ids` van de post — en wordt geweigerd als de post in een ingediend tijdvak valt (§3.3, invariant 3).
5. `levering_eu` (3b) in een tijdvak → banner "ICP-opgaaf vereist" op het aangifte-overzicht (de opgaaf zelf is Goal Architecture).
6. Bedragen zijn overal Decimal (Hard Rule 1); een Float die het domein binnenkomt is een bug in de parse-laag, nergens anders.
