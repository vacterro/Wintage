# Wintage för desktopapplikationer

Userskriptet teman webben. Det här teman programmen runtomkring, från samma
paletter, så att webbläsaren och apparna slutar vara oense om vad mörkguld
betyder.

Det finns en regel bakom varje beslut här: **applikationer uppdaterar sig själva,
och en uppdatering får inte tyst bryta något.** Där ett mål har en egen plats i
din profil, hamnar temat där och överlever uppdateringar. Där det inte har det, är
installeraren skriven för att kunna köras igen — och säger det, i stället för att
låtsas att den var beständig.

## GUI:t

Dubbelklicka på **`Wintage Installer.vbs`** i repo-roten för att öppna den utan
konsolfönster, eller kör detta direkt för diagnostik:

```powershell
powershell -File desktop\WintageInstaller.ps1
```

Temalist med färgprover, målen som hittats på den här datorn, en live
Win95-förhandsvisning och alla tjugoen färgtoken som redigerbara swatches. Att
redigera en swatch förgrenar paletten till **Custom** i stället för att ändra ett
medföljande tema bakom ryggen på dig. Panelen till höger visar live WCAG-kontrast
för de tre token som bär text — en palett som failar där nekas ändå av
buildgrinden, så det är bättre att se det före Apply än efter.

Mål är delade i två listor som nås via tangentbordet: **MY APPS** innehåller de
portabla/source-tree-verktygen CodeNomad, SAIPENVIEW, SmartVac och WildRift;
**POPULAR APPS** innehåller Windows, OBS, terminaler, editorer och den övriga
installerade programvaran. ALL/NONE och Apply/Revert verkar på båda listorna utan
att ändra deras gruppering.

Fönstret bär den palett det håller på att installera. Det är den snabbaste
tillgängliga förhandsvisningen, och det håller verktyget ärligt: en palett som gör
detta fönster oläsligt är påtagligt oläsligt.

Apply skickar vidare till `install.ps1`. Det finns exakt en kodväg som installerar
ett tema, så GUI:t kan inte glida iväg från kommandoraden.

## Kommandoraden

```powershell
.\desktop\install.ps1                                  # vad som finns, vad som temats, med vilken palett
.\desktop\install.ps1 -Target freebuff -Palette klite  # en app, en palett
.\desktop\install.ps1 -Target all -Palette goldendefault # allt
.\desktop\install.ps1 -Target all -WhatIf              # säg vad som skulle ändras, rör ingenting
.\desktop\install.ps1 -Target freebuff -Revert         # ångra en
```

`-Palette` har som standard `goldendefault` (**Golden Default**). GUI:t öppnar på
samma palett och kontrollerar alla tillgängliga mål. Att måla om en app som redan
är temad fungerar medan den kör; en första installation gör det inte, eftersom
arkivet är i bruk.

## Vad varje mål faktiskt kan teman

| mål | mekanism | överlever en appuppdatering |
|---|---|---|
| `windows` | användarens `.theme`: mörkt system-/appläge, accent- och klassiska färgroller | yes — installerat i din lokala Windows Themes-mapp |
| `browsers` | upptäcker installerade + portabla Chromium-profiler, stegar fram det valda chrome-temat och öppnar webbläsarägda Tampermonkey/temabekräftelsesidor | yes — efter en **Load unpacked** per profil |
| `terminal` | Windows Terminal-schema + standardvärden för alla profiler, Consolas 12 aliased | yes — inställningarna finns i din profil |
| `conhost` | `HKCU\Console`-standardvärden + varje befintlig cmd/PowerShell-profil | yes — exakt snapshot av vidrörda värden |
| `obs` | OBS 30.2+-`.ovt`-variant + aktiv `user.ini`-temad | yes — den bor i din profil |
| `antigravity`, `vscode` | färgtemaextension i `~/.antigravity/extensions` / `~/.vscode/extensions` | **yes** — den bor i din profil |
| `freebuff`, `antigravity-app`, `codenomad` | Electron-shim, se nedan | no — kör installeraren igen |
| `claude` | Electron-shim, lappad på plats — se nedan | no — en uppdatering skapar en ny `app-<version>`-mapp |
| `mpchc` | registry, mörkt tema + endast OSD-typografi | no — MPC-HC skriver om sina inställningar vid avslut |
| `obsidian` | communitytema per vault, alla paletter installerade på en gång | **yes** — den bor i din vault |
| `saipenview` | skriver om sina egna `:root`-tokenvärden i `style.css` | no — en källfil; kör igen efter en pull |
| `discord` | CSS placerat i BetterDiscords egen temamapp | yes |
| `totalcmd`, `totalcmd2` | `wincmd.ini`-nycklar `[Colors]`; befintliga recent-file-filter använder palettens länkfärg | yes — det är din ini |
| `smartvac`, `wildrift` | tokentabell omskriven i appens egen källkod | no — en källfil; kör igen efter en pull |

