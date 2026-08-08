# Wintage

**Win95-mørk gylden vintage-tema til hele nettet.** Et Tampermonkey-userscript, der gør hver hjemmeside om til en mørk gyldenbrun Windows 95-applikation: pixelskarpe 3D-fasninger, nul afrundede hjørner, nul animationer, ingen hover-blink, Verdana overalt.

[🤍 Støt udvikleren](https://buymeacoffee.com/vacuum34)

[EN](README.md) | [RU](README.ru.md) | [ET](README.et.md) | [Дед](README.ded.md)

_Det moderne web optimerer æstetik på bekostning af brugervenlighed. Afrundede hjørner erstatter visuel hierarki, animationer erstatter feedback, skygger erstatter struktur, og minimalisme fjerner ofte præcis de signaler, hjernen stoler på for at forstå et interface._

_Brugeren skal ikke gætte, om noget er en knap, en etiket, et kort eller bare tekst. Wintage bringer et entydigt visuelt sprog tilbage: hævede knapper, forsænkede inputfelter, skarpe kanter, konsistent typografi, nul distraktion og øjeblikkelige tilstandsændringer._

_Hvert element kommunikerer sit formål ved første øjekast, reducerer kognitiv belastning og gør nettet til et præcist instrument igen i stedet for en samling dekorative bobler._

[Changelog](CHANGELOG.md)

## Installation

1. Installér [Tampermonkey](https://www.tampermonkey.net/) (Chrome, Edge, Firefox, Opera, Safari).
2. Klik på **[Installér Wintage](https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js)** — Tampermonkey åbner installationssiden automatisk.
3. Færdig. Hver hjemmeside, du besøger, kører nu Windows 95, mørk gylden udgave.

## Opdatering

- **Automatisk:** scriptet har `@updateURL`/`@downloadURL` pegende på dette repository, så Tampermonkey henter nye versioner ved sine regelmæssige opdateringskontroller.
- **Manuel opdatering:** Tampermonkey → **Utilities → Check for userscript updates**, eller klik bare på installationslinket igen — det erstatter den gamle version direkte, ingen afinstallation nødvendig.
- **Manglende temarækker betyder gammelt script:** menuen genereres fra det indbyggede temaregister, og release-testen kræver præcis én menurække per indbygget palet. Er menuen kortere end paletlisten nedenfor, så klik igen på **Install Wintage** og bekræft **Update** i Tampermonkey.

## Seksten paletter og en kontakt

Wintage er ikke længere én palet. Seks er UI.md-strukturen roteret til en anden farvefamilie (Dark Golden, Claude Code, Antigravity, K-Lite, FreeBuff, CodeNomad); Custom kan redigeres og gemmes fra desktopinstalleren, og ni er importeret fra [FastPrompter](https://github.com/vacterro) (Default, Golden Vintage, Golden Default, Vintage Dark, Vintage Classic, Dark 2 OLED, Dracula, Nord, Solarized Dark). Hver består WCAG AA på de tre tokens, der bærer tekst — build-porten afviser en palet, der ikke gør.

Vælg én fra **Tampermonkey-menuen** på enhver side; valget gemmes per bruger, ikke per side, så det gælder på tværs af alle domæner.

Paletter bor i `themes/*.json`, uden for scriptet, af én grund: Tampermonkey gen-downloader `wintage.user.js` ved hver opdatering, så en håndskrevet palet ville forsvinde. Anvend dem på en frisk build med:

```powershell
.\install-themes.ps1 -Latest
```

## Ud over browseren

De samme paletter installeres i desktopapplikationer — VS Code og Antigravity som farvetemaer, Electron-apps (Freebuff, Antigravity agent-app) via en shim, der injicerer præcis det stylesheet, dette userscript bruger. Der er et lille GUI til det:

Dobbeltklik på **`Wintage Installer.vbs`** i repoets rod. Det åbner GUI'et uden konsolvindue. Den ældre `.cmd`-launcher videresender til den samme skjulte vært; `desktop\WintageInstaller.ps1` kan køres direkte til diagnostik.

Hvad hvert mål kan og ikke kan nå — inklusive de to apps, der er forseglet eller har kompilerede farver — står i **[desktop/README.md](desktop/README.md)**.

## Funktioner

- **Paletten Golden Default** — dyb brun-sort canvas `#1A1810`, gylden tekst `#D4C89A`, gyldne fasnings-højlys `#F0D060`. Kun solide flade overflader: ingen gradienter, ingen sløring, ingen transparenseffekter.
- **Klassiske 3D-fasninger** — knapper hævet, inputfelter forsænket, trykkede knapper presses ind (med det autentiske 1px-etiket-skift). Scrollbars er fulde 16px i Win95-stil, med faset tommelfinger og knapper.
- **Radius-dræber** — `border-radius: 0` håndhæves overalt, inklusive framework-CSS-variabler (Bootstrap, Material, YouTube, Reddit).
- **Bevægelse forbudt** — alle overgange og animationer nulstilles. Tilstandsændringer er øjeblikkelige, som i et rigtigt 1995-interface.
- **Hover-markering helt slået fra** — ingen hvide blinkrækker, ingen grå toningsblokke:
  - fyldegenskaber fjernes kirurgisk fra hver læsbar `:hover`-regel (funktionelle egenskaber som `display`/`visibility`/`opacity` beholdes, så hover-åbnede menuer fortsat virker);
  - ulæselige cross-origin stylesheets neutraliseres af en overgangs-frys-fallback.
  Kun ægte kontroller (knapper, links, inputfelter) beholder en øjeblikkelig, tematiseret fasningsreaktion.
- **Verdana tvunget 100 % overalt** — inklusive inputfelter og textarea, med font-udjævning slået fra. Ikonfonte er undtaget, så glyffer ikke bliver til bogstaver. Hvis du har en brugerdefineret font installeret under navnet `Verdana_m1` (f.eks. en de-antialiased Verdana-patch), bruges den automatisk; ellers almindelig Verdana.
- **Adaptiv repainter** — en letvægts JS-scanner omdanner lyse "blink"-overflader og ikke-tematiserede mørk-tilstande-grå til den vintage brune skala og reparerer lavkontrast (mørk-på-mørk) tekst til guld ved WCAG-bevidste tærskler. Billeder, videoer, canvasser og afspillere røres aldrig.
- **Shadow DOM-gennemtrængning** — tematiserer også webkomponenter (YouTube, Reddit og venner) via en `attachShadow`-hook.
- **Popups opfører sig** — menuer, dialoger, tooltips og hoverkort farves kun om; scriptet tvinger aldrig `opacity`/`z-index`/`visibility`, så skjult UI forbliver skjult.
- **Sikkerhedsvagt** — scriptet deaktiverer sig selv på OAuth-, captcha-, bank- og betalingssider, så kritiske flows aldrig restyles.

## Palet

Tabellen nedenfor viser 10 af 21 tokens i paletten Golden Default. Hver leveret palet definerer alle 21; de resterende 11 dækker fasningsstruktur, sekundær tekst, semantiske farver (succes/advarsel/fare), markering og mål-specifikke detaljer.

| Token | Hex | Bruges til |
|---|---|---|
| background | `#1A1810` | yderste baggrund |
| backgroundSoft | `#232018` | body-/indholdsbaggrund |
| surface | `#332E22` | overskrifter, navigation, paneler |
| surfaceRaised | `#3D372A` | knapper, popups, scrollbar-tommel |
| surfaceAlt | `#453D30` | knap-hover |
| borderHighlight | `#F0D060` | fasningskanter, links |
| borderDark | `#100E08` | forsænkede kanter, rammer |
| textPrimary | `#D4C89A` | primær gylden tekst |
| textMuted | `#6E674E` | pladsholdere, deaktiveret |
| link | `#F0D060` | links, fokus |

## Matchende browsertema

Målet `browsers` i desktopinstalleren registrerer installerede og bærbare Chromium-profiler, rapporterer Tampermonkey-dækning, forbereder det valgte browsertema og åbner de rigtige installations-/opdateringssider for hver profil. Chromium kræver én **Developer mode → Load unpacked**-bekræftelse per profil; installeren kopierer den stabile temasti til udklipsholderen. Senere paletændringer genbruger den sti.

## Kendt adfærd

- Sider, der bygger hover-effekter i JavaScript (via klasseændringer) i stedet for CSS `:hover`, kan fortsat vise deres egen markering.
- På sjældne sider med cross-origin CSS kan et klik på et ikke-fokuserbart element forsinke den visuelle tilstandsændring, indtil musen forlader det (hover-frys-fallbacken griber ind). Ægte knapper og links er undtaget.
- Scriptet er bevidst statisk: intet indstillingspanel, ingen per-site-kontakter. Fork det og redigér tokens ovenfor, hvis du vil have en anden smag.

## Udgive en ny version (for vedligeholdere)

Redigér `wintage.user.js`, kør derefter:

```powershell
.\release.ps1 -Message "hvad der ændrede sig"
```

Det hæver `@version`-patchnummeret, committer og pusher — Tampermonkey-klienter henter opdateringen automatisk. Til større releases skal du sende `-Bump minor` eller `-Bump major`.

## Licens

[MIT](LICENSE)

<!-- source-digest: README.md sha256:ee7c6a2a1626faed -->
