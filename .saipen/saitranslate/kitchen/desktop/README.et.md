# Wintage lauaarvuti rakendustele

Kasutajaskript teemindab veebi. See teemindab ümber ka programmid, mis selle
ümber on, samadest palettidest lähtudes — nii et brauser ja rakendused lõpetavad
tüli selle üle, mida tume kuldne tähendab.

Iga otsuse taga on üks reegel: **rakendused uuendavad end ise, ja uuendus ei
tohi midagi vaikselt katki teha.** Kui sihtmärgil on koht sinu enda profiilis,
läheb teema sinna ja peab uuendustele vastu. Kus seda pole, on paigaldaja
kirjutatud nii, et seda saab uuesti käivitada — ja ta ütleb seda ka, selle
asemel et teeselda, et teema jäi püsima.

## GUI

Topeltklõpsa repositooriumi juurtes olevat **`Wintage Installer.vbs`**-i, et see
avaneb ilma konsooliaknata, või käivita diagnostikaks otse:

```powershell
powershell -File desktop\WintageInstaller.ps1
```

Teemaloend värvilaastudega, sellel masinal leitud sihtmärgid, reaalajas Win95
eelvaade ja kõik kakskümmend üks värvitookenit redigeeritavate väljana. Mis tahes
välja muutmine hargib paleti **Custom**-iks selle asemel, et sinu selja taga
kaasasolevat teemat muuta. Parempoolne paneel näitab reaalajas WCAG-kontrasti
kolme teksti kandva tookeni jaoks — palett, mis seal FAIL on, lükkab ehitusvärav
nagunii tagasi, nii et parem on seda näha enne RAKENDA klõpsu kui pärast.

Sihtmärgid on jaotatud kahte klaviatuuriga ligipääsetavasse loendisse:
**MINU RAKENDUSED** sisaldab kaasaskantavaid/allikapuust pärinevaid CodeNomad,
SAIPENVIEW, SmartVac ja WildRift tööriistu; **POPULAARSED RAKENDUSED** sisaldab
Windowsi, OBS-i, terminale, redaktoreid ja muud paigaldatud tarkvara.
KÕIK/MITTE ÜHTEGI ning RAKENDA/TASTA toimivad mõlema loendi peale ilma nende
rühmitust muutmata.

Aken kannab paletti, mida ta paigaldamas on. See on kiireim võimalik eelvaade ja
hoiab tööriista ausana: palett, mis muudab selle akna loetamatuks, on nähtavalt
loetamatu.

RAKENDA kutsub välja `install.ps1`-i. Teema paigaldab täpselt üks kooditee, nii
et GUI ei saa käsureast kõrvale triivida.

## Käsurida

```powershell
.\desktop\install.ps1                                  # what is here, what is themed, with which palette
.\desktop\install.ps1 -Target freebuff -Palette klite  # one app, one palette
.\desktop\install.ps1 -Target all -Palette goldendefault # everything
.\desktop\install.ps1 -Target all -WhatIf              # say what would change, touch nothing
.\desktop\install.ps1 -Target freebuff -Revert         # undo one
```

`-Palette` vaikeväärtus on `goldendefault` (**Golden Default**). GUI avaneb samal
paletil ja kontrollib iga saadaolevat sihtmärki. Juba teemindatud rakenduse
ülevärvimine töötab selle töötamise ajal; esmakordne paigaldus ei tööta, sest
arhiiv on kasutuses.

## Mida iga sihtmärk tegelikult teemindada suudab

