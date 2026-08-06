---
phase: BLOCKED
task: none
next_action: WAIT: user brake -- 5 stranded TODO tickets (T-120/T-119/T-118/T-117/T-112) require user verification (user reports idle CPU, scroll jumps, usage bars, status indicators, popovers). No workable tickets remain. 16/20 goal tickets used, 1/3 waves.
blocker: remaining TODO tickets are unworkable (verify criteria require user action)
agent: claude-opus-5
mode: full
saipen_version: 7
schema_version: 3
style_contract: ded-97af6dca
saipen_home: V:\___VAC\__K\__CODE\_AI_STUFF_AGENTIC\_SAIPEN\saipen
goal_mode: true
goal_waves: 1
goal_tickets: 16
transition_from: SHIP
last_event: 488
updated: 2026-08-07T00:30:00Z
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
