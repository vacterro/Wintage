---
phase: SHIP
task: T-002
next_action: "merge perf-verify into main as v1.3.0, push, delete scratch branch"
blocker: none
agent: claude-opus-5
mode: full
saipen_version: 7
saipen_home: V:\___VAC\__K\__CODE\_AI_STUFF_AGENTIC\_SAIPEN\saipen
updated: 2026-07-26T11:20:00Z
---

# Wintage — idle-CPU + slow-load fix (saipen)

T-002..T-005 BUILT + VERIFIED as v1.3.0. Full reasoning + numbers in
KNOWLEDGE/ADR-002.md; this is the short version.

Root cause was NOT the sweep frequency — it was `process()` reading
`getComputedStyle` and writing inline styles in the same loop. Each write
invalidates style, so the next read forced a whole-document recalc against this
theme's own pathological selectors (`*`, the 8-`:not([class*=… i])` Verdana
selector, the 12-negation hover freeze). One write bought one full recalc, 2500
times per force pass.

Measured, en.wikipedia.org WWII page, 16921 elements, both versions eval'd live:

| | v1.2.1 | v1.3.0 |
|---|---|---|
| boot long task | 716 ms | **327 ms** |
| force tick | 253 ms | **19–42 ms** |
| light tick | — | **0.8–1.3 ms** |
| avg CPU, settling | **16.9 %** | **1.28 %** |
| avg CPU, settled | 16.9 % | **0.09 %** |
| 996-element pixel diff | — | **0 differences** |

Traps recorded in ADR-002: never put `style` in the observer's attributeFilter
(setImp would feed the observer its own output); the 30 s heartbeat is load-bearing,
not decoration; `requestForceSweep()` owes a whole lap, not one pass; improved
numbers are NOT headroom for more universal selectors.

T-001 DONE + SHIPPED as v1.2.0 (animation taming). See KNOWLEDGE/ADR-001.md.
