# Wintage pentru aplicații desktop

Userscript-ul teme web-ul. Acesta teme programele din jurul lui, din aceleași palete, astfel încât browserul și aplicațiile încetează să se contrazică despre ce înseamnă auriu-închis.

Există o singură regulă în spatele fiecărei decizii de aici: **aplicațiile se actualizează singure, iar o actualizare nu trebuie să strice nimic în tăcere.** Acolo unde o țintă are un loc în propriul tău profil, tema stă acolo și supraviețuiește actualizărilor. Acolo unde nu are, installer-ul este scris să fie re-rulat — și o spune, în loc să pretindă că a persistat.

## GUI-ul

Fă dublu-clic pe **`Wintage Installer.vbs`** din rădăcina repo-ului pentru a-l deschide fără fereastră de consolă, sau rulează asta direct pentru diagnosticare:

```powershell
powershell -File desktop\WintageInstaller.ps1
```

Listă de teme cu mostre de culoare, țintele găsite pe această mașină, o previzualizare Win95 live și toate cele douăzeci și unu de tokenuri de culoare ca mostre editabile. Editarea oricărei mostre duce paleta în **Custom** în loc să schimbe o temă livrată pe sub tine. Panoul din dreapta arată contrastul WCAG live pentru cele trei tokenuri care poartă text — o paletă care FAIL-ează acolo este oricum refuzată de poarta de build, deci e mai bine să o vezi înainte de Apply decât după.

Țintele sunt împărțite în două liste accesibile de la tastatură: **MY APPS** conține instrumentele portabile/source-tree CodeNomad, SAIPENVIEW, SmartVac și WildRift; **POPULAR APPS** conține Windows, OBS, terminale, editoare și restul software-ului instalat. ALL/NONE și Apply/Revert operează pe ambele liste fără să le schimbe gruparea.

Fereastra poartă paleta pe care urmează să o instaleze. Asta este cea mai rapidă previzualizare disponibilă și ține instrumentul onest: o paletă care face această fereastră ilizibilă este vizibil ilizibilă.

Apply apelează în exterior `install.ps1`. Există exact o cale de cod care instalează o temă, deci GUI-ul nu poate deriva departe de linia de comandă.

## Linia de comandă

```powershell
.\desktop\install.ps1                                  # ce e aici, ce e tematizat, cu ce paletă
.\desktop\install.ps1 -Target freebuff -Palette klite  # o aplicație, o paletă
.\desktop\install.ps1 -Target all -Palette goldendefault # tot
.\desktop\install.ps1 -Target all -WhatIf              # spune ce s-ar schimba, nu atinge nimic
.\desktop\install.ps1 -Target freebuff -Revert         # anulează una
```

`-Palette` este implicit `goldendefault` (**Golden Default**). GUI-ul se deschide pe aceeași paletă și verifică fiecare țintă disponibilă. Repictarea unei aplicații deja tematizate funcționează în timp ce rulează; o primă instalare nu, pentru că arhiva este în uz.

## Cât de mult poate fi tematizată fiecare țintă

| țintă | mecanism | supraviețuiește unei actualizări de aplicație |
|---|---|---|
| `windows` | `.theme` de utilizator: mod întunecat al sistemului/aplicației, roluri de culoare accent și clasice | da — instalat în dosarul tău local Windows Themes |
| `browsers` | detectează profilurile Chromium instalate + portabile, pregătește tema chrome selectată și deschide paginile de confirmare Tampermonkey/temă deținute de browser | da după un **Load unpacked** per profil |
| `terminal` | schemă Windows Terminal + setările implicite pentru toate profilurile, Consolas 12 aliased | da — setările sunt în profilul tău |
| `conhost` | `HKCU\Console` implicite + fiecare profil cmd/PowerShell existent | da — snapshot exact al valorilor atinse |
| `obs` | variantă OBS 30.2+ `.ovt` + ID-ul de temă activ din `user.ini` | da — trăiește în profilul tău |
| `antigravity`, `vscode` | extensie de temă de culoare în `~/.antigravity/extensions` / `~/.vscode/extensions` | **da** — trăiește în profilul tău |
| `freebuff`, `antigravity-app`, `codenomad` | shim Electron, vezi mai jos | nu — re-rulează installer-ul |
| `claude` | shim Electron, patch-uit pe loc — vezi mai jos | nu — o actualizare face un dosar nou `app-<version>` |
| `mpchc` | registry, doar temă întunecată + tipografie OSD | nu — MPC-HC își rescrie setările la ieșire |
| `obsidian` | temă de comunitate per vault, toate paletele instalate deodată | **da** — trăiește în vault-ul tău |
| `saipenview` | rescrie propriile valori de token `:root` în `style.css` | nu — un fișier sursă; re-rulează după un pull |
| `discord` | CSS aruncat în propriul dosar de teme al BetterDiscord | da |
| `totalcmd`, `totalcmd2` | chei `wincmd.ini` `[Colors]`; filtrele existente de fișiere recente folosesc culoarea linkului din paletă | da — e ini-ul tău |
| `smartvac`, `wildrift` | tabelul de tokenuri rescris în sursa proprie a aplicației | nu — un fișier sursă; re-rulează după un pull |