### FreeBuff-annonsborttagning

FreeBuff (AI-assistentens desktopapp) levererar sitt eget annonsnätverk:
renderer-bundlen (`resources/orchestrator/ui/assets/index-*.js`) renderar ett
`sponsored-ad`-kort och en trådbanér, och orkestratorn (`resources/orchestrator/orchestrator.js`)
exponerar `/api/ad/slot|impression|click`-rutter som anropar den fjärranslutna
annonsauktionen. Shimen teman bara appen; den rör inte dessa filer.

`desktop/patch-freebuff-ads.js` klipper bort annonserna på bytenivå:

- renderer: annonskortets/banérets anropsställen blir `null`, och
  API-klientmetoderna `adSlot` / `adImpression` / `adClick` blir no-ops — ingenting
  renderas, och ingen `/api/ad/*`-förfrågan lämnar någonsin renderaren;
- orkestrator: alla tre `/api/ad/*`-rutter slutar anropa annonsnätverket, och
  live-turns inline-annonsförfrågan (`maybeRequestAd`) kortsluts.

Bundlfilnamnet innehåller en build-hash, så lappen hittar den aktuella bundlen via
`index.html` i stället för att leverera en versionslåst payload — det är det som
får den att överleva uppdateringar. Originalen backas upp till
`_orig-backup-<timestamp>/` i installationskatalogen; `--revert` återställer den
nyaste.

**Framtida versioner hanteras på två oberoende lager:**

1. **Byte-lapp med regex-fallbackar.** Varje mål har en exakt sträng för den
   nuvarande builden *och* en fallback baserad på reguljära uttryck, förankrad i
   det som en minifier inte kan döpa om — `/api/ad/*`-sökvägsliteralerna,
   protokoll-diskriminatorn `case"ad":`, klassen `sponsored-ad` och placeringarna
   `variant:"banner"` / `variant:"card"`. Orkestratorn är inte minifierad
   (läsbara namn som `maybeRequestAd` och `app.ads.slotAd`), så dess exakta
   strängar håller länge; renderer-bundlen är minifierad, så dess regex-fallbackar
   tar över i samma ögonblick som nästa build döper om dess identifierare.
2. **Blockering på shim-nivå (`targets/electron/shim.cjs`).** Helt oberoende av
   bundlen: alla fetch/XHR till en `/api/ad/`-URL avvisas inne på sidan, och alla
   element vars klass innehåller `sponsored-ad` döljs i samma stund som de visas.
   Till och med en helt ny bundle som detta skript ännu inte lärt sig kan inte få
   fram en annons.

```powershell
node .\desktop\patch-freebuff-ads.js           # lappa (backar upp först)
node .\desktop\patch-freebuff-ads.js --sound "C:\...\my.mp3"   # lappa + eget avslutningsljud (wav/mp3/ogg/flac/m4a/aac)
node .\desktop\patch-freebuff-ads.js --scan    # vilka annonsmarkeringar bär DENNA build?
node .\desktop\patch-freebuff-ads.js --verify
node .\desktop\patch-freebuff-ads.js --revert
```

Den körs automatiskt som en del av `install.ps1 -Target freebuff` och måste köras
om efter varje FreeBuff-uppdatering (uppdateringar återställer standardfilerna).
Om en build ändrar form, nämner skriptet vilket mål som inte längre matchade —
kör `--scan` för att se vad den nya builden fortfarande bär och uppdatera
strängarna där.

