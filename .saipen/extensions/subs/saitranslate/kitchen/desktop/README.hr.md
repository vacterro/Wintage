# Wintage za desktop aplikacije

Userscript temati web. Ovo tematizira programe oko njega, iz istih paleta, kako bi preglednik i aplikacije prestali biti nesložni oko toga što tamno zlato znači.

Iza svake odluke ovdje stoji jedno pravilo: **aplikacije se same ažuriraju i ažuriranje ne smije tiho ništa pokvariti.** Gdje cilj ima mjesto u vašem vlastitom profilu, tema ide tamo i preživljava ažuriranja. Gdje nema, instalater je napisan da se ponovno pokrene — i kaže to, umjesto da se pretvara da je trajan.

## GUI

Dvaput kliknite na **`Wintage Installer.vbs`** u korijenu repozitorija da ga otvorite bez prozora konzole ili pokrenite ovo izravno za dijagnostiku:

```powershell
powershell -File desktop\WintageInstaller.ps1
```

Popis tema s krugovima boja, ciljevi pronađeni na ovom računalu, živi Win95-pregled i svih dvadeset i jedan token boje kao uredive boje. Uređivanje bilo koje boje račva paletu u **Custom** umjesto da vam mijenja isporučenu temu. Ploča s desne strane prikazuje živi WCAG-kontrast za tri tokena koja nose tekst — paletu koja tamo padne build vrata ionako odbijaju, pa ju je bolje vidjeti prije Apply nego poslije.

Ciljevi su podijeljeni u dva popisa dostupna tipkovnicom: **MY APPS** sadrži prijenosne/izvorne alate CodeNomad, SAIPENVIEW, SmartVac i WildRift; **POPULAR APPS** sadrži Windows, OBS, terminale, uređivače i drugi instalirani softver. ALL/NONE i Apply/Revert djeluju na oba popisa bez promjene njihovog grupiranja.

Prozor nosi paletu koju će instalirati. To je najbrži dostupan pregled i održava alat poštenim: paleta koja ovaj prozor čini nečitljivim vidljivo je nečitljiva.

Apply delegira na `install.ps1`. Postoji točno jedna putanja koda koja instalira temu, pa se GUI ne može udaljiti od naredbenog retka.

## Naredbeni redak

```powershell
.\desktop\install.ps1                                  # što je ovdje, što je tematsko, s kojom paletom
.\desktop\install.ps1 -Target freebuff -Palette klite  # jedna aplikacija, jedna paleta
.\desktop\install.ps1 -Target all -Palette goldendefault # sve
.\desktop\install.ps1 -Target all -WhatIf              # reći što bi se promijenilo, ništa ne dirati
.\desktop\install.ps1 -Target freebuff -Revert         # vratiti jednu
```

`-Palette` je prema zadanim postavkama `goldendefault` (**Golden Default**). GUI se otvara na istoj paleti i provjerava svaki dostupni cilj. Prebojavanje već tematizirane aplikacije radi dok se pokreće; prva instalacija ne, jer je arhiva u upotrebi.

## Što svaki cilj zapravo može biti tematiziran

| cilj | mehanizam | preživljava ažuriranje aplikacije |
|---|---|---|
| `windows` | korisnički `.theme`: tamni način sustava/aplikacije, akcent i klasične uloge boja | da — instalirano u vašoj lokalnoj mapi Windows Themes |
| `browsers` | otkriva instalirane + prijenosne Chromium profile, priprema odabranu chrome temu i otvara preglednikove stranice potvrde Tampermonkey/teme | da nakon jednog **Load unpacked** po profilu |
| `terminal` | shema Windows Terminal + zadane postavke svih profila, Consolas 12 s aliasom | da — postavke su u vašem profilu |
| `conhost` | zadane `HKCU\Console` + svaki postojeći cmd/PowerShell profil | da — točan snimak dodirnutih vrijednosti |
| `obs` | OBS 30.2+ `.ovt` varijanta + aktivni ID teme u `user.ini` | da — živi u vašem profilu |
| `antigravity`, `vscode` | proširenje teme boja u `~/.antigravity/extensions` / `~/.vscode/extensions` | **da** — živi u vašem profilu |
| `freebuff`, `antigravity-app`, `codenomad` | Electron shim, pogledajte dolje | ne — ponovno pokrenite instalater |
| `claude` | Electron shim, zakrpljen na mjestu — pogledajte dolje | ne — ažuriranje stvara novu mapu `app-<verzija>` |
| `mpchc` | registar, tamna tema + tipografija OSD-a samo | ne — MPC-HC prepisuje svoje postavke pri izlasku |
| `obsidian` | društvena tema po trezoru, sve palete instalirane odjednom | **da** — živi u vašem trezoru |
| `saipenview` | prepisuje vlastite vrijednosti tokena `:root` u `style.css` | ne — izvorna datoteka; ponovno pokrenite nakon pulla |
| `discord` | CSS ubačen u vlastitu mapu tema BetterDiscorda | da |
| `totalcmd`, `totalcmd2` | ključevi `wincmd.ini` `[Colors]`; postojeći filtri nedavnih datoteka koriste boju poveznice palete | da — to je vaš ini |
| `smartvac`, `wildrift` | tablica tokena prepisana u vlastitom izvoru aplikacije | ne — izvorna datoteka; ponovno pokrenite nakon pulla |

