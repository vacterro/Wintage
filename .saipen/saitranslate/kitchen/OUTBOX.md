# OUTBOX

## SAIT-002: Wintage full translation bundle — 29 languages × README/desktop/browser-theme/locales

- **status:** ready
- **summary:** Complete 29-language translation bundle across every real surface —
  README, desktop README, browser-theme README, and UI locale JSONs (49 keys each).
  Supersedes the Core-share-only SAIT-001 draft.
- **critical:** false
- **producer:** saitranslate
- **source_head:** 3fd1ae60ef197ff028e1620574781ea4e7e355e7 (project HEAD)
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
