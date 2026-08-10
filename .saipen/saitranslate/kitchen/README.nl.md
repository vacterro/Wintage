# Wintage

**Win95 donkergouden-vintage-thema voor het hele web.** Een Tampermonkey-userscript dat elke website omtovert tot een donkere goudbruine Windows 95-applicatie: pixelhaarscherpe 3D-afschuiningen, nul afgeronde hoeken, nul animaties, geen hover-flitsen, overal Verdana.

[🤍 Ontwikkelaar steunen](https://buymeacoffee.com/vacuum34)

[EN](README.md) | [RU](README.ru.md) | [ET](README.et.md) | [Дед](README.ded.md)

_Het moderne web optimaliseert esthetiek ten koste van bruikbaarheid. Afgeronde hoeken vervangen visuele hiërarchie, animaties vervangen feedback, schaduwen vervangen structuur, en minimalisme verwijdert vaak precies de signalen waarop ons brein vertrouwt om een interface te begrijpen._

_De gebruiker zou niet moeten raden of iets een knop, label, kaart of gewoon tekst is. Wintage brengt een ondubbelzinnige visuele taal terug: verheven knoppen, verzonken invoervelden, scherpe randen, consistente typografie, nul afleiding en onmiddellijke statuswisselingen._

_Elk element communiceert zijn doel in één oogopslag, vermindert cognitieve belasting en maakt het web weer een precies instrument in plaats van een verzameling decoratieve bubbels._

[Changelog](CHANGELOG.md)

## Installatie

1. Installeer [Tampermonkey](https://www.tampermonkey.net/) (Chrome, Edge, Firefox, Opera, Safari).
2. Klik op **[Installeer Wintage](https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js)** — Tampermonkey opent de installatiepagina automatisch.
3. Klaar. Elke website die je bezoekt draait nu op Windows 95, donkergouden editie.

## Update

- **Automatisch:** het script draagt `@updateURL`/`@downloadURL` naar deze repository, dus Tampermonkey haalt nieuwe versies op bij zijn reguliere updatecontroles.
- **Handmatig updaten:** Tampermonkey → **Utilities → Check for userscript updates**, of klik simpelweg nogmaals op de installatielink — die vervangt de oude versie direct, geen de-installatie nodig.
- **Ontbrekende themaregels betekenen een oud script:** het menu wordt gegenereerd uit het ingebouwde themaregister, en de releasetest vereist precies één menuregel per ingebouwde palette. Is het menu korter dan de palettelijst hieronder, klik dan opnieuw **Install Wintage** en bevestig **Update** in Tampermonkey.

## Zestien paletten en een schakelaar

Wintage is niet langer één palette. Zes zijn de UI.md-structuur gedraaid naar een andere kleurfamilie (Dark Golden, Claude Code, Antigravity, K-Lite, FreeBuff, CodeNomad); Custom kan worden bewerkt en opgeslagen vanuit de desktopinstaller, en negen zijn geïmporteerd uit [FastPrompter](https://github.com/vacterro) (Default, Golden Vintage, Golden Default, Vintage Dark, Vintage Classic, Dark 2 OLED, Dracula, Nord, Solarized Dark). Elk haalt WCAG AA op de drie tokens die tekst dragen — de buildpoort weigert een palette dat dat niet haalt.

Kies er een uit het **Tampermonkey-menu** op elke pagina; de keuze wordt per gebruiker opgeslagen, niet per site, dus geldt ze voor alle domeinen.

Paletten leven in `themes/*.json`, buiten het script, om één reden: Tampermonkey downloadt `wintage.user.js` opnieuw bij elke update, dus een handgeschreven palette zou verdwijnen. Breng ze op een verse build aan met:

```powershell
.\install-themes.ps1 -Latest
```

## Verder dan de browser

Dezelfde paletten installeren in desktopapplicaties — VS Code en Antigravity als kleurthema's, Electron-apps (Freebuff, de Antigravity agent-app) via een shim die exact het stylesheet injecteert dat dit userscript gebruikt. Daarvoor is er een kleine GUI:

Dubbelklik op **`Wintage Installer.vbs`** in de repositorywortel. Het opent de GUI zonder consolevenster. De legacy `.cmd`-launcher leidt door naar dezelfde verborgen host; `desktop\WintageInstaller.ps1` kan voor diagnose direct worden uitgevoerd.

Wat elke doelgroep wel en niet kan bereiken — inclusief de twee apps die dichtgesold zijn of waarvan de kleuren zijn gecompileerd — staat in **[desktop/README.md](desktop/README.md)**.

## Functies

- **Golden Default-palette** — diep bruinzwart canvas `#1A1810`, gouden tekst `#D4C89A`, gouden afschuining-highlights `#F0D060`. Alleen massieve platte oppervlakken: geen verlopen, geen blur, geen transparantie-effecten.
- **Klassieke 3D-afschuiningen** — knoppen verheven, invoervelden verzonken, ingedrukte knoppen duiken naar binnen (met de authentieke 1px-labelverschuiving). Scrollbalken zijn volle 16px in Win95-stijl, met afgeschuinde duim en knoppen.
- **Radius-killer** — `border-radius: 0` wordt overal afgedwongen, inclusief framework-CSS-variabelen (Bootstrap, Material, YouTube, Reddit).
- **Beweging verboden** — alle overgangen en animaties zijn op nul gezet. Statuswisselingen zijn direct, zoals in een echte 1995-interface.
- **Hover-uitlichting volledig uitgeschakeld** — geen witte flitsregels, geen grijze tintblokken:
  - vuleigenschappen worden chirurgisch verwijderd uit elke leesbare `:hover`-CSS-regel (functionele eigenschappen zoals `display`/`visibility`/`opacity` blijven, zodat via hover geopende menu's blijven werken);
  - onleesbare cross-origin stylesheets worden geneutraliseerd door een overgangsbevriezings-fallback.
  Alleen echte bedieningselementen (knoppen, links, invoervelden) behouden een directe, gethematiseerde afschuiningreactie.
- **Verdana overal 100% afgedwongen** — inclusief invoervelden en textareas, met font-anti-aliasing uitgeschakeld. Iconfonts worden uitgesloten zodat glyphs geen letters worden. Als er een aangepast lettertype is geïnstalleerd onder de naam `Verdana_m1` (bijv. een ont-antialiased Verdana-patch), wordt dat automatisch gebruikt; anders normale Verdana.
- **Adaptieve repainter** — een lichtgewicht JS-sweeper zet lichte "flits"-oppervlakken en ongethematiseerde donkere grijstinten om naar de vintage bruine schaal, en repareert laagcontrast (donker-op-donker) tekst naar goud op WCAG-bewuste drempels. Afbeeldingen, video's, canvases en spelers worden nooit aangeraakt.
- **Shadow DOM-doordringing** — thematiseert ook webcomponenten (YouTube, Reddit en vrienden) via een `attachShadow`-hook.
- **Popups gedragen zich** — menu's, dialoogvensters, tooltips en hovercards worden alleen herkleurd; het script dwingt nooit `opacity`/`z-index`/`visibility`, dus verborgen site-UI blijft verborgen.
- **Veiligheidsbewaker** — het script schakelt zichzelf uit op OAuth-, captcha-, bank- en betaalpagina's zodat kritieke flows nooit worden herstijld.

## Palet

De tabel hieronder toont 10 van de 21 Golden Default-palet tokens. Elk verzonden palette definieert alle 21; de overige 11 dekken afschuinstructuur, secundaire tekst, semantische kleuren (succes/waarschuwing/gevaar), selectie en per-doelgroep-specifieke zaken.

| Token | Hex | Gebruikt voor |
|---|---|---|
| background | `#1A1810` | buitenste achtergrond |
| backgroundSoft | `#232018` | body-/inhoudsachtergrond |
| surface | `#332E22` | kopteksten, navigatie, panelen |
| surfaceRaised | `#3D372A` | knoppen, popups, scrollbalkduim |
| surfaceAlt | `#453D30` | knop-hover |
| borderHighlight | `#F0D060` | afschuinranden, links |
| borderDark | `#100E08` | verzonken randen, kaders |
| textPrimary | `#D4C89A` | primaire gouden tekst |
| textMuted | `#6E674E` | placeholders, uitgeschakeld |
| link | `#F0D060` | links, focus |

## Bijpassend browserthema

De `browsers`-doelgroep van de desktopinstaller detecteert geïnstalleerde en draagbare Chromium-profielen, rapporteert Tampermonkey-dekking, bereidt het geselecteerde browserthema voor en opent de juiste installatie-/updatepagina's voor elk profiel. Chromium vereist één **Developer mode → Load unpacked**-bevestiging per profiel; de installer kopieert het stabiele themapad naar het klembord. Latere palettewijzigingen hergebruiken dat pad.

## Bekend gedrag

- Sites die hover-effecten in JavaScript bouwen (via klassewissels) in plaats van CSS `:hover`, kunnen hun eigen uitlichting blijven tonen.
- Op zeldzame sites met cross-origin CSS kan een klik op een niet-focusbaar element de visuele statuswisseling vertragen tot de muis het verlaat (de hover-bevriezings-fallback grijpt in). Echte knoppen en links zijn uitgesloten.
- Het script is bewust statisch: geen optiepaneel, geen per-site-schakelaars. Fork het en bewerk de tokens hierboven als je een andere smaak wilt.

## Een nieuwe versie uitbrengen (voor onderhouders)

Voeg eerst een `## [x.y.z] - date`-item toe bovenaan `CHANGELOG.md` — `release.ps1` weigert te draaien zonder. Voer daarna uit:

```powershell
.\release.ps1 -Message "wat er veranderd is"
```

Het verhoogt het `@version`-patchnummer (de Tampermonkey-header en de `W95_VERSION`-stempel bewegen samen), herbouwt de gegenereerde desktopthema's, draait de volledige release-gate-suite, en commit, tagt en pusht — Tampermonkey-clients halen de update automatisch op. Voor grotere releases geef je `-Bump minor` of `-Bump major` door.

## Licentie

[MIT](LICENSE)

<!-- source-digest: README.md sha256:886c5e27060e7b30 -->
