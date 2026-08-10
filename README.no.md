# Wintage

**Win95-mørk gull vintage-tema for hele nettet.** Et Tampermonkey-userscript som gjør hver nettside om til en mørk gullbrun Windows 95-applikasjon: pikselskarpe 3D-fasinger, null avrundede hjørner, null animasjoner, ingen hover-blitser, Verdana overalt.

[🤍 Støtt utvikleren](https://buymeacoffee.com/vacuum34)

[EN](README.md) | [RU](README.ru.md) | [ET](README.et.md) | [Дед](README.ded.md)

_Moderne nett optimaliserer estetikk på bekostning av brukervennlighet. Avrundede hjørner erstatter visuell hierarki, animasjoner erstatter tilbakemelding, skygger erstatter struktur, og minimalisme fjerner ofte nettopp signalene hjernen stoler på for å forstå et grensesnitt._

_Brukeren skal ikke måtte gjette om noe er en knapp, en etikett, et kort eller bare tekst. Wintage bringer tilbake et entydig visuelt språk: opphøyde knapper, nedsenkede inntastingsfelt, skarpe kanter, konsekvent typografi, null distraksjon og øyeblikkelige tilstandsendringer._

_Hvert element kommuniserer formålet sitt ved første øyekast, reduserer kognitiv belastning og gjør nettet til et presist instrument igjen i stedet for en samling dekorative bobler._

[Changelog](CHANGELOG.md)

## Installasjon

1. Installer [Tampermonkey](https://www.tampermonkey.net/) (Chrome, Edge, Firefox, Opera, Safari).
2. Klikk **[Installer Wintage](https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js)** — Tampermonkey åpner installasjonssiden automatisk.
3. Ferdig. Hver nettside du besøker kjører nå Windows 95, mørk gull-utgaven.

## Oppdatering

- **Automatisk:** skriptet har `@updateURL`/`@downloadURL` som peker til denne repo-en, så Tampermonkey henter nye versjoner ved sine regelmessige oppdateringskontroller.
- **Manuell oppdatering:** Tampermonkey → **Utilities → Check for userscript updates**, eller klikk bare på installasjonslenken igjen — den erstatter den gamle versjonen direkte, ingen avinstallering nødvendig.
- **Manglende temarader betyr gammelt skript:** menyen genereres fra det innebygde temaregisteret, og release-testen krever nøyaktig én menyarad per innebygd palett. Er menyen kortere enn palettlisten nedenfor, klikk igjen på **Install Wintage** og bekreft **Update** i Tampermonkey.

## Seksten paletter og en bryter

Wintage er ikke lenger én palett. Seks er UI.md-strukturen rotert til en annen fargefamilie (Dark Golden, Claude Code, Antigravity, K-Lite, FreeBuff, CodeNomad); Custom kan redigeres og lagres fra desktop-installatøren, og ni er importert fra [FastPrompter](https://github.com/vacterro) (Default, Golden Vintage, Golden Default, Vintage Dark, Vintage Classic, Dark 2 OLED, Dracula, Nord, Solarized Dark). Hver består WCAG AA på de tre tokenene som bærer tekst — build-porten avviser en palett som ikke gjør det.

Velg én fra **Tampermonkey-menyen** på hvilken som helst side; valget lagres per bruker, ikke per nettsted, så det gjelder på tvers av alle domener.

Paletter bor i `themes/*.json`, utenfor skriptet, av én grunn: Tampermonkey laster ned `wintage.user.js` på nytt ved hver oppdatering, så en håndskrevet palett ville forsvinne. Bruk dem på en fersk build med:

```powershell
.\install-themes.ps1 -Latest
```

## Utenfor nettleseren

De samme palettene installeres i desktop-applikasjoner — VS Code og Antigravity som fargetemaer, Electron-apper (Freebuff, Antigravity agent-app) via en shim som injiserer nøyaktig det stilarket dette userscriptet bruker. Det finnes et lite GUI for det:

Dobbeltklikk på **`Wintage Installer.vbs`** i roten av repo-en. Den åpner GUI-et uten konsollvindu. Den eldre `.cmd`-starteren videresender til den samme skjulte verten; `desktop\WintageInstaller.ps1` kan kjøres direkte for diagnostikk.

Hva hvert mål kan og ikke kan nå — inkludert de to appene som er forseglet eller har kompilerte farger — står i **[desktop/README.md](desktop/README.md)**.

## Funksjoner

- **Paletten Golden Default** — dyp brun-svart canvas `#1A1810`, gyllen tekst `#D4C89A`, gylne fasings-høylys `#F0D060`. Kun solide flate overflater: ingen gradienter, ingen uskarphet, ingen transparenseffekter.
- **Klassiske 3D-fasinger** — knapper opphøyd, inntastingsfelt nedsenket, trykkede knapper presses inn (med det autentiske 1px-etikettskiftet). Scrollbars er fulle 16px i Win95-stil, med fasett tommel og knapper.
- **Radius-dreper** — `border-radius: 0` håndheves overalt, inkludert framework-CSS-variabler (Bootstrap, Material, YouTube, Reddit).
- **Bevegelse forbudt** — alle overganger og animasjoner nullstilles. Tilstandsendringer er øyeblikkelige, som i et ekte 1995-grensesnitt.
- **Hover-markering helt av** — ingen hvite blitsrader, ingen grå toningsblokker:
  - fyllegenskaper fjernes kirurgisk fra hver lesbare `:hover`-regel (funksjonelle egenskaper som `display`/`visibility`/`opacity` beholdes, så hover-åpnede menyer fortsetter å fungere);
  - uleselige cross-origin-ark neutraliseres av en overgangsfrys-fallback.
  Kun ekte kontroller (knapper, lenker, inntastingsfelt) beholder en øyeblikkelig, tematisert fasingsreaksjon.
- **Verdana tvunget 100 % overalt** — inkludert inntastingsfelt og textarea, med font-utjamming av. Ikonfonter er unntatt så glyfer ikke blir til bokstaver. Har du en tilpasset font installert under navnet `Verdana_m1` (f.eks. en de-antialiased Verdana-patch), brukes den automatisk; ellers vanlig Verdana.
- **Adaptiv repainter** — en lettvekts JS-skanner omdanner lyse «blits»-flater og u-tematiserte mørk-modus-gråtoner til den vintage brune skalaen, og reparerer lavkontrast (mørkt-på-mørkt) tekst til gull ved WCAG-bevisste terskler. Bilder, videoer, canvas og spillere røres aldri.
- **Shadow DOM-gjennomtrengning** — tematiserer også webkomponenter (YouTube, Reddit og venner) via en `attachShadow`-krok.
- **Popups oppfører seg** — menyer, dialoger, tooltips og hoverkort farges bare om; skriptet tvinger aldri `opacity`/`z-index`/`visibility`, så skjult nettside-UI forblir skjult.
- **Sikkerhetsvakt** — skriptet deaktiverer seg selv på OAuth-, captcha-, bank- og betalingssider så kritiske flyter aldri restyles.

## Palett

Tabellen nedenfor viser 10 av 21 token i paletten Golden Default. Hver levert palett definerer alle 21; de resterende 11 dekker fasingsstruktur, sekundær tekst, semantiske farger (suksess/advarsel/fare), markering og mål-spesifikke detaljer.

| Token | Hex | Brukes til |
|---|---|---|
| background | `#1A1810` | ytterste bakgrunn |
| backgroundSoft | `#232018` | body-/innholds-bakgrunn |
| surface | `#332E22` | overskrifter, navigasjon, paneler |
| surfaceRaised | `#3D372A` | knapper, popups, scrollbar-tommel |
| surfaceAlt | `#453D30` | knapp-hover |
| borderHighlight | `#F0D060` | fasingskanter, lenker |
| borderDark | `#100E08` | nedsenkede kanter, rammer |
| textPrimary | `#D4C89A` | primær gyllen tekst |
| textMuted | `#6E674E` | plassholdere, deaktivert |
| link | `#F0D060` | lenker, fokus |

## Matchende nettlesertema

Målet `browsers` i desktop-installatøren registrerer installerte og bærbare Chromium-profiler, rapporterer Tampermonkey-dekning, forbereder det valgte nettlesertemaet og åpner riktige installasjons-/oppdateringssider for hver profil. Chromium krever én **Developer mode → Load unpacked**-bekreftelse per profil; installatøren kopierer den stabile temabanen til utklippstavlen. Senere palettendringer gjenbruker den banen.

## Kjent atferd

- Nettsteder som bygger hover-effekter i JavaScript (via klassebytte) i stedet for CSS `:hover`, kan fortsatt vise sin egen markering.
- På sjeldne nettsteder med cross-origin CSS kan et klikk på et ikke-fokuserbart element forsinke den visuelle tilstandsendringen til musen forlater det (hover-frys-fallbacken griper inn). Ekte knapper og lenker er unntatt.
- Skriptet er bevisst statisk: intet innstillingspanel, ingen per-nettsted-brytere. Fork det og rediger tokenene ovenfor hvis du vil ha en annen smak.

## Utgi en ny versjon (for vedlikeholdere)

Legg først til en `## [x.y.z] - date`-oppføring øverst i `CHANGELOG.md` — `release.ps1` nekter å kjøre uten den. Kjør deretter:

```powershell
.\release.ps1 -Message "hva som endret seg"
```

Det hever `@version`-patchnummeret (Tampermonkey-headeren og `W95_VERSION`-stempelet beveger seg sammen), bygger opp de genererte desktop-temaene, kjører hele release-gate-suiten, og committer, tagger og pusher — Tampermonkey-klienter henter oppdateringen automatisk. For større releaser sender du `-Bump minor` eller `-Bump major`.

## Lisens

[MIT](LICENSE)

<!-- source-digest: README.md sha256:886c5e27060e7b30 -->
