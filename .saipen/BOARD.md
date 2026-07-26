# BOARD

## DOING
- [ ] T-006 Token block: full UI.md palette in :root; kill off-palette link colour #9DD9F9 -> --borderHighlight; ::selection -> --selection #362812 | owner: claude-opus-5 | claim_time: 2026-07-26T11:25:40Z | verify: grep finds no hex outside the palette

## TODO
- [ ] T-007 Depth language per UI.md law 3: 2px 4-value bevel borders replacing 1px+inset-shadow, global box-shadow/text-shadow none, scrollbars reworked, disabled keeps its raised bevel, dialogs + th raised | needs: T-006 | verify: no box-shadow left in GLOBAL_CSS/SHADOW_CSS except none
- [ ] T-008 Zero blur/gradient per law 2: global backdrop-filter none, filter none except media, JS kills ALL gradients not just light ones, progress/meter exempt | needs: T-007
- [ ] T-009 Typography ladder: 12px default, h1 16, h2-h6 14, small 10, line-height 1.2, text-rendering optimizeSpeed, -moz-osx-font-smoothing unset | needs: T-006
- [ ] T-010 Control metrics: input/select height 20px padding 1px 3px, textarea min-height 64px resize none, button padding 2px 6px min 24x20, focus outline-offset -4px | needs: T-007
- [ ] T-011 Semantic colours: map saturated backgrounds to --success/--warning/--danger by hue instead of the arbitrary 0.18 darkening | needs: T-006
- [ ] T-012 ADR-003 recording the DELIBERATE deviations from UI.md and why (transition/animation not `none`; no global margin:0 or box-sizing; no body overflow-x:hidden) | needs: T-007,T-008,T-009,T-010,T-011

## DONE
- [x] T-001 Tame animations: animation-duration/-delay 0.001s, global+shadow, verified safe, shipped v1.2.0
- [x] T-002 Kill style-recalc thrash: process() reads only, writes batched into one flush per sweep | verify: force tick 250ms -> 19-42ms, 996-element pixel diff vs v1.2.1 = 0
- [x] T-003 Sub-frames get CSS + observer + 3 bounded settling sweeps, no interval (@noframes rejected: would leave embeds unthemed)
- [x] T-004 Force sweeps demand-driven (new DOM / changed sheet / tab return / 30s heartbeat), not blind every 4.5s | verify: settled-page tick 1.3ms, 0 long tasks
- [x] T-005 Mutation batch de-dup: skip records whose ancestor is in the same batch, skip already-detached nodes

## BLOCKED
