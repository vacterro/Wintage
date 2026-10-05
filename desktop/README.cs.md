# Wintage pro desktopové aplikace

Userscript zatemňuje web. Tohle zatemňuje programy kolem něj ze stejných
palet, takže prohlížeč a aplikace si přestanou odporovat v tom, co znamená
tmavě zlatá.

Za každým rozhodnutím tu stojí jedno pravidlo: **aplikace se aktualizují samy a
aktualizace nesmí tiše něco rozbít.** Kde má cíl místo ve vašem vlastním profilu,
téma jde tam a přežije aktualizace. Kde ho nemá, je instalátor napsán tak, aby se
dal spouštět znovu — a sám to říká, místo aby předstíral, že zůstal.

## GUI

Dvakrát klikněte na **`Wintage Installer.vbs`** v kořeni repozitáře, abyste ho
otevřeli bez okna konzole, nebo pro diagnostiku spusťte přímo toto:

```powershell
powershell -File desktop\WintageInstaller.ps1
```

Seznam motivů s barevnými vzorníky, cíle nalezené na tomto počítači, živý náhled
Win95 a všech jednadvacet barevných tokenů jako upravitelné vzorky. Úprava
jakéhokoli vzorku rozdělí paletu do **Custom** místo toho, aby vám potichu
měnila dodávaný motiv. Panel vpravo ukazuje živý kontrast WCAG pro tři tokeny,
které nesou text — paleta, která tam selže, je stejně odmítnuta build bránou,
takže je lepší to vidět před Apply než po něm.

Cíle jsou rozděleny do dvou seznamů dosažitelných klávesnicí: **MY APPS** obsahuje
přenosné/zdrojové nástroje CodeNomad, WorkBuddy; **POPULAR
APPS** obsahuje Windows, OBS, terminály, editory a další nainstalovaný software.
ALL/NONE a Apply/Revert fungují na obou seznamech, aniž by měnily jejich seskupení.

Okno nosí paletu, kterou se chystá nainstalovat. To je nejrychlejší dostupný
náhled a udržuje nástroj čestný: paleta, která toto okno udělá nečitelným, je
viditelně nečitelná.

Apply obalí volání `install.ps1`. Existuje přesně jedna cesta kódu, která
instaluje motiv, takže GUI se nemůže odchýlit od příkazového řádku.

## Příkazový řádek

```powershell
.\desktop\install.ps1                                  # co tu je, co je zatemněno, s jakou paletou
.\desktop\install.ps1 -Target freebuff -Palette klite  # jedna aplikace, jedna paleta
.\desktop\install.ps1 -Target all -Palette goldendefault # všechno
.\desktop\install.ps1 -Target all -WhatIf              # řekni, co by se změnilo, ničeho se nedotýkej
.\desktop\install.ps1 -Target freebuff -Revert         # vrátit jednu
```

`-Palette` má výchozí hodnotu `goldendefault` (**Golden Default**). GUI se otevře
se stejnou paletou a zkontroluje každý dostupný cíl. Přelakování aplikace, která
už je zatemněná, funguje za běhu; první instalace ne, protože archiv je používán.

## Co lze u každého cíle skutečně zatemňovat

| target | mechanism | survives an app update |
|---|---|---|
| `windows` | uživatelský `.theme`: tmavý režim systému/aplikace, akcent a klasické barevné role | ano — nainstalováno do vaší místní složky Windows Themes |
| `browsers` | detekuje nainstalované + přenosné Chromium profily, připraví vybraný chrome motiv a otevře stránky potvrzení Tampermonkey/motivu vlastněné prohlížečem | ano po jednom **Load unpacked** pro každý profil |
| `terminal` | schéma Windows Terminal + výchozí pro všechny profily, Consolas 12 aliased | ano — nastavení jsou ve vašem profilu |
| `conhost` | výchozí `HKCU\Console` + každý existující profil cmd/PowerShell | ano — přesný snímek dotčených hodnot |
| `obs` | varianta OBS 30.2+ `.ovt` + aktivní ID motivu v `user.ini` | ano — žije ve vašem profilu |
| `qbittorrent` | rozbalený motiv Qt UI (`config.json` + `stylesheet.qss`) + dva klíče motivu v `qBittorrent.ini` | ano — žije ve vašem profilu |
| `antigravity`, `vscode` | rozšíření barevného motivu v `~/.antigravity/extensions` / `~/.vscode/extensions` | **ano** — žije ve vašem profilu |
| `freebuff`, `antigravity-app`, `codenomad` | Electron shim, viz níže | ne — spusťte instalátor znovu |
| `claude` | Electron shim, záplatován na místě — viz níže | ne — aktualizace vytvoří novou složku `app-<version>` |
| `mpchc` | registr, jen tmavý motiv + typografie OSD | ne — MPC-HC při ukončení přepíše svá nastavení |
| `obsidian` | komunitní motiv pro každý trezor, všechny palety najednou | **ano** — žije ve vašem trezoru |
| `discord` | CSS vloženo do vlastní složky motivů BetterDiscord | ano |
| `totalcmd`, `totalcmd2` | klíče `wincmd.ini` `[Colors]`; existující filtry posledních souborů používají barvu odkazu palety | ano — je to váš ini |

