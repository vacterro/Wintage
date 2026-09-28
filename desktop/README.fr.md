# Wintage pour les applications de bureau

L'userscript thème le web. Ceci thème les programmes qui l'entourent, à partir des mêmes palettes, pour que le navigateur et les apps cessent de se disputer sur ce que « dark golden » veut dire.

Il y a une règle derrière chaque décision : **les applications se mettent à jour toutes seules, et une mise à jour ne doit rien casser en silence.** Là où une cible a une place dans votre propre profil, le thème y va et survit aux mises à jour. Là où elle n'en a pas, l'installeur est conçu pour être relancé — et le dit, plutôt que de prétendre avoir persisté.

## La GUI

Double-cliquez sur **`Wintage Installer.vbs`** à la racine du dépôt pour l'ouvrir sans fenêtre de console, ou exécutez ceci directement pour les diagnostics :

```powershell
powershell -File desktop\WintageInstaller.ps1
```

Liste de thèmes avec pastilles de couleur, les cibles trouvées sur cette machine, un aperçu Win95 en direct, et les vingt-et-un tokens de couleur comme nuanciers modifiables. Modifier un nuancier fork la palette en **Custom** plutôt que de changer un thème livré sous vos pieds. Le panneau de droite affiche en direct le contraste WCAG des trois tokens qui portent du texte — une palette qui FAIL à cet endroit est de toute façon refusée par le build gate, donc il vaut mieux la voir avant Apply qu'après.

Les cibles sont réparties en deux listes accessibles au clavier : **MY APPS** contient les outils portables/arbre-source CodeNomad, WorkBuddy ; **POPULAR APPS** contient Windows, OBS, terminaux, éditeurs et l'autre logiciel installé. ALL/NONE et Apply/Revert agissent sur les deux listes sans changer leur regroupement.

La fenêtre porte la palette qu'elle s'apprête à installer. C'est l'aperçu le plus rapide disponible, et cela garde l'outil honnête : une palette qui rend cette fenêtre illisible est visiblement illisible.

Apply délègue à `install.ps1`. Il y a exactement un chemin de code qui installe un thème, donc la GUI ne peut pas dériver de la ligne de commande.

## La ligne de commande

```powershell
.\desktop\install.ps1                                  # ce qui est là, ce qui est thémé, avec quelle palette
.\desktop\install.ps1 -Target freebuff -Palette klite  # une app, une palette
.\desktop\install.ps1 -Target all -Palette goldendefault # tout
.\desktop\install.ps1 -Target all -WhatIf              # dire ce qui changerait, ne rien toucher
.\desktop\install.ps1 -Target freebuff -Revert         # annuler une seule
```

`-Palette` est par défaut `goldendefault` (**Golden Default**). La GUI s'ouvre sur la même palette et vérifie chaque cible disponible. Repeindre une app déjà thémée fonctionne pendant qu'elle tourne ; une première installation non, car l'archive est en cours d'utilisation.

## Ce que chaque cible peut réellement être thémé

| target | mécanisme | survit à une mise à jour d'app |
|---|---|---|
| `windows` | `.theme` utilisateur : mode système/app sombre, rôles de couleurs accent et classiques | oui — installé dans votre dossier Windows Themes local |
| `browsers` | détecte les profils Chromium installés + portables, prépare le thème chrome choisi et ouvre les pages de confirmation Tampermonkey/thème propres au navigateur | oui — après un **Load unpacked** par profil |
| `terminal` | schéma Windows Terminal + défauts tous-profils, Consolas 12 aliased | oui — les paramètres sont dans votre profil |
| `conhost` | défauts `HKCU\Console` + chaque profil cmd/PowerShell existant | oui — instantané exact des valeurs touchées |
| `obs` | variante OBS 30.2+ `.ovt` + ID de thème `user.ini` actif | oui — il vit dans votre profil |
| `antigravity`, `vscode` | extension de thème de couleurs dans `~/.antigravity/extensions` / `~/.vscode/extensions` | **oui** — elle vit dans votre profil |
| `freebuff`, `antigravity-app`, `codenomad` | shim Electron, voir ci-dessous | non — relancez l'installeur |
| `claude` | shim Electron, patché sur place — voir ci-dessous | non — une mise à jour crée un nouveau dossier `app-<version>` |
| `mpchc` | registre, thème sombre + typographie OSD uniquement | non — MPC-HC réécrit ses paramètres à la fermeture |
| `obsidian` | thème communautaire par vault, toutes les palettes installées d'un coup | **oui** — il vit dans votre vault |
| `discord` | CSS déposé dans le propre dossier de thèmes de BetterDiscord | oui |
| `totalcmd`, `totalcmd2` | clés `[Colors]` de `wincmd.ini` ; les filtres de fichiers récents existants utilisent la couleur de lien de la palette | oui — c'est votre ini |

