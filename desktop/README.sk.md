# Wintage pre desktopové aplikácie

Userscript tematizuje web. Toto tematizuje programy okolo neho, z rovnakých paliet, aby prehliadač a aplikácie prestali byť nezhodní v tom, čo znamená tmavo zlatá.

Za každým rozhodnutím tu stojí jedno pravidlo: **aplikácie sa aktualizujú samy a aktualizácia nesmie nič ticho rozbiť.** Kde má cieľ miesto vo vašom vlastnom profile, téma ide tam a prežije aktualizácie. Kde nie, inštalátor je napísaný na opätovné spustenie — a hovorí to, namiesto predstierania, že pretrval.

## GUI

Dvakrát kliknite na **`Wintage Installer.vbs`** v koreni repozitára a otvorí sa bez okna konzoly, alebo to spustite priamo na diagnostiku:

```powershell
powershell -File desktop\WintageInstaller.ps1
```

Zoznam tém s farebnými vzorkami, ciele nájdené na tomto počítači, živý Win95-náhľad a všetkých dvadsaťjeden farebných tokenov ako upraviteľné swatche. Úprava ktoréhokoľvek swatchu rozvetví paletu na **Custom** namiesto zmeny vydanej témy popod vás. Panel vpravo zobrazuje živý WCAG-kontrast pre tri tokeny nesúce text — paletu, ktorá tam zlyhá, build brána aj tak odmietne, takže je lepšie ju vidieť pred Apply ako po ňom.

Ciele sú rozdelené do dvoch zoznamov dosiahnuteľných klávesnicou: **MY APPS** obsahuje prenosné/zdrojové nástroje CodeNomad, WorkBuddy; **POPULAR APPS** obsahuje Windows, OBS, terminály, editory a ďalší nainštalovaný softvér. ALL/NONE a Apply/Revert fungujú na oboch zoznamoch bez zmeny ich zoskupenia.

Okno nosí paletu, ktorú sa chystá nainštalovať. To je najrýchlejší dostupný náhľad a udržiava nástroj čestný: paleta, ktorá robí toto okno nečitateľným, je viditeľne nečitateľná.

Apply deleguje na `install.ps1`. Existuje presne jedna cesta kódu, ktorá inštaluje tému, takže GUI sa nemôže odchýliť od príkazového riadku.

## Príkazový riadok

```powershell
.\desktop\install.ps1                                  # čo je tu, čo je tematizované, s akou paletou
.\desktop\install.ps1 -Target freebuff -Palette klite  # jedna aplikácia, jedna paleta
.\desktop\install.ps1 -Target all -Palette goldendefault # všetko
.\desktop\install.ps1 -Target all -WhatIf              # povedať, čo by sa zmenilo, nič nedotknúť
.\desktop\install.ps1 -Target freebuff -Revert         # vrátiť jednu
```

`-Palette` má predvolené `goldendefault` (**Golden Default**). GUI sa otvára na rovnakej palete a kontroluje každý dostupný cieľ. Premaľovanie už tematizovanej aplikácie funguje, kým beží; prvá inštalácia nie, pretože archív sa používa.

## Čo každý cieľ môže byť vlastne tematizovaný