### Odstranění reklam ve FreeBuff

FreeBuff (desktopová aplikace AI asistenta) dodává vlastní reklamní síť: renderer
bundle (`resources/orchestrator/ui/assets/index-*.js`) vykresluje kartu
`sponsored-ad` a banner vlákna a orchestrator (`resources/orchestrator/orchestrator.js`)
vystavuje routy `/api/ad/slot|impression|click`, které volají vzdálenou reklamní
aukci. Shim pouze zatemňuje aplikaci; nedotýká se těchto souborů.

`desktop/patch-freebuff-ads.js` vyřezává reklamy na úrovni bajtů:

- renderer: volací místa karty/banneru reklamy se stanou `null` a metody API
  klienta `adSlot` / `adImpression` / `adClick` se stanou no-op — nic se
  nevykresluje a z rendereru nikdy nevyjde žádný požadavek `/api/ad/*`;
- orchestrator: všechny tři routy `/api/ad/*` přestanou volat reklamní síť a
  inline požadavek reklamy v živém tahu (`maybeRequestAd`) je zkratován.

Název bundle souboru v sobě nese build hash, takže záplata objeví aktuální bundle
z `index.html` místo dodání payloadu uzamčeného na verzi — díky tomu přežije
aktualizace. Originály jsou zálohovány do `_orig-backup-<timestamp>/` v instalačním
adresáři; `--revert` obnoví nejnovější.

**Budoucí verze jsou ošetřeny ve dvou nezávislých vrstvách:**

1. **Bajtová záplata s regex fallbacky.** Každý cíl má přesný řetězec pro aktuální
   build *a* fallback regulárního výrazu ukotvený na tom, co minifier nemůže
   přejmenovat — literály cest `/api/ad/*`, diskriminátor protokolu `case"ad":`,
   třída `sponsored-ad` a umístění `variant:"banner"` / `variant:"card"`.
   Orchestrator není minifikován (čitelné názvy jako `maybeRequestAd` a
   `app.ads.slotAd`), takže jeho přesné řetězce dlouho vydrží; renderer bundle je
   minifikovaný, takže jeho regex fallbacky převezmou řízení v okamžiku, kdy další
   build přejmenuje jeho identifikátory.
2. **Blok na úrovni shimu (`targets/electron/shim.cjs`).** Zcela nezávislý na
   bundle: jakýkoli fetch/XHR na `/api/ad/` URL je uvnitř stránky odmítnut a
   jakýkoli prvek, jehož třída obsahuje `sponsored-ad`, je skryt v okamžiku, kdy
   se objeví. Ani zbrusu nový bundle, který tento skript ještě nezná, nemůže
   zobrazit reklamu.

```powershell
node .\desktop\patch-freebuff-ads.js           # záplata (nejprve zálohuje)
node .\desktop\patch-freebuff-ads.js --sound "C:\...\my.mp3"   # záplata + vlastní zvuk dokončení (wav/mp3/ogg/flac/m4a/aac)
node .\desktop\patch-freebuff-ads.js --scan    # jaké reklamní značky nese TENHLE build?
node .\desktop\patch-freebuff-ads.js --verify
node .\desktop\patch-freebuff-ads.js --revert
```

Spouští se automaticky jako součást `install.ps1 -Target freebuff` a musí být
znovu spuštěn po každé aktualizaci FreeBuff (aktualizace obnoví stock soubory).
Pokud build změní tvar, skript pojmenuje cíl, který už neodpovídá — spusťte
`--scan`, abyste viděli, co nový build stále nese, a obnovte tam řetězce.

