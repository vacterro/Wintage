# Wintage

**Win95 sötét arany vintage téma az egész webhez.** Egy Tampermonkey-felhasználóskript, amely minden oldalt sötét aranybarna Windows 95-alkalmazássá stilizál: pixeléles 3D ferdeségek, nulla lekerekített sarok, nulla animáció, nincs hover-villanás, mindenhol Verdana.
[🤍 Támogasd a fejlesztőt](https://buymeacoffee.com/vacuum34)

[EN](README.md) | [RU](README.ru.md) | [ET](README.et.md) | [Дед](README.ded.md)

_A modern web az esztétikát optimalizálja a használhatóság rovására. A lekerekített sarkok felváltják a vizuális hierarchiát, az animációk a visszajelzést, az árnyékok a struktúrát, a minimalizmus pedig gyakran épp azokat a jelzéseket távolítja el, amelyekre az agyunknak az interfész megértéséhez szüksége van._

_A felhasználónak nem kellene találgatnia, hogy valami gomb, címke, kártya vagy egyszerű szöveg. A Wintage visszahozza az egyértelmű vizuális nyelvet: kiemelt gombok, besüllyedt beviteli mezők, éles határok, következetes tipográfia, nulla zavaró tényező és azonnali állapotváltozások._

_Minden elem egyetlen pillantásra elárulja a rendeltetését, csökkentve a kognitív terhelést, és a webet ismét precíz eszköznek érezteti, nem pedig dekoratív buborékok gyűjteményének._

[Változásnapló](CHANGELOG.md)

## Telepítés

1. Telepítsd a [Tampermonkey](https://www.tampermonkey.net/)-t (Chrome, Edge, Firefox, Opera, Safari).
2. Kattints a **[Wintage telepítése](https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js)** gombra — a Tampermonkey automatikusan megnyitja a telepítőoldalát.
3. Kész. Minden meglátogatott oldal mostantól Windows 95-öt futtat, sötét arany kiadásban.

## Frissítés

- **Automatikus:** a szkript `@updateURL`/`@downloadURL` címe erre a repóra mutat, így a Tampermonkey a rendszeres frissítésellenőrzések során felveszi az új verziókat.
- **Kézi frissítés:** Tampermonkey → **Utilities → Check for userscript updates**, vagy csak kattints újra a telepítőlinkre — a helyén cseréli le a régi verziót, eltávolításra nincs szükség.
- **A hiányzó témasorok régi szkriptet jelentenek:** a menü a beépített témaregiszterből készül, és a release-teszt minden beépített palettához pontosan egy menüsort követel. Ha a menü rövidebb, mint az alábbi palettalista, kattints újra a **Wintage telepítése** linkre, és erősítsd meg a Tampermonkey-ben az **Update** gombot.

## Tizenhat paletta és egy váltókapcsoló

A Wintage már nem egyetlen paletta. Hat a UI.md saját szerkezete, egy másik színcsaládra forgatva (Dark Golden, Claude Code, Antigravity, K-Lite, FreeBuff, CodeNomad); a Custom az asztali telepítőből szerkeszthető és menthető, kilenc pedig a [FastPrompter](https://github.com/vacterro) projektből importált (Default, Golden Vintage, Golden Default, Vintage Dark, Vintage Classic, Dark 2 OLED, Dracula, Nord, Solarized Dark). Mindegyik teljesíti a WCAG AA-t a szöveget hordozó három tokenen — az építőkapu visszautasít minden palettát, amely nem teszi.

Bármelyik oldalon válassz egyet a **Tampermonkey menüből**; a választás felhasználónként, nem oldalanként tárolódik, így minden domainen érvényes marad.

A paletták a `themes/*.json` fájlban élnek, a szkripten kívül, egyetlen okból: a Tampermonkey minden frissítéskor újra letölti a `wintage.user.js` fájlt, így a kézzel beleírt paletta eltűnne. Vidd fel őket egy friss buildre a következővel:

```powershell
.\install-themes.ps1 -Latest
```

## A böngészőn túl

Ugyanezek a paletták asztali alkalmazásokba is települnek — a VS Code-ba és az Antigravity-be színtémaként, az Electron-alkalmazásokba (Freebuff, az Antigravity-ügynökalkalmazás) egy shimen keresztül, amely pontosan azt a stíluslapot injektálja, amelyet ez a felhasználóskript használ. Van hozzá egy kis GUI:

Kattints duplán a repo gyökerében található **`Wintage Installer.vbs`** fájlra. Ez konzolablak nélkül nyitja meg a GUI-t. Az örökölt `.cmd` indító ugyanarra a rejtett hosztra továbbít; a `desktop\WintageInstaller.ps1` diagnosztikai célból továbbra is közvetlenül futtatható.

Hogy az egyes célpontok mit érnek el és mit nem — beleértve a két, beégetve lezárt vagy beépített színű alkalmazást —, az a **[desktop/README.md](desktop/README.md)** dokumentumban van leírva.

## Funkciók

- **Golden Default paletta** — mély barna-fekete vászon `#1A1810`, arany szöveg `#D4C89A`, arany ferde kiemelések `#F0D060`. Csak tömör sík felületek: nincs gradiens, nincs elmosás, nincs átlátszósági effekt.
- **Klasszikus 3D ferdeségek** — a gombok kiemeltek, a beviteli mezők besüllyedtek, a lenyomott gomb benyomódik (a hiteles 1px címkeeltolással). A görgetősávok teljes 16px-es Win95-stílusúak, ferde gombbal és nyilakkal.
- **Sarokölő** — a `border-radius: 0` mindenhol kikényszerítve, beleértve a keretrendszerek CSS-változóit (Bootstrap, Material, YouTube, Reddit).
- **A mozgás tilos** — minden átmenet és animáció nullázva. Az állapotváltozások azonnaliak, mint egy igazi 1995-ös UI-ban.
- **Hover-kihangsúlyozás teljesen letiltva** — nincsenek fehér villanó sorok, nincsenek szürke színezőblokkok:
  - a festési tulajdonságokat sebészeti pontossággal eltávolítjuk minden olvasható `:hover` CSS-szabályból (a funkcionális tulajdonságok, mint a `display`/`visibility`/`opacity`, megmaradnak, így a hoverrel megnyíló menük továbbra is működnek);
  - az olvashatatlan, más forrásból származó stíluslapok egy átmenet-mentesítő (transition-freeze) tartalékkal semlegesítődnek.
  Csak a valódi vezérlők (gombok, linkek, beviteli mezők) tartanak meg egy azonnali, tematizált ferde választ.
- **Verdana erőltetve 100%-osan mindenhol** — beleértve a beviteli mezőket és a textarea-ket is, a betűsimítás kikapcsolva. Az ikonfontok ki vannak zárva, hogy a glifák ne váljanak betűkké. Ha egy `Verdana_m1` nevű egyéni betűtípust telepítettél (pl. egy anti-aliasing nélküli Verdana-javítást), az automatikusan használatra kerül; egyébként a normál Verdana.
- **Adaptív újrafestő** — egy könnyű JS-takarító a világos "villanó" felületeket és a nem tematizált sötét mód szürkéit vintage barna skálává alakítja, és az alacsony kontrasztú (sötét-sötéten) szöveget aranyszínűre javítja, WCAG-tudatos küszöbértékekkel. A képeket, videókat, canvas-eket és lejátszókat soha nem érinti.
- **Shadow DOM átlyukasztás** — a webkomponenseket is tematizálja (YouTube, Reddit és társaik) egy `attachShadow` horog segítségével.
- **A felugró ablakok rendesen viselkednek** — a menük, párbeszédablakok, tippek és hover-kártyák csak átfestődnek; a szkript soha nem kényszerít `opacity`/`z-index`/`visibility` értéket, így a rejtett oldal-UI rejtve marad.
- **Biztonsági védelem** — a szkript önmagát letiltja OAuth-, captcha-, banki- és fizetési oldalakon, hogy a kritikus folyamatokat soha ne tematizálja át.

## Paletta

Az alábbi táblázat a Golden Default paletta 21 tokenjéből 10-et mutat. Minden
szállított paletta mind a 21-et definiálja; a fennmaradó 11 a ferde szerkezetre,
a másodlagos szövegre, a szemantikus színekre (siker/figyelmeztetés/veszély), a
kijelölésre és a célpontonkénti részletekre vonatkozik.

| Token | Hex | Felhasználás |
|---|---|---|
| background | `#1A1810` | legkülső háttér |
| backgroundSoft | `#232018` | test / tartalom háttere |
| surface | `#332E22` | fejlécek, navigáció, panelek |
| surfaceRaised | `#3D372A` | gombok, felugrók, görgetősáv gombja |
| surfaceAlt | `#453D30` | gomb hover |
| borderHighlight | `#F0D060` | bal-felső 3D élek |
| borderDark | `#100E08` | jobb-alsó 3D élek |
| textPrimary | `#D4C89A` | elsődleges arany szöveg |
| textMuted | `#6E674E` | helykitöltők, letiltottak |
| link | `#F0D060` | linkek, fókusz |

## Illeszkedő böngészőtéma

Az asztali telepítő `browsers` célpontja észleli a telepített és hordozható Chromium-profilokat, jelentést ad a Tampermonkey-lefedettségről, előkészíti a kiválasztott böngészőtémát, és minden profilhoz megnyitja a megfelelő telepítő/frissítő oldalakat. A Chromium profilonként egy **Developer mode → Load unpacked** megerősítést igényel; a telepítő a stabil témaútvonalat a vágólapra másolja. A későbbi palettaváltoztatások újra ezt az útvonalat használják.

## Ismert viselkedések

- Azok az oldalak, amelyek hover-effekteket JavaScriptben építenek (osztályváltással), nem pedig CSS `:hover`-rel, továbbra is mutathatják a saját kiemelésüket.
- Ritka, más forrásból származó CSS-t használó oldalakon a nem fókuszálható elemre kattintás késleltetheti a vizuális állapotváltozást, amíg az egér el nem hagyja (a hover-freeze tartalék dolgozik). A valódi gombok és linkek mentesülnek.
- A szkript szándékosan statikus: nincs beállítópult, nincs oldalankénti kapcsoló. Forkold le, és szerkeszd a tetején lévő tokeneket, ha más ízt szeretnél.

## Új verzió kiadása (karbantartóknak)

Először adj hozzá egy `## [x.y.z] - date` bejegyzést a `CHANGELOG.md` tetejére — enélkül a `release.ps1` nem hajlandó futni. Ezután:

```powershell
.\release.ps1 -Message "mi változott"
```

Ez növeli az `@version` javítás (patch) számát (a Tampermonkey-fejléc és a `W95_VERSION` bélyeg együtt mozog), újraépíti a generált asztali témákat, lefuttatja a teljes release-gate csomagot, majd commitol, tagel és pushol — a Tampermonkey-kliensek automatikusan felveszik a frissítést. Nagyobb kiadásokhoz adj `-Bump minor` vagy `-Bump major` paramétert.

## Licenc

[MIT](LICENSE)

<!-- source-digest: README.md sha256:886c5e27060e7b30 -->
