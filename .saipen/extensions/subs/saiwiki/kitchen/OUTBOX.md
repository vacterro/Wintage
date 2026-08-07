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
