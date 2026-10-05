# Wintage per applicazioni desktop

Lo userscript temizza il web. Questo temizza i programmi che lo circondano, dalle stesse palette, così browser e app smettono di litigare su cosa significhi "dark golden".

C'è una regola dietro ogni decisione: **le applicazioni si aggiornano da sole, e un aggiornamento non deve rompere nulla in silenzio.** Dove un target ha un posto nel tuo profilo, il tema va lì e sopravvive agli aggiornamenti. Dove non ce l'ha, l'installer è scritto per essere rilanciato — e lo dice, invece di fingere di aver persistito.

## La GUI

Fai doppio clic su **`Wintage Installer.vbs`** nella root del repository per aprirla senza finestra console, oppure esegui questo direttamente per la diagnostica:

```powershell
powershell -File desktop\WintageInstaller.ps1
```

Elenco temi con chip colore, i target trovati su questa macchina, un'anteprima Win95 dal vivo, e tutti i ventuno token colore come campioni modificabili. Modificare un qualsiasi campione fa un fork della palette in **Custom** invece di cambiare un tema distribuito sotto i tuoi piedi. Il pannello a destra mostra in tempo reale il contrasto WCAG dei tre token che portano testo — una palette che FAIL lì viene comunque rifiutata dal build gate, quindi è meglio vederlo prima di Apply che dopo.

I target sono divisi in due liste raggiungibili da tastiera: **MY APPS** contiene gli strumenti portatili/albero-sorgente CodeNomad, WorkBuddy; **POPULAR APPS** contiene Windows, OBS, terminali, editor e l'altro software installato. ALL/NONE e Apply/Revert operano su entrambe le liste senza cambiarne il raggruppamento.

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

| obiettivo | meccanismo | sopravvive a un aggiornamento dell'app |
|---|---|---|
| `windows` | `.theme` utente: modalità sistema/app scura, ruoli colore accent e classici | sì — installato nella tua cartella locale Temi di Windows |
| `browsers` | rileva i profili Chromium installati + portatili, prepara il tema chrome scelto e apre le pagine di conferma Tampermonkey/tema di proprietà del browser | sì — dopo un **Load unpacked** per profilo |
| `terminal` | schema Windows Terminal + predefiniti tutti-profili, Consolas 12 con aliasing | sì — le impostazioni sono nel tuo profilo |
| `conhost` | predefiniti `HKCU\Console` + ogni profilo cmd/PowerShell esistente | sì — snapshot esatto dei valori toccati |
| `obs` | variante OBS 30.2+ `.ovt` + ID tema attivo in `user.ini` | sì — vive nel tuo profilo |
| `qbittorrent` | tema UI Qt non impacchettato (`config.json` + `stylesheet.qss`) + le due chiavi del tema in `qBittorrent.ini` | sì — vive nel tuo profilo |
| `antigravity`, `vscode` | estensione tema colore in `~/.antigravity/extensions` / `~/.vscode/extensions` | **sì** — vive nel tuo profilo |
| `freebuff`, `antigravity-app`, `codenomad` | shim Electron, vedi sotto | no — rilancia l'installer |
| `claude` | shim Electron, patchato sul posto — vedi sotto | no — un aggiornamento crea una nuova cartella `app-<version>` |
| `mpchc` | registro, solo tema scuro + tipografia OSD | no — MPC-HC riscrive le sue impostazioni alla chiusura |
| `obsidian` | tema di comunità per vault, tutte le palette installate in una volta | **sì** — vive nel tuo vault |
| `discord` | CSS depositato nella cartella temi propria di BetterDiscord | sì |
| `totalcmd`, `totalcmd2` | chiavi `[Colors]` di `wincmd.ini`; i filtri file recenti esistenti usano il colore link della palette | sì — è la tua ini |

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

### qBittorrent

`qbittorrent` scrive un tema UI Qt **non impacchettato** in `%APPDATA%\qBittorrent\themes\wintage` — un `config.json` (i ruoli `Palette.*` più i colori di contesto propri di qBittorrent: stati della lista trasferimenti, gravità del registro) e accanto uno `stylesheet.qss` (gli smussi da 2px, gli angoli squadrati e Verdana, che una palette non può esprimere) — poi punta `General\CustomUIThemePath` a quel `config.json` e imposta `General\UseCustomUITheme=true`.
Non impacchettato invece che come bundle `.qbtheme`, di proposito: un `.qbtheme` è un file Qt Resource Collection e per produrlo servirebbe sulla macchina un binario `rcc` con la stessa versione maggiore, cioè una dipendenza da compilatore per due file di testo. qBittorrent legge la forma a cartella in modo nativo (`FolderThemeSource`).
Chiudi qBittorrent prima di Apply o Revert: riscrive l’intero `qBittorrent.ini` all’uscita, quindi una modifica fatta mentre è in esecuzione viene persa alla chiusura — il target si rifiuta di funzionare in quello stato invece di riportare un successo che l’uscita successiva cancella. `-Revert` riporta le due chiavi INI ai loro valori esatti precedenti a Wintage (o le rimuove se non c’erano) e rimette a posto byte per byte ogni cartella di tema con lo stesso nome; le modifiche non correlate a `qBittorrent.ini` fatte dopo Apply sopravvivono.
Non raggiungibile: le icone della barra degli strumenti e dell’area di notifica provengono dal bundle di risorse compilato di qBittorrent, quindi mantengono i colori originali.

