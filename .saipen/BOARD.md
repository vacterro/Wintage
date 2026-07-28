# BOARD

## DOING

## TODO
- [ ] T-018 Theme switching: @grant GM_getValue/GM_setValue/GM_registerMenuCommand, one menu entry per theme, silent fallback to the default palette when the GM API is absent | needs: T-017 | verify: pick a theme in the Tampermonkey menu, reload, palette persists and holds across a different origin
- [ ] T-019 Palette-independent repainter: dark-floor 0.004, neutral spread<=60, darkBg 0.008 and the palette-token early return all derived from the active theme instead of the golden constants; AA contrast floor asserted per palette | needs: T-017 | verify: golden unchanged on wikipedia; a deliberately light test palette yields 0 low-contrast text
- [ ] T-027 Theme packs + installer: each palette becomes themes/<slug>.json (the single source), tools/apply-themes.js regenerates the THEMES block between markers in ANY wintage.user.js, install-themes.ps1 re-applies the packs onto a freshly upgraded script, release.ps1 runs the generator before its gates | needs: T-017 | verify: run the installer against an unmodified upstream wintage.user.js -> themes present, node --check + check-css PASS; run it twice -> byte-identical file (idempotent)
- [ ] T-020 Claude Code palette | needs: T-017,T-019 | verify: 0 off-palette bg/text, 0 low-contrast text, live on 3 control sites
- [ ] T-021 Antigravity palette | needs: T-017,T-019 | verify: 0 off-palette bg/text, 0 low-contrast text, live on 3 control sites
- [ ] T-022 K-Lite / MPC-HC palette | needs: T-017,T-019 | verify: 0 off-palette bg/text, 0 low-contrast text, live on 3 control sites
- [ ] T-023 FreeBuff palette | needs: T-017,T-019 | verify: 0 off-palette bg/text, 0 low-contrast text, live on 3 control sites
- [ ] T-024 NomadCode palette | needs: T-017,T-019 | verify: 0 off-palette bg/text, 0 low-contrast text, live on 3 control sites
- [ ] T-025 Companion browser themes: tools/apply-themes.js also emits browser-theme/<slug>/manifest.json from the same themes/<slug>.json, so the Cent Browser chrome matches whichever theme is active | needs: T-020,T-021,T-022,T-023,T-024,T-027 | verify: 6 manifests emitted, each loads in the browser and its frame colour equals its palette background
- [ ] T-026 README theme docs (switching + installing a pack onto a new Wintage version) and release.ps1 gating the generator + check-css over every theme | needs: T-025 | verify: node tools/check-css.js iterates all 6 palettes and PASSes; injecting an off-palette hex into any one of them FAILs

## DONE
- [x] T-017 Theme registry: THEMES map keyed by slug, T = THEMES[active].tokens, first paint no longer hardcodes golden; check-css.js swapped its frozen palette set for "zero literal hex in a CSS body" plus a per-theme table check | verify: GLOBAL_CSS + SHADOW_CSS byte-identical to HEAD, 18/18 tokens identical, 4 injected fault classes all rejected -- E-047, E-048, E-049
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

- [x] T-013 Pause infinite animations instead of driving them to 1000 iterations/sec | verify: infinite div/svg/in-button all animation-play-state:paused, finite still running
- [x] T-014 Idle-CPU review of the reworked scheduler: identity-based self-write suppression replacing the 100ms time window | verify: self-inflicted style records 9466 -> 0, backoff ladder reaches 60000, foreign inline write still repainted
- [x] T-015 Fix the sweep-rate hot loop: MIN_SWEEP_GAP floor, no 0ms scheduling, never replace a sooner timer | verify: 148 -> 11 sweeps per 15s under identical churn
- [x] T-016 Enforce UI.md invariants from JS where CSS loses to site !important; palette clamp for control subtrees; close dark-surface gaps; palette idempotence | verify: 3 popular sites all zero violations, zero drift across two settling windows

## BLOCKED
