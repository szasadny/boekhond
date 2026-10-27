# Boekhond — Data Model

Split out of [ARCHITECTURE.md](./ARCHITECTURE.md) §4 so the model only loads when it is the task. **Every entity, field, or btw-code change updates this file in the same change.** Persistence rules (atomic writes, string-amounts, audit) are in ARCHITECTURE.md §4.

| § | Contents |
| --- | --- |
| 1 | Entities (one DSON collection each) |
| 2 | btw-codes → aangifte-rubrieken — the fiscal heart |
| 3 | Tijdvak & aangifte lifecycle |
| 4 | Invarianten (enforced in services, tested per Hard Rule 10) |
| 5 | Exportbundel (overdracht tussen instances) |

---

## 1. Entities

All ids are `"{prefix}-{oplopend Int}"` (`j-1` journaalpost, `b-1` bijlage, …), issued by the store. All dates `"YYYY-MM-DD"` in Europe/Amsterdam (`datum.vandaag`, `datum.lokale_datum`), timestamps ISO-8601 UTC (`nap.stamp`). All amounts Decimal-as-string (ARCHITECTURE.md §4).

```text
─── instellingen.dson (singleton Dict) ───────────────────────
  bedrijfsnaam, adres, kvk_nummer, btw_id, iban
  standaard_btw_code   default btw_code voor nieuwe journaalregels
  mollie_laatste_sync  "YYYY-MM-DD" — datum van de laatste geslaagde Mollie-sync; alleen weergave,
                       geen filter (de sync haalt altijd alles op, idempotent per id)
                       (de Mollie API-key is een secret → .env, nooit hier)

─── rekeningen.dson (List) — rekeningschema (chart of accounts) ───
  Rekening — grootboekrekening; geseed met een standaard-schema voor een
  eenmanszaak, uitbreidbaar in de UI (nummer is uniek en onwijzigbaar)
    nummer                   "1300" (vrij gekozen, RGS-geïnspireerd; alleen cijfers, getrimd)
    naam                     "Debiteuren" (verplicht, getrimd)
    type                     "activa" | "passiva" | "eigen_vermogen" | "omzet" | "kosten"
                             (allow-list `rekeningen.TYPES`; andere types geweigerd)
    btw_code                 optionele default voor regels op deze rekening
    actief                   Bool — deactiveren (en weer activeren) i.p.v. verwijderen (historie)
                             (systeemrekeningen `rekeningen.SYSTEEM` en rekeningen van een
                             actief kostensjabloon niet deactiveerbaar)

─── journaal.dson (List) — dubbel boekhouden (double-entry) ──
  Journaalpost — één transactie; de bron van elke rubriek én de balans
    id, datum
    omschrijving, relatie    (klant/leverancier, vrije tekst)
    regels                   [{rekening, debet, credit, btw_code, btw_bedrag?}]
                             per regel is debet óf credit gevuld (Decimal-as-string);
                             btw_code alleen op regels met fiscale betekenis
                             (omzet-/kostenregels = grondslag)
                             btw_bedrag (optioneel, Decimal-as-string, >= 0): de btw van
                             de factuur op deze grondslagregel (Mollie: incl − ex); max.
                             1 cent van ex × pct; ontbreekt hij, dan geldt ex × pct
    bron                     "mollie" | "terugkerend" | "handmatig" | "bank" | "memoriaal"
    mollie_payment_id        gezet bij bron "mollie" (betaling) — idempotentie-sleutel (§4.2);
                             geld-been op Bank (1100), omzet 21% -> rubriek 1a
    mollie_refund_id         gezet bij een Mollie-refund-tegenboeking — idempotentie-sleutel (§4.3)
    refund_van               journaalpost-id van de betaal-post (via `paymentId`), als die al geboekt is;
                             een post met een geboekte refund weigert `journaal.storneer` (§3.4)
    terugkerend_sleutel      gezet bij bron "terugkerend" — "{sjabloon-id}-{YYYY-MM}",
                             idempotentie-sleutel per sjabloon+maand (§4.2)
    valuta, bedrag_valuta    alleen bij bron "terugkerend" in vreemde valuta: "USD" en het
                             oorspronkelijke bedrag excl. btw (Decimal-as-string)
    koers, koers_tijd,       gebruikte koers (Decimal-as-string, bv. "0.86215"), het
    koers_bron               tijdstip van de koers (Wise `time`) en de bron ("wise") —
                             audit-metadata; de regels staan altijd in EUR
    bijlage_ids              [bijlage-id, …]
    storno_van               journaalpost-id — dit ís een tegenboeking (correctie, §3.4)
    correctie_van_datum      datum in een ingediend tijdvak waarop deze post corrigeert:
                             een Mollie-post die daarom in het open tijdvak is geboekt, of
                             een herboeking via `journaal.markeer_correctie` (§3.4)
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
    pad                      "uploads/{jaar}/{id}.{ext}"
    mime, grootte_bytes, geupload_op

─── terugkerend.dson (List) ──────────────────────────────────
  KostenSjabloon — maandelijkse kosten-generator (vaste abonnementen);
  bedragen zijn instance-data, alleen hier (data/, gitignored), nooit in source
    id, actief (Bool)         deactiveren (en weer activeren) i.p.v. verwijderen (Hard Rule 3)
    leverancier               vrije tekst
    omschrijving              boekingsomschrijving
    kosten_rek                actieve rekening met type "kosten" (bv. "4000")
    btw_code                  inkoop-code, verkoop-codes geweigerd (bv. import_buiten_eu → 4a + 5b)
    bedrag_ex                 Decimal-as-string, bedrag excl. btw, in `valuta`
    valuta                    "EUR" | "USD" (allow-list wisselkoers.VALUTA); ontbreekt bij
                              oude sjablonen → "EUR"
    dag                       1–28 (cap — boekdatum blijft geldig in korte maanden)
    vanaf                     "YYYY-MM" — eerste maand die geboekt mag worden
  De generator boekt per lopende maand één post per actief sjabloon (op/na `dag`,
  niet vóór `vanaf`), idempotent per sjabloon+maand via `terugkerend_sleutel` op de
  journaalpost. Geen backfill van gemiste maanden. De btw-splitsing (bv. 4a + 5b bij
  import_buiten_eu) loopt via `journaal.inkoop_post` — geen btw-logica hier.
  Een niet-EUR sjabloon wordt bij het boeken omgerekend met de live Wise-koers
  (`wisselkoers.omreken`, half-up op centen); zonder koers geen boeking (fout-melding,
  de volgende run probeert opnieuw). Weigert `journaal.bewaar` de post (bv. inactieve
  rekening), dan wordt dat geaudit als `terugkerend-mislukt`, als fout-melding gemeld en
  draait de rest door; het sjabloon blijft ongeboekt tot de oorzaak weg is.

─── aangiften.dson (List) ────────────────────────────────────
  Aangifte — één ingediend (of open berekend) tijdvak
    id, jaar, tijdvak        "Q1".."Q4"
    status                   "open" | "ingediend"
    ingediend_op
    rubrieken                snapshot bij indienen: {rubriek: {bedrag, btw}} — de btw.rubrieken()-motorvorm (§2)
    5a, 5b                   verschuldigd / voorbelasting (hele euro's), samen met de snapshot bevroren
    saldo                    5a − 5b (te betalen; negatief = terug te vragen)

─── tellers.dson (singleton Dict) ────────────────────────────
  {prefix: laatst uitgegeven Int} — id-uitgifte via store.nieuw_id ("j" → j-1, j-2, …);
  nooit verlaagd, dus een id wordt nooit hergebruikt

─── audit.dsonl (append-only, geen collectie) ────────────────
  {ts, actie, entiteit, id, data} — vóór elke state-write (ARCHITECTURE.md §4)
```

