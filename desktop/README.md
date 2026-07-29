# Wintage for desktop applications

The userscript themes the web. This themes the programs around it, from the same
palettes, so the browser and the apps stop disagreeing about what dark golden means.

There is one rule behind every decision here: **applications update themselves, and
an update must not quietly break anything.** Where a target has a place in your own
profile, the theme goes there and survives updates. Where it does not, the installer
is written to be re-run — and says so, rather than pretending it persisted.

## The GUI

```powershell
powershell -File desktop\WintageInstaller.ps1
```

Theme list with colour chips, the targets found on this machine, a live Win95
preview, and all eighteen colour tokens as editable swatches. Editing any swatch
forks the palette into **Custom** rather than changing a shipped theme under you.
The panel on the right shows live WCAG contrast for the three tokens that carry
text — a palette that FAILs there is refused by the build gate anyway, so it is
better to see it before Apply than after.

The window wears the palette it is about to install. That is the fastest preview
available, and it keeps the tool honest: a palette that makes this window
unreadable is visibly unreadable.

Apply shells out to `install.ps1`. There is exactly one code path that installs a
theme, so the GUI cannot drift away from the command line.

## The command line

```powershell
.\install.ps1                                  # what is here, what is themed, with which palette
.\install.ps1 -Target freebuff -Palette klite  # one app, one palette
.\install.ps1 -Target all -Palette golden      # everything
.\install.ps1 -Target all -WhatIf              # say what would change, touch nothing
.\install.ps1 -Target freebuff -Revert         # undo one
```

`-Palette` defaults to `golden`. Repainting an app that is already themed works
while it is running; a first install does not, because the archive is in use.

## What each target can actually be themed

| target | mechanism | survives an app update |
|---|---|---|
| `antigravity`, `vscode` | colour-theme extension in `~/.antigravity/extensions` / `~/.vscode/extensions` | **yes** — it lives in your profile |
| `freebuff`, `antigravity-app`, `nomadcode` | Electron shim, see below | no — re-run the installer |
| `claude` | **not themeable**, see below | — |
| `mpchc` | registry, dark theme + OSD typography only | no — MPC-HC rewrites its settings on exit |

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

### Claude's desktop app: fused shut

Claude ships with two Electron fuses enabled:

- `OnlyLoadAppFromAsar` — Electron loads `resources/app.asar` and nothing else, so
  the shim can never run.
- `EnableEmbeddedAsarIntegrityValidation` — the archive is hash-checked against the
  binary, so repacking it instead is not a way around the first.

Both are deliberate code-integrity controls. Getting past them would mean defeating
a security check the vendor switched on on purpose, so the installer reads the fuses
**before it moves anything** and refuses with the reason. Check any app yourself:

```powershell
node ..\tools\electron-fuses.js "<path to the app's exe>"
```

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
