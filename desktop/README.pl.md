# Wintage dla aplikacji desktopowych

Userskrypt motywuje sieć. To motywuje otaczające ją programy, z tych samych
palet, żeby przeglądarka i aplikacje przestały się nie zgadzać co do tego, co
znaczy ciemne złoto.

Za każdą decyzją tutaj stoi jedna zasada: **aplikacje aktualizują się same, a
aktualizacja nie może po cichu niczego zepsuć.** Tam, gdzie target ma miejsce w
twoim własnym profilu, motyw trafia tam i przetrwa aktualizacje. Tam, gdzie nie ma,
instalator jest napisany tak, by można go było uruchomić ponownie — i mówi to
wprost, zamiast udawać, że coś utrwalił.

## GUI

Kliknij dwukrotnie **`Wintage Installer.vbs`** w katalogu głównym repo, aby go
otworzyć bez okna konsoli, albo uruchom bezpośrednio to, do celów diagnostycznych:

```powershell
powershell -File desktop\WintageInstaller.ps1
```

Lista motywów z próbkami kolorów, targety znalezione na tej maszynie, podgląd
Win95 na żywo oraz wszystkie dwadzieścia jeden tokenów kolorów jako edytowalne
próbki. Edycja dowolnej próbki rozgałęzia paletę na **Custom**, zamiast zmieniać
dostarczony motyw pod tobą. Panel po prawej pokazuje na żywo kontrast WCAG dla
trzech tokenów niosących tekst — paleta, która tam nie przechodzi, i tak zostanie
odrzucona przez bramkę builda, więc lepiej zobaczyć to przed Apply niż po.

Targety są podzielone na dwie osiągalne z klawiatury listy: **MY APPS** zawiera
przenośne/drzewo-źródłowe narzędzia CodeNomad, SAIPENVIEW, SmartVac i WildRift;
**POPULAR APPS** zawiera Windows, OBS, terminale, edytory i inne zainstalowane
oprogramowanie. ALL/NONE i Apply/Revert działają na obu listach bez zmiany ich
grupowania.

Okno nosi paletę, którą ma zaraz zainstalować. To najszybszy dostępny podgląd i
utrzymuje narzędzie uczciwym: paleta, która czyni to okno nieczytelnym, jest
widocznie nieczytelna.

Apply wywołuje `install.ps1`. Jest dokładnie jedna ścieżka kodu instalująca
motyw, więc GUI nie może oddalić się od linii poleceń.

## Linia poleceń

```powershell
.\desktop\install.ps1                                  # co tu jest, co jest motywowane i jaką paletą
.\desktop\install.ps1 -Target freebuff -Palette klite  # jedna aplikacja, jedna paleta
.\desktop\install.ps1 -Target all -Palette goldendefault # wszystko
.\desktop\install.ps1 -Target all -WhatIf              # pokaż, co by się zmieniło, niczego nie dotykaj
.\desktop\install.ps1 -Target freebuff -Revert         # cofnij jedną
```

`-Palette` domyślnie przyjmuje `goldendefault` (**Golden Default**). GUI otwiera
się na tej samej palecie i sprawdza każdy dostępny target. Przemalowanie aplikacji,
która już jest motywowana, działa, gdy działa ona na bieżąco; pierwsza instalacja
nie, bo archiwum jest w użyciu.

## Co właściwie można zmotywować w każdym targetu

