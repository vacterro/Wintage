# OUTBOX

## WIKI-007: Wintage wiki fresh QQ at 8867967, v1.26.4 restamp (converge closure)

- **status:** ready
- **summary:** Converge stage-L fresh QQ bound to the current HEAD (8867967,
  v1.26.4 T-187 ship). The 8-page maintained wiki was version-restamped
  1.26.3 -> 1.26.4 (Home.md current-version line + _Footer.md) and re-verified
  against the new identity. The payload is NOT yet live in the repo mirror —
  collect via qqq applies it (repo wiki/ still carries 1.26.3 stamps until
  then). Freshness identity: source_head 8867967, fingerprint a7d2ffe1 (clean
  delta, .saipen excluded), role_revision 54a42475 (unchanged charter).
- **critical:** false
- **severity:** P3
- **producer:** saiwiki
- **source_head:** 88679679000435dedb61393f89ccac971e9e0072 (project HEAD)
- **source_tree_fingerprint:** git-delta-v1:a7d2ffe1d350186aa7c2577b767eb5af8e3625e4ce75c0e9ef500759e9bc959b
- **role_revision:** sha256:54a42475a124ab0f27e83d600a284a9cc54d9668029c4828cfc48512b031df13
- **coverage:** every maintained wiki page (Home, Installation, Palettes, Desktop,
  Known-Behaviors, Development, _Sidebar, _Footer). Source invariants cross-checked:
  wintage.user.js @version 1.26.4 + W95_VERSION, CHANGELOG.md [1.26.4] - 2026-08-11,
  README.md (post-T-184 release section, sixteen palettes), desktop/README.md,
  16-palette THEMES registry in wintage.user.js, release.ps1 gate list (incl.
  check-wiki-mirror).
