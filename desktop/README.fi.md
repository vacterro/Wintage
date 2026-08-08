# Wintage työpöytäsovelluksiin

Käyttäjäskripti teemaa verkon. Tämä teemaa sen ympärillä olevat ohjelmat samoista
paleteista, jotta selain ja sovellukset lakkaavat olemasta eri mieltä siitä, mitä
tumma kultainen tarkoittaa.

Jokaisen tämän päätöksen takana on yksi sääntö: **sovellukset päivittävät itse itsensä, ja
päivitys ei saa hiljaa rikkoa mitään.** Kun kohteella on paikka omassa
profiilissasi, teema menee sinne ja säilyy päivitysten yli. Kun paikkaa ei ole, asentaja
on kirjoitettu ajettavaksi uudelleen — ja kertoo sen, eikä teeskentele tallentaneensa.

## Graafinen käyttöliittymä

Kaksoisnapsauta **`Wintage Installer.vbs`** -tiedostoa repon juuressa avataksesi sen ilman
konsoli-ikkunaa, tai aja tämä suoraan vianetsintää varten:

```powershell
powershell -File desktop\WintageInstaller.ps1
```

Teemaluettelo värikuvakkeineen, tästä koneesta löytyvät kohteet, reaaliaikainen Win95
-esikatselu ja kaikki kaksikymmentäyksi väritokenia muokattavina värikenttinä. Minkä tahansa
värikentän muokkaaminen haarauttaa paletin **Custom**-tilaan sen sijaan, että muuttaisi
toimitettua teemaa huomaamattasi. Oikealla oleva paneeli näyttää reaaliaikaisen WCAG-kontrastin
kolmelle tekstiä kantavalle tokenille — paletti, joka epäonnistuu siinä, hylätään
rakennusportissa muutenkin, joten se on parempi nähdä ennen Applya kuin sen jälkeen.

Kohteet on jaettu kahteen näppäimistöllä tavoitettavaan luetteloon: **MY APPS** sisältää
kannettavat/source-puun CodeNomad-, SAIPENVIEW-, SmartVac- ja WildRift-työkalut; **POPULAR
APPS** sisältää Windowsin, OBS:n, terminaalit, editorit ja muun asennetun ohjelmiston.
ALL/NONE ja Apply/Revert toimivat molempien luetteloiden yli muuttamatta niiden ryhmittelyä.

Ikkuna kantaa sitä palettia, jonka se on asentamassa. Se on nopein käytettävissä oleva
esikatselu, ja se pitää työkalun rehellisenä: paletti, joka tekee tästä ikkunasta
lukukelvottoman, on näkyvästi lukukelvoton.

Apply kutsuu `install.ps1`:ää. Teeman asentava koodipolku on täsmälleen yksi,
joten GUI ei voi ajautua erilleen komentorivistä.

## Komentorivi

```powershell
.\desktop\install.ps1                                  # mikä on täällä, mikä on teemoitettu, millä paletilla
.\desktop\install.ps1 -Target freebuff -Palette klite  # yksi sovellus, yksi paletti
.\desktop\install.ps1 -Target all -Palette goldendefault # kaikki
.\desktop\install.ps1 -Target all -WhatIf              # kerro mikä muuttuisi, älä koske mihinkään
.\desktop\install.ps1 -Target freebuff -Revert         # kumoa yksi
```

`-Palette` oletusarvo on `goldendefault` (**Golden Default**). GUI avautuu
samaan palettiin ja tarkistaa kaikki käytettävissä olevat kohteet. Jo teemoitetun sovelluksen
uudelleenmaalaaminen toimii sen ollessa käynnissä; ensimmäinen asennus ei, koska
arkisto on käytössä.

## Mitä kukin kohde voi oikeasti teemoittaa