**FreeBuff-avslutningsljud.** Renderaren spelar `chime-<hash>.mp3` när en tur är
klar. Lappen hittar det på samma sätt som den hittar bundlen (namnet innehåller en
build-hash), så `--sound <file>` installerar ditt eget ljud (wav/mp3/ogg/flac/m4a/
aac) över det och behåller standardfilen som `chime-*.mp3.bak`; `--revert`
återställer den. `--verify` rapporterar vilken som är aktiv.

### FreeBuff-ljudknapp (GUI)

`WintageInstaller.ps1` har en liten **FB SOUND**-knapp under APPLY / REVERT-stacken.
Den lagrar bara en *preferens*; `install.ps1 -Target freebuff` läser samma fil och
lämnar över den till lappen som `--sound`, så annonserna och ljudet appliceras i
en enda körning:

- **Vänsterklick** — välj en ljudfil (OpenFileDialog, wav/mp3/ogg/flac/m4a/aac)
  och hör den spelas upp direkt: PCM WAV via System.Media.SoundPlayer, alla andra
  format via en WPF MediaPlayer (Media Foundation, asynkront, så fönstret fryser
  aldrig). Valet kommer ihåg i
  `%APPDATA%\Wintage\freebuff-sound.txt` (per maskin, utanför git-checkouten,
  precis som de ihågkomna source-tree-mapparna).
- **Högerklick** — återställ preferensen till FreeBuff:s standard-chime (stoppar
  också en förhandsvisning som fortfarande spelas).
- **COPY** — kopierar det valda ljudet in i själva repot
  (`sounds\freebuff.<ext>`, med källans filändelse) och pekar om preferensen mot
  den kopian, så ljudet överlever att originalfilen tas bort eller flyttas.
  Aktiverad bara medan ett eget ljud är inställt; att kopiera igen skriver bara
  över repo-kopian. Mappen `sounds/` är vanligt git-spårat innehåll, så att
  commit:a den gör att ljudet också överlever om-kloner.

Endast igenkända ljudcontainrar förhandsvisas — huvudet sniffas först, så ett
icke-ljudval annonseras i stället för att tyst spela ingenting.

Knappen visar `ON` medan ett eget ljud är inställt; att hovra över den visar sökvägen.
Applicera `freebuff`-målet efteråt (markera FreeBuff + APPLY, eller kör
`install.ps1 -Target freebuff` från en terminal) för att det ska träda i kraft.

### Terminaler

`terminal` skriver ett `Wintage`-färgschema i varje upptäckt stabil, Preview- eller
oförpackad Windows Terminal-inställningsfil och väljer det via
`profiles.defaults`, tillsammans med konsolsäker Consolas 12 och aliased text.
Originalfilen behålls byte-för-byte bredvid den, och `-Revert` återställer den.

`conhost` täcker klassisk `cmd.exe`, Windows PowerShell, Git CMD/Bash-konsol-
profiler och andra befintliga `HKCU\Console`-barn. Den skriver palettens fulla
16-färgstabell till både rotstandarderna och varje befintlig override, och
återställer sedan bara de värden den vidrörde. Den applicerar Consolas också,
eftersom proportionell Verdana kolliderar med det fasta cellrutnät som båda
terminalvärdarna använder.

### Webbläsare och Tampermonkey

`browsers` hittar Chrome-, Edge-, Brave-, Cent-, Vivaldi- och Opera-profiler på
installerade platser och från den portabla rot du pekar den mot (`-PortableRoot`,
eller den ihågkomna `portable`-posten i `paths.json`). Dess status visar både
antalet profiler och hur många av dem som innehåller Tampermonkey. Apply kopierar
det valda browser-chrome-temat till den stabila mappen
`%LOCALAPPDATA%\Wintage\browser-theme`, lägger den sökvägen på urklippstavlan och
öppnar varje exakt profil på `chrome://extensions` plus Wintage-userskriptets
Install/Update-sida. Profiler utan Tampermonkey får också dess Chrome
Web Store-sida.

