# Wintage for desktop applications

The userscript themes the web. This themes the programs around it, from the same
palettes, so the browser and the apps stop disagreeing about what dark golden means.

There is one rule behind every decision here: **applications update themselves, and
an update must not quietly break anything.** Where a target has a place in your own
profile, the theme goes there and survives updates. Where it does not, the installer
is written to be re-run — and says so, rather than pretending it persisted.

## The GUI

Double-click **`Wintage Installer.vbs`** in the repo root to open it without a
console window, or run this directly for diagnostics:

```powershell
powershell -File desktop\WintageInstaller.ps1
```

Theme list with colour chips, the targets found on this machine, a live Win95
preview, and all eighteen colour tokens as editable swatches. Editing any swatch
forks the palette into **Custom** rather than changing a shipped theme under you.
The panel on the right shows live WCAG contrast for the three tokens that carry
text — a palette that FAILs there is refused by the build gate anyway, so it is
better to see it before Apply than after.

Targets are split into two keyboard-reachable lists: **MY APPS** contains the
portable/source-tree CodeNomad, SAIPENVIEW, SmartVac and WildRift tools; **POPULAR
APPS** contains Windows, OBS, terminals, editors and the other installed software.
ALL/NONE and Apply/Revert operate across both lists without changing their grouping.

The window wears the palette it is about to install. That is the fastest preview
available, and it keeps the tool honest: a palette that makes this window
unreadable is visibly unreadable.

Apply shells out to `install.ps1`. There is exactly one code path that installs a
theme, so the GUI cannot drift away from the command line.

## The command line

```powershell
.\install.ps1                                  # what is here, what is themed, with which palette
.\install.ps1 -Target freebuff -Palette klite  # one app, one palette
.\install.ps1 -Target all -Palette goldendefault # everything
.\install.ps1 -Target all -WhatIf              # say what would change, touch nothing
.\install.ps1 -Target freebuff -Revert         # undo one
```

`-Palette` defaults to `goldendefault` (**Golden Default**). The GUI opens on the
same palette and checks every available target. Repainting an app that is already
themed works while it is running; a first install does not, because the archive is
in use.

## What each target can actually be themed

| target | mechanism | survives an app update |
|---|---|---|
| `windows` | user `.theme`: dark system/app mode, accent and classic colour roles | yes — installed in your local Windows Themes folder |
| `browsers` | detects installed + portable Chromium profiles, stages the selected chrome theme and opens browser-owned Tampermonkey/theme confirmation pages | yes after one **Load unpacked** per profile |
| `terminal` | Windows Terminal scheme + all-profile defaults, Verdana 12 aliased | yes — settings are in your profile |
| `conhost` | `HKCU\Console` defaults + every existing cmd/PowerShell profile | yes — exact touched-value snapshot |
| `obs` | OBS 30.2+ `.ovt` variant + active `user.ini` theme ID | yes — it lives in your profile |
| `antigravity`, `vscode` | colour-theme extension in `~/.antigravity/extensions` / `~/.vscode/extensions` | **yes** — it lives in your profile |
| `freebuff`, `antigravity-app`, `codenomad` | Electron shim, see below | no — re-run the installer |
| `claude` | Electron shim, patched in place — see below | no — an update makes a new `app-<version>` folder |
| `mpchc` | registry, dark theme + OSD typography only | no — MPC-HC rewrites its settings on exit |
| `obsidian` | community theme per vault, all palettes installed at once | **yes** — it lives in your vault |
| `saipenview` | rewrites its own `:root` token values in `style.css` | no — a source file; re-run after a pull |
| `discord` | CSS dropped into BetterDiscord's own theme folder | yes |
| `totalcmd`, `totalcmd2` | `wincmd.ini` `[Colors]` keys; existing recent-file filters use the palette link colour | yes — it is your ini |
| `smartvac`, `wildrift` | token table rewritten in the app's own source | no — a source file; re-run after a pull |

### Terminals

`terminal` writes a `Wintage` colour scheme into every detected stable, Preview,
or unpackaged Windows Terminal settings file and selects it through
`profiles.defaults`, together with Verdana 12 and aliased text. The original file
is kept byte-for-byte beside it and `-Revert` restores it.

`conhost` covers classic `cmd.exe`, Windows PowerShell, Git CMD/Bash console
profiles, and other existing `HKCU\Console` children. It writes the palette's full
16-colour table to both the root defaults and every existing override, then restores
only the values it touched. It applies Verdana there too, so both terminal hosts
follow the same Vintage typography.

### Browsers and Tampermonkey

`browsers` finds Chrome, Edge, Brave, Cent, Vivaldi and Opera profiles from
installed locations and the portable root (`V:\___VAC\__P` by default). Its status
shows both profile count and how many contain Tampermonkey. Apply copies the chosen
browser-chrome theme to the stable
`%LOCALAPPDATA%\Wintage\browser-theme` folder, puts that path on the clipboard,
and opens each exact profile at `chrome://extensions` plus the Wintage userscript
Install/Update page. Profiles without Tampermonkey also get its Chrome Web Store
page.

Chromium deliberately forbids silent off-store extension installation on an
unmanaged Windows machine. The first browser-theme install therefore needs one
**Developer mode → Load unpacked** confirmation per profile. Pick the copied path;
after that, Wintage keeps replacing the same stable folder when palettes change.
Confirm **Install/Update** in Tampermonkey as well. No browser `Preferences`, Secure
Preferences or Tampermonkey LevelDB file is edited behind the browser's back.
If Tampermonkey was not present, install it from the opened store tab and refresh
the already-open `wintage.user.js` tab to get the Install screen.

### Windows