| sihtmärk | mehhanism | peab rakenduse uuenduse üle vastu |
|---|---|---|
| `windows` | kasutaja `.theme`: tume süsteemi/rakenduse režiim, aktsent ja klassikalised värviosad | yes — paigaldatud sinu lokaalsesse Windows Themes kausta |
| `browsers` | tuvastab paigaldatud ja kaasaskantavad Chromiumi profiilid, valmistab ette valitud chrome teema ja avab brauseri enda Tampermonkey/teema kinnituslehed | yes pärast üht **Load unpacked** kinnitust profiili kohta |
| `terminal` | Windows Terminal skeem + kõigi profiilide vaikeseaded, Consolas 12 silumata | yes — seaded on sinu profiilis |
| `conhost` | `HKCU\Console` vaikeseaded + iga olemasolev cmd/PowerShell profiil | yes — puudutatud väärtuste täpne hetktõmmis |
| `obs` | OBS 30.2+ `.ovt` variant + aktiivne `user.ini` teema ID | yes — elab sinu profiilis |
| `antigravity`, `vscode` | värviteema laiendus kaustas `~/.antigravity/extensions` / `~/.vscode/extensions` | **yes** — elab sinu profiilis |
| `freebuff`, `antigravity-app`, `codenomad` | Electroni shim, vaata allpool | no — käivita paigaldaja uuesti |
| `claude` | Electroni shim, plaasterdatud paigas — vaata allpool | no — uuendus loob uue `app-<version>` kausta |
| `mpchc` | registrisse, ainult tume teema + OSD tüpograafia | no — MPC-HC kirjutab oma seaded väljudes üle |
| `obsidian` | kogukonna teema iga vault-i jaoks, kõik paletid paigaldatud korraga | **yes** — elab sinu vault-is |
| `saipenview` | kirjutab oma `:root` tookeni väärtused `style.css`-is üle | no — allikafail; käivita uuesti pärast pulli |
| `discord` | CSS visatud BetterDiscordi enda teemakausta | yes |
| `totalcmd`, `totalcmd2` | `wincmd.ini` `[Colors]` võtmed; olemasolevad hiljutiste failide filtrid kasutavad paleti lingivärvi | yes — see on sinu ini |
| `smartvac`, `wildrift` | tookenitabel ümber kirjutatud rakenduse enda allikasse | no — allikafail; käivita uuesti pärast pulli |

### FreeBuffi reklaamide eemaldamine

FreeBuff (AI assistendi lauaarvuti rakendus) tarnib kaasa oma reklaamivõrgu:
renderdaja kimp (`resources/orchestrator/ui/assets/index-*.js`) renderdab
`sponsored-ad` kaardi ja lõimebänneri, ning orkestreerija
(`resources/orchestrator/orchestrator.js`) avab `/api/ad/slot|impression|click`
marsruudid, mis kutsuvad kaugreklaami-oksjoni. Shim ainult teemindab rakendust;
need failid jäävad puutumata.

`desktop/patch-freebuff-ads.js` lõikab reklaamid välja baiditasandil:

- renderdaja: reklaamkaardi/bänneri väljakutsepunktid muutuvad `null`-iks ning
  `adSlot` / `adImpression` / `adClick` API kliendimeetodid muutuvad no-opideks —
  midagi ei renderdu ja ükski `/api/ad/*` päring ei lahku kunagi renderdajast;
- orkestreerija: kõik kolm `/api/ad/*` marsruuti lõpetavad reklaamivõrgu
  kutsumise ning reaalajas pöörde sisene reklaamipäring (`maybeRequestAd`)
  lühistatakse.

Kimbu failinimes on sees ehitus-hash, nii et plaaster leiab praeguse kimbu
`index.html`-ist selle asemel, et tarnida versioonikinnitatud lasti — just see
teebki selle uuendustele vastupidavaks. Originaalid varundatakse kausta
`_orig-backup-<timestamp>/` paigalduskausta; `--revert` taastab uusima.

**Tulevasi versioone töödeldakse kahel sõltumatul kihil:**

1. **Baiditasandiline plaaster regex-varuvariantidega.** Igal sihtmärgil on täpne
   sõne praeguse ehituse jaoks *ja* regulaaravaldise varuvariant, mis
   ankurdatakse selle külge, mida minifitseerija ümber nimetada ei saa —
   `/api/ad/*` teekonnaliteraalid, `case"ad":` protokolli eristaja,
   `sponsored-ad` klass ning `variant:"banner"` / `variant:"card"` asetused.
   Orkestreerija pole minifitseeritud (loetavad nimed nagu `maybeRequestAd` ja
   `app.ads.slotAd`), nii et tema täpsed sõned püsivad kaua; renderdaja kimp on
   minifitseeritud, nii et tema regex-varuvariandid võtavad juhtimise üle
   niipea, kui järgmine ehitus oma identifikaatorid ümber nimetab.