| target | mekanismi | säilyykö sovelluspäivityksen yli |
|---|---|---|
| `windows` | käyttäjän `.theme`: tumma järjestelmä-/sovellustila, korostus- ja klassiset väriroolit | yes — asennettu paikalliseen Windows Themes -kansioosi |
| `browsers` | tunnistaa asennetut + kannettavat Chromium-profiilit, lavastaa valitun chrome-teeman ja avaa selaimen omat Tampermonkey/teemavahvistussivut | yes yhden **Load unpacked** -vahvistuksen jälkeen profiilia kohti |
| `terminal` | Windows Terminal -skeema + oletusasetukset kaikkiin profiileihin, Consolas 12 aliasoitu | yes — asetukset ovat profiilissasi |
| `conhost` | `HKCU\Console`-oletukset + kaikki olemassa olevat cmd/PowerShell-profiilit | yes — täsmällinen kuvakaappaus kosketuista arvoista |
| `obs` | OBS 30.2+ `.ovt`-variantti + aktiivinen `user.ini`-teema-ID | yes — se on profiilissasi |
| `antigravity`, `vscode` | väriteemalaajennus `~/.antigravity/extensions` / `~/.vscode/extensions` -kansiossa | **yes** — se on profiilissasi |
| `freebuff`, `antigravity-app`, `codenomad` | Electron-shim, katso alla | no — aja asentaja uudelleen |
| `claude` | Electron-shim, paikattu paikan päällä — katso alla | no — päivitys luo uuden `app-<version>`-kansion |
| `mpchc` | rekisteri, vain tumma teema + OSD-typografia | no — MPC-HC kirjoittaa asetuksensa uusiksi lopettaessaan |
| `obsidian` | yhteisöteema vaultia kohti, kaikki paletit asennettu kerralla | **yes** — se on vaultissasi |
| `saipenview` | kirjoittaa omat `:root`-tokenarvonsa uusiksi `style.css`-tiedostossa | no — lähdetiedosto; aja uudelleen pullin jälkeen |
| `discord` | CSS pudotettu BetterDiscordin omaan teemakansioon | yes |
| `totalcmd`, `totalcmd2` | `wincmd.ini` `[Colors]`-avaimet; olemassa olevat viimeisimmät-tiedostosuodattimet käyttävät paletin linkkiväriä | yes — se on sinun ini:si |
| `smartvac`, `wildrift` | tokenitaulukko kirjoitettu uusiksi sovelluksen omassa lähdekoodissa | no — lähdetiedosto; aja uudelleen pullin jälkeen |

### FreeBuff-mainosten poisto

FreeBuff (tekoälyavustajan työpöytäsovellus) toimittaa oman mainosverkkonsa:
renderöijä-bundle (`resources/orchestrator/ui/assets/index-*.js`) renderöi `sponsored-ad`
-kortin ja ketjun bannerin, ja orkestroija (`resources/orchestrator/orchestrator.js`)
paljastaa `/api/ad/slot|impression|click`-reitit, jotka kutsuvat etäistä mainoshuutokauppaa.
Shim vain teemaa sovelluksen; se ei koske niihin tiedostoihin.

`desktop/patch-freebuff-ads.js` leikkaa mainokset pois tavutasolla:

- renderöijä: mainoskortin/-bannerin kutsukohdista tulee `null`, ja `adSlot` /
  `adImpression` / `adClick`-API-asiakasmetodeista tulee no-opeja — mikään ei renderöidy,
  eikä mikään `/api/ad/*`-pyyntö koskaan poistu renderöijästä;
- orkestroija: kaikki kolme `/api/ad/*`-reittiä lopettavat mainosverkon kutsumisen, ja
  live-vuoron inline-mainospyyntö (`maybeRequestAd`) oikosuljetaan.

Bundlen tiedostonimi upottaa rakennushashin, joten paikkaus löytää nykyisen
bundlen `index.html`-tiedostosta sen sijaan, että toimittaisi versiolukitun hyötykuorman —
juuri se saa sen säilymään päivitysten yli. Alkuperäiset varmuuskopioidaan
`_orig-backup-<timestamp>/`-kansioon asennushakemistoon; `--revert` palauttaa uusimman.

**Tulevat versiot käsitellään kahdella riippumattomalla kerroksella:**

1. **Tavupaikkaus regex-varapolutilla.** Jokaisella kohteella on täsmällinen merkkijono
   nykyiselle rakennukselle *ja* regex-varapolku, joka on ankkuroitu sellaiseen, jota
   minifioija ei voi nimetä uudelleen — `/api/ad/*`-polkukirjaimiin, `case"ad":`-protokolla
   -diskriminaattoriin, `sponsored-ad`-luokkaan ja `variant:"banner"` /
   `variant:"card"`-sijoitteluihin. Orkestroijaa ei ole minifioitu (luettavat nimet
   kuten `maybeRequestAd` ja `app.ads.slotAd`), joten sen tarkat merkkijonot pitävät
   pitkään; renderöijä-bundle on minifioitu, joten sen regex-varapolut ottavat vallan
   heti kun seuraava rakennus nimeää sen tunnisteet uudelleen.