Chromium förbjuder medvetet tyst installation av extensioner utanför butiken på en
ohanterad Windows-maskin. Den första webbläsartemainstallationen kräver därför ett
**Developer mode → Load unpacked**-bekräftande per profil. Välj den kopierade
sökvägen; efter det fortsätter Wintage att byta ut samma stabila mapp när paletter
ändras. Bekräfta även **Install/Update** i Tampermonkey. Ingen `Preferences`-,
Secure Preferences- eller Tampermonkey-LevelDB-fil redigeras bakom webbläsarens
rygg. Om Tampermonkey inte fanns, installera det från den öppnade butiksfliken och
uppdatera den redan öppna `wintage.user.js`-fliken för att få Install-skärmen.

### Windows

`windows` installerar och aktiverar omedelbart ett innehållsadresserat
`%LOCALAPPDATA%\Microsoft\Windows\Themes\Wintage-<hash>.theme`. Den utgår från det
aktiva temat och ersätter bara de dokumenterade sektionerna för färg, markör och
visuell stil. Tapet, ljud och skrivbordsikoner förblir oförändrade; markörer växlar
avsiktligt till det installerade `___CURRENT___`-schemat. Det första aktiva temat
sparas byte-för-byte som `Wintage.original.theme`; palettändringar behåller den
baslinjen, och `-Revert` aktiverar den igen. Moderna Windows-kontroller kommer
fortfarande från den signerade Aero-visuella stilen — Wintage ändrar dess stödda
mörka läge, accent och klassiska systemfärgsinmatningar i stället för att ersätta
skyddade `.msstyles`-filer. Aktiva och inaktiva titelrader delar palettens
dämpade upphöjda-yt-färg; den ljusa highlighten förblir reserverad för
text/markeringskanter. Den tidigare inaktiva titelradsaccentsnapshotas separat och
återställs exakt av `-Revert`. Innehållshashen ger Windows ett nytt
filassocieringsmål när samma palett byggs om, så att återapplicering av en
uppdaterad palett inte misstas för en no-op; den övertagna Wintage-filen tas bort
efter att Windows bekräftat att den nya är aktiv.

### OBS Studio

`obs` genererar en OBS 30.2+-variant över den underhållna Yami Classic-basen,
installerar den i `%APPDATA%\obs-studio\themes` och skriver dess stabila temad till
`user.ini`, så den valda Wintage-paletten är redan vald vid nästa start. Stäng OBS
före Apply eller Revert: OBS skriver om `user.ini` vid avslut. Den första
appliceringen backar upp både det tidigare valet och alla teman med samma namn
byte-för-byte.

### Electron-appar

`resources/app.asar` flyttas till `resources/app/app.asar` (dess
`app.asar.unpacked`-syskon följer med — den kopplingen är efter filnamn, och att
skilja dem åt bryter varje nativ modul), och en liten `shim.cjs` tar den lediga
`resources/app`-platsen. Shimen injicerar stilmallen och laddar sedan det
ursprungliga arkivet. **Ingen applikationsbyte skrivs om**, bara flyttas om;
`-Revert` flyttar tillbaka den direkt.

Stilmallen skrivs inte för dessa appar — den extraheras från `wintage.user.js`, så
varje bevel-, scrollbar- och typstegsfix som gjorts för webbläsaren hamnar också
här, utan en andra kopia som kan ruttna.

Två noteringar värda att ha i förväg:

- Det uppenbara tillvägagångssättet — att släppa `resources/app` bredvid arkivet
  och lita på att Electron föredrar det — **fungerar inte och misslyckas tyst**.
  Electron söker efter `app.asar` först. Appen startar perfekt och temat körs
  aldrig.
- Shimen är medvetet `.cjs`, inte `.js`. Dess `package.json` kopieras från appens
  egen så att appen behåller sitt namn och sin version (namnet avgör var userData
  bor — en shim som döper om det flyttar appen till en tom profil). Om manifestet
  säger `"type": "module"`, dör en `.js`-shim på sitt första `require`.

### Claude:s desktopapp: på plats, och i ramen den faktiskt ritar i

