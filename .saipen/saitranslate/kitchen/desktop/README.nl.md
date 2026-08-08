# Wintage voor desktopapplicaties

De userscript themet het web. Dit themet de programma's eromheen, vanuit dezelfde
paletten, zodat de browser en de apps het niet meer oneens zijn over wat donkergoud
betekent.

Er is één regel achter elke beslissing hier: **applicaties updaten zichzelf, en
een update mag niets stilletjes breken.** Waar een target een eigen plek in je
profiel heeft, gaat het thema daarheen en overleeft het updates. Waar dat niet zo
is, is de installer zo geschreven dat hij opnieuw kan worden uitgevoerd — en zegt
hij dat ook, in plaats van te doen alsof hij blijvend is toegepast.

## De GUI

Dubbelklik op **`Wintage Installer.vbs`** in de repo-root om hem te openen zonder
consolevenster, of draai dit rechtstreeks voor diagnostiek:

```powershell
powershell -File desktop\WintageInstaller.ps1
```

Themalijst met kleurstalen, de targets die op deze machine zijn gevonden, een live
Win95-voorbeeld en alle eenentwintig kleurtokens als bewerkbare stalen. Een staal
bewerken splitst het palet af naar **Custom** in plaats van een meegeleverd thema
onder je vandaan te veranderen. Het paneel rechts toont live WCAG-contrast voor de
drie tokens die tekst dragen — een palet dat daar FAIL krijgt, wordt door de
buildgate toch geweigerd, dus het is beter om het vóór Apply te zien dan erna.

Targets zijn verdeeld over twee lijsten die met het toetsenbord bereikbaar zijn:
**MY APPS** bevat de draagbare/source-tree CodeNomad, SAIPENVIEW, SmartVac en
WildRift-tools; **POPULAR APPS** bevat Windows, OBS, terminals, editors en de
overige geïnstalleerde software. ALL/NONE en Apply/Revert werken op beide lijsten
zonder hun groepering te veranderen.

Het venster draagt het palet dat het op het punt staat te installeren. Dat is het
snelste beschikbare voorbeeld, en het houdt de tool eerlijk: een palet dat dit
venster onleesbaar maakt, is zichtbaar onleesbaar.

Apply delegeert naar `install.ps1`. Er is precies één codepad dat een thema
installeert, dus de GUI kan niet afdwalen van de commandoregel.

## De commandoregel

```powershell
.\desktop\install.ps1                                  # wat er is, wat gethemed is, met welk palet
.\desktop\install.ps1 -Target freebuff -Palette klite  # één app, één palet
.\desktop\install.ps1 -Target all -Palette goldendefault # alles
.\desktop\install.ps1 -Target all -WhatIf              # zeg wat er zou veranderen, raak niets aan
.\desktop\install.ps1 -Target freebuff -Revert         # één ongedaan maken
```

`-Palette` staat standaard op `goldendefault` (**Golden Default**). De GUI opent
op hetzelfde palet en controleert elk beschikbaar target. Het herschilderen van een
app die al gethemed is, werkt terwijl hij draait; een eerste installatie niet,
omdat het archief dan in gebruik is.

## Wat elk target daadwerkelijk kan worden gethemed

| target | mechanisme | overleeft een app-update |
|---|---|---|
| `windows` | gebruikers-`.theme`: donkere systeem/app-modus, accent- en klassieke kleurrollen | yes — geïnstalleerd in je lokale Windows Themes-map |
| `browsers` | detecteert geïnstalleerde + draagbare Chromium-profielen, plaatst het gekozen chrome-thema klaar en opent door de browser beheerde Tampermonkey/themabevestigingspagina's | yes — na één **Load unpacked** per profiel |
| `terminal` | Windows Terminal-schema + standaardwaarden voor alle profielen, Consolas 12 gealiased | yes — de instellingen staan in je profiel |
| `conhost` | `HKCU\Console`-standaardwaarden + elk bestaand cmd/PowerShell-profiel | yes — exacte snapshot van aangeraakte waarden |
| `obs` | OBS 30.2+-`.ovt`-variant + actieve `user.ini`-thema-id | yes — hij leeft in je profiel |
| `antigravity`, `vscode` | kleurthema-extensie in `~/.antigravity/extensions` / `~/.vscode/extensions` | **yes** — hij leeft in je profiel |
| `freebuff`, `antigravity-app`, `codenomad` | Electron-shim, zie hieronder | no — draai de installer opnieuw |
| `claude` | Electron-shim, ter plaatse gepatcht — zie hieronder | no — een update maakt een nieuwe map `app-<version>` |
| `mpchc` | registry, donker thema + alleen OSD-typografie | no — MPC-HC herschrijft zijn instellingen bij afsluiten |
| `obsidian` | community-thema per vault, alle paletten tegelijk geïnstalleerd | **yes** — hij leeft in je vault |
| `saipenview` | herschrijft zijn eigen `:root`-tokenwaarden in `style.css` | no — een bronbestand; na een pull opnieuw draaien |
| `discord` | CSS in BetterDiscord's eigen themamap geplaatst | yes |
| `totalcmd`, `totalcmd2` | `wincmd.ini`-sleutels `[Colors]`; bestaande recent-file-filters gebruiken de paletlinkkleur | yes — het is jouw ini |
| `smartvac`, `wildrift` | tokenschema herschreven in de eigen bron van de app | no — een bronbestand; na een pull opnieuw draaien |

