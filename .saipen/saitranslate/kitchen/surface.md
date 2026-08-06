# Real translation surface — Wintage (HEAD 3e1e77a, v1.26.0)

Determined by reading the actual project, per TRANSLATE § 2. Nothing fabricated.

## (a) Documentation — real, user-facing

| surface | size | translate? |
|---|---|---|
| `README.md` | ~10 KB | YES — the root doc users read; primary surface |
| `desktop/README.md` | ~9 KB | YES — install/mechanism docs for the desktop subsystem (gained FreeBuff ad-removal + sound sections at v1.26.0; EN only, translation pending the dedicated instance) |
| `browser-theme/README.txt` | small | YES — install notes for the companion browser theme |
| `CHANGELOG.md` | small | NO — release ledger, stays English by convention |
| `LICENSE` | — | NO — legal text, never translated |

No hand-maintained per-language siblings exist (`*_XX.md` — none found). No
root README mirrors (`README.ee.md` / `README.ded.md` / `README.ja.md` — none
exist, so the mirror-sync rule has nothing to sync yet; a future run that adds
them must keep the language switcher exact).

## (b) Real in-app UI strings

- `desktop/WintageInstaller.ps1` — WinForms GUI: real labels (`'Wintage Theme
  Installer'`, `'THEME'`, `'MY APPS'`, `'POPULAR APPS'`, `'ALL'`, `'NONE'`,
  `'PREVIEW'`, `'COLOURS (click a swatch...)'`, buttons, tooltips).
- `desktop/install.ps1` — console status/progress messages.
- `wintage.user.js` — Tampermonkey menu entries (theme labels + `'🤍 Support
  developer'`).

**BUT: there is no i18n/locale loader anywhere** — no `.resx`, no culture
plumbing, no string table the app reads. A JSON-bundle-per-locale would translate
strings nothing consumes. So NO fabricated UI bundle is built. The honest paths:
(1) leave UI English-only (default), (2) ticket an i18n loader as a real feature
first, then translate the real strings into it. Covered by T-103.

## Who does what (TRANSLATE hard split)

- Core (this run): **English** (source), **Russian**, **Estonian**, **Дед voice**.
- 29 other languages (Japanese, Ukrainian, German, French, Spanish, Italian,
  Portuguese, Dutch, Polish, Swedish, Danish, Finnish, Norwegian, Chinese, Korean,
  Thai, Vietnamese, Arabic, Hebrew, Turkish, Hindi, Indonesian, Greek, Czech,
  Romanian, Hungarian, Bulgarian, Slovak, Croatian) — **subSaipen work, ticketed
  (T-102), not grinded by Core.**
