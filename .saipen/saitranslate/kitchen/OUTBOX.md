# OUTBOX

## SAIT-002: Wintage full translation bundle — 29 languages × README/desktop/browser-theme/locales

- **status:** reviewed
- **summary:** Complete 29-language translation bundle across every real surface —
  README, desktop README, browser-theme README, and UI locale JSONs (49 keys each).
  Supersedes the Core-share-only SAIT-001 draft. Collected at T-177 (eee), shipped 26e1d74.
- **critical:** false
- **producer:** saitranslate
- **source_head:** f79229d94b08214e267b8ab9c54b058d88228251 (project HEAD)
- **source_tree_fingerprint:** git-delta-v1:c66baf69a8306f3b95dfc7badb5f72b088f8de8408e933efadc4d149721a1195
- **role_revision:** sha256:f241e6b83c39e9b46bfa586638efb0374bbb39889646f723b9189bbb4912c0c5
- **coverage:**
  - docs — README.md: **29 languages** complete (ja uk de fr es it pt nl pl sv da fi no
    zh ko th vi ar he tr hi id el cs ro hu bg sk hr), each translated from the
    current English source, carrying the current source-digest. Plus the Core-share
    EN/RU/ET/Дед root copies already live in the repo (README.ru/et/ded.md
    byte-identical, switcher bar preserved).
  - docs — desktop/README.md: **29 languages** complete, each from the current
    English source, correct digest, targets table + commands preserved verbatim.
  - docs — browser-theme/README.txt: **29 languages** complete. Preamble reflects
    the T-171 correction (fixed legacy Dark Golden palette, independent of the
    userscript's switchable palettes), token-mapping table verbatim.
  - UI strings — desktop/locales/*.json: **all 33 locales** (en ru et ded + 29),
    49 keys each, zero gaps vs en.json, loadable by the i18n loader (T-103).
- **payload:**
  - kitchen/README.<lang>.md — 29 files (the 17 pre-existing updated to the T-167
    palette table + current digest; 12 newly translated: uk pt nl pl sv da fi no tr
    cs sk hr)
  - kitchen/desktop/README.<lang>.md — 29 files (17 pre-existing + 12 new)
  - kitchen/browser-theme/README.<lang>.txt — 29 files (17 pre-existing, preamble
    refreshed for T-171 + digest; 12 new)
  - kitchen/locales/<lang>.json — 12 new locale files (uk pt nl pl sv da fi no tr
    cs sk hr)
  - README.ru/et/ded.md at repo root already live (Core share, byte-identical to
    kitchen); locale ru/et/ded.json already live.
  (English sources = README.md / desktop/README.md / browser-theme/README.txt /
  en.json at source_head; no files to ship for EN.)
- **verified:**
  - Every one of the 29 languages has all four surfaces present (README, desktop,
    browser-theme, locales) — programmatic coverage check: zero missing.
  - README digests: all 29 carry sha256:ee7c6a2a1626faed (current README.md);
    desktop all carry sha256:1b166ae6a7cf8a5c; browser-theme all carry
    sha256:056bdd1c330ee8c2 — all computed from the current sources.
  - Locale JSONs: 12 new all parse (ConvertFrom-Json), 49 keys, exact key parity
    with en.json (0 missing, 0 extra), {0} placeholders and \r\n escapes preserved,
    command examples verbatim.
  - README translations: heading structure / code fences / hex tokens / commands
    preserved; T-167 palette table (real goldendefault hexes) in every existing
    translation, zero stale legacy hexes.
  - browser-theme translations: token-mapping table verbatim, zero leftover
    "Uses the same palette" wording (T-171 correction reflected everywhere).
- **instructions:** (1) `eee` collects: apply the 29 kitchen README.<lang>.md to
  repo-root README.<lang>.md, the 29 desktop kitchen files to desktop/README.<lang>.md,
  the 29 browser-theme kitchen files to browser-theme/README.<lang>.txt, and the 12
  new locale JSONs to desktop/locales/. (2) The repo-root README.ru/et/ded.md and
  locale ru/et/ded.json are already live — collection must not duplicate or drift
  them (verify byte-identity, they match kitchen). (3) After collect, the language
  switcher bar in each root README must stay intact (T-107). (4) English sources are
  not shipped — they live in the repo already.
- **details:**
  This is the T-102 completion: the dedicated saitranslate instance produced the
  full 29-language bundle. Prior SAIT-001 (Core share only, status draft) is
  superseded. All work under .saipen/saitranslate/kitchen/; the main repo tree was
  not touched by this preparation.

  UPDATE (ee, 08.08.26): dedicated-instance run at 576a03b. 12 missing languages
  translated on every surface (README/desktop/browser-theme/locales); 17 existing
  translations updated: README palette table to the T-167 correction + current
  digest, browser-theme preamble to the T-171 correction + current digest. Full
  29×4 coverage verified programmatically. Status ready.

## SAIT-003: Wintage full translation bundle — 32 languages × README/desktop/browser-theme/locales

- **status:** reviewed
- **summary:** Complete 32-language translation bundle across every real surface —
  README, desktop README, browser-theme README, UI locale JSONs. Supersedes
  SAIT-002 (added Core-share ru/et/ded to the desktop and browser-theme surfaces
  at T-179). Collected at sc stage 5 — repo mirrors kitchen byte-for-byte.
- **critical:** false
- **producer:** saitranslate
- **source_head:** 2483b4989f3da4b9f42d03b46cbb48ecff7c9340 (project HEAD)
- **source_tree_fingerprint:** git-delta-v1:c66baf69a8306f3b95dfc7badb5f72b088f8de8408e933efadc4d149721a1195
- **role_revision:** sha256:f241e6b83c39e9b46bfa586638efb0374bbb39889646f723b9189bbb4912c0c5
- **coverage:**
  - docs — README.md: **32 locales** (en source + ru et ded + 29 bundle), all
    carrying the current source-digest. EN/RU/ET/Дед live at repo root; 29 bundle
    translated from current source.
  - docs — desktop/README.md: **32 locales**, each with current digest, targets
    table + commands preserved verbatim. Core-share ru/et/ded added at T-179.
  - docs — browser-theme/README.txt: **32 locales**, T-171 fixed-legacy preamble
    everywhere, token-mapping table verbatim. Core-share ru/et/ded added at T-179.
  - UI strings — desktop/locales/*.json: **33 locales** (en ru et ded + 29),
    49 keys each, zero gaps vs en.json.
- **payload:** the full 32-language kitchen set (README.<lang>.md at root,
  desktop/README.<lang>.md, browser-theme/README.<lang>.txt, locale JSONs) —
  byte-identical to the live repo copies; collect is a no-op re-verify unless the
  repo drifted.
- **verified:** kitchen ↔ repo byte-identical for all ru/et/ded on all three
  surfaces (programmatic hash check, zero drift); 29×4 bundle coverage complete;
  locale JSONs parse with exact en.json key parity; all digests current
  (README ee7c6a2a, desktop 1b166ae6, browser-theme 056bdd1c).
- **instructions:** (1) `eee` collects — but the repo copies already match the
  kitchen byte-for-byte (T-177 shipped the 29, T-179 shipped ru/et/ded), so
  collect is a re-verify no-op. (2) If the repo ever drifts from kitchen, re-apply
  the corresponding files. (3) After collect, language switcher bars must stay
  intact.
- **details:**
  FORCE-FRESH at 2483b49 after T-178/T-179 (sc circuit stage 5). T-178 added
  digest markers to Core-share READMEs; T-179 translated ru/et/ded for the
  desktop and browser-theme surfaces and synced kitchen. Kitchen is the single
  source of truth; repo mirrors verified current. All work under
  .saipen/saitranslate/kitchen/.

