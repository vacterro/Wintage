# OUTBOX

## WIKI-001: Wintage wiki authored from current HEAD docs (v1.26.1)

- **status:** ready
- **summary:** Wintage GitHub wiki was a one-page stub. Authored 8-page maintained wiki.
  Pages carry v1.26.1 stamps (updated by T-145). Kitchen content current against HEAD.
- **main_project_refs:** [README.md, CHANGELOG.md, desktop/README.md, wintage.user.js]
- **critical:** false
- **severity:** P3
- **producer:** saiwiki
- **source_head:** e24adf7f9383b5ce6cdb3380e3b6b5ee518d759a (project HEAD)
  (previously: 6e18ec1 authored, dad7f2a restamped v1.24.0, eeb2515 re-verified,
  3e1e77a v1.26.0 restamp, now v1.26.1 at e24adf7)
- **coverage:** every maintained wiki page (Home, Installation, Palettes, Desktop,
  Known-Behaviors, Development, _Sidebar, _Footer). Source invariants: README.md
  (Golden Default palette label, 10-of-21 note), desktop/README.md (target table
  with updated paths, token count 21), CHANGELOG.md v1.26.1, 16-palette registry.
- **payload:**
  - kitchen/wiki/Home.md (v1.26.1 stamp)
  - kitchen/wiki/Installation.md
  - kitchen/wiki/Palettes.md
  - kitchen/wiki/Desktop.md
  - kitchen/wiki/Known-Behaviors.md
  - kitchen/wiki/Development.md
  - kitchen/wiki/_Sidebar.md
  - kitchen/wiki/_Footer.md (v1.26.1 stamp)
- **verified:**
  - Version stamps v1.26.1 cross-checked against CHANGELOG.md and wintage.user.js @version.
  - Palette table cross-checked against README.md (Golden Default, 21 tokens).
  - Desktop target table cross-checked against desktop/README.md.
  - Freshness: kitchen pages carry v1.26.1 stamps from T-145.
  - Wiki remote at d6d5611 (previous qqq push with FreeBuff ad mentions removed).
- **instructions:** (1) Push kitchen/wiki/*.md to github.com/vacterro/Wintage.wiki
  master. (2) No main-project file changes required — wiki mirror already at repo
  wiki/. (3) Use `qqq` to collect and ship.
- **details:**
  Pages were last pushed at E-451 (qqq collect → remote 00a619c then d6d5611 for
  FreeBuff ad-removal). Since then: v1.26.1 (T-128 ship), doc drift fix (T-145),
  hardcoded path removal (T-148), -Status switch (T-149), CLI i18n (T-150).
  Kitchen pages restamped to v1.26.1; OUTBOX refreshed to ready.