| cieľ | mechanizmus | prežije aktualizáciu aplikácie |
|---|---|---|
| `windows` | používateľský `.theme`: tmavý systémový/aplikačný režim, akcent a klasické farebné roly | áno — nainštalované vo vašom lokálnom priečinku Windows Themes |
| `browsers` | deteguje nainštalované + prenosné profily Chromium, pripraví vybranú chrome tému a otvorí vlastné stránky potvrdenia Tampermonkey/témy prehliadača | áno po jednom **Load unpacked** na profil |
| `terminal` | schéma Windows Terminal + predvolené nastavenia všetkých profilov, Consolas 12 s aliasom | áno — nastavenia sú vo vašom profile |
| `conhost` | predvolené `HKCU\Console` + každý existujúci profil cmd/PowerShell | áno — presná snímka dotknutých hodnôt |
| `obs` | OBS 30.2+ `.ovt` variant + aktívne ID témy v `user.ini` | áno — žije vo vašom profile |
| `qbittorrent` | rozbalená Qt UI téma (`config.json` + `stylesheet.qss`) + dva kľúče témy v `qBittorrent.ini` | áno — žije vo vašom profile |
| `antigravity`, `vscode` | rozšírenie farebnej témy v `~/.antigravity/extensions` / `~/.vscode/extensions` | **áno** — žije vo vašom profile |
| `freebuff`, `antigravity-app`, `codenomad` | Electron shim, pozri nižšie | nie — znova spustite inštalátor |
| `claude` | Electron shim, opravený na mieste — pozri nižšie | nie — aktualizácia vytvorí nový priečinok `app-<verzia>` |
| `mpchc` | register, tmavá téma + typografia OSD len | nie — MPC-HC prepíše svoje nastavenia pri ukončení |
| `obsidian` | komunitná téma na trezor, všetky palety nainštalované naraz | **áno** — žije vo vašom trezore |
| `discord` | CSS vložené do vlastného priečinka tém BetterDiscord | áno |
| `totalcmd`, `totalcmd2` | kľúče `wincmd.ini` `[Colors]`; existujúce filtre nedávnych súborov používajú farbu odkazu palety | áno — je to váš ini |

### Odstránenie reklám FreeBuff

FreeBuff (desktopová aplikácia AI asistenta) dodáva vlastnú reklamnú sieť: renderer bundle (`resources/orchestrator/ui/assets/index-*.js`) renderuje kartu `sponsored-ad` a banner vlákna a orchestrátor (`resources/orchestrator/orchestrator.js`) vystavuje trasy `/api/ad/slot|impression|click`, ktoré volajú vzdialenú reklamnú aukciu. Shim len tematizuje aplikáciu; nedotýka sa týchto súborov.

`desktop/patch-freebuff-ads.js` vyrezáva reklamy na úrovni bajtov:

- renderer: miesta volania reklamnej karty/bannera sa stanú `null` a metódy API klienta `adSlot` / `adImpression` / `adClick` sa stanú no-ops — nič sa nerenderuje a žiadny `/api/ad/*` požiadavok neopustí renderer;
- orchestrátor: všetky tri trasy `/api/ad/*` prestanú volať reklamnú sieť a inline požiadavka reklamy živého ťahu (`maybeRequestAd`) je skratovaná.

Názov bundle obsahuje hash buildu, takže patch objaví aktuálny bundle z `index.html` namiesto dodania verziou uzamknutého payloadu — to je to, čo mu umožňuje prežiť aktualizácie. Originály sú zálohované do `_orig-backup-<časová pečiatka>/` v inštalačnom priečinku; `--revert` obnoví najnovší.

**Budúce verzie sa riešia na dvoch nezávislých úrovniach:**

1. **Bajtový patch s regex fallbackmi.** Každý cieľ má presný reťazec pre aktuálny build *a* fallback na regulárny výraz zakotvený v tom, čo minifikátor nevie premenovať — literály cesty `/api/ad/*`, diskriminátor protokolu `case"ad":`, trieda `sponsored-ad` a umiestnenia `variant:"banner"` / `variant:"card"`. Orchestrátor nie je minifikovaný (čitateľné názvy ako `maybeRequestAd` a `app.ads.slotAd`), takže jeho presné reťazce vydržia dlho; renderer bundle je minifikovaný, takže jeho regex fallbacky prevezmú riadenie v momente, keď ďalší build premenuje jeho identifikátory.
2. **Blokovanie na úrovni shimu (`targets/electron/shim.cjs`).** Úplne nezávislé od bundle: akýkoľvek fetch/XHR na URL `/api/ad/` je odmietnutý v rámci stránky a akýkoľvek prvok, ktorého trieda obsahuje `sponsored-ad`, je skrytý v momente, keď sa objaví. Dokonca ani úplne nový bundle, ktorý tento skript ešte nepozná, nemôže zobraziť reklamu.