2. **Shim-tason esto (`targets/electron/shim.cjs`).** Täysin riippumaton bundlesta:
   mikä tahansa fetch/XHR `/api/ad/`-URL:ään hylätään sivun sisällä, ja mikä tahansa
   elementti, jonka luokka sisältää `sponsored-ad`, piilotetaan heti kun se
   ilmestyy. Edes aivan uusi bundle, jota tämä skripti ei ole vielä oppinut, ei voi
   nostaa mainosta esiin.

```powershell
node .\desktop\patch-freebuff-ads.js           # paikkaa (varmuuskopioi ensin)
node .\desktop\patch-freebuff-ads.js --sound "C:\...\my.mp3"   # paikkaa + mukautettu valmistumisääni (wav/mp3/ogg/flac/m4a/aac)
node .\desktop\patch-freebuff-ads.js --scan    # mitä mainosmerkkejä TÄMÄ rakennus kantaa?
node .\desktop\patch-freebuff-ads.js --verify
node .\desktop\patch-freebuff-ads.js --revert
```

Se ajetaan automaattisesti osana `install.ps1 -Target freebuff` -komentoa, ja se on
ajettava uudelleen jokaisen FreeBuff-päivityksen jälkeen (päivitykset palauttavat vakiotiedostot).
Jos rakennus muuttaa muotoaan, skripti nimeää kohteen, joka ei enää täsmännyt — aja
`--scan` nähdäksesi mitä uusi rakennus vielä kantaa, ja päivitä merkkijonot siellä.

**FreeBuff-valmistumisääni.** Renderöijä soittaa `chime-<hash>.mp3`-tiedoston, kun vuoro
päättyy. Paikkaus löytää sen samalla tavalla kuin bundlen (nimi upottaa
rakennushashin), joten `--sound <file>` asentaa oman äänesi (wav/mp3/ogg/flac/m4a/
aac) sen päälle ja säilyttää vakiotiedoston nimellä `chime-*.mp3.bak`; `--revert` palauttaa
sen. `--verify` kertoo kumman on käytössä.

### FreeBuff-äänipainike (GUI)

`WintageInstaller.ps1`:ssä on pieni **FB SOUND** -painike APPLY / REVERT
-pinon alla. Se vain säilyttää *asetuksen*; `install.ps1 -Target freebuff` lukee
saman tiedoston ja antaa sen paikkaukselle `--sound`-argumenttina, joten mainokset ja ääni
sovelletaan yhdellä ajolla:

- **Vasen napsautus** — valitse äänitiedosto (OpenFileDialog, wav/mp3/ogg/flac/m4a/aac)
  ja kuule se heti: PCM WAV System.Media.SoundPlayerin kautta,
  kaikki muut formaatit WPF MediaPlayerin kautta (Media Foundation, asynkroninen, joten
  ikkuna ei koskaan jäädy). Valinta muistetaan
  `%APPDATA%\Wintage\freebuff-sound.txt`-tiedostossa (konekohtainen, git-checkoutin
  ulkopuolella, aivan kuten muistetut source-puukansiot).
- **Oikea napsautus** — tyhjennä asetus takaisin FreeBuffin vakio-chimeen (pysäyttää
  myös mahdollisesti vielä soivan esikatselun).
- **COPY** — kopioi valitun äänen itse repoon
  (`sounds\freebuff.<ext>`, säilyttäen lähdetiedoston päätteen) ja osoittaa
  asetuksen uudelleen tuohon kopioon, joten ääni säilyy vaikka alkuperäinen tiedosto
  poistetaan tai siirretään. Käytössä vain silloin, kun mukautettu ääni on asetettu;
  uudelleenkopiointi yksinkertaisesti korvaa repon kopion. `sounds/`-kansio on tavallista
  git-seurattavaa sisältöä, joten sen committaus saa äänen säilymään myös uudelleenkloonausten
  yli.

Vain tunnistetut äänisäiliöt esikatsellaan — otsake tunnistetaan ensin, joten
ei-ääni-valinnasta ilmoitetaan sen sijaan, että soitetaan hiljaa ei mitään.

