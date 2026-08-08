# Wintage asztali alkalmazásokhoz

A userscript a webet temázza. Ez a körülötte lévő programokat temázza, ugyanazokból a palettákból, így a böngésző és az alkalmazások többé nem vitatkoznak azon, mit jelent a sötét arany.

Minden döntés mögött egyetlen szabály áll: **az alkalmazások magukat frissítik, és egy frissítés nem törhet el csendben semmit.** Ahol egy célpontnak van helye a saját profilodban, a téma oda kerül, és túléli a frissítéseket. Ahol nincs, az telepítő úgy van megírva, hogy újra lehessen futtatni — és ezt meg is mondja, ahelyett hogy úgy tenne, mintha megmaradt volna.

## A GUI

Kattints duplán a repo gyökerében található **`Wintage Installer.vbs`** fájlra, hogy konzolablak nélkül nyíljon meg, vagy futtasd közvetlenül diagnosztikához:

```powershell
powershell -File desktop\WintageInstaller.ps1
```

Témalista színmintákkal, a gépen talált célpontok, élő Win95-előnézet, és mind a huszonegy színtoken szerkeszthető mintaként. Bármely minta szerkesztése a palettát **Custom**-ba forkolja, ahelyett hogy észrevétlenül megváltoztatna egy szállított témát. A jobb oldali panel élő WCAG-kontrasztot mutat a szöveget hordozó három tokenhez — a paletta, amely ott FAIL-t kap, úgyis elutasításra kerül az építőkapuban, ezért jobb még az Apply előtt látni, mint utána.

A célpontok két billentyűzettel elérhető listára vannak osztva: a **MY APPS** a hordozható/source-tree CodeNomad, SAIPENVIEW, SmartVac és WildRift eszközöket tartalmazza; a **POPULAR APPS** a Windowst, OBS-t, terminálokat, szerkesztőket és a többi telepített szoftvert. Az ALL/NONE és az Apply/Revert mindkét listára működik anélkül, hogy megváltoztatná a csoportosítást.

Az ablak azt a palettát viseli, amelyet épp telepíteni készül. Ez a leggyorsabb elérhető előnézet, és az eszközt is őszintén tartja: egy paletta, amely ezt az ablakot olvashatatlanná teszi, láthatóan olvashatatlan.

Az Apply a `install.ps1`-t hívja meg. Pontosan egy kódútvonal telepít témát, így a GUI nem sodródhat el a parancssortól.

## A parancssor

```powershell
.\desktop\install.ps1                                  # mi van itt, mi van temázva, melyik palettával
.\desktop\install.ps1 -Target freebuff -Palette klite  # egy alkalmazás, egy paletta
.\desktop\install.ps1 -Target all -Palette goldendefault # minden
.\desktop\install.ps1 -Target all -WhatIf              # mondd meg, mi változna, ne érj hozzá semmihez
.\desktop\install.ps1 -Target freebuff -Revert         # vonj vissza egyet
```

A `-Palette` alapértelmezése a `goldendefault` (**Golden Default**). A GUI ugyanazon a palettán nyílik meg, és minden elérhető célpontot ellenőriz. Egy már temázott alkalmazás újrafestése működik, miközben fut; az első telepítés nem, mert az archívum foglalt.

## Mit tud ténylegesen temázni az egyes célpontok