```powershell
node .\desktop\patch-freebuff-ads.js           # patch (najprv zálohuje)
node .\desktop\patch-freebuff-ads.js --sound "C:\...\my.mp3"   # patch + vlastný zvuk dokončenia (wav/mp3/ogg/flac/m4a/aac)
node .\desktop\patch-freebuff-ads.js --scan    # aké reklamné markery nesie TENTO build?
node .\desktop\patch-freebuff-ads.js --verify
node .\desktop\patch-freebuff-ads.js --revert
```

Spúšťa sa automaticky ako súčasť `install.ps1 -Target freebuff` a musí sa znova spustiť po každej aktualizácii FreeBuff (aktualizácie obnovia štandardné súbory). Ak build zmení tvar, skript pomenuje cieľ, ktorý už nezodpovedal — spustite `--scan`, aby ste videli, čo nový build stále nesie, a obnovte tam reťazce.

**Zvuk dokončenia FreeBuff.** Renderer prehráva `chime-<hash>.mp3`, keď sa ťah skončí. Patch ho nájde rovnako, ako nájde bundle (názov obsahuje hash buildu), takže `--sound <súbor>` nainštaluje váš vlastný zvuk (wav/mp3/ogg/flac/m4a/aac) cez neho a ponechá štandardný súbor ako `chime-*.mp3.bak`; `--revert` ho obnoví. `--verify` hlási, ktorý je aktívny.

### Tlačidlo zvuku FreeBuff (GUI)

`WintageInstaller.ps1` má malé tlačidlo **FB SOUND** pod stohom APPLY / REVERT. Ukladá iba *preferenciu*; `install.ps1 -Target freebuff` číta rovnaký súbor a odovzdá ho patchi ako `--sound`, takže reklamy a zvuk sa aplikujú v jednom behu:

- **Ľavé kliknutie** — vyberte zvukový súbor (OpenFileDialog, wav/mp3/ogg/flac/m4a/aac) a okamžite ho počujte prehrať: PCM WAV cez System.Media.SoundPlayer, každý iný formát cez WPF MediaPlayer (Media Foundation, asynchrónne, takže okno nikdy nezmrzne). Voľba sa pamätá v `%APPDATA%\Wintage\freebuff-sound.txt` (na zariadenie, mimo git check-out, presne ako zapamätané priečinky zdrojového kódu).
- **Pravé kliknutie** — vymazať preferenciu späť na štandardný chime FreeBuff (tiež zastaví akýkoľvek náhľad, ktorý ešte hrá).
- **COPY** — skopíruje vybraný zvuk do samotného repozitára (`sounds\freebuff.<ext>`, zachová príponu zdroja) a presmeruje preferenciu na túto kópiu, takže zvuk prežije vymazanie alebo presun pôvodného súboru. Povolené len kým je nastavený vlastný zvuk; opätovné kopírovanie jednoducho prepíše kópiu v repozitári. Priečinok `sounds/` je bežný git-sledovateľný obsah, takže jeho commitom zvuk prežije aj re-klony.

Prehliadajú sa len rozpoznané zvukové kontajnery — hlavička sa najprv oňuchá, takže výber nie-ária sa oznámi namiesto tichého prehrávania ničoho.

Tlačidlo ukazuje `ON`, kým je nastavený vlastný zvuk; hover zobrazí cestu. Potom aplikujte cieľ `freebuff` (zaškrtnite FreeBuff + APPLY, alebo spustite `install.ps1 -Target freebuff` z terminálu), aby sa to prejavilo.

### Terminály

`terminal` zapisuje farebnú schému `Wintage` do každého zisteného stabilného, Preview alebo nebaleného súboru nastavení Windows Terminal a vyberie ju cez `profiles.defaults`, spolu s konzolovo bezpečným Consolas 12 a aliasovaným textom. Pôvodný súbor je ponechaný byte-za-byte vedľa neho a `-Revert` ho obnoví.