**Zvuk dokončení FreeBuff.** Renderer přehrává `chime-<hash>.mp3`, když tah
skončí. Záplata ho najde stejným způsobem jako bundle (název nese build hash),
takže `--sound <file>` nainstaluje váš vlastní zvuk (wav/mp3/ogg/flac/m4a/aac)
přes něj a ponechá stock soubor jako `chime-*.mp3.bak`; `--revert` ho obnoví.
`--verify` hlásí, který je aktivní.

### Tlačítko zvuku FreeBuff (GUI)

`WintageInstaller.ps1` má malé tlačítko **FB SOUND** pod zásobníkem APPLY /
REVERT. Ukládá pouze *preferenci*; `install.ps1 -Target freebuff` čte stejný
soubor a předá ho záplatě jako `--sound`, takže reklamy a zvuk se aplikují
v jednom běhu:

- **Levým kliknutím** — vyberte zvukový soubor (OpenFileDialog, wav/mp3/ogg/flac/m4a/aac)
  a ihned si ho přehrajte: PCM WAV přes System.Media.SoundPlayer, každý jiný
  formát přes WPF MediaPlayer (Media Foundation, asynchronní, takže okno nikdy
  nezmrzne). Volba je zapamatována v `%APPDATA%\Wintage\freebuff-sound.txt`
  (na počítač, mimo git checkout, přesně jako zapamatované složky zdrojového
  stromu).
- **Pravým kliknutím** — vymažte preferenci zpět na stock zvuk FreeBuff (také
  zastaví jakýkoli náhled, který stále hraje).
- **COPY** — zkopíruje vybraný zvuk přímo do repozitáře (`sounds\freebuff.<ext>`,
  se zachováním zdrojové přípony) a přesměruje preferenci na tuto kopii, takže
  zvuk přežije smazání nebo přesun původního souboru. Povoleno pouze když je
  nastaven vlastní zvuk; opětovné kopírování jednoduše přepíše kopii v repozitáři.
  Složka `sounds/` je běžný gitově sledovatelný obsah, takže jeho commitování
  zajistí, že zvuk přežije i re-klony.

Pouze rozpoznané zvukové kontejnery se náhledují — hlavička se nejprve očichá,
takže výběr ne-zvuku je oznámen místo tichého přehrávání ničeho.

Tlačítko ukazuje `ON`, dokud je nastaven vlastní zvuk; najetí myší ukáže cestu.
Pak aplikujte cíl `freebuff` (zaškrtněte FreeBuff + APPLY, nebo spusťte
`install.ps1 -Target freebuff` z terminálu), aby se projevil.

### Terminály

`terminal` zapíše barevné schéma `Wintage` do každého detekovaného stabilního,
Preview nebo nebaleného souboru nastavení Windows Terminal a vybere ho přes
`profiles.defaults`, spolu s konzolově bezpečným Consolas 12 a aliased textem.
Původní soubor je uchován bajt po bajtu vedle něj a `-Revert` ho obnoví.

`conhost` pokrývá klasické profily `cmd.exe`, Windows PowerShell, Git CMD/Bash
konzole a další existující potomky `HKCU\Console`. Zapíše plnou 16barevnou
tabulku palety jak do kořenových výchozích, tak do každého existujícího
přepsání, a pak obnoví pouze hodnoty, kterých se dotkl. Použije tam i Consolas,
protože proporcionální Verdana koliduje uvnitř mřížky buněk pevné šířky, kterou
používají oba terminálové hosty.

### Prohlížeče a Tampermonkey

`browsers` najde profily Chrome, Edge, Brave, Cent, Vivaldi a Opera z
nainstalovaných umístění a z přenosného kořene, na který ukazujete
(`-PortableRoot`, nebo zapamatovaný záznam `portable` v `paths.json`). Jeho stav
ukazuje počet profilů i to, kolik jich obsahuje Tampermonkey. Apply zkopíruje
vybraný motiv chrome prohlížeče do stabilní složky
`%LOCALAPPDATA%\Wintage\browser-theme`, dá tuto cestu do schránky a otevře každý
konkrétní profil na `chrome://extensions` plus stránku Wintage userscript
Install/Update. Profily bez Tampermonkey dostanou i jeho stránku v Chrome Web Store.

