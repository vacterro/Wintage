---
phase: VERIFY
task: T-244
next_action: "PHASE REVIEW T-244"
blocker: none
agent: zcode
saipen_version: 7
schema_version: 3
saipen_home: V:\___VAC\__K\__CODE\_AI_STUFF_AGENTIC\_SAIPEN
mode: full
execution_intent: converge
converge_target: ship
last_event: 912
style_contract: ded-4ae736e4
updated: "2026-09-11T07:05:00Z"
transition_from: BUILD
---

# Active Work

Sole DOING owner: T-244 (ZCode usage-popup 5-hours label, light orange; claimed E-910). T-243 DONE and SHIPPED as v1.35.0 (ead75e8, tag pushed; ship line reconstructed E-910). T-242 DONE (SRC-006 closed E-902). audit/5.md remains uncaptured; T-238 and T-065 stay parked.

## Full matrix, current (E-900 verify)

tests/Run-Tests.ps1 ALL TESTS PASSED (2026-09-11, real Windows checkout). Node gates theme-switch, spa-exclude, perf-recovery, perf-lanes, perf-bounded, shim-payloads, electron-shim, electron-state, repainter-polarity, diag-counters, fs-retry, recovery-lifecycle, terminal-font, theme-packs, check-css, check-wiki-mirror, build-desktop --check all PASS; node --check wintage.user.js PASS.

## SAIOPS is refused in this project, deliberately

`E-837` records it in full: fast validation demands a CONSECUTIVE E-ID chain, and this project carries two documented T-222-era stub-backfill gaps (E-703->E-717, E-718->E-722). E-774 relaxed that rule in the shared install; the saipen project has since reverted it and proved on a fixture that the relaxed rule accepts a forged log line. So E-865..E-888 are hand-appended with no `[op: ...]` id and the validator's `[saio]` provenance check lists them by design.

## Untracked files that must ride the next ship

desktop/targets/cinema4d/ and desktop/targets/notepadplusplus/ templates (T-243 era), tools/test-vscode-recovery.ps1 (SRC-006:R004, E-895), tools/test-reapply-intent.ps1 (SRC-006:R005, E-899/E-900), tools/test-logon-task-gui.ps1 (concurrent actor, E-897). Tracked-but-modified T-242 surfaces: desktop/install.ps1, desktop/modules/common.ps1, tests/Run-Tests.ps1, desktop/WintageInstaller.ps1 (concurrent), tools/install-electron.js (concurrent R007 WIP).
