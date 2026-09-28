# Wintage til skrivebordsprogrammer

Userscriptet temaer nettet. Dette temaer de programmer, der omgiver det, fra de
samme paletter, så browseren og appene holder op med at være uenige om, hvad
mørkt gyldent betyder.

Der er én regel bag enhver beslutning her: **programmer opdaterer sig selv, og en
opdatering må ikke stille og roligt ødelægge noget.** Hvor et mål har en plads i
din egen profil, kommer temaet derhen og overlever opdateringer. Hvor det ikke
har, er installatøren skrevet til at kunne køres igen — og siger det, i stedet
for at lade som om, det er gemt permanent.

## GUI'en

Dobbeltklik på **`Wintage Installer.vbs`** i repoets rod for at åbne den uden et
konsolvindue, eller kør dette direkte til fejlfinding:

```powershell
powershell -File desktop\WintageInstaller.ps1
```

Temaliste med farvechips, de mål, der findes på denne maskine, en live Win95
forhåndsvisning og alle enogtyve farvetokens som redigerbare farvefelter. Redigering af
et hvilket som helst farvefelt gaffer paletten ud i **Custom** i stedet for at ændre et
medfølgende tema hen over hovedet på dig. Panelet til højre viser live WCAG-kontrast
for de tre tokens, der bærer tekst — en palet, der FEJLER der, afvises af
byggeporten alligevel, så det er bedre at se det, før man anvender, end efter.

Målene er delt op i to lister, der kan nås fra tastaturet: **MY APPS** indeholder
de bærbare/kildetræsbaserede CodeNomad, WorkBuddy-værktøjer;
**POPULAR APPS** indeholder Windows, OBS, terminaler, editorer og den anden installerede
software. ALL/NONE og Apply/Revert virker på tværs af begge lister uden at ændre deres
gruppering.

Vinduet bærer den palet, som det er ved at installere. Det er den hurtigste
forhåndsvisning, der findes, og det holder værktøjet ærligt: en palet, der gør dette
vindue ulæseligt, er synligt ulæseligt.

Apply kalder videre til `install.ps1`. Der er præcis én kodevej, der installerer et
tema, så GUI'en ikke kan drive væk fra kommandolinjen.

## Kommandolinjen

```powershell
.\desktop\install.ps1                                  # hvad er her, hvad er tematiseret, med hvilken palet
.\desktop\install.ps1 -Target freebuff -Palette klite  # én app, én palet
.\desktop\install.ps1 -Target all -Palette goldendefault # alting
.\desktop\install.ps1 -Target all -WhatIf              # sig, hvad der ville ændre sig, rør intet
.\desktop\install.ps1 -Target freebuff -Revert         # fortryd en enkelt
```

`-Palette` er som standard `goldendefault` (**Golden Default**). GUI'en åbner på den
samme palet og tjekker alle tilgængelige mål. Genmaling af en app, der allerede er
tematiseret, virker, mens den kører; en første installation gør det ikke, fordi
arkivet er i brug.

## Hvad hvert mål faktisk kan tematiseres til

| target | mekanisme | overlever en app-opdatering |
|---|---|---|
| `windows` | bruger-`.theme`: mørk system-/app-tilstand, accent- og klassiske farveroller | yes — installeret i din lokale Windows Temas-mappe |
| `browsers` | registrerer installerede + bærbare Chromium-profiler, stiller det valgte chrome-tema op og åbner browserens egne Tampermonkey/tema-bekræftelsessider | yes efter én **Load unpacked** pr. profil |
| `terminal` | Windows Terminal-skema + standarder for alle profiler, Consolas 12 aliaseret | yes — indstillingerne ligger i din profil |
| `conhost` | `HKCU\Console`-standarder + enhver eksisterende cmd/PowerShell-profil | yes — eksakt snapshot af berørte værdier |
| `obs` | OBS 30.2+ `.ovt`-variant + aktiv `user.ini`-tema-ID | ja — det ligger i din profil |
| `antigravity`, `vscode` | farvetema-udvidelse i `~/.antigravity/extensions` / `~/.vscode/extensions` | **yes** — det ligger i din profil |
| `freebuff`, `antigravity-app`, `codenomad` | Electron-shim, se nedenfor | no — kør installatøren igen |
| `claude` | Electron-shim, patch'et på stedet — se nedenfor | no — en opdatering laver en ny `app-<version>`-mappe |
| `mpchc` | registreringsdatabasen, kun mørkt tema + OSD-typografi | no — MPC-HC omskriver sine indstillinger ved afslutning |
| `obsidian` | community-tema pr. vault, alle paletter installeret på én gang | **yes** — det ligger i din vault |
| `discord` | CSS lagt i BetterDiscords egen temamappe | yes |
| `totalcmd`, `totalcmd2` | `wincmd.ini` `[Colors]`-nøgler; eksisterende seneste-fil-filtre bruger palettens linkfarve | yes — det er din ini |