Chromium záměrně zakazuje tichou instalaci rozšíření mimo obchod na
nespravovaném počítači s Windows. První instalace motivu prohlížeče proto
vyžaduje jedno potvrzení **Developer mode → Load unpacked** pro každý profil.
Vyberte zkopírovanou cestu; poté Wintage při změně palet stále nahrazuje stejnou
stabilní složku. Potvrďte také **Install/Update** v Tampermonkey. Žádný soubor
`Preferences`, Secure Preferences prohlížeče nebo LevelDB Tampermonkey není
upravován za zády prohlížeče. Pokud Tampermonkey nebyl přítomen, nainstalujte ho
z otevřené záložky obchodu a obnovte již otevřenou záložku `wintage.user.js`,
abyste získali obrazovku Install.

### Windows

`windows` nainstaluje a okamžitě aktivuje obsahově adresovaný
`%LOCALAPPDATA%\Microsoft\Windows\Themes\Wintage-<hash>.theme`. Začíná od
aktivního motivu a nahrazuje pouze dokumentované sekce barev, kurzorů a vizuálního
stylu. Tapeta, zvuky a ikony plochy zůstávají beze změny; kurzory se záměrně
přepnou na nainstalované schéma `___CURRENT___`. První aktivní motiv je uložen
bajt po bajtu jako `Wintage.original.theme`; změny palety zachovávají tento
základ a `-Revert` ho znovu aktivuje. Moderní ovládací prvky Windows stále
pocházejí z podepsaného vizuálního stylu Aero — Wintage mění jeho podporovaný
tmavý režim, akcent a vstupy klasických barev systému, místo aby nahrazoval
chráněné soubory `.msstyles`. Aktivní a neaktivní titulky sdílejí ztlumenou barvu
zvednutého povrchu palety; jasné zvýraznění zůstává vyhrazeno pro okraje
textu/výběru. Předchozí akcent neaktivního titulku je snímkován samostatně a
`-Revert` ho přesně obnoví. Obsahový hash dává Windows nový cíl přiřazení souborů,
když je stejná paleta znovu sestavena, takže znovupoužití aktualizované palety
není zaměněno za no-op; překonaný soubor Wintage je odstraněn poté, co Windows
potvrdí, že nový je aktivní.

### OBS Studio

`obs` vygeneruje variantu OBS 30.2+ nad udržovaným základem Yami Classic,
nainstaluje ji do `%APPDATA%\obs-studio\themes` a zapíše její stabilní ID motivu
do `user.ini`, takže vybraná paleta Wintage je při příštím spuštění už vybraná.
Zavřete OBS před Apply nebo Revert: OBS při ukončení přepíše `user.ini`. První
aplikace zálohuje jak předchozí výběr, tak jakýkoli motiv stejného jména bajt po
bajtu.

### qBittorrent

`qbittorrent` zapisuje **rozbalený** Qt motiv rozhraní do `%APPDATA%\qBittorrent\themes\wintage` — soubor `config.json` (role `Palette.*` plus vlastní kontextové barvy qBittorrentu: stavy seznamu přenosů, úrovně protokolu) a vedle něj `stylesheet.qss` (2px zkosení, pravé rohy a Verdana, což paleta vyjádřit neumí) — poté nasměruje `General\CustomUIThemePath` na tento `config.json` a nastaví `General\UseCustomUITheme=true`.
Rozbaleně, a ne jako balíček `.qbtheme` — záměrně: `.qbtheme` je soubor typu Qt Resource Collection a k jeho vytvoření by na stroji bylo potřeba `rcc` se shodnou hlavní verzí, tedy závislost na kompilátoru kvůli dvěma textovým souborům. qBittorrent čte složkovou podobu nativně (`FolderThemeSource`).
Před Apply nebo Revert qBittorrent zavřete: při ukončení přepisuje celý `qBittorrent.ini`, takže úprava provedená za běhu se při zavření zahodí — cíl v takovém stavu odmítne pracovat, místo aby hlásil úspěch, který příští ukončení smaže. `-Revert` vrátí dva klíče v INI na přesné hodnoty před Wintage (nebo je odstraní, pokud nebyly) a vrátí každou stejnojmennou složku motivu bajt po bajtu; nesouvisející úpravy `qBittorrent.ini` provedené po Apply zůstávají.
Nedosažitelné: ikony panelu nástrojů a oznamovací oblasti pocházejí z vlastního zkompilovaného zdrojového balíčku qBittorrentu, takže si zachovávají původní barvy.

### Písmo: pojmenovaná, nikdy se neinstalují