### Uklanjanje oglasa FreeBuff

FreeBuff (desktop aplikacija AI asistenta) isporučuje vlastitu oglasnu mrežu: renderer paket (`resources/orchestrator/ui/assets/index-*.js`) prikazuje karticu `sponsored-ad` i banner niti, a orkestrator (`resources/orchestrator/orchestrator.js`) izlaže rute `/api/ad/slot|impression|click` koje pozivaju udaljenu oglasnu aukciju. Shim samo tematizira aplikaciju; ne dira te datoteke.

`desktop/patch-freebuff-ads.js` izrezuje oglase na razini bajtova:

- renderer: mjesta poziva kartice/bannera oglasa postaju `null`, a metode klijenta API-ja `adSlot` / `adImpression` / `adClick` postaju no-ops — ništa se ne prikazuje i nikakav `/api/ad/*` zahtjev ne napušta renderer;
- orkestrator: sve tri rute `/api/ad/*` prestaju pozivati oglasnu mrežu, a zahtjev za inline oglas uživo (`maybeRequestAd`) je kratko spojen.

Naziv paketa ugrađuje hash izgradnje, pa zakrpa otkriva trenutni paket iz `index.html` umjesto isporuke verzijom zaključanog sadržaja — to ju čini otpornom na ažuriranja. Originali se sigurnosno kopiraju u `_orig-backup-<vremenska oznaka>/` u instalacijsku mapu; `--revert` vraća najnoviji.

**Buduće verzije obrađuju se na dvije neovisne razine:**

1. **Bajtovska zakrpa s regex fallbackovima.** Svaki cilj ima točan niz za trenutnu izgradnju *i* fallback na regularni izraz usidren u ono što minifikator ne može preimenovati — literale putanje `/api/ad/*`, diskriminator protokola `case"ad":`, klasu `sponsored-ad` i postave `variant:"banner"` / `variant:"card"`. Orkestrator nije minificiran (čitljiva imena poput `maybeRequestAd` i `app.ads.slotAd`), pa njegovi točni nizovi traju dugo; renderer paket je minificiran, pa njegovi regex fallbackovi preuzimaju čim sljedeća izgradnja preimenuje njegove identifikatore.
2. **Blokiranje na razini shima (`targets/electron/shim.cjs`).** Potpuno neovisno o paketu: bilo koji fetch/XHR na `/api/ad/` URL odbija se unutar stranice, a svaki element čija klasa sadrži `sponsored-ad` skriva se čim se pojavi. Čak ni potpuno novi paket kojeg ovaj skript još nije naučio ne može prikazati oglas.

```powershell
node .\desktop\patch-freebuff-ads.js           # zakrpa (najprije sigurnosno kopira)
node .\desktop\patch-freebuff-ads.js --sound "C:\...\my.mp3"   # zakrpa + prilagođeni zvuk završetka (wav/mp3/ogg/flac/m4a/aac)
node .\desktop\patch-freebuff-ads.js --scan    # koje oglasne oznake nosi OVA izgradnja?
node .\desktop\patch-freebuff-ads.js --verify
node .\desktop\patch-freebuff-ads.js --revert
```

Pokreće se automatski kao dio `install.ps1 -Target freebuff` i mora se ponovno pokrenuti nakon svakog ažuriranja FreeBuffa (ažuriranja vraćaju standardne datoteke). Ako izgradnja promijeni oblik, skript imenuje cilj koji se više ne podudara — pokrenite `--scan` da vidite što nova izgradnja još nosi i osvježite nizove tamo.