| target | mechanizm | przetrwa aktualizację aplikacji |
|---|---|---|
| `windows` | `.theme` użytkownika: ciemny tryb systemu/aplikacji, kolor akcentu i klasyczne role kolorów | yes — zainstalowany w twoim lokalnym folderze Windows Themes |
| `browsers` | wykrywa zainstalowane + przenośne profile Chromium, przygotowuje wybrany motyw chrome i otwiera należące do przeglądarki strony potwierdzenia Tampermonkey/motywu | yes — po jednym **Load unpacked** na profil |
| `terminal` | schemat Windows Terminal + domyślne dla wszystkich profili, Consolas 12 aliased | yes — ustawienia są w twoim profilu |
| `conhost` | domyślne `HKCU\Console` + każdy istniejący profil cmd/PowerShell | yes — dokładny snapshot dotkniętych wartości |
| `obs` | wariant `.ovt` dla OBS 30.2+ + aktywny identyfikator motywu w `user.ini` | yes — żyje w twoim profilu |
| `antigravity`, `vscode` | rozszerzenie motywu kolorów w `~/.antigravity/extensions` / `~/.vscode/extensions` | **yes** — żyje w twoim profilu |
| `freebuff`, `antigravity-app`, `codenomad` | shim Electrona, patrz poniżej | no — uruchom ponownie instalator |
| `claude` | shim Electrona, łatany na miejscu — patrz poniżej | no — aktualizacja tworzy nowy folder `app-<version>` |
| `mpchc` | rejestr, ciemny motyw + tylko typografia OSD | no — MPC-HC nadpisuje swoje ustawienia przy zamykaniu |
| `obsidian` | motyw społeczności per vault, wszystkie palety zainstalowane naraz | **yes** — żyje w twoim vault |
| `saipenview` | nadpisuje własne wartości tokenów `:root` w `style.css` | no — plik źródłowy; uruchom ponownie po pull |
| `discord` | CSS wrzucony do własnego folderu motywów BetterDiscord | yes |
| `totalcmd`, `totalcmd2` | klucze `wincmd.ini` `[Colors]`; istniejące filtry ostatnich plików używają koloru linku palety | yes — to twój ini |
| `smartvac`, `wildrift` | tabela tokenów nadpisana we własnym źródle aplikacji | no — plik źródłowy; uruchom ponownie po pull |

### Usuwanie reklam FreeBuff

FreeBuff (desktopowa aplikacja asystenta AI) dostarcza własną sieć reklamową:
bundle renderera (`resources/orchestrator/ui/assets/index-*.js`) renderuje kartę
`sponsored-ad` i baner wątku, a orkiestrator (`resources/orchestrator/orchestrator.js`)
udostępnia trasy `/api/ad/slot|impression|click`, które wywołują zdalną aukcję
reklam. Shim tylko motywuje aplikację; nie dotyka tych plików.

`desktop/patch-freebuff-ads.js` wycina reklamy na poziomie bajtów:

- renderer: miejsca wywołań karty/banera reklamy stają się `null`, a metody klienta
  API `adSlot` / `adImpression` / `adClick` stają się no-opami — nic się nie
  renderuje i żaden `/api/ad/*` nie opuszcza renderera;
- orkiestrator: wszystkie trzy trasy `/api/ad/*` przestają wywoływać sieć
  reklamową, a inline'owe żądanie reklamy przy żywych turach (`maybeRequestAd`)
  jest zwarciowane.

Nazwa pliku bundle'a zawiera hash builda, więc łatka odkrywa bieżący bundle z
`index.html` zamiast dostarczać payload przypięty do wersji — to właśnie pozwala
jej przetrwać aktualizacje. Oryginały są kopiowane zapasowo do
`_orig-backup-<timestamp>/` w katalogu instalacji; `--revert` przywraca najnowszy.

**Przyszłe wersje są obsługiwane na dwóch niezależnych warstwach:**

1. **Łata bajtowa z fallbackami regexowymi.** Każdy target ma dokładny ciąg dla
   bieżącego builda *oraz* fallback oparty na wyrażeniach regularnych, zakotwiczony
   na tym, czego minifier nie może przemianować — literały ścieżek `/api/ad/*`,
   dyskryminator protokołu `case"ad":`, klasa `sponsored-ad` oraz plasowania
   `variant:"banner"` / `variant:"card"`. Orkiestrator nie jest minifikowany
   (czytelne nazwy jak `maybeRequestAd` i `app.ads.slotAd`), więc jego dokładne
   ciągi trzymają się długo; bundle renderera jest minifikowany, więc jego
   fallbacki regexowe przejmują w momencie, gdy następny build przemianuje jego
   identyfikatory.