---

## 2. btw-codes → aangifte-rubrieken

**The fiscal heart.** Every journaalregel with fiscale betekenis (omzet- en kostenregels) carries exactly one `btw_code`; every code maps to exactly one rubriek-behaviour. The regel's bedrag is the grondslag (bedrag_ex); the corresponding btw-regel lands on the btw-rekening (af te dragen / voorbelasting). Implemented solely in `app/services/btw.doge` (Hard Rule 5); this table is its specification. `btw.rubrieken(posten, j, kw)` consumes the **journaalposten** of the tijdvak directly: it walks each post's `regels`, treats every regel with a `btw_code` as a grondslagregel (bedrag = debet/credit on its natural side), and derives the btw via `btw.regel_btw`: the regel's `btw_bedrag` (invoice btw, art. 37 Wet OB) when present, else `btw_code` + bedrag (invariant 1). A storno's mirrored debet/credit nets automatically. (Verkoop-codes komen op de omzet-regels van de Mollie-import; inkoop-codes op kosten-/activa-regels van terugkerende + handmatige inkoop — Resend/Claude/OpenAI zijn diensten van buiten de EU → `import_buiten_eu`, rubriek 4a + 5b.)

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
- **Afronding:** rubrieken in **hele euro's** op de aangifte. De wet staat afronden in eigen voordeel toe; wij ronden per rubriek: verschuldigde btw **naar beneden**, voorbelasting (5b) **naar boven**. De onderliggende administratie blijft op de cent (Decimal). Gevolg: verlegde btw (2a/4a/4b + 5b) die op de cent nettoot kan op de aangifte een saldo van een paar euro negatief geven. `btw.specificatie(posten, j, kw)` levert dezelfde afleiding per post zonder afronding; de aangiftepagina toont die naast de afgeronde cijfers, plus per post een controle of de geboekte btw (1510/1520) aansluit op de btw-codes (`aangifte.uitleg`). Daarnaast sluit `aangifte.aansluiting` het hele open tijdvak op de cent aan op het grootboek: verschuldigde btw tegen de netto credit-beweging op 1510, voorbelasting tegen de netto debet-beweging op 1520. Een btw-afrekening (post zonder btw-code die alleen activa/passiva/eigen vermogen raakt, zoals de btw-betaling) telt niet mee. Bij een verschil tonen het overzicht en de doen-pagina een waarschuwing; een ingediend tijdvak toont alleen de snapshot.
- Btw per journaalregel: rekenkundig afronden op 2 decimalen (`dec`, half-up), per regel.
- Inclusieve bedragen (Mollie levert incl) splitsen naar `[ex, btw]` via `btw.splits_incl`
  zoals de factuur: `ex = afgerond(incl × 100 / (100 + pct))`, `btw = incl − ex` (€ 100,00 → 82,64 +
  17,36). De factuur-btw is verschuldigd (art. 37 Wet OB), dus de omzetregel draagt hem als
  `btw_bedrag` en de aangifte telt die; geen afrondingsregel. Oudere Mollie-posten met een
  8900-regel (Afrondingsverschillen) houden hun ex × pct-afleiding. Afronding blijft in `btw.doge` (Hard Rule 5).
