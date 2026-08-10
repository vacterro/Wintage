# OUTBOX

## SAIT-005: Wintage full translation bundle — fresh EE at 83d3d1e, payload already live (converge closure)

- **status:** ready
- **summary:** Converge stage-K fresh EE bound to the post-closure HEAD (83d3d1e).
  Full 32-language bundle re-verified against the current identity; the payload
  is already integrated (eee shipped it at fd53d63, nothing touched the
  translation surfaces since), so collect is a content-equivalent no-op: all
  repo surfaces are byte-identical to the kitchen. Freshness identity:
  source_head 83d3d1e, fingerprint c66baf69 (clean delta, .saipen excluded),
  role_revision f241e6b8 (unchanged charter).
- **critical:** false
- **severity:** P3
- **producer:** saitranslate
- **source_head:** 83d3d1e635efa28091c6f05577753f219bf7643d (project HEAD)
- **source_tree_fingerprint:** git-delta-v1:c66baf69a8306f3b95dfc7badb5f72b088f8de8408e933efadc4d149721a1195
- **role_revision:** sha256:f241e6b83c39e9b46bfa586638efb0374bbb39889646f723b9189bbb4912c0c5
- **coverage:**
  - docs — README.md: **32 locales** (en source + ru et ded + 29 bundle), all 32
    kitchen README.<lang>.md carry the current digest 886c5e27060e7b30 and the
    post-T-184 release section (CHANGELOG prerequisite named, zero "Edit
    wintage.user.js" hits, switcher bar verbatim).
  - docs — desktop/README.md: **32 locales**, digest 1b166ae6a7cf8a5c current,
    targets table + commands preserved.
  - docs — browser-theme/README.txt: **32 locales**, digest 056bdd1c330ee8c2
    current, T-171 fixed-legacy preamble everywhere.
  - UI strings — desktop/locales/*.json: **33 locales** (en ru et ded + 29),
    49 keys each, exact parity vs en.json, all parse.
- **payload:** the full 32-language kitchen set (README.<lang>.md at kitchen
  root, desktop/README.<lang>.md, browser-theme/README.<lang>.txt, 29 locale
  JSONs) — already live in the repo byte-identical (eee applied at fd53d63;
  desktop/browser/locales were already current even before). Collect = verify
  only; no file needs copying.
- **verified:**
  - Freshness identity recomputed with tools/freshness.py at 83d3d1e:
    source_head 83d3d1e635efa28091c6f05577753f219bf7643d, fingerprint
    c66baf69 (clean delta, .saipen excluded), role_revision f241e6b8 matches
    the charter's declared YAML value.
  - All 32 kitchen READMEs: current digest 886c5e27060e7b30 (programmatic),
    zero stale release-section hits, switcher bar verbatim in all.
  - All 32 desktop kitchen files carry 1b166ae6a7cf8a5c; all 32 browser-theme
    kitchen files carry 056bdd1c330ee8c2 (programmatic digest match).
  - All 29 locale JSONs parse (json.load) and have exactly 49 keys; key set
    identical to desktop/locales/en.json (0 missing, 0 extra).
  - Byte-identity kitchen vs repo re-confirmed across all three md surfaces
    (root README.<lang>.md 32/32, desktop 32/32, browser-theme 32/32) — zero
    diffs; the eee collect already applied everything.
  - TRANSLATION_CONTRACT.md digest constants current (886c5e27060e7b30 /
    1b166ae6a7cf8a5c / 056bdd1c330ee8c2).
- **instructions:** (1) This is a closure-bar package (CONVERGE.md stage K): it
  exists so `--gate converge` sees EE fresh+ready at the final HEAD. (2)
  Collect via `eee` is optional — it verifies byte-identity (already proven
  here) and marks reviewed; no repo mutation is required. (3) If any future
  source change lands before collect, re-run `ee` first.
- **details:**
  Fresh EE, not reuse: SAIT-004 was collected by `eee` at fd53d63 and the
  qqq wiki ship moved HEAD to 83d3d1e, so the closure bar (CONVERGE.md stage
  M: "bound to the current source identity") demanded a fresh ready package.
  The wiki-only ship touched no translation surface, so regeneration against
  all three freshness inputs is byte/content-equivalent — a legal no-op with
  the rerun verification recorded above. All work under
  .saipen/saitranslate/kitchen/; the main repo tree was not touched by this
  preparation.

## SAIT-004: Wintage full translation bundle — 32 languages × README/desktop/browser-theme/locales (FORCE-FRESH at 96a1a62)

- **status:** reviewed
- **collected_at:** 2026-08-10T20:14:00Z (eee, T-185)
- **summary:** Complete 32-language translation bundle re-verified and re-bound to
  current HEAD 96a1a62 (post-T-184 README release-section rewrite). README
  digest refreshed ee7c6a2a -> 886c5e27060e7b30 across all 32 kitchen READMEs;
  desktop/browser-theme surfaces unchanged (digests 1b166ae6 / 056bdd1c
  already current); locale JSONs unchanged (49-key parity intact).
- **critical:** false
- **producer:** saitranslate
- **source_head:** 96a1a6243e1c63f12d575ffcea959961bdb68938 (project HEAD)
- **source_tree_fingerprint:** git-delta-v1:c66baf69a8306f3b95dfc7badb5f72b088f8de8408e933efadc4d149721a1195
- **role_revision:** sha256:f241e6b83c39e9b46bfa586638efb0374bbb39889646f723b9189bbb4912c0c5
- **coverage:**
  - docs — README.md: **32 locales** (en source + ru et ded + 29 bundle), all 32
    kitchen README.<lang>.md carry the current digest 886c5e27060e7b30 and the
    post-T-184 release section (CHANGELOG prerequisite named, zero "Edit
    wintage.user.js" hits).
  - docs — desktop/README.md: **32 locales**, digest 1b166ae6a7cf8a5c current,
    targets table + commands preserved.
  - docs — browser-theme/README.txt: **32 locales**, digest 056bdd1c330ee8c2
    current, T-171 fixed-legacy preamble everywhere.
  - UI strings — desktop/locales/*.json: **33 locales** (en ru et ded + 29),
    49 keys each, exact parity vs en.json, all parse.
- **payload:** the full 32-language kitchen set (README.<lang>.md at kitchen
  root, desktop/README.<lang>.md, browser-theme/README.<lang>.txt, 29 locale
  JSONs) — the only drift vs the live repo is the root README release section
  (repo root README.ru/et/ded + 29 bundle READMEs still carry digest ee7c6a2a
  and the old release section; desktop/browser ru/et/ded at repo root already
  match kitchen).
- **verified:**
  - Freshness identity computed with tools/freshness.py at 96a1a62:
    source_head 96a1a6243e1c63f12d575ffcea959961bdb68938, fingerprint
    c66baf69 (clean delta, .saipen excluded), role_revision f241e6b8 matches
    the charter's declared YAML value.
  - All 32 kitchen READMEs: current digest 886c5e27060e7b30 (programmatic),
    digest is the FINAL line, switcher bar verbatim in all, zero stale
    release-section hits, zero <img> leaks.
  - All 32 desktop kitchen files carry 1b166ae6a7cf8a5c; all 32 browser-theme
    kitchen files carry 056bdd1c330ee8c2 (programmatic digest match).
  - All 29 locale JSONs parse (json.load) and have exactly 49 keys; key set
    identical to desktop/locales/en.json (0 missing, 0 extra).
  - Root Core-share lag confirmed as expected: repo README.ru/ded still old
    digest (collect applies kitchen); desktop/browser ru at root == kitchen
    byte-identical.
  - TRANSLATION_CONTRACT.md digest constants refreshed to the current values
    (886c5e27060e7b30 / 1b166ae6a7cf8a5c / 056bdd1c330ee8c2) so a future
    batch worker stamps correct markers.
- **instructions:** (1) `eee` collects: apply the 32 kitchen README.<lang>.md
  to repo-root README.<lang>.md (all 32, ru/et/ded included — their repo-root
  copies still carry the old release section + digest ee7c6a2a), the 32
  desktop kitchen files to desktop/README.<lang>.md, the 32 browser-theme
  kitchen files to browser-theme/README.<lang>.txt (desktop/browser ru/et/ded
  already byte-identical — skip or re-verify), and the 29 locale JSONs to
  desktop/locales/ (already live — re-verify parity). (2) After collect, the
  language switcher bar in each root README must stay intact (T-107). (3)
  English sources are not shipped — they live in the repo already.
- **details:**
  FORCE-FRESH, not reuse: SAIT-003 (source_head 2483b49) went stale when T-184
  rewrote README.md's release section (CHANGELOG prerequisite, "Edit
  wintage.user.js" gone) and normalized CRLF->LF, moving the README digest
  ee7c6a2a -> 886c5e27060e7b30. The kitchen READMEs were regenerated against
  the new source in a prior ee pass (uncommitted working-tree diff), and this
  run re-verified the whole bundle programmatically, refreshed the contract
  digest constants, and re-bound the package to 96a1a62. All work under
  .saipen/saitranslate/kitchen/; the main repo tree was not touched by this
  preparation.

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

- **status:** stale
- **superseded_by:** SAIT-004 (source_head 2483b49 -> 96a1a62 at T-184; README digest moved ee7c6a2a -> 886c5e27060e7b30, release section rewritten)
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