### FreeBuff-annoncefjernelse

FreeBuff (AI-assistentens skrivebordsapp) leverer sit eget annoncenetværk:
renderer-bundlen (`resources/orchestrator/ui/assets/index-*.js`) viser et
`sponsored-ad`-kort og et trådbanner, og orkestratoren (`resources/orchestrator/orchestrator.js`)
eksponerer `/api/ad/slot|impression|click`-ruter, der kalder den eksterne
annonceauktion. Shimen temaer kun appen; den rører ikke ved disse filer.

`desktop/patch-freebuff-ads.js` skærer annoncerne ud på byte-niveau:

- renderer: annoncekortets/-bannerets kaldesteder bliver til `null`, og `adSlot` /
  `adImpression` / `adClick`-API-klientmetoderne bliver til no-ops — intet gengives,
  og ingen `/api/ad/*`-forespørgsel forlader nogensinde rendereren;
- orkestrator: alle tre `/api/ad/*`-ruter holder op med at kalde annoncenetværket, og
  live-turn-inline-annonceforespørgslen (`maybeRequestAd`) kortsluttes.

Bundle-filnavnet indeholder en bygge-hash, så patchen finder den aktuelle
bundle fra `index.html` i stedet for at levere en versionslåst nyttelast — det er
det, der får den til at overleve opdateringer. Originalerne sikkerhedskopieres til
`_orig-backup-<timestamp>/` i installationsmappen; `--revert` gendanner den nyeste.

**Fremtidige versioner håndteres på to uafhængige lag:**

1. **Byte-patch med regex-fallback.** Hvert mål har en eksakt streng for den
   aktuelle bygning *og* en regular-expression-fallback, der er forankret i det, en
   minifier ikke kan omdøbe — `/api/ad/*`-stilitteralerne, `case"ad":`-protokol-
   diskriminatoren, `sponsored-ad`-klassen og `variant:"banner"` /
   `variant:"card"`-placeringerne. Orkestratoren er ikke minificeret (læsbare navne
   som `maybeRequestAd` og `app.ads.slotAd`), så dens eksakte strenge holder længe;
   renderer-bundlen er minificeret, så dens regex-fallback overtager, det øjeblik
   den næste bygning omdøber sine identifikatorer.
2. **Blokering på shim-niveau (`targets/electron/shim.cjs`).** Uafhængig af bundlen
   helt og holdent: enhver fetch/XHR til en `/api/ad/`-URL afvises inde på siden, og
   ethvert element, hvis klasse indeholder `sponsored-ad`, skjules, det øjeblik det
   vises. Selv en helt ny bundle, som dette script endnu ikke har lært, kan ikke
   vise en annonce.

```powershell
node .\desktop\patch-freebuff-ads.js           # patch (sikkerhedskopierer først)
node .\desktop\patch-freebuff-ads.js --sound "C:\...\my.mp3"   # patch + brugerdefineret færdiglyd (wav/mp3/ogg/flac/m4a/aac)
node .\desktop\patch-freebuff-ads.js --scan    # hvilke annoncemarkører bærer DENNE bygning?
node .\desktop\patch-freebuff-ads.js --verify
node .\desktop\patch-freebuff-ads.js --revert
```

Det kører automatisk som en del af `install.ps1 -Target freebuff`, og det skal
køres igen efter hver FreeBuff-opdatering (opdateringer gendanner standardfilene).
Hvis en bygning ændrer form, navngiver scriptet det mål, der ikke længere matchede —
kør `--scan` for at se, hvad den nye bygning stadig bærer, og opfrisk strengene der.

**FreeBuff-færdiglyd.** Rendereren afspiller `chime-<hash>.mp3`, når en tur
er færdig. Patchen finder den på samme måde, som den finder bundlen (navnet indeholder en
bygge-hash), så `--sound <file>` installerer din egen lyd (wav/mp3/ogg/flac/m4a/
aac) henover den og beholder standardfilen som `chime-*.mp3.bak`; `--revert` gendanner
den. `--verify` rapporterer, hvilken der er live.