- Alleen Mollie-bedragen met `amount.currency == "EUR"` worden geboekt; een payment of refund in een andere valuta wordt geweigerd (geen koersconversie), niet als geboekt gemarkeerd en bij elke sync opnieuw gemeld (`geweigerd` + audit-event `mollie-geweigerd`). Een betaalde payment van 0,00 (bv. een mandaat-eerste-betaling) heeft geen omzet en wordt overgeslagen. Weigert `journaal.bewaar` een post (bv. een inactieve rekening), dan wordt die payment of refund evenmin als geboekt gemarkeerd, gemeld als `mislukt` + audit-event `mollie-mislukt`, en boekt de rest van de batch gewoon door. Een item met ontbrekende of ongeldige velden (`id`, `status`, `amount.value`, `paidAt`/`createdAt`, `description`) gaat op dezelfde manier naar `mislukt` + `mollie-mislukt`; een pagina zonder `_embedded` breekt de sync af met "ongeldig antwoord van Mollie".

---

## 3. Tijdvak & aangifte lifecycle

1. Een kwartaaltijdvak (`Q1`..`Q4`) is **open** zolang er geen Aangifte met status `ingediend` voor bestaat; rubrieken worden live berekend uit de journaalposten met `datum` in het tijdvak. Een tijdvak is alleen geldig met kwartaal 1 t/m 4 en een jaar vanaf het jaar van de vroegste journaalpost (uiterlijk vorig jaar, ook zonder posten, voor een nihil-aangifte) t/m volgend jaar; `aangifte.controleer_tijdvak` bewaakt dit voor `dien_in` en voor elke pagina die `j`/`kw` uit query of formulier leest (400 via `weergave.tijdvak_fout`).
2. De ondernemer neemt de berekende rubrieken over in **Mijn Belastingdienst Zakelijk** (handmatig — geen publieke API; Digipoort is out of scope) en markeert het tijdvak **ingediend** → Aangifte-record met rubrieken-snapshot + `ingediend_op`.
3. Vanaf dat moment is het tijdvak **vergrendeld** (Hard Rule 3): journaalposten met een datum in een ingediend tijdvak zijn immutable; nieuwe posten kunnen er niet in gedateerd worden.
4. **Correctie** op een vergrendeld tijdvak = storno-journaalpost (`storno_van`, debet/credit gespiegeld) + eventueel een nieuwe juiste post, beide gedateerd in het open tijdvak. De storno wordt gebouwd door `journaal.storno_post` (mirror + `storno_van`) en geboekt via `journaal.storneer`, dat een tweede storno van dezelfde post, een storno van een storno en een storno van een Mollie-betaling met een geboekte (ook gedeeltelijke) refund (`refund_van`) weigert, want die refund draait de omzet al terug. De UI toont bij het volgende tijdvak een **suppletie-signaal** als het gecorrigeerde btw-effect > €1.000 is (dan is een suppletieformulier verplicht; daaronder mag verrekenen in de eerstvolgende aangifte). De drempel en het signaal leven in `app/services/aangifte.doge` (`suppletie_signaal`), dat het btw-effect per post via `btw.post_effect` afleidt — nooit btw-rekenwerk buiten `btw.doge` (Hard Rule 5). Het signaal nettoot de signed effecten per oorspronkelijk ingediend tijdvak en telt de absolute netto bedragen per tijdvak op; tijdvakken netten niet tegen elkaar. Een Mollie-payment of -refund waarvan het eigen tijdvak al ingediend is, boekt `mollie.doge` op vandaag in het open tijdvak met `correctie_van_datum`. Een herboeking na een storno krijgt `correctie_van_datum` via het veld "Correctie van post" op de memoriaalpost: `journaal.markeer_correctie` neemt de datum van die post over en weigert een post buiten een ingediend tijdvak. Storno € 1.500 btw + herboeking € 1.400 telt zo als € 100.
5. De default voor **te doen** is het oudste afgelopen, nog niet ingediende kwartaal. Dashboard en doen-pagina noemen alle afgelopen, niet-ingediende kwartalen; een kwartaal is **te laat** na zijn uiterste datum (laatste dag van de maand na het tijdvak). Lege kwartalen ná de start van de administratie worden niet overgeslagen; op een clean install is dat het direct voorafgaande kwartaal.

