# Wintage für Desktop-Anwendungen

Das Userscript thematisiert das Web. Dieses thematisiert die Programme darum herum, mit denselben Paletten, damit Browser und Apps sich nicht mehr darüber streiten, was dunkles Gold bedeutet.

Hinter jeder Entscheidung hier steht eine Regel: **Anwendungen aktualisieren sich selbst, und ein Update darf nichts leise kaputtmachen.** Wo ein Ziel einen Platz in deinem eigenen Profil hat, kommt das Theme dorthin und übersteht Updates. Wo nicht, ist der Installer darauf ausgelegt, erneut ausgeführt zu werden — und sagt das auch, statt vorzugeben, es sei persistent.

## Die GUI

Doppelklicke **`Wintage Installer.vbs`** im Repository-Root, um sie ohne Konsolenfenster zu öffnen, oder führe das hier direkt für Diagnosen aus:

```powershell
powershell -File desktop\WintageInstaller.ps1
```

Themenliste mit Farbchips, die auf dieser Maschine gefundenen Ziele, eine Live-Win95-Vorschau und alle einundzwanzig Farbtokens als editierbare Swatches. Das Bearbeiten eines Swatch forkt die Palette in **Custom**, statt unter dir eine ausgelieferte Theme zu ändern. Das Panel rechts zeigt live WCAG-Kontrast für die drei Tokens, die Text tragen — eine Palette, die dort FAILt, lehnt das Build-Gate ohnehin ab, also ist es besser, das vor Apply zu sehen als danach.

Ziele sind in zwei tastaturerreichbare Listen geteilt: **MY APPS** enthält die portablen/Quellbaum-Tools CodeNomad, SAIPENVIEW, SmartVac und WildRift; **POPULAR APPS** enthält Windows, OBS, Terminals, Editoren und die andere installierte Software. ALL/NONE und Apply/Revert arbeiten über beide Listen, ohne deren Gruppierung zu ändern.

Das Fenster trägt die Palette, die es gleich installieren will. Das ist die schnellste verfügbare Vorschau, und es hält das Werkzeug ehrlich: eine Palette, die dieses Fenster unlesbar macht, ist sichtbar unlesbar.

Apply ruft `install.ps1` auf. Es gibt genau einen Codepfad, der ein Theme installiert, also kann die GUI nicht von der Kommandozeile abdriften.

## Die Kommandozeile

```powershell
.\desktop\install.ps1                                  # was ist da, was ist thematisiert, mit welcher Palette
.\desktop\install.ps1 -Target freebuff -Palette klite  # eine App, eine Palette
.\desktop\install.ps1 -Target all -Palette goldendefault # alles
.\desktop\install.ps1 -Target all -WhatIf              # sagen, was sich ändern würde, nichts anfassen
.\desktop\install.ps1 -Target freebuff -Revert         # eine rückgängig machen
```

`-Palette` ist standardmäßig `goldendefault` (**Golden Default**). Die GUI öffnet sich mit derselben Palette und prüft jedes verfügbare Ziel. Das Neu-Repainting einer bereits thematisierten App funktioniert, während sie läuft; eine Erstinstallation nicht, weil das Archiv in Benutzung ist.

## Was jedes Ziel tatsächlich themen kann