### FreeBuff-lydknap (GUI)

`WintageInstaller.ps1` har en lille **FB SOUND**-knap under APPLY / REVERT-
stakken. Den gemmer kun en *præference*; `install.ps1 -Target freebuff` læser den
samme fil og rækker den til patchen som `--sound`, så annoncerne og lyden
anvendes i ét kørsel:

- **Venstre-klik** — vælg en lydfil (OpenFileDialog, wav/mp3/ogg/flac/m4a/aac)
  og hør den afspillet med det samme: PCM WAV gennem System.Media.SoundPlayer,
  alle andre formater gennem en WPF MediaPlayer (Media Foundation, asynkron, så
  vinduet aldrig fryser). Valget huskes i
  `%APPDATA%\Wintage\freebuff-sound.txt` (pr. maskine, uden for git-checkout'et,
  præcis som de huskede kildetræsmapper).
- **Højre-klik** — ryd præferencen tilbage til FreeBuffs standard-chime (stopper
  også enhver preview, der stadig afspiller).
- **COPY** — kopierer den valgte lyd ind i selve repoet
  (`sounds\freebuff.<ext>`, med kildeudvidelsen bevaret) og peger
  præferencen om på den kopi, så lyden overlever, at den oprindelige fil bliver
  slettet eller flyttet. Kun aktiveret, mens en brugerdefineret lyd er sat;
  genkopiering overskriver simpelthen repo-kopien. `sounds/`-mappen er almindeligt
  git-sporbart indhold, så hvis man committer den, overlever lyden også re-kloner.

Kun genkendte lydcontainere forhåndsvises — headeren snuses først, så et
ikke-lydvalg meldes ud i stedet for lydløst at afspille ingenting.

Knappen læser `ON`, mens en brugerdefineret lyd er sat; svævning over den viser
stien. Anvend derefter `freebuff`-målet (sæt flueben i FreeBuff + APPLY, eller kør
`install.ps1 -Target freebuff` fra en terminal), for at det træder i kraft.

### Terminaler

`terminal` skriver et `Wintage`-farveskema ind i enhver registreret stabil-, Preview-,
eller upakket Windows Terminal-indstillingsfil og vælger det via
`profiles.defaults`, sammen med konsolsikker Consolas 12 og aliaseret tekst. Den oprindelige fil
bevares byte-for-byte ved siden af, og `-Revert` gendanner den.

`conhost` dækker klassiske `cmd.exe`, Windows PowerShell, Git CMD/Bash-konsol-
profiler og andre eksisterende `HKCU\Console`-børn. Den skriver palettens fulde
16-farve-tabel til både rod-standarderne og enhver eksisterende override, og gendanner derefter
kun de værdier, den rørte. Den anvender også Consolas der, fordi proportionale
Verdana kolliderer inde i det fast-bredde celleret, som begge terminal-hosts bruger.

### Browsere og Tampermonkey

`browsers` finder Chrome-, Edge-, Brave-, Cent-, Vivaldi- og Opera-profiler fra
installerede placeringer og fra den bærbare rod, du peger den på (`-PortableRoot`, eller
den huskede `portable`-post i `paths.json`). Dens status
viser både profilantallet og, hvor mange der indeholder Tampermonkey. Apply kopierer det valgte
browser-chrome-tema til den stabile
`%LOCALAPPDATA%\Wintage\browser-theme`-mappe, lægger stien på udklipsholderen,
og åbner hver enkelt profil ved `chrome://extensions` plus Wintage-userscriptets
Install/Update-side. Profiler uden Tampermonkey får også dens Chrome Web Store-
side.

Chromium forbyder bevidst tavs off-store-udvidelsesinstallation på en
uadministreret Windows-maskine. Den første browser-tema-installation kræver derfor én
**Developer mode → Load unpacked**-bekræftelse pr. profil. Vælg den kopierede sti;
derefter bliver Wintage ved med at erstatte den samme stabile mappe, når paletter skifter.
Bekræft også **Install/Update** i Tampermonkey. Ingen browser-`Preferences`, Secure
Preferences- eller Tampermonkey-LevelDB-fil redigeres bag om ryggen på browseren.
Hvis Tampermonkey ikke var til stede, så installer det fra den åbnede store-fane og opfrisk
den allerede åbne `wintage.user.js`-fane for at få Install-skærmen.