2. **Shimi-tasandi blokk (`targets/electron/shim.cjs`).** Kimbust täiesti
   sõltumatu: igasugune fetch/XHR-päring `/api/ad/` URL-ile lükatakse lehe sees
   tagasi ning iga element, mille klass sisaldab `sponsored-ad`-i, peidetakse
   kohe, kui see ilmub. Isegi täiesti uus kimp, mida see skript veel ei tunne,
   ei suuda reklaami nähtavale tuua.

```powershell
node .\desktop\patch-freebuff-ads.js           # patch (backs up first)
node .\desktop\patch-freebuff-ads.js --sound "C:\...\my.mp3"   # patch + custom completion sound (wav/mp3/ogg/flac/m4a/aac)
node .\desktop\patch-freebuff-ads.js --scan    # what ad markers does THIS build carry?
node .\desktop\patch-freebuff-ads.js --verify
node .\desktop\patch-freebuff-ads.js --revert
```

See käivitub automaatselt osana käsust `install.ps1 -Target freebuff` ning seda
tuleb pärast igat FreeBuffi uuendust uuesti käivitada (uuendused taastavad
tavalised failid). Kui ehitus muudab kuju, nimetab skript sihtmärgi, mis enam ei
sobinud — käivita `--scan`, et näha, mida uus ehitus endiselt kannab, ja
värskenda sõnesid seal.

**FreeBuffi lõpetamise heli.** Renderdaja mängib pöörde lõppedes
`chime-<hash>.mp3`-i. Plaaster leiab selle sama moodi nagu kimbu (nimes on sees
ehitus-hash), nii et `--sound <file>` paigaldab sinu enda heli
(wav/mp3/ogg/flac/m4a/aac) selle peale ja hoiab tavalise faili
`chime-*.mp3.bak`-ina; `--revert` taastab selle. `--verify` teatab, kumb on
aktiivne.

### FreeBuffi helinupp (GUI)

`WintageInstaller.ps1`-il on väike **FB HELI** nupp RAKENDA / TASTA nuppude all.
See salvestab ainult *eelistuse*; `install.ps1 -Target freebuff` loeb sama faili
ja annab selle plaastrile `--sound`-ina edasi, nii et reklaamid ja heli
rakendatakse ühe käiguga:

- **Vasakklõps** — vali helifail (OpenFileDialog, wav/mp3/ogg/flac/m4a/aac) ja
  kuula kohe esitust: PCM WAV läbi System.Media.SoundPlayer, kõik muud
  vormingud läbi WPF MediaPlayer-i (Media Foundation, asünkroonne, nii et aken
  kunagi ei tardu). Valik jääb meelde faili
  `%APPDATA%\Wintage\freebuff-sound.txt` (masinapõhine, väljaspool
  git-väljavõtet, täpselt nagu meelde jäänud allikapuust kaustad).
- **Paremklõps** — kustuta eelistus tagasi FreeBuffi tavalisele toonile
  (peatab ka igasuguse veel mängiva eelvaate).
- **KOPEERI** — kopeerib valitud heli repositooriumi enda sisse
  (`sounds\freebuff.<ext>`, säilitades allika laiendi) ja suunab eelistuse
  sellele koopiale, nii et heli peab vastu ka siis, kui originaalfail
  kustutatakse või liigutatakse. Aktiivne ainult siis, kui kohandatud heli on
  seatud; uuesti kopeerimine lihtsalt kirjutab repositooriumi koopia üle.
  `sounds/` kaust on tavaline git-jälgitav sisu, nii et selle committimine teeb
  heli vastupidavaks ka uuesti kloonimisele.