`conhost` pokrýva klasický `cmd.exe`, Windows PowerShell, konzolové profily Git CMD/Bash a ďalšie existujúce deti `HKCU\Console`. Zapisuje úplnú 16-farebnú tabuľku palety do koreňových predvolieb aj do každého existujúceho prekrytia a potom obnoví iba hodnoty, ktorých sa dotkol. Aplikuje Consolas aj tam, pretože proporcionálna Verdana koliduje v rámci mriežky pevných buniek, ktorú používajú obaja hostitelia terminálov.

### Prehliadače a Tampermonkey

`browsers` nájde profily Chrome, Edge, Brave, Cent, Vivaldi a Opera z nainštalovaných umiestnení a z prenosného koreňa, na ktorý ho nasmerujete (`-PortableRoot`, alebo zapamätaný záznam `portable` v `paths.json`). Jeho stav ukazuje počet profilov aj to, koľko obsahuje Tampermonkey. Apply skopíruje vybranú chrome tému prehliadača do stabilného priečinka `%LOCALAPPDATA%\Wintage\browser-theme`, vloží túto cestu do schránky a otvorí každý presný profil na `chrome://extensions` plus stránku Inštalácia/Aktualizácia userscriptu Wintage. Profily bez Tampermonkey tiež dostanú jeho stránku Chrome Web Store.

Chromium zámerne zakazuje tichú inštaláciu rozšírení mimo obchodu na nespravovanom počítači so systémom Windows. Prvá inštalácia témy prehliadača preto vyžaduje jedno potvrdenie **Developer mode → Load unpacked** na profil. Vyberte skopírovanú cestu; potom Wintage naďalej nahrádza rovnaký stabilný priečinok, keď sa palety menia. Potvrďte aj **Install/Update** v Tampermonkey. Žiadny súbor `Preferences`, Secure Preferences alebo Tampermonkey LevelDB prehliadača nie je upravovaný za chrbtom prehliadača. Ak Tampermonkey nebol prítomný, nainštalujte ho z otvorenej karty obchodu a obnovte už otvorenú kartu `wintage.user.js`, aby sa zobrazila obrazovka Inštalácia.

### Windows

`windows` nainštaluje a okamžite aktivuje obsahovo adresovaný `%LOCALAPPDATA%\Microsoft\Windows\Themes\Wintage-<hash>.theme`. Začína z aktívnej témy a nahrádza iba zdokumentované sekcie farieb, kurzorov a vizuálneho štýlu. Tapeta, zvuky a ikony pracovnej plochy zostávajú nezmenené; kurzory zámerne prepnú na nainštalovanú schému `___CURRENT___`. Prvá aktívna téma je uložená byte-za-byte ako `Wintage.original.theme`; zmeny palety zachovávajú túto základnú líniu a `-Revert` ju znova aktivuje. Moderné ovládacie prvky Windows stále pochádzajú z podpísaného vizuálneho štýlu Aero — Wintage mení jeho podporované vstupy tmavého režimu, akcentu a klasických systémových farieb namiesto nahrádzania chránených súborov `.msstyles`. Aktívne a neaktívne titulky zdieľajú tlmenú zvýšenú farbu povrchu palety; jasné zvýraznenie zostáva vyhradené pre okraje textu/výberu. Predchádzajúci neaktívny akcent titulky je snímkovaný samostatne a `-Revert` ho presne obnoví. Hash obsahu dáva systému Windows nový cieľ asociácie súborov, keď sa rovnaká paleta prestavuje, takže opätovné aplikovanie aktualizovanej palety nie je zamenené za no-op; zastaraný súbor Wintage sa odstráni po tom, čo systém Windows potvrdí nový ako aktívny.

### OBS Studio

`obs` generuje variant OBS 30.2+ nad udržiavanou základňou Yami Classic, nainštaluje ho do `%APPDATA%\obs-studio\themes` a zapíše svoje stabilné ID témy do `user.ini`, takže vybraná paleta Wintage je už vybraná pri ďalšom spustení. Zatvorte OBS pred Apply alebo Revert: OBS prepíše `user.ini` pri ukončení. Prvé aplikovanie zálohuje predchádzajúci výber aj akúkoľvek tému s rovnakým názvom byte-za-byte.