| célpont | mechanizmus | túléli az alkalmazásfrissítést |
|---|---|---|
| `windows` | felhasználói `.theme`: sötét rendszer/alkalmazás mód, accent és klasszikus színszerepek | igen — a helyi Windows Themes mappádba települ |
| `browsers` | észleli a telepített + hordozható Chromium-profilokat, előkészíti a kiválasztott chrome témát és megnyitja a böngésző tulajdonában lévő Tampermonkey/téma megerősítő oldalakat | igen, egy **Load unpacked** után profilonként |
| `terminal` | Windows Terminal séma + minden profil alapértelmezései, Consolas 12 aliasolt | igen — a beállítások a profilodban vannak |
| `conhost` | `HKCU\Console` alapértelmezések + minden meglévő cmd/PowerShell profil | igen — az érintett értékek pontos pillanatképe |
| `obs` | OBS 30.2+ `.ovt` változat + aktív `user.ini` témaazonosító | igen — a profilodban él |
| `antigravity`, `vscode` | színtéma-kiterjesztés a `~/.antigravity/extensions` / `~/.vscode/extensions` mappában | **igen** — a profilodban él |
| `freebuff`, `antigravity-app`, `codenomad` | Electron shim, lásd lentebb | nem — futtasd újra az telepítőt |
| `claude` | Electron shim, helyben javítva — lásd lentebb | nem — egy frissítés új `app-<version>` mappát készít |
| `mpchc` | rendszerleíró adatbázis, csak sötét téma + OSD tipográfia | nem — az MPC-HC kilépéskor felülírja a beállításait |
| `obsidian` | közösségi téma boltonként, minden paletta egyszerre telepítve | **igen** — a vaultodban él |
| `saipenview` | felülírja a saját `:root` token értékeit a `style.css`-ben | nem — forrásfájl; futtasd újra pull után |
| `discord` | CSS a BetterDiscord saját téma mappájába dobva | igen |
| `totalcmd`, `totalcmd2` | `wincmd.ini` `[Colors]` kulcsok; a meglévő friss-fájl szűrők a paletta link színét használják | igen — a te ini-d |
| `smartvac`, `wildrift` | token tábla felülírva az alkalmazás saját forrásában | nem — forrásfájl; futtasd újra pull után |

### FreeBuff hirdetéseltávolítás

A FreeBuff (az AI-asszisztens asztali alkalmazás) saját hirdetési hálózatot szállít: a renderer bundle (`resources/orchestrator/ui/assets/index-*.js`) `sponsored-ad` kártyát és szál-bannert renderel, az orchestrator pedig (`resources/orchestrator/orchestrator.js`) `/api/ad/slot|impression|click` útvonalakat tesz elérhetővé, amelyek a távoli hirdetésaukciót hívják. A shim csak temázza az alkalmazást; nem nyúl ezekhez a fájlokhoz.

A `desktop/patch-freebuff-ads.js` bájtszinten vágja ki a hirdetéseket:

- renderer: a hirdetéskártya/banner hívási helyek `null`-ok lesznek, az `adSlot` / `adImpression` / `adClick` API-kliens metódusok pedig no-op-k — semmi nem renderelődik, és a rendererből nem indul `/api/ad/*` kérés;
- orchestrator: mindhárom `/api/ad/*` útvonal leáll, hogy a hirdetési hálózatot hívja, és az élő körös inline hirdetési kérés (`maybeRequestAd`) rövidre van zárva.

A bundle fájlnév build-hash-t ágyaz be, így a javítás a `index.html`-ből deríti ki az aktuális bundle-t, ahelyett hogy verzióhoz kötött payloadot szállítana — ez az, amitől túléli a frissítéseket. Az eredetiek `_orig-backup-<timestamp>/` mappába vannak mentve a telepítési könyvtárban; a `--revert` a legújabbat állítja vissza.

**A jövőbeli verziókat két független réteg kezeli:**

