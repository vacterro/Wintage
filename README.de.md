# Wintage

**Win95-Dunkelgolden-Vintage-Theme für das gesamte Web.** Ein Tampermonkey-Userscript, das jede Website in eine dunkle goldbraune Windows-95-Anwendung verwandelt: pixel-scharfe 3D-Fasen, null abgerundete Ecken, null Animationen, kein Hover-Aufblitzen, überall Verdana.

[🤍 Entwickler unterstützen](https://buymeacoffee.com/vacuum34)

[EN](README.md) | [RU](README.ru.md) | [ET](README.et.md) | [Дед](README.ded.md)

_Das moderne Web optimiert die Ästhetik auf Kosten der Benutzerfreundlichkeit. Abgerundete Ecken ersetzen die visuelle Hierarchie, Animationen ersetzen Feedback, Schatten ersetzen Struktur, und Minimalismus entfernt oft genau die Hinweise, auf die sich unser Gehirn verlässt, um eine Oberfläche zu verstehen._

_Benutzer sollten nicht raten müssen, ob etwas ein Button, ein Label, eine Karte oder schlichter Text ist. Wintage bringt eine eindeutige visuelle Sprache zurück: erhabene Buttons, versenkte Eingabefelder, scharfe Grenzen, konsistente Typografie, null Ablenkung und sofortige Zustandswechsel._

_Jedes Element kommuniziert seinen Zweck auf einen Blick, reduziert die kognitive Last und macht das Web wieder zu einem präzisen Instrument statt zu einer Sammlung dekorativer Blasen._

[Changelog](CHANGELOG.md)

## Installation

1. Installiere [Tampermonkey](https://www.tampermonkey.net/) (Chrome, Edge, Firefox, Opera, Safari).
2. Klicke **[Wintage installieren](https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js)** — Tampermonkey öffnet die Installationsseite automatisch.
3. Fertig. Jede Website, die du besuchst, läuft jetzt unter Windows 95, Dunkelgoldene Edition.

## Aktualisierung

- **Automatisch:** das Skript trägt `@updateURL`/`@downloadURL` mit Verweis auf dieses Repository, also holt Tampermonkey neue Versionen bei seinen regulären Update-Prüfungen.
- **Manuell aktualisieren:** Tampermonkey → **Utilities → Check for userscript updates**, oder klicke einfach erneut auf den Installations-Link — er ersetzt die alte Version direkt, kein Deinstallieren nötig.
- **Fehlende Theme-Zeilen bedeuten ein altes Skript:** das Menü wird aus dem eingebetteten Theme-Register erzeugt, und der Release-Test verlangt genau eine Menüzeile für jede eingebettete Palette. Ist das Menü kürzer als die Palettenliste unten, klicke erneut **Install Wintage** und bestätige **Update** in Tampermonkey.

## Sechzehn Paletten und ein Schalter

Wintage ist nicht länger eine einzelne Palette. Sechs sind die Struktur von UI.md, gedreht in eine andere Farbfamilie (Dark Golden, Claude Code, Antigravity, K-Lite, FreeBuff, CodeNomad); Custom lässt sich aus dem Desktop-Installer bearbeiten und speichern, und neun sind aus [FastPrompter](https://github.com/vacterro) importiert (Default, Golden Vintage, Golden Default, Vintage Dark, Vintage Classic, Dark 2 OLED, Dracula, Nord, Solarized Dark). Jede davon besteht WCAG AA bei den drei Tokens, die Text tragen — das Build-Gate lehnt eine Palette ab, die das nicht schafft.

Wähle eine aus dem **Tampermonkey-Menü** auf jeder Seite; die Wahl wird pro Benutzer gespeichert, nicht pro Website, also gilt sie über alle Domains hinweg.

Paletten leben in `themes/*.json`, außerhalb des Skripts, aus einem Grund: Tampermonkey lädt `wintage.user.js` bei jedem Update neu herunter, also würde eine von Hand hineingeschriebene Palette verschwinden. Bringe sie mit folgendem Befehl auf einen frischen Build auf:

```powershell
.\install-themes.ps1 -Latest
```

## Jenseits des Browsers

Dieselben Paletten installieren in Desktop-Anwendungen — VS Code und Antigravity als Farbthemen, Electron-Apps (Freebuff, die Antigravity-Agent-App) über einen Shim, der genau das Stylesheet einspritzt, das dieses Userscript verwendet. Dafür gibt es eine kleine GUI:

Doppelklicke **`Wintage Installer.vbs`** im Repository-Root. Sie öffnet die GUI ohne Konsolenfenster. Der veraltete `.cmd`-Launcher leitet an denselben versteckten Host weiter; `desktop\WintageInstaller.ps1` lässt sich für Diagnosen weiterhin direkt ausführen.

Was jedes Ziel erreichen kann und was nicht — einschließlich der beiden Apps, die fest verschweißt sind oder deren Farben einkompiliert wurden — steht in **[desktop/README.md](desktop/README.md)**.

## Funktionen

- **Golden-Default-Palette** — tiefer braun-schwarzer Canvas `#1A1810`, goldener Text `#D4C89A`, goldene Bevel-Highlights `#F0D060`. Nur solide flache Flächen: keine Verläufe, kein Blur, keine Transparenzeffekte.
- **Klassische 3D-Fasen** — Buttons erhaben, Eingabefelder versenkt, gedrückte Buttons drücken sich hinein (mit dem authentischen 1px-Label-Shift). Scrollbars sind volle 16px im Win95-Stil, mit gefaster Daumenleiste und Buttons.
- **Radius-Killer** — `border-radius: 0` wird überall durchgesetzt, einschließlich Framework-CSS-Variablen (Bootstrap, Material, YouTube, Reddit).
- **Bewegung verboten** — alle Übergänge und Animationen werden genullt. Zustandswechsel passieren sofort, wie in einer echten 1995er-Oberfläche.
- **Hover-Hervorhebung komplett deaktiviert** — keine weißen Aufblitz-Zeilen, keine grauen Tönungsblöcke:
  - Füll-Eigenschaften werden chirurgisch aus jeder lesbaren `:hover`-CSS-Regel entfernt (funktionale Eigenschaften wie `display`/`visibility`/`opacity` bleiben erhalten, damit per Hover geöffnete Menüs weiter funktionieren);
  - unlesbare Cross-Origin-Stylesheets werden durch einen Übergangs-Freeze-Fallback neutralisiert.
  Nur echte Bedienelemente (Buttons, Links, Eingabefelder) behalten eine sofortige, thematisierte Fasen-Reaktion.
- **Verdana überall zu 100 % erzwungen** — einschließlich Eingabefeldern und Textareas, mit deaktiviertem Font-Smoothing. Icon-Fonts sind ausgenommen, damit Glyphen nicht zu Buchstaben werden. Ist eine benutzerdefinierte Schrift unter dem Namen `Verdana_m1` installiert (z. B. ein entschärfter Verdana-Patch), wird sie automatisch verwendet; sonst reguläres Verdana.
- **Adaptiver Repainter** — ein leichtgewichtiger JS-Sweeper wandelt helle „Aufblitz"-Flächen und unthematisierte Dunkelmodus-Grautöne in die Vintage-Braunskala um und repariert kontrastarmen (dunkel-auf-dunkel) Text zu golden, an WCAG-bewussten Schwellen. Bilder, Videos, Canvases und Player werden nie angefasst.
- **Shadow-DOM-Durchdringung** — thematisiert auch Web-Komponenten (YouTube, Reddit und Freunde) über einen `attachShadow`-Hook.
- **Popups verhalten sich** — Menüs, Dialoge, Tooltips und Hover-Cards werden nur umgefärbt; das Skript erzwingt nie `opacity`/`z-index`/`visibility`, also bleibt versteckte Site-UI versteckt.
- **Sicherheitswächter** — das Skript deaktiviert sich auf OAuth-, Captcha-, Banking- und Zahlungsseiten, damit kritische Abläufe nie umgestylt werden.

## Palette

Die Tabelle unten zeigt 10 der 21 Golden-Default-Palettentokens. Jede ausgelieferte Palette definiert alle 21; die restlichen 11 decken Fasenstruktur, Sekundärtext, semantische Farben (Erfolg/Warnung/Gefahr), Auswahl und zielspezifische Details ab.

| Token | Hex | Verwendet für |
|---|---|---|
| background | `#1A1810` | äußerster Hintergrund |
| backgroundSoft | `#232018` | Body-/Inhaltshintergrund |
| surface | `#332E22` | Kopfzeilen, Navigation, Panels |
| surfaceRaised | `#3D372A` | Buttons, Popups, Scrollbar-Daumen |
| surfaceAlt | `#453D30` | Button-Hover |
| borderHighlight | `#F0D060` | obere-linke 3D-Kanten |
| borderDark | `#100E08` | untere-rechte 3D-Kanten |
| textPrimary | `#D4C89A` | primärer goldener Text |
| textMuted | `#6E674E` | Platzhalter, deaktiviert |
| link | `#F0D060` | Links, Fokus |

## Passende Browser-Theme

Das `browsers`-Ziel des Desktop-Installers erkennt installierte und portable Chromium-Profile, meldet die Tampermonkey-Abdeckung, bereitet die gewählte Browser-Theme vor und öffnet die richtigen Installations-/Update-Seiten für jedes Profil. Chromium verlangt eine **Developer mode → Load unpacked**-Bestätigung pro Profil; der Installer kopiert den stabilen Theme-Pfad in die Zwischenablage. Spätere Palettenänderungen verwenden diesen Pfad wieder.

## Bekannte Verhaltensweisen

- Websites, die Hover-Effekte in JavaScript aufbauen (per Klassenwechsel) statt per CSS `:hover`, können weiterhin ihre eigene Hervorhebung zeigen.
- Auf seltenen Websites mit Cross-Origin-CSS kann ein Klick auf ein nicht fokussierbares Element den visuellen Zustandswechsel verzögern, bis die Maus es verlässt (der Hover-Freeze-Fallback greift). Echte Buttons und Links sind ausgenommen.
- Das Skript ist absichtlich statisch: kein Optionspanel, keine Pro-Site-Schalter. Forke es und bearbeite die Tokens oben, wenn du einen anderen Geschmack willst.

## Eine neue Version veröffentlichen (für Maintainer)

Bearbeite `wintage.user.js`, dann führe aus:

```powershell
.\release.ps1 -Message "was sich geändert hat"
```

Es erhöht die `@version`-Patch-Nummer, committed und pusht — Tampermonkey-Clients holen das Update automatisch. Für größere Releases `-Bump minor` oder `-Bump major` übergeben.

## Lizenz

[MIT](LICENSE)

<!-- source-digest: README.md sha256:ee7c6a2a1626faed -->