### qBittorrent

`qbittorrent` zapisuje **rozbalenú** Qt tému rozhrania do `%APPDATA%\qBittorrent\themes\wintage` — súbor `config.json` (roly `Palette.*` plus vlastné kontextové farby qBittorrentu: stavy zoznamu prenosov, závažnosti denníka) a vedľa neho `stylesheet.qss` (2px skosenia, pravé rohy a Verdana, čo paleta nedokáže vyjadriť) — potom nasmeruje `General\CustomUIThemePath` na tento `config.json` a nastaví `General\UseCustomUITheme=true`.
Rozbalene, a nie ako balík `.qbtheme` — zámerne: `.qbtheme` je súbor typu Qt Resource Collection a na jeho vytvorenie by bol na stroji potrebný `rcc` so zhodnou hlavnou verziou, teda závislosť na prekladači kvôli dvom textovým súborom. qBittorrent číta priečinkovú podobu natívne (`FolderThemeSource`).
Pred Apply alebo Revert qBittorrent zatvorte: pri ukončení prepisuje celý `qBittorrent.ini`, takže úprava vykonaná počas behu sa pri zatvorení zahodí — cieľ v takom stave odmietne pracovať, namiesto toho, aby hlásil úspech, ktorý nasledujúce ukončenie zmaže. `-Revert` vráti dva kľúče v INI na presné hodnoty pred Wintage (alebo ich odstráni, ak neboli) a vráti každý rovnomenný priečinok témy bajt po bajte; nesúvisiace úpravy `qBittorrent.ini` vykonané po Apply ostanú.
Nedostupné: ikony panela nástrojov a oznamovacej oblasti pochádzajú z vlastného skompilovaného balíka zdrojov qBittorrentu, takže si zachovávajú pôvodné farby.

### Písmo: pomenované, nikdy sa neinštalujú

Zákon 1 z UI.md žiada Verdana **bez antialiasingu**. Stylesheet Qt nemá vlastnosť, ktorá by to umožnila, a `OSDFont` v MPC-HC je iba názov písma GDI — jedinou pákou je teda samotné písmo. `Verdana_m1.ttf` v koreňi repozitára je kópia Verdany s vopred vykreslenými 1bpp bitmapovými úsekmi od 3 do 30 ppem, ktoré vykresľovanie použije namiesto vyhladzovania obrysu.
Stylesheety `qbittorrent` a `obs` uvádzajú `Verdana_m1, Verdana` a `mpchc` uvádza ten z oboch, ktorý stroj skutočne vyrieši. **Inštalátor nikdy písmo neinštaluje ani neodinštaluje** a to je zámer, nie nedokončená práca:
Rodina písiem sa rieši podľa (rodina, štýl). Zaregistrujte Regular + Bold + Italic a každý spotrebiteľ sa vyrieši správne; odregistrujte **jeden** člen a každý spotrebiteľ žiadajúci tú rodinu sa presmeruje na preživšieho člena. Na stroji, ktorý aliasuje `MS Shell Dlg 2` — písmo dialógov Windows — na tú rodinu cez `HKLM\...\FontSubstitutes`, odstránenie Regular otočí **celú plochu kurzívne**, vrátane nadpisov okien, ktoré DWM už cacheoval, a na obnovenie treba odhlásenie. Žiadne počítanie referencií to neopraví: dopad je celo-strojový a inštalátor motívu do toho nemá čo riekať.
Písmo je teda jednorazový výslovný krok používateľa: pravý klik na `Verdana_m1.ttf` → **Inštalovať** (pre používateľa, bez práv správcu) a potom znova aplikujte cieľ. Ak písmo chýba, ciele to povedia raz, pomenujú opravu a vrátia sa na štandardnú Verdana — s antialiasingom, ale bez toho, aby sa niečo robilo na vašom stroji za vaším chrbátom.