`windows` installs and immediately activates a content-addressed
`%LOCALAPPDATA%\Microsoft\Windows\Themes\Wintage-<hash>.theme`.
It starts from the active theme and replaces only the documented colour, cursor and
visual-style sections. Wallpaper, sounds and desktop icons stay unchanged; cursors
intentionally switch to the installed `___CURRENT___` scheme. The first active theme
is saved byte-for-byte as `Wintage.original.theme`; palette changes keep that baseline,
and `-Revert` activates it again. Modern Windows controls still come
from the signed Aero visual style — Wintage changes its supported dark mode, accent,
and classic system-colour inputs rather than replacing protected `.msstyles` files.
Active and inactive captions share the palette's muted raised-surface colour; the
bright highlight stays reserved for text/selection edges. The previous inactive
caption accent is snapshotted separately and restored exactly by `-Revert`.
The content hash gives Windows a new file association target when the same palette
is rebuilt, so re-applying an updated palette is not mistaken for a no-op; the
superseded Wintage file is removed after Windows confirms the new one active.

### OBS Studio

`obs` generates an OBS 30.2+ variant over the maintained Yami Classic base,
installs it into `%APPDATA%\obs-studio\themes`, and writes its stable theme ID to
`user.ini`, so the chosen Wintage palette is already selected on the next launch.
Close OBS before Apply or Revert: OBS rewrites `user.ini` on exit. The first apply
backs up both the previous selection and any same-named theme byte-for-byte.

### Electron apps

`resources/app.asar` is moved to `resources/app/app.asar` (its `app.asar.unpacked`
sibling moves with it — that pairing is by filename, and separating it breaks every
native module), and a small `shim.cjs` takes the vacated `resources/app` slot. The
shim injects the stylesheet and then loads the original archive. **No application
byte is rewritten**, only relocated; `-Revert` moves it straight back.

The stylesheet is not written for these apps — it is extracted from
`wintage.user.js`, so every bevel, scrollbar and type-ladder fix made for the
browser lands here too, with no second copy to rot.

Two notes worth having in advance:

- The obvious approach — dropping `resources/app` next to the archive and relying
  on Electron preferring it — **does not work and fails silently**. Electron
  searches `app.asar` first. The app starts perfectly and the theme never runs.
- The shim is `.cjs`, not `.js`, on purpose. Its `package.json` is copied from the
  app's own so the app keeps its name and version (the name decides where userData
  lives — a shim that renames it moves the app to an empty profile). If that
  manifest says `"type": "module"`, a `.js` shim dies on its first `require`.

### Claude's desktop app: in-place, and the frame it actually draws in

Claude cannot use the relocation above, because `OnlyLoadAppFromAsar` is fused on —
Electron loads `resources/app.asar` and nothing else, so a shim in `resources/app`
can never run. It is patched **in place** instead: the archive is backed up, its
`package.json` `main` is rewritten to `"../wintage-shim.cjs"` (padded to the same
byte length, so every offset in the archive stays valid), and the per-file integrity
hash is updated to match. `-Revert` restores the backup.

The installer still reads the fuses **before it moves anything** and refuses with a
reason when they block it — `EnableEmbeddedAsarIntegrityValidation` would make the
rewrite above fail at launch rather than at install. Check any app yourself:

```powershell
node ..\tools\electron-fuses.js "<path to the app's exe>"
```

The second half of this was a much quieter problem. Claude's `BrowserWindow` renders
a thin shell and the **entire visible application is a `WebContentsView`** attached
to it. The shim used to hook `browser-window-created`, so it injected the stylesheet
into the shell, reported success to `wintage-status.txt`, and changed nothing you
could see. It hooks `web-contents-created` now, which covers window contents,
`WebContentsView`s, `BrowserView`s, `<webview>` guests and popups alike.

### Obsidian

A community theme is written into every vault's `.obsidian/themes/` — all sixteen
palettes at once, exactly like the VS Code target, so you switch between them in
**Settings → Appearance** without re-running anything. The template was derived from
the hand-made `VintageWin95` theme already in the vault, each colour replaced by the
token it equalled. `-Palette <slug>` sets which one is active on install;
`appearance.json` is backed up first, and `-Revert` removes only the `Wintage *`
themes and restores your previous choice — a hand-made theme in the same vault is
never touched.

### SAIPENVIEW

Its frontend already declares the Wintage token names in its own `:root`, so this
patch rewrites **only the token values** — never a selector, a font, a border width
or a padding. Nothing that affects the box model changes, so the text cannot shift.
That is deliberate: the earlier approach appended the whole browser stylesheet on
top, and `wintage.css` is written for arbitrary web pages — universal selectors
forcing the font, the size ladder, 2px borders and control heights. On an app that
already has its own layout, that moves everything.

Verified by masking every hex and diffing against the backup: structurally
identical, only colour literals differ. `--link` is reported as not declared there
(its markdown links read `--accentTeal`, which this does set) rather than injected —
adding a variable the app never reads would be dead weight.

### MPC-HC (K-Lite)

Native Win32, no stylesheet and no injection point, and its dark theme's colours are
compiled into the program — no registry value exposes them. So this target **cannot
carry a palette**. What it does: switches the dark theme on and applies the UI.md
typography rules to the OSD, which is the one surface MPC-HC lets a user control.
The previous settings are exported to `desktop/backup/mpc-hc-settings.reg` first.

Close MPC-HC before applying: it rewrites its settings on exit.

## Rebuilding

Everything under `desktop/out/` is generated from `themes/*.json`:

```powershell
node ..\tools\build-desktop.js          # rebuild all targets
node ..\tools\build-desktop.js --check  # exit 1 if anything is stale
```

`release.ps1` runs the build and every gate, so a release cannot ship output that
has drifted from the palettes.