Painike lukee `ON`, kun mukautettu ääni on asetettu; osoittamalla sitä näkyy
polku. Käytä `freebuff`-kohdetta sen jälkeen (rastita FreeBuff + APPLY, tai aja
`install.ps1 -Target freebuff` terminaalista), jotta se astuu voimaan.

### Terminaalit

`terminal` kirjoittaa `Wintage`-väriskeeman jokaiseen tunnistettuun stable-, Preview-
tai pakkaamattomaan Windows Terminal -asetustiedostoon ja valitsee sen
`profiles.defaults`-kautta, yhdessä konsolinkestävän Consolas 12:n ja aliasoidun tekstin kanssa. Alkuperäinen tiedosto
säilytetään tavuilleen sen vieressä, ja `-Revert` palauttaa sen.

`conhost` kattaa klassisia `cmd.exe`, Windows PowerShell, Git CMD/Bash-konsoli
-profiileja ja muita olemassa olevia `HKCU\Console`-lapsia. Se kirjoittaa paletin koko
16-väritaulukon sekä juurioletuksiin että jokaiseen olemassa olevaan ohitukseen, ja palauttaa sitten
vain ne arvot, joihin se koski. Se käyttää Consolaa sielläkin, koska suhteellinen
Verdana törmää kiinteän leveyden soluruudukossa, jota molemmat terminaaliohjelmat käyttävät.

### Selain ja Tampermonkey

`browsers` löytää Chrome-, Edge-, Brave-, Cent-, Vivaldi- ja Opera-profiilit
asennetuista sijainneista ja kannettavasta juuresta, johon osoitat sen (`-PortableRoot`, tai
muistettu `portable`-merkintä `paths.json`-tiedostossa). Sen tila
näyttää sekä profiilimäärän että kuinka moni sisältää Tampermonkeyn. Apply kopioi valitun
selain-chrome-teeman vakaaseen
`%LOCALAPPDATA%\Wintage\browser-theme`-kansioon, laittaa sen polun leikepöydälle,
ja avaa jokaisen profiilin kohdalla `chrome://extensions`-sivun sekä Wintage-käyttäjäskriptin
Install/Update-sivun. Profiilit ilman Tampermonkeyta saavat myös sen Chrome Web Store
-sivun.

Chromium kieltää tarkoituksella hiljaisen storen ulkopuolisen laajennusasennuksen
hallitsemattomalla Windows-koneella. Ensimmäinen selainteeman asennus vaatii siksi yhden
**Developer mode → Load unpacked** -vahvistuksen profiilia kohti. Valitse kopioitu polku;
sen jälkeen Wintage jatkaa saman vakaan kansion korvaamista palettien vaihtuessa.
Vahvista **Install/Update** myös Tampermonkeyssa. Yhtään selaimen `Preferences`-, Secure
Preferences- tai Tampermonkey-LevelDB-tiedostoa ei muokata selaimen selän takana.
Jos Tampermonkey ei ollut asennettuna, asenna se avatusta kauppa-välilehdestä ja päivitä
jo avoin `wintage.user.js`-välilehti saadaksesi Install-näytön.

### Windows

`windows` asentaa ja aktivoi heti sisältöosoitetun
`%LOCALAPPDATA%\Microsoft\Windows\Themes\Wintage-<hash>.theme`-tiedoston.
Se lähtee aktiivisesta teemasta ja korvaa vain dokumentoidut väri-, kohdistin- ja
visuaalityyli-osiot. Taustakuva, äänet ja työpöydän kuvakkeet pysyvät ennallaan; kohdistimet
vaihtuvat tarkoituksella asennettuun `___CURRENT___`-skeemaan. Ensimmäinen aktiivinen teema
tallennetaan tavuilleen nimellä `Wintage.original.theme`; palettimuutokset säilyttävät tuon perustan,
ja `-Revert` aktivoi sen uudelleen. Nykyaikaiset Windows-kontrollit tulevat edelleen
allekirjoitetusta Aero-tyylistä — Wintage muuttaa sen tukemaa tummaa tilaa, korostusta,
ja klassisia järjestelmävärien syötteitä sen sijaan, että korvaisi suojattuja `.msstyles`-tiedostoja.
Aktiiviset ja epäaktiiviset otsikkopalkit jakavat paletin vaimean kohotetun pinnan värin;
kirkas korostus pysyy varattuna teksti-/valintareunoille. Edellinen epäaktiivisen
otsikkopalkin korostus tallennetaan erikseen kuvakaappauksena ja palautetaan täsmälleen `-Revert`-toiminnolla.
Sisältöhash antaa Windowsille uuden tiedostoassosiaatiokohteen, kun sama paletti
rakennetaan uudelleen, joten päivitetyn paletin uudelleensoveltamista ei sekoiteta no-opiin;
syrjäytetty Wintage-tiedosto poistetaan sen jälkeen, kun Windows vahvistaa uuden aktiiviseksi.