### Aplikácie Electron

`resources/app.asar` sa presunie do `resources/app/app.asar` (jeho súrodenec `app.asar.unpacked` sa presúva s ním — to párovanie je podľa názvu súboru a oddelenie rozbije každý natívny modul) a malý `shim.cjs` zaberie uvoľnený slot `resources/app`. Shim vstrekne štýlový list a potom načíta pôvodný archív. **Žiadny bajt aplikácie nie je prepísaný**, iba presunutý; `-Revert` ho presunie priamo späť.

Štýlový list nie je napísaný pre tieto aplikácie — je extrahovaný z `wintage.user.js`, takže každá oprava fasety, scrollbaru a typovej stupnice vytvorená pre prehliadač sa dostane aj sem, bez druhej kópie, ktorá by hnilá.

Dve poznámky, ktoré sa oplatí mať vopred:

- Zjavný prístup — vložiť `resources/app` vedľa archívu a spoliehať sa, že Electron ho uprednostní — **nefunguje a ticho zlyháva**. Electron najprv hľadá `app.asar`. Aplikácia sa spustí perfektne a téma nikdy nebeží.
- Shim je `.cjs`, nie `.js`, zámerne. Jeho `package.json` je skopírovaný z vlastného `package.json` aplikácie, takže aplikácia si zachová názov a verziu (názov rozhoduje, kde žije userData — shim, ktorý ho premenuje, presunie aplikáciu do prázdneho profilu). Ak manifest hovorí `"type": "module"`, `.js` shim zomrie na svojom prvom `require`.

### Desktopová aplikácia Claude: na mieste a rám, v ktorom skutočne kreslí

Claude nemôže použiť presun vyššie, pretože `OnlyLoadAppFromAsar` je zatavené — Electron načíta `resources/app.asar` a nič iné, takže shim v `resources/app` nikdy nemôže bežať. Je opravený **na mieste** namiesto toho: archív je zálohovaný, jeho `main` v `package.json` je prepísaný na `"../wintage-shim.cjs"` (doplnený na rovnakú dĺžku bajtov, aby každý offset v archíve zostal platný) a hash integrity každého súboru je aktualizovaný, aby zodpovedal. `-Revert` obnoví zálohu.

Inštalátor stále číta fuses **predtým, než čokoľvek presunie**, a odmieta s dôvodom, keď ho blokujú — `EnableEmbeddedAsarIntegrityValidation` by spôsobil zlyhanie prepisu vyššie pri spustení namiesto pri inštalácii. Skontrolujte akúkoľvek aplikáciu sami:

```powershell
node ..\tools\electron-fuses.js "<cesta k exe aplikácie>"
```

Druhá polovica tohto bola oveľa tichší problém. `BrowserWindow` Claude renderuje tenkú škrupinu a **celá viditeľná aplikácia je `WebContentsView`** pripojená k nej. Shim kedysi hákol `browser-window-created`, takže vstrekol štýlový list do škrupiny, hlásil úspech do `wintage-status.txt` a nezmenil nič viditeľné. Teraz háka `web-contents-created`, ktorý pokrýva obsah okna, `WebContentsView`, `BrowserView`, hostí `<webview>` a vyskakovacie okná rovnako.

### Obsidian

Komunitná téma sa zapíše do `.obsidian/themes/` každého trezora — všetkých šestnásť paliet naraz, presne ako cieľ VS Code, takže medzi nimi prepínate v **Settings → Appearance** bez opätovného spúšťania čohokoľvek. Šablóna bola odvodená z ručne vyrobenej témy `VintageWin95`, ktorá už bola v trezore, každá farba nahradená tokenom, ktorému sa rovnala. `-Palette <slug>` nastaví, ktorá je aktívna pri inštalácii; `appearance.json` sa najprv zálohuje a `-Revert` odstráni iba témy `Wintage *` a obnoví vašu predchádzajúcu voľbu — ručne vyrobená téma v rovnakom trezore sa nikdy nedotkne.


