---
phase: REVIEW
task: T-246
next_action: "PHASE REVIEW T-246"
blocker: none
agent: antigravity
saipen_version: 7
schema_version: 3
saipen_home: V:\___VAC\__K\__CODE\_AI_STUFF_AGENTIC\_SAIPEN
mode: full
execution_intent: converge
converge_target: ship
last_event: 948
style_contract: ded-4ae736e4
updated: "2026-09-16T11:22:16Z"
transition_from: VERIFY
---

# Active Work

T-246 DOING (SRC-007 / audit/5.md umbrella execution, 15 clauses: 15 verified, 0 open). R009 VERIFIED (E-927: production 71/71 incl. sections 11-17, RED A/B/C mutation-based, T-247/T-248/T-249 closed). R010 VERIFIED (E-928: normal 48/0, deterministic mutant red control A/B/C, git-HEAD oracle removed, both suites canonical). R011 VERIFIED (E-929: prerequisite preference persistence, zero post-success persistence, test-path-preference-ordering 55/0). R012 VERIFIED (E-931/E-932: shipped legacyWidePush/legacyIntake/__wintageTestHooks branches REALLY removed from shim.cjs, scalar-snapshot + intake-vs-render-frame harness semantics, identity-based 250,002/100,002 coverage, lazy-Proxy instrumentation (-72% wall time), red controls rebuilt as temporary source mutants with applied-assertions; full Run-Tests.ps1 ALL TESTS PASSED 2026-09-15). R013 VERIFIED (E-935/E-936: PERF-002 bounded repainter - persistent incremental root cursor replacing `[document, ...piercedRoots]`, explicit root/sheet/rule budgets (STYLE_ROOT_BUDGET 16 / STYLE_SHEET_BUDGET 32 / STYLE_RULE_BUDGET 500) separate from the DOM element budget, iterative persistent-stack CSSOM traversal replacing recursive walkRules, completion-safe sheetSeen generations, budgeted append fast path, FINITE style-lap membership via the registerStyleRoot/stamped-sequence epoch (a root pierced mid-lap is deferred to the next lap instead of joining the running one), root-level stripHoverSheets DELETED from production, lazy STYLE owner-text invalidation with zero querySelectorAll('style'), no unbounded CSSOM primitive left (static guards: no stripHoverSheets, no drainStyleRules(..., Infinity), single registration stamp); tools/test-repainter-budget.js wired into tests/Run-Tests.ps1 (Run-Tests.ps1:727) with 12 behavioural fixtures (250k rules, force-root 25k, STYLE-root 25k, nested CSSOM, DOM/style independence, force mid-lap root, STYLE mid-lap root, same-count replacement, 50k append, throwing CSSOM, STYLE owner text, 5k sheets) plus primitive-level RED A/RED B temporary-mutant controls (mutant 25,001 root advances / 250,000 rule reads vs fixed 63 / 500); full Run-Tests.ps1 ALL TESTS PASSED 2026-09-16). R015 VERIFIED (E-943/E-944/E-945: PERF-004 portable browser discovery cache + bounded preference scan. `tools/browser-discovery.ps1` holds the discovery DECISION in one place: a persistent candidate cache keyed by the case-insensitive PortableRoot, cheap path-existence re-validation of cached candidates (a vanished browser is dropped, never invented), invalidation only on cold/corrupt cache, changed root, an invalidated candidate or an explicit `-Rescan`; the walk itself is streamed (name filter during enumeration, no full-tree list) and keeps the historical shortest-path-first ordering, product validation and NO depth bound; preference matching is a chunked byte search carrying boundary overlap instead of `ReadAllText`, exact for both the escaped-backslash and slash forms; profile health carries an mtime+length fingerprint so an unchanged `Preferences` is never reopened. `tools/install-browsers.ps1` delegates both and publishes `PortableDiscovery` in its listing; `desktop/install.ps1` gained `-RescanBrowsers` (forwarded at the listing and apply call sites, and into re-apply children). Evidence: `tools/test-browser-cache.ps1` 41 PASS / 0 FAIL / 0 SKIP, canonical in `tests/Run-Tests.ps1`; child-process listing run1 discovery=walked, run2 discovery=cache with an identical profile set and zero recursive enumeration, run3 `-Rescan` walked; RED A (cache branch removed) reproduces walk-on-every-refresh and RED B (fingerprint shortcut removed) reproduces the re-read, each asserting the mutation applied; full `tests/Run-Tests.ps1` ALL TESTS PASSED 2026-09-16). Open findings: none. T-250 (locale LanguageLabel backfill) still TODO. T-244/T-243/T-242 shipped/done. T-238 and T-065 stay parked.



## Full matrix, current (E-900 verify)

tests/Run-Tests.ps1 ALL TESTS PASSED (2026-09-16, real Windows checkout, exit 0) including the new test-repainter-budget.js (R013) and test-browser-cache.ps1 (R015) entries. Node gates theme-switch, spa-exclude, perf-recovery, perf-lanes, perf-bounded, shim-payloads, electron-shim, electron-state, repainter-polarity, diag-counters, fs-retry, recovery-lifecycle, terminal-font, theme-packs, force-root-budget, check-css, check-wiki-mirror, build-desktop --check all PASS; node --check wintage.user.js PASS. Generated Electron payload (desktop/out/electron/<palette>/shim.cjs) re-proved aligned at E-936: bounded cursor present (drainStyleWork/registerStyleRoot), zero full-root snapshot, zero querySelectorAll('style'), zero recursive walkRules, zero stripHoverSheets, no unbudgeted CSSOM drain.

## SAIOPS is refused in this project, deliberately

`E-837` records it in full: fast validation demands a CONSECUTIVE E-ID chain, and this project carries two documented T-222-era stub-backfill gaps (E-703->E-717, E-718->E-722). E-774 relaxed that rule in the shared install; the saipen project has since reverted it and proved on a fixture that the relaxed rule accepts a forged log line. So E-865..E-888 are hand-appended with no `[op: ...]` id and the validator's `[saio]` provenance check lists them by design.

E-940 (one-time ledger repair, user-authorized) removed the three FLOOR/order defects that kept every mutating SAIOPS operation refused: the T-222-era LEDGER-GAP AMNESTY DECs were re-issued as E-937/E-938/E-939 so they are strictly increasing and, crucially, sit AT OR AFTER the gap they exempt (a DEC older than the gap it covers cannot bound it). Same text, same pairs, same scope -- ids and positions only; nothing was deleted (tree vs HEAD: 0 missing lines; the damaged intermediate is preserved under `.saipen/recovery/conflict-evidence/ledger-repair-20260916/`). Sealed-segment debt is untouched. Plan and write are live again for this project: E-941/E-942 (reconcile), E-943/E-944 (R015 build + transition), E-945 (R015 verify) were all written by the engine itself.

## Untracked files that must ride the next ship

desktop/targets/cinema4d/ and desktop/targets/notepadplusplus/ templates (T-243 era), tools/test-vscode-recovery.ps1 (SRC-006:R004, E-895), tools/test-reapply-intent.ps1 (SRC-006:R005, E-899/E-900), tools/test-logon-task-gui.ps1 (concurrent actor, E-897). Tracked-but-modified T-242 surfaces: desktop/install.ps1, desktop/modules/common.ps1, tests/Run-Tests.ps1, desktop/WintageInstaller.ps1 (concurrent), tools/install-electron.js (concurrent R007 WIP).