1. **Bájt-javítás regex tartalékokkal.** Minden célpontnak van pontos karakterlánca az aktuális buildhez *és* reguláris kifejezéses tartaléka, amely arra horgonyoz, amit egy minifier nem tud átnevezni — a `/api/ad/*` útvonalliterálokra, a `case"ad":` protokoll-diszkriminátorra, a `sponsored-ad` osztályra és a `variant:"banner"` / `variant:"card"` elhelyezésekre. Az orchestrator nincs minifikálva (olvasható nevek, mint `maybeRequestAd` és `app.ads.slotAd`), így a pontos karakterláncai sokáig érvényesek; a renderer bundle minifikált, így a regex-tartalékok lépnek be abban a pillanatban, amikor a következő build átnevezi az azonosítóit.
2. **Shim-szintű blokkolás (`targets/electron/shim.cjs`).** Teljesen független a bundle-től: minden `/api/ad/` URL-hez menő fetch/XHR elutasításra kerül az oldal belsejében, és minden olyan elem, amelynek osztálya `sponsored-ad`-t tartalmaz, elrejtésre kerül abban a pillanatban, amikor megjelenik. Még egy teljesen új bundle is, amelyet ez a script még nem ismert meg, nem tud hirdetést felmutatni.

```powershell
node .\desktop\patch-freebuff-ads.js           # javítás (először mentés)
node .\desktop\patch-freebuff-ads.js --sound "C:\...\my.mp3"   # javítás + egyedi befejezési hang (wav/mp3/ogg/flac/m4a/aac)
node .\desktop\patch-freebuff-ads.js --scan    # milyen hirdetésmarkereket hordoz EZ a build?
node .\desktop\patch-freebuff-ads.js --verify
node .\desktop\patch-freebuff-ads.js --revert
```

A `install.ps1 -Target freebuff` részeként automatikusan fut, és minden FreeBuff-frissítés után újra kell futtatni (a frissítések visszaállítják a gyári fájlokat). Ha egy build megváltoztatja a formáját, a script megnevezi a célpontot, amelyhez már nem illeszkedett — futtasd a `--scan`-t, hogy lásd, mit hordoz még az új build, és frissítsd ott a karakterláncokat.

**FreeBuff befejezési hang.** A renderer a `chime-<hash>.mp3` fájlt játssza le, amikor egy kör befejeződik. A javítás ugyanúgy találja meg, ahogy a bundle-t (a név build-hash-t ágyaz be), így a `--sound <file>` a saját hangodat (wav/mp3/ogg/flac/m4a/aac) helyezi a helyére, és a gyári fájlt `chime-*.mp3.bak`-ként tartja meg; a `--revert` visszaállítja. A `--verify` jelenti, hogy melyik van életben.

### FreeBuff hang gomb (GUI)

A `WintageInstaller.ps1`-ben van egy kis **FB SOUND** gomb az APPLY / REVERT gombok alatt. Csak *preferenciát* tárol; a `install.ps1 -Target freebuff` ugyanezt a fájlt olvassa, és `--sound`-ként adja a javításnak, így a hirdetések és a hang egy futtatásban kerülnek alkalmazásra:

- **Bal kattintás** — válassz hangfájlt (OpenFileDialog, wav/mp3/ogg/flac/m4a/aac), és azonnal hallod lejátszva: PCM WAV a System.Media.SoundPlayer-en keresztül, minden más formátum egy WPF MediaPlayer-en (Media Foundation, aszinkron, így az ablak soha nem fagy le). A választás megjegyzésre kerül a `%APPDATA%\Wintage\freebuff-sound.txt` fájlban (gépenként, a git-checkouton kívül, pontosan úgy, mint a megjegyzett source-tree mappák).
- **Jobb kattintás** — törli a preferenciát vissza a FreeBuff gyári csengésére (és leállít minden, még játszó előnézetet).
- **COPY** — a kiválasztott hangot magába a repóba másolja (`sounds\freebuff.<ext>`, megtartva a forrás kiterjesztését), és a preferenciát erre a másolatra irányítja, így a hang túléli, ha az eredeti fájlt törlik vagy áthelyezik. Csak akkor engedélyezett, ha egyedi hang van beállítva; az újramásolás egyszerűen felülírja a repó-másolatot. A `sounds/` mappa sima, git-követhető tartalom, így a commitolással a hang az újraklónozásokat is túléli.