**Zvuk završetka FreeBuff.** Renderer svira `chime-<hash>.mp3` kad završi potez. Zakrpa ga nalazi na isti način kao i paket (naziv ugrađuje hash izgradnje), pa `--sound <datoteka>` instalira vaš vlastiti zvuk (wav/mp3/ogg/flac/m4a/aac) preko njega i čuva standardnu datoteku kao `chime-*.mp3.bak`; `--revert` je vraća. `--verify` izvještava koji je aktivan.

### Gumb zvuka FreeBuff (GUI)

`WintageInstaller.ps1` ima mali gumb **FB SOUND** ispod stoga APPLY / REVERT. On samo pohranjuje *preferenciju*; `install.ps1 -Target freebuff` čita istu datoteku i prosljeđuje je zakrpi kao `--sound`, pa se oglasi i zvuk primjenjuju u jednom pokretanju:

- **Lijevi klik** — odaberite audio datoteku (OpenFileDialog, wav/mp3/ogg/flac/m4a/aac) i odmah je čujte: PCM WAV putem System.Media.SoundPlayer, svaki drugi format putem WPF MediaPlayer (Media Foundation, asinkrono, pa se prozor nikad ne zamrzava). Odabir se pamti u `%APPDATA%\Wintage\freebuff-sound.txt` (po računalu, izvan git check-outa, točno kao zapamćene mape izvornog koda).
- **Desni klik** — vrati preferenciju na standardni chime FreeBuffa (također zaustavlja bilo koji pregled koji se još svira).
- **COPY** — kopira odabrani zvuk u sam repozitorij (`sounds\freebuff.<ext>`, zadržavajući izvornu ekstenziju) i preusmjerava preferenciju na tu kopiju, tako da zvuk preživi brisanje ili premještanje izvorne datoteke. Omogućen samo dok je postavljen prilagođeni zvuk; ponovno kopiranje jednostavno prepisuje kopiju u repozitoriju. Mapa `sounds/` običan je git-slediv sadržaj, pa je njenim commitom zvuk preživljava i ponovne klonove.

Pregledavaju se samo prepoznati audio spremnici — zaglavlje se prvo opipa, pa se odabir koji nije audio najavljuje umjesto da tiho svira ništa.

Gumb prikazuje `ON` dok je postavljen prilagođeni zvuk; hover pokazuje putanju. Nakon toga primijenite cilj `freebuff` (označite FreeBuff + APPLY ili pokrenite `install.ps1 -Target freebuff` iz terminala) da stupi na snagu.

### Terminali

`terminal` upisuje shemu boja `Wintage` u svaku otkrivenu stabilnu, Preview ili neupakiranu datoteku postavki Windows Terminala i odabire je putem `profiles.defaults`, zajedno s konzolno sigurnim Consolas 12 i aliasanim tekstom. Izvorna datoteka čuva se bajt-po-bajt pokraj nje i `-Revert` je vraća.

`conhost` pokriva klasični `cmd.exe`, Windows PowerShell, konzolne profile Git CMD/Bash i druge postojeće podređene `HKCU\Console`. Upisuje potpunu tablicu od 16 boja palete i u korijenske zadane postavke i u svako postojeće prekrivanje, zatim vraća samo vrijednosti kojih se dotaknuo. Primjenjuje Consolas i tamo, jer proporcionalna Verdana sudara unutar mreže fiksnih ćelija koju koriste oba terminalna domaćina.

### Preglednici i Tampermonkey

`browsers` pronalazi Chrome, Edge, Brave, Cent, Vivaldi i Opera profile iz instaliranih lokacija i iz prijenosnog korijena na koji ga uputite (`-PortableRoot`, ili zapamćeni unos `portable` u `paths.json`). Njegov status prikazuje i broj profila i koliko ih sadrži Tampermonkey. Apply kopira odabranu pregledničku chrome temu u stabilnu mapu `%LOCALAPPDATA%\Wintage\browser-theme`, stavlja tu putanju u međuspremnik i otvara svaki točan profil na `chrome://extensions` plus stranicu Instaliraj/Ažuriraj userscripta Wintage. Profili bez Tampermonkeyja također dobivaju njegovu stranicu Chrome Web Storea.