### Suppression des pubs FreeBuff

FreeBuff (l'app de bureau de l'assistant IA) embarque son propre réseau publicitaire : le bundle renderer (`resources/orchestrator/ui/assets/index-*.js`) rend une carte `sponsored-ad` et une bannière de fil, et l'orchestrateur (`resources/orchestrator/orchestrator.js`) expose des routes `/api/ad/slot|impression|click` qui appellent l'enchère publicitaire distante. Le shim ne fait que thème l'app ; il ne touche pas à ces fichiers.

`desktop/patch-freebuff-ads.js` coupe les pubs au niveau de l'octet :

- renderer : les points d'appel de la carte/bannière publicitaire deviennent `null`, et les méthodes client API `adSlot` / `adImpression` / `adClick` deviennent des no-ops — rien ne rend, et aucune requête `/api/ad/*` ne quitte jamais le renderer ;
- orchestrateur : les trois routes `/api/ad/*` cessent d'appeler le réseau publicitaire, et la requête pub en ligne d'un tour en direct (`maybeRequestAd`) est court-circuitée.

Le nom du fichier bundle embarque un hash de build, donc le patch découvre le bundle courant depuis `index.html` au lieu de livrer un payload verrouillé sur une version — c'est ce qui lui permet de survivre aux mises à jour. Les originaux sont sauvegardés dans `_orig-backup-<timestamp>/` dans le dossier d'installation ; `--revert` restaure le plus récent.

**Les versions futures sont traitées à deux couches indépendantes :**

1. **Patch d'octets avec replis regex.** Chaque cible a une chaîne exacte pour le build courant *et* un repli par expression régulière ancré sur ce qu'un minifieur ne peut pas renommer — les littéraux de chemin `/api/ad/*`, le discriminateur de protocole `case"ad":`, la classe `sponsored-ad`, et les emplacements `variant:"banner"` / `variant:"card"`. L'orchestrateur n'est pas minifié (noms lisibles comme `maybeRequestAd` et `app.ads.slotAd`), donc ses chaînes exactes tiennent longtemps ; le bundle renderer est minifié, donc ses replis regex prennent le relais dès que le prochain build renomme ses identifiants.
2. **Blocage au niveau shim (`targets/electron/shim.cjs`).** Totalement indépendant du bundle : tout fetch/XHR vers une URL `/api/ad/` est rejeté dans la page, et tout élément dont la classe contient `sponsored-ad` est masqué dès qu'il apparaît. Même un bundle flambant neuf que ce script n'a pas encore appris ne peut pas faire surface une pub.

```powershell
node .\desktop\patch-freebuff-ads.js           # patcher (sauvegarde d'abord)
node .\desktop\patch-freebuff-ads.js --sound "C:\...\my.mp3"   # patcher + son de fin personnalisé (wav/mp3/ogg/flac/m4a/aac)
node .\desktop\patch-freebuff-ads.js --scan    # quels marqueurs de pub CE build porte-t-il ?
node .\desktop\patch-freebuff-ads.js --verify
node .\desktop\patch-freebuff-ads.js --revert
```

Il s'exécute automatiquement dans le cadre de `install.ps1 -Target freebuff`, et doit être relancé après chaque mise à jour de FreeBuff (les mises à jour restaurent les fichiers d'origine). Si un build change de forme, le script nomme la cible qui ne correspond plus — lancez `--scan` pour voir ce que le nouveau build porte encore et rafraîchissez les chaînes là-bas.

**Son de fin FreeBuff.** Le renderer joue `chime-<hash>.mp3` quand une session se termine. Le patch le trouve de la même façon qu'il trouve le bundle (le nom embarque un hash de build), donc `--sound <file>` installe votre propre audio (wav/mp3/ogg/flac/m4a/aac) par-dessus et garde le fichier d'origine sous `chime-*.mp3.bak` ; `--revert` le restaure. `--verify` indique lequel est actif.