### Eliminarea reclamelor FreeBuff

FreeBuff (aplicația desktop a asistentului AI) livrează propria rețea de reclame: bundle-ul renderer (`resources/orchestrator/ui/assets/index-*.js`) randează un card `sponsored-ad` și un banner de thread, iar orchestratorul (`resources/orchestrator/orchestrator.js`) expune rutele `/api/ad/slot|impression|click` care apelează licitația remote de reclame. Shim-ul doar teme aplicația; nu atinge acele fișiere.

`desktop/patch-freebuff-ads.js` taie reclamele la nivel de byte:

- renderer: locurile de apel ale cardului/bannerului devin `null`, iar metodele clientului API `adSlot` / `adImpression` / `adClick` devin no-op — nu se randează nimic, și nicio cerere `/api/ad/*` nu părăsește renderer-ul;
- orchestrator: toate cele trei rute `/api/ad/*` încetează să mai apeleze rețeaua de reclame, iar cererea inline de reclamă la runda live (`maybeRequestAd`) este scurtcircuitată.

Numele fișierului bundle încorporează un hash de build, așa că patch-ul descoperă bundle-ul curent din `index.html` în loc să livreze un payload blocat de versiune — asta îl face să supraviețuiască actualizărilor. Originalele sunt salvate în `_orig-backup-<timestamp>/` în directorul de instalare; `--revert` restaurează cel mai recent.

**Versiunile viitoare sunt tratate la două straturi independente:**

1. **Byte patch cu fallback-uri regex.** Fiecare țintă are un șir exact pentru build-ul curent *și* un fallback cu expresie regulată ancorat pe ce un minifier nu poate redenumi — literalii de cale `/api/ad/*`, discriminatorul de protocol `case"ad":`, clasa `sponsored-ad` și plasările `variant:"banner"` / `variant:"card"`. Orchestratorul nu este minificat (nume lizibile ca `maybeRequestAd` și `app.ads.slotAd`), deci șirurile sale exacte rezistă mult timp; bundle-ul renderer este minificat, deci fallback-urile regex preiau controlul în momentul în care următorul build își redenumește identificatorii.
2. **Blocare la nivel de shim (`targets/electron/shim.cjs`).** Independent de bundle cu totul: orice fetch/XHR către un URL `/api/ad/` este respins în interiorul paginii, iar orice element a cărui clasă conține `sponsored-ad` este ascuns în clipa în care apare. Chiar și un bundle complet nou pe care acest script nu l-a învățat încă nu poate scoate o reclamă la suprafață.

```powershell
node .\desktop\patch-freebuff-ads.js           # patch (face întâi backup)
node .\desktop\patch-freebuff-ads.js --sound "C:\...\my.mp3"   # patch + sunet personalizat de finalizare (wav/mp3/ogg/flac/m4a/aac)
node .\desktop\patch-freebuff-ads.js --scan    # ce markeri de reclamă poartă ACEST build?
node .\desktop\patch-freebuff-ads.js --verify
node .\desktop\patch-freebuff-ads.js --revert
```

Rulează automat ca parte din `install.ps1 -Target freebuff` și trebuie re-rulat după fiecare actualizare FreeBuff (actualizările restaurează fișierele standard). Dacă un build își schimbă forma, scriptul numește ținta care nu s-a mai potrivit — rulează `--scan` ca să vezi ce poartă încă noul build și reîmprospătează șirurile de acolo.

