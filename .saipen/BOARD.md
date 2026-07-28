# BOARD

## DOING

## TODO
- [ ] T-033 Claude Code: the colours are the terminal's, so emit a Windows Terminal scheme per palette plus the ~/.claude/settings.json wiring | needs: T-031 | verify: scheme appears in Windows Terminal, Claude Code renders on it without unreadable text
- [ ] T-034 K-Lite / MPC-HC: native Win32, registry only -- set what HKCU\Software\MPC-HC exposes, write a .reg backup first, and REPORT what the app does not let a theme reach rather than claiming full coverage | needs: T-031 | verify: keys applied, backup restores the previous state, uncovered surfaces named explicitly
- [ ] T-035 FreeBuff (Electron): CSS injection that survives an app update, backup of the original asar, one-command revert | needs: T-031 | verify: app launches themed, revert restores the original bytes, re-running after a simulated update re-applies cleanly
- [ ] T-036 NomadCode (Electron): same mechanism as T-035, different target paths | needs: T-035 | verify: as T-035
- [ ] T-037 README for the desktop side: what each target can and cannot be themed, how to re-apply after an app update, how to revert | needs: T-032,T-033,T-034,T-035,T-036 | verify: each documented command runs as written
- [ ] T-030 Split the link colour out of borderHighlight: the token is both the bevel light edge and the link colour, which only works on a dark palette -- on a light one the bevel must be near-white and near-white fails AA as text. Touches GLOBAL_CSS, SHADOW_CSS, the repainter link branch, the pack schema and both gates | needs: T-027 | verify: golden link colour unchanged, a light pack passes the AA gate with a readable link and a near-white bevel
- [ ] T-025 Companion browser themes: tools/apply-themes.js also emits browser-theme/<slug>/manifest.json from the same themes/<slug>.json, so the Cent Browser chrome matches whichever theme is active | needs: T-020,T-021,T-022,T-023,T-024,T-027 | verify: 6 manifests emitted, each loads in the browser and its frame colour equals its palette background
- [ ] T-026 README theme docs (switching + installing a pack onto a new Wintage version) and release.ps1 gating the generator + check-css over every theme | needs: T-025 | verify: node tools/check-css.js iterates all 6 palettes and PASSes; injecting an off-palette hex into any one of them FAILs

- [ ] T-029 Confirm live in Tampermonkey that @sandbox raw kept page context: open any site with shadow DOM (reddit, youtube) and check `document.querySelector('*').shadowRoot?.querySelector('style[data-w95]')` is non-null, plus the theme menu switches and persists across origins | needs: T-018 | verify: shadow style present on 2 shadow-DOM sites, switch survives a cross-origin navigation
- [ ] T-028 release.ps1 bumps `// @version` but not `const W95_VERSION` (:94), so the data-w95-ver diagnostic stamp reports a stale build — derive the constant from the header at load, or bump both | verify: run release.ps1, both values agree; a deliberately mismatched pair FAILs the gate

## DONE
- [x] T-031 desktop/ subsystem: tools/build-desktop.js fills ${token} templates from the same themes/*.json packs, desktop/install.ps1 installs into the user profile with -WhatIf, -Revert, timestamped backups and a staleness refusal | verify: build --check clean, install run twice with backup-then-replace, -WhatIf touched nothing -- E-082
- [x] T-032 Antigravity + VS Code: six colour themes generated from a template DERIVED from the user's own hand-made Win95 theme (96/99 keys mapped to tokens) | verify: generated golden byte-equal to the original (99 colours, 14 tokenColors), other palettes differ, no placeholders left, installed to both -- E-083, E-084
- [x] T-022 K-Lite (MPC-HC) palette -- graphite + silver, neutral by design (MPCTheme=1 confirms the dark UI; MPC's dark chrome carries no hue) | verify: 7.56 / 4.84 / 5.67 : 1, AA gate PASS -- E-076
- [x] T-023 FreeBuff palette -- lime #7CFF3F accent read out of the installed app.asar, slate surfaces | verify: 10.49 / 7.06 / 8.40 : 1 -- E-075, E-076
- [x] T-024 NomadCode palette -- indigo #624AFF read out of the app's own Electron cache; needed an AA lift the gate demanded | verify: 5.65 / 4.72 / 4.77 : 1 after lifting two tokens -- E-076
- [x] T-020 Claude Code palette -- re-derived from golden per UI.md (coral #D97757 hue on warm near-neutral surfaces) after the user ruled that every theme is UI.md, not a copy of the product UI | verify: 8.18 / 5.34 / 6.13 : 1 -- E-074, E-076
- [x] T-021 Antigravity palette -- re-derived from golden, teal #09b6a2 read out of the IDE's own tailwind.config.js (not the Google blue a guess would have picked) | verify: 10.64 / 7.16 / 8.67 : 1 -- E-075, E-076
- [x] T-027 Theme packs + installer: themes/<slug>.json as the palette source, tools/apply-themes.js generating the block into ANY wintage.user.js (markers if present, brace-walk + add markers if not), install-themes.ps1 with -Latest/-Check for re-applying after an upgrade | verify: tools/test-theme-packs.js 18/18 PASS incl. patching the last released commit and byte-identical re-runs -- E-066
- [x] T-019 Palette-independent repainter: elev() normalises incoming luminance into the active theme's polarity (identity on a dark theme, so golden is provably untouched), text contrast measured against the theme's own backdrop, color-scheme + data-w95-dark follow the theme, per-theme WCAG AA floor in check-css.js | verify: tools/test-repainter-polarity.js 21/21 PASS, AA gate rejects a forced 2.70:1 textPrimary -- E-062
- [x] T-018 Theme switching: GM-backed selection (per-user, not per-origin), one menu entry per theme in the top frame only, reload on switch, total fallback chain; @sandbox raw keeps page context so the attachShadow interception survives the grants | verify: tools/test-theme-switch.js 22/22 PASS, gated into release.ps1 -- E-055
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