### OBS Studio

`obs` tuottaa OBS 30.2+ -variantin ylläpidetyn Yami Classic -pohjan päälle,
asentaa sen `%APPDATA%\obs-studio\themes`-kansioon, ja kirjoittaa vakaan teema-ID:nsä
`user.ini`-tiedostoon, joten valittu Wintage-paletti on jo valittuna seuraavalla käynnistyksellä.
Sulje OBS ennen Applya tai Revertiä: OBS kirjoittaa `user.ini`-tiedoston uusiksi lopettaessaan. Ensimmäinen sovellus
varmuuskopioi sekä aiemman valinnan että kaikki samannimiset teemat tavuilleen.

### Electron-sovellukset

`resources/app.asar` siirretään kohtaan `resources/app/app.asar` (sen `app.asar.unpacked`
-sisar siirtyy mukana — tuo paritus on tiedostonimen varassa, ja sen erottaminen rikkoo jokaisen
natiivimoduulin), ja pieni `shim.cjs` ottaa vapautuneen `resources/app`-paikan. Shim
injektoi tyylitiedoston ja lataa sitten alkuperäisen arkiston. **Yhtään sovelluksen
tavua ei kirjoiteta uusiksi**, vain siirretään; `-Revert` siirtää sen suoraan takaisin.

Tyylitiedostoa ei ole kirjoitettu näille sovelluksille — se puretaan
`wintage.user.js`-tiedostosta, joten jokainen selainta varten tehty bevel-, vierityspalkki- ja
tyyppitikkas-korjaus päätyy tännekin, ilman toista mätänemään jäävää kopiota.

Kaksi etukäteen mainitsemisen arvoista huomautusta:

- Ilmeinen tapa — `resources/app`-kansion pudottaminen arkiston viereen ja luottaminen
  Electronin suosivan sitä — **ei toimi ja epäonnistuu hiljaa**. Electron
  etsii `app.asar`-tiedoston ensin. Sovellus käynnistyy täydellisesti, ja teema ei koskaan käynnisty.
- Shim on `.cjs`, ei `.js`, tarkoituksella. Sen `package.json` kopioidaan sovelluksen
  omasta, jotta sovellus säilyttää nimensä ja versionsa (nimi ratkaisee, missä userData
  sijaitsee — shim, joka nimeää sen uudelleen, siirtää sovelluksen tyhjään profiiliin). Jos se manifesti
  sanoo `"type": "module"`, `.js`-shim kuolee ensimmäiseen `require`-kutsuunsa.

### Claude'n työpöytäsovellus: paikan päällä, ja se kehys, johon se todella piirtää

Claude ei voi käyttää yllä olevaa siirtoa, koska `OnlyLoadAppFromAsar` on sulautettu päälle —
Electron lataa `resources/app.asar`-tiedoston eikä mitään muuta, joten shim kohdassa `resources/app`
ei voi koskaan käynnistyä. Se paikataan **paikan päällä** sen sijaan: arkisto varmuuskopioidaan, sen
`package.json`-`main` kirjoitetaan uudelleen arvoon `"../wintage-shim.cjs"` (täytettynä samaan
tavupituuteen, joten jokainen offset arkistossa pysyy kelvollisena), ja tiedostokohtainen eheys
-hash päivitetään vastaamaan. `-Revert` palauttaa varmuuskopion.

Asentaja lukee fuusit silti **ennen kuin se liikuttaa mitään** ja kieltäytyy syyn
kera, kun ne estävät sen — `EnableEmbeddedAsarIntegrityValidation` saisi
yllä olevan uudelleenkirjoituksen epäonnistumaan käynnistyksessä asennuksen sijaan. Tarkista mikä tahansa sovellus itse:

```powershell
node ..\tools\electron-fuses.js "<path to the app's exe>"
```