| target | Mechanismus | übersteht ein App-Update |
|---|---|---|
| `windows` | Benutzer-`.theme`: dunkler System-/App-Modus, Akzent- und klassische Farbrollen | ja — installiert in deinem lokalen Windows-Themes-Ordner |
| `browsers` | erkennt installierte + portable Chromium-Profile, bereitet die gewählte Chrome-Theme vor und öffnet die browser-eigenen Tampermonkey-/Theme-Bestätigungsseiten | ja — nach einmal **Load unpacked** pro Profil |
| `terminal` | Windows-Terminal-Schema + All-Profil-Standards, Consolas 12 aliased | ja — die Einstellungen liegen in deinem Profil |
| `conhost` | `HKCU\Console`-Defaults + jedes vorhandene cmd/PowerShell-Profil | ja — exakter Snapshot der berührten Werte |
| `obs` | OBS-30.2+-`.ovt`-Variante + aktive `user.ini`-Theme-ID | ja — sie lebt in deinem Profil |
| `antigravity`, `vscode` | Farbthemen-Erweiterung in `~/.antigravity/extensions` / `~/.vscode/extensions` | **ja** — sie lebt in deinem Profil |
| `freebuff`, `antigravity-app`, `codenomad` | Electron-Shim, siehe unten | nein — Installer erneut ausführen |
| `claude` | Electron-Shim, vor Ort gepatcht — siehe unten | nein — ein Update erzeugt einen neuen `app-<version>`-Ordner |
| `mpchc` | Registry, nur dunkle Theme + OSD-Typografie | nein — MPC-HC überschreibt seine Einstellungen beim Beenden |
| `obsidian` | Community-Theme pro Vault, alle Paletten auf einmal installiert | **ja** — sie lebt in deinem Vault |
| `saipenview` | schreibt seine eigenen `:root`-Tokenwerte in `style.css` um | nein — eine Quelldatei; nach einem Pull erneut ausführen |
| `discord` | CSS in den eigenen Theme-Ordner von BetterDiscord eingefügt | ja |
| `totalcmd`, `totalcmd2` | `wincmd.ini`-`[Colors]`-Schlüssel; vorhandene Recent-File-Filter nutzen die Paletten-Linkfarbe | ja — es ist deine ini |
| `smartvac`, `wildrift` | Tokentabelle im eigenen Quellcode der App umgeschrieben | nein — eine Quelldatei; nach einem Pull erneut ausführen |

### FreeBuff-Werbeentfernung

FreeBuff (die Desktop-App des KI-Assistenten) bringt ein eigenes Werbenetzwerk mit: das Renderer-Bundle (`resources/orchestrator/ui/assets/index-*.js`) rendert eine `sponsored-ad`-Karte und ein Thread-Banner, und der Orchestrator (`resources/orchestrator/orchestrator.js`) stellt `/api/ad/slot|impression|click`-Routen bereit, die die Remote-Werbeauktion aufrufen. Der Shim thematisiert nur die App; er fasst diese Dateien nicht an.

`desktop/patch-freebuff-ads.js` schneidet die Werbung bytegenau heraus:

- Renderer: die Aufrufstellen der Anzeigenkarte/des Banners werden zu `null`, und die `adSlot`-/`adImpression`-/`adClick`-API-Clientmethoden werden zu No-Ops — nichts rendert, und kein `/api/ad/*`-Request verlässt je den Renderer;
- Orchestrator: alle drei `/api/ad/*`-Routen rufen das Werbenetzwerk nicht mehr auf, und die Inline-Werbeanfrage bei Live-Turns (`maybeRequestAd`) wird kurzgeschlossen.

Der Bundle-Dateiname trägt einen Build-Hash, also entdeckt der Patch das aktuelle Bundle aus `index.html`, statt ein versionsfixiertes Payload mitzuliefern — genau das macht ihn updatefest. Originale werden nach `_orig-backup-<timestamp>/` im Installationsverzeichnis gesichert; `--revert` stellt das neueste wieder her.

**Zukünftige Versionen werden auf zwei unabhängigen Ebenen behandelt:**