### MPC-HC (K-Lite)

Natívny Win32, bez štýlového listu a bez bodu vstreknutia, a farby jeho tmavej témy sú skompilované do programu — žiadna hodnota registra ich nevystavuje. Takže tento cieľ **nemôže niesť paletu**. Čo robí: zapne tmavú tému a aplikuje pravidlá typografie UI.md na OSD, čo je jediný povrch, ktorý MPC-HC nechá používateľa ovládať. Predchádzajúce nastavenia sa najprv exportujú do `desktop/backup/mpc-hc-settings.reg`.

Zatvorte MPC-HC pred aplikovaním: pri ukončení prepíše svoje nastavenia.

## Prestavba

Všetko pod `desktop/out/` sa generuje z `themes/*.json`. Nesleduje sa v gite (T-160), takže čerstvý klon ho musí postaviť raz pred inštaláciou:

```powershell
node ..\tools\build-desktop.js          # prestavať všetky ciele
node ..\tools\build-desktop.js --check  # ukončiť 1, ak je niečo zastarané
```

`release.ps1` spúšťa build a každú bránu, takže vydanie nemôže odoslať výstup, ktorý sa odchýlil od paliet.

<!-- T-311 target/section coverage supplement -->
## Pokrytie cieľov a sekcií

Táto sekcia zrkadlí pokrytie aktuálneho anglického README pre Process Explorer, Notepad++, Cinema 4D a písma terminálov, aby táto lokalizácia potichu nezostala zaostarávajúca. Literály kódu (identifikátory cieľov, cesty v registri, názvy súborov) sú jazykovo nezávislé už zo zadania; okolitý text je tu preložený.

### Čo sa z každého cieľa dá skutočne tematizovať (pridané ciele)

| cieľ | mechanizmus | prežije aktualizáciu aplikácie |
|---|---|---|
| `notepadplusplus` | XML témy + alias do priečinka `themes` vášho Notepad++ | áno — žije vo vašom profile |
| `cinema4d` | farebná schéma vložená do priečinka `schemes` vášho Cinema 4D | áno — žije vo vašom profile |
| `processexplorer` | `HKCU\Software\Sysinternals\Process Explorer`: farby zvýraznenia riadkov a pozadia grafov, viď nižšie | nie — Process Explorer si pri ukončení prepíše nastavenia; zavrite ho a spustite znova |

### Process Explorer (Sysinternals)

Process Explorer si drží farby v `HKCU\Software\Sysinternals\Process Explorer` a pri ukončení tento kľúč prepíše, preto cieľ **odmietne, kým beží `procexp`, `procexp64` alebo `procexp64a`** — zavrite ho a spustite znova. Tematizuje nastaviteľné farebné kategórie:

- **dostupné**: farby zvýraznenia riadkov procesov (`ColorOwn`, `ColorServices`, `ColorRelocatedDlls`, `ColorImmersive`, `ColorPacked`, `ColorJobs`, `ColorNet`, `ColorProtected`, `ColorNewProc`, `ColorDelProc`, `ColorSuspend`) v svetlom režime aj v ich variantoch `*Dark`, plus pozadia grafov (`ColorGraphBk`, `ColorGraphBkDark`) — spolu 24 hodnôt. Každá varianta sa mieša s zodpovedajúcim pólom aktívnej palety (svetlejší odtieň pre výplň v svetlom režime, tmavší odtieň pre `*Dark`), takže výplne riadkov zostávajú v kľúči samotnej palety namiesto toho, aby sa pastelizovali takmer na bielu;
- **nedostupné**: titulná lišta, ponuková lišta, lišta nástrojov, pozadie a farby textu v zoznamovom zobrazení a farby čiar grafov — tie sú skompilované do `procexp.exe` a žiadna hodnota nastavenia ich neodhaľuje. Cieľ tematizuje zvýraznenie riadkov a pozadie grafu, ktoré mu naozaj patria, a netvrdí nič viac.

