# Wintage for skrivebordsapplikasjoner

Userscriptet temasetter nettet. Dette temasetter programmene rundt det, fra de samme palettene, slik at nettleseren og appene slutter å være uenige om hva mørkt gull betyr.

Det er én regel bak hver beslutning her: **applikasjoner oppdaterer seg selv, og en oppdatering må ikke stille bryte noe.** Der et mål har en plass i din egen profil, går temaet dit og overlever oppdateringer. Der det ikke har det, er installatøren skrevet for å kjøres på nytt — og sier ifra, i stedet for å late som om det vedvarte.

## GUI-en

Dobbeltklikk **`Wintage Installer.vbs`** i repo-roten for å åpne den uten konsollvindu, eller kjør dette direkte for diagnostikk:

```powershell
powershell -File desktop\WintageInstaller.ps1
```

Temaliste med fargebrikker, målene som er funnet på denne maskinen, en live Win95-forhåndsvisning og alle tjueen fargetokener som redigerbare swatches. Å redigere en swatch gafler paletten til **Custom** i stedet for å endre et utlevert tema under deg. Panelet til høyre viser live WCAG-kontrast for de tre tokenene som bærer tekst — en palett som feiler der blir uansett avvist av byggeporten, så det er bedre å se det før Apply enn etter.

Målene er delt i to lister som nås med tastatur: **MY APPS** inneholder de bærbare/kilde-tre-verktøyene CodeNomad, SAIPENVIEW, SmartVac og WildRift; **POPULAR APPS** inneholder Windows, OBS, terminaler, editorer og den andre installerte programvaren. ALL/NONE og Apply/Revert virker på begge listene uten å endre grupperingen.

Vinduet bærer paletten den er i ferd med å installere. Det er den raskeste forhåndsvisningen som finnes, og det holder verktøyet ærlig: en palett som gjør dette vinduet uleselig, er synlig uleselig.

Apply delegerer til `install.ps1`. Det er nøyaktig én kodebane som installerer et tema, så GUI-en kan ikke drive bort fra kommandolinjen.

## Kommandolinjen

```powershell
.\desktop\install.ps1                                  # hva er her, hva er tematisert, med hvilken palett
.\desktop\install.ps1 -Target freebuff -Palette klite  # én app, én palett
.\desktop\install.ps1 -Target all -Palette goldendefault # alt
.\desktop\install.ps1 -Target all -WhatIf              # si hva som ville endret seg, ikke rør noe
.\desktop\install.ps1 -Target freebuff -Revert         # angre én
```

`-Palette` er som standard `goldendefault` (**Golden Default**). GUI-en åpner på samme palett og sjekker alle tilgjengelige mål. Å male om en app som allerede er tematisert, fungerer mens den kjører; en første installasjon gjør ikke det, fordi arkivet er i bruk.

## Hva hvert mål faktisk kan tematiseres

| mål | mekanisme | overlever en app-oppdatering |
|---|---|---|
| `windows` | bruker-`.theme`: mørk system/app-modus, aksent og klassiske fargeroller | ja — installert i din lokale Windows Themes-mappe |
| `browsers` | oppdager installerte + bærbare Chromium-profiler, legger til rette for det valgte chrome-temaet og åpner nettleserens egne Tampermonkey-/temabekreftelsessider | ja etter én **Load unpacked** per profil |
| `terminal` | Windows Terminal-skjema + standarder for alle profiler, Consolas 12 med alias | ja — innstillingene ligger i profilen din |
| `conhost` | `HKCU\Console`-standarder + alle eksisterende cmd/PowerShell-profiler | ja — nøyaktig øyeblikksbilde av berørte verdier |
| `obs` | OBS 30.2+ `.ovt`-variant + aktiv `user.ini`-tema-ID | ja — det ligger i profilen din |
| `antigravity`, `vscode` | fargetema-utvidelse i `~/.antigravity/extensions` / `~/.vscode/extensions` | **ja** — det ligger i profilen din |
| `freebuff`, `antigravity-app`, `codenomad` | Electron-shim, se nedenfor | nei — kjør installatøren på nytt |
| `claude` | Electron-shim, patchet på plass — se nedenfor | nei — en oppdatering lager en ny `app-<versjon>`-mappe |
| `mpchc` | register, mørkt tema + OSD-typografi kun | nei — MPC-HC skriver om innstillingene sine ved avslutning |
| `obsidian` | fellesskapstema per hvelv, alle paletter installert samtidig | **ja** — det ligger i hvelvet ditt |
| `saipenview` | skriver om sine egne `:root`-tokenverdier i `style.css` | nei — en kildefil; kjør på nytt etter en pull |
| `discord` | CSS sluppet inn i BetterDiscords egen temamappe | ja |
| `totalcmd`, `totalcmd2` | `wincmd.ini` `[Colors]`-nøkler; eksisterende nylige-fil-filtre bruker palettens lenkefarge | ja — det er din ini |
| `smartvac`, `wildrift` | token-tabellen skrevet om i appens egen kilde | nei — en kildefil; kjør på nytt etter en pull |