**Sunetul de finalizare FreeBuff.** Renderer-ul redă `chime-<hash>.mp3` când o rundă se termină. Patch-ul îl găsește la fel cum găsește bundle-ul (numele încorporează un hash de build), deci `--sound <file>` instalează propriul tău audio (wav/mp3/ogg/flac/m4a/aac) peste el și păstrează fișierul standard ca `chime-*.mp3.bak`; `--revert` îl restaurează. `--verify` raportează care este live.

### Butonul de sunet FreeBuff (GUI)

`WintageInstaller.ps1` are un mic buton **FB SOUND** sub stiva APPLY / REVERT. Stochează doar o *preferință*; `install.ps1 -Target freebuff` citește același fișier și îl dă patch-ului ca `--sound`, deci reclamele și sunetul sunt aplicate într-o singură rulare:

- **Click stânga** — alege un fișier audio (OpenFileDialog, wav/mp3/ogg/flac/m4a/aac) și îl auzi redat imediat: PCM WAV prin System.Media.SoundPlayer, orice alt format printr-un WPF MediaPlayer (Media Foundation, async, deci fereastra nu îngheață niciodată). Alegerea este reținută în `%APPDATA%\Wintage\freebuff-sound.txt` (per-mașină, în afara git checkout-ului, exact ca dosarele reținute source-tree).
- **Click dreapta** — șterge preferința înapoi la sunetul standard FreeBuff (oprește și orice previzualizare care încă se redă).
- **COPY** — copiază audio-ul ales în repo-ul însuși (`sounds\freebuff.<ext>`, păstrând extensia sursei) și repointernează preferința către acea copie, deci sunetul supraviețuiește dacă fișierul original este șters sau mutat. Activat doar cât timp e setat un sunet personalizat; re-copierea pur și simplu suprascrie copia din repo. Dosarul `sounds/` este conținut obișnuit trackabil în git, deci commit-uit îl face pe sunet să supraviețuiască și re-clonărilor.

Doar containerele audio recunoscute sunt previzualizate — antetul este sniff-uit întâi, deci o alegere non-audio este anunțată în loc să nu redea nimic în tăcere.

Butonul citește **ON** cât timp e setat un sunet personalizat; hover peste el arată calea. Aplică apoi ținta `freebuff` (bifează FreeBuff + APPLY, sau rulează `install.ps1 -Target freebuff` dintr-un terminal) ca să intre în efect.

### Terminale

`terminal` scrie o schemă de culori `Wintage` în fiecare fișier de setări Windows Terminal stabil, Preview sau neambalat detectat și o selectează prin `profiles.defaults`, împreună cu Consolas 12 sigur pentru consolă și text aliased. Fișierul original este păstrat byte-cu-byte lângă el, iar `-Revert` îl restaurează.

`conhost` acoperă `cmd.exe` clasic, Windows PowerShell, profilurile de consolă Git CMD/Bash și alți copii existenți `HKCU\Console`. Scrie întreaga tabelă de 16 culori a paletei atât în implicitele rădăcină, cât și în fiecare suprascriere existentă, apoi restaurează doar valorile pe care le-a atins. Aplică și aici Consolas, pentru că Verdana proporțională se ciocnește în grila de celule cu lățime fixă folosită de ambele host-uri terminale.

### Browsere și Tampermonkey

`browsers` găsește profiluri Chrome, Edge, Brave, Cent, Vivaldi și Opera din locațiile instalate și din rădăcina portabilă către care o îndrepți (`-PortableRoot`, sau intrarea `portable` reținută în `paths.json`). Statusul său arată atât numărul de profiluri, cât și câte conțin Tampermonkey. Apply copiază tema chrome de browser aleasă în dosarul stabil `%LOCALAPPDATA%\Wintage\browser-theme`, pune acea cale pe clipboard și deschide fiecare profil exact la `chrome://extensions` plus pagina Install/Update a userscript-ului Wintage. Profilurile fără Tampermonkey primesc și pagina lui Chrome Web Store.

