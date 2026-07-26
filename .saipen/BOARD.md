# BOARD

## DOING

## TODO

## DONE
- [x] T-001 Tame animations: animation-duration/-delay 0.001s, global+shadow, verified safe, shipped v1.2.0
- [x] T-002 Kill style-recalc thrash: process() reads only, writes batched into one flush per sweep | verify: force tick 250ms -> 19-42ms, 996-element pixel diff vs v1.2.1 = 0
- [x] T-003 Sub-frames get CSS + observer + 3 bounded settling sweeps, no interval (@noframes rejected: would leave embeds unthemed)
- [x] T-004 Force sweeps demand-driven (new DOM / changed sheet / tab return / 30s heartbeat), not blind every 4.5s | verify: settled-page tick 1.3ms, 0 long tasks
- [x] T-005 Mutation batch de-dup: skip records whose ancestor is in the same batch, skip already-detached nodes
- [x] T-006 Full UI.md token block; off-palette link colour #9DD9F9 -> --borderHighlight; ::selection -> --selection | verify: 0 off-palette bg + 0 off-palette text across 16921 live elements
- [x] T-007 Depth language: 2px 4-value bevels, global box-shadow/text-shadow none, scrollbars rebuilt from borders, disabled keeps its bevel, dialogs + th raised | verify: 0 box-shadows live
- [x] T-008 Zero blur/gradient: backdrop-filter none, filter none except media, ALL gradient hues killed in JS, progress/meter/slider exempt | verify: 0 gradients live
- [x] T-009 Type ladder 12/14/16/10 + line-height 1.2 + two weights | verify: only 10/12/14/16px and only weights 400/700 present live
- [x] T-010 Control metrics: input/select 20px, textarea 64px, button padding 2px 6px min 24x20, focus outline-offset -4px
- [x] T-011 Semantic colours: saturated backgrounds snap to --success/--warning/--danger by hue sector; NOT used as text colour (fails AA)
- [x] T-012 ADR-003 recording the deliberate UI.md deviations; tools/check-css.js guard added and gated into release.ps1

## BLOCKED
