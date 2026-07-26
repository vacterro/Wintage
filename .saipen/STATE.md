---
phase: SHIP
task: T-014
next_action: "merge idle-verify into main as v1.4.2, push origin/main"
blocker: none
agent: claude-opus-5
mode: full
saipen_version: 7
saipen_home: V:\___VAC\__K\__CODE\_AI_STUFF_AGENTIC\_SAIPEN\saipen
updated: 2026-07-26T23:16:33Z
---

# Wintage — UI.md conformance wave (saipen)

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

1. **Specificity.** The base type selector's six `:not([class*="…" i])` matches
   score (0,6,4), so `h1 { font-size: 16px !important }` at (0,0,1) LOST — every
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
unmerged — `-D` is destructive and needs the user's word).