### FreeBuff-annonsefjerning

FreeBuff (AI-assistent-skrivebordsappen) leverer sitt eget annonsenettverk: renderer-bundlen (`resources/orchestrator/ui/assets/index-*.js`) gjengir et `sponsored-ad`-kort og en trådbanner, og orkestratoren (`resources/orchestrator/orchestrator.js`) eksponerer `/api/ad/slot|impression|click`-ruter som kaller den eksterne annonseauksjonen. Shim-en tematiserer bare appen; den rører ikke disse filene.

`desktop/patch-freebuff-ads.js` kutter ut annonsene på bytenivå:

- renderer: annonsekort-/banner-kallepunktene blir `null`, og API-klientmetodene `adSlot` / `adImpression` / `adClick` blir no-ops — ingenting gjengis, og ingen `/api/ad/*`-forespørsel forlater rendereren;
- orkestrator: alle tre `/api/ad/*`-rutene slutter å kalle annonsenettverket, og den innebygde annonseforespørselen for levende tur (`maybeRequestAd`) kortsluttes.

Bundlenavnet inneholder en bygge-hash, så patchen finner den gjeldende bundlen fra `index.html` i stedet for å levere en versjonslåst nyttelast — det er det som gjør at den overlever oppdateringer. Originalene sikkerhetskopieres til `_orig-backup-<tidsstempel>/` i installasjonsmappen; `--revert` gjenoppretter den nyeste.

**Fremtidige versjoner håndteres på to uavhengige nivåer:**

1. **Byte-patch med regex-fallback.** Hvert mål har en eksakt streng for gjeldende bygg *og* en regex-fallback forankret i det en minifiserer ikke kan gi nytt navn — `/api/ad/*`-stilene, `case"ad":`-protokoll-diskriminatoren, `sponsored-ad`-klassen og `variant:"banner"` / `variant:"card"`-plasseringene. Orkestratoren er ikke minifisert (lesbare navn som `maybeRequestAd` og `app.ads.slotAd`), så de eksakte strengene holder lenge; renderer-bundlen er minifisert, så regex-fallbackene tar over i det neste bygget gir identifikatorene nye navn.
2. **Blokkering på shim-nivå (`targets/electron/shim.cjs`).** Helt uavhengig av bundlen: enhver fetch/XHR til en `/api/ad/`-URL avvises inne på siden, og ethvert element hvis klasse inneholder `sponsored-ad` skjules i det det dukker opp. Selv en helt ny bundle som dette scriptet ennå ikke har lært, kan ikke vise en annonse.

```powershell
node .\desktop\patch-freebuff-ads.js           # patch (sikkerhetskopierer først)
node .\desktop\patch-freebuff-ads.js --sound "C:\...\my.mp3"   # patch + tilpasset fullføringslyd (wav/mp3/ogg/flac/m4a/aac)
node .\desktop\patch-freebuff-ads.js --scan    # hvilke annonsemarkører bærer DETTE bygget?
node .\desktop\patch-freebuff-ads.js --verify
node .\desktop\patch-freebuff-ads.js --revert
```

Det kjører automatisk som en del av `install.ps1 -Target freebuff`, og må kjøres på nytt etter hver FreeBuff-oppdatering (oppdateringer gjenoppretter standardfilene). Hvis et bygg endrer form, navngir scriptet målet som ikke lenger matchet — kjør `--scan` for å se hva det nye bygget fortsatt bærer, og oppdater strengene der.

