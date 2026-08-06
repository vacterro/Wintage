# OUTBOX

## WIKI-001: Wintage wiki authored from current HEAD docs (v1.23.3)

- **status:** shipped
- **summary:** Wintage GitHub wiki was a one-page stub ("Welcome to the Wintage wiki!").
  Authored the complete maintained wiki (8 pages) from the current project docs:
  Home, Installation, Palettes, Desktop, Known-Behaviors, Development, _Sidebar,
  _Footer. Verified against current HEAD.
- **main_project_refs:** [README.md, CHANGELOG.md, desktop/README.md, wintage.user.js]
- **critical:** false
- **severity:** P3
- **producer:** saiwiki
- **source_head:** 3e1e77a09d79ee64255ef62c8c254a24cc1b6cb5 (project), 7fffb8a75a8930b4f39cc88a2b4af51112e40934 (wiki remote)
  (authored at 6e18ec1; restamped to v1.24.0 at dad7f2a; re-verified at eeb2515;
  v1.26.0 restamp at 3e1e77a -- README drift since was screenshots + CRLF/palette
  sections only, CHANGELOG now carries the [1.26.0] entry, pages carry 1.26.0 stamps)
- **coverage:** every maintained wiki page (Home, Installation, Palettes, Desktop,
  Known-Behaviors, Development, _Sidebar, _Footer); source invariants = README.md
  structure, CHANGELOG.md current version 1.26.0, desktop/README.md target table
  (14 targets + mechanisms + update-survival) + FreeBuff ad-removal/sound sections,
  twenty-one-token registry (16 packs).
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
  - Version stamps 1.26.0 cross-checked against CHANGELOG.md top entry and
    wintage.user.js @version.
  - Palette table (16 palettes, 21-token Dark Golden table) cross-checked against
    README.md and themes/*.json (16 packs present).
  - Desktop target table cross-checked against desktop/README.md (14 rows,
    mechanisms and update-survival match; FreeBuff ad-removal + sound added).
  - Freshness: restamped against project HEAD 3e1e77a (v1.26.0); only version /
    token-count / FreeBuff-subsection drift demanded edits, no structural redraft.
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

  UPDATE (E-391, restamp): pages restamped to v1.24.0 after the v1.24.0 ship.
  UPDATE (E-393, `qq` re-verify): source_head refreshed to eeb2515. No content
  drift requiring a redraft -- README diff is screenshots + CRLF only, and the
  CHANGELOG [1.24.0] entry is already linked from _Footer. Status stays ready;
  the wiki-remote push remains the qqq step.
  UPDATE (E-447, `qq` prepare v1.26.0): pages restamped to v1.26.0 (2026-08-03) --
  Home.md current-version line + _Footer.md stamp; Palettes.md/Desktop.md token
  count 18 -> 21; Desktop.md gained the FreeBuff ad-removal + completion-sound
  section; Development.md gained inspect-electron.js + shim/terminal test gates.
  source_head refreshed to 3e1e77a. Status stays ready; push remains the qqq step.

  UPDATE (E-451, `qqq` collect + ship): consumed. All 8 pages pushed to
  github.com/vacterro/Wintage.wiki master (00a619c, replaces 3fffb8a stub).
  Remote master byte-identical to kitchen. Handoff fully integrated; status:
  shipped.
