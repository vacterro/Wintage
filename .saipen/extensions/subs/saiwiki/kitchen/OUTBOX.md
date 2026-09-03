# OUTBOX

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
- **status:** ready
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
  - Repo wiki/ mirror synced and validated via 
ode tools/check-wiki-mirror.js.
  - Boundary clean: all kitchen writes inside .saipen/extensions/subs/saiwiki/.