### Bouton son FreeBuff (GUI)

`WintageInstaller.ps1` a un petit bouton **FB SOUND** sous la pile APPLY / REVERT. Il ne stocke qu'une *préférence* ; `install.ps1 -Target freebuff` lit le même fichier et le transmet au patch en tant que `--sound`, donc les pubs et le son sont appliqués en un seul passage :

- **Clic gauche** — choisir un fichier audio (OpenFileDialog, wav/mp3/ogg/flac/m4a/aac) et l'entendre immédiatement : PCM WAV via System.Media.SoundPlayer, tout autre format via un MediaPlayer WPF (Media Foundation, asynchrone, donc la fenêtre ne gèle jamais). Le choix est mémorisé dans `%APPDATA%\Wintage\freebuff-sound.txt` (par machine, hors du checkout git, exactement comme les dossiers d'arbre-source mémorisés).
- **Clic droit** — remettre la préférence sur le chime d'origine de FreeBuff (arrête aussi tout aperçu encore en cours).
- **COPY** — copie l'audio choisi dans le dépôt lui-même (`sounds\freebuff.<ext>`, en gardant l'extension source) et repointe la préférence vers cette copie, donc le son survit à la suppression ou au déplacement du fichier d'origine. Activé seulement tant qu'un son personnalisé est défini ; re-copier écrase simplement la copie du dépôt. Le dossier `sounds/` est un contenu git-traçable normal, donc le committer fait survivre le son aux re-clones aussi.

Seuls les conteneurs audio reconnus sont prévisualisés — l'en-tête est reniflé d'abord, donc une sélection non-audio est annoncée au lieu de ne jouer silencieusement rien.

Le bouton affiche `ON` tant qu'un son personnalisé est défini ; le survol montre le chemin. Appliquez ensuite la cible `freebuff` (cochez FreeBuff + APPLY, ou lancez `install.ps1 -Target freebuff` depuis un terminal) pour que cela prenne effet.

### Terminaux

`terminal` écrit un schéma de couleurs `Wintage` dans chaque fichier de paramètres Windows Terminal stable, Preview ou non empaqueté détecté et le sélectionne via `profiles.defaults`, avec Consolas 12 compatible console et texte aliased. Le fichier d'origine est conservé octet pour octet à côté et `-Revert` le restaure.

`conhost` couvre le classique `cmd.exe`, Windows PowerShell, les profils de console Git CMD/Bash et les autres enfants `HKCU\Console` existants. Il écrit la table complète des 16 couleurs de la palette à la fois dans les défauts racine et dans chaque override existant, puis restaure seulement les valeurs qu'il a touchées. Il applique aussi Consolas là-bas, car la Verdana proportionnelle entre en collision avec la grille de cellules à largeur fixe utilisée par les deux hôtes de terminal.

### Navigateurs et Tampermonkey

