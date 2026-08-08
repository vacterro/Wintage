# Wintage

**Win95-tumma kultainen vintage-teema koko webille.** Tampermonkey-userscript, joka muuttaa jokaisen sivuston tummaksi kullanruskeaksi Windows 95 -sovellukseksi: pikselintarkat 3D-viisteet, nolla pyöristettyä kulmaa, nolla animaatiota, ei hover-välähdyksiä, Verdana kaikkialla.

[🤍 Tue kehittäjää](https://buymeacoffee.com/vacuum34)

[EN](README.md) | [RU](README.ru.md) | [ET](README.et.md) | [Дед](README.ded.md)

_Nykyaikainen verkko optimoi estetiikkaa käytettävyyden kustannuksella. Pyöristetyt kulmat korvaavat visuaalisen hierarkian, animaatiot palautteen, varjot rakenteen, ja minimalismi poistaa usein juuri ne vihjeet, joihin aivot luottavat ymmärtääkseen käyttöliittymän._

_Käyttäjän ei pitäisi joutua arvaamaan, onko jokin painike, tunniste, kortti vai pelkkää tekstiä. Wintage tuo takaisin yksiselitteisen visuaalisen kielen: kohotetut painikkeet, upotetut syöttökentät, terävät reunat, johdonmukainen typografia, nolla häiriötä ja välittömät tilamuutokset._

_Jokainen elementti kertoo tarkoituksensa ensi silmäyksellä, vähentää kognitiivista kuormitusta ja tekee verkosta jälleen tarkan instrumentin koristeellisten kuplien sijaan._

[Changelog](CHANGELOG.md)

## Asennus

1. Asenna [Tampermonkey](https://www.tampermonkey.net/) (Chrome, Edge, Firefox, Opera, Safari).
2. Napsauta **[Asenna Wintage](https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js)** — Tampermonkey avaa asennussivun automaattisesti.
3. Valmis. Jokainen vierailemasi sivusto toimii nyt Windows 95:ssä, tumma kultainen painos.

## Päivitys

- **Automaattisesti:** skriptissä on `@updateURL`/`@downloadURL` tähän repoon, joten Tampermonkey hakee uudet versiot säännöllisissä päivitystarkistuksissaan.
- **Manuaalinen päivitys:** Tampermonkey → **Utilities → Check for userscript updates**, tai napsauta vain asennuslinkkiä uudelleen — se korvaa vanhan version suoraan, poistoa ei tarvita.
- **Puuttuvat teemarivit tarkoittavat vanhaa skriptiä:** valikko luodaan sisäänrakennetusta teemarekisteristä, ja julkaisutesti vaatii täsmälleen yhden valikkorivin jokaista sisäänrakennettua palettia kohden. Jos valikko on lyhyempi kuin alla oleva palettilista, napsauta uudelleen **Install Wintage** ja vahvista **Update** Tampermonkeyssa.

## Kuusitoista palettia ja kytkin

Wintage ei ole enää yksi paletti. Kuusi ovat UI.md-rakenteen kierrettyjä muunnelmia toiseen väriperheeseen (Dark Golden, Claude Code, Antigravity, K-Lite, FreeBuff, CodeNomad); Customia voi muokata ja tallentaa työpöytäasentajasta, ja yhdeksän on tuotu [FastPrompter](https://github.com/vacterro)ista (Default, Golden Vintage, Golden Default, Vintage Dark, Vintage Classic, Dark 2 OLED, Dracula, Nord, Solarized Dark). Jokainen läpäisee WCAG AA:n kolmella tekstiä kantavalla tokenilla — build-portti hylkää paletin, joka ei sitä tee.

Valitse yksi **Tampermonkey-valikosta** millä tahansa sivulla; valinta tallennetaan käyttäjäkohtaisesti, ei sivustokohtaisesti, joten se pätee kaikilla verkkotunnuksilla.

Paletit asuvat `themes/*.json`-tiedostoissa, skriptin ulkopuolella, yhdestä syystä: Tampermonkey lataa `wintage.user.js`:n uudelleen joka päivityksessä, joten käsin kirjoitettu paletti katoaisi. Käytä ne uudelleen tuoreeseen buildiin:

```powershell
.\install-themes.ps1 -Latest
```

## Selaimen ulkopuolella

Samat paletit asentuvat työpöytäsovelluksiin — VS Code ja Antigravity väriteemoina, Electron-sovelluksiin (Freebuff, Antigravity agent -sovellus) shimin kautta, joka injektoi täsmälleen sen tyylitiedoston, jota tämä userscript käyttää. Sitä varten on pieni GUI:

Kaksoisnapsauta **`Wintage Installer.vbs`** repon juuressa. Se avaa GUI:n ilman konsoli-ikkunaa. Vanhempi `.cmd`-käynnistin ohjaa samaan piilotettuun isäntään; `desktop\WintageInstaller.ps1` voidaan ajaa suoraan diagnostiikkaa varten.

Mitä kukin kohde voi ja ei voi saavuttaa — mukaan lukien kaksi suljettua tai värit kompiloitua sovellusta — on kuvattu **[desktop/README.md](desktop/README.md)**-tiedostossa.

## Ominaisuudet

- **Golden Default -paletti** — syvä ruskeanmusta kangas `#1A1810`, kultainen teksti `#D4C89A`, kultaiset viistekorostukset `#F0D060`. Vain kiinteitä tasaisia pintoja: ei gradientteja, ei sumennusta, ei läpinäkyvyysvaikutuksia.
- **Klassiset 3D-viisteet** — painikkeet kohotettuja, syöttökentät upotettuja, painetut painikkeet painuvat sisään (autenttisella 1px-tunnisteen siirtymällä). Vierityspalkit ovat täysiä 16px Win95-tyyliä, viistetyllä peukalolla ja painikkeilla.
- **Säteentappaja** — `border-radius: 0` pakotetaan kaikkialle, mukaan lukien framework-CSS-muuttujat (Bootstrap, Material, YouTube, Reddit).
- **Liike kielletty** — kaikki siirtymät ja animaatiot nollataan. Tilamuutokset ovat välittömiä, kuten oikeassa 1995-käyttöliittymässä.
- **Hover-korostus kokonaan pois** — ei valkoisia välähdysrivejä, ei harmaita sävylohkoja:
  - täyttöominaisuudet poistetaan kirurgisesti jokaisesta luettavasta `:hover`-säännöstä (toiminnalliset ominaisuudet kuten `display`/`visibility`/`opacity` säilytetään, joten hoverilla avatut valikot toimivat edelleen);
  - lukemattomat cross-origin-tyylitiedostot neutraloidaan siirtymien jäädytys-fallbackilla.
  Vain aidot säätimet (painikkeet, linkit, syöttökentät) säilyttävät välittömän, teematun viistereaktion.
- **Verdana pakotettu 100 % kaikkialle** — mukaan lukien syöttökentät ja textarea, fonttitasoitus pois päältä. Kuvakefontit on suljettu pois, jotta glyfit eivät muutu kirjaimiksi. Jos sinulla on mukautettu fontti nimellä `Verdana_m1` (esim. de-antialiasoitu Verdana-päivitys), sitä käytetään automaattisesti; muuten tavallinen Verdana.
- **Adaptiivinen repainter** — kevyt JS-skanneri muuntaa vaaleat "välähdys"-pinnat ja ei-teematut tumman tilan harmaat vintage-ruskeaksi asteikoksi ja korjaa matalakontrastisen (tumma-tummalla) tekstin kultaiseksi WCAG-tietoisilla kynnyksillä. Kuvia, videoita, canvasseja ja soittimia ei kosketa koskaan.
- **Shadow DOM -läpäisy** — teemat myös verkkokomponentit (YouTube, Reddit ja kumppanit) `attachShadow`-hookin kautta.
- **Popupit käyttäytyvät** — valikot, dialogit, tooltipit ja hover-kortit vain värjätään; skripti ei koskaan pakota `opacity`/`z-index`/`visibility`-arvoja, joten piilotettu sivuston käyttöliittymä pysyy piilossa.
- **Turvavartija** — skripti poistaa itsensä käytöstä OAuth-, captcha-, pankki- ja maksusivuilla, jotta kriittisiä toimintoja ei koskaan muotoilla uudelleen.

## Paletti

Alla oleva taulukko näyttää 10/21 Golden Default -paletin tokenista. Jokainen toimitettu paletti määrittelee kaikki 21; loput 11 kattavat viisterakenteen, toissijaisen tekstin, semanttiset värit (onnistuminen/varoitus/vaara), valinnan ja kohteen erityispiirteet.

| Token | Hex | Käytetään |
|---|---|---|
| background | `#1A1810` | uloin tausta |
| backgroundSoft | `#232018` | rungon / sisällön tausta |
| surface | `#332E22` | otsikot, navigointi, paneelit |
| surfaceRaised | `#3D372A` | painikkeet, popupit, vierityspalkin peukalo |
| surfaceAlt | `#453D30` | painikkeen hover |
| borderHighlight | `#F0D060` | viistereunat, linkit |
| borderDark | `#100E08` | upotetut reunat, kehykset |
| textPrimary | `#D4C89A` | ensisijainen kultainen teksti |
| textMuted | `#6E674E` | paikkamerkit, poissa käytöstä |
| link | `#F0D060` | linkit, fokus |

## Vastaava selainteema

Työpöytäasentajan `browsers`-kohde havaitsee asennetut ja kannettavat Chromium-profiilit, raportoi Tampermonkey-peiton, valmistelee valitun selainteeman ja avaa oikeat asennus-/päivityssivut jokaiselle profiilille. Chromium vaatii yhden **Developer mode → Load unpacked** -vahvistuksen per profiili; asentaja kopioi vakaan teemapolun leikepöydälle. Myöhemmät palettimuutokset käyttävät samaa polkua uudelleen.

## Tunnettua käyttäytymistä

- Sivustot, jotka rakentavat hover-efektejä JavaScriptillä (luokanvaihdoilla) CSS `:hover`-sääntöjen sijaan, voivat näyttää oman korostuksensa.
- Harvinaisilla cross-origin-CSS-sivustoilla napsautus ei-fokusoitavissa olevaan elementtiin voi viivästyttää visuaalista tilamuutosta, kunnes hiiri poistuu siitä (hover-jäädytys-fallback astuu voimaan). Aidot painikkeet ja linkit on suljettu pois.
- Skripti on tarkoituksella staattinen: ei asetuspaneelia, ei sivustokohtaisia kytkimiä. Forkkaa se ja muokkaa yllä olevia tokeneita, jos haluat toisen maun.

## Uuden version julkaiseminen (ylläpitäjille)

Muokkaa `wintage.user.js`-tiedostoa ja suorita sitten:

```powershell
.\release.ps1 -Message "mitä muuttui"
```

Se nostaa `@version`-patch-numeroa, tekee commitin ja pushaa — Tampermonkey-asiakkaat hakevat päivityksen automaattisesti. Suurempia julkaisuja varten anna `-Bump minor` tai `-Bump major`.

## Lisenssi

[MIT](LICENSE)

<!-- source-digest: README.md sha256:ee7c6a2a1626faed -->