Zákon 1 z UI.md žádá Verdana **bez antialiasingu**. Stylysheet Qt nemá vlastnost, která by to umožnila, a `OSDFont` v MPC-HC je prostý název GDI písma — jedinou pákou je tedy samo písmo. `Verdana_m1.ttf` v kořeni repozitáře je kopie Verdany s předem vykreslenými 1bpp bitmapovými řezy od 3 do 30 ppem, které vykreslování použije před hladkým obrysem.
Stylysheety `qbittorrent` a `obs` uvádějí `Verdana_m1, Verdana` a `mpchc` uvádí ten z obou, který stroj skutečně vyřeší. **Instalátor nikdy písmo neinstaluje ani neodinstalovává** a to je záměr, ne nedokončenost:
Rodina písma se řeší podle (rodina, styl). Zaregistrujte Regular + Bold + Italic a každý spotřebitel se vyřeší správně; odeberte **jeden** člen a každý spotřebitel žádající tuto rodinu se přesměruje na přeživší člen. Na stroji, který aliasuje `MS Shell Dlg 2` — písmo dialogů Windows — na tuto rodinu přes `HKLM\...\FontSubstitutes`, odebrání Regular natočí **celou plochu kurzivně**, včetně titulků oken, které DWM už cacheoval, a k obnově je potřeba odhlášení. Žádné počítání referencí to neopraví: dopad je celo-strojový a instalátor motivu do toho nemá co říkat.
Písmo je tedy jednorázový výslovný krok uživatele: pravý klik na `Verdana_m1.ttf` → **Instalovat** (pro uživatele, bez práv správce), pak znovu aplikujte cíl. Pokud písmo chybí, cíle to řeknou jednou, pojmenují opravu a vrátí se ke stock Verdana — s antialiasingem, ale bez toho, aby se cokoli dělalo na vašem stroji za vašimi zády.

### Electron aplikace

`resources/app.asar` je přesunut do `resources/app/app.asar` (jeho sourozenec
`app.asar.unpacked` se přesouvá s ním — toto párování je podle názvu souboru a
jeho oddělení rozbije každý nativní modul) a malý `shim.cjs` zaujme uvolněný slot
`resources/app`. Shim vloží stylsheet a pak načte původní archiv. **Žádný bajt
aplikace není přepsán**, pouze přemístěn; `-Revert` ho přesune rovnou zpět.

Stylsheet není pro tyto aplikace napsán — je extrahován z `wintage.user.js`, takže
každá oprava zkosení, posuvníku a typografického žebříku vytvořená pro prohlížeč
dopadne i sem, bez druhé kopie, která by hnila.

Dvě poznámky, které stojí za to mít předem:

- Zjevný přístup — nechat `resources/app` vedle archivu a spoléhat na to, že ho
  Electron preferuje — **nefunguje a tiše selže**. Electron hledá `app.asar`
  jako první. Aplikace se spustí perfektně a motiv nikdy neběží.
- Shim je záměrně `.cjs`, ne `.js`. Jeho `package.json` je zkopírován z vlastního
  souboru aplikace, takže aplikace si zachová jméno a verzi (jméno rozhoduje, kde
  žije userData — shim, který ho přejmenuje, přesune aplikaci do prázdného
  profilu). Pokud tento manifest říká `"type": "module"`, `.js` shim zemře na
  svém prvním `require`.

### Desktopová aplikace Claude: na místě a rám, do kterého skutečně kreslí

Claude nemůže použít výše uvedené přemístění, protože `OnlyLoadAppFromAsar` je
připájeno na — Electron načte `resources/app.asar` a nic jiného, takže shim
v `resources/app` nikdy nemůže běžet. Místo toho je **záplatován na místě**:
archiv je zálohován, jeho `package.json` `main` je přepsán na
`"../wintage-shim.cjs"` (doplněn na stejnou délku bajtů, takže každý offset
v archivu zůstává platný) a hash integrity na soubor je aktualizován, aby
odpovídal. `-Revert` obnoví zálohu.

Instalátor čte fuses **ještě předtím, než něco přesune**, a odmítne s důvodem,
když ho blokují — `EnableEmbeddedAsarIntegrityValidation` by výše uvedený přepis
nechal selhat při spuštění, ne při instalaci. Zkontrolujte si jakoukoli aplikaci
sami:

```powershell
node ..\tools\electron-fuses.js "<path to the app's exe>"
```