Tämän toinen puoli oli paljon hiljaisempi ongelma. Claude'n `BrowserWindow` renderöi
ohuen kuoren, ja **koko näkyvä sovellus on `WebContentsView`**, joka on
kiinnitetty siihen. Shim hookkasi aiemmin `browser-window-created`, joten se injektoi tyylitiedoston
kuoreen, raportoi onnistumisen `wintage-status.txt`-tiedostoon, eikä muuttanut mitään, mitä
näit. Se hookkaa nyt `web-contents-created`-tapahtumaa, joka kattaa ikkunan sisällön,
`WebContentsView`:t, `BrowserView`:t, `<webview>`-vieraat ja ponnahdusikkunat yhtä lailla.

### Obsidian

Yhteisöteema kirjoitetaan jokaisen vaultin `.obsidian/themes/`-kansioon — kaikki kuusitoista
palettia kerralla, täsmälleen kuten VS Code -kohde, joten vaihdat niiden välillä
**Settings → Appearance** -valikossa ajamatta mitään uudelleen. Mallipohja johdettiin
vaultissa jo olevasta käsin tehdystä `VintageWin95`-teemasta, jokainen väri korvattiin
tokenilla, jota se vastasi. `-Palette <slug>` määrää, kumpi on aktiivinen asennuksessa;
`appearance.json` varmuuskopioidaan ensin, ja `-Revert` poistaa vain `Wintage *`-
teemat ja palauttaa aiemman valintasi — käsin tehtyyn teemaan samassa vaultissa
ei koskaan kosketa.

### SAIPENVIEW

Sen frontend julistaa jo Wintage-tokenien nimet omassa `:root`-lohkossaan, joten tämä
paikkaus kirjoittaa uusiksi **vain tokenien arvot** — ei koskaan valitsinta, kirjasinta, reunuksen leveyttä
tai paddingia. Mikään, mikä vaikuttaa box-malliin, ei muutu, joten teksti ei voi siirtyä.
Se on tarkoituksellista: aiempi lähestymistapa liitti koko selaimen tyylitiedoston
päälle, ja `wintage.css` on kirjoitettu mielivaltaisille verkkosivuille — universaalit valitsimet,
jotka pakottavat kirjasimen, kokotikkaat, 2px-reunukset ja kontrollien korkeudet. Sovelluksessa,
jolla on jo oma asettelunsa, se siirtää kaiken.

Varmennettu peittämällä jokainen hex ja diffaamalla varmuuskopiota vastaan: rakenteellisesti
identtinen, vain värikirjaimet eroavat. `--link` raportoidaan siellä julistamattomaksi
(sen markdown-linkit lukevat `--accentTeal`, jonka tämä asettaa) sen sijaan, että se injektoitaisiin —
sellaisen muuttujan lisääminen, jota sovellus ei koskaan lue, olisi kuollutta painoa.

### MPC-HC (K-Lite)

Natiivinen Win32, ei tyylitiedostoa eikä injektiokohtaa, ja sen tumman teeman värit ovat
käännettynä ohjelmaan — mikään rekisteriarvo ei paljasta niitä. Joten tämä kohde **ei voi
kantaa palettia**. Mitä se tekee: kytkee tumman teeman päälle ja soveltaa UI.md
-typografiasääntöjä OSD:hen, joka on se ainoa pinta, jota MPC-HC antaa käyttäjän hallita.
Aiemmat asetukset viedään ensin tiedostoon `desktop/backup/mpc-hc-settings.reg`.

Sulje MPC-HC ennen soveltamista: se kirjoittaa asetuksensa uusiksi lopettaessaan.

## Uudelleenrakentaminen

Kaikki `desktop/out/`-kansion alla on generoitu `themes/*.json`-tiedostoista. Se ei ole
git-seurannassa (T-160), joten tuore klooni täytyy rakentaa kerran ennen asennusta:

```powershell
node ..\tools\build-desktop.js          # rakenna kaikki kohteet uudelleen
node ..\tools\build-desktop.js --check  # exit 1, jos mikään on vanhentunutta
```

`release.ps1` ajaa rakennuksen ja jokaisen portin, joten julkaisu ei voi toimittaa tulostetta, joka
on ajautunut erilleen paleteista.

<!-- source-digest: desktop/README.md sha256:1b166ae6a7cf8a5c -->