### FreeBuff-advertentieverwijdering

FreeBuff (de AI-assistent-desktopapp) levert zijn eigen advertentienetwerk: de
renderer-bundel (`resources/orchestrator/ui/assets/index-*.js`) rendert een
`sponsored-ad`-kaart en een thread-banner, en de orchestrator
(`resources/orchestrator/orchestrator.js`) stelt `/api/ad/slot|impression|click`-routes
beschikbaar die de externe advertentieveiling aanroepen. De shim themet de app
alleen; hij raakt die bestanden niet aan.

`desktop/patch-freebuff-ads.js` snijdt de advertenties er op byteniveau uit:

- renderer: de aanroep-plekken van de ad-kaart/banner worden `null`, en de
  API-clientmethoden `adSlot` / `adImpression` / `adClick` worden no-ops — er wordt
  niets gerendert, en er vertrekt nooit een `/api/ad/*`-verzoek uit de renderer;
- orchestrator: alle drie de `/api/ad/*`-routes stoppen met het aanroepen van het
  advertentienetwerk, en het inline-advertentieverzoek bij live beurten
  (`maybeRequestAd`) wordt kortgesloten.

De bundelbestandsnaam bevat een build-hash, dus de patch vindt de huidige bundel
via `index.html` in plaats van een versiegebonden payload mee te leveren — dat is
wat hem updates laat overleven. Originelen worden geback-upt naar
`_orig-backup-<timestamp>/` in de installatiemap; `--revert` herstelt de nieuwste.

**Toekomstige versies worden op twee onafhankelijke lagen afgehandeld:**

1. **Byte-patch met regex-fallbacks.** Elk target heeft een exacte string voor de
   huidige build *en* een fallback op basis van reguliere expressies, verankerd aan
   wat een minifier niet kan hernoemen — de `/api/ad/*`-padliterals, de
   protocol-discriminator `case"ad":`, de klasse `sponsored-ad`, en de
   plaatsingen `variant:"banner"` / `variant:"card"`. De orchestrator is niet
   geminifieerd (leesbare namen zoals `maybeRequestAd` en `app.ads.slotAd`), dus
   zijn exacte strings blijven lang geldig; de renderer-bundel is geminifieerd,
   dus zijn regex-fallbacks nemen het over op het moment dat de volgende build zijn
   identifiers hernoemt.
2. **Blokkade op shim-niveau (`targets/electron/shim.cjs`).** Volledig onafhankelijk
   van de bundel: elke fetch/XHR naar een `/api/ad/`-URL wordt binnen de pagina
   afgewezen, en elk element waarvan de klasse `sponsored-ad` bevat, wordt verborgen
   zodra het verschijnt. Zelfs een gloednieuwe bundel waar dit script nog niets van
   heeft geleerd, kan geen advertentie tonen.

```powershell
node .\desktop\patch-freebuff-ads.js           # patchen (maakt eerst een back-up)
node .\desktop\patch-freebuff-ads.js --sound "C:\...\my.mp3"   # patchen + eigen voltooiingsgeluid (wav/mp3/ogg/flac/m4a/aac)
node .\desktop\patch-freebuff-ads.js --scan    # welke ad-markers draagt DEZE build?
node .\desktop\patch-freebuff-ads.js --verify
node .\desktop\patch-freebuff-ads.js --revert
```

Het draait automatisch als onderdeel van `install.ps1 -Target freebuff`, en moet na
elke FreeBuff-update opnieuw worden uitgevoerd (updates herstellen de standaard-
bestanden). Als een build van vorm verandert, noemt het script het target dat niet
meer matchte — draai `--scan` om te zien wat de nieuwe build nog bevat en verfris
de strings daar.

