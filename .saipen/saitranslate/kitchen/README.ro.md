# Wintage

**Temă vintage Windows 95 auriu-închis pentru tot web-ul.** Un userscript Tampermonkey care restilează fiecare site într-o aplicație Windows 95 maro-aurie închisă: teșituri 3D clare la pixel, zero colțuri rotunjite, zero animații, fără flash-uri la hover, Verdana peste tot.
[🤍 Susține dezvoltatorul](https://buymeacoffee.com/vacuum34)

[EN](README.md) | [RU](README.ru.md) | [ET](README.et.md) | [Дед](README.ded.md)

_Web-ul modern optimizează estetica în detrimentul utilității. Colțurile rotunjite înlocuiesc ierarhia vizuală, animațiile înlocuiesc feedback-ul, umbrele înlocuiesc structura, iar minimalismul elimină adesea tocmai indiciile de care creierul nostru are nevoie pentru a înțelege o interfață._

_Utilizatorul nu ar trebui să ghicească dacă ceva este un buton, o etichetă, un card sau text simplu. Wintage readuce limbajul vizual explicit: butoane reliefate, câmpuri adâncite, limite clare, tipografie consecventă, zero distrageri și schimbări de stare imediate._

_Fiecare element își comunică scopul dintr-o privire, reducând încărcătura cognitivă și făcând web-ul să se simtă din nou ca un instrument de precizie, nu ca o colecție de bule decorative._

[Jurnal de modificări](CHANGELOG.md)

## Instalare

1. Instalează [Tampermonkey](https://www.tampermonkey.net/) (Chrome, Edge, Firefox, Opera, Safari).
2. Dă clic pe **[Instalează Wintage](https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js)** — Tampermonkey deschide automat pagina de instalare.
3. Gata. Fiecare site pe care îl vizitezi rulează acum Windows 95, ediția auriu-închis.

## Actualizare

- **Automat:** scriptul poartă `@updateURL`/`@downloadURL` care indică acest repo, așa că Tampermonkey preia versiunile noi la verificările obișnuite de actualizare.
- **Reîmprospătare manuală:** Tampermonkey → **Utilities → Check for userscript updates**, sau pur și simplu dă din nou clic pe link-ul de instalare — înlocuiește vechea versiune pe loc, fără dezinstalare.
- **Lipsa rândurilor de temă înseamnă un script vechi:** meniul este generat din registrul de teme încorporat, iar testul de lansare cere exact un rând de meniu pentru fiecare paletă încorporată. Dacă meniul este mai scurt decât lista de palete de mai jos, dă din nou clic pe **Instalează Wintage** și confirmă **Update** în Tampermonkey.

## Șaisprezece palete și un comutator

Wintage nu mai este o singură paletă. Șase sunt structura proprie a UI.md rotită către altă familie de nuanțe (Dark Golden, Claude Code, Antigravity, K-Lite, FreeBuff, CodeNomad); Custom poate fi editat și salvat din installer-ul desktop, iar nouă sunt importate din [FastPrompter](https://github.com/vacterro) (Default, Golden Vintage, Golden Default, Vintage Dark, Vintage Classic, Dark 2 OLED, Dracula, Nord, Solarized Dark). Fiecare dintre ele trece WCAG AA pe cele trei tokenuri care poartă text — poarta de build refuză o paletă care nu trece.

Alege una din **meniul Tampermonkey** pe orice pagină; alegerea este stocată pe utilizator, nu pe site, așa că se menține pe toate domeniile.

Paletele trăiesc în `themes/*.json`, în afara scriptului, dintr-un singur motiv: Tampermonkey re-descarcă `wintage.user.js` la fiecare actualizare, așa că o paletă editată manual în el ar dispărea. Re-aplică-le pe un build proaspăt cu:

```powershell
.\install-themes.ps1 -Latest
```

## Dincolo de browser

Aceleași palete se instalează în aplicații desktop — în VS Code și Antigravity ca teme de culori, în aplicații Electron (Freebuff, aplicația agent Antigravity) printr-un shim care injectează exact stylesheet-ul folosit de acest userscript. Există un mic GUI pentru asta:

Fă dublu-clic pe **`Wintage Installer.vbs`** din rădăcina repo-ului. Deschide GUI-ul fără fereastră de consolă. Launcher-ul vechi `.cmd` trimite către același host ascuns; `desktop\WintageInstaller.ps1` poate fi rulat direct pentru diagnosticare.

Ce poate și ce nu poate atinge fiecare țintă — inclusiv cele două aplicații sudate sau cu culorile compilate — este documentat în **[desktop/README.md](desktop/README.md)**.

## Funcții

- **Paleta Golden Default** — pânză adâncă maro-negru `#1A1810`, text auriu `#D4C89A`, accente aurii de teșire `#F0D060`. Doar suprafețe solide plane: fără gradienturi, fără blur, fără efecte de transparență.
- **Teșituri 3D clasice** — butoanele sunt reliefate, câmpurile adâncite, butonul apăsat se afundă (cu deplasarea autentică a etichetei cu 1px). Scrollbar-urile sunt complete, de 16px, în stil Win95, cu cap de teșire și butoane.
- **Omorâtor de raze** — `border-radius: 0` forțat peste tot, inclusiv în variabilele CSS ale framework-urilor (Bootstrap, Material, YouTube, Reddit).
- **Mișcarea este interzisă** — toate tranzițiile și animațiile sunt zeroizate. Schimbările de stare sunt instantanee, ca într-un UI real din 1995.
- **Evidențierea la hover complet dezactivată** — fără rânduri albe flash, fără blocuri gri:
  - proprietățile de pictare sunt îndepărtate chirurgical din fiecare regulă CSS `:hover` lizibilă (proprietățile funcționale precum `display`/`visibility`/`opacity` sunt păstrate, așa că meniurile care se deschid la hover funcționează în continuare);
  - stylesheet-urile cross-origin ilizibile sunt neutralizate printr-un fallback de înghețare a tranzițiilor.
  Doar controalele reale (butoane, linkuri, câmpuri) păstrează un răspuns de teșire tematic instantaneu.
- **Verdana forțată 100% peste tot** — inclusiv în câmpuri și textarea, cu netezirea fontului dezactivată. Fonturile de iconițe sunt excluse, ca glifurile să nu devină litere. Dacă ai instalat un font personalizat numit `Verdana_m1` (de ex. un patch Verdana fără anti-aliasing), acesta este folosit automat; altfel, Verdana obișnuită.
- **Repainter adaptiv** — un măturător JS ușor transformă suprafețele luminoase „flashbang" și griurile întunecate netematizate în scara maro vintage și corectează textul cu contrast scăzut (întunecat pe întunecat) la auriu, cu praguri conștiente de WCAG. Imaginile, videoclipurile, canvas-urile și playerele nu sunt atinse niciodată.
- **Pătrunderea Shadow DOM** — teme și componentele web (YouTube, Reddit și altele) printr-un hook `attachShadow`.
- **Popup-urile se comportă corect** — meniurile, dialogurile, tooltip-urile și hovercard-urile sunt doar recolorați; scriptul nu forțează niciodată `opacity`/`z-index`/`visibility`, așa că UI-ul ascuns al site-ului rămâne ascuns.
- **Gardă de siguranță** — scriptul se dezactivează pe paginile OAuth, captcha, bancare și de plată, ca fluxurile critice să nu fie niciodată restilate.

## Paletă

Tabelul de mai jos arată 10 dintre cele 21 de tokenuri ale paletei Golden Default. Fiecare
paletă livrată definește toate cele 21; restul de 11 acoperă structura teșiturilor,
textul secundar, culorile semantice (succes/avertisment/pericol), selecția și
specificitățile pe țintă.

| Token | Hex | Folosit pentru |
|---|---|---|
| background | `#1A1810` | fundalul cel mai exterior |
| backgroundSoft | `#232018` | fundalul corpului / conținutului |
| surface | `#332E22` | anteturi, navigare, panouri |
| surfaceRaised | `#3D372A` | butoane, popup-uri, cap de scrollbar |
| surfaceAlt | `#453D30` | hover buton |
| borderHighlight | `#F0D060` | muchiile 3D stânga-sus |
| borderDark | `#100E08` | muchiile 3D dreapta-jos |
| textPrimary | `#D4C89A` | textul auriu principal |
| textMuted | `#6E674E` | placeholder-uri, dezactivat |
| link | `#F0D060` | linkuri, focus |

## Temă de browser potrivită

Ținta `browsers` a installer-ului desktop detectează profilurile Chromium instalate și portabile, raportează acoperirea Tampermonkey, pregătește tema de browser selectată și deschide paginile corecte de instalare/actualizare pentru fiecare profil. Chromium cere o confirmare **Developer mode → Load unpacked** per profil; installer-ul copiază calea stabilă a temei în clipboard. Schimbările ulterioare de paletă reutilizează acea cale.

## Comportamente cunoscute

- Site-urile care construiesc efectele de hover în JavaScript (prin comutarea claselor), nu în CSS `:hover`, își pot afișa în continuare propria evidențiere.
- Pe site-uri rare al căror CSS este cross-origin, clic-ul pe un element nefocusabil poate întârzia schimbarea vizuală a stării până când mouse-ul îl părăsește (fallback-ul de înghețare a hover-ului la lucru). Butoanele și linkurile reale sunt scutite.
- Scriptul este static prin design: fără panou de opțiuni, fără comutatoare per-site. Fork-ează-l și editează tokenurile din partea de sus dacă vrei alt gust.

## Lansarea unei versiuni noi (întreținători)

Adaugă întâi o intrare `## [x.y.z] - date` în partea de sus a `CHANGELOG.md` — fără ea, `release.ps1` refuză să ruleze. Apoi:

```powershell
.\release.ps1 -Message "ce s-a schimbat"
```

Incrementează numărul de patch `@version` (antetul Tampermonkey și ștampila `W95_VERSION` se mișcă împreună), reconstruiește temele desktop generate, rulează întreaga suită de release gates, apoi face commit, tag și push — clienții Tampermonkey preiau actualizarea automat. Pentru lansări mai mari, dă `-Bump minor` sau `-Bump major`.

## Licență

[MIT](LICENSE)

<!-- source-digest: README.md sha256:886c5e27060e7b30 -->