### Caratteri: nominati, mai installati

La legge 1 di UI.md chiede Verdana **senza antialiasing**. Un foglio di stile Qt non ha alcuna proprietà per questo, e l'`OSDFont` di MPC-HC è un semplice nome di font GDI — quindi l'unica leva è il font stesso. Il `Verdana_m1.ttf` nella radice del repository è una copia di Verdana con tratti bitmap a 1 bpp già renderizzati da 3 a 30 ppem, che il renderer preferisce rispetto all'antialiasing del contorno.
I fogli di stile di `qbittorrent` e `obs` nominano `Verdana_m1, Verdana`, e `mpchc` nomina quella che la macchina risolve davvero. **Il programma di installazione non installa e non disinstalla mai un font**, ed è una scelta deliberata, non un lavoro incompiuto:
Una famiglia di font viene risolta tramite (famiglia, stile). Registra Regular + Bold + Italic e ogni fruitore si risolve correttamente; annulla **un** membro e ogni fruitore che chiede quella famiglia si ripunta su un membro sopravvissuto. Su una macchina che aliassa `MS Shell Dlg 2` — il font delle finestre di dialogo di Windows — a quella famiglia tramite `HKLM\...\FontSubstitutes`, rimuovere Regular rende **l'intero desktop corsivo**, compresi i titoli delle finestre che il DWM ha già messo in cache, ed è necessario un logout per recuperarlo. Nessun conteggio dei riferimenti risolve la cosa: il raggio d'azione è l'intera macchina e un installatore di temi non ha nulla da fare lì.
Il font è dunque un'azione dell'utente unica e esplicita: clic destro su `Verdana_m1.ttf` → **Installa** (per utente, senza diritti di amministratore), poi riapplica il bersaglio. Se il font è assente, i bersagli lo dicono una volta, nominano la correzione e tornano alla Verdana di fabbrica — con antialiasing, ma senza toccare la macchina alle tue spalle.

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

<!-- T-311 target/section coverage supplement -->
## Copertura di target e sezioni

Questa sezione rispecchia la copertura Process Explorer, Notepad++, Cinema 4D
e dei font del terminale del README inglese corrente, così questa localizzazione
non diventa vecchia in silenzio. I letterali di codice (id dei target, percorsi
del registro, nomi dei file) sono invarianti per lingua per progetto; il testo
intorno è tradotto.

### Cosa ogni target può realmente essere temizzato (target aggiunti)

| obiettivo | meccanismo | sopravvive a un aggiornamento dell'app |
|---|---|---|
| `notepadplusplus` | XML del tema + alias nella cartella `themes` di Notepad++ dell'utente | sì — vive nel tuo profilo |
| `cinema4d` | schema colori depositato nella cartella `schemes` di Cinema 4D dell'utente | sì — vive nel tuo profilo |
| `processexplorer` | `HKCU\Software\Sysinternals\Process Explorer`: colori di evidenziazione righe e sfondi dei grafici, vedi sotto | no — Process Explorer riscrive le sue impostazioni all'uscita; chiudilo e rilancialo |

### Process Explorer (Sysinternals)

Process Explorer conserva i suoi colori in
`HKCU\Software\Sysinternals\Process Explorer` e riscrive quella chiave
all'uscita, quindi il target **rifiuta mentre `procexp`, `procexp64` o
`procexp64a` è in esecuzione** — chiudilo e rilancialo. Temizza le categorie
di colore configurabili:

- **raggiungibili**: i colori di evidenziazione delle righe di processo
  (`ColorOwn`, `ColorServices`, `ColorRelocatedDlls`, `ColorImmersive`,
  `ColorPacked`, `ColorJobs`, `ColorNet`, `ColorProtected`, `ColorNewProc`,
  `ColorDelProc`, `ColorSuspend`) sia nelle varianti a modalità chiara sia
  `*Dark`, più gli sfondi dei grafici (`ColorGraphBk`, `ColorGraphBkDark`) —
  24 valori in tutto. Ogni variante viene mescolata verso il polo corrispondente
  della palette attiva (la tonalità più chiara per il riempimento chiaro,
  quella più scura per `*Dark`), così i riempimenti delle righe restano nella
  chiave della palette stessa invece di sbiadire verso un quasi bianco;
