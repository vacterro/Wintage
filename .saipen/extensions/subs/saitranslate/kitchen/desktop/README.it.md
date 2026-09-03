# Wintage per applicazioni desktop

Lo userscript temizza il web. Questo temizza i programmi che lo circondano, dalle stesse palette, così browser e app smettono di litigare su cosa significhi "dark golden".

C'è una regola dietro ogni decisione: **le applicazioni si aggiornano da sole, e un aggiornamento non deve rompere nulla in silenzio.** Dove un target ha un posto nel tuo profilo, il tema va lì e sopravvive agli aggiornamenti. Dove non ce l'ha, l'installer è scritto per essere rilanciato — e lo dice, invece di fingere di aver persistito.

## La GUI

Fai doppio clic su **`Wintage Installer.vbs`** nella root del repository per aprirla senza finestra console, oppure esegui questo direttamente per la diagnostica:

```powershell
powershell -File desktop\WintageInstaller.ps1
```

Elenco temi con chip colore, i target trovati su questa macchina, un'anteprima Win95 dal vivo, e tutti i ventuno token colore come campioni modificabili. Modificare un qualsiasi campione fa un fork della palette in **Custom** invece di cambiare un tema distribuito sotto i tuoi piedi. Il pannello a destra mostra in tempo reale il contrasto WCAG dei tre token che portano testo — una palette che FAIL lì viene comunque rifiutata dal build gate, quindi è meglio vederlo prima di Apply che dopo.

I target sono divisi in due liste raggiungibili da tastiera: **MY APPS** contiene gli strumenti portatili/albero-sorgente CodeNomad, SAIPENVIEW, SmartVac e WildRift; **POPULAR APPS** contiene Windows, OBS, terminali, editor e l'altro software installato. ALL/NONE e Apply/Revert operano su entrambe le liste senza cambiarne il raggruppamento.

La finestra indossa la palette che sta per installare. È l'anteprima più veloce disponibile, e mantiene lo strumento onesto: una palette che rende questa finestra illeggibile è visibilmente illeggibile.

Apply delega a `install.ps1`. C'è esattamente un percorso di codice che installa un tema, quindi la GUI non può allontanarsi dalla riga di comando.

## La riga di comando

```powershell
.\desktop\install.ps1                                  # cosa c'è, cosa è temizzato, con quale palette
.\desktop\install.ps1 -Target freebuff -Palette klite  # un'app, una palette
.\desktop\install.ps1 -Target all -Palette goldendefault # tutto
.\desktop\install.ps1 -Target all -WhatIf              # dire cosa cambierebbe, non toccare nulla
.\desktop\install.ps1 -Target freebuff -Revert         # annullarne uno
```

`-Palette` predefinita `goldendefault` (**Golden Default**). La GUI si apre sulla stessa palette e controlla ogni target disponibile. Ridipingere un'app già temizzata funziona mentre è in esecuzione; una prima installazione no, perché l'archivio è in uso.

## Cosa ogni target può realmente essere temizzato

| target | meccanismo | sopravvive a un aggiornamento dell'app |
|---|---|---|
| `windows` | `.theme` utente: modalità sistema/app scura, ruoli colore accent e classici | sì — installato nella tua cartella locale Temi di Windows |
| `browsers` | rileva i profili Chromium installati + portatili, prepara il tema chrome scelto e apre le pagine di conferma Tampermonkey/tema di proprietà del browser | sì — dopo un **Load unpacked** per profilo |
| `terminal` | schema Windows Terminal + predefiniti tutti-profili, Consolas 12 con aliasing | sì — le impostazioni sono nel tuo profilo |
| `conhost` | predefiniti `HKCU\Console` + ogni profilo cmd/PowerShell esistente | sì — snapshot esatto dei valori toccati |
| `obs` | variante OBS 30.2+ `.ovt` + ID tema attivo in `user.ini` | sì — vive nel tuo profilo |
| `antigravity`, `vscode` | estensione tema colore in `~/.antigravity/extensions` / `~/.vscode/extensions` | **sì** — vive nel tuo profilo |
| `freebuff`, `antigravity-app`, `codenomad` | shim Electron, vedi sotto | no — rilancia l'installer |
| `claude` | shim Electron, patchato sul posto — vedi sotto | no — un aggiornamento crea una nuova cartella `app-<version>` |
| `mpchc` | registro, solo tema scuro + tipografia OSD | no — MPC-HC riscrive le sue impostazioni alla chiusura |
| `obsidian` | tema di comunità per vault, tutte le palette installate in una volta | **sì** — vive nel tuo vault |
| `saipenview` | riscrive i suoi stessi valori token `:root` in `style.css` | no — un file sorgente; rilancia dopo un pull |
| `discord` | CSS depositato nella cartella temi propria di BetterDiscord | sì |
| `totalcmd`, `totalcmd2` | chiavi `[Colors]` di `wincmd.ini`; i filtri file recenti esistenti usano il colore link della palette | sì — è la tua ini |
| `smartvac`, `wildrift` | tabella token riscritta nel codice sorgente proprio dell'app | no — un file sorgente; rilancia dopo un pull |