Csak felismert hangkonténerek kerülnek előnézetbe — a fejléc először megvizsgálásra kerül, így a nem hangfájl választás bejelentésre kerül, ahelyett hogy némán nem játszana semmit.

A gomb **ON**-t mutat, amíg egyedi hang van beállítva; felette húzva az útvonalat mutatja. Utána alkalmazd a `freebuff` célpontot (pipáld be a FreeBuff-ot + APPLY, vagy futtasd a `install.ps1 -Target freebuff` parancsot egy terminálból), hogy érvénybe lépjen.

### Terminálok

A `terminal` egy `Wintage` színsémát ír minden észlelt stabil, Preview vagy nem csomagolt Windows Terminal beállításfájlba, és a `profiles.defaults`-on keresztül kiválasztja, a konzolbiztos Consolas 12-vel és aliasolt szöveggel együtt. Az eredeti fájl bájtonként megőrződik mellette, és a `-Revert` visszaállítja.

A `conhost` a klasszikus `cmd.exe`-t, a Windows PowerShell-t, a Git CMD/Bash konzolprofilokat és más meglévő `HKCU\Console` gyerekeket fedi le. A paletta teljes 16-színű tábláját beírja a gyökér alapértelmezésekbe és minden meglévő felülírásba, majd csak az általa érintett értékeket állítja vissza. Itt is Consolas-t alkalmaz, mert az arányos Verdana ütközik a mindkét terminálhost által használt fix szélességű cellarácsban.

### Böngészők és Tampermonkey

A `browsers` Chrome, Edge, Brave, Cent, Vivaldi és Opera profilokat talál meg telepített helyekről és abból a hordozható gyökérből, ahová mutatsz (`-PortableRoot`, vagy a `paths.json`-ban megjegyzett `portable` bejegyzés). Az állapota a profilok számát és azt is mutatja, hányban van Tampermonkey. Az Apply a kiválasztott böngésző-chrome témát a stabil `%LOCALAPPDATA%\Wintage\browser-theme` mappába másolja, ezt az útvonalat a vágólapra teszi, és minden pontos profilt megnyit a `chrome://extensions` címen, plusz a Wintage userscript Install/Update oldalát. A Tampermonkey nélküli profilok a Chrome Web Store oldalát is megkapják.

A Chromium szándékosan tiltja a nem üzleti célú, off-store kiterjesztéstelepítést egy nem felügyelt Windows gépen. Ezért az első böngészőtéma-telepítés profilonként egy **Developer mode → Load unpacked** megerősítést igényel. Válaszd a másolt útvonalat; ezután a Wintage továbbra is ugyanazt a stabil mappát cseréli, amikor a paletták változnak. A Tampermonkey-ben is erősítsd meg az **Install/Update** gombot. A böngésző háta mögött nem módosul egyetlen `Preferences`, Secure Preferences vagy Tampermonkey LevelDB fájl sem. Ha a Tampermonkey nem volt jelen, telepítsd a megnyitott bolt-lapról, és frissítsd a már megnyitott `wintage.user.js` lapot az Install képernyőhöz.

### Windows

A `windows` telepíti és azonnal aktiválja a tartalom-címzett `%LOCALAPPDATA%\Microsoft\Windows\Themes\Wintage-<hash>.theme` fájlt. Az aktív témából indul, és csak a dokumentált szín-, kurzor- és vizuálisstílus-szakaszokat cseréli. A háttérkép, a hangok és az asztali ikonok változatlanok maradnak; a kurzorok szándékosan a telepített `___CURRENT___` sémára váltanak. Az első aktív téma bájtonként elmentésre kerül `Wintage.original.theme` néven; a palettaváltozások ezt az alapvonalat tartják meg, a `-Revert` pedig újra aktiválja. A modern Windows-vezérlők továbbra is az aláírt Aero vizuális stílusból jönnek — a Wintage a támogatott sötét módját, accentjét és klasszikus rendszerszín-bemeneteit változtatja, ahelyett hogy a védett `.msstyles` fájlokat cserélné. Az aktív és az inaktív feliratok megosztják a paletta tompított, kiemelt felszín színét; a fényes highlight a szöveg/kijelölés éleire van fenntartva. Az előző inaktív felirat-accent külön pillanatfelvételre kerül, és a `-Revert` pontosan visszaállítja. A tartalom-hash új fájltársítási célt ad a Windowsnak, amikor ugyanaz a paletta újraépül, így a frissített paletta újraalkalmazását nem tévesztik össze a no-op-pal; a felváltott Wintage-fájl eltávolításra kerül, miután a Windows megerősíti az új aktiválását.