- **payload:** the 8 kitchen/wiki/*.md pages (Home.md + _Footer.md restamped to
  1.26.4; all other pages unchanged from WIKI-006 and re-verified faithful).
  The repo wiki/ mirror still carries 1.26.3 stamps — collect applies the
  restamp; Wintage.wiki master currently at 9260021 (1.26.3).
- **verified:**
  - Freshness identity recomputed with tools/freshness.py at 8867967:
    source_head 88679679000435dedb61393f89ccac971e9e0072, fingerprint
    a7d2ffe1 (clean delta, .saipen excluded), role_revision 54a42475 matches
    the charter's declared YAML value.
  - Version stamps: Home.md + _Footer.md carry 1.26.4 (2026-08-11), zero 1.26.3
    remains in any page; matches wintage.user.js @version 1.26.4 and CHANGELOG
    [1.26.4] - 2026-08-11.
  - All other pages byte-identical to WIKI-006's payload (the T-187 audit touched
    no wiki-visible source: installer internals + tools only; README.md and
    desktop/README.md unchanged).
  - Development.md release section matches the post-T-184 README contract: zero
    "Edit wintage.user.js" hits across all pages; CHANGELOG head-entry
    prerequisite named; check-wiki-mirror listed in the Gates section and wired
    at release.ps1:107.
  - Palettes.md token-table hexes byte-match themes/goldendefault.json (10/10).
- **instructions:** (1) This is a closure-bar package (CONVERGE.md stage L): it
  exists so `--gate converge` sees QQ fresh+ready at the final HEAD. (2) Collect
  via `qqq` applies the 8 pages to the repo wiki/ mirror with .md-adapted links
  (kitchen pages link as [Home](Home); the mirror carries [Home](Home.md) per
  T-105 precedent — adapt at injection, never edit kitchen), re-syncs the mirror
  (check-wiki-mirror goes green again) and pushes Wintage.wiki master. (3) If
  any future source change lands before collect, re-run `qq` first.
- **details:**
  Fresh QQ, not reuse: WIKI-006 was bound to 83d3d1e; the T-187 audit ship
  moved HEAD to 8867967 (v1.26.4) and bumped the version stamps, so the closure
  bar (CONVERGE.md stage M: "bound to the current source identity") demanded a
  fresh ready package AND a real content change (the 1.26.4 restamp). All other
  pages re-verified byte-identical to WIKI-006. All work under
  .saipen/extensions/subs/saiwiki/kitchen/; the main repo tree and wiki remote
  were not touched by this preparation.

## WIKI-006: Wintage wiki fresh QQ at 83d3d1e, payload already live (converge closure)

- **status:** stale
- **superseded_by:** WIKI-007 (source_head 83d3d1e -> 8867967 at the T-187 v1.26.4 ship; version stamps lifted to 1.26.4)
- **summary:** Converge stage-L fresh QQ bound to the post-closure HEAD (83d3d1e).
  Complete 8-page maintained wiki re-verified against the current identity; the
  payload is already integrated (qqq shipped it at 83d3d1e: repo wiki/ mirror
  restamped to v1.26.3 with .md links + Wintage.wiki master 9260021), so
  collect is a content-equivalent no-op. Freshness identity: source_head
  83d3d1e, fingerprint c66baf69 (clean delta, .saipen excluded), role_revision
  54a42475 (unchanged charter).
- **critical:** false
- **severity:** P3
- **producer:** saiwiki
- **source_head:** 83d3d1e635efa28091c6f05577753f219bf7643d (project HEAD)
- **source_tree_fingerprint:** git-delta-v1:c66baf69a8306f3b95dfc7badb5f72b088f8de8408e933efadc4d149721a1195
- **role_revision:** sha256:54a42475a124ab0f27e83d600a284a9cc54d9668029c4828cfc48512b031df13
- **coverage:** every maintained wiki page (Home, Installation, Palettes, Desktop,
  Known-Behaviors, Development, _Sidebar, _Footer). Source invariants cross-checked:
  wintage.user.js @version 1.26.3 + W95_VERSION, CHANGELOG.md [1.26.3] - 2026-08-10,
  README.md (post-T-184 release section, sixteen palettes), desktop/README.md,
  16-palette THEMES registry in wintage.user.js, release.ps1 gate list (incl.
  check-wiki-mirror).
- **payload:** the 8 kitchen/wiki/*.md pages — already live: repo wiki/ mirror
  carries them with .md-adapted links (check-wiki-mirror PASS), Wintage.wiki
  master carries the bare-link forms (9260021). Collect = verify only.
- **verified:**
  - Freshness identity recomputed with tools/freshness.py at 83d3d1e:
    source_head 83d3d1e635efa28091c6f05577753f219bf7643d, fingerprint
    c66baf69 (clean delta, .saipen excluded), role_revision 54a42475 matches
    the charter's declared YAML value.
  - Version stamps: Home.md + _Footer.md carry 1.26.3, zero 1.26.2 remains in
    any page; matches wintage.user.js @version 1.26.3 and CHANGELOG [1.26.3].
  - Development.md release section matches the post-T-184 README contract: zero
    "Edit wintage.user.js" hits across all pages; CHANGELOG head-entry
    prerequisite named; check-wiki-mirror listed in the Gates section and wired
    at release.ps1:107.
  - Palettes.md token-table hexes byte-match themes/goldendefault.json (10/10).
  - Repo wiki/ mirror: every kitchen page has a mirror page; check-wiki-mirror
    PASSes (last run at qqq collect, 83d3d1e tree unchanged for wiki sources).
  - Wintage.wiki master already at 9260021 (qqq push) — remote collect done.
- **instructions:** (1) This is a closure-bar package (CONVERGE.md stage L): it
  exists so `--gate converge` sees QQ fresh+ready at the final HEAD. (2)
  Collect via `qqq` is optional — it re-verifies byte-identity (proven here)
  and marks reviewed; no repo or remote mutation is required. (3) If any
  future source change lands before collect, re-run `qq` first.
- **details:**
  Fresh QQ, not reuse: WIKI-005 was collected by `qqq` at 83d3d1e and its
  source_head was fd53d63, so the closure bar (CONVERGE.md stage M: "bound to
  the current source identity") demanded a fresh ready package at the final
  HEAD. The translation ship touched no wiki-relevant source; regeneration
  against all three freshness inputs is content-equivalent — a legal no-op
  with the rerun verification recorded above. All work under
  .saipen/extensions/subs/saiwiki/kitchen/; the main repo tree and wiki remote
  were not touched by this preparation.

## WIKI-005: Wintage wiki forced-fresh at 96a1a62, re-verified at fd53d63, v1.26.3 (qq)

- **status:** reviewed
- **collected_at:** 2026-08-10T20:21:00Z (qqq, T-186)
- **summary:** Complete 8-page maintained wiki regenerated and verified against current
  HEAD (96a1a62, re-verified at fd53d63 after the eee translation ship). Version stamps lifted 1.26.2 -> 1.26.3 (Home + _Footer) after v1.26.3
  shipped and T-182..T-184, T-173, T-183 landed on top. Development.md release section
  corrected to the post-T-184 README contract: `CHANGELOG.md` head-entry prerequisite
  named, the stale "Edit `wintage.user.js`, then run" instruction removed, and the
  `check-wiki-mirror` gate added to the Gates list (T-168). All other pages re-verified
  faithful to current docs.
- **main_project_refs:** [README.md, CHANGELOG.md, desktop/README.md, wintage.user.js, themes/*.json]
- **critical:** false
- **severity:** P3
- **producer:** saiwiki
- **source_head:** fd53d6350dbc61d062d4fc750e7b8d0b890fc255
- **source_tree_fingerprint:** git-delta-v1:c66baf69a8306f3b95dfc7badb5f72b088f8de8408e933efadc4d149721a1195
- **role_revision:** sha256:54a42475a124ab0f27e83d600a284a9cc54d9668029c4828cfc48512b031df13
- **coverage:** every maintained wiki page (Home, Installation, Palettes, Desktop,
  Known-Behaviors, Development, _Sidebar, _Footer). Source invariants cross-checked:
  wintage.user.js @version 1.26.3 + W95_VERSION, CHANGELOG.md [1.26.3] - 2026-08-10,
  README.md (sixteen palettes, Golden Default label, 10-of-21 token table, post-T-184
  release section), desktop/README.md (desktop/out/ untracked note, Rebuilding commands,
  GUI token count 21), 16-palette THEMES registry in wintage.user.js
  (golden/claudecode/antigravity/klite/freebuff/codenomad/fpdefault/goldenvintage/
  goldendefault/vintagedark/vintageclassic/oled/dracula/nord/solarized/custom),
  release.ps1 gate list (incl. check-wiki-mirror).
- **payload:**
  - kitchen/wiki/Home.md (v1.26.3 stamp)
  - kitchen/wiki/Installation.md (`.\desktop\install.ps1` command block)
  - kitchen/wiki/Palettes.md (T-167 corrected goldendefault token table)
  - kitchen/wiki/Desktop.md (desktop/out/ untracked note in Rebuilding)
  - kitchen/wiki/Known-Behaviors.md
  - kitchen/wiki/Development.md (post-T-184 release section, check-wiki-mirror gate)
  - kitchen/wiki/_Sidebar.md
  - kitchen/wiki/_Footer.md (v1.26.3 stamp)
- **verified:**
  - Version stamps: Home.md + _Footer.md now carry 1.26.3, matching wintage.user.js
    @version 1.26.3 and CHANGELOG.md [1.26.3] (2026-08-10); grep over kitchen wiki shows
    zero remaining 1.26.2.
  - Development.md release section now matches README.md's post-T-184 contract: rg over
    kitchen wiki returns zero "Edit wintage.user.js" hits; CHANGELOG head-entry
    prerequisite named (release.ps1:26-30 throws without it); @version + W95_VERSION both
    move together; -Bump minor/major stated.
  - check-wiki-mirror added to the Gates list; release.ps1:107 wires it as a gate.
  - Palette count 16 confirmed against the THEMES registry and README.md "Sixteen
    palettes" (T-176 added a target, not a palette).
  - Palettes.md token table hexes byte-match themes/goldendefault.json (10/10:
    #1A1810/#232018/#332E22/#3D372A/#453D30/#F0D060/#100E08/#D4C89A/#6E674E/#F0D060).
  - install.ps1 command block `.\desktop\install.ps1` matches desktop/README.md;
    desktop/install.ps1 exists at repo HEAD.
  - desktop/out/ untracked claims match .gitignore + desktop/README.md.
  - Freshness: source identity computed with tools/freshness.py after the last source
    read (96a1a62 / c66baf69); role_revision re-derived from project-local
    .saipen/extensions/subs/saiwiki.md charter, matches its declared YAML value.
  - Repo wiki/ mirror now intentionally drifts from kitchen (1.26.2 stamps + stale
    Development.md release section) until qqq collects and re-syncs it.
- **instructions:** (1) On collect, apply only the 8 kitchen/wiki/*.md pages to the
  repo wiki/ mirror with .md-adapted links (kitchen pages link as [Home](Home); the
  repo mirror carries [Home](Home.md) per T-105 precedent — adapt at injection, never
  edit kitchen). (2) The mirror currently lags this package (1.26.2 stamps, stale
  Development.md release section); collect closes the drift and tools/check-wiki-mirror.js
  goes green again. (3) Use `qqq` to collect and ship (push to
  github.com/vacterro/Wintage.wiki master).
- **details:**
  Forced-fresh, not reuse: WIKI-004 went stale when v1.26.3 shipped (953061f) and
  T-182..T-184, T-173, T-183 landed on top, moving source_head 2483b49 -> 96a1a62.
  The wiki-visible changes since WIKI-004: the version bump, and the T-184 README
  release-section correction whose pre-fix form the wiki Development page still mirrored
  ("Edit wintage.user.js" — the same defect T-184 removed from README.md). Nothing
  pushed; main project tree untouched (all changes under
  .saipen/extensions/subs/saiwiki/).

  RE-VERIFY (qq, 10.08.26): freshness identity recomputed with tools/freshness.py —
  source_head still 96a1a62, fingerprint still c66baf69, role_revision still 54a42475
  (the ee pass touched only .saipen/, excluded from the fingerprint). All 8 pages
  re-verified: Home/_Footer carry 1.26.3, zero 1.26.2 hits, zero "Edit
  wintage.user.js", Palettes.md hexes byte-match themes/goldendefault.json (10/10),
  check-wiki-mirror wired at release.ps1:107 and named in Development.md:45, CHANGELOG
  head-entry prerequisite stated at Development.md:21. Package stays ready; collect is
  qqq.

  RE-VERIFY (qqq, 10.08.26): source_head refreshed 96a1a62 -> fd53d63 after the eee
  translation ship (fd53d63 touched only README.<lang>.md translations + .saipen/;
  git diff 96a1a62..fd53d63 over README.md/CHANGELOG.md/desktop/README.md/wintage.user.js/
  release.ps1/themes/ is empty). fingerprint c66baf69 + role_revision 54a42475
  unchanged. All 8 pages still faithful; package ready for qqq collect.

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
- **source_head:** 2483b4989f3da4b9f42d03b46cbb48ecff7c9340
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
- **source_head:** 2483b4989f3da4b9f42d03b46cbb48ecff7c9340
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

- **status:** stale
- **summary:** Complete 8-page maintained wiki re-verified against current HEAD
  (1dd24c6). No page content changed since WIKI-003 (which went stale when T-176
  shipped): version stamps still 1.26.2, install commands still
  `.\desktop\install.ps1`, desktop/out/ still documented gitignored. T-176 added
  the BetterDiscord target (desktop/targets/betterdiscord/, generated
  out/betterdiscord/) but no wiki page describes desktop targets in enough detail
  to need an update; the 16-palette count and token table are unchanged.
  Collected at sc stage 6 — repo wiki/ mirror already current (check-wiki-mirror PASS).
- **main_project_refs:** [README.md, CHANGELOG.md, desktop/README.md, wintage.user.js, themes/*.json]
- **critical:** false
- **severity:** P3
- **producer:** saiwiki
- **source_head:** 2483b4989f3da4b9f42d03b46cbb48ecff7c9340
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
  SUPERSEDED by WIKI-005 (source_head moved to 96a1a62 at T-184/T-183; version
  stamps + Development.md release section changed).


