# Installation

## Browser (Tampermonkey)

1. Install [Tampermonkey](https://www.tampermonkey.net/) — Chrome, Edge, Firefox, Opera, Safari.
2. Click **[Install Wintage](https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js)** — Tampermonkey opens its install page automatically.
3. Done. Every site you visit is now running Windows 95, Dark Golden edition.

### Updating

- **Automatic:** the script carries `@updateURL`/`@downloadURL` pointing at the repo,
  so Tampermonkey picks up new versions on its regular update checks.
- **Manual refresh:** Tampermonkey → **Utilities → Check for userscript updates**, or
  click the install link again — it replaces the old version in place.
- **Missing theme rows means an old script:** the menu is generated from the embedded
  theme registry. If the menu is shorter than the palette list, click **Install Wintage**
  again and confirm **Update**.

### Choosing a palette

Pick one from the **Tampermonkey menu** on any page; the choice is stored per user,
not per site, so it holds across every domain.

## Desktop applications

Double-click **`Wintage Installer.vbs`** in the repo root — it opens the GUI without
a console window. The legacy `.cmd` launcher forwards to the same hidden host;
`desktop\WintageInstaller.ps1` can still be run directly for diagnostics.

Command line:

```powershell
.\install.ps1                                  # what is here, what is themed, with which palette
.\install.ps1 -Target freebuff -Palette klite  # one app, one palette
.\install.ps1 -Target all -Palette goldendefault # everything
.\install.ps1 -Target all -WhatIf              # say what would change, touch nothing
.\install.ps1 -Target freebuff -Revert         # undo one
```

See [Desktop](Desktop) for what each target can and cannot reach.