### OBS Studio

A `obs` egy OBS 30.2+ változatot generál a karbantartott Yami Classic alapra, a `%APPDATA%\obs-studio\themes` mappába telepíti, és a stabil témaazonosítóját a `user.ini`-be írja, így a kiválasztott Wintage-paletta a következő indításkor már ki van választva. Az Apply vagy Revert előtt zárd be az OBS-t: az OBS kilépéskor felülírja a `user.ini` fájlt. Az első alkalmazás bájtonként menti az előző kijelölést és minden azonos nevű témát.

### Electron alkalmazások

A `resources/app.asar` áthelyezésre kerül a `resources/app/app.asar` útvonalra (az `app.asar.unpacked` testvére vele mozog — ez a párosítás fájlnév alapú, és a szétválasztás minden natív modult eltör), és egy kis `shim.cjs` foglalja el a megüresedett `resources/app` helyet. A shim injektálja a stíluslapot, majd betölti az eredeti archívumot. **Egyetlen alkalmazás-bájtot sem írnak át**, csak áthelyezés történik; a `-Revert` egyenesen visszamozgatja.

A stíluslap ezekhez az alkalmazásokhoz nincs megírva — a `wintage.user.js`-ből van kinyerve, így minden, a böngészőhöz készített bevel, scrollbar és tipográfia-javítás ide is eljut, második, rothadó másolat nélkül.

Két megjegyzés, amelyet érdemes előre tudni:

- A kézenfekvő megközelítés — a `resources/app` az archívum mellé dobása, és az Electronra bízni, hogy előnyben részesíti — **nem működik, és némán megbukik**. Az Electron először az `app.asar`-t keresi. Az alkalmazás tökéletesen elindul, és a téma soha nem fut.
- A shim szándékosan `.cjs`, nem `.js`. A `package.json`-je az alkalmazás sajátjából van másolva, így az alkalmazás megtartja a nevét és a verzióját (a név dönti el, hol él a userData — egy shim, amely átnevezi, üres profilba mozgatja az alkalmazást). Ha ez a manifest `"type": "module"`-t mond, egy `.js` shim az első `require`-nél meghal.

### Claude asztali alkalmazása: helyben, és a keret, amelyben valójában rajzol

A Claude nem tudja használni a fenti áthelyezést, mert az `OnlyLoadAppFromAsar` be van égetve — az Electron a `resources/app.asar` fájlt tölti be, és semmi mást, így a `resources/app` mappában lévő shim soha nem futhat. Ehelyett **helyben** van javítva: az archívumról mentés készül, a `package.json` `main` értéke `"../wintage-shim.cjs"`-re íródik át (ugyanarra a bájthosszra párnázva, így az archívum minden offsetje érvényes marad), és a fájlonkénti integritás-hash frissítésre kerül, hogy egyezzen. A `-Revert` visszaállítja a mentést.

Az telepítő **mielőtt bármit mozgatna** leolvassa a fuse-okat, és indoklással megtagadja, ha azok blokkolják — az `EnableEmbeddedAsarIntegrityValidation` a fenti átírást indításkor meghiúsítaná, nem pedig telepítéskor. Nézd meg bármelyik alkalmazást magad:

```powershell
node ..\tools\electron-fuses.js "<path to the app's exe>"
```