1. **Byte-Patch mit Regex-Fallbacks.** Jedes Ziel hat einen exakten String für den aktuellen Build *und* einen Regex-Fallback, der an dem verankert ist, was ein Minifier nicht umbenennen kann — die `/api/ad/*`-Pfadliterale, der `case"ad":`-Protokoll-Diskriminator, die `sponsored-ad`-Klasse und die Platzierungen `variant:"banner"` / `variant:"card"`. Der Orchestrator ist nicht minifiziert (lesbare Namen wie `maybeRequestAd` und `app.ads.slotAd`), also halten seine exakten Strings lange; das Renderer-Bundle ist minifiziert, also übernehmen seine Regex-Fallbacks in dem Moment, in dem der nächste Build seine Bezeichner umbenennt.
2. **Shim-Ebenen-Block (`targets/electron/shim.cjs`).** Völlig unabhängig vom Bundle: jeder fetch/XHR zu einer `/api/ad/`-URL wird in der Seite abgewiesen, und jedes Element, dessen Klasse `sponsored-ad` enthält, wird in dem Moment ausgeblendet, in dem es erscheint. Selbst ein brandneues Bundle, das dieses Skript noch nicht kennt, kann keine Anzeige zeigen.

```powershell
node .\desktop\patch-freebuff-ads.js           # patchen (Backup zuerst)
node .\desktop\patch-freebuff-ads.js --sound "C:\...\my.mp3"   # patchen + benutzerdefinierter Abschlusston (wav/mp3/ogg/flac/m4a/aac)
node .\desktop\patch-freebuff-ads.js --scan    # welche Ad-Marker trägt DIESER Build?
node .\desktop\patch-freebuff-ads.js --verify
node .\desktop\patch-freebuff-ads.js --revert
```

Es läuft automatisch als Teil von `install.ps1 -Target freebuff` und muss nach jedem FreeBuff-Update erneut ausgeführt werden (Updates stellen die Originaldateien wieder her). Ändert ein Build seine Form, nennt das Skript das Ziel, das nicht mehr passte — führe `--scan` aus, um zu sehen, was der neue Build noch trägt, und aktualisiere dort die Strings.

**FreeBuff-Abschlusston.** Der Renderer spielt `chime-<hash>.mp3` ab, wenn eine Runde endet. Der Patch findet ihn genauso, wie er das Bundle findet (der Name trägt einen Build-Hash), also installiert `--sound <file>` dein eigenes Audio (wav/mp3/ogg/flac/m4a/aac) darüber und behält die Originaldatei als `chime-*.mp3.bak`; `--revert` stellt sie wieder her. `--verify` meldet, welche gerade aktiv ist.

### FreeBuff-Ton-Button (GUI)

`WintageInstaller.ps1` hat einen kleinen **FB SOUND**-Button unter dem APPLY-/REVERT-Stack. Er speichert nur eine *Präferenz*; `install.ps1 -Target freebuff` liest dieselbe Datei und übergibt sie dem Patch als `--sound`, also werden Werbung und Ton in einem Lauf angewendet:

- **Linksklick** — eine Audiodatei wählen (OpenFileDialog, wav/mp3/ogg/flac/m4a/aac) und sie sofort abspielen hören: PCM WAV über System.Media.SoundPlayer, jedes andere Format über einen WPF-MediaPlayer (Media Foundation, async, also friert das Fenster nie ein). Die Wahl wird in `%APPDATA%\Wintage\freebuff-sound.txt` gemerkt (pro Maschine, außerhalb des git-Checkouts, genau wie die gemerkten Quellbaum-Ordner).
- **Rechtsklick** — die Präferenz zurück auf FreeBuffs Original-Chime setzen (stoppt auch jede noch laufende Vorschau).
- **COPY** — kopiert das gewählte Audio in das Repo selbst (`sounds\freebuff.<ext>`, mit der Quelldateiendung) und zeigt die Präferenz auf diese Kopie, damit der Ton das Löschen oder Verschieben der Originaldatei überlebt. Nur aktiv, solange ein benutzerdefinierter Ton gesetzt ist; erneutes Kopieren überschreibt die Repo-Kopie einfach. Der `sounds/`-Ordner ist normaler git-tracbarer Inhalt, also überlebt das Einchecken auch Re-Clones.

