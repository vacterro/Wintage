# Wintage

**Tema vintage « Win95 Dark Golden » per tutto il web.** Uno userscript Tampermonkey che ristilizza ogni sito in un'applicazione Windows 95 dorato-bruno scuro: smussi 3D nitidi al pixel, zero angoli arrotondati, zero animazioni, nessun bagliore all'hover, Verdana ovunque.

[🤍 Supporta lo sviluppatore](https://buymeacoffee.com/vacuum34)

[EN](README.md) | [RU](README.ru.md) | [ET](README.et.md) | [Дед](README.ded.md)

_Il web moderno ottimizza l'estetica a scapito dell'usabilità. Gli angoli arrotondati sostituiscono la gerarchia visiva, le animazioni sostituiscono il feedback, le ombre sostituiscono la struttura, e il minimalismo spesso rimuove proprio i segnali su cui il nostro cervello fa affidamento per capire un'interfaccia._

_Gli utenti non dovrebbero dover indovinare se qualcosa è un pulsante, un'etichetta, una card o semplice testo. Wintage riporta un linguaggio visivo esplicito: pulsanti in rilievo, campi di input incassati, confini netti, tipografia coerente, zero distrazioni e cambi di stato immediati._

_Ogni elemento comunica il suo scopo a colpo d'occhio, riducendo il carico cognitivo e facendo tornare il web uno strumento preciso invece che una collezione di bolle decorative._

[Registro modifiche](CHANGELOG.md)

## Installazione

1. Installa [Tampermonkey](https://www.tampermonkey.net/) (Chrome, Edge, Firefox, Opera, Safari).
2. Fai clic su **[Installa Wintage](https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js)** — Tampermonkey apre automaticamente la sua pagina di installazione.
3. Fatto. Ogni sito che visiti ora gira su Windows 95, edizione Dark Golden.

## Aggiornamento

- **Automatico:** lo script porta `@updateURL`/`@downloadURL` che puntano a questo repository, quindi Tampermonkey raccoglie le nuove versioni nei suoi controlli periodici.
- **Aggiornamento manuale:** Tampermonkey → **Utilities → Check for userscript updates**, oppure fai di nuovo clic sul link di installazione — sostituisce la vecchia versione sul posto, senza disinstallare.
- **Righe di tema mancanti = script vecchio:** il menu viene generato dal registro temi incorporato e il test di release richiede esattamente una riga di menu per ogni palette incorporata. Se il menu è più corto dell'elenco palette qui sotto, fai di nuovo clic su **Install Wintage** e conferma **Update** in Tampermonkey.

## Sedici palette e un interruttore

Wintage non è più una sola palette. Sei sono la struttura stessa di UI.md ruotata su un'altra famiglia di tinte (Dark Golden, Claude Code, Antigravity, K-Lite, FreeBuff, CodeNomad); Custom si modifica e si salva dall'installer desktop, e nove vengono importate da [FastPrompter](https://github.com/vacterro) (Default, Golden Vintage, Golden Default, Vintage Dark, Vintage Classic, Dark 2 OLED, Dracula, Nord, Solarized Dark). Ognuna supera WCAG AA sui tre token che portano testo — il build gate rifiuta una palette che non lo fa.

Scegline una dal **menu di Tampermonkey** su qualsiasi pagina; la scelta è salvata per utente, non per sito, quindi vale su tutti i domini.

Le palette vivono in `themes/*.json`, fuori dallo script, per un motivo: Tampermonkey riscarica `wintage.user.js` a ogni aggiornamento, quindi una palette modificata a mano sparirebbe. Ri-applicale su una build fresca con:

```powershell
.\install-themes.ps1 -Latest
```

## Oltre il browser

Le stesse palette si installano nelle applicazioni desktop — VS Code e Antigravity come temi colore, app Electron (Freebuff, l'app agente Antigravity) tramite uno shim che inietta esattamente il foglio di stile usato da questo userscript. C'è una piccola GUI per questo:

Fai doppio clic su **`Wintage Installer.vbs`** nella root del repository. Apre la GUI senza finestra console. Il vecchio launcher `.cmd` inoltra allo stesso host nascosto; `desktop\WintageInstaller.ps1` resta eseguibile direttamente per la diagnostica.

Cosa ogni target può e non può raggiungere — incluse le due app saldate o con i colori compilati — è scritto in **[desktop/README.md](desktop/README.md)**.

## Funzionalità

- **Palette Golden Default** — canvas marrone-nero profondo `#1A1810`, testo dorato `#D4C89A`, rilievi dorati `#F0D060`. Solo superfici piatte solide: niente gradienti, niente blur, niente effetti di trasparenza.
- **Smussi 3D classici** — pulsanti in rilievo, input incassati, pulsanti premuti che affondano (con l'autentico spostamento di 1px dell'etichetta). Le scrollbar sono piene 16px in stile Win95, con pollice e pulsanti smussati.
- **Killer dei raggi** — `border-radius: 0` imposto ovunque, incluse le variabili CSS dei framework (Bootstrap, Material, YouTube, Reddit).
- **Movimento vietato** — tutte le transizioni e animazioni azzerate. I cambi di stato sono immediati, come in una vera interfaccia del 1995.
- **Evidenziazione hover completamente disattivata** — niente righe che sbattono in bianco, niente blocchi di tinta grigia:
  - le proprietà di pittura vengono rimosse chirurgicamente da ogni regola `:hover` leggibile (le proprietà funzionali come `display`/`visibility`/`opacity` restano, così i menu aperti all'hover continuano a funzionare);
  - i fogli di stile cross-origin illeggibili vengono neutralizzati con un fallback di congelamento delle transizioni.
  Solo i veri controlli (pulsanti, link, campi) mantengono una risposta smussata immediata e tematizzata.
- **Verdana forzato al 100 % ovunque** — inclusi input e textarea, con l'anti-alias del font disattivato. I font di icone sono esclusi così i glifi non diventano lettere. Se hai un font personalizzato installato con il nome `Verdana_m1` (es. una patch Verdana de-antialiasata), viene usato automaticamente; altrimenti Verdana normale.
- **Ridipintore adattivo** — uno sweeper JS leggero converte le superfici chiare "flashbang" e i grigi del dark mode non temato nella scala marrone vintage, e corregge il testo a basso contrasto (scuro-su-scuro) verso il dorato, a soglie consapevoli del WCAG. Immagini, video, canvas e player non vengono mai toccati.
- **Perforazione del Shadow DOM** — temizza anche i web component (YouTube, Reddit e compagnia) tramite un hook `attachShadow`.
- **I popup si comportano bene** — menu, dialoghi, tooltip e hovercard vengono solo ricolorati; lo script non forza mai `opacity`/`z-index`/`visibility`, quindi l'UI nascosta del sito resta nascosta.
- **Salvaguardia di sicurezza** — lo script si disattiva su pagine OAuth, captcha, bancarie e di pagamento così i flussi critici non vengono mai ristilizzati.

## Palette

La tabella sotto mostra 10 dei 21 token della palette Golden Default. Ogni palette distribuita definisce tutti i 21; gli 11 rimanenti coprono la struttura degli smussi, il testo secondario, i colori semantici (successo/avviso/pericolo), la selezione e le specificità per target.

| Token | Hex | Usato per |
|---|---|---|
| background | `#1A1810` | sfondo più esterno |
| backgroundSoft | `#232018` | sfondo body / contenuto |
| surface | `#332E22` | intestazioni, navigazione, pannelli |
| surfaceRaised | `#3D372A` | pulsanti, popup, pollice della scrollbar |
| surfaceAlt | `#453D30` | hover del pulsante |
| borderHighlight | `#F0D060` | bordi 3D in alto a sinistra |
| borderDark | `#100E08` | bordi 3D in basso a destra |
| textPrimary | `#D4C89A` | testo dorato primario |
| textMuted | `#6E674E` | placeholder, disabilitato |
| link | `#F0D060` | link, focus |

## Tema browser abbinato

Il target `browsers` dell'installer desktop rileva i profili Chromium installati e portatili, riporta la copertura Tampermonkey, prepara il tema browser selezionato e apre le pagine di installazione/aggiornamento corrette per ogni profilo. Chromium richiede una conferma **Developer mode → Load unpacked** per profilo; l'installer copia il percorso stabile del tema negli appunti. I successivi cambi di palette riusano quel percorso.

## Comportamenti noti

- I siti che costruiscono gli effetti hover in JavaScript (tramite toggle di classi) invece che in CSS `:hover` possono ancora mostrare la propria evidenziazione.
- Sui rari siti il cui CSS è cross-origin, fare clic su un elemento non focalizzabile può ritardare il suo cambio di stato visivo finché il mouse non lo lascia (all'opera il fallback di congelamento hover). I veri pulsanti e link sono esenti.
- Lo script è statico per design: nessun pannello opzioni, nessun toggle per sito. Fai un fork e modifica i token in alto se vuoi un sapore diverso.

## Pubblicare una nuova versione (manutentori)

Aggiungi prima una voce `## [x.y.z] - date` all'inizio di `CHANGELOG.md` — `release.ps1` si rifiuta di girare senza. Poi:

```powershell
.\release.ps1 -Message "cosa è cambiato"
```

Incrementa il numero di patch di `@version` (l'intestazione di Tampermonkey e il timbro `W95_VERSION` si muovono insieme), ricostruisce i temi desktop generati, esegue l'intera suite di gate di rilascio, e committa, tagga e fa push — i client Tampermonkey raccolgono l'aggiornamento automaticamente. Passa `-Bump minor` o `-Bump major` per release più grandi.

## Licenza

[MIT](LICENSE)

<!-- source-digest: README.md sha256:886c5e27060e7b30 -->