### Windows

`windows` installerer og aktiverer straks et content-adresseret
`%LOCALAPPDATA%\Microsoft\Windows\Themes\Wintage-<hash>.theme`.
Det starter fra det aktive tema og erstatter kun de dokumenterede farve-, markør- og
visuel-stil-sektioner. Baggrund, lyde og skrivebordsikoner forbliver uændrede; markører
skifter med vilje til det installerede `___CURRENT___`-skema. Det første aktive tema
gemmes byte-for-byte som `Wintage.original.theme`; paletændringer bevarer den baseline,
og `-Revert` aktiverer den igen. Moderne Windows-kontroller kommer stadig
fra den signerede Aero-visuelle stil — Wintage ændrer dens understøttede mørke tilstand, accent,
og klassiske system-farveinput i stedet for at erstatte beskyttede `.msstyles`-filer.
Aktive og inaktive titellinjer deler palettens dæmpede hævede-overfladefarve; den
lyse highlight forbliver reserveret til tekst-/markeringskanter. Den tidligere inaktive
titelbar-accent snapshot'ees separat og gendannes eksakt af `-Revert`.
Content-hashen giver Windows et nyt filassocieringsmål, når den samme palet
genopbygges, så genanvendelse af en opdateret palet ikke forveksles med en no-op; den
overflødiggjorte Wintage-fil fjernes, efter Windows bekræfter, at den nye er aktiv.

### OBS Studio

`obs` genererer en OBS 30.2+-variant over den vedligeholdte Yami Classic-base,
installerer den i `%APPDATA%\obs-studio\themes`, og skriver dens stabile tema-ID til
`user.ini`, så den valgte Wintage-palet allerede er valgt ved næste opstart.
Luk OBS før Apply eller Revert: OBS omskriver `user.ini` ved afslutning. Første anvendelse
sikkerhedskopierer både det tidligere valg og ethvert tema med samme navn byte-for-byte.

### Electron-apps

`resources/app.asar` flyttes til `resources/app/app.asar` (dets `app.asar.unpacked`-
søskendefil flytter med — den parring er efter filnavn, og at adskille den ødelægger enhver
indbygget modul), og en lille `shim.cjs` tager den forladte `resources/app`-plads. Shimen
injektérer stylesheet'et og loader derefter det originale arkiv. **Ingen app-
byte omskrives**, kun flyttes; `-Revert` flytter den lige tilbage.

Stylesheet'et er ikke skrevet til disse apps — det udpakkes fra
`wintage.user.js`, så enhver bevel-, scrollbar- og type-ladder-fiks lavet til
browseren lander også her, uden en anden kopi til at rådne.

To noter, der er værd at have på forhånd:

- Den oplagte tilgang — at lægge `resources/app` ved siden af arkivet og stole på,
  at Electron foretrækker det — **virker ikke og fejler lydløst**. Electron
  søger efter `app.asar` først. Appen starter perfekt, og temaet kører aldrig.
- Shimen er `.cjs`, ikke `.js`, med vilje. Dens `package.json` kopieres fra appens
  egen, så appen beholder sit navn og sin version (navnet afgør, hvor userData
  bor — en shim, der omdøber den, flytter appen til en tom profil). Hvis det manifest
  siger `"type": "module"`, dør en `.js`-shim ved sin første `require`.

### Claude's skrivebordsapp: in-place, og den ramme, den faktisk tegner i

Claude kan ikke bruge flytningen ovenfor, fordi `OnlyLoadAppFromAsar` er smeltet på —
Electron loader `resources/app.asar` og intet andet, så en shim i `resources/app`
kan aldrig køre. Den patch'es **in place** i stedet: arkivet sikkerhedskopieres, dets
`package.json`-`main` omskrives til `"../wintage-shim.cjs"` (polstret til den samme
byte-længde, så hver offset i arkivet forbliver gyldig), og den pr.-fil integritets-
hash opdateres til at matche. `-Revert` gendanner sikkerhedskopien.

Installatøren læser stadig fuserne **før den flytter noget** og nægter med en
begrundelse, når de blokerer den — `EnableEmbeddedAsarIntegrityValidation` ville få
omskrivningen ovenfor til at fejle ved opstart i stedet for ved installation. Tjek enhver app selv:

```powershell
node ..\tools\electron-fuses.js "<path to the app's exe>"
```