2. **Blokada na poziomie shima (`targets/electron/shim.cjs`).** Całkowicie
   niezależna od bundle'a: każdy fetch/XHR pod URL `/api/ad/` jest odrzucany
   wewnątrz strony, a każdy element, którego klasa zawiera `sponsored-ad`, jest
   ukrywany w chwili pojawienia się. Nawet całkiem nowy bundle, którego ten skrypt
   się jeszcze nie nauczył, nie może wyświetlić reklamy.

```powershell
node .\desktop\patch-freebuff-ads.js           # łata (najpierw kopia zapasowa)
node .\desktop\patch-freebuff-ads.js --sound "C:\...\my.mp3"   # łata + własny dźwięk zakończenia (wav/mp3/ogg/flac/m4a/aac)
node .\desktop\patch-freebuff-ads.js --scan    # jakie markery reklam niesie TEN build?
node .\desktop\patch-freebuff-ads.js --verify
node .\desktop\patch-freebuff-ads.js --revert
```

Działa automatycznie w ramach `install.ps1 -Target freebuff` i musi być
uruchamiana po każdej aktualizacji FreeBuff (aktualizacje przywracają standardowe
pliki). Jeśli build zmieni kształt, skrypt podaje nazwę targeta, który przestał
pasować — uruchom `--scan`, aby zobaczyć, co nowy build wciąż niesie, i odśwież
tam ciągi.

**Dźwięk zakończenia FreeBuff.** Renderer gra `chime-<hash>.mp3`, gdy tura się
kończy. Łatka znajduje go tak samo, jak znajduje bundle (nazwa zawiera hash
builda), więc `--sound <file>` instaluje nad nim twoje własne audio
(wav/mp3/ogg/flac/m4a/aac) i zachowuje standardowy plik jako `chime-*.mp3.bak`;
`--revert` go przywraca. `--verify` raportuje, który jest aktywny.

### Przycisk dźwięku FreeBuff (GUI)

`WintageInstaller.ps1` ma mały przycisk **FB SOUND** pod stosem APPLY / REVERT.
Zapisuje tylko *preferencję*; `install.ps1 -Target freebuff` czyta ten sam plik i
przekazuje go łatce jako `--sound`, więc reklamy i dźwięk są stosowane w jednym
uruchomieniu:

- **Lewy klik** — wybierz plik audio (OpenFileDialog, wav/mp3/ogg/flac/m4a/aac)
  i od razu go usłyszysz: PCM WAV przez System.Media.SoundPlayer, każdy inny format
  przez WPF MediaPlayer (Media Foundation, asynchronicznie, więc okno nigdy nie
  zamarza). Wybór jest zapamiętywany w
  `%APPDATA%\Wintage\freebuff-sound.txt` (na maszynę, poza checkoutem git,
  dokładnie jak zapamiętane foldery drzewa źródłowego).
- **Prawy klik** — wyczyść preferencję z powrotem do standardowej chime FreeBuff
  (zatrzymuje też każdy wciąż grający podgląd).
- **COPY** — kopiuje wybrane audio do samego repo
  (`sounds\freebuff.<ext>`, zachowując rozszerzenie źródła) i przekierowuje
  preferencję na tę kopię, więc dźwięk przetrwa usunięcie lub przeniesienie
  oryginalnego pliku. Włączony tylko, gdy ustawiony jest własny dźwięk; ponowne
  kopiowanie po prostu nadpisuje kopię w repo. Folder `sounds/` to zwykła treść
  śledzona przez git, więc jej zacommitowanie sprawia, że dźwięk przetrwa też
  ponowne klony.

Podglądane są tylko rozpoznane kontenery audio — nagłówek jest sprawdzany
najpierw, więc wybór nie-audio jest anonsowany zamiast po cichu nic nie grać.