Chromium namjerno zabranjuje tiho instaliranje proširenja izvan trgovine na neupravljanom Windows računalu. Prva instalacija pregledničke teme zato zahtijeva jednu potvrdu **Developer mode → Load unpacked** po profilu. Odaberite kopiranu putanju; nakon toga Wintage nastavlja zamjenjivati istu stabilnu mapu kad se palete mijenjaju. Potvrdite i **Install/Update** u Tampermonkeyju. Nijedna datoteka `Preferences`, Secure Preferences ili Tampermonkey LevelDB preglednika ne uređuje se iza leđa preglednika. Ako Tampermonkey nije bio prisutan, instalirajte ga s otvorene kartice trgovine i osvježite već otvorenu karticu `wintage.user.js` da dobijete zaslon Instaliraj.

### Windows

`windows` instalira i odmah aktivira sadržajno adresiran `%LOCALAPPDATA%\Microsoft\Windows\Themes\Wintage-<hash>.theme`. Kreće od aktivne teme i zamjenjuje samo dokumentirane odjeljke boja, pokazivača i vizualnog stila. Pozadina, zvukovi i ikone radne površine ostaju nepromijenjeni; pokazivači namjerno prelaze na instaliranu shemu `___CURRENT___`. Prva aktivna tema sprema se bajt-po-bajt kao `Wintage.original.theme`; promjene palete zadržavaju tu osnovnu liniju i `-Revert` je ponovno aktivira. Moderni Windows kontrole i dalje dolaze iz potpisanog vizualnog stila Aero — Wintage mijenja njegove podržane unose tamnog načina, akcenta i klasičnih sistemskih boja umjesto zamjene zaštićenih `.msstyles` datoteka. Aktivni i neaktivni naslovi dijele prigušenu boju podignute površine palete; svijetlo isticanje ostaje rezervirano za rubove teksta/odabira. Prethodni neaktivni akcent naslova zasebno se snima i `-Revert` ga točno vraća. Hash sadržaja daje Windowsu novi cilj pridruživanja datoteka kad se ista paleta ponovno gradi, pa ponovno primjenjivanje ažurirane palete nije zamijenjeno s no-op; zastarjela Wintage datoteka uklanja se nakon što Windows potvrdi novu kao aktivnu.

### OBS Studio

`obs` generira varijantu OBS 30.2+ preko održavane baze Yami Classic, instalira je u `%APPDATA%\obs-studio\themes` i upisuje njen stabilni ID teme u `user.ini`, tako da je odabrana Wintage paleta već odabrana pri sljedećem pokretanju. Zatvorite OBS prije Apply ili Revert: OBS prepisuje `user.ini` pri izlasku. Prva primjena sigurnosno kopira i prethodni odabir i bilo koju temu s istim imenom bajt-po-bajt.

### Electron aplikacije

`resources/app.asar` premješta se u `resources/app/app.asar` (njegov brat `app.asar.unpacked` premješta se s njim — to uparivanje je po nazivu datoteke i razdvajanje razbija svaki nativni modul), a mali `shim.cjs` zauzima oslobođeni slot `resources/app`. Shim ubrizgava stilski list i zatim učitava izvornu arhivu. **Nijedan bajt aplikacije nije prepisan**, samo premješten; `-Revert` ga premješta ravno natrag.

Stilski list nije napisan za te aplikacije — izvučen je iz `wintage.user.js`, pa svaka popravka faseti, trake za pomicanje i ljestvice tipova napravljena za preglednik stigne i ovdje, bez druge kopije koja trune.

Dvije napomene koje vrijedi imati unaprijed:

- Očigledni pristup — staviti `resources/app` pokraj arhive i osloniti se na to da ga Electron preferira — **ne radi i tiho pada**. Electron prvo traži `app.asar`. Aplikacija se savršeno pokrene i tema nikad ne radi.
- Shim je `.cjs`, ne `.js`, namjerno. Njegov `package.json` kopiran je iz vlastitog `package.json` aplikacije, pa aplikacija zadržava ime i verziju (ime odlučuje gdje živi userData — shim koji ga preimenuje premješta aplikaciju u prazan profil). Ako taj manifest kaže `"type": "module"`, `.js` shim umire na svom prvom `require`.

### Desktop aplikacija Claude: na mjestu i okvir u kojem zapravo crta