**FreeBuff-fullføringslyd.** Rendereren spiller `chime-<hash>.mp3` når en tur er ferdig. Patchen finner den på samme måte som den finner bundlen (navnet inneholder en bygge-hash), så `--sound <fil>` installerer din egen lyd (wav/mp3/ogg/flac/m4a/aac) over den og beholder standardfilen som `chime-*.mp3.bak`; `--revert` gjenoppretter den. `--verify` rapporterer hvilken som er aktiv.

### FreeBuff-lydknapp (GUI)

`WintageInstaller.ps1` har en liten **FB SOUND**-knapp under APPLY / REVERT-stabelen. Den lagrer bare en *preferanse*; `install.ps1 -Target freebuff` leser samme fil og gir den til patchen som `--sound`, så annonsene og lyden brukes i én kjøring:

- **Venstreklikk** — velg en lydfil (OpenFileDialog, wav/mp3/ogg/flac/m4a/aac) og hør den spilles av umiddelbart: PCM WAV via System.Media.SoundPlayer, alle andre formater via en WPF MediaPlayer (Media Foundation, asynkron, så vinduet aldri fryser). Valget huskes i `%APPDATA%\Wintage\freebuff-sound.txt` (per maskin, utenfor git-sjekkouten, akkurat som de huskede kilde-tre-mappene).
- **Høyreklikk** — tilbakestill preferansen til FreeBuff-standardlyden (stopper også en forhåndsvisning som fortsatt spiller).
- **COPY** — kopierer den valgte lyden inn i selve repoet (`sounds\freebuff.<ext>`, behold kilde-utvidelsen) og peker preferansen på den kopien, så lyden overlever at originalfilen slettes eller flyttes. Aktivert bare mens en tilpasset lyd er satt; å kopiere på nytt overskriver bare repo-kopien. `sounds/`-mappen er vanlig git-sporbart innhold, så å committe den gjør at lyden overlever også re-kloner.

Bare gjenkjente lydcontainere forhåndsvises — overskriften snuses først, så et ikke-lydvalg annonseres i stedet for stille å spille ingenting.

Knappen viser `ON` mens en tilpasset lyd er satt; å holde musepekeren over viser banen. Bruk `freebuff`-målet etterpå (huk av FreeBuff + APPLY, eller kjør `install.ps1 -Target freebuff` fra en terminal) for at det skal tre i kraft.

### Terminaler

`terminal` skriver et `Wintage`-fargeskjema inn i hver oppdagede stabile, Preview- eller uemballerte Windows Terminal-innstillingsfil og velger det via `profiles.defaults`, sammen med konsolltrygg Consolas 12 og aliasert tekst. Den originale filen beholdes byte-for-byte ved siden av, og `-Revert` gjenoppretter den.

`conhost` dekker klassisk `cmd.exe`, Windows PowerShell, Git CMD/Bash-konsollprofiler og andre eksisterende `HKCU\Console`-barn. Den skriver palettens fulle 16-fargetabell både til rotstandardene og til hvert eksisterende overstyr, og gjenoppretter deretter bare verdiene den rørte. Den bruker Consolas også der, fordi proporsjonal Verdana kolliderer innenfor det faste celle-rutenettet som begge terminalverter bruker.

### Nettlesere og Tampermonkey

`browsers` finner Chrome-, Edge-, Brave-, Cent-, Vivaldi- og Opera-profiler fra installerte plasseringer og fra den bærbare roten du peker den mot (`-PortableRoot`, eller den huskede `portable`-oppføringen i `paths.json`). Statusen viser både antall profiler og hvor mange som inneholder Tampermonkey. Apply kopierer det valgte nettleser-chrome-temaet til den stabile `%LOCALAPPDATA%\Wintage\browser-theme`-mappen, legger den banen på utklippstavlen og åpner hver eksakte profil på `chrome://extensions` pluss Wintage-userscriptets Install/Update-side. Profiler uten Tampermonkey får også Chrome Web Store-siden.