Przycisk pokazuje `ON`, gdy ustawiony jest własny dźwięk; najazd myszą pokazuje
ścieżkę. Zastosuj potem target `freebuff` (zaznacz FreeBuff + APPLY albo uruchom
`install.ps1 -Target freebuff` z terminala), aby zadziałał.

### Terminale

`terminal` zapisuje schemat kolorów `Wintage` do każdego wykrytego stabilnego,
Preview lub nieopakowanego pliku ustawień Windows Terminal i wybiera go przez
`profiles.defaults`, wraz z bezpieczną dla konsoli Consolas 12 i aliased tekstem.
Oryginalny plik jest zachowywany obok bajt po bajcie, a `-Revert` go przywraca.

`conhost` obejmuje klasyczne `cmd.exe`, Windows PowerShell, profile konsoli
Git CMD/Bash i inne istniejące dzieci `HKCU\Console`. Zapisuje pełną 16-kolorową
tabelę palety do domyślnych wartości głównych i każdej istniejącej nadpisywanej
wartości, a potem przywraca tylko wartości, których dotknął. Consolas stosuje tam
też, bo proporcjonalna Verdana koliduje z siatką komórek o stałej szerokości,
której używają oba hosty terminali.

### Przeglądarki i Tampermonkey

`browsers` znajduje profile Chrome, Edge, Brave, Cent, Vivaldi i Opera w
zainstalowanych lokalizacjach i z przenośnego katalogu głównego, na który go
wskazesz (`-PortableRoot`, albo zapamiętany wpis `portable` w `paths.json`). Jego
status pokazuje liczbę profili i to, ile z nich zawiera Tampermonkey. Apply kopiuje
wybrany motyw browser-chrome do stabilnego folderu
`%LOCALAPPDATA%\Wintage\browser-theme`, umieszcza tę ścieżkę w schowku i otwiera
każdy dokładny profil na `chrome://extensions` oraz stronę Instalacji/Aktualizacji
userskryptu Wintage. Profile bez Tampermonkey dostają też stronę Chrome Web Store.

Chromium celowo zabrania cichej instalacji rozszerzeń spoza sklepu na
niezarządzanym komputerze z Windows. Pierwsza instalacja motywu przeglądarki
wymaga więc jednego potwierdzenia **Developer mode → Load unpacked** na profil.
Wybierz skopiowaną ścieżkę; potem Wintage wciąż podmienia ten sam stabilny folder,
gdy palety się zmieniają. Potwierdź też **Install/Update** w Tampermonkey. Żaden
plik `Preferences` przeglądarki, Secure Preferences ani LevelDB Tampermonkey nie
jest edytowany za plecami przeglądarki. Jeśli Tampermonkey nie było, zainstaluj je
z otwartej karty sklepu i odśwież już otwartą kartę `wintage.user.js`, aby dostać
ekran Install.

### Windows

`windows` instaluje i natychmiast aktywuje adresowany treściowo
`%LOCALAPPDATA%\Microsoft\Windows\Themes\Wintage-<hash>.theme`. Zaczyna od
aktywnego motywu i zastępuje tylko udokumentowane sekcje kolorów, kursorów i stylu
wizualnego. Tapeta, dźwięki i ikony pulpitu pozostają niezmienione; kursory celowo
przełączają się na zainstalowany schemat `___CURRENT___`. Pierwszy aktywny motyw
jest zapisywany bajt po bajcie jako `Wintage.original.theme`; zmiany palety
zachowują tę bazę, a `-Revert` aktywuje ją ponownie. Nowoczesne kontrolki Windows
nadal pochodzą z podpisanego stylu wizualnego Aero — Wintage zmienia wspierany
przez niego ciemny tryb, akcent i klasyczne wejścia kolorów systemowych, zamiast
zastępować chronione pliki `.msstyles`. Aktywne i nieaktywne paski tytułowe
dzielą przytłumiony kolor podniesionej powierzchni palety; jasny highlight
pozostaje zarezerwowany dla krawędzi tekstu/zaznaczenia. Poprzedni akcent
nieaktywnego paska jest snapshotowany osobno i przywracany dokładnie przez
`-Revert`. Hash treści daje Windowsowi nowy cel asocjacji plików, gdy ta sama
paleta jest przebudowywana, więc ponowne zastosowanie zaktualizowanej palety nie
jest mylone z no-opem; wyprzedzony plik Wintage jest usuwany, gdy Windows
potwierdzi, że nowy jest aktywny.

