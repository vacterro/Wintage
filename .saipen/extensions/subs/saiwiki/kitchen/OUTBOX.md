# OUTBOX

## WIKI-002: Wintage wiki restamped to v1.26.2, forced-fresh (qq)

- **status:** reviewed
- **summary:** Complete 8-page maintained wiki regenerated and verified against current HEAD
  (5e79f51). Version stamps lifted 1.26.1 -> 1.26.2; `.\install.ps1` commands corrected to
  `.\desktop\install.ps1`; `desktop/out/` documented as gitignored/untracked. Instance
  migrated `.saipen/subs/saiwiki` -> `.saipen/extensions/subs/saiwiki` and modernized to
  schema_version 3 with role_revision.
- **main_project_refs:** [README.md, CHANGELOG.md, desktop/README.md, wintage.user.js, themes/*.json]
- **critical:** false
- **severity:** P3
- **producer:** saiwiki
- **source_head:** 5e79f513d6f5a6c01d2c3d0c2be68b700149baee
- **source_tree_fingerprint:** git-delta-v1:c66baf69a8306f3b95dfc7badb5f72b088f8de8408e933efadc4d149721a1195
- **role_revision:** sha256:54a42475a124ab0f27e83d600a284a9cc54d9668029c4828cfc48512b031df13
- **coverage:** every maintained wiki page (Home, Installation, Palettes, Desktop,
  Known-Behaviors, Development, _Sidebar, _Footer). Source invariants cross-checked:
  wintage.user.js @version 1.26.2, CHANGELOG.md [1.26.2], README.md (sixteen palettes,
  Golden Default label, 10-of-21 token table, bevel/Verdana/repainter claims),
  desktop/README.md (desktop/out/ untracked note, Rebuilding commands, GUI token count 21,
  MY APPS / POPULAR APPS split), 16-palette registry in wintage.user.js THEMES
  (golden/claudecode/antigravity/klite/freebuff/codenomad/fpdefault/goldenvintage/
  goldendefault/vintagedark/vintageclassic/oled/dracula/nord/solarized/custom).
- **payload:**
  - kitchen/wiki/Home.md (v1.26.2 stamp)
  - kitchen/wiki/Installation.md (`.\desktop\install.ps1` command block)
  - kitchen/wiki/Palettes.md
  - kitchen/wiki/Desktop.md (desktop/out/ untracked note in Rebuilding)
  - kitchen/wiki/Known-Behaviors.md
  - kitchen/wiki/Development.md (desktop/out/ gitignored note in layout)
  - kitchen/wiki/_Sidebar.md
  - kitchen/wiki/_Footer.md (v1.26.2 stamp)
- **verified:**
  - Version stamps: Home.md + _Footer.md now carry 1.26.2, matching wintage.user.js
    @version and CHANGELOG.md [1.26.2] (2026-08-07); grep over kitchen wiki shows no
    remaining 1.26.1.
  - Palette count 16 confirmed against the THEMES registry (regex count over the
    generated block) and README.md "Sixteen palettes".
  - Palette table values byte-match README.md's Golden Default 10-of-21 table.
  - install.ps1 command block corrected to `.\desktop\install.ps1`, matching
    desktop/README.md:42-46 verbatim; desktop/install.ps1 exists.
  - desktop/out/ untracked claim matches .gitignore entry + desktop/README.md:302-303.
  - Palette token label hexes (#1A0F05/#D4B87A/#C0A060) match README.md:69.
  - Freshness: source identity computed with tools/freshness.py after last source read;
    role_revision re-derived from project-local .saipen/extensions/subs/saiwiki.md
    charter and matches its declared YAML value.
  - Instance migrated via git mv; BOARD/LOG/STATE preserved byte-for-byte.
- **instructions:** (1) On collect, apply only the 8 kitchen/wiki/*.md pages to the
  repo wiki/ mirror with .md-adapted links (kitchen pages link as [Home](Home);
  the repo mirror carries [Home](Home.md) per T-105 precedent — adapt at injection,
  never edit kitchen). (2) No main-project source changes required — wiki mirror
  already sits at repo wiki/. (3) Use `qqq` to collect and ship (push to
  github.com/vacterro/Wintage.wiki master).
- **details:**
  Forced-fresh regeneration, not reuse: the prior v1.26.1 package was invalidated on
  evidence (source_head 8c2ed25 -> 5e79f51, version stamps 1.26.1 -> 1.26.2). v1.26.2
  (T-140/T-153/T-154/T-155/T-156/T-158/T-160/T-161/T-163/T-164/T-165) shipped installer
  housekeeping and portability fixes; the only wiki-visible surfaces were the version
  stamp, the installer command path (desktop/README was corrected at T-145 but the wiki
  mirror was not), and the desktop/out/ untracked note. All other pages verified still
  faithful to current docs. Nothing pushed; main project tree untouched (all changes
  under .saipen/).

## WIKI-003: Wintage wiki forced-fresh at 576a03b (qq)

- **status:** stale
- **summary:** Complete 8-page maintained wiki re-verified against current HEAD
  (576a03b). No page content changed since WIKI-002 (collected at T-166, shipped
  9fb22b9/1a54ffb): version stamps still 1.26.2, install commands still
  `.\desktop\install.ps1`, desktop/out/ still documented gitignored. The one
  source change since — T-167's palette-table correction (07bd410) — was already
  applied to the kitchen Palettes.md during that ticket and re-verified here.
  SUPERSEDED by WIKI-004 (source_head moved to 1dd24c6 at T-176).
- **main_project_refs:** [README.md, CHANGELOG.md, desktop/README.md, wintage.user.js, themes/*.json]
- **critical:** false
- **severity:** P3
- **producer:** saiwiki
- **source_head:** 576a03b329143064797881f8848fe19a8e1b31b5
- **source_tree_fingerprint:** git-delta-v1:c66baf69a8306f3b95dfc7badb5f72b088f8de8408e933efadc4d149721a1195
- **role_revision:** sha256:54a42475a124ab0f27e83d600a284a9cc54d9668029c4828cfc48512b031df13
- **coverage:** every maintained wiki page (Home, Installation, Palettes, Desktop,
  Known-Behaviors, Development, _Sidebar, _Footer). Source invariants cross-checked:
  wintage.user.js @version 1.26.2, CHANGELOG.md [1.26.2], README.md (sixteen palettes,
  Golden Default label, 10-of-21 token table), desktop/README.md (desktop/out/
  untracked note, Rebuilding commands), 16-palette THEMES registry in wintage.user.js.
- **payload:**
  - kitchen/wiki/Home.md (v1.26.2 stamp)
  - kitchen/wiki/Installation.md (`.\desktop\install.ps1` command block)
  - kitchen/wiki/Palettes.md (T-167 corrected goldendefault token table)
  - kitchen/wiki/Desktop.md (desktop/out/ untracked note in Rebuilding)
  - kitchen/wiki/Known-Behaviors.md
  - kitchen/wiki/Development.md (desktop/out/ gitignored note in layout)
  - kitchen/wiki/_Sidebar.md
  - kitchen/wiki/_Footer.md (v1.26.2 stamp)
- **verified:**
  - Version stamps: Home.md + _Footer.md carry 1.26.2, matching wintage.user.js
    @version and CHANGELOG.md [1.26.2]; grep over kitchen wiki shows no 1.26.1.
  - Palette count 16 confirmed against the THEMES registry and README.md "Sixteen
    palettes".
  - Palettes.md token table carries the corrected goldendefault values
    (#1A1810 background, #D4C89A textPrimary, #F0D060 borderHighlight), matching
    README.md's corrected 10-of-21 table; zero legacy hexes remain.
  - install.ps1 command block still `.\desktop\install.ps1`, matching
    desktop/README.md verbatim.
  - desktop/out/ untracked claim matches .gitignore + desktop/README.md.
  - tools/check-wiki-mirror.js PASSes (repo wiki/ mirror == kitchen, .md links only).
  - Freshness: source identity computed with tools/freshness.py after last source
    read (576a03b / c66baf69); role_revision re-derived from project-local
    .saipen/extensions/subs/saiwiki.md charter, matches declared YAML value.
- **instructions:** (1) On collect, apply only the 8 kitchen/wiki/*.md pages to the
  repo wiki/ mirror with .md-adapted links (kitchen pages link as [Home](Home); the
  repo mirror carries [Home](Home.md) per T-105 precedent — adapt at injection, never
  edit kitchen). (2) The repo mirror is already current — check-wiki-mirror.js PASSes
  at HEAD, so collect is a no-op re-verify unless the mirror drifted. (3) Use `qqq` to
  collect and ship (push to github.com/vacterro/Wintage.wiki master).
- **details:**
  Forced-fresh, not reuse: WIKI-002 is `reviewed` history; this package re-verifies
  the same 8 pages against 576a03b. Since WIKI-002 (5e79f51), the tree moved through
  T-166 ship (9fb22b9), the dd plan (87acc71), and T-167..T-172 (07bd410..576a03b).
  The only wiki-visible source change was T-167's palette-table correction, which
  T-167 itself already propagated to the kitchen Palettes.md. All other pages verified
  still faithful. Nothing pushed; main project tree untouched (all changes under
  .saipen/).

## WIKI-004: Wintage wiki forced-fresh at 1dd24c6 (qq)

- **status:** ready
- **summary:** Complete 8-page maintained wiki re-verified against current HEAD
  (1dd24c6). No page content changed since WIKI-003 (which went stale when T-176
  shipped): version stamps still 1.26.2, install commands still
  `.\desktop\install.ps1`, desktop/out/ still documented gitignored. T-176 added
  the BetterDiscord target (desktop/targets/betterdiscord/, generated
  out/betterdiscord/) but no wiki page describes desktop targets in enough detail
  to need an update; the 16-palette count and token table are unchanged.
- **main_project_refs:** [README.md, CHANGELOG.md, desktop/README.md, wintage.user.js, themes/*.json]
- **critical:** false
- **severity:** P3
- **producer:** saiwiki
- **source_head:** 3fd1ae60ef197ff028e1620574781ea4e7e355e7
- **source_tree_fingerprint:** git-delta-v1:c66baf69a8306f3b95dfc7badb5f72b088f8de8408e933efadc4d149721a1195
- **role_revision:** sha256:54a42475a124ab0f27e83d600a284a9cc54d9668029c4828cfc48512b031df13
- **coverage:** every maintained wiki page (Home, Installation, Palettes, Desktop,
  Known-Behaviors, Development, _Sidebar, _Footer). Source invariants cross-checked:
  wintage.user.js @version 1.26.2, CHANGELOG.md [1.26.2], README.md (sixteen palettes,
  Golden Default label, 10-of-21 token table), desktop/README.md (desktop/out/
  untracked note, Rebuilding commands), 16-palette THEMES registry in wintage.user.js,
  build-desktop.js target list (now includes betterdiscord).
- **payload:**
  - kitchen/wiki/Home.md (v1.26.2 stamp)
  - kitchen/wiki/Installation.md (`.\desktop\install.ps1` command block)
  - kitchen/wiki/Palettes.md (T-167 corrected goldendefault token table)
  - kitchen/wiki/Desktop.md (desktop/out/ untracked note in Rebuilding)
  - kitchen/wiki/Known-Behaviors.md
  - kitchen/wiki/Development.md (desktop/out/ gitignored note in layout)
  - kitchen/wiki/_Sidebar.md
  - kitchen/wiki/_Footer.md (v1.26.2 stamp)
- **verified:**
  - Version stamps: Home.md + _Footer.md carry 1.26.2, matching wintage.user.js
    @version and CHANGELOG.md [1.26.2]; grep over kitchen wiki shows no 1.26.1.
  - Palette count 16 confirmed against the THEMES registry and README.md "Sixteen
    palettes" (T-176 added a target, not a palette).
  - Palettes.md token table carries the corrected goldendefault values
    (#1A1810 background, #D4C89A textPrimary, #F0D060 borderHighlight), matching
    README.md's corrected 10-of-21 table; zero legacy hexes remain.
  - install.ps1 command block still `.\desktop\install.ps1`, matching
    desktop/README.md verbatim.
  - desktop/out/ untracked claim matches .gitignore + desktop/README.md.
  - tools/check-wiki-mirror.js PASSes (repo wiki/ mirror == kitchen, .md links only).
  - Freshness: source identity computed with tools/freshness.py after last source
    read (1dd24c6 / c66baf69); role_revision re-derived from project-local
    .saipen/extensions/subs/saiwiki.md charter, matches declared YAML value.
- **instructions:** (1) On collect, apply only the 8 kitchen/wiki/*.md pages to the
  repo wiki/ mirror with .md-adapted links (kitchen pages link as [Home](Home); the
  repo mirror carries [Home](Home.md) per T-105 precedent — adapt at injection, never
  edit kitchen). (2) The repo mirror is already current — check-wiki-mirror.js PASSes
  at HEAD, so collect is a no-op re-verify unless the mirror drifted. (3) Use `qqq` to
  collect and ship (push to github.com/vacterro/Wintage.wiki master).
- **details:**
  Forced-fresh, not reuse: WIKI-003 went stale when T-176's ship changed source_head
  (576a03b -> 1dd24c6) while the tree fingerprint stayed c66baf69 (T-176 touched
  only new target + generated output, no wiki-visible source). Pages re-verified
  byte-identical to WIKI-003's payload. Nothing pushed; main project tree untouched
  (all changes under .saipen/).