Chromium forbyr bevisst stille installasjon av utvidelser utenfor butikken på en uadministrert Windows-maskin. Den første nettlesertemainstallasjonen trenger derfor én **Developer mode → Load unpacked**-bekreftelse per profil. Velg den kopierte banen; etter det fortsetter Wintage å erstatte den samme stabile mappen når paletter endres. Bekreft også **Install/Update** i Tampermonkey. Ingen nettleser-`Preferences`, Secure Preferences eller Tampermonkey-LevelDB-fil redigeres bak ryggen på nettleseren. Hvis Tampermonkey ikke var til stede, installer den fra den åpnede butikkfanen og oppdater den allerede åpne `wintage.user.js`-fanen for å få Install-skjermen.

### Windows

`windows` installerer og aktiverer umiddelbart et innholdsadressert `%LOCALAPPDATA%\Microsoft\Windows\Themes\Wintage-<hash>.theme`. Det starter fra det aktive temaet og erstatter bare de dokumenterte farge-, markør- og visuell-stil-seksjonene. Bakgrunnsbilde, lyder og skrivebordsikoner forblir uendret; markører bytter bevisst til det installerte `___CURRENT___`-skjemaet. Det første aktive temaet lagres byte-for-byte som `Wintage.original.theme`; palettendringer beholder den grunnlinjen, og `-Revert` aktiverer den igjen. Moderne Windows-kontroller kommer fortsatt fra den signerte Aero-visuelle stilen — Wintage endrer dens støttede mørke modus, aksent og klassiske systemfarge-inndata i stedet for å erstatte beskyttede `.msstyles`-filer. Aktive og inaktive titler deler palettens dempede hevede overflatefarge; den lyse markeringen forblir reservert for tekst-/utvalgskanter. Den forrige inaktive tittel-aksenten øyeblikksbildes separat og gjenopprettes nøyaktig av `-Revert`. Innholdshashen gir Windows et nytt filassosiasjonsmål når den samme paletten bygges om, så å bruke en oppdatert palett på nytt ikke forveksles med en no-op; den overstyrte Wintage-filen fjernes etter at Windows bekrefter at den nye er aktiv.

### OBS Studio

`obs` genererer en OBS 30.2+-variant over den vedlikeholdte Yami Classic-basen, installerer den i `%APPDATA%\obs-studio\themes` og skriver den stabile tema-ID-en til `user.ini`, så den valgte Wintage-paletten allerede er valgt ved neste oppstart. Lukk OBS før Apply eller Revert: OBS skriver om `user.ini` ved avslutning. Første bruk sikkerhetskopierer både det forrige valget og ethvert tema med samme navn byte-for-byte.

### Electron-apper

`resources/app.asar` flyttes til `resources/app/app.asar` (søskenet `app.asar.unpacked` flytter med — den paringen er etter filnavn, og å skille dem bryter hver nativ modul), og en liten `shim.cjs` tar den frigjorte `resources/app`-plassen. Shim-en injiserer stilarket og laster deretter det originale arkivet. **Ingen app-byte skrives om**, bare flyttes; `-Revert` flytter den rett tilbake.

Stilarket skrives ikke for disse appene — det trekkes ut av `wintage.user.js`, så hver fas-, scrollbar- og typestige-fiks laget for nettleseren havner også her, uten en andre kopi å råtne.

To notater verdt å ha på forhånd:

- Den åpenbare tilnærmingen — å slippe `resources/app` ved siden av arkivet og stole på at Electron foretrekker det — **virker ikke og feiler stille**. Electron søker etter `app.asar` først. Appen starter perfekt, og temaet kjører aldri.
- Shim-en er `.cjs`, ikke `.js`, med vilje. Dens `package.json` kopieres fra appens egen, så appen beholder navn og versjon (navnet avgjør hvor userData bor — en shim som gir det nytt navn, flytter appen til en tom profil). Hvis manifestet sier `"type": "module"`, dør en `.js`-shim på sin første `require`.

### Claude-skrivebordsappen: på plass, og rammen den faktisk tegner i

