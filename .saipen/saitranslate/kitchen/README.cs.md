# Wintage

**Téma Vintage Win95 v tmavě zlaté pro celý web.** Tampermonkey userscript, který přemění každý web na tmavou zlatohnědou aplikaci Windows 95: pixelově ostré 3D zkosení, nula zaoblených rohů, nula animací, žádné hover záblesky, Verdana všude.

[🤍 Podpořte vývojáře](https://buymeacoffee.com/vacuum34)

[EN](README.md) | [RU](README.ru.md) | [ET](README.et.md) | [Дед](README.ded.md)

_Moderní web optimalizuje estetiku na úkor použitelnosti. Zaoblené rohy nahrazují vizuální hierarchii, animace nahrazují zpětnou vazbu, stíny nahrazují strukturu a minimalismus často odstraňuje právě ty signály, na které se mozek spoléhá, aby porozuměl rozhraní._

_Uživatel by neměl hádat, zda je něco tlačítko, štítek, karta nebo jen text. Wintage vrací jednoznačný vizuální jazyk: zvýšená tlačítka, zapuštěná vstupní pole, ostré hrany, konzistentní typografie, nula rušivých prvků a okamžité změny stavu._

_Každý prvek sděluje svůj účel na první pohled, snižuje kognitivní zátěž a dělá z webu opět přesný nástroj místo sbírky dekorativních bublin._

[Changelog](CHANGELOG.md)

## Instalace

1. Nainstalujte [Tampermonkey](https://www.tampermonkey.net/) (Chrome, Edge, Firefox, Opera, Safari).
2. Klikněte na **[Nainstalovat Wintage](https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js)** — Tampermonkey automaticky otevře stránku instalace.
3. Hotovo. Každý web, který navštívíte, nyní běží na Windows 95, tmavě zlaté vydání.

## Aktualizace

- **Automaticky:** skript má `@updateURL`/`@downloadURL` odkazující na toto úložiště, takže Tampermonkey získává nové verze při svých pravidelných kontrolách aktualizací.
- **Ruční aktualizace:** Tampermonkey → **Utilities → Check for userscript updates**, nebo jednoduše klikněte znovu na instalační odkaz — starou verzi nahradí přímo, bez odinstalace.
- **Chybějící řádky témat znamenají starý skript:** nabídka se generuje z vloženého registru témat a test vydání vyžaduje přesně jeden řádek nabídky pro každou vloženou paletu. Je-li nabídka kratší než seznam palet níže, klikněte znovu na **Install Wintage** a potvrďte **Update** v Tampermonkey.

## Šestnáct palet a přepínač

Wintage už není jedna paleta. Šest je struktura UI.md otočená do jiné barevné rodiny (Dark Golden, Claude Code, Antigravity, K-Lite, FreeBuff, CodeNomad); Custom lze upravit a uložit z desktopového instalátoru a devět je importováno z [FastPrompter](https://github.com/vacterro) (Default, Golden Vintage, Golden Default, Vintage Dark, Vintage Classic, Dark 2 OLED, Dracula, Nord, Solarized Dark). Každá projde WCAG AA na třech tokenech nesoucích text — build brána odmítne paletu, která to neudělá.

Vyberte jednu z **nabídky Tampermonkey** na libovolné stránce; volba se ukládá na uživatele, ne na web, takže platí napříč všemi doménami.

Palety žijí v `themes/*.json`, mimo skript, z jednoho důvodu: Tampermonkey při každé aktualizaci znovu stahuje `wintage.user.js`, takže ručně zapsaná paleta by zmizela. Znovu je aplikujte na čerstvý build:

```powershell
.\install-themes.ps1 -Latest
```

## Mimo prohlížeč

Stejné palety se instalují do desktopových aplikací — VS Code a Antigravity jako barevná témata, aplikace Electron (Freebuff, Antigravity agent app) přes shim, který vstřikuje přesně ten stylový list, který tento userscript používá. K tomu existuje malé GUI:

Dvakrát klikněte na **`Wintage Installer.vbs`** v kořeni úložiště. Otevře GUI bez okna konzoly. Zastaralý spouštěč `.cmd` přeposílá na stejný skrytý hostitel; `desktop\WintageInstaller.ps1` lze spustit přímo pro diagnostiku.

Co každý cíl může a nemůže dosáhnout — včetně dvou aplikací zatavených nebo s kompilovanými barvami — je popsáno v **[desktop/README.md](desktop/README.md)**.

## Funkce

- **Paleta Golden Default** — hluboké hnědočerné plátno `#1A1810`, zlatý text `#D4C89A`, zlaté zvýraznění zkosení `#F0D060`. Pouze pevné ploché povrchy: žádné přechody, žádné rozostření, žádné efekty průhlednosti.
- **Klasická 3D zkosení** — tlačítka zvýšená, vstupní pole zapuštěná, stisknutá tlačítka se vtlačí dovnitř (s autentickým posunem štítku o 1px). Posuvníky jsou plné 16px ve stylu Win95, se zkoseným palcem a tlačítky.
- **Zabiják poloměrů** — `border-radius: 0` se vynucuje všude, včetně CSS proměnných frameworků (Bootstrap, Material, YouTube, Reddit).
- **Pohyb zakázán** — všechny přechody a animace jsou vynulovány. Změny stavu jsou okamžité, jako ve skutečném rozhraní z roku 1995.
- **Zvýraznění při najetí zcela vypnuto** — žádné bílé záblesky, žádné šedé bloky:
  - vlastnosti výplně se chirurgicky odstraňují z každého čitelného pravidla `:hover` (funkční vlastnosti jako `display`/`visibility`/`opacity` zůstávají, takže nabídky otevírané najetím fungují dál);
  - nečitelné cross-origin stylové listy se neutralizují záložním zmrazením přechodů.
  Pouze skutečné ovládací prvky (tlačítka, odkazy, vstupní pole) si zachovají okamžitou, tematickou reakci zkosení.
- **Verdana vynucena 100 % všude** — včetně vstupních polí a textarea, s vypnutým vyhlazováním písma. Ikonové fonty jsou vyloučeny, aby se glyfy nezměnily v písmena. Pokud máte nainstalované vlastní písmo pod názvem `Verdana_m1` (např. Verdana záplata bez anti-aliasingu), použije se automaticky; jinak běžná Verdana.
- **Adaptivní repainter** — lehký JS skener přeměňuje světlé „zábleskové" plochy a netematizované šedi tmavého režimu na vintage hnědou škálu a opravuje nízkokontrastní (tmavé-na-tmavém) text na zlatý na prahech respektujících WCAG. Obrázky, videa, canvas a přehrávače se nikdy nedotýká.
- **Pronikání Shadow DOM** — tematizuje také webové komponenty (YouTube, Reddit a spol.) přes háček `attachShadow`.
- **Vyskakovací okna se chovají** — nabídky, dialogy, tooltipy a karty najetí se jen přebarvují; skript nikdy nevynucuje `opacity`/`z-index`/`visibility`, takže skryté rozhraní webu zůstává skryté.
- **Bezpečnostní strážce** — skript se deaktivuje na stránkách OAuth, captcha, bankovnictví a plateb, aby kritické toky nebyly nikdy přestylovány.

## Paleta

Níže uvedená tabulka ukazuje 10 z 21 tokenů palety Golden Default. Každá dodaná paleta definuje všech 21; zbývajících 11 pokrývá strukturu zkosení, sekundární text, sémantické barvy (úspěch/varování/nebezpečí), výběr a podrobnosti specifické pro cíle.

| Token | Hex | Použití |
|---|---|---|
| background | `#1A1810` | nejvzdálenější pozadí |
| backgroundSoft | `#232018` | pozadí těla / obsahu |
| surface | `#332E22` | záhlaví, navigace, panely |
| surfaceRaised | `#3D372A` | tlačítka, vyskakovací okna, palec posuvníku |
| surfaceAlt | `#453D30` | hover tlačítka |
| borderHighlight | `#F0D060` | hrany zkosení, odkazy |
| borderDark | `#100E08` | zapuštěné hrany, rámečky |
| textPrimary | `#D4C89A` | primární zlatý text |
| textMuted | `#6E674E` | zástupné texty, zakázáno |
| link | `#F0D060` | odkazy, fokus |

## Odpovídající prohlížečové téma

Cíl `browsers` desktopového instalátoru detekuje nainstalované a přenosné profily Chromium, hlásí pokrytí Tampermonkey, připraví vybrané prohlížečové téma a otevře správné stránky instalace/aktualizace pro každý profil. Chromium vyžaduje jedno potvrzení **Developer mode → Load unpacked** na profil; instalátor zkopíruje stabilní cestu tématu do schránky. Pozdější změny palety tuto cestu znovu použijí.

## Známé chování

- Weby, které budují efekty najetí v JavaScriptu (změnou tříd) místo CSS `:hover`, mohou nadále ukazovat své vlastní zvýraznění.
- Na vzácných webech s cross-origin CSS může kliknutí na nefokusovatelný prvek zpozdit vizuální změnu stavu, dokud myš prvek neopustí (zapojí se záložní zmrazení hoveru). Skutečná tlačítka a odkazy jsou vyloučena.
- Skript je záměrně statický: žádný panel nastavení, žádné přepínače per-site. Forkněte ho a upravte tokeny výše, pokud chcete jinou příchuť.

## Vydání nové verze (pro správce)

Nejprve přidejte na začátek `CHANGELOG.md` záznam `## [x.y.z] - date` — bez něj se `release.ps1` odmítne spustit. Poté:

```powershell
.\release.ps1 -Message "co se změnilo"
```

Zvýší číslo `@version` (patch) (hlavička Tampermonkey a razítko `W95_VERSION` se pohybují společně), znovu sestaví generované desktopové motivy, spustí celou sadu release bran a commitne, otaguje a odešle — klienti Tampermonkey aktualizaci získají automaticky. Pro větší vydání předejte `-Bump minor` nebo `-Bump major`.

## Licence

[MIT](LICENSE)

<!-- source-digest: README.md sha256:886c5e27060e7b30 -->