---

## 4. Invarianten

Enforced in services, elk met een test (Hard Rule 10):

0. **Elke journaalpost balanceert:** som(debet) == som(credit), op de cent (Decimal). Een niet-balancerende post wordt geweigerd, nooit "rechtgetrokken". `journaal.bewaar` weigert daarnaast elke regel zonder bestaande, actieve rekening (een storno mag een inmiddels inactieve rekening raken), met debet én credit of geen van beide, met een negatief bedrag of een bedrag boven `geld.MAX_BEDRAG` (999.999.999,99), een post zonder bedrag groter dan nul, en een boekdatum meer dan een jaar na vandaag. Een bank/privé-post weigert 0900 als tegenrekening. Sjabloonflows dragen alleen codes van hun soort: `handmatig`/`terugkerend` alleen inkoop-codes, `mollie` alleen verkoop-codes; memoriaal en storno zijn vrij.
1. Btw-regels zijn altijd herafleidbaar uit de grondslagregels (`bedrag` + `btw_code`, of het `btw_bedrag` van de factuur dat de Mollie-import op de omzetregel zet; `journaal.bewaar` weigert een `btw_bedrag` dat meer dan 1 cent van ex × pct afwijkt) — de service berekent de btw-regel, de UI stuurt nooit een btw-bedrag in. Een storno neemt `btw_bedrag` ongewijzigd over; het teken volgt de grondslag, dus de storno nettoot.
2. **Import is idempotent, elke bron precies één keer geboekt:** een Mollie-payment wordt hoogstens één journaalpost (uniek `mollie_payment_id`), een kostensjabloon hoogstens één post per maand (uniek `terugkerend_sleutel` = sjabloon-id + maand; alleen de lopende maand, geen backfill). Een `data/import/`-bestand wordt hoogstens één Bijlage (`bron = "import"`): `bijlagen.scan_import` verwijdert de bronfile na een geslaagde ingest, dus een tweede scan vindt 'm niet meer — idempotentie via bronfile-verwijdering (geen stored key; een Bijlage is geen boeking). Een geweigerd importbestand wordt één keer gemeld en naar `data/import/overgeslagen/` verplaatst (nooit verwijderd). Dubbel draaien van de sync/scheduler/scan boekt nooit dubbel; elke import is een audit-event (Hard Rule 2).
3. Een journaalpost in een ingediend tijdvak muteert nooit (§3.3); een storno verwijst altijd naar een bestaande post en spiegelt alle regels exact (debet ↔ credit). Een Mollie-refund is zo'n tegenboeking (gespiegelde omzet-post, gedateerd op `createdAt`), idempotent per `mollie_refund_id` — dubbel syncen boekt 'm nooit dubbel.
4. Bijlagen worden nooit verwijderd; een journaalpost met bijlagen kan niet verwijderd worden (alleen storneren). Koppelen is symmetrisch en gaat via `journaal.koppel_bijlage` (de enige schrijver van journaalposten): het zet `journaalpost_id` op de Bijlage én voegt het bijlage-id toe aan `bijlage_ids` van de post — en wordt geweigerd als de post in een ingediend tijdvak valt (§3.3, invariant 3).
5. `levering_eu` (3b) in een tijdvak → banner "ICP-opgaaf vereist" op het aangifte-overzicht (de opgaaf zelf is Goal Architecture).
6. Bedragen zijn overal Decimal (Hard Rule 1); een Float die het domein binnenkomt is een bug in de parse-laag, nergens anders.

