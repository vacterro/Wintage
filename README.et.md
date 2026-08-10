# Wintage

**Win95 tume kuldne vintaaž-teema kogu veebile.** Tampermonkey kasutajaskript, mis
stiliseerib iga saidi ümber tumedaks kuldseks Windows 95 rakenduseks: teravad 3D
servad, null ümarat nurka, null animatsiooni, ei mingeid hõljumisvilku, igal pool
Verdana.

_Kaasaegne veeb optimeerib esteetikat kasutatavuse arvelt. Ümarad nurgad asendavad
visuaalse hierarhia, animatsioonid tagasiside, varjud struktuuri ning minimalism
eemaldab just need vihjed, millele aju liidese mõistmisel toetub._

_Kasutaja ei peaks ära arvama, kas miski on nupp, silt, kaart või lihtsalt tekst.
Wintage toob tagasi selge visuaalse keele: kõrgendatud nupud, süvistatud väljad,
teravad piirid, ühtne tüpograafia, null segajat ja hetkelised olekumuutused._

_Iga element ütleb esimesest pilgust, milleks ta on. See vähendab kognitiivset
koormust ja teeb veebist jälle täpse instrumendi, mitte dekoratiivsete mullide kogu._

[🤍 Toeta arendajat](https://buymeacoffee.com/vacuum34)

[EN](README.md) | [RU](README.ru.md) | [ET](README.et.md) | [Дед](README.ded.md)

[Muudatuste logi](CHANGELOG.md)

## Paigaldamine

1. Paigalda [Tampermonkey](https://www.tampermonkey.net/) (Chrome, Edge, Firefox, Opera, Safari).
2. Klõpsa **[Paigalda Wintage](https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js)** — Tampermonkey avab paigalduslehe ise.
3. Valmis. Iga külastatav sait töötab nüüd Windows 95 tumedas kullas.

## Uuendamine

- **Automaatselt:** skript kannab `@updateURL`/`@downloadURL` viiteid sellele
  repositooriumile, nii et Tampermonkey võtab uued versioonid tavapäraste
  uuenduskontrollidega üles.
- **Käsitsi:** Tampermonkey → **Utilities → Check for userscript updates** või
  klõpsa paigalduslingile uuesti — see asendab vana versiooni paigas, midagi
  eemaldama ei pea.
- **Teemaridu puudu tähendab vana skripti:** menüü genereeritakse sisse ehitatud
  teemaregistrist ja väljalaske test nõuab igale paletile täpselt üht menüürida.
  Kui menüü on lühem kui allolev palettide loend, klõpsa uuesti **Install Wintage**
  ja kinnita Tampermonkeys **Update**.

## Kuusteist paletti ja lüliti

Wintage pole enam üks palett. Kuus on UI.md enda struktuur, pööratud teise
toonide perekonda (Dark Golden, Claude Code, Antigravity, K-Lite, FreeBuff,
CodeNomad); Custom on redigeeritav ja salvestatav lauaarvuti paigaldajast; üheksa
on imporditud [FastPrompter](https://github.com/vacterro) projektist (Default,
Golden Vintage, Golden Default, Vintage Dark, Vintage Classic, Dark 2 OLED,
Dracula, Nord, Solarized Dark). Igaüks neist läbib WCAG AA kolme teksti kandva
tookeni osas — ehitusvärav keeldub paletist, mis seda ei tee.

Vali üks **Tampermonkey menüüst** igal lehel; valik salvestatakse kasutaja, mitte
saidipõhiselt, nii et see kehtib kõigil domeenidel.

Paletid elavad `themes/*.json`, väljaspool skripti, ühel põhjusel: Tampermonkey
laeb `wintage.user.js` iga uuendusega alla, ja käsitsi sisse kirjutatud palett
kaoks. Kanna need värskele ehitusele uuesti sisse käsuga:

```powershell
.\install-themes.ps1 -Latest
```

## Peale brauseri

Samad paletid paigalduvad lauaarvuti rakendustesse — VS Code ja Antigravity
värviteemadena, Electron-rakendustesse (Freebuff, Antigravity agendirakendus)
shimi kaudu, mis süstib just selle stiililehe, mida kasutajaskript kasutab.
Selleks on väike GUI:

Topeltklõpsa repositooriumi juurtes olevat **`Wintage Installer.vbs`**. See avab
GUI ilma konsooliaknata. Vana `.cmd` käivita suunab samasse peidetud hosti;
`desktop\WintageInstaller.ps1` saab diagnostikaks otse käivitada.

Mida iga sihtmärk suudab ja ei suuda ulatada — sealhulgas kaks rakendust, mis on
fusitud kinni või mille värvid on kompileeritud sisse — on kirjas dokumendis
**[desktop/README.md](desktop/README.md)**.

## Funktsioonid

- **Golden Default palett** — sügav pruunikasmust lõuend `#1A1810`, kuldne tekst
  `#D4C89A`, kuldsed servad `#F0D060`. Ainult tasased pinnad: ei gradiiente, ei
  hägustust, ei läbipaistvust.
- **Klassikalised 3D servad** — nupud kõrgendatud, väljad süvistatud, vajutatud
  nupp vajub sisse (autentse 1px sildi nihkega). Kerimisribad on täismõõdus 16px
  Win95 stiilis, servadega käepideme ja nuppudega.
- **Raadiuste tapja** — `border-radius: 0` sunnitakse igal pool, sealhulgas
  raamistiku CSS-muutujates (Bootstrap, Material, YouTube, Reddit).
- **Liikumine keelatud** — kõik üleminekud ja animatsioonid nullitud. Olekud
  muutuvad hetkega, nagu päris 1995. aasta liideses.
- **Hõljumise esiletõst täielikult keelatud** — ei mingeid valgeid vilkuvaid
  ridu ega halli toone:
  - värvimisomadused eemaldatakse kirurgiliselt igast loetavast `:hover`
    CSS-reeglist (funktsionaalsed omadused nagu `display`/`visibility`/`opacity`
    jäetakse alles, nii et hõljumisel avanevad menüüd töötavad);
  - loetamatud teiste domeenide stiililehed neutraliseeritakse üleminekute
    külmutamise varuvariandiga.
  Ainult päris juhtelemendid (nupud, lingid, väljad) säilitavad hetkelise
  teemapärase servareaktsiooni.
- **Verdana sunnitult igal pool** — sealhulgas väljades ja textarea-des, ilma
  fondisilumiseta. Ikoonifondid on välistatud, et glüüfid ei muutuks tähtedeks.
  Kui sul on installitud font nimega `Verdana_m1` (nt silumata Verdana plaat),
  kasutatakse seda automaatselt; muidu tavaline Verdana.
- **Adaptiivne ümbervärvija** — kerge JS-skanneerija muudab heledad
  "välgu" pinnad ja teemavälised tumedad hallid vintaažseks pruuniks skaalaks
  ning parandab madala kontrastiga (tume-tumedal) teksti kuldseks, WCAG-teadlike
  lävenditega. Pilte, videoid, canvas-e ja pleiereid ei puudutata kunagi.
- **Shadow DOM läbistamine** — teemindab ka veebikomponente (YouTube, Reddit jt)
  läbi `attachShadow` konksu.
- **Hüpikud käituvad hästi** — menüüd, dialoogid, vihjetipud ja hoverkaardid
  ainult värvitakse üle; skript ei sunni kunagi `opacity`/`z-index`/`visibility`,
  nii et peidetud saidi-UI jääb peidetuks.
- **Ohutuskaitsme** — skript lülitab end OAuthi, captcha, panganduse ja maksete
  lehtedel ise välja, et kriitilised voogud jääksid puutumata.

## Palett

Allolevas tabelis on 10 Golden Default paleti 21-st tokenist. Iga
kaasasolev palett määratleb kõik 21; ülejäänud 11 hõlmavad servade
struktuuri, teisest teksti, semantilisi värve (edukus/hoiatus/oht),
valikut ja sihtmärgipõhiseid üksikasju.

| Tooken | Hex | Kasutus |
|---|---|---|
| background | `#1A1810` | kõige välimine taust |
| backgroundSoft | `#232018` | keha / sisu taust |
| surface | `#332E22` | päised, navigatsioon, paneelid |
| surfaceRaised | `#3D372A` | nupud, hüpikud, kerimisriba käepide |
| surfaceAlt | `#453D30` | nupu hõljumine |
| borderHighlight | `#F0D060` | faaside servad, lingid |
| borderDark | `#100E08` | süvistatud servad, raamid |
| textPrimary | `#D4C89A` | peamine kuldne tekst |
| textMuted | `#6E674E` | kohahoidjad, keelatud |
| link | `#F0D060` | lingid, fookus |

## Ühilduv brauseriteema

Lauaarvuti paigaldaja `browsers` sihtmärk leiab paigaldatud ja kaasaskantavad
Chromiumi profiilid, teatab Tampermonkey kaetusest, valmistab valitud
brauseriteema ja avab iga profiili jaoks õiged paigaldus-/uuenduslehed. Chromium
nõuab profiili kohta ühte **Developer mode → Load unpacked** kinnitust;
paigaldaja kopeerib stabiilse teematee lõikelauale. Hilisemad paletivahetused
kasutavad seda teed uuesti.

## Teadaolevad omadused

- Saidid, mis ehitavad hõljumisefekte JavaScriptis (klassivahetusega), mitte CSS
  `:hover`-iga, võivad ikkagi näidata oma esiletõstu.
- Haruldastel teiste domeenide CSS-iga saitidel võib klõps mittefokuseeritaval
  elemendil lükata visuaalse olekumuutuse hiire lahkumiseni (hõljumise külmutamise
  varuvariant tööl). Päris nupud ja lingid on erandlikud.
- Skript on disainilt staatiline: ei mingeid valikupaneele ega saidipõhiseid
  lüliteid. Forki see ja muuda ülaosas olevaid tookeneid, kui tahad teist maitset.

## Uue versiooni väljalaskmine (hooldajatele)

Lisa kõigepealt `CHANGELOG.md` algusesse kirje `## [x.y.z] - date` — ilma selleta keeldub `release.ps1` töötamast. Seejärel:

```powershell
.\release.ps1 -Message "mis muutus"
```

See tõstab `@version` plaaster-numbri (Tampermonkey päis ja `W95_VERSION` tempel liiguvad koos), ehitab loodud lauateemade ümber, käivitab kogu väljalaskegate'ide komplekti ning teeb commiti, tag'i ja pushi — Tampermonkey kliendid võtavad uuenduse automaatselt. Suuremate väljalasete jaoks anna `-Bump minor` või `-Bump major`.

## Litsents

[MIT](LICENSE)

<!-- source-digest: README.md sha256:886c5e27060e7b30 -->