Každá hodnota, ktorú Apply dokáže zmeniť, je uložená ako snímka pred zmenou (obnova pri prvom dotyku v `%APPDATA%\Wintage\recovery\processexplorer\`) a `-Revert` ju obnoví presne, vrátane informácie, či hodnota chýbala a či značka existovala, ale bola prázdna. Prenosný priečinok mimo štandardných adresárov Sysinternals sa pamätá cez kanónický kľúč `paths.json` `processexplorer` (CLI argument `-ProcessExplorerPath`; GUI ho tiež vie vybrať).

### Písma terminálov (`fonts/terminal/`)

Oba terminálové ciele čítajú JEDINÚ kanónickú typografickú preferenciu z `%APPDATA%\Wintage\terminal-font.json` (`schema`, `fontSlug`, `family`, `size`, `renderingMode`). Keď súbor chýba, ciele si ponechajú dodané predvolené hodnoty (Terminus (TTF) for Windows, 12 pt, aliased), takže existujúce stroje zostávajú nezmenené. Chybná preferencia zlyhá uzavreto: nič sa neprepíše a cieľ odmietne.

`fonts/terminal/catalog.json` je jediný katalóg písiem: 20 zabudovaných open-source monospace rodín plus dva systémové rezy, ktoré Wintage pomenuje, ale nikdy neposiela (Terminus (TTF) for Windows, Consolas). Každá zabudovaná položka nesie svoj upstream zdroj, pripnutú revíziu, ID licencie, súbor licencie a SHA-256. Presné súbory sú vendrované pod `fonts/terminal/files/` a texty licencií pod `licenses/`; Wintage za behu pracuje úplne offline a nikdy nestiahne písmo.

`tools/sync-terminal-fonts.ps1` je sťahovač len pre správcov. Číta `fonts/terminal/sources.json` (jeden nemenný artefakt na rodinu), overí každé SHA-256 a pri nezhodí odmietne. `-VerifyOnly` (predvolene) kontroluje strom na disku bez siete; `-Fetch -Write` ho znovu vendruje. Stiahnuté bajty písiem sa považujú za nedôveryhodné binárne aktíva — hashované a zapísané, nikdy vykonané. Jedna náhrada je zaznamenaná: **Fantasque Sans Mono** nahrádza Liberation Mono, ktorý nepublikuje žiadnu pripnutú binárnu release (iba zdroj `.sfd`).

Inštalátor **prebrowse písma, neinštaluje ich.** Karta TERMINAL FONTS načíta zabudovaný rez do procesne lokálnej `PrivateFontCollection` na živý náhľad, ktorý vykoná **nula** systémových registrácií písem. Voľba písma, veľkosti (7–24 pt) alebo režimu vykresľovania (aliased/grayscale/cleartype) aktualizuje len náhľad a preferenciu. Inštalácia písma je výslovná akcia **INSTALL SELECTED**, ktorá otvorí vlastný inštalačný program písem systému Windows; po potvrdení Windows používateľ znovu zistí stav cez Refresh. Skutočné zmeny terminálu sa dejú len pri výslovnej akcii **APPLY TERMINAL / APPLY CONHOST / APPLY BOTH**.

Windows Terminal sa aplikuje na vybranú nainštalovanú rodinu vo vybranej veľkosti a režim vykresľovania sa mapuje na `profiles.defaults.antialiasingMode`. Klasický conhost je prísnejší: vykresľuje na pevnej mriežke buniek, takže vybrané písmo sa odmietne pred akoukoľvek zmenou v registri, pokiaľ ho Windows nerozpozná (predvolený rez a záloha Consolas majú výnimku). Health a Reapply porovnajú nastavený rez/veľkosť/antialiasing s preferenciou, takže zmena preferencie po Apply sa nahlási ako odchýlka, nie ako zdravý stav. Životný cyklus farieb terminálu zostáva nedotknutý: Revert obnoví presné hodnoty vlastnené pred Wintage a nikdy neodstráni písmo zo stroja.
<!-- source-digest: desktop/README.md sha256:15c96dac8494ab84 -->