---

## 5. Exportbundel

Geen collectie maar een bestandsformaat: `GET /overdracht/export.json` levert de volledige administratie, `POST /overdracht/import` leest 'm in op een lege instance (`app/services/overdracht.doge`, ARCHITECTURE.md §4).

```text
─── boekhond-export-YYYY-MM-DD.json (JSON, niet DSON) ────────
  formaat      "boekhond-export"
  versie       1 — een andere versie wordt geweigerd
  gemaakt_op   ISO-8601 UTC
  collecties   {tellers, instellingen, rekeningen, terugkerend, aangiften, journaal, bijlagen}
               elk exact de inhoud van data/<naam>.dson (null als het bestand ontbreekt);
               bedragen blijven Decimal-as-string
  bestanden    {bijlage-id: base64} — de bytes achter elke Bijlage
  audit        de rauwe audit.dsonl-tekst
```

Een import valideert de hele bundel vóór de eerste write: alleen bekende collecties, elke journaalpost balanceert, elk bijlage-`pad` volgt exact `uploads/{jaar}/{id}.{ext}` met een toegestane extensie (`bijlagen.geldig_pad`, Hard Rule 7), elk bestand is aanwezig en heeft `grootte_bytes`, elke audit-regel is geldige DSON. `tellers` komt mee, zodat nieuwe ids na de import doorlopen.