Claude ne može koristiti premještanje gore, jer je `OnlyLoadAppFromAsar` zalemljen — Electron učitava `resources/app.asar` i ništa drugo, pa shim u `resources/app` nikad ne može raditi. Umjesto toga zakrpljuje se **na mjestu**: arhiva se sigurnosno kopira, njen `main` u `package.json` prepisuje se na `"../wintage-shim.cjs"` (dopunjeno na istu duljinu bajtova, da svaki pomak u arhivi ostane važeći), a hash integriteta po datoteci ažurira se da odgovara. `-Revert` vraća sigurnosnu kopiju.

Instalater i dalje čita fuses **prije nego što išta premjesti** i odbija s razlogom kad ga blokiraju — `EnableEmbeddedAsarIntegrityValidation` bi prouzročio pad prepisivanja gore pri pokretanju umjesto pri instalaciji. Provjerite bilo koju aplikaciju sami:

```powershell
node ..\tools\electron-fuses.js "<putanja do exe aplikacije>"
```

Druga polovica ovoga bila je mnogo tiši problem. `BrowserWindow` od Claudea prikazuje tanku ljusku i **cijela vidljiva aplikacija je `WebContentsView`** pričvršćena na nju. Shim je nekad hakovao `browser-window-created`, pa je ubrizgavao stilski list u ljusku, javljao uspjeh u `wintage-status.txt` i nije mijenjao ništa što ste mogli vidjeti. Sada haka `web-contents-created`, koji pokriva sadržaj prozora, `WebContentsView`-ove, `BrowserView`-ove, `<webview>` goste i skočne prozore jednako.

### Obsidian

Društvena tema upisuje se u `.obsidian/themes/` svakog trezora — svih šesnaest paleta odjednom, točno kao cilj VS Code, pa prebacujete između njih u **Settings → Appearance** bez ponovnog pokretanja ičega. Predložak je izveden iz ručno rađene teme `VintageWin95` koja je već bila u trezoru, svaka boja zamijenjena tokenom kojem je odgovarala. `-Palette <slug>` postavlja koja je aktivna pri instalaciji; `appearance.json` se prvo sigurnosno kopira, a `-Revert` uklanja samo `Wintage *` teme i vraća vaš prethodni odabir — ručno rađena tema u istom trezoru nikad se ne dira.

### SAIPENVIEW

Njegovo sučelje već deklarira imena tokena Wintage u vlastitom `:root`, pa ova zakrpa prepisuje **samo vrijednosti tokena** — nikad selektor, font, širinu ruba ili padding. Ništa što utječe na box model ne mijenja se, pa se tekst ne može pomaknuti. To je namjerno: prethodni pristup je dodavao cijeli preglednički stilski list odozgo, a `wintage.css` je napisan za proizvoljne web stranice — univerzalni selektori koji nameću font, ljestvicu veličina, 2px rubove i visine kontrola. Na aplikaciji koja već ima vlastiti raspored to pomiče sve.

Provjereno maskiranjem svakog hexa i usporedbom sa sigurnosnom kopijom: strukturno identično, razlikuju se samo literali boja. `--link` se izvještava kao nedeklariran tamo (njegove markdown poveznice čitaju `--accentTeal`, koje ovo postavlja) umjesto ubrizganog — dodavanje varijable koju aplikacija nikad ne čita bila bi mrtva težina.

### MPC-HC (K-Lite)

Izvorni Win32, bez stilskog lista i bez točke ubrizgavanja, a boje njegove tamne teme kompilirane su u program — nijedna vrijednost registra ih ne izlaže. Dakle, ovaj cilj **ne može nositi paletu**. Što radi: uključuje tamnu temu i primjenjuje pravila tipografije UI.md na OSD, što je jedina površina koju MPC-HC dopušta korisniku kontrolirati. Prethodne postavke prvo se izvoze u `desktop/backup/mpc-hc-settings.reg`.

Zatvorite MPC-HC prije primjene: prepisuje svoje postavke pri izlasku.

## Ponovna izgradnja

Sve pod `desktop/out/` generira se iz `themes/*.json`. Ne prati se u gitu (T-160), pa svježi klon mora to izgraditi jednom prije instalacije:

```powershell
node ..\tools\build-desktop.js          # ponovno izgradi sve ciljeve
node ..\tools\build-desktop.js --check  # izađi s 1 ako je nešto zastarjelo
```

`release.ps1` pokreće izgradnju i svaka vrata, pa izdanje ne može poslati izlaz koji je odlutao od paleta.

<!-- source-digest: desktop/README.md sha256:1b166ae6a7cf8a5c -->
