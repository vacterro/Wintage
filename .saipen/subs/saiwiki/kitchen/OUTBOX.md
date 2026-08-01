# OUTBOX

## WIKI-001: Wintage wiki authored from current HEAD docs (v1.23.3)

- **status:** ready
- **summary:** Wintage GitHub wiki was a one-page stub ("Welcome to the Wintage wiki!").
  Authored the complete maintained wiki (8 pages) from the current project docs:
  Home, Installation, Palettes, Desktop, Known-Behaviors, Development, _Sidebar,
  _Footer. Verified against current HEAD.
- **main_project_refs:** [README.md, CHANGELOG.md, desktop/README.md, wintage.user.js]
- **critical:** false
- **severity:** P3
- **producer:** saiwiki
- **source_head:** 6e18ec10ba9c362a8d9fc143d5fcb5884aba6b4c (project), 3fffb8a75a8930b4f39cc88a2b4af51112e40934 (wiki remote)
- **coverage:** every maintained wiki page (Home, Installation, Palettes, Desktop,
  Known-Behaviors, Development, _Sidebar, _Footer); source invariants = README.md
  structure, CHANGELOG.md current version 1.23.3, desktop/README.md target table
  (14 targets + mechanisms + update-survival), sixteen-palette registry.
- **payload:**
  - kitchen/wiki/Home.md
  - kitchen/wiki/Installation.md
  - kitchen/wiki/Palettes.md
  - kitchen/wiki/Desktop.md
  - kitchen/wiki/Known-Behaviors.md
  - kitchen/wiki/Development.md
  - kitchen/wiki/_Sidebar.md
  - kitchen/wiki/_Footer.md
- **verified:**
  - Version stamps 1.23.3 cross-checked against CHANGELOG.md top entry.
  - Palette table (16 palettes, 10-token Dark Golden table) cross-checked against
    README.md and themes/*.json (16 packs present).
  - Desktop target table cross-checked against desktop/README.md (14 rows,
    mechanisms and update-survival match).
  - Freshness: drafted against project HEAD 6e18ec1 (uncommitted working tree is the
    Claude transparency fix series, not wiki-relevant).
  - Wiki remote reviewed read-only: single stub Home.md, no other pages to preserve.
- **instructions:** (1) Push kitchen/wiki/*.md to github.com/vacterro/Wintage.wiki
  (add Home.md content, add 7 new pages; keep _Sidebar/_Footer). (2) No main-project
  file changes required. (3) Then run Core VERIFY -> REVIEW -> SHIP via `qqq`.
  (4) Do not touch the Claude transparency commits (69d3094..6e18ec1) — they are
  unpushed local work owned by another session.
- **update:** pages restamped to v1.24.0 (2026-08-02) after the v1.24.0 ship --
  Home.md current-version line and _Footer.md stamp, in both kitchen and the repo
  wiki/ mirror (E-390). Kitchen remains canonical for the remote push.
- **details:**
  The wiki had exactly one stub page (30 bytes). All eight pages are drafted from the
  current docs so the wiki and the repo agree about what Wintage is, how to install
  it, what the desktop targets can and cannot reach, and how releases are made.
  Prepared by Core adopting saiwiki per RFC `qq` route; nothing was pushed and no
  main-project file was modified by the sub.