Chromium interzice deliberat instalarea silențioasă a extensiilor din afara magazinului pe o mașină Windows neadministrată. Prima instalare de temă de browser cere deci o confirmare **Developer mode → Load unpacked** per profil. Alege calea copiată; după aceea, Wintage continuă să înlocuiască același dosar stabil când paletele se schimbă. Confirmă și **Install/Update** în Tampermonkey. Niciun fișier `Preferences`, Secure Preferences sau Tampermonkey LevelDB al browserului nu este editat pe la spatele browserului. Dacă Tampermonkey nu era prezent, instalează-l din tab-ul de magazin deschis și reîmprospătează tab-ul deja deschis `wintage.user.js` ca să obții ecranul Install.

### Windows

`windows` instalează și activează imediat un `%LOCALAPPDATA%\Microsoft\Windows\Themes\Wintage-<hash>.theme` adresat pe conținut. Pornește de la tema activă și înlocuiește doar secțiunile documentate de culoare, cursor și stil vizual. Fundalul, sunetele și iconițele desktop rămân neschimbate; cursorii trec intenționat la schema instalată `___CURRENT___`. Prima temă activă este salvată byte-cu-byte ca `Wintage.original.theme`; schimbările de paletă păstrează acea linie de bază, iar `-Revert` o reactivează. Controalele moderne Windows vin tot din stilul vizual Aero semnat — Wintage îi schimbă modul întunecat, accentul și intrările clasice de culoare de sistem susținute, în loc să înlocuiască fișiere `.msstyles` protejate. Captionurile active și inactive împart culoarea de suprafață ridicată, închisă, a paletei; highlight-ul luminos rămâne rezervat pentru muchiile de text/selecție. Accentul anterior al captionului inactiv este snapshottat separat și restaurat exact de `-Revert`. Hash-ul de conținut dă Windowsului o nouă țintă de asociere a fișierelor când aceeași paletă este reconstruită, deci re-aplicarea unei palete actualizate nu este confundată cu un no-op; fișierul Wintage înlocuit este eliminat după ce Windows confirmă noul ca activ.

### OBS Studio

`obs` generează o variantă OBS 30.2+ peste baza întreținută Yami Classic, o instalează în `%APPDATA%\obs-studio\themes` și scrie ID-ul său stabil de temă în `user.ini`, deci paleta Wintage aleasă este deja selectată la următoarea pornire. Închide OBS înainte de Apply sau Revert: OBS rescrie `user.ini` la ieșire. Prima aplicare face backup byte-cu-byte atât pentru selecția anterioară, cât și pentru orice temă cu același nume.

### Aplicații Electron

`resources/app.asar` este mutat în `resources/app/app.asar` (fratele său `app.asar.unpacked` se mută cu el — acea împerechere este după numele fișierului, iar despărțirea lor strică fiecare modul nativ), iar un mic `shim.cjs` preia slotul liber `resources/app`. Shim-ul injectează stylesheet-ul și apoi încarcă arhiva originală. **Niciun byte al aplicației nu este rescris**, doar relocat; `-Revert` îl mută direct înapoi.

Stylesheet-ul nu este scris pentru aceste aplicații — este extras din `wintage.user.js`, deci fiecare fix de bevel, scrollbar și scară tipografică făcut pentru browser aterizează și aici, fără o a doua copie care să putrezească.

Două note care merită știute dinainte:

- Abordarea evidentă — să arunci `resources/app` lângă arhivă și să te bazezi pe Electron că o preferă — **nu funcționează și eșuează silențios**. Electron caută `app.asar` primul. Aplicația pornește perfect și tema nu rulează niciodată.
- Shim-ul este `.cjs`, nu `.js`, intenționat. `package.json`-ul lui este copiat din al aplicației, deci aplicația își păstrează numele și versiunea (numele decide unde trăiește userData — un shim care îl redenumește mută aplicația într-un profil gol). Dacă acel manifest spune `"type": "module"`, un shim `.js` moare la primul `require`.

### Aplicația desktop a lui Claude: pe loc, și cadrul în care chiar desenează