**FreeBuff-voltooiingsgeluid.** De renderer speelt `chime-<hash>.mp3` af wanneer
een beurt is afgelopen. De patch vindt het op dezelfde manier als hij de bundel
vindt (de naam bevat een build-hash), dus `--sound <file>` installeert je eigen
audio (wav/mp3/ogg/flac/m4a/aac) eroverheen en houdt het standaardbestand aan als
`chime-*.mp3.bak`; `--revert` herstelt het. `--verify` rapporteert welke actief is.

### FreeBuff-geluidsknop (GUI)

`WintageInstaller.ps1` heeft een kleine **FB SOUND**-knop onder de APPLY / REVERT-
stack. Die slaat alleen een *voorkeur* op; `install.ps1 -Target freebuff` leest
hetzelfde bestand en geeft het aan de patch mee als `--sound`, zodat de
advertenties en het geluid in één run worden toegepast:

- **Linkerklik** — kies een audiobestand (OpenFileDialog, wav/mp3/ogg/flac/m4a/aac)
  en hoor het direct afspelen: PCM-WAV via System.Media.SoundPlayer, elk ander
  formaat via een WPF-MediaPlayer (Media Foundation, asynchroon, dus het venster
  bevriest nooit). De keuze wordt onthouden in
  `%APPDATA%\Wintage\freebuff-sound.txt` (per machine, buiten de git-checkout,
  net als de onthouden source-tree-mappen).
- **Rechterklik** — wis de voorkeur terug naar FreeBuff's standaard-chime (stopt
  ook elk voorbeeld dat nog speelt).
- **COPY** — kopieert de gekozen audio de repo zelf in
  (`sounds\freebuff.<ext>`, met behoud van de bron-extensie) en wijst de voorkeur
  opnieuw naar die kopie, zodat het geluid het verwijderen of verplaatsen van het
  originele bestand overleeft. Alleen ingeschakeld terwijl er een eigen geluid is
  ingesteld; opnieuw kopiëren overschrijft de repo-kopie simpelweg. De map
  `sounds/` is gewone, met git te volgen content, dus het committen ervan laat het
  geluid ook her-clones overleven.

Alleen herkende audiocontainers worden voorbeeldafgespeeld — de header wordt eerst
gesnuffeld, dus een niet-audio-keuze wordt aangekondigd in plaats van stilletjes
niets af te spelen.

De knop leest `ON` terwijl er een eigen geluid is ingesteld; hoveren toont het pad.
Pas daarna het `freebuff`-target toe (vink FreeBuff aan + APPLY, of draai
`install.ps1 -Target freebuff` vanuit een terminal) om het in werking te laten
treden.

### Terminals

`terminal` schrijft een `Wintage`-kleurschema in elk gedetecteerd stabiel,
Preview- of niet-verpakt Windows Terminal-instellingenbestand en selecteert het via
`profiles.defaults`, samen met console-veilige Consolas 12 en gealiased tekst. Het
originele bestand wordt er byte voor byte naast bewaard en `-Revert` herstelt het.

`conhost` dekt klassieke `cmd.exe`, Windows PowerShell, Git CMD/Bash-console-
profielen en andere bestaande `HKCU\Console`-kinderen. Het schrijft de volledige
16-kleuren-tabel van het palet naar zowel de root-standaardwaarden als elke
bestaande override, en herstelt daarna alleen de waarden die het heeft aangeraakt.
Het past Consolas daar ook toe, omdat proportionele Verdana botst met het
celraster met vaste breedte dat beide terminal-hosts gebruiken.

### Browsers en Tampermonkey

`browsers` vindt Chrome, Edge, Brave, Cent, Vivaldi en Opera-profielen in
geïnstalleerde locaties en vanuit de draagbare root waarnaar je hem verwijst
(`-PortableRoot`, of de onthouden `portable`-entry in `paths.json`). Zijn status
toont zowel het aantal profielen als hoeveel ervan Tampermonkey bevatten. Apply
kopieert het gekozen browser-chrome-thema naar de stabiele map
`%LOCALAPPDATA%\Wintage\browser-theme`, zet dat pad op het klembord en opent elk
exact profiel op `chrome://extensions` plus de Wintage-userscript
Install/Update-pagina. Profielen zonder Tampermonkey krijgen ook de Chrome
Web Store-pagina te zien.