Druhá polovina tohohle byl mnohem tišší problém. `BrowserWindow` Claude vykresluje
tenkou skořápku a **celá viditelná aplikace je `WebContentsView`** připojený k ní.
Shim se dříve hákoval na `browser-window-created`, takže vložil stylsheet do
skořápky, nahlásil úspěch do `wintage-status.txt` a nezměnil nic, co byste viděli.
Teď se háčkuje na `web-contents-created`, který pokrývá obsah okna,
`WebContentsView`, `BrowserView`, hosty `<webview>` i popupy.

### Obsidian

Do `.obsidian/themes/` každého trezoru je zapsán komunitní motiv — všech šestnáct
palet najednou, přesně jako cíl VS Code, takže mezi nimi přepínáte v **Settings →
Appearance**, aniž byste něco znovu spouštěli. Šablona byla odvozena z ručně
vytvořeného motivu `VintageWin95`, který už v trezoru je; každá barva byla
nahrazena tokenem, kterému se rovnala. `-Palette <slug>` určuje, který bude při
instalaci aktivní; `appearance.json` je nejprve zálohován a `-Revert` odstraní
jen motivy `Wintage *` a obnoví vaši předchozí volbu — ručně vytvořeného motivu ve
stejném trezoru se nikdy nedotkne.


### MPC-HC (K-Lite)

Nativní Win32, žádný stylsheet a žádný injekční bod, a barvy jeho tmavého motivu
jsou zkompilovány do programu — žádná hodnota registru je nevystavuje. Takže tento
cíl **nemůže nést paletu**. Co dělá: zapne tmavý motiv a aplikuje pravidla
typografie UI.md na OSD, což je jediný povrch, který MPC-HC uživateli umožňuje
ovládat. Předchozí nastavení je nejprve exportováno do
`desktop/backup/mpc-hc-settings.reg`.

Zavřete MPC-HC před aplikací: při ukončení přepíše svá nastavení.

## Přestavba

Vše pod `desktop/out/` je generováno z `themes/*.json`. Není sledováno v gitu
(T-160), takže čerstvý klon musí před instalací jednou sestavit:

```powershell
node ..\tools\build-desktop.js          # přestavět všechny cíle
node ..\tools\build-desktop.js --check  # exit 1, pokud je něco zastaralé
```

`release.ps1` spustí build a každou bránu, takže vydání nemůže dodat výstup, který
se odchýlil od palet.

<!-- T-311 target/section coverage supplement -->
## Pokrytí cílů a sekcí

Tato sekce zrcadlí pokrytí Process Explorer, Notepad++, Cinema 4D a písem terminálu v aktuálním anglickém README, aby tato lokalizace tiše nezastarala. Literály kódu (ID cílů, cesty v registru, názvy souborů) jsou jazykově nezávislé záměrně; okolní text je zde přeložen.

### Co se z každého cíle dá skutečně tematizovat (přidané cíle)

| cíl | mechanismus | přežije aktualizaci aplikace |
|---|---|---|
| `notepadplusplus` | XML motivu + alias do složky `themes` u Notepad++ | ano — žije ve vašem profilu |
| `cinema4d` | barevné schéma vložené do složky `schemes` u Cinema 4D | ano — žije ve vašem profilu |
| `processexplorer` | `HKCU\Software\Sysinternals\Process Explorer`: barvy zvýraznění řádků a pozadí grafů, viz níže | ne — Process Explorer si při ukončení přepíše vlastní nastavení; zavřete ho a spusťte znovu |

### Process Explorer (Sysinternals)

Process Explorer si drží barvy v `HKCU\Software\Sysinternals\Process Explorer` a při ukončení tento klíč přepíše, proto cíl **odmítne, dokud běží `procexp`, `procexp64` nebo `procexp64a`** — zavřete ho a spusťte znovu. Tematizuje nastavitelné barevné kategorie:

- **dostupné**: barvy zvýraznění řádků procesů (`ColorOwn`, `ColorServices`, `ColorRelocatedDlls`, `ColorImmersive`, `ColorPacked`, `ColorJobs`, `ColorNet`, `ColorProtected`, `ColorNewProc`, `ColorDelProc`, `ColorSuspend`) v režimu světlém i v jejich variantách `*Dark`, plus pozadí grafů (`ColorGraphBk`, `ColorGraphBkDark`) — celkem 24 hodnot. Každá varianta se míchá s odpovídajícím pólem aktivní palety (světlejší odstín pro výplň ve světlém režimu, tmavší pro `*Dark`), takže výplně řádků zůstávají ve vlastním odstínu palety, místo aby pastelizovaly skoro na bílou;
- **nedostupné**: titulní lišta, lišta nabídky, lišta nástrojů, pozadí a barvy textu v zobrazení seznamu a barvy čar grafů — ty jsou zkompilované do `procexp.exe` a žádná hodnota nastavení je neodhaluje. Cíl tematizuje zvýraznění řádků a pozadí grafu, které opravdu vlastní, a netvrdí nic dalšího.