Claude nu poate folosi relocarea de mai sus, pentru că `OnlyLoadAppFromAsar` este fuzed-on — Electron încarcă `resources/app.asar` și nimic altceva, deci un shim în `resources/app` nu poate rula niciodată. Este patch-uit **pe loc** în schimb: arhiva este salvată, `main` din `package.json` este rescris la `"../wintage-shim.cjs"` (umplut la aceeași lungime de byte, deci fiecare offset din arhivă rămâne valid), iar hash-ul de integritate per-fișier este actualizat să se potrivească. `-Revert` restaurează backup-ul.

Installer-ul tot citește fuse-urile **înainte să mute orice** și refuză cu un motiv când ele îl blochează — `EnableEmbeddedAsarIntegrityValidation` ar face rescrierea de mai sus să eșueze la lansare, nu la instalare. Verifică orice aplicație singur:

```powershell
node ..\tools\electron-fuses.js "<path to the app's exe>"
```

A doua jumătate a fost o problemă mult mai tăcută. `BrowserWindow` al lui Claude randează o cochilie subțire, iar **întreaga aplicație vizibilă este un `WebContentsView`** atașat la ea. Shim-ul obișnuia să prindă `browser-window-created`, deci injecta stylesheet-ul în cochilie, raporta succes către `wintage-status.txt` și nu schimba nimic din ce puteai vedea. Acum prinde `web-contents-created`, care acoperă conținutul ferestrei, `WebContentsView`-urile, `BrowserView`-urile, invitații `<webview>` și popup-urile deopotrivă.

### Obsidian

O temă de comunitate este scrisă în `.obsidian/themes/` a fiecărui vault — toate cele șaisprezece palete deodată, exact ca ținta VS Code, deci comuți între ele în **Settings → Appearance** fără să re-rulеzi nimic. Șablonul a fost derivat din tema făcută manual `VintageWin95` deja prezentă în vault, fiecare culoare înlocuită cu tokenul căruia îi corespundea. `-Palette <slug>` setează care este activă la instalare; `appearance.json` este salvat întâi, iar `-Revert` elimină doar temele `Wintage *` și restaurează alegerea ta anterioară — o temă făcută manual în același vault nu este atinsă niciodată.

### SAIPENVIEW

Frontend-ul său declară deja numele de token Wintage în propriul `:root`, deci acest patch rescrie **doar valorile tokenurilor** — niciodată un selector, un font, o lățime de border sau un padding. Nimic din ce afectează box model-ul nu se schimbă, deci textul nu se poate deplasa. Asta este deliberat: abordarea anterioară adăuga întregul stylesheet de browser deasupra, iar `wintage.css` este scris pentru pagini web arbitrare — selectori universali care forțează fontul, scara de dimensiuni, borderuri de 2px și înălțimi de control. Pe o aplicație care are deja propriul layout, asta mută totul.

Verificat prin mascarea fiecărui hex și difing împotriva backup-ului: structural identic, doar literalii de culoare diferă. `--link` este raportat ca nedeclarat acolo (linkurile sale markdown citesc `--accentTeal`, pe care acesta îl setează) în loc să fie injectat — adăugarea unei variabile pe care aplicația nu o citește niciodată ar fi greutate moartă.

### MPC-HC (K-Lite)

Win32 nativ, fără stylesheet și fără punct de injectare, iar culorile temei sale întunecate sunt compilate în program — nicio valoare de registry nu le expune. Deci această țintă **nu poate purta o paletă**. Ce face: pornește tema întunecată și aplică regulile de tipografie din UI.md la OSD, care este singura suprafață pe care MPC-HC îi permite utilizatorului să o controleze. Setările anterioare sunt exportate întâi în `desktop/backup/mpc-hc-settings.reg`.

Închide MPC-HC înainte de aplicare: își rescrie setările la ieșire.

## Reconstruirea

Tot ce se află sub `desktop/out/` este generat din `themes/*.json`. Nu este urmărit în git (T-160), deci un clone proaspăt trebuie să-l construiască o dată înainte de instalare:

```powershell
node ..\tools\build-desktop.js          # reconstruiește toate țintele
node ..\tools\build-desktop.js --check  # exit code 1 dacă ceva e vechi
```

`release.ps1` rulează build-ul și fiecare poartă, deci o lansare nu poate livra output care a derivat de la palete.

<!-- source-digest: desktop/README.md sha256:1b166ae6a7cf8a5c -->
