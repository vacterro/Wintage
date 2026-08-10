# Wintage

**Tema Vintage Win95 u tamnozlatoj za cijeli web.** Tampermonkey userscript koji svaku stranicu pretvara u tamnu zlatnosmeđu aplikaciju Windows 95: piksel-oštre 3D kosine, nula zaobljenih kutova, nula animacija, bez hover bljeskova, Verdana posvuda.

[🤍 Podržite developera](https://buymeacoffee.com/vacuum34)

[EN](README.md) | [RU](README.ru.md) | [ET](README.et.md) | [Дед](README.ded.md)

_Moderni web optimizira estetiku na štetu upotrebljivosti. Zaobljeni kutovi zamjenjuju vizualnu hijerarhiju, animacije povratnu informaciju, sjene strukturu, a minimalizam često uklanja upravo signale na koje se mozak oslanja da bi razumio sučelje._

_Korisnik ne bi trebao pogađati je li nešto gumb, oznaka, kartica ili samo tekst. Wintage vraća nedvosmislen vizualni jezik: podignuti gumbi, uvučena polja za unos, oštre rubove, dosljednu tipografiju, nula distrakcija i trenutne promjene stanja._

_Svaki element komunicira svoju svrhu na prvi pogled, smanjuje kognitivno opterećenje i čini web ponovno preciznim instrumentom umjesto zbirke dekorativnih mjehurića._

[Changelog](CHANGELOG.md)

## Instalacija

1. Instalirajte [Tampermonkey](https://www.tampermonkey.net/) (Chrome, Edge, Firefox, Opera, Safari).
2. Kliknite **[Instaliraj Wintage](https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js)** — Tampermonkey automatski otvara stranicu instalacije.
3. Gotovo. Svaka stranica koju posjetite sada radi na Windows 95, tamnozlatno izdanje.

## Ažuriranje

- **Automatski:** skripta ima `@updateURL`/`@downloadURL` koje upućuju na ovo spremište, pa Tampermonkey preuzima nove verzije pri svojim redovitim provjerama ažuriranja.
- **Ručno ažuriranje:** Tampermonkey → **Utilities → Check for userscript updates**, ili jednostavno ponovno kliknite instalacijsku poveznicu — izravno zamijeni staru verziju, bez deinstalacije.
- **Nedostajući redovi tema znače staru skriptu:** izbornik se generira iz ugrađenog registra tema, a test izdanja zahtijeva točno jedan redak izbornika za svaku ugrađenu paletu. Ako je izbornik kraći od popisa paleta u nastavku, ponovno kliknite **Install Wintage** i potvrdite **Update** u Tampermonkeyju.

## Šesnaest paleta i prekidač

Wintage više nije jedna paleta. Šest je struktura UI.md okrenuta u drugu obitelj boja (Dark Golden, Claude Code, Antigravity, K-Lite, FreeBuff, CodeNomad); Custom se može uređivati i spremati iz desktop instalatera, a devet je uvezeno iz [FastPrompter](https://github.com/vacterro) (Default, Golden Vintage, Golden Default, Vintage Dark, Vintage Classic, Dark 2 OLED, Dracula, Nord, Solarized Dark). Svaka prolazi WCAG AA na tri tokena koja nose tekst — build vrata odbijaju paletu koja to ne čini.

Odaberite jednu iz **Tampermonkey izbornika** na bilo kojoj stranici; odabir se sprema po korisniku, ne po stranici, pa vrijedi na svim domenama.

Palete žive u `themes/*.json`, izvan skripte, iz jednog razloga: Tampermonkey ponovno preuzima `wintage.user.js` pri svakom ažuriranju, pa bi ručno zapisana paleta nestala. Ponovno ih primijenite na svježu izgradnju:

```powershell
.\install-themes.ps1 -Latest
```

## Izvan preglednika

Iste se palete instaliraju u desktop aplikacije — VS Code i Antigravity kao teme boja, Electron aplikacije (Freebuff, Antigravity agent app) putem shima koji ubrizgava točno onaj stilski list koji ova skripta koristi. Za to postoji maleni GUI:

Dvaput kliknite na **`Wintage Installer.vbs`** u korijenu spremišta. Otvara GUI bez prozora konzole. Zastarjeli `.cmd` pokretač prosljeđuje na istog skrivenog domaćina; `desktop\WintageInstaller.ps1` može se pokrenuti izravno za dijagnostiku.

Što svaka meta može i ne može postići — uključujući dvije aplikacije koje su zapečaćene ili imaju kompilirane boje — opisano je u **[desktop/README.md](desktop/README.md)**.

## Značajke

- **Paleta Golden Default** — duboko smeđe-crno platno `#1A1810`, zlatni tekst `#D4C89A`, zlatna kosinska istaknuća `#F0D060`. Samo pune ravne površine: bez gradijenata, bez zamućenja, bez efekata prozirnosti.
- **Klasične 3D kosine** — gumbi podignuti, polja za unos uvučena, pritisnuti gumbi se utiskuju (s autentičnim pomakom oznake od 1px). Trake za pomicanje su pune 16px u Win95 stilu, s kosinskim palcem i gumbima.
- **Ubojica polumjera** — `border-radius: 0` se provodi posvuda, uključujući CSS varijable okvira (Bootstrap, Material, YouTube, Reddit).
- **Kretanje zabranjeno** — svi prijelazi i animacije su nulirani. Promjene stanja su trenutne, kao u pravom sučelju iz 1995.
- **Hover isticanje potpuno isključeno** — bez bijelih bljeskova, bez sivih blokova:
  - svojstva ispune se kirurški uklanjaju iz svakog čitljivog pravila `:hover` (funkcionalna svojstva poput `display`/`visibility`/`opacity` ostaju, pa izbornici otvoreni hoverom nastavljaju raditi);
  - nečitljivi cross-origin stilski listovi neutraliziraju se rezervnim zamrzavanjem prijelaza.
  Samo prave kontrole (gumbi, poveznice, polja za unos) zadržavaju trenutnu, tematsku reakciju kosine.
- **Verdana prisiljena 100 % posvuda** — uključujući polja za unos i textarea, s isključenim izglađivanjem fonta. Ikonski fontovi su isključeni da se glifovi ne pretvore u slova. Ako imate instaliran prilagođeni font pod nazivom `Verdana_m1` (npr. zakrpa Verdane bez anti-aliasinga), koristi se automatski; inače obična Verdana.
- **Adaptivni repainter** — lagani JS skener pretvara svijetle „bljeskove" površine i netematizirane sive tamnog načina u vintage smeđu skalu te popravlja niskokontrastni (tamno-na-tamnom) tekst u zlatni na pragovima koji poštuju WCAG. Slike, videozapisi, canvas i playeri se nikad ne diraju.
- **Proboj kroz Shadow DOM** — tematizira i web komponente (YouTube, Reddit i druge) putem kuke `attachShadow`.
- **Skakački prozori se ponašaju** — izbornici, dijalozi, tooltipovi i hover kartice se samo prebojavaju; skripta nikad ne prisiljava `opacity`/`z-index`/`visibility`, pa skriveno sučelje stranice ostaje skriveno.
- **Sigurnosni čuvar** — skripta se deaktivira na OAuth, captcha, bankovnim i platnim stranicama kako kritični tokovi nikad ne bi bili prestilizirani.

## Paleta

Tablica u nastavku prikazuje 10 od 21 tokena palete Golden Default. Svaka isporučena paleta definira svih 21; preostalih 11 pokriva strukturu kosina, sekundarni tekst, semantičke boje (uspjeh/upozorenje/opasnost), odabir i pojedinosti specifične za mete.

| Token | Hex | Koristi se za |
|---|---|---|
| background | `#1A1810` | najudaljenija pozadina |
| backgroundSoft | `#232018` | pozadina tijela / sadržaja |
| surface | `#332E22` | zaglavlja, navigacija, ploče |
| surfaceRaised | `#3D372A` | gumbi, skakački prozori, palac trake |
| surfaceAlt | `#453D30` | hover gumba |
| borderHighlight | `#F0D060` | rubovi kosina, poveznice |
| borderDark | `#100E08` | uvučeni rubovi, okviri |
| textPrimary | `#D4C89A` | primarni zlatni tekst |
| textMuted | `#6E674E` | rezervirana mjesta, onemogućeno |
| link | `#F0D060` | poveznice, fokus |

## Odgovarajuća preglednička tema

Meta `browsers` desktop instalatera otkriva instalirane i prijenosne Chromium profile, izvještava o pokrivenosti Tampermonkeyjem, priprema odabranu pregledničku temu i otvara točne stranice instalacije/ažuriranja za svaki profil. Chromium zahtijeva jednu potvrdu **Developer mode → Load unpacked** po profilu; instalater kopira stabilan put teme u međuspremnik. Kasnije promjene palete ponovno koriste taj put.

## Poznato ponašanje

- Stranice koje grade hover efekte u JavaScriptu (promjenom klasa) umjesto CSS `:hover` mogu nastaviti prikazivati vlastito isticanje.
- Na rijetkim stranicama s cross-origin CSS-om klik na element koji se ne može fokusirati može odgoditi vizualnu promjenu stanja dok miš ne napusti element (uključuje se rezervno zamrzavanje hovera). Pravi gumbi i poveznice su isključeni.
- Skripta je namjerno statična: bez ploče s postavkama, bez prekidača po stranici. Forkajte je i uredite tokene iznad ako želite drugačiji okus.

## Izdavanje nove verzije (za održavatelje)

Prvo dodajte unos `## [x.y.z] - date` na vrh `CHANGELOG.md` — bez njega `release.ps1` odbija raditi. Zatim:

```powershell
.\release.ps1 -Message "što se promijenilo"
```

Podiže `@version` patch broj (Tampermonkey zaglavlje i pečat `W95_VERSION` kreću se zajedno), ponovno gradi generirane desktop teme, pokreće cijeli set release gateova te commita, tagira i gura — Tampermonkey klijenti automatski preuzimaju ažuriranje. Za veća izdanja proslijedite `-Bump minor` ili `-Bump major`.

## Licenca

[MIT](LICENSE)

<!-- source-digest: README.md sha256:886c5e27060e7b30 -->
