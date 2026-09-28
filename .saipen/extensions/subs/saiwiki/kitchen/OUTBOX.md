# OUTBOX

## W-010: Wintage wiki FORCE-FRESH rebind at 82178cd, v1.36.0 restamp
- **status:** ready
- **summary:** FORCE-FRESH re-verified full 8-page wiki package bound to v1.36.0 HEAD 82178cd. Version stamps moved to 1.36.0 (Home.md, _Footer.md); Desktop.md dropped the non-existent `antigravity-app` target row and now documents the remembered portable-browser discovery plus `-RescanBrowsers`; Installation.md shows the rescan command; Development.md lists the repainter-budget and browser-cache gates. Palettes.md re-verified unchanged (16 palettes, 21 tokens, 10/10 hex match). The repo wiki/ mirror is expected to lag until qqq.
- **main_project_refs:** [wiki/Home.md, wiki/Installation.md, wiki/Palettes.md, wiki/Desktop.md, wiki/Development.md, wiki/_Footer.md, CHANGELOG.md, wintage.user.js, desktop/install.ps1, tools/install-browsers.ps1, tools/check-wiki-mirror.js]
- **critical:** false
- **severity:** P2
- **producer:** saiwiki
- **source_head:** 82178cdfb124ad55f9dccc7cd55ce3a633d51a6c
- **source_tree_fingerprint:** git-delta-v1:c66baf69a8306f3b95dfc7badb5f72b088f8de8408e933efadc4d149721a1195
- **role_revision:** sha256:54a42475a124ab0f27e83d600a284a9cc54d9668029c4828cfc48512b031df13
- **coverage:** All 8 maintained wiki pages (Home, Installation, Palettes, Desktop, Known-Behaviors, Development, _Sidebar, _Footer) - 100% of wiki surface.
- **payload:** .saipen/extensions/subs/saiwiki/kitchen/wiki/*.md (8 pages)
- **verified:** PASS -- 8/8 kitchen pages non-empty; the version stamp 1.36.0 in Home.md and _Footer.md equals wintage.user.js @version and const W95_VERSION; Palettes.md saying "sixteen palettes" equals the 16-entry THEMES registry and its 10-row hex table matches themes/goldendefault.json (21 tokens) with zero mismatches; the Desktop.md target table contains no key outside the live listing and leaves none of the 20 live targets uncovered; no unresolved internal links; source identity recomputed with freshness.compute_source_identity on a clean working tree at 82178cd; role revision recomputed from this charter and unchanged.
- **instructions:** For qqq (Core `saipen collect saiwiki` then ship): copy `.saipen/extensions/subs/saiwiki/kitchen/wiki/*.md` over `wiki/*.md`, adapting bare internal links to `*.md` -- the ONLY permitted difference (tools/check-wiki-mirror.js); then run `node tools/check-wiki-mirror.js` (must exit 0). That gate is RED between this prepare and the collect because the kitchen has moved ahead of the mirror, which is the expected lag E-014 recorded; it is not a defect of this package. Commit and ship. This role pushed nothing and wrote nothing into the main tree.
- **details:**
  Docs drift since W-009 (v1.30.0, 2026-09-02): the wiki still described 1.30.0 while CHANGELOG.md and wintage.user.js are at 1.36.0 (the audit/5.md wave, T-245/T-246). Three facts had drifted: the version stamp, the `antigravity-app` row in the target table (no such target exists in the live listing -- the Electron relocation targets are freebuff, codenomad, workbuddy, zcode plus claude patched in place), and a new user-facing capability with no page describing it (the portable browser root is now remembered, so a status refresh no longer rescans it, and `install.ps1 -RescanBrowsers` / `install-browsers.ps1 -Rescan` is the explicit rescan). Everything else re-verified rather than rewritten: palettes (16/16, token table equal to the Golden Default pack), the target mechanisms table, the userscript behaviours and the deliberate UI.md deviations.

## W-007: Wintage wiki FORCE-FRESH rebind at 8867967
- **status:** stale
- **superseded_by:** WIKI-009
- **summary:** historical v1.26.4-era wiki package; superseded by WIKI-009.
- **producer:** saiwiki
- **source_head:** 886796720f135b12da6bb05ae3fc5e8cf2e411b2
- **source_tree_fingerprint:** git-delta-v1:8f53396e95963bbf98b1b22591605330366eb4b79b8a89274e0d9b4db7d591b6
- **role_revision:** sha256:54a42475a124ab0f27e83d600a284a9cc54d9668029c4828cfc48512b031df13
- **coverage:** 8 wiki pages (Home, Installation, Palettes, Desktop, Known-Behaviors, Development, _Sidebar, _Footer).
- **payload:** .saipen/extensions/subs/saiwiki/kitchen/wiki/*.md (8 pages)
- **verified:** PASS -- legacy run verified
- **instructions:** Superseded by WIKI-009.
- **details:** Historical entry retained for audit log continuity.

## W-008: Wintage wiki FORCE-FRESH rebind at a9399dc9
- **status:** stale
- **superseded_by:** WIKI-009 (source_head a9399dc9 -> ffc13fd at v1.30.0 ship)
- **summary:** historical v1.29.0-era wiki package; superseded by WIKI-009.
- **producer:** saiwiki
- **source_head:** a9399dc9d053b0cd333e0c343fbe6eed26d40185
- **source_tree_fingerprint:** git-delta-v1:3dc46023688daf25f64f1105823dc4f33ba0da21e693b73e8ff88a1da1357209
- **role_revision:** sha256:54a42475a124ab0f27e83d600a284a9cc54d9668029c4828cfc48512b031df13
- **coverage:** 8 wiki pages.
- **payload:** .saipen/extensions/subs/saiwiki/kitchen/wiki/*.md (8 pages)
- **verified:** PASS -- legacy run verified
- **instructions:** Superseded by WIKI-009.
- **details:** Historical entry retained for audit log continuity.

## W-009: Wintage wiki FORCE-FRESH rebind at ffc13fd, v1.30.0 restamp
- **status:** stale
- **superseded_by:** W-010
- **summary:** FORCE-FRESH re-verified full 8-page wiki package bound to v1.30.0 HEAD ffc13fd; version stamps updated to 1.30.0 (Home.md, _Footer.md); Desktop.md carries qbittorrent target + font policy; Palettes.md 10/10 hex match goldendefault.json; repo wiki/ mirror in sync.
- **main_project_refs:** [wiki/Home.md, wiki/Desktop.md, wiki/_Footer.md, README.md, wintage.user.js, themes/goldendefault.json]
- **critical:** false
- **severity:** P2
- **producer:** saiwiki
- **source_head:** ffc13fd5065855239642a6d479806e6c14956814
- **source_tree_fingerprint:** git-delta-v1:c3e75317953761991f3c534a4a146f4085ad51cbfe0d43929ac5417275e93d20
- **role_revision:** sha256:54a42475a124ab0f27e83d600a284a9cc54d9668029c4828cfc48512b031df13
- **coverage:** All 8 maintained wiki pages (Home, Installation, Palettes, Desktop, Known-Behaviors, Development, _Sidebar, _Footer) - 100% of wiki surface.
- **payload:** .saipen/extensions/subs/saiwiki/kitchen/wiki/*.md (8 pages)
- **verified:** PASS -- tools/check-wiki-mirror.js exits 0 (repo wiki/ mirror in sync via adaptForRepo); 8/8 kitchen pages non-empty; version stamp 1.30.0 matches wintage.user.js; Desktop.md covers qbittorrent; Palettes.md matches goldendefault.json.
- **instructions:** For qqq (Core saipen collect saiwiki then ship): copy kitchen pages to repo wiki/ via adaptForRepo (.md link rewrite), verify with check-wiki-mirror.js, commit and push.
- **details:**
  - Re-bound post-v1.30.0 ship to new source_head ffc13fd and source_tree_fingerprint.
  - Home.md and _Footer.md version stamps bumped to 1.30.0 (2026-09-02).
  - Desktop.md includes qbittorrent row + name-never-install font policy.
  - Repo wiki/ mirror synced and validated via node tools/check-wiki-mirror.js.
  - Boundary clean: all kitchen writes inside .saipen/extensions/subs/saiwiki/.