Den anden halvdel af dette var et meget roligere problem. Claude's `BrowserWindow` gengiver
en tynd skal, og **hele den synlige applikation er en `WebContentsView`**, der er
hæftet på den. Shimen plejede at hooke `browser-window-created`, så den injicerede stylesheet'et
ind i skallen, rapporterede succes til `wintage-status.txt`, og ændrede intet, du
kunne se. Den hooker `web-contents-created` nu, som dækker vinduesindhold,
`WebContentsView`'er, `BrowserView`'er, `<webview>`-gæster og popups lige så meget.

### Obsidian

Et community-tema skrives ind i hver vaults `.obsidian/themes/` — alle seksten
paletter på én gang, præcis som VS Code-målet, så du skifter mellem dem i
**Settings → Appearance** uden at køre noget igen. Skabelonen blev afledt fra
det håndlavede `VintageWin95`-tema, der allerede var i vaulten, hver farve erstattet af det
token, den svarede til. `-Palette <slug>` sætter, hvilken der er aktiv ved installation;
`appearance.json` sikkerhedskopieres først, og `-Revert` fjerner kun `Wintage *`-
temaerne og gendanner dit tidligere valg — et håndlavet tema i samme vault
røres aldrig.


### MPC-HC (K-Lite)

Indbygget Win32, intet stylesheet og intet injektionspunkt, og dens mørke temas farver er
kompileret ind i programmet — ingen registreringsdatabase-værdi eksponerer dem. Så dette mål **kan ikke
bære en palet**. Hvad det gør: slår det mørke tema til og anvender UI.md
-typografireglerne på OSD'en, som er den ene overflade, MPC-HC lader brugeren styre.
De tidligere indstillinger eksporteres til `desktop/backup/mpc-hc-settings.reg` først.

Luk MPC-HC før du anvender: det omskriver sine indstillinger ved afslutning.

## Genopbygning

Alt under `desktop/out/` er genereret fra `themes/*.json`. Det er ikke
sporet i git (T-160), så en frisk klon skal bygge det én gang, før det installeres:

```powershell
node ..\tools\build-desktop.js          # genopbyg alle mål
node ..\tools\build-desktop.js --check  # exit 1, hvis noget er forældet
```

`release.ps1` kører bygningen og hver port, så en release ikke kan sende output, der
har drevet væk fra paletterne.

<!-- T-311 target/section coverage supplement -->
## Dækning af mål og sektioner

