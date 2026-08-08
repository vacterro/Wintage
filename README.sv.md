# Wintage

**Win95-mörkt gyllene vintage-tema för hela webben.** Ett Tampermonkey-userscript som gör om varje webbplats till en mörk gyllenbrun Windows 95-applikation: pixelskärpa 3D-fasningar, noll rundade hörn, noll animationer, inga hover-blixtar, Verdana överallt.

[🤍 Stöd utvecklaren](https://buymeacoffee.com/vacuum34)

[EN](README.md) | [RU](README.ru.md) | [ET](README.et.md) | [Дед](README.ded.md)

_Den moderna webben optimerar estetik på bekostnad av användbarhet. Rundade hörn ersätter visuell hierarki, animationer ersätter feedback, skuggor ersätter struktur, och minimalism tar ofta bort just de signaler som hjärnan förlitar sig på för att förstå ett gränssnitt._

_Användaren ska inte behöva gissa om något är en knapp, en etikett, ett kort eller bara text. Wintage återför ett entydigt visuellt språk: upphöjda knappar, nedsänkta inmatningsfält, skarpa kanter, konsekvent typografi, noll distraktion och omedelbara tillståndsändringar._

_Varje element kommunicerar sitt syfte vid första anblicken, minskar kognitiv belastning och gör webben till ett precist instrument igen i stället för en samling dekorativa bubblor._

[Changelog](CHANGELOG.md)

## Installation

1. Installera [Tampermonkey](https://www.tampermonkey.net/) (Chrome, Edge, Firefox, Opera, Safari).
2. Klicka på **[Installera Wintage](https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js)** — Tampermonkey öppnar installationssidan automatiskt.
3. Klart. Varje webbplats du besöker kör nu Windows 95, mörkt gyllene utgåvan.

## Uppdatering

- **Automatiskt:** skriptet har `@updateURL`/`@downloadURL` som pekar på den här repon, så Tampermonkey hämtar nya versioner vid sina regelbundna uppdateringskontroller.
- **Manuell uppdatering:** Tampermonkey → **Utilities → Check for userscript updates**, eller klicka bara på installationslänken igen — den ersätter den gamla versionen direkt, ingen avinstallation behövs.
- **Saknade temarader betyder gammalt skript:** menyn genereras från det inbäddade temaregistret, och releasetestet kräver exakt en menynrad per inbäddad palett. Är menyn kortare än palettlistan nedan, klicka igen på **Install Wintage** och bekräfta **Update** i Tampermonkey.

## Sexton paletter och en växel

Wintage är inte längre en enda palett. Sex är UI.md:s struktur roterad till en annan färgfamilj (Dark Golden, Claude Code, Antigravity, K-Lite, FreeBuff, CodeNomad); Custom kan redigeras och sparas från skrivbordsinstalleraren, och nio är importerade från [FastPrompter](https://github.com/vacterro) (Default, Golden Vintage, Golden Default, Vintage Dark, Vintage Classic, Dark 2 OLED, Dracula, Nord, Solarized Dark). Var och en klarar WCAG AA på de tre token som bär text — byggporten avvisar en palett som inte gör det.

Välj en från **Tampermonkey-menyn** på vilken sida som helst; valet sparas per användare, inte per webbplats, så det gäller över alla domäner.

Paletter bor i `themes/*.json`, utanför skriptet, av en anledning: Tampermonkey laddar ner `wintage.user.js` på nytt vid varje uppdatering, så en handskriven palett skulle försvinna. Applicera dem på en ny byggnad med:

```powershell
.\install-themes.ps1 -Latest
```

## Bortom webbläsaren

Samma paletter installeras i skrivbordsapplikationer — VS Code och Antigravity som färgteman, Electron-appar (Freebuff, Antigravity agent-app) via en shim som injicerar exakt den stilmall detta userscript använder. Det finns ett litet GUI för det:

Dubbelklicka på **`Wintage Installer.vbs`** i repons rot. Det öppnar GUI:t utan konsolfönster. Den äldre `.cmd`-startaren vidarebefordrar till samma dolda värd; `desktop\WintageInstaller.ps1` kan köras direkt för diagnostik.

Vad varje mål kan och inte kan nå — inklusive de två appar som är förseglade eller vars färger är kompilerade — står i **[desktop/README.md](desktop/README.md)**.

## Funktioner

- **Paletten Golden Default** — djupt brun-svart canvas `#1A1810`, gyllene text `#D4C89A`, gyllene fasningshöjdpunkter `#F0D060`. Endast solida plana ytor: inga gradienter, inget blur, inga transparenseffekter.
- **Klassiska 3D-fasningar** — knappar upphöjda, inmatningsfält nedsänkta, nedtryckta knappar trycks in (med den autentiska 1px-etikettförskjutningen). Scrollbars är fulla 16px i Win95-stil, med fasat tumgrepp och knappar.
- **Radie-dödare** — `border-radius: 0` tvingas överallt, inklusive framework-CSS-variabler (Bootstrap, Material, YouTube, Reddit).
- **Rörelse förbjuden** — alla övergångar och animationer nollställs. Tillståndsändringar är omedelbara, som i ett riktigt 1995-gränssnitt.
- **Hover-markering helt avstängd** — inga vita blixtrader, inga grå tonblock:
  - fyllnadsegenskaper tas kirurgiskt bort från varje läsbar `:hover`-regel (funktionella egenskaper som `display`/`visibility`/`opacity` behålls, så hover-öppnade menyer fortsätter fungera);
  - oläsbara cross-origin-stilmallar neutraliseras av en övergångsfrysnings-fallback.
  Endast riktiga kontroller (knappar, länkar, inmatningsfält) behåller en omedelbar, tematiserad fasningsreaktion.
- **Verdana tvingas 100 % överallt** — inklusive inmatningsfält och textarea, med typsnittsutjämning avstängd. Ikonfontar exkluderas så att glyfer inte blir bokstäver. Om du har ett anpassat typsnitt installerat under namnet `Verdana_m1` (t.ex. en de-antialiasad Verdana-patch), används det automatiskt; annars vanlig Verdana.
- **Adaptiv repainter** — en lättvikts-JS-skanner omvandlar ljusa "blixt"-ytor och o-tematiserade mörk-läges-grå till den vintage bruna skalan och reparerar lågkontrast (mörkt-på-mörkt) text till guld vid WCAG-medvetna trösklar. Bilder, videor, canvas och spelare rörs aldrig.
- **Shadow DOM-genomträngning** — tematiserar också webbkomponenter (YouTube, Reddit med flera) via en `attachShadow`-hook.
- **Popups beter sig** — menyer, dialoger, tooltips och hoverkort färgas bara om; skriptet tvingar aldrig `opacity`/`z-index`/`visibility`, så dold webbplats-UI förblir dold.
- **Säkerhetsvakt** — skriptet avaktiverar sig självt på OAuth-, captcha-, bank- och betalningssidor så att kritiska flöden aldrig omformateras.

## Palett

Tabellen nedan visar 10 av 21 token i paletten Golden Default. Varje levererad palett definierar alla 21; de återstående 11 täcker fasningsstruktur, sekundär text, semantiska färger (framgång/varning/fara), markering och mål-specifika detaljer.

| Token | Hex | Används för |
|---|---|---|
| background | `#1A1810` | yttersta bakgrund |
| backgroundSoft | `#232018` | body-/innehållsbakgrund |
| surface | `#332E22` | rubriker, navigering, paneler |
| surfaceRaised | `#3D372A` | knappar, popups, scrollbar-tumme |
| surfaceAlt | `#453D30` | knapp-hover |
| borderHighlight | `#F0D060` | fasningskanter, länkar |
| borderDark | `#100E08` | nedsänkta kanter, ramar |
| textPrimary | `#D4C89A` | primär gyllene text |
| textMuted | `#6E674E` | platshållare, inaktiverat |
| link | `#F0D060` | länkar, fokus |

## Matchande webbläsartema

Målet `browsers` i skrivbordsinstalleraren detekterar installerade och bärbara Chromium-profiler, rapporterar Tampermonkey-täckning, förbereder det valda webbläsartemat och öppnar rätt installations-/uppdateringssidor för varje profil. Chromium kräver en **Developer mode → Load unpacked**-bekräftelse per profil; installeraren kopierar den stabila temavägen till urklipp. Senare palettändringar återanvänder den sökvägen.

## Känt beteende

- Webbplatser som bygger hover-effekter i JavaScript (via klassbyte) i stället för CSS `:hover` kan fortsätta visa sin egen markering.
- På sällsynta webbplatser med cross-origin CSS kan ett klick på ett icke-fokuserbart element fördröja den visuella tillståndsändringen tills musen lämnar det (hover-frysnings-fallbacken griper in). Riktiga knappar och länkar är undantagna.
- Skriptet är medvetet statiskt: ingen inställningspanel, inga per-site-växlar. Forka det och redigera token ovan om du vill ha en annan smak.

## Släppa en ny version (för underhållare)

Redigera `wintage.user.js` och kör sedan:

```powershell
.\release.ps1 -Message "vad som ändrats"
```

Det höjer `@version`-patchnumret, commitar och pushar — Tampermonkey-klienter hämtar uppdateringen automatiskt. För större releaser skicka `-Bump minor` eller `-Bump major`.

## Licens

[MIT](LICENSE)

<!-- source-digest: README.md sha256:ee7c6a2a1626faed -->