### OBS Studio

`obs` generuje wariant OBS 30.2+ na bazie utrzymywanego Yami Classic, instaluje go
w `%APPDATA%\obs-studio\themes` i zapisuje jego stabilny identyfikator motywu do
`user.ini`, więc wybrana paleta Wintage jest już wybrana przy następnym uruchomieniu.
Zamknij OBS przed Apply lub Revert: OBS nadpisuje `user.ini` przy zamykaniu.
Pierwszy apply robi kopię zapasową zarówno poprzedniego wyboru, jak i każdego
motywu o tej samej nazwie, bajt po bajcie.

### Aplikacje Electron

`resources/app.asar` jest przenoszone do `resources/app/app.asar` (jego
`app.asar.unpacked`-bliźniak podąża za nim — to parowanie jest po nazwie pliku, a
rozdzielenie ich psuje każdy natywny moduł), a mały `shim.cjs` zajmuje zwolniony
slot `resources/app`. Shim wstrzykuje arkusz stylów, a potem ładuje oryginalne
archiwum. **Żaden bajt aplikacji nie jest nadpisywany**, tylko przenoszony;
`-Revert` przenosi go z powrotem wprost.

Arkusz stylów nie jest pisany dla tych aplikacji — jest wyodrębniany z
`wintage.user.js`, więc każda poprawka bevelów, pasków przewijania i drabinki
typograficznej zrobiona dla przeglądarki ląduje też tutaj, bez drugiej kopii, która
mogłaby zgnić.

Dwie notatki, które warto znać z wyprzedzeniem:

- Oczywiste podejście — wrzucenie `resources/app` obok archiwum i poleganie na
  tym, że Electron je preferuje — **nie działa i zawodzi po cichu**. Electron
  szuka najpierw `app.asar`. Aplikacja startuje idealnie, a motyw nigdy nie działa.
- Shim jest celowo `.cjs`, nie `.js`. Jego `package.json` jest kopiowany z
  własnego pliku aplikacji, żeby aplikacja zachowała nazwę i wersję (nazwa decyduje,
  gdzie mieszka userData — shim, który ją przemianuje, przenosi aplikację do
  pustego profilu). Jeśli ten manifest mówi `"type": "module"`, `.js`-shim pada
  na pierwszym `require`.

### Aplikacja desktopowa Claude: na miejscu i w ramce, w której faktycznie rysuje

Claude nie może użyć powyższego przeniesienia, bo `OnlyLoadAppFromAsar` jest
wtopione: Electron ładuje `resources/app.asar` i nic poza tym, więc shim w
`resources/app` nigdy nie zadziała. Zamiast tego jest łatany **na miejscu**:
archiwum jest kopiowane zapasowo, `main` w jego `package.json` jest nadpisywany na
`"../wintage-shim.cjs"` (wypełnione do tej samej długości bajtów, więc każdy offset
w archiwum pozostaje ważny), a hash integralności per plik jest aktualizowany, by
pasował. `-Revert` przywraca kopię zapasową.

Instalator czyta fuses wciąż **zanim cokolwiek przeniesie** i odmawia z podaniem
powodu, gdy go blokują — `EnableEmbeddedAsarIntegrityValidation` sprawiłby, że
powyższe nadpisanie padłoby przy starcie, a nie przy instalacji. Sprawdź sam
dowolną aplikację:

```powershell
node ..\tools\electron-fuses.js "<path to the app's exe>"
```

Druga połowa tego była znacznie cichszym problemem. `BrowserWindow` Claude'a
renderuje cienką powłokę, a **cała widoczna aplikacja to `WebContentsView`**
przyczepiona do niej. Shim hakował kiedyś `browser-window-created`, więc
wstrzykiwał arkusz stylów do powłoki, raportował sukces do `wintage-status.txt` i
nie zmieniał niczego, co dałoby się zobaczyć. Teraz hakiuje `web-contents-created`,
co obejmuje zawartość okien, `WebContentsView`, `BrowserView`, gości `<webview>`
i popupy równo.

### Obsidian

Motyw społeczności jest zapisywany do `.obsidian/themes/` każdego vaulta — wszystkie
szesnaście palet naraz, dokładnie jak przy targetu VS Code, więc przełączasz się
między nimi w **Settings → Appearance** bez ponownego uruchamiania czegokolwiek.
Szablon pochodzi z ręcznie zrobionego motywu `VintageWin95`, który już był we
vaultcie, każdy kolor zastąpiony tokenem, któremu był równy. `-Palette <slug>`
ustala, który jest aktywny przy instalacji; `appearance.json` jest najpierw
kopiowany zapasowo, a `-Revert` usuwa tylko motywy `Wintage *` i przywraca twoje
poprzednie wybory — ręcznie zrobiony motyw w tym samym vaultcie nigdy nie jest
dotykany.

### SAIPENVIEW

Jego frontend deklaruje nazwy tokenów Wintage już we własnym `:root`, więc ta
łatka nadpisuje **tylko wartości tokenów** — nigdy selektora, fontu, szerokości
ramki ani paddingu. Nic, co wpływa na model pudełkowy, się nie zmienia, więc tekst
nie może się przesunąć. To zamierzone: wcześniejsze podejście doklejało cały arkusz
stylów przeglądarki na wierzch, a `wintage.css` jest pisany pod dowolne strony
internetowe — uniwersalne selektory wymuszające font, drabinkę rozmiarów, ramki
2px i wysokości kontrolek. Na aplikacji, która ma już własny layout, to przesuwa
wszystko.

Zweryfikowane przez zamaskowanie każdego hexu i zdiffowanie z kopią zapasową:
strukturalnie identyczne, różnią się tylko literały kolorów. `--link` jest
raportowany jako niezadeklarowany tam (jego linki markdown czytają `--accentTeal`,
co to ustawia) zamiast być wstrzyknięty — dodawanie zmiennej, której aplikacja
nigdy nie czyta, byłoby martwym balastem.

### MPC-HC (K-Lite)

Natywne Win32, bez arkusza stylów i bez punktu wstrzyknięcia, a kolory jego
ciemnego motywu są skompilowane w program — żadna wartość rejestru ich nie
ujawnia. Więc ten target **nie może nieść palety**. Co robi: włącza ciemny motyw i
stosuje do OSD zasady typografii z UI.md — jedyną powierzchnię, którą MPC-HC
pozwala użytkownikowi kontrolować. Poprzednie ustawienia są najpierw eksportowane
do `desktop/backup/mpc-hc-settings.reg`.

Zamknij MPC-HC przed zastosowaniem: nadpisuje swoje ustawienia przy zamykaniu.

## Przebudowa

Wszystko pod `desktop/out/` jest generowane z `themes/*.json`. Nie jest śledzone
w git (T-160), więc świeży klon musi je zbudować raz, zanim zainstaluje:

```powershell
node ..\tools\build-desktop.js          # przebuduj wszystkie targety
node ..\tools\build-desktop.js --check  # wyjście 1, jeśli cokolwiek jest nieaktualne
```

`release.ps1` uruchamia build i każdą bramkę, więc wydanie nie może dostarczyć
wyniku, który oddalił się od palet.

<!-- source-digest: desktop/README.md sha256:1b166ae6a7cf8a5c -->
