# Desktop applications

The userscript themes the web. `desktop/` themes the programs around it, from the
same palettes, so the browser and the apps stop disagreeing about what dark golden
means.

One rule behind every decision: **applications update themselves, and an update must
not quietly break anything.** Where a target has a place in your own profile, the
theme goes there and survives updates. Where it does not, the installer is written to
be re-run — and says so, rather than pretending it persisted.

## The GUI

Double-click **`Wintage Installer.vbs`** in the repo root to open it without a
console window, or run directly for diagnostics:

```powershell
powershell -File desktop\WintageInstaller.ps1
```

Theme list with colour chips, the targets found on this machine, a live Win95
preview, and all twenty-one colour tokens as editable swatches. Editing any swatch
forks the palette into **Custom**. A live WCAG panel shows contrast for the three
text-bearing tokens before Apply.

Targets are split into two keyboard-reachable lists: **MY APPS** (portable/source-tree
CodeNomad, SAIPENVIEW, SmartVac, WildRift) and **POPULAR APPS** (Windows, OBS,
terminals, editors and other installed software). ALL/NONE and Apply/Revert operate
across both lists without changing their grouping.

## What each target can actually be themed

| target | mechanism | survives an app update |
|---|---|---|
| `windows` | user `.theme`: dark system/app mode, accent and classic colour roles | yes |
| `browsers` | detects Chromium profiles, stages the chrome theme, opens browser-owned confirmation pages | yes after one **Load unpacked** per profile |
| `terminal` | Windows Terminal scheme + all-profile defaults, Consolas 12 aliased | yes |
| `conhost` | `HKCU\Console` defaults + every existing cmd/PowerShell profile | yes |
| `obs` | OBS 30.2+ `.ovt` variant + active `user.ini` theme ID | yes |
| `antigravity`, `vscode` | colour-theme extension in the extensions folder | **yes** |
| `freebuff`, `antigravity-app`, `codenomad` | Electron shim (relocation) | no — re-run the installer |
| `claude` | Electron shim, patched in place | no — an update makes a new folder |
| `mpchc` | registry, dark theme + OSD typography only | no — MPC-HC rewrites settings on exit |
| `obsidian` | community theme per vault, all palettes installed at once | **yes** |
| `saipenview` | rewrites its own `:root` token values in `style.css` | no — a source file; re-run after a pull |
| `discord` | CSS dropped into BetterDiscord's own theme folder | yes |
| `totalcmd`, `totalcmd2` | `wincmd.ini` `[Colors]` keys | yes |
| `smartvac`, `wildrift` | token table rewritten in the app's own source | no — a source file; re-run after a pull |

## Electron apps

`resources/app.asar` is moved to `resources/app/app.asar` (its `app.asar.unpacked`
sibling moves with it — that pairing is by filename), and a small `shim.cjs` takes
the vacated `resources/app` slot. The shim injects the stylesheet and then loads the
original archive. **No application byte is rewritten**, only relocated; `-Revert`
moves it straight back.

The stylesheet is not written for these apps — it is extracted from
`wintage.user.js`, so every bevel, scrollbar and type-ladder fix made for the browser
lands here too.

### Claude's desktop app: in-place

Claude cannot use relocation, because `OnlyLoadAppFromAsar` is fused on. It is
patched **in place**: the archive is backed up, its `package.json` `main` is
rewritten to the shim (padded to the same byte length, so every offset stays valid),
and the per-file integrity hash is updated to match. `-Revert` restores the backup.

Claude's `BrowserWindow` renders a thin shell and the entire visible application is a
`WebContentsView` — the shim hooks `web-contents-created`, which covers window
contents, `WebContentsView`s, `BrowserView`s, `<webview>` guests and popups alike.

## Terminals

`terminal` writes a `Wintage` colour scheme into every detected Windows Terminal
settings file and selects it through `profiles.defaults`, with console-safe
Consolas 12. `conhost` covers classic `cmd.exe`, Windows PowerShell, Git CMD/Bash
profiles and other `HKCU\Console` children, writing the palette's full 16-colour
table and restoring only the values it touched. Proportional Verdana collides inside
the fixed-width cell grid, so both hosts use Consolas.

## Rebuilding

Everything under `desktop/out/` is generated from `themes/*.json`:

```powershell
node ..\tools\build-desktop.js          # rebuild all targets
node ..\tools\build-desktop.js --check  # exit 1 if anything is stale
```

`release.ps1` runs the build and every gate, so a release cannot ship output that has
drifted from the palettes.