### Rimozione pubblicità FreeBuff

FreeBuff (l'app desktop dell'assistente AI) porta con sé una propria rete pubblicitaria: il bundle renderer (`resources/orchestrator/ui/assets/index-*.js`) renderizza una card `sponsored-ad` e un banner di thread, e l'orchestratore (`resources/orchestrator/orchestrator.js`) espone route `/api/ad/slot|impression|click` che chiamano l'asta pubblicitaria remota. Lo shim temizza solo l'app; non tocca quei file.

`desktop/patch-freebuff-ads.js` taglia gli annunci a livello di byte:

- renderer: i punti di chiamata di card/banner pubblicitario diventano `null`, e i metodi client API `adSlot` / `adImpression` / `adClick` diventano no-op — nulla viene renderizzato, e nessuna richiesta `/api/ad/*` esce mai dal renderer;
- orchestratore: tutte e tre le route `/api/ad/*` smettono di chiamare la rete pubblicitaria, e la richiesta annuncio inline di un turno dal vivo (`maybeRequestAd`) viene cortocircuitata.

Il nome del file bundle incorpora un hash di build, quindi la patch scopre il bundle corrente da `index.html` invece di spedire un payload bloccato sulla versione — è questo che la fa sopravvivere agli aggiornamenti. Gli originali vengono salvati in `_orig-backup-<timestamp>/` nella directory di installazione; `--revert` ripristina il più recente.

**Le versioni future sono gestite a due livelli indipendenti:**

1. **Patch a byte con fallback regex.** Ogni target ha una stringa esatta per la build corrente *e* un fallback con espressione regolare ancorato a ciò che un minificatore non può rinominare — i letterali di percorso `/api/ad/*`, il discriminatore di protocollo `case"ad":`, la classe `sponsored-ad`, e i posizionamenti `variant:"banner"` / `variant:"card"`. L'orchestratore non è minificato (nomi leggibili come `maybeRequestAd` e `app.ads.slotAd`), quindi le sue stringhe esatte reggono a lungo; il bundle renderer è minificato, quindi i suoi fallback regex prendono il sopravvento nel momento in cui la build successiva rinomina i suoi identificatori.
2. **Blocco a livello shim (`targets/electron/shim.cjs`).** Del tutto indipendente dal bundle: qualsiasi fetch/XHR verso un URL `/api/ad/` viene rifiutato dentro la pagina, e qualsiasi elemento la cui classe contiene `sponsored-ad` viene nascosto nel momento in cui appare. Nemmeno un bundle nuovissimo che questo script non ha ancora imparato può far emergere un annuncio.

```powershell
node .\desktop\patch-freebuff-ads.js           # patchare (prima il backup)
node .\desktop\patch-freebuff-ads.js --sound "C:\...\my.mp3"   # patchare + suono di completamento personalizzato (wav/mp3/ogg/flac/m4a/aac)
node .\desktop\patch-freebuff-ads.js --scan    # quali marcatori annuncio porta QUESTA build?
node .\desktop\patch-freebuff-ads.js --verify
node .\desktop\patch-freebuff-ads.js --revert
```