Claude kan ikke bruke flyttingen ovenfor, fordi `OnlyLoadAppFromAsar` er smeltet på — Electron laster `resources/app.asar` og ingenting annet, så en shim i `resources/app` kan aldri kjøre. Den patche i stedet **på plass**: arkivet sikkerhetskopieres, `main` i `package.json` skrives om til `"../wintage-shim.cjs"` (paddet til samme bytelengde, så hver offset i arkivet forblir gyldig), og per-fil-integritetshashen oppdateres til å matche. `-Revert` gjenoppretter sikkerhetskopien.

Installatøren leser fortsatt fuses **før den flytter noe** og nekter med en grunn når de blokkerer — `EnableEmbeddedAsarIntegrityValidation` ville få omskrivingen ovenfor til å feile ved oppstart i stedet for ved installasjon. Sjekk hvilken som helst app selv:

```powershell
node ..\tools\electron-fuses.js "<bane til appens exe>"
```

Den andre halvdelen av dette var et mye stillere problem. Claudes `BrowserWindow` gjengir et tynt skall, og **hele den synlige applikasjonen er en `WebContentsView`** festet til det. Shim-en pleide å koble på `browser-window-created`, så den injiserte stilarket inn i skallet, rapporterte suksess til `wintage-status.txt` og endret ikke noe du kunne se. Den kobler på `web-contents-created` nå, som dekker vindusinnhold, `WebContentsView`-er, `BrowserView`-er, `<webview>`-gjester og popup-vinduer likt.

### Obsidian

Et fellesskapstema skrives inn i hvert hvelvs `.obsidian/themes/` — alle seksten paletter samtidig, nøyaktig som VS Code-målet, så du bytter mellom dem i **Settings → Appearance** uten å kjøre noe på nytt. Malen ble utledet fra det håndlagde `VintageWin95`-temaet som allerede var i hvelvet, hver farge erstattet av tokenet den tilsvarte. `-Palette <slug>` setter hvilken som er aktiv ved installasjon; `appearance.json` sikkerhetskopieres først, og `-Revert` fjerner bare `Wintage *`-temaene og gjenoppretter ditt forrige valg — et håndlaget tema i samme hvelv røres aldri.

### SAIPENVIEW

Frontenden erklærer allerede Wintage-tokennavnene i sin egen `:root`, så denne patchen skriver om **bare tokenverdiene** — aldri en selektor, en font, en bordbredde eller en padding. Ingenting som påvirker boksen modell endres, så teksten kan ikke flytte seg. Det er bevisst: den tidligere tilnærmingen la hele nettleserens stilark oppå, og `wintage.css` er skrevet for vilkårlige nettsider — universelle selektorer som tvinger font, størrelsesstige, 2px-border og kontrollhøyder. På en app som allerede har sitt eget oppsett, flytter det alt.

Verifisert ved å maske hver hex og diff mot sikkerhetskopien: strukturelt identisk, bare fargeliteraler skiller seg. `--link` rapporteres som ikke deklarert der (markdown-lenkene leser `--accentTeal`, som dette setter) i stedet for injisert — å legge til en variabel appen aldri leser, ville vært dødvekt.

### MPC-HC (K-Lite)

Nativ Win32, uten stilark og uten injeksjonspunkt, og fargene i det mørke temaet er kompilert inn i programmet — ingen registerverdi eksponerer dem. Så dette målet **kan ikke bære en palett**. Hva det gjør: slår på det mørke temaet og bruker UI.md-typografireglene på OSD, som er den ene overflaten MPC-HC lar en bruker kontrollere. De forrige innstillingene eksporteres til `desktop/backup/mpc-hc-settings.reg` først.

Lukk MPC-HC før du bruker: det skriver om innstillingene sine ved avslutning.

## Gjenoppbygging

Alt under `desktop/out/` genereres fra `themes/*.json`. Det spores ikke i git (T-160), så en fersk klon må bygge det én gang før installasjon:

```powershell
node ..\tools\build-desktop.js          # bygg om alle mål
node ..\tools\build-desktop.js --check  # avslutt 1 hvis noe er utdatert
```

`release.ps1` kjører bygget og hver port, så en utgivelse kan ikke sende utdata som har drevet bort fra palettene.

<!-- source-digest: desktop/README.md sha256:1b166ae6a7cf8a5c -->