Denne sektion spejler dækningen af Process Explorer, Notepad++, Cinema 4D og terminalskrifterne i den nuværende engelske README, så denne oversættelse ikke bliver stille forældet. Kodeliteralerne (mål-id'er, registre-stier, filnavne) er med vilje sprog-uafhængige; teksten omkring dem er oversat.

### Hvad hvert mål faktisk kan tematisere (tilføjede mål)

| mål | mekanisme | overlever en app-opdatering |
|---|---|---|
| `notepadplusplus` | tema-XML + alias ind i din `themes`-mappe for Notepad++ | ja — det ligger i din egen profil |
| `cinema4d` | farveskema lagt i din `schemes`-mappe for Cinema 4D | ja — det ligger i din egen profil |
| `processexplorer` | `HKCU\Software\Sysinternals\Process Explorer`: rækkefremhævningsfarver og grafikbaggrunde, se nedenfor | nej — Process Explorer skriver sine egne indstillinger om, når det afslutter; luk det og kør igen |

### Process Explorer (Sysinternals)

Process Explorer gemmer farverne i `HKCU\Software\Sysinternals\Process Explorer` og skriver den nøgle om, når programmet lukker, så målet **nægter, mens `procexp`, `procexp64` eller `procexp64a` kører** — luk det og kør igen. Det tematiserer de konfigurerbare farvekategorier:

- **tilgængelige**: rækkefremhævningsfarverne for processer (`ColorOwn`, `ColorServices`, `ColorRelocatedDlls`, `ColorImmersive`, `ColorPacked`, `ColorJobs`, `ColorNet`, `ColorProtected`, `ColorNewProc`, `ColorDelProc`, `ColorSuspend`) i både lysmodus- og `*Dark`-varianter, plus grafikbaggrundene (`ColorGraphBk`, `ColorGraphBkDark`) — 24 værdier i alt. Hver variant blandes mod den tilsvarende pol i den aktive palet (dets lysere nuance til lysmodus-udfyldningen, den mørkere til `*Dark`), så rækkefyldningerne beholder palettens egen nuance frem for at blegne næsten til hvid;
- **ikke tilgængelige**: titellinjen, menulinjen, værktøjslinjen, baggrunden og tekstfarverne i listevisningen samt graflinjernes farver — de er kompileret ind i `procexp.exe` og afsløres af ingen indstillingsværdi. Målet tematiserer rækkefremhævningerne og den grafikbaggrund, det virkelig ejer, og påstår intet mere.

Hver værdi, Apply kan ændre, tages som et øjeblikssnapshot før ændringen (gendannelse ved første berøring under `%APPDATA%\Wintage\recovery\processexplorer\`) og sættes nøjagtigt tilbage af `-Revert`, inklusive om hver værdi var fraværende, og om markøren var til stede, men tom. En transportabel mappe uden for de almindelige Sysinternals-kataloger huskes via den kanoniske `paths.json`-nøgle `processexplorer` (CLI-argumentet `-ProcessExplorerPath`; GUI'en kan også vælge den).

### Terminalskrifter (`fonts/terminal/`)

Begge terminalmål læser ÉN kanonisk typografisk indstilling i `%APPDATA%\Wintage\terminal-font.json` (`schema`, `fontSlug`, `family`, `size`, `renderingMode`). Når filen mangler, beholder målene den udleverede standardværdi (Terminus (TTF) for Windows, 12 pt, aliased), så eksisterende maskiner forbliver uændrede. En ugyldig indstilling fejler lukket: intet overskrives, og målet nægter.

`fonts/terminal/catalog.json` er det ene skriftkatalog: 20 indbundne open source-monospace-familier plus de to systemtyper, Wintage navngiver men aldrig udleverer (Terminus (TTF) for Windows, Consolas). Hver indbundet post indeholder sin upstream-kilde, fastlåste revision, licens-id, licensfil og SHA-256. De præcise filer ligger i `fonts/terminal/files/` med deres licenstekster i `licenses/`; Wintage under drift arbejder helt offline og henter aldrig en skrift.

`tools/sync-terminal-fonts.ps1` er downloaderen kun for vedligeholdere. Den læser `fonts/terminal/sources.json` (én uforanderlig artefakt pr. familie), verificerer hver SHA-256 og nægter ved afvigelse. `-VerifyOnly` (standard) kontrollerer træet på disken uden netværk; `-Fetch -Write` leverer filerne ind igen. Downloadede skriftbytes behandles som utroværdige binære aktiver — hashet og skrevet, aldrig kørt. Én udskiftning er registreret: **Fantasque Sans Mono** erstatter Liberation Mono, som ikke udgiver nogen fastlåst binær udgivelse (kun kilden `.sfd`).

Installatøren **gennemser skrifter, den installerer dem ikke.** Fanen TERMINAL FONTS indlæser en indbundet skrifttype i en proceslokal `PrivateFontCollection` til en live forhåndsvisning, som foretager **nul** systemregistreringer af skrifter. At vælge en skrift, en størrelse (7–24 pt) eller en gengivelsestilstand (aliased/grayscale/cleartype) opdaterer kun forhåndsvisningen og indstillingen. At installere en skrift er en eksplicit **INSTALL SELECTED**-handling, der åbner Windows' egen skriftinstallatør; efter Windows' bekræftelse må brugeren tjekke igen med Refresh. Reelle terminalændringer sker kun ved en eksplicit **APPLY TERMINAL / APPLY CONHOST / APPLY BOTH**.

Windows Terminal anvendes på den valgte installerede familie i den valgte størrelse, og gengivelsestilstanden kortlægges til `profiles.defaults.antialiasingMode`. Klassisk conhost er strengere: den gengiver på et fast cellenet, så en valgt skrifttype nægtes før nogen ændring af registret, medmindre Windows kan opløse den (standardtypen og Consolas-reserven er undtaget). Health og Reapply validerer den konfigurerede skrifttype, størrelse og antialiasing mod indstillingen, så en ændring af indstillingen efter et Apply rapporteres som en afvigelse i stedet for som "sund". Terminalfarvernes livscyklus er urørt: Revert gendanner de præcise værdier, der var ejet af Wintage før, og fjerner aldrig en skrift fra maskinen.
<!-- source-digest: desktop/README.md sha256:1b166ae6a7cf8a5c -->