Viene eseguita automaticamente come parte di `install.ps1 -Target freebuff`, e va rilanciata dopo ogni aggiornamento di FreeBuff (gli aggiornamenti ripristinano i file originali). Se una build cambia forma, lo script nomina il target che non ha più corrisposto — esegui `--scan` per vedere cosa porta ancora la nuova build e aggiorna le stringhe lì.

**Suono di completamento FreeBuff.** Il renderer suona `chime-<hash>.mp3` quando un turno finisce. La patch lo trova nello stesso modo in cui trova il bundle (il nome incorpora un hash di build), quindi `--sound <file>` installa il tuo audio (wav/mp3/ogg/flac/m4a/aac) sopra e tiene il file originale come `chime-*.mp3.bak`; `--revert` lo ripristina. `--verify` segnala quale è attivo.

### Bottone suono FreeBuff (GUI)

`WintageInstaller.ps1` ha un piccolo bottone **FB SOUND** sotto la pila APPLY / REVERT. Memorizza solo una *preferenza*; `install.ps1 -Target freebuff` legge lo stesso file e lo passa alla patch come `--sound`, quindi pubblicità e suono vengono applicati in un'unica esecuzione:

- **Clic sinistro** — scegli un file audio (OpenFileDialog, wav/mp3/ogg/flac/m4a/aac) e ascoltalo subito: PCM WAV tramite System.Media.SoundPlayer, ogni altro formato tramite un MediaPlayer WPF (Media Foundation, asincrono, così la finestra non si blocca mai). La scelta è ricordata in `%APPDATA%\Wintage\freebuff-sound.txt` (per macchina, fuori dal checkout git, esattamente come le cartelle albero-sorgente ricordate).
- **Clic destro** — azzera la preferenza tornando al chime originale di FreeBuff (ferma anche qualsiasi anteprima ancora in riproduzione).
- **COPY** — copia l'audio scelto nel repository stesso (`sounds\freebuff.<ext>`, mantenendo l'estensione sorgente) e ripunta la preferenza a quella copia, così il suono sopravvive alla cancellazione o allo spostamento del file originale. Abilitato solo finché è impostato un suono personalizzato; ricopiare semplicemente sovrascrive la copia del repo. La cartella `sounds/` è normale contenuto tracciabile da git, quindi committarla fa sopravvivere il suono anche ai re-clone.

Vengono anteprimate solo le buste audio riconosciute — prima si annusa l'header, quindi una selezione non-audio viene annunciata invece di riprodurre silenziosamente nulla.

Il bottone mostra `ON` finché è impostato un suono personalizzato; passandoci sopra mostra il percorso. Applica poi il target `freebuff` (spunta FreeBuff + APPLY, oppure esegui `install.ps1 -Target freebuff` da un terminale) perché abbia effetto.

### Terminali

`terminal` scrive uno schema colori `Wintage` in ogni file di impostazioni di Windows Terminal stabile, Preview o non impacchettato rilevato e lo seleziona tramite `profiles.defaults`, insieme a Consolas 12 sicuro per console e testo con aliasing. Il file originale viene conservato byte per byte accanto e `-Revert` lo ripristina.

`conhost` copre il classico `cmd.exe`, Windows PowerShell, i profili console Git CMD/Bash e gli altri figli `HKCU\Console` esistenti. Scrive la tabella completa dei 16 colori della palette sia nei predefiniti radice che in ogni override esistente, poi ripristina solo i valori che ha toccato. Applica Consolas anche lì, perché la Verdana proporzionale collide dentro la griglia di celle a larghezza fissa usata da entrambi gli host di terminale.

### Browser e Tampermonkey

`browsers` trova i profili di Chrome, Edge, Brave, Cent, Vivaldi e Opera dalle posizioni installate e dalla root portabile a cui punti (`-PortableRoot`, o la voce `portable` ricordata in `paths.json`). Il suo stato mostra sia il numero di profili sia quanti contengono Tampermonkey. Apply copia il tema chrome scelto nella cartella stabile `%LOCALAPPDATA%\Wintage\browser-theme`, mette quel percorso negli appunti, e apre ogni profilo esatto su `chrome://extensions` più la pagina Installa/Aggiorna dello userscript Wintage. I profili senza Tampermonkey ricevono anche la sua pagina Chrome Web Store.