Claude kan inte använda omflyttningen ovan, eftersom `OnlyLoadAppFromAsar` är
smält på: Electron laddar `resources/app.asar` och inget annat, så en shim i
`resources/app` kan aldrig köras. Den lappas i stället **på plats**: arkivet backas
upp, dess `package.json`-`main` skrivs om till `"../wintage-shim.cjs"` (utfyllt
till samma bytelängd, så varje offset i arkivet förblir giltig), och
per-fil-integritetshashen uppdateras så att den stämmer. `-Revert` återställer
backupen.

Installeraren läser fortfarande fuses **innan den flyttar något** och vägrar med en
anledning när de blockerar den — `EnableEmbeddedAsarIntegrityValidation` skulle få
omskrivningen ovan att misslyckas vid start snarare än vid installation. Kontrollera
vilken app som helst själv:

```powershell
node ..\tools\electron-fuses.js "<path to the app's exe>"
```

Andra halvan av detta var ett mycket tystare problem. Claude:s `BrowserWindow`
renderar ett tunt skal och **hela den synliga applikationen är en
`WebContentsView`** som är fäst vid det. Shimen hakade förr på
`browser-window-created`, så den injicerade stilmallen i skalet, rapporterade
framgång till `wintage-status.txt` och ändrade ingenting du kunde se. Den hakar nu
på `web-contents-created`, vilket täcker fönsterinnehåll, `WebContentsView`-ar,
`BrowserView`-ar, `<webview>`-gäster och popups lika mycket.

### Obsidian

Ett communitytema skrivs in i varje vaults `.obsidian/themes/` — alla sexton
paletter på en gång, precis som VS Code-målet, så du växlar mellan dem i
**Settings → Appearance** utan att köra om något. Mallen härleddes från det
handgjorda `VintageWin95`-temat som redan fanns i vaulten, varje färg ersatt med
den token den motsvarade. `-Palette <slug>` avgör vilken som är aktiv vid
installation; `appearance.json` backas upp först, och `-Revert` tar bort bara
`Wintage *`-temana och återställer ditt tidigare val — ett handgjort tema i samma
vault rörs aldrig.

### SAIPENVIEW

Dess frontend deklarerar redan Wintage-tokennamnen i sin egen `:root`, så den här
lappen skriver om **bara tokenvärdena** — aldrig en selektor, ett typsnitt, en
rambredd eller en padding. Inget som påverkar boxmodellen ändras, så texten kan
inte flytta sig. Det är avsiktligt: det tidigare tillvägagångssättet lade hela
webbläsarstilmallen ovanpå, och `wintage.css` är skriven för godtyckliga webbsidor
— universella selektorer som tvingar fram typsnittet, storleksstegen, 2px-ramar
och kontrollhöjder. På en app som redan har sin egen layout flyttar det allt.

Verifierat genom att maskera varje hex och diffa mot backupen: strukturellt
identiska, bara färgliteralerna skiljer. `--link` rapporteras som inte deklarerad
där (dess markdown-länkar läser `--accentTeal`, vilket detta ställer in) i stället
för att injiceras — att lägga till en variabel som appen aldrig läser vore dödvikt.

### MPC-HC (K-Lite)

Nativ Win32, ingen stilmall och ingen injiceringspunkt, och det mörka temats färger
är kompilerade in i programmet — inget registryvärde exponerar dem. Så det här
målet **kan inte bära en palett**. Vad det gör: slår på det mörka temat och
tillämpar UI.md-typografireglerna på OSD:n, den enda ytan som MPC-HC låter en
användare kontrollera. De tidigare inställningarna exporteras först till
`desktop/backup/mpc-hc-settings.reg`.

Stäng MPC-HC före applicering: den skriver om sina inställningar vid avslut.

## Ombyggnad

Allt under `desktop/out/` genereras från `themes/*.json`. Det spåras inte i git
(T-160), så en ny klon måste bygga det en gång före installation:

```powershell
node ..\tools\build-desktop.js          # bygg om alla mål
node ..\tools\build-desktop.js --check  # exit 1 om något är föråldrat
```

`release.ps1` kör builden och varje grind, så en release kan inte leverera utdata
som har drivit bort från paletterna.

<!-- source-digest: desktop/README.md sha256:1b166ae6a7cf8a5c -->