Eelvaadatakse ainult tuntud helikonteinerit — päis nuusitakse enne välja, nii et
mitte-helivalik teatatakse ette, selle asemel et vaikselt mitte midagi mängida.

Nupp näitab `ON`, kui kohandatud heli on seatud; selle kohal hõljumine näitab
teed. Rakenda seejärel `freebuff` sihtmärk (märgi FreeBuff + RAKENDA, või
käivita terminalist `install.ps1 -Target freebuff`), et see jõustuks.

### Terminalid

`terminal` kirjutab `Wintage` värviskeemi igasse tuvastatud stabiilsesse, Preview
või pakendamata Windows Terminal seadefaili ning valib selle `profiles.defaults`
kaudu koos konsooliohutu Consolas 12 ja silumata tekstiga. Originaalfail
hoitakse selle kõrval baidibaidi alles ja `-Revert` taastab selle.

`conhost` katab klassikalised `cmd.exe`, Windows PowerShell, Git CMD/Bash
konsoolprofiilid ja teised olemasolevad `HKCU\Console` alamvõtmed. See kirjutab
paleti täieliku 16-värvilise tabeli nii juurvaikeseadetesse kui ka igasse
olemasolevasse ülekirjutusse ning taastab seejärel ainult puudutatud väärtused.
Ka seal rakendab see Consolas'i, sest proportsionaalne Verdana põrkab kokku
fikseeritud laiusega lahtrivõrguga, mida mõlemad terminalihostid kasutavad.

### Brauserid ja Tampermonkey

`browsers` leiab Chrome, Edge, Brave, Cent, Vivaldi ja Opera profiilid nii
paigaldatud asukohtadest kui ka sellest kaasaskantavast juurtest, millele sa
selle suunad (`-PortableRoot`, või meelde jäänud `portable` kanne failis
`paths.json`). Selle olekuvaade näitab nii profiilide arvu kui ka seda, kui
mitmes neist on Tampermonkey. RAKENDA kopeerib valitud brauseriteema stabiilsesse
`%LOCALAPPDATA%\Wintage\browser-theme` kausta, paneb selle tee lõikelauale ja
avab iga täpse profiili aadressil `chrome://extensions` pluss Wintage
kasutajaskripti Install/Update lehe. Ilma Tampermonkeyta profiilid saavad ka
selle Chrome Web Store lehe.

Chromium keelab meelega vaikse poevälise laienduspaigalduse haldamata Windowsi
masinal. Seetõttu vajab esimene brauseriteema paigaldus profiili kohta ühte
**Developer mode → Load unpacked** kinnitust. Vali kopeeritud tee; pärast seda
asendab Wintage sama stabiilset kausta edasi, kui paletid muutuvad. Kinnita
Tampermonkeys ka **Install/Update**. Ühtegi brauseri `Preferences`, Secure
Preferences või Tampermonkey LevelDB faili ei muudeta brauseri selja taga. Kui
Tampermonkey puudus, paigalda see avatud poe vahekaardilt ja värskenda juba
avatud `wintage.user.js` vahekaarti, et saada Install ekraan.

### Windows

`windows` paigaldab ja aktiveerib kohe sisuga adresseeritud
`%LOCALAPPDATA%\Microsoft\Windows\Themes\Wintage-<hash>.theme`. See lähtub
aktiivsest teemast ja asendab ainult dokumenteeritud värvi-, kursori- ja
visuaalstiili sektsioone. Taustapilt, helid ja töölauaikoonid jäävad
muutumatuks; kursorid lülituvad teadlikult üle paigaldatud `___CURRENT___`
skeemile. Esimene aktiivne teema salvestatakse baidibaidi failina
`Wintage.original.theme`; paletivahetused hoiavad selle baasjoont alles ning
`-Revert` aktiveerib selle uuesti. Kaasaegsed Windowsi juhtelemendid tulevad
endiselt allkirjastatud Aero visuaalstiilist — Wintage muudab selle toetatud
tumeda režiimi, aktsendi ja klassikaliste süsteemivärvide sisendeid, selle
asemel et kaitstud `.msstyles` faile asendada. Aktiivsed ja mitteaktiivsed
tiitliribad jagavad paleti vaigistatud kõrgendatud pinna värvi; hele esiletõst
jääb reserveerituks teksti/valiku servadele. Eelmine mitteaktiivse tiitliriba
aktsent pildistatakse eraldi hetktõmmiseks ja `-Revert` taastab selle täpselt.
Sisu-hash annab Windowsile uue failiassotsiatsiooni sihtmärgi, kui sama palett
uuesti ehitatakse, nii et uuendatud paleti uuesti rakendamist ei aeta no-op'iks;
ületatud Wintage fail eemaldatakse pärast seda, kui Windows kinnitab uue
aktiivseks.