Chromium vieta deliberatamente l'installazione silenziosa di estensioni fuori-store su una macchina Windows non gestita. La prima installazione del tema browser richiede quindi una conferma **Developer mode → Load unpacked** per profilo. Scegli il percorso copiato; dopo, Wintage continua a sostituire la stessa cartella stabile quando le palette cambiano. Conferma anche **Install/Update** in Tampermonkey. Nessun file `Preferences` del browser, Secure Preferences o LevelDB di Tampermonkey viene modificato alle spalle del browser. Se Tampermonkey non era presente, installalo dalla scheda store aperta e aggiorna la scheda già aperta di `wintage.user.js` per ottenere la schermata di installazione.

### Windows

`windows` installa e attiva immediatamente un `%LOCALAPPDATA%\Microsoft\Windows\Themes\Wintage-<hash>.theme` indirizzato per contenuto. Parte dal tema attivo e sostituisce solo le sezioni documentate di colore, cursori e stile visivo. Sfondo, suoni e icone del desktop restano invariati; i cursori passano intenzionalmente allo schema `___CURRENT___` installato. Il primo tema attivo viene salvato byte per byte come `Wintage.original.theme`; i cambi di palette mantengono quella baseline, e `-Revert` lo riattiva. I controlli Windows moderni arrivano ancora dallo stile visivo Aero firmato — Wintage modifica le sue voci supportate di modalità scura, accent e colori di sistema classici invece di sostituire file `.msstyles` protetti. Le barre del titolo attive e inattive condividono il colore di superficie sollevata attenuato della palette; l'evidenziazione brillante resta riservata ai bordi di testo/selezione. L'accent precedente della barra inattiva viene fotografato separatamente e ripristinato esattamente da `-Revert`. L'hash di contenuto dà a Windows una nuova destinazione di associazione file quando la stessa palette viene ricostruita, quindi ri-applicare una palette aggiornata non viene scambiato per un no-op; il file Wintage superato viene rimosso dopo che Windows conferma attivo il nuovo.

### OBS Studio

`obs` genera una variante OBS 30.2+ sulla base mantenuta Yami Classic, la installa in `%APPDATA%\obs-studio\themes`, e scrive il suo ID tema stabile in `user.ini`, così la palette Wintage scelta è già selezionata al prossimo avvio. Chiudi OBS prima di Apply o Revert: OBS riscrive `user.ini` all'uscita. Il primo apply salva sia la selezione precedente sia qualsiasi tema omonimo byte per byte.

### App Electron

