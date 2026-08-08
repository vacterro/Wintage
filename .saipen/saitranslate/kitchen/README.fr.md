# Wintage

**Thème vintage « Win95 Dark Golden » pour tout le web.** Un userscript Tampermonkey qui restyle chaque site en application Windows 95 brun-doré sombre : biseaux 3D nets au pixel, zéro angle arrondi, zéro animation, aucun flash au survol, Verdana partout.

[🤍 Soutenir le développeur](https://buymeacoffee.com/vacuum34)

[EN](README.md) | [RU](README.ru.md) | [ET](README.et.md) | [Дед](README.ded.md)

_Le web moderne optimise l'esthétique au détriment de l'utilisabilité. Les coins arrondis remplacent la hiérarchie visuelle, les animations remplacent le retour d'information, les ombres remplacent la structure, et le minimalisme retire souvent précisément les repères sur lesquels notre cerveau s'appuie pour comprendre une interface._

_Les utilisateurs ne devraient pas avoir à deviner si quelque chose est un bouton, une étiquette, une carte ou du simple texte. Wintage ramène un langage visuel explicite : boutons en relief, champs de saisie enfoncés, limites nettes, typographie cohérente, zéro distraction et changements d'état immédiats._

_Chaque élément communique sa fonction d'un coup d'œil, réduisant la charge cognitive et redonnant au web la sensation d'un instrument précis plutôt que d'une collection de bulles décoratives._

[Changelog](CHANGELOG.md)

## Installation

1. Installez [Tampermonkey](https://www.tampermonkey.net/) (Chrome, Edge, Firefox, Opera, Safari).
2. Cliquez sur **[Installer Wintage](https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js)** — Tampermonkey ouvre automatiquement sa page d'installation.
3. C'est fait. Chaque site que vous visitez tourne maintenant sous Windows 95, édition Dark Golden.

## Mise à jour

- **Automatique :** le script porte `@updateURL`/`@downloadURL` pointant vers ce dépôt, donc Tampermonkey récupère les nouvelles versions lors de ses vérifications régulières.
- **Actualisation manuelle :** Tampermonkey → **Utilities → Check for userscript updates**, ou cliquez simplement à nouveau sur le lien d'installation — il remplace l'ancienne version sur place, pas besoin de désinstaller.
- **Des lignes de thème manquantes signifient un script obsolète :** le menu est généré à partir du registre de thèmes embarqué et le test de release exige exactement une ligne de menu pour chaque palette embarquée. Si le menu est plus court que la liste de palettes ci-dessous, cliquez à nouveau sur **Install Wintage** et confirmez **Update** dans Tampermonkey.

## Seize palettes et un interrupteur

Wintage n'est plus une seule palette. Six sont la structure propre de UI.md, tournée vers une autre famille de teintes (Dark Golden, Claude Code, Antigravity, K-Lite, FreeBuff, CodeNomad) ; Custom se modifie et se sauvegarde depuis l'installeur desktop ; neuf sont importées de [FastPrompter](https://github.com/vacterro) (Default, Golden Vintage, Golden Default, Vintage Dark, Vintage Classic, Dark 2 OLED, Dracula, Nord, Solarized Dark). Chacune passe le WCAG AA sur les trois tokens qui portent du texte — le build gate refuse toute palette qui échoue.

Choisissez-en une dans le **menu Tampermonkey** sur n'importe quelle page ; le choix est stocké par utilisateur, pas par site, donc il vaut sur tous les domaines.

Les palettes vivent dans `themes/*.json`, hors du script, pour une raison : Tampermonkey re-télécharge `wintage.user.js` à chaque mise à jour, donc une palette éditée à la main s'évaporerait. Réappliquez-les sur un build neuf avec :

```powershell
.\install-themes.ps1 -Latest
```

## Au-delà du navigateur

Les mêmes palettes s'installent dans des applications de bureau — VS Code et Antigravity comme thèmes de couleurs, les apps Electron (Freebuff, l'app agent Antigravity) via un shim qui injecte exactement la feuille de style qu'utilise ce userscript. Il y a une petite GUI pour cela :

Double-cliquez sur **`Wintage Installer.vbs`** à la racine du dépôt. Elle ouvre la GUI sans fenêtre de console. L'ancien lanceur `.cmd` renvoie vers le même hôte caché ; `desktop\WintageInstaller.ps1` reste exécutable directement pour les diagnostics.

Ce que chaque cible peut et ne peut pas atteindre — y compris les deux apps soudées ou dont les couleurs sont compilées — est décrit dans **[desktop/README.md](desktop/README.md)**.

## Fonctionnalités

- **Palette Golden Default** — canvas brun-noir profond `#1A1810`, texte doré `#D4C89A`, reliefs dorés `#F0D060`. Uniquement des surfaces planes : ni dégradés, ni flou, ni effets de transparence.
- **Biseaux 3D classiques** — boutons en relief, champs enfoncés, boutons pressés qui s'enfoncent (avec le décalage authentique du libellé de 1px). Les barres de défilement sont de pleines 16px style Win95, pouce et boutons biseautés inclus.
- **Tueur de rayons** — `border-radius: 0` appliqué partout, y compris les variables CSS des frameworks (Bootstrap, Material, YouTube, Reddit).
- **Mouvement interdit** — toutes les transitions et animations sont réduites à zéro. Les changements d'état sont instantanés, comme dans une vraie interface de 1995.
- **Surbrillance au survol complètement désactivée** — aucune ligne qui flashe en blanc, aucun bloc de teinte grise :
  - les propriétés de remplissage sont chirurgicalement retirées de chaque règle `:hover` lisible (les propriétés fonctionnelles comme `display`/`visibility`/`opacity` sont conservées, donc les menus ouverts au survol fonctionnent toujours) ;
  - les feuilles de style cross-origin illisibles sont neutralisées par un repli de gel des transitions.
  Seuls les vrais contrôles (boutons, liens, champs) gardent une réponse biseautée immédiate et thémée.
- **Verdana forcé à 100 % partout** — champs et textareas compris, avec l'anticrénelage désactivé. Les polices d'icônes sont exclues pour que les glyphes ne deviennent pas des lettres. Si vous avez une police personnalisée installée sous le nom `Verdana_m1` (p. ex. un patch Verdana sans anticrénelage), elle est utilisée automatiquement ; sinon, Verdana standard.
- **Repainter adaptatif** — un balayeur JS léger convertit les surfaces claires « flash » et les gris non thémés du mode sombre en l'échelle brune vintage, et corrige les textes à faible contraste (sombre-sur-sombre) vers le doré, à des seuils conscients du WCAG. Les images, vidéos, canvas et lecteurs ne sont jamais touchés.
- **Percée du Shadow DOM** — thème aussi les web components (YouTube, Reddit et compagnie) via un hook `attachShadow`.
- **Les popups se tiennent bien** — menus, dialogues, infobulles et hovercards sont seulement recolorés ; le script n'impose jamais `opacity`/`z-index`/`visibility`, donc l'UI cachée du site reste cachée.
- **Garde de sécurité** — le script se désactive sur les pages OAuth, captcha, bancaires et de paiement pour que les parcours critiques ne soient jamais restylés.

## Palette

Le tableau ci-dessous montre 10 des 21 tokens de la palette Golden Default. Chaque palette livrée définit les 21 ; les 11 restants couvrent la structure des biseaux, le texte secondaire, les couleurs sémantiques (succès/avertissement/danger), la sélection et les spécificités par cible.

| Token | Hex | Utilisé pour |
|---|---|---|
| background | `#1A1810` | arrière-plan le plus externe |
| backgroundSoft | `#232018` | fond du body / du contenu |
| surface | `#332E22` | en-têtes, navigation, panneaux |
| surfaceRaised | `#3D372A` | boutons, popups, pouce de scrollbar |
| surfaceAlt | `#453D30` | survol de bouton |
| borderHighlight | `#F0D060` | bords 3D haut-gauche |
| borderDark | `#100E08` | bords 3D bas-droite |
| textPrimary | `#D4C89A` | texte doré principal |
| textMuted | `#6E674E` | placeholders, désactivé |
| link | `#F0D060` | liens, focus |

## Thème de navigateur assorti

La cible `browsers` de l'installeur desktop détecte les profils Chromium installés et portables, rapporte la couverture Tampermonkey, prépare le thème de navigateur sélectionné et ouvre les bonnes pages d'installation/mise à jour pour chaque profil. Chromium exige une confirmation **Developer mode → Load unpacked** par profil ; l'installeur copie le chemin stable du thème dans le presse-papiers. Les changements de palette ultérieurs réutilisent ce chemin.

## Comportements connus

- Les sites qui construisent les effets de survol en JavaScript (bascule de classes) plutôt qu'en CSS `:hover` peuvent encore afficher leur propre surbrillance.
- Sur les rares sites dont le CSS est cross-origin, cliquer sur un élément non focusable peut retarder son changement d'état visuel jusqu'à ce que la souris le quitte (le repli de gel de survol agit). Les vrais boutons et liens sont exemptés.
- Le script est statique par conception : pas de panneau d'options, pas de bascules par site. Forkez-le et modifiez les tokens en haut si vous voulez une autre saveur.

## Publier une nouvelle version (mainteneurs)

Modifiez `wintage.user.js`, puis exécutez :

```powershell
.\release.ps1 -Message "ce qui a changé"
```

Il incrémente le numéro de patch de `@version`, commit et pousse — les clients Tampermonkey récupèrent la mise à jour automatiquement. Passez `-Bump minor` ou `-Bump major` pour les releases plus importantes.

## Licence

[MIT](LICENSE)

<!-- source-digest: README.md sha256:ee7c6a2a1626faed -->
