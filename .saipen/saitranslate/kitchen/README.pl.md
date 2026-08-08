# Wintage

**Motyw Vintage Win95 w ciemnym złocie dla całej sieci.** To userscript Tampermonkey, który zamienia każdą stronę w ciemnozłotą aplikację Windows 95: ostre jak piksel fazki 3D, zero zaokrąglonych rogów, zero animacji, bez rozbłysków najechania, Verdana wszędzie.

[🤍 Wspomóż dewelopera](https://buymeacoffee.com/vacuum34)

[EN](README.md) | [RU](README.ru.md) | [ET](README.et.md) | [Дед](README.ded.md)

_Nowoczesna sieć optymalizuje estetykę kosztem użyteczności. Zaokrąglone rogi zastępują hierarchię wizualną, animacje zastępują informację zwrotną, cienie zastępują strukturę, a minimalizm często usuwa dokładnie te sygnały, na których polega nasz mózg, by zrozumieć interfejs._

_Użytkownik nie powinien zgadywać, czy coś jest przyciskiem, etykietą, kartą czy zwykłym tekstem. Wintage przywraca jednoznaczny język wizualny: wypukłe przyciski, wklęsłe pola wejściowe, ostre krawędzie, spójną typografię, zero rozpraszaczy i natychmiastowe zmiany stanu._

_Każdy element komunikuje swój cel na pierwszy rzut oka, zmniejszając obciążenie poznawcze i czyniąc sieć znów precyzyjnym narzędziem zamiast zbiorem ozdobnych bąbelków._

[Changelog](CHANGELOG.md)

## Instalacja

1. Zainstaluj [Tampermonkey](https://www.tampermonkey.net/) (Chrome, Edge, Firefox, Opera, Safari).
2. Kliknij **[Zainstaluj Wintage](https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js)** — Tampermonkey automatycznie otworzy stronę instalacji.
3. Gotowe. Każda strona, którą odwiedzasz, działa teraz na Windows 95, edycja ciemnozłota.

## Aktualizacja

- **Automatycznie:** skrypt ma `@updateURL`/`@downloadURL` wskazujące ten repozytorium, więc Tampermonkey pobiera nowe wersje przy regularnych kontrolach aktualizacji.
- **Ręczna aktualizacja:** Tampermonkey → **Utilities → Check for userscript updates**, albo po prostu kliknij ponownie link instalacji — zastąpi starą wersję bezpośrednio, bez odinstalowywania.
- **Brakujące linie motywu oznaczają stary skrypt:** menu jest generowane z wbudowanego rejestru motywów, a test wydania wymaga dokładnie jednej linii menu na każdą wbudowaną paletę. Jeśli menu jest krótsze niż lista palet poniżej, kliknij ponownie **Install Wintage** i potwierdź **Update** w Tampermonkey.

## Szesnaście palet i przełącznik

Wintage to już nie jedna paleta. Sześć to struktura UI.md obrócona do innej rodziny kolorów (Dark Golden, Claude Code, Antigravity, K-Lite, FreeBuff, CodeNomad); Custom można edytować i zapisywać z instalatora desktopowego, a dziewięć zaimportowano z [FastPrompter](https://github.com/vacterro) (Default, Golden Vintage, Golden Default, Vintage Dark, Vintage Classic, Dark 2 OLED, Dracula, Nord, Solarized Dark). Każda przechodzi WCAG AA na trzech tokenach niosących tekst — bramka builda odrzuca paletę, która tego nie robi.

Wybierz jedną z **menu Tampermonkey** na dowolnej stronie; wybór zapisywany jest na użytkownika, nie na stronę, więc obowiązuje na wszystkich domenach.

Palety żyją w `themes/*.json`, poza skryptem, z jednego powodu: Tampermonkey pobiera `wintage.user.js` ponownie przy każdej aktualizacji, więc ręcznie wpisana paleta zniknęłaby. Zastosuj je ponownie na świeżym buildzie:

```powershell
.\install-themes.ps1 -Latest
```

## Poza przeglądarką

Te same palety instalują się w aplikacjach desktopowych — VS Code i Antigravity jako motywy kolorów, aplikacje Electron (Freebuff, Antigravity agent app) przez shim wstrzykujący dokładnie ten arkusz stylów, którego używa ten userscript. Do tego służy mały GUI:

Kliknij dwukrotnie **`Wintage Installer.vbs`** w katalogu głównym repozytorium. Otwiera GUI bez okna konsoli. Przestarzały launcher `.cmd` przekierowuje do tego samego ukrytego hosta; `desktop\WintageInstaller.ps1` można uruchamiać bezpośrednio do diagnostyki.

Co każdy cel może i czego nie może osiągnąć — w tym dwie aplikacje zapieczętowane lub z wkompilowanymi kolorami — opisano w **[desktop/README.md](desktop/README.md)**.

## Funkcje

- **Paleta Golden Default** — głębokie brązowoczarne płótno `#1A1810`, złoty tekst `#D4C89A`, złote podświetlenia fazek `#F0D060`. Tylko jednolite płaskie powierzchnie: bez gradientów, bez rozmycia, bez efektów przezroczystości.
- **Klasyczne fazki 3D** — przyciski wypukłe, pola wejściowe wklęsłe, wciśnięte przyciski wpadają do środka (z autentycznym przesunięciem etykiety o 1px). Paski przewijania są pełne 16px w stylu Win95, z fazowanym uchwytem i przyciskami.
- **Pogromca promieni** — `border-radius: 0` wymuszane wszędzie, w tym w zmiennych CSS frameworków (Bootstrap, Material, YouTube, Reddit).
- **Ruch zakazany** — wszystkie przejścia i animacje wyzerowane. Zmiany stanu są natychmiastowe, jak w prawdziwym interfejsie z 1995.
- **Podświetlanie najechania całkowicie wyłączone** — bez białych rozbłysków, bez szarych bloków:
  - właściwości wypełnienia są chirurgicznie usuwane z każdej czytelnej reguły `:hover` (właściwości funkcjonalne jak `display`/`visibility`/`opacity` pozostają, więc menu otwierane najechaniem działają dalej);
  - nieczytelne arkusze cross-origin są neutralizowane przez fallback zamrażania przejść.
  Tylko prawdziwe elementy sterujące (przyciski, linki, pola wejściowe) zachowują natychmiastową, tematyczną reakcję fazki.
- **Verdana wymuszane w 100% wszędzie** — w tym pola wejściowe i textarea, z wyłączonym wygładzaniem czcionek. Czcionki ikon są wykluczone, by glify nie zamieniały się w litery. Jeśli masz zainstalowaną niestandardową czcionkę o nazwie `Verdana_m1` (np. łatkę Verdany bez antyaliasingu), jest używana automatycznie; w przeciwnym razie zwykła Verdana.
- **Adaptacyjny repainter** — lekki skaner JS zamienia jasne powierzchnie "rozbłysk" i nietematyczne szarości trybu ciemnego na wintage'ową brązową skalę oraz naprawia nisko kontrastowy (ciemny-na-ciemnym) tekst na złoty, na progach zgodnych z WCAG. Obrazy, wideo, canvas i odtwarzacze nigdy nie są ruszane.
- **Przenikanie Shadow DOM** — motywuje też komponenty webowe (YouTube, Reddit i spółka) przez hook `attachShadow`.
- **Popupy zachowują się** — menu, okna dialogowe, tooltipy i karty najechania są tylko przemalowywane; skrypt nigdy nie wymusza `opacity`/`z-index`/`visibility`, więc ukryty UI strony pozostaje ukryty.
- **Strażnik bezpieczeństwa** — skrypt wyłącza się na stronach OAuth, captcha, bankowości i płatności, by krytyczne przepływy nigdy nie były restylowane.

## Paleta

Poniższa tabela pokazuje 10 z 21 tokenów palety Golden Default. Każda wydana paleta definiuje wszystkie 21; pozostałe 11 obejmuje strukturę fazek, tekst drugorzędny, kolory semantyczne (sukces/ostrzeżenie/niebezpieczeństwo), zaznaczenie i szczegóły specyficzne dla celów.

| Token | Hex | Używane do |
|---|---|---|
| background | `#1A1810` | najbardziej zewnętrzne tło |
| backgroundSoft | `#232018` | tło treści |
| surface | `#332E22` | nagłówki, nawigacja, panele |
| surfaceRaised | `#3D372A` | przyciski, popupy, uchwyt paska |
| surfaceAlt | `#453D30` | najechanie przycisku |
| borderHighlight | `#F0D060` | krawędzie fazek, linki |
| borderDark | `#100E08` | wklęsłe krawędzie, obramowania |
| textPrimary | `#D4C89A` | główny złoty tekst |
| textMuted | `#6E674E` | placeholdery, wyłączone |
| link | `#F0D060` | linki, fokus |

## Pasujący motyw przeglądarki

Cel `browsers` instalatora desktopowego wykrywa zainstalowane i przenośne profile Chromium, raportuje pokrycie Tampermonkey, przygotowuje wybrany motyw przeglądarki i otwiera właściwe strony instalacji/aktualizacji dla każdego profilu. Chromium wymaga jednego potwierdzenia **Developer mode → Load unpacked** na profil; instalator kopiuje stabilną ścieżkę motywu do schowka. Późniejsze zmiany palety używają tej ścieżki ponownie.

## Znane zachowania

- Strony budujące efekty najechania w JavaScript (przez zmianę klas) zamiast CSS `:hover` mogą nadal pokazywać własne podświetlenie.
- Na rzadkich stronach z cross-origin CSS kliknięcie niefokusowalnego elementu może opóźnić wizualną zmianę stanu, aż mysz go opuści (zadziała fallback zamrażania najechania). Prawdziwe przyciski i linki są wykluczone.
- Skrypt jest celowo statyczny: bez panelu opcji, bez przełączników per-site. Sforkuj go i edytuj tokeny powyżej, jeśli chcesz inny smak.

## Wydanie nowej wersji (dla opiekunów)

Edytuj `wintage.user.js`, a następnie uruchom:

```powershell
.\release.ps1 -Message "co się zmieniło"
```

Podnosi numer `@version` patch, commituje i wypycha — klienci Tampermonkey pobierają aktualizację automatycznie. Dla większych wydań przekaż `-Bump minor` lub `-Bump major`.

## Licencja

[MIT](LICENSE)

<!-- source-digest: README.md sha256:ee7c6a2a1626faed -->