Každou hodnotu, kterou Apply dokáže změnit, uloží jako snímek před změnou (obnova při prvním dotyku v `%APPDATA%\Wintage\recovery\processexplorer\`) a `-Revert` ji obnoví přesně, včetně informace, zda hodnota chyběla a zda značka existovala, ale byla prázdná. Přenosná složka mimo standardní adresáře Sysinternals se pamatuje přes kanonický klíč `paths.json` `processexplorer` (argument příkazové řádky `-ProcessExplorerPath`; i GUI ho umí vybrat).

### Písma terminálu (`fonts/terminal/`)

Oba cílové terminály čtou JEDINOU kanonickou typografickou preferenci z `%APPDATA%\Wintage\terminal-font.json` (`schema`, `fontSlug`, `family`, `size`, `renderingMode`). Když soubor chybí, cíle si ponechají dodané výchozí hodnoty (Terminus (TTF) for Windows, 12 pt, aliased), takže existující stroje zůstávají beze změny. Vadná preference selže uzavřeně: nic se nepřepíše a cíl odmítne.

`fonts/terminal/catalog.json` je jediný katalog písem: 20 zabudovaných open-source monospace rodin plus dvě systémové řezy, které Wintage jmenuje, ale nikdy nedodává (Terminus (TTF) for Windows, Consolas). Každá zabudovaná položka nese svůj upstream zdroj, připnutou revizi, ID licence, soubor licence a SHA-256. Přesné soubory jsou dodané pod `fonts/terminal/files/` a texty licencí pod `licenses/`; běžící Wintage pracuje zcela offline a nikdy nestáhne žádné písmo.

`tools/sync-terminal-fonts.ps1` je stahovadlo pouze pro správce. Čte `fonts/terminal/sources.json` (jeden neměnný artefakt na rodinu), ověřuje každé SHA-256 a při neshodě odmítne. `-VerifyOnly` (výchozí) kontroluje strom na disku bez sítě; `-Fetch -Write` je znovu dodá. Stažené bajty písem se považují za nedůvěryhodná binární aktiva — hašovaná a zapsaná, nikdy spuštěná. Jedna náhrada je zaznamenaná: **Fantasque Sans Mono** nahrazuje Liberation Mono, který nepublikuje žádnou připnutou binární verzi (pouze zdrojové `.sfd`).

Instalátor **prohlíží písma, neinstaluje je.** Karta TERMINAL FONTS načte zabudovaný řez do `PrivateFontCollection` lokálního pro proces pro živou ukázku, která provede **nulovou** systémovou registraci písem. Volba písma, velikosti (7–24 pt) nebo režimu vykreslování (aliased/grayscale/cleartype) aktualizuje jen ukázku a preferenci. Instalace písma je výslovná akce **INSTALL SELECTED**, která otevře vlastní instalační program písem systému Windows; po potvrzení systémem Windows uživatel znovu zjišťuje stav tlačítkem Refresh. Skutečné změny terminálu se dějí pouze při výslovné akci **APPLY TERMINAL / APPLY CONHOST / APPLY BOTH**.

Windows Terminal se aplikuje na vybranou nainstalovanou rodinu ve vybrané velikosti a režim vykreslování se mapuje na `profiles.defaults.antialiasingMode`. Klasický conhost je přísnější: vykresluje na pevné mřížce buněk, takže vybrané písmo se odmítne před jakoukoli změnou registru, pokud ho Windows nerozpozná (výchozí řez a záložní Consolas mají výjimku). Health a Reapply porovnají nastavený řez, velikost a vyhlazování s preferencí, takže změna preference po Apply se nahlásí jako odchylka, a ne jako stav "zdravý". Životní cyklus barev terminálu zůstává nedotčený: Revert obnoví přesné hodnoty vlastněné před Wintagem a nikdy neodebere písmo ze stroje.
<!-- source-digest: desktop/README.md sha256:15c96dac8494ab84 -->