### OBS Studio

`obs` genereerib hooldatud Yami Classic baasi peale OBS 30.2+ variandi,
paigaldab selle kausta `%APPDATA%\obs-studio\themes` ja kirjutab selle stabiilse
teema ID `user.ini`-sse, nii et valitud Wintage palett on järgmisel käivitamisel
juba valitud. Sulge OBS enne RAKENDA või TASTA kasutamist: OBS kirjutab
`user.ini` väljudes üle. Esimene rakendamine varundab nii eelmise valiku kui ka
igasuguse samanimelise teema baidibaidi.

### Electroni rakendused

`resources/app.asar` teisaldatakse aadressile `resources/app/app.asar` (selle
`app.asar.unpacked` sõsarkaust liigub kaasa — see paar sobib kokku failinime
järgi ja nende lahutamine lõhub iga natiivse mooduli), ning väike `shim.cjs`
võtab vabanenud `resources/app` koha. Shim süstib stiililehe ja laadib seejärel
originaalarhiivi. **Ühtegi rakenduse baiti ei kirjutata ümber**, ainult
teisaldatakse; `-Revert` liigutab selle otse tagasi.

Stiililehte ei kirjutata nende rakenduste jaoks eraldi — see võetakse
`wintage.user.js`-ist välja, nii et iga brauseri jaoks tehtud faasi-,
kerimisriba- ja tüpograafiaredeliparandus jõuab ka siia, ilma teise koopiata,
mis mädaneda võiks.

Kaks märkust, mida tasub ette teada:

- Ilmselge lähenemine — panna `resources/app` arhiivi kõrvale ja loota, et
  Electron eelistab seda — **ei tööta ja ebaõnnestub vaikselt**. Electron
  otsib kõigepealt `app.asar`-i. Rakendus käivitub suurepäraselt ja teema ei
  jookse kunagi.
- Shim on meelega `.cjs`, mitte `.js`. Selle `package.json` kopeeritakse
  rakenduse enda omast, nii et rakendus säilitab nime ja versiooni (nimi
  otsustab, kus userData elab — shim, mis selle ümber nimetab, liigutab
  rakenduse tühja profiili). Kui see manifest ütleb `"type": "module"`, siis
  `.js` shim sureb oma esimesel `require`-l.

### Claude'i lauaarvuti rakendus: paigas ning raam, kuhu see tegelikult joonistab

Claude ei saa ülaltoodud teisaldust kasutada, sest `OnlyLoadAppFromAsar` fuse on
sisse lülitatud — Electron laeb `resources/app.asar`-i ja mitte midagi muud,
nii et shim kaustas `resources/app` ei jookse kunagi. Selle asemel plaasterdatakse
see **paigas**: arhiiv varundatakse, selle `package.json` `main` kirjutatakse
ümber väärtuseks `"../wintage-shim.cjs"` (täiendatud sama baidipikkuseni, nii et
iga nihe arhiivis jääb kehtivaks) ja failipõhine tervikluse-hash uuendatakse
vastavaks. `-Revert` taastab varukoopia.

Paigaldaja loeb fusid ikka **enne, kui midagi liigutab**, ja keeldub põhjusega,
kui need seda blokeerivad — `EnableEmbeddedAsarIntegrityValidation` paneks
ülaltoodud ümberkirjutuse ebaõnnestuma käivitamisel, mitte paigaldusel. Kontrolli
iga rakendust ise:

```powershell
node ..\tools\electron-fuses.js "<path to the app's exe>"
```

Selle teine pool oli palju vaiksem probleem. Claude'i `BrowserWindow` renderdab
õhukese kesta ja **kogu nähtav rakendus on selle külge kinnitatud
`WebContentsView`**. Shim konksutas varem `browser-window-created`-i, nii et see
süstis stiililehe kesta, teatas edust `wintage-status.txt`-i ja ei muutnud
midagi, mida näha oleks. Nüüd konksutab see `web-contents-created`-i, mis katab
nii akna sisu, `WebContentsView`-id, `BrowserView`-id kui ka `<webview>`
külalised ja hüpikud.

### Obsidian

Igasse vault-i `.obsidian/themes/` kirjutatakse kogukonna teema — kõik kuusteist
paletti korraga, täpselt nagu VS Code sihtmärgi puhul, nii et sa vahetad nende
vahel jaotises **Settings → Appearance** ilma midagi uuesti käivitamata. Mall
tuletati vault-is juba olevast käsitsi tehtud `VintageWin95` teemast, kusjuures
iga värv asendati tookeniga, millele see vastas. `-Palette <slug>` määrab,
milline on paigaldusel aktiivne; `appearance.json` varundatakse enne ning
`-Revert` eemaldab ainult `Wintage *` teemad ja taastab sinu eelmise valiku —
sama vault-i käsitsi tehtud teemat ei puudutata kunagi.

### SAIPENVIEW

Selle frontend deklareerib Wintage tookeninimed juba oma `:root`-is, nii et see
plaaster kirjutab ümber **ainult tookeni väärtused** — mitte kunagi selektorit,
fonti, piirilaiust ega paddingut. Miski, mis mõjutab kastimudelit, ei muutu,
nii et tekst ei saa nihkuda. See on tahtlik: varasem lähenemine pani terve
brauseri stiililehe peale, ja `wintage.css` on kirjutatud suvaliste veebilehtede
jaoks — universaalsed selektorid, mis sunnivad fonti, suurusteredelit, 2px piire
ja juhtelementide kõrgusi. Rakendusel, millel on juba oma paigutus, liigutab see
kõike.

Kinnitatud nii, et iga hex maskiti ja varukoopiaga diffiti: struktuurilt
identne, erinevad ainult värviliteraalid. `--link` teatatakse seal
deklareerimata (selle markdown lingid loevad `--accentTeal`, mida see küll
määrab), mitte ei süstita — muutuja lisamine, mida rakendus kunagi ei loe,
oleks surnud koorem.

### MPC-HC (K-Lite)

Natiivne Win32, ilma stiililehe ja ilma süstepunktita, ning selle tumeda teema
värvid on programmi kompileeritud — ükski registriväärtus neid ei avalda. Nii et
see sihtmärk **ei saa paletti kanda**. Mida see teeb: lülitab tumeda teema sisse
ja rakendab UI.md tüpograafiareeglid OSD-le, mis on ainus pind, mida MPC-HC
kasutajal kontrollida laseb. Eelmised seaded eksporditakse enne faili
`desktop/backup/mpc-hc-settings.reg`.

Sulge MPC-HC enne rakendamist: see kirjutab oma seaded väljudes üle.

## Ümberehitamine

Kõik kausta `desktop/out/` all on genereeritud failidest `themes/*.json`. Seda
ei jälgita gitis (T-160), nii et värske kloon peab selle enne paigaldamist korra
üles ehitama:

```powershell
node ..\tools\build-desktop.js          # rebuild all targets
node ..\tools\build-desktop.js --check  # exit 1 if anything is stale
```

`release.ps1` käivitab ehituse ja iga värava, nii et väljalase ei saa saata
väljundit, mis on palettidest kõrvale triivinud.

<!-- source-digest: desktop/README.md sha256:1b166ae6a7cf8a5c -->
