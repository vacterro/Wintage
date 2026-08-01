# Development & release

## Repository layout

- `wintage.user.js` — the userscript (Tampermonkey). Palettes are embedded by
  `tools/apply-themes.js` inside the `THEMES` registry.
- `themes/*.json` — the sixteen palette packs, the single source of truth for colour.
- `desktop/` — the desktop theme subsystem: `tools/build-desktop.js` fills `${token}`
  templates from the packs, `install.ps1` installs into the user profile,
  `WintageInstaller.ps1` is the WinForms GUI.
- `tools/` — generators and gates: `apply-themes.js`, `derive-palette.js`,
  `check-css.js`, `build-desktop.js`, `electron-fuses.js`, plus the test harnesses.
- `browser-theme/` — companion Chromium theme manifests generated from a role-based
  template.
- `tests/` — PowerShell test harness (`Run-Tests.ps1`).

## Releasing a new version

Edit `wintage.user.js`, then run:

```powershell
.\release.ps1 -Message "what changed"
```

It bumps the `@version` patch number, runs every gate (build `--check`, `check-css`,
theme packs, repainter polarity, theme switch), commits, and pushes — Tampermonkey
clients pick the update up automatically. Pass `-Bump minor` or `-Bump major` for
bigger releases.

## Gates

`release.ps1` refuses to ship unless the generated artifacts are current:

- `tools/build-desktop.js --check` — desktop outputs match the packs.
- `tools/check-css.js` — no stray/unclosed/nested comments, brace imbalance, or
  off-palette hex in the CSS bodies; also checks the per-theme WCAG AA floor and
  version stamp consistency.
- `tools/test-theme-packs.js`, `tools/test-repainter-polarity.js`,
  `tools/test-theme-switch.js` — the behavioural harnesses gated into release.

## Deliberate deviations from UI.md

Transition/animation stay at 0.001s (live evidence beats the literal law); no global
`margin: 0` or `box-sizing`; no `body { overflow-x: hidden }`; no class-name-based
status colours; semantic tokens are never used as text colour (1.8:1 fails AA).
Full reasoning lives in `.saipen/KNOWLEDGE/ADR-001..006` in the source repo.
