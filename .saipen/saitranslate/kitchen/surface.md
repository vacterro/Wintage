# Real translation surface - Wintage (HEAD 708bc21, v1.26.2)

Determined by reading the actual project, per TRANSLATE § 2. Nothing fabricated.

## (a) Documentation - real, user-facing

| surface | size | translate? |
|---|---|---|
| `README.md` | ~10 KB | YES - the root doc users read; primary surface; RU/ET/Дед siblings shipped and current |
| `desktop/README.md` | ~9 KB | YES - install/mechanism docs for the desktop subsystem; EN only, translation pending the dedicated instance (T-102) |
| `browser-theme/README.txt` | small | YES - install notes for the companion browser theme; EN only, pending T-102 |
| `CHANGELOG.md` | small | NO - release ledger, stays English by convention |
| `LICENSE` | - | NO - legal text, never translated |

Hand-maintained per-language siblings exist at repo root: `README.ru.md`,
`README.et.md`, `README.ded.md` (Core share, EN/RU/ET/Дед). These ARE the root
README mirrors for this repo (the switcher bar links them); they must stay in
exact sync with `README.md` and with the kitchen payloads below.

## (b) Real in-app UI strings

- `desktop/WintageInstaller.ps1` - WinForms GUI: labels wired to `T()` (T-144).
- `desktop/install.ps1` - console status/progress messages wired to `T()`
  (T-150).
- `wintage.user.js` - Tampermonkey menu entries (theme labels + support link).

The i18n loader shipped (T-103): `desktop/locales/{en,ru,et,ded}.json`, 49 keys
each, zero gaps (T-152 resolved), auto-detects system language with English
fallback. Core share of the UI surface is complete; the 29 remaining languages
are the dedicated instance's job (T-102).