Nur erkannte Audio-Container werden vorgespielt — der Header wird zuerst gesnifft, also wird eine Nicht-Audio-Auswahl angesagt, statt still nichts abzuspielen.

Der Button zeigt `ON`, solange ein benutzerdefinierter Ton gesetzt ist; beim Hovern wird der Pfad angezeigt. Wende danach das `freebuff`-Ziel an (FreeBuff + APPLY anhaken, oder `install.ps1 -Target freebuff` aus einem Terminal ausführen), damit es wirkt.

### Terminals

`terminal` schreibt ein `Wintage`-Farbschema in jede erkannte stabile, Preview- oder ungepackte Windows-Terminal-Einstellungsdatei und wählt es über `profiles.defaults`, zusammen mit konsolen-sicherem Consolas 12 und aliased Text. Die Originaldatei wird bytegenau daneben behalten und `-Revert` stellt sie wieder her.

`conhost` deckt klassisches `cmd.exe`, Windows PowerShell, Git CMD/Bash-Konsolenprofile und andere vorhandene `HKCU\Console`-Kinder ab. Es schreibt die volle 16-Farben-Tabelle der Palette sowohl in die Root-Defaults als auch in jeden vorhandenen Override und stellt danach nur die berührten Werte wieder her. Es wendet dort auch Consolas an, weil proportionale Verdana innerhalb des festen Zellengitters kollidiert, das beide Terminal-Hosts verwenden.

### Browser und Tampermonkey

`browsers` findet Chrome-, Edge-, Brave-, Cent-, Vivaldi- und Opera-Profile aus installierten Orten und aus dem portablen Root, auf den du zeigst (`-PortableRoot` oder der gemerkte `portable`-Eintrag in `paths.json`). Sein Status zeigt sowohl die Profilanzahl als auch, wie viele Tampermonkey enthalten. Apply kopiert das gewählte Browser-Chrome-Theme in den stabilen Ordner `%LOCALAPPDATA%\Wintage\browser-theme`, legt diesen Pfad in die Zwischenablage und öffnet jedes genaue Profil bei `chrome://extensions` plus die Wintage-Userscript-Installations-/Update-Seite. Profile ohne Tampermonkey bekommen zusätzlich dessen Chrome-Web-Store-Seite.

Chromium verbietet absichtlich die stille Off-Store-Erweiterungsinstallation auf einem nicht verwalteten Windows-Rechner. Die erste Browser-Theme-Installation braucht daher eine **Developer mode → Load unpacked**-Bestätigung pro Profil. Wähle den kopierten Pfad; danach ersetzt Wintage bei Palettenänderungen immer denselben stabilen Ordner. Bestätige zusätzlich **Install/Update** in Tampermonkey. Keine Browser-`Preferences`, Secure-Preferences- oder Tampermonkey-LevelDB-Datei wird hinter dem Rücken des Browsers editiert. Wenn Tampermonkey nicht vorhanden war, installiere es aus dem geöffneten Store-Tab und aktualisiere den bereits offenen `wintage.user.js`-Tab, um den Installationsbildschirm zu bekommen.

### Windows

`windows` installiert und aktiviert sofort ein inhaltsadressiertes `%LOCALAPPDATA%\Microsoft\Windows\Themes\Wintage-<hash>.theme`. Es startet vom aktiven Theme und ersetzt nur die dokumentierten Farb-, Cursor- und Visual-Style-Abschnitte. Wallpaper, Sounds und Desktop-Icons bleiben unverändert; Cursor wechseln absichtlich zum installierten `___CURRENT___`-Schema. Das erste aktive Theme wird bytegenau als `Wintage.original.theme` gespeichert; Palettenänderungen behalten diese Baseline, und `-Revert` aktiviert sie wieder. Moderne Windows-Steuerelemente kommen weiterhin aus dem signierten Aero-Visual-Style — Wintage ändert dessen unterstützten Dunkelmodus, Akzent- und klassische Systemfarb-Eingaben, statt geschützte `.msstyles`-Dateien zu ersetzen. Aktive und inaktive Titelzeilen teilen die gedämpfte erhabene Oberflächenfarbe der Palette; das helle Highlight bleibt für Text-/Auswahlkanten reserviert. Der vorherige inaktive Titel-Akzent wird separat gesnapshottet und von `-Revert` exakt wiederhergestellt. Der Inhaltshash gibt Windows ein neues Dateizuordnungsziel, wenn dieselbe Palette neu gebaut wird, also wird ein erneutes Anwenden einer aktualisierten Palette nicht für einen No-Op gehalten; die ersetzte Wintage-Datei wird entfernt, nachdem Windows die neue als aktiv bestätigt.