`browsers` trouve les profils Chrome, Edge, Brave, Cent, Vivaldi et Opera depuis les emplacements installés et depuis la racine portable vers laquelle vous pointez (`-PortableRoot`, ou l'entrée `portable` mémorisée dans `paths.json`). Son statut montre à la fois le nombre de profils et combien contiennent Tampermonkey. Apply copie le thème chrome de navigateur choisi dans le dossier stable `%LOCALAPPDATA%\Wintage\browser-theme`, met ce chemin dans le presse-papiers, et ouvre chaque profil exact à `chrome://extensions` plus la page Install/Update de l'userscript Wintage. Les profils sans Tampermonkey reçoivent aussi sa page Chrome Web Store.

Chromium interdit délibérément l'installation silencieuse d'extensions hors-store sur une machine Windows non gérée. La première installation du thème navigateur exige donc une confirmation **Developer mode → Load unpacked** par profil. Choisissez le chemin copié ; ensuite, Wintage continue de remplacer le même dossier stable quand les palettes changent. Confirmez aussi **Install/Update** dans Tampermonkey. Aucun `Preferences` de navigateur, Secure-Preferences ou fichier LevelDB de Tampermonkey n'est modifié dans le dos du navigateur. Si Tampermonkey n'était pas présent, installez-le depuis l'onglet store ouvert et rafraîchissez l'onglet `wintage.user.js` déjà ouvert pour obtenir l'écran d'installation.

### Windows

`windows` installe et active immédiatement un `%LOCALAPPDATA%\Microsoft\Windows\Themes\Wintage-<hash>.theme` adressé par contenu. Il part du thème actif et ne remplace que les sections de couleurs, de curseurs et de style visuel documentées. Le fond d'écran, les sons et les icônes du bureau restent inchangés ; les curseurs passent intentionnellement au schéma `___CURRENT___` installé. Le premier thème actif est sauvegardé octet pour octet sous `Wintage.original.theme` ; les changements de palette gardent cette ligne de base, et `-Revert` la réactive. Les contrôles Windows modernes viennent toujours du style visuel Aero signé — Wintage change ses entrées de mode sombre, d'accent et de couleurs système classiques prises en charge plutôt que de remplacer les fichiers `.msstyles` protégés. Les légendes actives et inactives partagent la couleur de surface surélevée atténuée de la palette ; le surlignage brillant reste réservé aux bords du texte/sélection. L'accent précédent de légende inactive est photographié séparément et restauré exactement par `-Revert`. Le hash de contenu donne à Windows une nouvelle cible d'association de fichier quand la même palette est reconstruite, donc réappliquer une palette mise à jour n'est pas pris pour un no-op ; le fichier Wintage supplanté est supprimé après que Windows confirme le nouveau actif.

### OBS Studio

`obs` génère une variante OBS 30.2+ sur la base maintenue Yami Classic, l'installe dans `%APPDATA%\obs-studio\themes`, et écrit son ID de thème stable dans `user.ini`, donc la palette Wintage choisie est déjà sélectionnée au prochain lancement. Fermez OBS avant Apply ou Revert : OBS réécrit `user.ini` à la fermeture. Le premier apply sauvegarde à la fois la sélection précédente et tout thème homonyme octet pour octet.

### Apps Electron

`resources/app.asar` est déplacé vers `resources/app/app.asar` (son frère `app.asar.unpacked` suit — ce jumelage passe par le nom de fichier, et les séparer casse chaque module natif), et un petit `shim.cjs` prend l'emplacement `resources/app` libéré. Le shim injecte la feuille de style puis charge l'archive d'origine. **Aucun octet d'application n'est réécrit**, seulement relocalisé ; `-Revert` le replace directement.

La feuille de style n'est pas écrite pour ces apps — elle est extraite de `wintage.user.js`, donc chaque correctif de biseau, scrollbar et échelle typographique fait pour le navigateur atterrit aussi ici, sans seconde copie qui pourrit.

Deux notes à connaître à l'avance :

- L'approche évidente — déposer `resources/app` à côté de l'archive et compter sur Electron pour la préférer — **ne fonctionne pas et échoue en silence**. Electron cherche `app.asar` d'abord. L'app démarre parfaitement et le thème ne tourne jamais.
- Le shim est `.cjs`, pas `.js`, exprès. Son `package.json` est copié de celui de l'app pour que l'app garde son nom et sa version (le nom décide où vit userData — un shim qui le renomme déplace l'app vers un profil vide). Si ce manifeste dit `"type": "module"`, un shim `.js` meurt sur son premier `require`.

### L'app de bureau de Claude : sur place, et le cadre dans lequel elle dessine réellement

Claude ne peut pas utiliser la relocalisation ci-dessus, car `OnlyLoadAppFromAsar` est fusionné : Electron charge `resources/app.asar` et rien d'autre, donc un shim dans `resources/app` ne peut jamais s'exécuter. Elle est patchée **sur place** à la place : l'archive est sauvegardée, son `main` de `package.json` est réécrit en `"../wintage-shim.cjs"` (rembourré à la même longueur d'octets, pour que chaque offset de l'archive reste valide), et le hash d'intégrité par fichier est mis à jour en conséquence. `-Revert` restaure la sauvegarde.

L'installeur lit les fuses **avant de déplacer quoi que ce soit** et refuse avec une raison quand elles bloquent — `EnableEmbeddedAsarIntegrityValidation` ferait échouer la réécriture ci-dessus au lancement plutôt qu'à l'installation. Vérifiez n'importe quelle app vous-même :

```powershell
node ..\tools\electron-fuses.js "<path to the app's exe>"
```

La seconde moitié était un problème bien plus silencieux. Le `BrowserWindow` de Claude rend une coquille mince et **toute l'application visible est une `WebContentsView`** attachée à lui. Le shim accrochait `browser-window-created`, donc il injectait la feuille de style dans la coquille, rapportait un succès à `wintage-status.txt`, et ne changeait rien que vous puissiez voir. Il accroche `web-contents-created` maintenant, ce qui couvre le contenu de fenêtre, les `WebContentsView`, les `BrowserView`, les invités `<webview>` et les popups.

### Obsidian

Un thème communautaire est écrit dans `.obsidian/themes/` de chaque vault — les seize palettes d'un coup, exactement comme la cible VS Code, donc vous basculez entre elles dans **Settings → Appearance** sans rien relancer. Le modèle a été dérivé du thème fait main `VintageWin95` déjà présent dans le vault, chaque couleur remplacée par le token auquel elle correspondait. `-Palette <slug>` définit laquelle est active à l'installation ; `appearance.json` est sauvegardé d'abord, et `-Revert` ne retire que les thèmes `Wintage *` et restaure votre choix précédent — un thème fait main dans le même vault n'est jamais touché.


### MPC-HC (K-Lite)

Win32 natif, pas de feuille de style ni de point d'injection, et les couleurs de son thème sombre sont compilées dans le programme — aucune valeur de registre ne les expose. Donc cette cible **ne peut pas porter de palette**. Ce qu'elle fait : active le thème sombre et applique les règles de typographie de UI.md à l'OSD, la seule surface que MPC-HC laisse contrôler à l'utilisateur. Les paramètres précédents sont exportés d'abord vers `desktop/backup/mpc-hc-settings.reg`.

Fermez MPC-HC avant d'appliquer : il réécrit ses paramètres à la fermeture.

## Reconstruction

Tout ce qui est sous `desktop/out/` est généré à partir de `themes/*.json`. Ce n'est pas suivi dans git (T-160), donc un clone frais doit construire une fois avant d'installer :

```powershell
node ..\tools\build-desktop.js          # reconstruire toutes les cibles
node ..\tools\build-desktop.js --check  # exit 1 si quoi que ce soit est obsolète
```

`release.ps1` exécute le build et chaque gate, donc une release ne peut pas livrer une sortie qui a dérivé des palettes.

<!-- T-311 target/section coverage supplement -->
## Couverture des cibles et des sections (T-311)

Cette section reprend la couverture Process Explorer, Notepad++, Cinema 4D et les
polices de terminal du README anglais actuel, pour que cette version linguistique ne
vieillisse pas en silence. Les littéraux de code (ids de cible, chemins de registre,
noms de fichiers) ne sont pas traduits par conception ; le texte qui les entoure est
désormais rédigé dans cette langue.

### Ce que chaque cible peut réellement être thémée (cibles ajoutées)

| target | mécanisme | survit à une mise à jour d'app |
|---|---|---|
| `notepadplusplus` | XML de thème + alias dans le dossier `themes` de Notepad++ de l'utilisateur | oui — il vit dans votre profil |
| `cinema4d` | jeu de couleurs déposé dans le dossier `schemes` de Cinema 4D de l'utilisateur | oui — il vit dans votre profil |
| `processexplorer` | `HKCU\Software\Sysinternals\Process Explorer` : couleurs de surlignage de ligne et fonds de graphique, voir ci-dessous | non — Process Explorer réécrit ses paramètres à la fermeture ; fermez-le et relancez |

### Process Explorer (Sysinternals)

Process Explorer garde ses couleurs dans
`HKCU\Software\Sysinternals\Process Explorer` et réécrit cette clé quand il se ferme,
donc la cible **refuse tant que `procexp`, `procexp64` ou `procexp64a` est en cours
d'exécution** — fermez-le et relancez. Elle thème les catégories de couleur
configurables :

- **accessible** : les couleurs de surlignage de ligne du processus (`ColorOwn`,
  `ColorServices`, `ColorRelocatedDlls`, `ColorImmersive`, `ColorPacked`,
  `ColorJobs`, `ColorNet`, `ColorProtected`, `ColorNewProc`, `ColorDelProc`,
  `ColorSuspend`) dans leur variante claire et dans leur variante `*Dark`, plus les
  fonds de graphique (`ColorGraphBk`, `ColorGraphBkDark`) — 24 valeurs au total.
  Chaque variante est mélangée vers le pôle correspondant de la palette active (sa
  nuance la plus claire pour le remplissage clair, sa nuance la plus sombre pour
  `*Dark`), afin que les remplissages de ligne restent dans la tonalité propre à la
  palette au lieu de virer au pastel presque blanc ;
- **non accessible** : la barre de titre, la barre de menus, la barre d'outils, le
  fond de la vue en liste et les couleurs de texte, ainsi que les couleurs des
  lignes du graphique — tout cela est compilé dans `procexp.exe` et n'est exposé par
  aucune valeur de paramètre. La cible thème les surlignages de ligne et le fond de
  graphique qu'elle possède réellement, et ne prétend rien de plus.

Chaque valeur qu'Apply peut modifier est capturée avant modification (récupération
au premier contact sous `%APPDATA%\Wintage\recovery\processexplorer\`) et
`-Revert` la restaure à l'identique, y compris le fait que la valeur était absente et
que le marqueur était présent mais vide. Un dossier portable hors des répertoires
Sysinternals habituels est mémorisé via la clé canonique `processexplorer` de
`paths.json` (argument de CLI `-ProcessExplorerPath` ; la GUI peut aussi le choisir).

### Polices de terminal (`fonts/terminal/`)

Les deux cibles de terminal lisent UNE seule préférence typographique canonique dans
`%APPDATA%\Wintage\terminal-font.json` (`schema`, `fontSlug`, `family`, `size`,
`renderingMode`). Si le fichier est absent, les cibles gardent la valeur par défaut
livrée (Terminus (TTF) pour Windows, 12 pt, aliased), si bien que les machines
existantes restent inchangées. Une préférence mal formée échoue en toute sécurité :
rien n'est écrasé et la cible refuse.

`fonts/terminal/catalog.json` est le catalogue unique des polices : 20 familles
monospace open source livrées, plus les deux polices système que Wintage nomme sans
jamais les livrer (Terminus (TTF) pour Windows, Consolas). Chaque entrée livrée porte
sa source amont, sa révision épinglée, son id de licence, son fichier de licence et
son SHA-256. Les fichiers exacts sont vendorisés sous `fonts/terminal/files/` avec
leurs textes de licence sous `licenses/` ; Wintage à l'exécution fonctionne
intégralement hors ligne et ne télécharge jamais une police.

`tools/sync-terminal-fonts.ps1` est le téléchargeur réservé à la maintenance. Il lit
`fonts/terminal/sources.json` (un artefact immuable par famille), vérifie chaque
SHA-256 et refuse toute divergence. `-VerifyOnly` (par défaut) contrôle l'arborescence
sur disque sans réseau ; `-Fetch -Write` la re-vendorise. Les octets de police
téléchargés sont traités comme des ressources binaires non fiables — ils sont
hachés et écrits, jamais exécutés. Un remplacement est consigné :
**Fantasque Sans Mono** remplace Liberation Mono, qui ne publie aucune version
binaire épinglée (un `.sfd` source seulement).

L'installeur **parcourt les polices, il ne les installe pas.** L'onglet
TERMINAL FONTS charge une police livrée dans un `PrivateFontCollection` local au
processus pour un aperçu en direct, ce qui représente **zéro** enregistrement de
police système.
Choisir une police, une taille (7–24 pt) ou un mode de rendu
(aliased/grayscale/cleartype) ne met à jour que l'aperçu et la préférence. Installer
une police est une action explicite **INSTALL SELECTED** qui ouvre l'installeur de
polices de Windows lui-même ; après la confirmation de Windows, l'utilisateur
redétecte avec Refresh. Les changements réels de terminal n'ont lieu que sur un
**APPLY TERMINAL / APPLY CONHOST / APPLY BOTH** explicite.

Windows Terminal est appliqué à la famille installée sélectionnée à la taille
sélectionnée, et le mode de rendu correspond à
`profiles.defaults.antialiasingMode`. Le conhost classique est plus strict : il rend
sur une grille de cellules fixe, donc une police sélectionnée est refusée avant
toute modification du registre sauf si Windows la résout (la police par défaut et le
repli sur Consolas sont tacitement acceptés). Health et Reapply valident la police,
la taille et l'anticrénelage configurés par rapport à la préférence, si bien que
modifier la préférence après un Apply est signalé comme une dérive et non comme
« sain ». Le cycle de vie des couleurs de terminal reste intact : Revert restaure
exactement les valeurs que Wintage possédait auparavant et ne retire jamais une
police de la machine.
<!-- source-digest: desktop/README.md sha256:1b166ae6a7cf8a5c -->