Chromium verbiedt bewust stille installatie van extensies van buiten de store op een
ongemanaged Windows-machine. De eerste browser-thema-installatie vereist daarom één
**Developer mode → Load unpacked**-bevestiging per profiel. Kies het gekopieerde
pad; daarna blijft Wintage dezelfde stabiele map vervangen wanneer paletten
veranderen. Bevestig ook **Install/Update** in Tampermonkey. Geen enkel browser-
`Preferences`-, Secure Preferences- of Tampermonkey-LevelDB-bestand wordt achter de
browser om bewerkt. Was Tampermonkey niet aanwezig, installeer het dan vanuit het
geopende store-tabblad en ververs het al geopende `wintage.user.js`-tabblad om het
Install-scherm te krijgen.

### Windows

`windows` installeert en activeert direct een content-addressed
`%LOCALAPPDATA%\Microsoft\Windows\Themes\Wintage-<hash>.theme`. Het start vanuit
het actieve thema en vervangt alleen de gedocumenteerde secties voor kleur, cursor
en visuele stijl. Achtergrond, geluiden en desktop-iconen blijven ongewijzigd;
cursors schakelen bewust over op het geïnstalleerde `___CURRENT___`-schema. Het
eerste actieve thema wordt byte voor byte opgeslagen als `Wintage.original.theme`;
paletwijzigingen behouden die basislijn, en `-Revert` activeert hem opnieuw.
Moderne Windows-besturingen komen nog steeds van de ondertekende Aero-visuele stijl
— Wintage wijzigt de ondersteunde donkere modus, het accent en klassieke
systeemkleur-inputs in plaats van beveiligde `.msstyles`-bestanden te vervangen.
Actieve en inactieve titelbalken delen de gedempte verhoogde-oppervlak-kleur van het
palet; de felle highlight blijft gereserveerd voor tekst/selectie-randen. Het
eerdere accent van de inactieve titelbalk wordt apart gesnapshot en door `-Revert`
exact hersteld. De content-hash geeft Windows een nieuw
bestandsassociatie-doel wanneer hetzelfde palet opnieuw wordt gebouwd, dus het
opnieuw toepassen van een bijgewerkt palet wordt niet aangezien voor een no-op; het
verdrongen Wintage-bestand wordt verwijderd nadat Windows bevestigt dat het nieuwe
actief is.

### OBS Studio

`obs` genereert een OBS 30.2+-variant over de onderhouden Yami Classic-basis,
installeert hem in `%APPDATA%\obs-studio\themes` en schrijft zijn stabiele thema-id
naar `user.ini`, zodat het gekozen Wintage-palet bij de volgende start al
geselecteerd is. Sluit OBS vóór Apply of Revert: OBS herschrijft `user.ini` bij
afsluiten. De eerste apply back-upt zowel de vorige selectie als elk thema met
dezelfde naam byte voor byte.

### Electron-apps

`resources/app.asar` wordt verplaatst naar `resources/app/app.asar` (zijn
`app.asar.unpacked`-broer gaat mee — die koppeling is op basis van bestandsnaam,
en het scheiden ervan breekt elke native module), en een kleine `shim.cjs` neemt de
vrijgemaakte `resources/app`-plek in. De shim injecteert de stylesheet en laadt dan
het originele archief. **Geen enkel applicatiebyte wordt herschreven**, alleen
verplaatst; `-Revert` zet hem rechtstreeks terug.

De stylesheet wordt niet voor deze apps geschreven — hij wordt geëxtraheerd uit
`wintage.user.js`, dus elke bevel-, scrollbar- en type-ladder-fix die voor de
browser is gemaakt, landt hier ook, zonder een tweede kopie die kan verrotten.

Twee notities die het waard zijn om vooraf te weten:

- De voor de hand liggende aanpak — `resources/app` naast het archief leggen en
  vertrouwen op Electron die daar de voorkeur aan geeft — **werkt niet en faalt
  stilletjes**. Electron zoekt eerst `app.asar`. De app start perfect en het thema
  wordt nooit uitgevoerd.
- De shim is bewust `.cjs`, niet `.js`. Zijn `package.json` wordt gekopieerd van
  die van de app, zodat de app zijn naam en versie behoudt (de naam bepaalt waar
  userData woont — een shim die die hernoemt, verplaatst de app naar een leeg
  profiel). Staat er `"type": "module"` in dat manifest, dan sterft een `.js`-shim
  bij zijn eerste `require`.

### Claude's desktopapp: ter plaatse, en het frame waarin hij werkelijk tekent