Ennek a második fele sokkal csendesebb probléma volt. Claude `BrowserWindow`-ja vékony héjat renderel, és a **teljes látható alkalmazás egy `WebContentsView`**, amely hozzá van kapcsolva. A shim korábban a `browser-window-created`-re akaszkodott, így a stíluslapot a héjba injektálta, sikert jelentett a `wintage-status.txt`-nek, és semmit sem változtatott, ami látható volt. Most a `web-contents-created`-re akaszkodik, amely lefedi az ablak tartalmait, a `WebContentsView`-kat, a `BrowserView`-okat, a `<webview>` vendégeket és a popup-okat egyaránt.

### Obsidian

Egy közösségi téma kerül minden vault `.obsidian/themes/` mappájába — mind a tizenhat paletta egyszerre, pontosan mint a VS Code célpontnál, így a **Settings → Appearance** menüben váltogathatsz közöttük újrafuttatás nélkül. A sablon a vaultban már meglévő, kézzel készített `VintageWin95` témából származik, minden szín a tokenre cserélve, amelynek megfelelt. A `-Palette <slug>` határozza meg, melyik legyen aktív telepítéskor; az `appearance.json` előbb mentésre kerül, a `-Revert` pedig csak a `Wintage *` témákat távolítja el, és visszaállítja az előző választásod — a kézzel készített téma ugyanabban a vaultban soha nincs megérintve.

### SAIPENVIEW

A frontendje már deklarálja a Wintage tokenneveket a saját `:root`-jában, így ez a javítás **csak a token értékeket** írja át — soha szelektort, fontot, szegélyszélességet vagy paddinget. Semmi, ami a box modellt érinti, nem változik, így a szöveg nem tud elmozdulni. Ez szándékos: a korábbi megközelítés a teljes böngésző-stíluslapot a tetejére fűzte, a `wintage.css` pedig tetszőleges weboldalakra van írva — univerzális szelektorok, amelyek kényszerítik a fontot, a méret-létrát, a 2px-es szegélyeket és a vezérlőmagasságokat. Egy olyan alkalmazáson, amelynek már van saját elrendezése, ez mindent elmozdít.

Ellenőrizve: minden hex elmaszkolása és a mentéssel való diffelés után — szerkezetileg azonos, csak a színliterálok különböznek. A `--link` nincs ott deklarálva (a markdown linkjei `--accentTeal`-t olvasnak, amelyet ez beállít), így nem kerül beinjektálásra — egy változó hozzáadása, amelyet az alkalmazás soha nem olvas, holt teher lenne.

### MPC-HC (K-Lite)

Natív Win32, nincs stíluslap és nincs injektálási pont, és a sötét témájának színei a programba vannak fordítva — egyetlen rendszerleíró érték sem teszi őket elérhetővé. Így ez a célpont **nem tud palettát hordozni**. Amit csinál: bekapcsolja a sötét témát, és a UI.md tipográfiai szabályait alkalmazza az OSD-re, amely az egyetlen felület, amelyet az MPC-HC felhasználó vezérelhet. Az előző beállítások előbb a `desktop/backup/mpc-hc-settings.reg` fájlba exportálódnak.

Alkalmazás előtt zárd be az MPC-HC-t: kilépéskor felülírja a beállításait.

## Újraépítés

Minden a `desktop/out/` alatt a `themes/*.json`-ból generálódik. Nem git-követett (T-160), így egy friss klónnak egyszer fel kell építenie, mielőtt telepítene:

```powershell
node ..\tools\build-desktop.js          # építsd újra az összes célpontot
node ..\tools\build-desktop.js --check  # 1-es kilépési kód, ha valami elavult
```

A `release.ps1` futtatja a buildet és minden kaput, így egy kiadás nem szállíthat olyan kimenetet, amely eltávolodott a palettáktól.

<!-- source-digest: desktop/README.md sha256:1b166ae6a7cf8a5c -->
