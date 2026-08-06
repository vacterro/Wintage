---
phase: HUNT
task: none
next_action: "WAIT: manual-verify -- restart Antigravity and FreeBuff and confirm both launch with the theme live."
blocker: none
agent: claude-opus-5
mode: full
saipen_version: 7
schema_version: 3
style_contract: ded-97af6dca
saipen_home: V:\___VAC\__K\__CODE\_AI_STUFF_AGENTIC\_SAIPEN\saipen
goal_mode: true
goal_waves: 1
goal_tickets: 1
transition_from: ADD
last_event: 457
updated: 2026-08-06T16:58:00Z
---

# Current wave — three apps reported unthemed, one common cause each (v1.22.0)

T-089 complete locally and deployed: Golden Default is first, available targets
start selected, Windows Terminal + conhost are first-class targets, conhost is live
on goldendefault, and CodeNomad's native session status colours are restored. The
user needs to restart CodeNomad and existing console windows to see the new payload.

T-078..T-083 on BOARD. The through-line: every one of these failed SILENTLY and
two of them reported SUCCESS while failing.

- **Claude** injected fine into the wrong frame. Its BrowserWindow is a shell; the
  application is a `WebContentsView`, which `browser-window-created` never reaches.
  Now hooked at `web-contents-created`. If another app ever reports "themed but
  unchanged", this is the first thing to check.
- **CodeNomad** was never themed at all — the target wrote a stylesheet the app has
  no code to read. It is a plain portable Electron app and is one now.
- **Bevels** used `borderHighlight`, which is also the link/accent colour. New
  `bevelLight` token per palette, one lightness step above surfaceAlt (the actual
  Win95 rule: the light edge is a lightness step, never a hue).
- **Scrollbars** cost every container a gutter the app never budgeted for, because
  styling `::-webkit-scrollbar` at all turns Chromium's overlay bars classic. Arrows
  gone, 12px, and containers whose whole range is ≤8px (this theme's own bevels)
  get `scrollbar-width: none` — never `overflow: hidden`, which would make content
  unreachable when the guess is wrong.
- **Caption buttons** are painted by Chromium outside the DOM (titleBarOverlay), so
  no stylesheet can reach them; recoloured via `setTitleBarOverlay` and controls
  under them nudged out using `navigator.windowControlsOverlay`.

Left needing the user's eyes: CodeNomad after restart, and the Antigravity restyle.

# Previous wave — five extra themes (goal wave 1)

Objective: Antigravity, Claude Code, K-Lite media player, FreeBuff, NomadCode —
five palettes alongside the existing Dark Golden, switchable at runtime.

T-017..T-026 on BOARD. Infrastructure first (registry, switch, palette-independent
repainter), then one ticket per palette, then companion browser themes and docs.

Open question, not blocking T-017/T-018/T-019: FreeBuff and NomadCode have no
public palette I can trace. Golden, Claude Code, Antigravity and K-Lite/MPC-HC do.
If the user has a screenshot or a source file for those two, it beats guessing.

## Previous wave — UI.md conformance (v1.4.0 .. v1.4.7)

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

1. **Specificity.** The base type selector's six `:not([class*="..." i])` matches
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