- **non raggiungibili**: la barra del titolo, la barra dei menu, la barra degli
  strumenti, lo sfondo e i colori del testo della vista a elenco, e i colori
  delle linee dei grafici — sono compilati dentro `procexp.exe` e non sono
  esposti da nessun valore di impostazione. Il target temizza le evidenziazioni
  delle righe e lo sfondo del grafico che possiede davvero, e non pretende
  nient'altro.

Ogni valore che Apply può mutare viene messo in snapshot prima della mutazione
(ripristino al primo tocco in
`%APPDATA%\Wintage\recovery\processexplorer\`) e ripristinato esattamente da
`-Revert`, incluso se ogni valore era assente e se il marcatore era
presente-ma-vuoto. Una cartella portatile fuori dalle directory Sysinternals
standard viene ricordata tramite la chiave canonica `processexplorer` in
`paths.json` (argomento CLI `-ProcessExplorerPath`; anche la GUI può
sceglierla).

### Font del terminale (`fonts/terminal/`)

Entrambi i target del terminale leggono UNA sola preferenza tipografica
canonica in `%APPDATA%\Wintage\terminal-font.json` (`schema`, `fontSlug`,
`family`, `size`, `renderingMode`). Quando il file manca, i target mantengono
il valore predefinito distribuito (Terminus (TTF) per Windows, 12 pt, con
alias), quindi le macchine esistenti restano invariate. Una preferenza
malformata fallisce in modo chiuso: non viene sovrascritto nulla e il target
rifiuta.

`fonts/terminal/catalog.json` è l'unico catalogo dei font: 20 famiglie
monospaced open source incluse più i due typeface di sistema che Wintage
nomina ma non distribuisce mai (Terminus (TTF) per Windows, Consolas). Ogni
voce inclusa porta la sua sorgente upstream, la revisione bloccata, l'id della
licenza, il file di licenza e lo SHA-256. I file esatti sono vendored in
`fonts/terminal/files/` con i testi delle licenze in `licenses/`; Wintage in
esecuzione lavora completamente offline e non scarica mai un font.

`tools/sync-terminal-fonts.ps1` è il downloader riservato ai manutentori.
Legge `fonts/terminal/sources.json` (un artefatto immutabile per famiglia),
verifica ogni SHA-256 e rifiuta ogni mismatch. `-VerifyOnly` (predefinito)
controlla l'albero su disco senza rete; `-Fetch -Write` ripubblica i file. I
byte dei font scaricati sono trattati come asset binari non fidati — hashati e
scritti, mai eseguiti. Una sostituzione è documentata: **Fantasque Sans Mono**
sostituisce Liberation Mono, che non pubblica alcuna release binaria bloccata
(solo sorgente `.sfd`).

L'installer **sfoglia i font, non li installa.** La scheda TERMINAL FONTS
carica un typeface incluso in una `PrivateFontCollection` locale al processo
per un'anteprima dal vivo, e non esegue **nessuna** registrazione di font di
sistema. Scegliere un font, una dimensione (7–24 pt) o una modalità di
rendering (aliased/grayscale/cleartype) aggiorna solo l'anteprima e la
preferenza. Installare un font è un'azione esplicita **INSTALL SELECTED** che
apre l'installatore di font di Windows stesso; dopo la conferma di Windows
l'utente riverifica con Refresh. Le modifiche reali al terminale avvengono solo
con un'azione esplicita **APPLY TERMINAL / APPLY CONHOST / APPLY BOTH**.

Windows Terminal viene applicato alla famiglia installata selezionata alla
dimensione scelta, e la modalità di rendering mappa su
`profiles.defaults.antialiasingMode`. Il conhost classico è più severo: esegue
il rendering su una griglia a celle fissa, quindi il typeface selezionato
viene rifiutato prima di qualunque modifica al registro a meno che Windows non
lo risolva (il typeface predefinito e il fallback Consolas sono esenti). Health
e Reapply validano typeface, dimensione e anti-aliasing configurati rispetto
alla preferenza, così cambiare la preferenza dopo un Apply viene segnalato
come drift anziché come "sano". Il ciclo di vita dei colori del terminale resta
intatto: Revert ripristina esattamente i valori posseduti pre-Wintage e non
rimuove mai un font dalla macchina.
<!-- source-digest: desktop/README.md sha256:15c96dac8494ab84 -->