`resources/app.asar` viene spostato in `resources/app/app.asar` (il suo gemello `app.asar.unpacked` si muove con lui — quell'abbinamento è per nome file, e separarli rompe ogni modulo nativo), e un piccolo `shim.cjs` prende lo slot `resources/app` liberato. Lo shim inietta il foglio di stile e poi carica l'archivio originale. **Nessun byte dell'applicazione viene riscritto**, solo riposizionato; `-Revert` lo rimette direttamente al suo posto.

Il foglio di stile non viene scritto per queste app — viene estratto da `wintage.user.js`, quindi ogni correzione di smussi, scrollbar e scala tipografica fatta per il browser approda anche qui, senza una seconda copia che marcisca.

Due note da sapere in anticipo:

- L'approccio ovvio — mettere `resources/app` accanto all'archivio e affidarsi a Electron che lo preferisca — **non funziona e fallisce in silenzio**. Electron cerca prima `app.asar`. L'app parte perfettamente e il tema non gira mai.
- Lo shim è `.cjs`, non `.js`, di proposito. Il suo `package.json` viene copiato da quello dell'app così l'app mantiene nome e versione (il nome decide dove vive userData — uno shim che lo rinomina sposta l'app in un profilo vuoto). Se quel manifest dice `"type": "module"`, uno shim `.js` muore al primo `require`.

### L'app desktop di Claude: sul posto, e il frame in cui disegna davvero

Claude non può usare lo spostamento qui sopra, perché `OnlyLoadAppFromAsar` è fuso: Electron carica `resources/app.asar` e nient'altro, quindi uno shim in `resources/app` non potrà mai girare. Viene patchata **sul posto** invece: l'archivio viene salvato, il suo `main` in `package.json` viene riscritto a `"../wintage-shim.cjs"` (riempito alla stessa lunghezza in byte, così ogni offset nell'archivio resta valido), e l'hash di integrità per file viene aggiornato per corrispondere. `-Revert` ripristina il backup.

L'installer legge i fuse **prima di spostare qualsiasi cosa** e rifiuta con un motivo quando lo bloccano — `EnableEmbeddedAsarIntegrityValidation` farebbe fallire la riscrittura qui sopra all'avvio invece che all'installazione. Controlla qualsiasi app da solo:

```powershell
node ..\tools\electron-fuses.js "<path to the app's exe>"
```

La seconda metà era un problema molto più silenzioso. Il `BrowserWindow` di Claude renderizza un guscio sottile e **l'intera applicazione visibile è una `WebContentsView`** collegata a esso. Lo shim agganciava `browser-window-created`, quindi iniettava il foglio di stile nel guscio, segnalava successo a `wintage-status.txt`, e non cambiava nulla di visibile. Ora aggancia `web-contents-created`, che copre contenuti di finestra, `WebContentsView`, `BrowserView`, guest `<webview>` e popup allo stesso modo.

### Obsidian

Un tema di comunità viene scritto nel `.obsidian/themes/` di ogni vault — tutte le sedici palette in una volta, esattamente come il target VS Code, così passi da una all'altra in **Settings → Appearance** senza rilanciare nulla. Il template è stato derivato dal tema fatto a mano `VintageWin95` già presente nel vault, ogni colore sostituito dal token a cui corrispondeva. `-Palette <slug>` imposta quale è attiva all'installazione; `appearance.json` viene salvato prima, e `-Revert` rimuove solo i temi `Wintage *` e ripristina la tua scelta precedente — un tema fatto a mano nello stesso vault non viene mai toccato.

### SAIPENVIEW

Il suo frontend dichiara già i nomi token di Wintage nel suo stesso `:root`, quindi questa patch riscrive **solo i valori dei token** — mai un selettore, un font, una larghezza di bordo o un padding. Nulla che riguardi il box model cambia, quindi il testo non può spostarsi. È deliberato: l'approccio precedente aggiungeva sopra l'intero foglio di stile del browser, e `wintage.css` è scritto per pagine web arbitrarie — selettori universali che impongono font, scala di dimensioni, bordi di 2px e altezze dei controlli. Su un'app che ha già il proprio layout, quello sposta tutto.

Verificato mascherando ogni hex e facendo diff contro il backup: strutturalmente identico, differiscono solo i letterali di colore. `--link` viene segnalato come non dichiarato lì (i suoi link markdown leggono `--accentTeal`, che questo imposta) invece di essere iniettato — aggiungere una variabile che l'app non legge mai sarebbe peso morto.

### MPC-HC (K-Lite)

Win32 nativo, senza foglio di stile e senza punto di iniezione, e i colori del suo tema scuro sono compilati nel programma — nessun valore di registro li espone. Quindi questo target **non può portare una palette**. Cosa fa: attiva il tema scuro e applica le regole di tipografia di UI.md all'OSD, che è l'unica superficie che MPC-HC lascia controllare all'utente. Le impostazioni precedenti vengono esportate prima in `desktop/backup/mpc-hc-settings.reg`.

Chiudi MPC-HC prima di applicare: riscrive le sue impostazioni all'uscita.

## Ricostruzione

Tutto ciò che è sotto `desktop/out/` viene generato da `themes/*.json`. Non è tracciato in git (T-160), quindi un clone fresco deve costruire una volta prima di installare:

```powershell
node ..\tools\build-desktop.js          # ricostruisci tutti i target
node ..\tools\build-desktop.js --check  # exit 1 se qualcosa è stantio
```

`release.ps1` esegue il build e ogni gate, quindi una release non può spedire un output che si è allontanato dalle palette.

<!-- source-digest: desktop/README.md sha256:1b166ae6a7cf8a5c -->