Claude kan de bovenstaande verplaatsing niet gebruiken, omdat `OnlyLoadAppFromAsar`
is gefused: Electron laadt `resources/app.asar` en niets anders, dus een shim in
`resources/app` kan nooit draaien. Hij wordt in plaats daarvan **ter plaatse**
gepatcht: het archief wordt geback-upt, de `main` van zijn `package.json` wordt
herschreven naar `"../wintage-shim.cjs"` (opgevuld tot dezelfde bytelengte, zodat
elke offset in het archief geldig blijft), en de per-bestand-integriteitshash wordt
bijgewerkt zodat die overeenkomt. `-Revert` herstelt de back-up.

De installer leest de fuses nog steeds **voordat hij iets verplaatst** en weigert
met een reden wanneer ze hem blokkeren — `EnableEmbeddedAsarIntegrityValidation`
zou de bovenstaande herschrijving bij het starten laten falen in plaats van bij het
installeren. Controleer elke app zelf:

```powershell
node ..\tools\electron-fuses.js "<path to the app's exe>"
```

De tweede helft hiervan was een veel stiller probleem. Claude's `BrowserWindow`
rendert een dunne schil en de **volledige zichtbare applicatie is een
`WebContentsView`** die eraan is bevestigd. De shim haakte voorheen op
`browser-window-created`, dus injecteerde hij de stylesheet in de schil,
rapporteerde succes naar `wintage-status.txt` en veranderde niets dat je kon zien.
Hij haakt nu op `web-contents-created`, wat vensterinhoud, `WebContentsView`s,
`BrowserView`s, `<webview>`-guests en popups gelijk dekt.

### Obsidian

Een community-thema wordt in elke vault's `.obsidian/themes/` geschreven — alle
zestien paletten tegelijk, precies zoals bij het VS Code-target, dus je schakelt
ertussen in **Settings → Appearance** zonder iets opnieuw te draaien. Het sjabloon
is afgeleid van het handgemaakte `VintageWin95`-thema dat al in de vault zat, elke
kleur vervangen door het token dat eraan gelijk was. `-Palette <slug>` bepaalt
welke bij installatie actief is; `appearance.json` wordt eerst geback-upt, en
`-Revert` verwijdert alleen de `Wintage *`-thema's en herstelt je vorige keuze —
een handgemaakt thema in dezelfde vault wordt nooit aangeraakt.

### SAIPENVIEW

Zijn frontend declareert de Wintage-tokennamen al in zijn eigen `:root`, dus deze
patch herschrijft **alleen de tokenwaarden** — nooit een selector, een font, een
randbreedte of een padding. Niets dat het box-model beïnvloedt verandert, dus de
tekst kan niet verschuiven. Dat is bewust: de eerdere aanpak plakte de volledige
browser-stylesheet er bovenop, en `wintage.css` is geschreven voor willekeurige
webpagina's — universele selectors die het font, de maat-ladder, 2px-randen en
bedieningshoogtes afdwingen. Op een app die al zijn eigen layout heeft, verplaatst
dat alles.

Geverifieerd door elk hex te maskeren en tegen de back-up te diffen: structureel
identiek, alleen kleurliterals verschillen. `--link` wordt gerapporteerd als niet
daar gedeclareerd (zijn markdown-links lezen `--accentTeal`, wat dit wel instelt)
in plaats van geïnjecteerd — een variabele toevoegen die de app nooit leest zou
dood gewicht zijn.

### MPC-HC (K-Lite)

Native Win32, geen stylesheet en geen injectiepunt, en de kleuren van het donkere
thema zijn in het programma gecompileerd — geen registry-waarde stelt ze bloot.
Dus dit target **kan geen palet dragen**. Wat het wel doet: het donkere thema
inschakelen en de UI.md-typografieregels op de OSD toepassen, het enige
oppervlak dat MPC-HC een gebruiker laat bedienen. De vorige instellingen worden
eerst geëxporteerd naar `desktop/backup/mpc-hc-settings.reg`.

Sluit MPC-HC vóór het toepassen: hij herschrijft zijn instellingen bij afsluiten.

## Opnieuw bouwen

Alles onder `desktop/out/` wordt gegenereerd uit `themes/*.json`. Het wordt niet
bijgehouden in git (T-160), dus een verse clone moet het eenmalig bouwen vóór het
installeren:

```powershell
node ..\tools\build-desktop.js          # alle targets opnieuw bouwen
node ..\tools\build-desktop.js --check  # exit 1 als iets stale is
```

`release.ps1` draait de build en elke gate, dus een release kan geen output
verzenden die van de paletten is afgedwaald.

<!-- source-digest: desktop/README.md sha256:1b166ae6a7cf8a5c -->
