# Akcije SI

Zasebna aplikacija za spremljanje akcij in kuponov slovenskih trgovcev. Avtomatsko izpostavi:

1. **popuste ≥ 30 %** (prag nastaviš v aplikaciji),
2. **najnižjo ceno na enoto** (€/kg, €/l, €/kos) za isto vrsto izdelka med trgovinami,
3. **zadetke z najinega seznama opazovanih živil**.

Aplikacija ima dve sekciji. **Živila in vsakdanje potrebščine** zajema hrano, drogerijo, čistila in hrano za živali. **Dom, vrt in DIY** zajema OBI in neživilsko posebno ponudbo trgovcev.

| Platforma | Tehnologija | Namestitev |
|---|---|---|
| iPad / iPhone | SwiftUI (iOS/iPadOS 18+) | `.ipa` + Sideloadly ([navodila](#ipad-sideloadly)) |
| Android | Flutter | `.apk` ([navodila](#android)) |
| Windows | Flutter | `.zip` ([navodila](#windows)) |

Podatke zbira **strežniški del** (`scraper/`) v GitHub Actions vsakih 6 ur, ne telefon. Aplikacije prenesejo samo pripravljene JSON datoteke.

```
 trgovci ──► scraper (GitHub Actions, vsakih 6 h) ──► offers.json, coupons.json, meta.json,
                                                       history.json, guide.json
                                                         │  GitHub Pages + veja "data"
                                                         ▼
                        iPad (SwiftUI)  ·  Android / Windows (Flutter)
                                                         │  shared.json (zasebni repo)
                                                         ▼
                              skupni nakupovalni seznam in opazovana živila
```

## Viri

Stanje 14. 10. 2026. Trenutno stanje vsakega vira je v `meta.json` in na strani <https://jakobskerbis.github.io/akcije-v-trgovinah/>.

| Veriga | Vir | Opomba |
|---|---|---|
| Mercator | `mercatoronline.si` (JSON spletne trgovine) | redna in akcijska cena, cena na enoto, veljavnost, oznake »Pika kartica« in »ob nakupu 2 ali več«. PDF katalog je povezava. |
| SPAR / INTERSPAR | `online.spar.si` → *Iz letaka* | `www.spar.si` je za Cloudflare izzivom, ki ga ne zaobidemo. |
| Tuš | `tus.si` → aktualno iz kataloga, Tuš klub −50 %, tedenski kuponi | Veljavnost je samo na strani izdelka, zato se prebere ena stran na akcijsko skupino. Kuponi so slike s črtno kodo. |
| HOFER | `hofer.si/posebna-ponudba/LLLL-MM-DD` | Samo akcijska cena, brez redne. Letaki s svežo ponudbo so samo v slikah. |
| Lidl | `lidl.si` → Super ponudba (JSON v strani) | Vključno s cenami z Lidl Plus. |
| Eurospin | `eurospin.si/akcije/` | Tekoči in naslednji teden. |
| OBI | `obi.si/c/akcija` | Sekcija »Dom, vrt in DIY«. |

Jager je po tvoji odločitvi izpuščen.

Pred zajemom scraper preveri `robots.txt`, vsakemu strežniku pošlje največ en zahtevek na 1,5 s in se predstavi z User-Agentom `AkcijeSI/1.0 (osebna raba …)`. Pogoji uporabe Mercatorja in Tuša dovoljujejo osebno, nekomercialno rabo, ponovno objavo pa omejujejo. Podatki na GitHub Pages so javno dostopni (to je bila tvoja odločitev). Če želiš, da niso javni, nastavi repozitorij kot zaseben in izklopi Pages, aplikacijam pa daj dostop do veje `data` z žetonom.

## Scraper

```bash
cd scraper
python3.12 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
python -m pytest            # testi na shranjenih vzorcih (tests/fixtures)
python -m akcije --out ../public            # vse verige
python -m akcije --out ../public --only lidl,tus
```

Rezultat v `public/`:

| Datoteka | Vsebina |
|---|---|
| `offers.json` | ponudbe (model `Offer`: id, chain, name, brand, category, packSize, price, regularPrice, discountPct, unitPrice, validFrom, validTo, condition {type, description}, sourceUrl, imageUrl, fetchedAt …) |
| `coupons.json` | kuponi in ugodnosti (model `Coupon`) |
| `meta.json` | stanje vsakega vira (ok/napaka, čas, število izdelkov), verige z barvami, sekcije, kategorije, katalogi |
| `history.json` | zgodovina cen (180 dni) |
| `guide.json` | kopija `data/guide.json` |
| `report.md`, `unclassified.json` | poročilo o zajemu in **neuvrščeni izdelki**, po katerih dopolniš pravila |

Napaka enega vira ne ustavi ostalih. Če vir odpove, ostanejo v `offers.json` njegove še veljavne ponudbe iz zadnjega uspešnega zajema, označene s `stale: true`.

### GitHub Actions

- `.github/workflows/scrape.yml`: zajem vsakih 6 ur, ročni zagon (*Actions → Zajem akcij → Run workflow*) in zagon ob spremembi scraperja. Rezultat gre v vejo `data` in na GitHub Pages.
- **Enkratna nastavitev:** *Settings → Pages → Build and deployment → Source: GitHub Actions*. Dokler Pages ni vklopljen, aplikacije berejo podatke iz veje `data` (`raw.githubusercontent.com`).
- `.github/workflows/ios.yml` zgradi iOS aplikacijo, požene teste, posname zaslone (iPhone in iPad Pro 13″) in objavi `.ipa` v *Releases → ios-latest*.
- `.github/workflows/flutter.yml` zgradi Android `.apk` in Windows `.zip` ter ju objavi v *Releases → android-latest / windows-latest*.

### Kako dodati novo verigo

1. Ustvari `scraper/akcije/adapters/<veriga>.py` z razredom, ki deduje od `Adapter`:
   ```python
   class NovaAdapter(Adapter):
       chain = "nova"                 # kratek id
       source = "nova.si/akcije"      # opis vira
       url = "https://www.nova.si/akcije"
       default_section = "zivila"     # ali "dom"

       def fetch(self) -> list[Offer]:
           html = self.client.text(self.url)   # vljuden odjemalec (robots.txt, razmik)
           return parse(html, self.today, self.now)
   ```
   Razčlenjevanje loči v funkcijo `parse(...)`, da jo lahko testiraš brez omrežja. Za `source_category` nastavi kategorijo vira (npr. »Meso in ribe«), ker pomaga pri razvrščanju. Datume razčleni s `parse_date_range`, ceno na enoto pa izračunaj s `compute_unit_price` ali `parse_unit_price_text` (`akcije/units.py`).
2. Dodaj razred v `ADAPTERS` v `scraper/akcije/adapters/__init__.py`.
3. Dodaj verigo (ime, barva, povezava na katalog) v `CHAINS` v `scraper/akcije/pipeline.py`.
4. Shrani vzorec strani v `scraper/tests/fixtures/<veriga>_….html.gz` (`gzip -9`) in napiši test v `tests/test_adapters.py`.
5. `python -m pytest` in `python -m akcije --out /tmp/test --only nova`, nato v `report.md` preveri neuvrščene izdelke.

Aplikacije novo verigo prikažejo samodejno, ker barve in imena berejo iz `meta.json`.

### Razvrščanje v kategorije

`scraper/akcije/classify.py`:

- **`IZJEME`**: fraze, ki imajo prednost (npr. »sirni namaz« → sir, »čokoladno mleko« → pijače, »kozica … fi 14 cm« → kuhinja).
- **`STEMS`**: slovenski koreni po kategorijah (piščan, svinj, gov, mlet, losos, oslič, sir, mocarel, jogurt, skuta, mleko …). Zmaga koren, ki se v imenu pojavi **najprej** (»Čips …, kisla smetana« → sladko in prigrizki).
- **`HINTS`**: kategorije virov (Mercator, Tuš, Spar, Lidl, teme Hoferja). Določijo, ali je izdelek živilo, in privzeto kategorijo.
- **`KINDS`**: vrste izdelkov za primerjavo cene na enoto (mleko, piščančje prsi, mleto meso …).

Izdelki, ki jih pravila ne uvrstijo zanesljivo, so v `report.md` in `unclassified.json`. Pravilo dodaš, testiraš v `tests/test_classify.py`, zajem pa se ponovi ob naslednjem zagonu.

### Vodič

`data/guide.json` je vodič po aplikacijah trgovcev in programih zvestobe, kjer je vsak podatek opremljen z virom in datumom. Ko ga popraviš in potisneš v `main`, ga aplikacije dobijo ob naslednji osvežitvi, brez nove različice.

## Aplikacije

Skupne funkcije:

- Zavihki: Izpostavljeno, Kategorije, Kuponi, Moj seznam, Vodič.
- Iskanje, filter po verigi, kategoriji in pogoju, razvrščanje po popustu, ceni na enoto, ceni ali koncu akcije.
- Kartica izdelka prikaže akcijsko ceno, prečrtano redno ceno, % popusta, barvo verige, značko pogoja (kartica, aplikacija, kupon, količinski) in koliko dni akcija še velja.
- Podrobnosti izdelka: zgodovina cene in primerjava med trgovinami (ista EAN koda ali ista vrsta izdelka).
- Nakupovalni seznam in opazovana živila. Ujemanje upošteva sklone (»piščančje prsi« najde »Piščančja prsa«).
- Obvestila, ko se pojavi opazovano živilo, in povzetek novih izpostavljenih akcij.
- Temni način, dinamična velikost pisave, haptika na telefonu.

### iPad (Sideloadly)

Brez plačljivega Apple Developer računa in brez Maca se aplikacija namesti s **Sideloadly** z Windows prenosnika:

1. Na Windows namesti [Sideloadly](https://sideloadly.io) po navodilih na njihovi strani (zahteva iTunes in iCloud z Applove spletne strani).
2. Prenesi `AkcijeSI.ipa` z *Releases → ios-latest* tega repozitorija.
3. Poveži iPad s kablom, v Sideloadly izberi `.ipa`, vpiši svoj Apple ID in klikni *Start*.
4. Na iPadu: *Nastavitve → Zasebnost in varnost → Način za razvijalce* (Developer Mode) vklopi in znova zaženi. Nato *Nastavitve → Splošno → Upravljanje VPN in naprav* in zaupaj svojemu Apple ID-ju.
5. Z brezplačnim Apple ID-jem podpis velja **7 dni**, nato aplikacijo znova namesti s Sideloadly (podatki ostanejo).

Na iPadu so na voljo NavigationSplitView s tremi stolpci (stranska vrstica, mreža s 3–5 stolpci, podrobnosti) ter bližnjice **⌘F** (iskanje), **⌘R** (osvežitev) in **⌘1–5** (zavihki). Kazalec ima hover učinek, izdelek z vlečenjem spustiš na »Moj seznam«. Podprta sta Split View in Stage Manager; v ozkem oknu se aplikacija preklopi na telefonsko postavitev. Deluje v ležeči in pokončni usmeritvi.

Če boš kdaj imel Maca: `brew install xcodegen && cd ios && xcodegen generate && open AkcijeSI.xcodeproj`.

### Android

1. Na telefonu odpri *Releases → android-latest* in prenesi `AkcijeSI.apk`.
2. Odpri datoteko in dovoli namestitev iz tega vira.
3. Ob prvem zagonu dovoli obvestila. Osveževanje v ozadju teče prek WorkManagerja (približno na 6 ur).

### Windows

1. Prenesi `AkcijeSI-windows.zip` z *Releases → windows-latest* in ga razpakiraj, npr. v `C:\Programi\AkcijeSI`.
2. Zaženi `akcije_si.exe`. Ker aplikacija ni podpisana, Windows SmartScreen opozori; izberi *Več informacij → Vseeno zaženi*.
3. Bližnjice: **Ctrl+F**, **Ctrl+R**, **Ctrl+1–5**. Izdelke lahko povlečeš na »Moj seznam«. Ko je aplikacija odprta, se podatki osvežijo vsako uro.

## Skupna raba seznamov (namesto CloudKita)

CloudKit zahteva plačljiv Apple Developer račun, zato seznama živita v **zasebnem GitHub repozitoriju**, ki ga berejo vse tri aplikacije.

1. Na <https://github.com/new> ustvari repozitorij **`akcije-skupno`**, nastavljen kot **Private**.
2. Ustvari žeton: <https://github.com/settings/personal-access-tokens/new>
   - *Repository access → Only select repositories → `akcije-skupno`*
   - *Permissions → Repository permissions → Contents: **Read and write***
   - Rok veljavnosti nastavi po želji (npr. 1 leto) in si ga zapiši v koledar.
3. V aplikaciji odpri *Nastavitve → Skupna raba seznamov* in vpiši svoje ime, lastnika `jakobskerbis`, repozitorij `akcije-skupno` in žeton, nato izberi *Shrani in sinhroniziraj*.
4. Na drugi napravi izberi *Pokaži QR kodo*. Na Androidu jo skeniraj s kamero (odpre se `akcijesi://sync?...`), na iPadu s kamero ali prilepi povezavo v nastavitvah.

Spremembe se prenesejo ob vsaki spremembi in vsakih 20 s, ko je aplikacija odprta. Ob sočasnih spremembah zmaga novejša sprememba posamezne postavke. **QR koda in žeton dajeta dostop do repozitorija `akcije-skupno`, zato ju ne deli.**

## Struktura

```
scraper/        Python zajem (adapterji, razvrščanje, testi + fixtures)
data/guide.json vodič (urejaš tukaj)
web/            preprosta statusna stran za GitHub Pages
ios/            SwiftUI aplikacija (XcodeGen project.yml, testi, UI test in skripta za posnetke)
flutter_app/    Flutter aplikacija za Android in Windows
tools/          pomožne skripte (demo podatki za posnetke zaslona)
.github/        GitHub Actions
```

*Zasebni projekt za osebno, nekomercialno rabo. Podatki so last trgovcev in so informativni; velja cena v trgovini.*
