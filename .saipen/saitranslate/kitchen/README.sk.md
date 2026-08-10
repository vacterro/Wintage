# Wintage

**Téma Vintage Win95 v tmavo zlatej pre celý web.** Tampermonkey userscript, ktorý premení každú stránku na tmavozlatohnedú aplikáciu Windows 95: pixelovo ostré 3D skosenia, nula zaoblených rohov, nula animácií, žiadne hover záblesky, Verdana všade.

[🤍 Podporte vývojára](https://buymeacoffee.com/vacuum34)

[EN](README.md) | [RU](README.ru.md) | [ET](README.et.md) | [Дед](README.ded.md)

_Moderný web optimalizuje estetiku na úkor použiteľnosti. Zaoblené rohy nahrádzajú vizuálnu hierarchiu, animácie spätnú väzbu, tiene štruktúru a minimalizmus často odstraňuje presne tie signály, na ktoré sa mozog spolieha, aby porozumel rozhraniu._

_Používateľ by nemal hádať, či je niečo tlačidlo, štítok, karta alebo len text. Wintage vracia jednoznačný vizuálny jazyk: zvýšené tlačidlá, zapustené vstupné polia, ostré hrany, konzistentná typografia, nula rušivých prvkov a okamžité zmeny stavu._

_Každý prvok komunikuje svoj účel na prvý pohľad, znižuje kognitívnu záťaž a robí z webu opäť presný nástroj namiesto zbierky ozdobných bublín._

[Changelog](CHANGELOG.md)

## Inštalácia

1. Nainštalujte [Tampermonkey](https://www.tampermonkey.net/) (Chrome, Edge, Firefox, Opera, Safari).
2. Kliknite na **[Nainštalovať Wintage](https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js)** — Tampermonkey automaticky otvorí stránku inštalácie.
3. Hotovo. Každá stránka, ktorú navštívite, teraz beží na Windows 95, tmavo zlaté vydanie.

## Aktualizácia

- **Automaticky:** skript má `@updateURL`/`@downloadURL` odkazujúce na toto úložisko, takže Tampermonkey získava nové verzie pri svojich pravidelných kontrolách aktualizácií.
- **Manuálna aktualizácia:** Tampermonkey → **Utilities → Check for userscript updates**, alebo jednoducho kliknite znova na inštalačný odkaz — starú verziu nahradí priamo, bez odinštalovania.
- **Chýbajúce riadky tém znamenajú starý skript:** ponuka sa generuje z vloženého registra tém a test vydania vyžaduje presne jeden riadok ponuky pre každú vloženú paletu. Ak je ponuka kratšia ako zoznam paliet nižšie, kliknite znova na **Install Wintage** a potvrďte **Update** v Tampermonkey.

## Šestnásť paliet a prepínač

Wintage už nie je jedna paleta. Šesť je štruktúra UI.md otočená do inej farebnej rodiny (Dark Golden, Claude Code, Antigravity, K-Lite, FreeBuff, CodeNomad); Custom možno upraviť a uložiť z desktopového inštalátora a deväť je importovaných z [FastPrompter](https://github.com/vacterro) (Default, Golden Vintage, Golden Default, Vintage Dark, Vintage Classic, Dark 2 OLED, Dracula, Nord, Solarized Dark). Každá prejde WCAG AA na troch tokenoch nesúcich text — build brána odmietne paletu, ktorá to neurobí.

Vyberte jednu z **ponuky Tampermonkey** na ľubovoľnej stránke; voľba sa ukladá na používateľa, nie na stránku, takže platí naprieč všetkými doménami.

Palety žijú v `themes/*.json`, mimo skriptu, z jedného dôvodu: Tampermonkey pri každej aktualizácii znova sťahuje `wintage.user.js`, takže ručne zapísaná paleta by zmizla. Znova ich aplikujte na čerstvý build:

```powershell
.\install-themes.ps1 -Latest
```

## Mimo prehliadača

Rovnaké palety sa inštalujú do desktopových aplikácií — VS Code a Antigravity ako farebné témy, aplikácie Electron (Freebuff, Antigravity agent app) cez shim, ktorý vstrekuje presne ten štýlový list, ktorý tento userscript používa. Na to existuje malé GUI:

Dvakrát kliknite na **`Wintage Installer.vbs`** v koreni úložiska. Otvorí GUI bez okna konzoly. Zastaraný spúšťač `.cmd` presmerováva na rovnakého skrytého hostiteľa; `desktop\WintageInstaller.ps1` možno spustiť priamo na diagnostiku.

Čo každý cieľ môže a nemôže dosiahnuť — vrátane dvoch aplikácií zatavených alebo s kompilovanými farbami — je opísané v **[desktop/README.md](desktop/README.md)**.

## Funkcie

- **Paleta Golden Default** — hlboké hnedočierne plátno `#1A1810`, zlatý text `#D4C89A`, zlaté zvýraznenia skosenia `#F0D060`. Iba pevné ploché povrchy: žiadne prechody, žiadne rozostrenie, žiadne efekty priehľadnosti.
- **Klasické 3D skosenia** — tlačidlá zvýšené, vstupné polia zapustené, stlačené tlačidlá sa vtlačia dovnútra (s autentickým posunom štítka o 1px). Posuvníky sú plné 16px v štýle Win95, so skoseným palcom a tlačidlami.
- **Zabijak polomerov** — `border-radius: 0` sa vynucuje všade, vrátane CSS premenných frameworkov (Bootstrap, Material, YouTube, Reddit).
- **Pohyb zakázaný** — všetky prechody a animácie sú vynulované. Zmeny stavu sú okamžité, ako v skutočnom rozhraní z roku 1995.
- **Zvýraznenie pri prejdení úplne vypnuté** — žiadne biele záblesky, žiadne sivé bloky:
  - vlastnosti výplne sa chirurgicky odstraňujú z každého čitateľného pravidla `:hover` (funkčné vlastnosti ako `display`/`visibility`/`opacity` zostávajú, takže ponuky otvárané prejdením fungujú ďalej);
  - nečitateľné cross-origin štýlové listy sa neutralizujú záložným zmrazením prechodov.
  Iba skutočné ovládacie prvky (tlačidlá, odkazy, vstupné polia) si zachovajú okamžitú, tematickú reakciu skosenia.
- **Verdana vynútená 100 % všade** — vrátane vstupných polí a textarea, s vypnutým vyhladzovaním písma. Ikonové fonty sú vylúčené, aby sa glyfy nezmenili na písmená. Ak máte nainštalované vlastné písmo pod názvom `Verdana_m1` (napr. záplata Verdany bez anti-aliasingu), použije sa automaticky; inak bežná Verdana.
- **Adaptívny repainter** — ľahký JS skener premieňa svetlé „zábleskové" plochy a netematizované šede tmavého režimu na vintage hnedú škálu a opravuje nízkokontrastný (tmavý-na-tmavom) text na zlatý na prahoch rešpektujúcich WCAG. Obrázky, videá, canvas a prehrávače sa nikdy nedotýka.
- **Prenikanie Shadow DOM** — tematizuje aj webové komponenty (YouTube, Reddit a spol.) cez háčik `attachShadow`.
- **Vyskakovacie okná sa správajú** — ponuky, dialógy, tooltipy a karty prejdenia sa len prefarbujú; skript nikdy nevynucuje `opacity`/`z-index`/`visibility`, takže skryté rozhranie stránky zostáva skryté.
- **Bezpečnostný strážca** — skript sa deaktivuje na stránkach OAuth, captcha, bankovníctva a platieb, aby kritické toky neboli nikdy prestylované.

## Paleta

Nižšie uvedená tabuľka ukazuje 10 z 21 tokenov palety Golden Default. Každá dodaná paleta definuje všetkých 21; zvyšných 11 pokrýva štruktúru skosenia, sekundárny text, sémantické farby (úspech/varovanie/nebezpečenstvo), výber a podrobnosti špecifické pre ciele.

| Token | Hex | Použitie |
|---|---|---|
| background | `#1A1810` | najvzdialenejšie pozadie |
| backgroundSoft | `#232018` | pozadie tela / obsahu |
| surface | `#332E22` | záhlavia, navigácia, panely |
| surfaceRaised | `#3D372A` | tlačidlá, vyskakovacie okná, palec posuvníka |
| surfaceAlt | `#453D30` | hover tlačidla |
| borderHighlight | `#F0D060` | hrany skosenia, odkazy |
| borderDark | `#100E08` | zapustené hrany, rámčeky |
| textPrimary | `#D4C89A` | primárny zlatý text |
| textMuted | `#6E674E` | zástupné texty, zakázané |
| link | `#F0D060` | odkazy, fokus |

## Zodpovedajúca prehliadačová téma

Cieľ `browsers` desktopového inštalátora deteguje nainštalované a prenosné profily Chromium, hlási pokrytie Tampermonkey, pripraví vybranú prehliadačovú tému a otvorí správne stránky inštalácie/aktualizácie pre každý profil. Chromium vyžaduje jedno potvrdenie **Developer mode → Load unpacked** na profil; inštalátor skopíruje stabilnú cestu témy do schránky. Neskoršie zmeny palety túto cestu znova použijú.

## Známe správanie

- Stránky, ktoré budujú efekty prejdenia v JavaScripte (zmenou tried) namiesto CSS `:hover`, môžu naďalej ukazovať vlastné zvýraznenie.
- Na vzácnych stránkach s cross-origin CSS môže kliknutie na nefokusovateľný prvok oneskoriť vizuálnu zmenu stavu, kým myš prvok neopustí (zapojí sa záložné zmrazenie hoveru). Skutočné tlačidlá a odkazy sú vylúčené.
- Skript je zámerne statický: žiadny panel nastavení, žiadne prepínače per-site. Forknite ho a upravte tokeny vyššie, ak chcete inú príchuť.

## Vydanie novej verzie (pre správcov)

Najprv pridajte záznam `## [x.y.z] - date` na začiatok `CHANGELOG.md` — bez neho `release.ps1` odmieta bežať. Potom:

```powershell
.\release.ps1 -Message "čo sa zmenilo"
```

Zvýši číslo `@version` patch (hlavička Tampermonkey a pečiatka `W95_VERSION` sa pohybujú spolu), znova zostaví generované desktopové témy, spustí celú sadu release brán a commitne, otaguje a odošle — klienti Tampermonkey aktualizáciu získajú automaticky. Pre väčšie vydania odovzdajte `-Bump minor` alebo `-Bump major`.

## Licencia

[MIT](LICENSE)

<!-- source-digest: README.md sha256:886c5e27060e7b30 -->