### OBS Studio

`obs` erzeugt eine OBS-30.2+-Variante über die gepflegte Yami-Classic-Basis, installiert sie in `%APPDATA%\obs-studio\themes` und schreibt ihre stabile Theme-ID in `user.ini`, also ist die gewählte Wintage-Palette beim nächsten Start bereits ausgewählt. Schließe OBS vor Apply oder Revert: OBS überschreibt `user.ini` beim Beenden. Der erste Apply sichert sowohl die vorherige Auswahl als auch jede gleichnamige Theme bytegenau.

### Electron-Apps

`resources/app.asar` wird zu `resources/app/app.asar` verschoben (seine `app.asar.unpacked`-Geschwisterdatei zieht mit — diese Paarung läuft über den Dateinamen, und das Trennen bricht jedes native Modul), und ein kleiner `shim.cjs` nimmt den geräumten `resources/app`-Slot. Der Shim injiziert das Stylesheet und lädt dann das Originalarchiv. **Kein Anwendungsbyte wird umgeschrieben**, nur verschoben; `-Revert` verschiebt es direkt zurück.

Das Stylesheet wird für diese Apps nicht geschrieben — es wird aus `wintage.user.js` extrahiert, also landet jede Bevel-, Scrollbar- und Type-Ladder-Fix, die für den Browser gemacht wurde, auch hier, ohne eine zweite Kopie zum Verrotten.

Zwei Hinweise, die man im Voraus kennen sollte:

- Der naheliegende Ansatz — `resources/app` neben das Archiv legen und darauf vertrauen, dass Electron es bevorzugt — **funktioniert nicht und scheitert still**. Electron sucht zuerst nach `app.asar`. Die App startet perfekt und das Theme läuft nie.
- Der Shim ist absichtlich `.cjs`, nicht `.js`. Sein `package.json` wird vom eigenen der App kopiert, damit die App Name und Version behält (der Name entscheidet, wo userData lebt — ein Shim, der ihn umbenennt, verschiebt die App in ein leeres Profil). Sagt das Manifest `"type": "module"`, stirbt ein `.js`-Shim beim ersten `require`.

### Claudes Desktop-App: vor Ort, und der Rahmen, in dem sie tatsächlich zeichnet

Claude kann die Verschiebung oben nicht nutzen, weil `OnlyLoadAppFromAsar` fest verschweißt ist — Electron lädt `resources/app.asar` und sonst nichts, also kann ein Shim in `resources/app` nie laufen. Stattdessen wird **vor Ort** gepatcht: das Archiv wird gesichert, sein `package.json`-`main` wird zu `"../wintage-shim.cjs"` umgeschrieben (auf dieselbe Bytelänge aufgefüllt, damit jedes Offset im Archiv gültig bleibt), und der per-Datei-Integritätshash wird entsprechend aktualisiert. `-Revert` stellt das Backup wieder her.

Der Installer liest die Fuses **vor jeder Bewegung** und verweigert mit einem Grund, wenn sie blockieren — `EnableEmbeddedAsarIntegrityValidation` würde das Umschreiben oben eher beim Start als bei der Installation scheitern lassen. Prüfe jede App selbst:

```powershell
node ..\tools\electron-fuses.js "<path to the app's exe>"
```

Die zweite Hälfte davon war ein viel leiseres Problem. Claudes `BrowserWindow` rendert eine dünne Schale und die **gesamte sichtbare Anwendung ist eine `WebContentsView`**, die daran hängt. Der Shim hakte früher `browser-window-created`, also injizierte er das Stylesheet in die Schale, meldete Erfolg an `wintage-status.txt` und änderte nichts Sichtbares. Er hakt jetzt `web-contents-created`, das Fensterinhalte, `WebContentsView`s, `BrowserView`s, `<webview>`-Gäste und Popups gleichermaßen abdeckt.

### Obsidian

Eine Community-Theme wird in jedes Vault-Verzeichnis `.obsidian/themes/` geschrieben — alle sechzehn Paletten auf einmal, genau wie beim VS-Code-Ziel, also wechselst du zwischen ihnen in **Settings → Appearance**, ohne etwas erneut auszuführen. Die Vorlage wurde von der handgefertigten `VintageWin95`-Theme abgeleitet, die schon im Vault war, jede Farbe durch den Token ersetzt, dem sie entsprach. `-Palette <slug>` setzt, welche bei der Installation aktiv ist; `appearance.json` wird zuerst gesichert, und `-Revert` entfernt nur die `Wintage *`-Themes und stellt deine frühere Wahl wieder her — eine handgefertigte Theme im selben Vault wird nie angefasst.

### SAIPENVIEW

Sein Frontend deklariert die Wintage-Tokennamen bereits in seinem eigenen `:root`, also schreibt dieser Patch **nur die Tokenwerte** um — nie einen Selektor, ein Font, eine Rahmenbreite oder ein Padding. Nichts, was das Box-Model betrifft, ändert sich, also kann der Text nicht verrutschen. Das ist beabsichtigt: der frühere Ansatz hängte das ganze Browser-Stylesheet oben an, und `wintage.css` ist für beliebige Webseiten geschrieben — universelle Selektoren, die Font, Größenleiter, 2px-Rahmen und Steuerelementhöhen erzwingen. Auf einer App, die bereits ein eigenes Layout hat, verschiebt das alles.

Verifiziert durch Maskieren jedes Hex und Diff gegen das Backup: strukturell identisch, nur Farbliterale unterscheiden sich. `--link` wird dort als nicht deklariert gemeldet (seine Markdown-Links lesen `--accentTeal`, das dieser Patch setzt), statt injiziert — eine Variable hinzuzufügen, die die App nie liest, wäre totes Gewicht.

### MPC-HC (K-Lite)

Natives Win32, kein Stylesheet und kein Injektionspunkt, und die Farben seines dunklen Themes sind ins Programm kompiliert — kein Registry-Wert legt sie offen. Also kann dieses Ziel **keine Palette tragen**. Was es tut: schaltet das dunkle Theme ein und wendet die UI.md-Typografieregeln auf das OSD an, die eine Fläche, die MPC-HC dem Benutzer überlässt. Die vorherigen Einstellungen werden zuerst nach `desktop/backup/mpc-hc-settings.reg` exportiert.

Schließe MPC-HC vor dem Anwenden: Es überschreibt seine Einstellungen beim Beenden.

## Neu aufbauen

Alles unter `desktop/out/` wird aus `themes/*.json` erzeugt. Es ist nicht in git getrackt (T-160), also muss ein frischer Clone einmal bauen, bevor installiert wird:

```powershell
node ..\tools\build-desktop.js          # alle Ziele neu bauen
node ..\tools\build-desktop.js --check  # exit 1, wenn etwas stale ist
```

`release.ps1` führt den Build und jedes Gate aus, also kann ein Release keinen Output liefern, der von den Paletten abgedriftet ist.

<!-- source-digest: desktop/README.md sha256:1b166ae6a7cf8a5c -->
