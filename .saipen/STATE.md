---
phase: DONE
task: none
next_action: "PHASE HUNT [T-065 and T-029 need the user; nothing else open]"
blocker: none
agent: claude-opus-5
mode: full
saipen_version: 7
schema_version: 1
saipen_home: V:\___VAC\__K\__CODE\_AI_STUFF_AGENTIC\_SAIPEN\saipen
goal_mode: true
goal_waves: 1
goal_tickets: 7
transition_from: SHIP
last_event: 201
updated: 2026-07-31T15:08:00Z
---

# Wintage вЂ” five extra themes (goal wave 1)

Objective: Antigravity, Claude Code, K-Lite media player, FreeBuff, NomadCode вЂ”
five palettes alongside the existing Dark Golden, switchable at runtime.

T-017..T-026 on BOARD. Infrastructure first (registry, switch, palette-independent
repainter), then one ticket per palette, then companion browser themes and docs.

Open question, not blocking T-017/T-018/T-019: FreeBuff and NomadCode have no
public palette I can trace. Golden, Claude Code, Antigravity and K-Lite/MPC-HC do.
If the user has a screenshot or a source file for those two, it beats guessing.

## Previous wave вЂ” UI.md conformance (v1.4.0 .. v1.4.7)

T-006..T-012 BUILT + VERIFIED as v1.4.0. Reasoning + deviations in
KNOWLEDGE/ADR-003.md; perf history in ADR-002.md; animation history in ADR-001.md.

Measured live, en.wikipedia.org WWII, 16921 elements:

| check | result |
|---|---|
| font sizes present | 10/12/14/16px, nothing else |
| font weights present | 400 and 700, nothing else |
| off-palette backgrounds | 0 |
| off-palette text colours | 0 |
| box-shadows / rounded corners / gradients | 0 / 0 / 0 |
| idle CPU settled | 0.14 % (v1.3.0 0.09 %, pre-fix 16.9 %) |

Two bugs were caught only by live measurement, both now guarded:

1. **Specificity.** The base type selector's six `:not([class*="вЂ¦" i])` matches
   score (0,6,4), so `h1 { font-size: 16px !important }` at (0,0,1) LOST вЂ” every
   heading silently flattened to 12px. Exceptions are now carved out of the base
   selector (disjoint, no specificity race); the `font-weight` pair had the same
   bug, fixed with a `:root`/`:host` prefix.
2. **`node --check` cannot see inside a CSS template literal.** Prose pasted after
   a comment's closing `*/` left a stray `*/` in `GLOBAL_CSS`; `--check` passed and
   the browser's CSS parser silently discarded rules while recovering. Now
   `tools/check-css.js` fails on stray/unclosed/nested comments, brace imbalance
   and off-palette hex, and `release.ps1` gates on it. Guard validated by
   injecting all three fault classes.

Deliberate deviations from UI.md (full reasoning in ADR-003): transition/animation
stay at 0.001s (ADR-001 live evidence beats the literal law); no global `margin:0`
or `box-sizing`; no `body{overflow-x:hidden}`; no class-name-based status colours;
semantic tokens never used as text colour (1.8:1 fails AA).

Also open: local branch `perf-verify` still exists (squash-merged, so git calls it
unmerged вЂ” `-D` is destructive and needs the user's word).

