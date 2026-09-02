# BOARD

## DOING
- [/] T-228 qBittorrent desktop target + native-font policy: new `qbittorrent` install target (unpacked Qt theme: config.json + stylesheet.qss + the two INI keys), and the Verdana_m1 face is NAMED by qbittorrent/obs/mpchc but never installed or removed. | verify: tools/test-ownership.ps1 66/66 PASS (13 qBittorrent assertions), Run-Tests ALL PASSED, build-desktop --check clean

## DONE
- [x] T-231 unattributed unshipped work in the tree (SHIP attribution gate): PERF-008 chunked fuse scanner, PERF-009 GDI disposal, W2-007 keep/finalize recovery ordering and three suites were dirty since the T-224 era with no ticket. Also two "gate nobody runs" defects: test-terminal-recorded-set aborted on its own subject (native stderr under EAP=Stop) and five suites were reachable from neither Run-Tests nor release.ps1. | verify: test-terminal-recorded-set 18/18 PASS (was 12+abort), 9/9 tool suites wired and green, Run-Tests ALL PASSED [E-765..E-766]
- [x] T-230 install-electron reported every Windows sharing violation as "the application is running": the release gate was red ~1 run in 20 on correct code and real users were told to close an app that was not open. Bounded fsRetry (EBUSY/EPERM/EACCES, 25-400ms, 6 attempts) on every mutating rename/copy in both transactions and their rollback steps. | verify: node tools/test-fs-retry.js 22/22 PASS, 16/16 clean electron-state runs (baseline 3 red in 12), FileShare::None control still refuses, 2 instrument controls red [E-762..E-764]
- [x] T-229 tools/test-perf-bounded.js ColorDialog assertion was stuck RED on correct code for a release cycle (it demanded the allocation INSIDE the try, which is the bug it should reject) and E-738 mis-triaged that red as a missing fix. Assertion repaired, suite wired into release.ps1. | verify: node tools/test-perf-bounded.js PASS, 2 instrument controls red, WintageInstaller.ps1 untouched [E-759..E-760]
- [x] T-227 CORE-015 silent catches in the hover CSSOM surgery + shadow pierce: 4 swallows now counted via DIAG/noteSuppressed, first error retained, `window.__wintageDiag()` reporter, shim prelude mirrors it. | verify: node tools/test-diag-counters.js 18/18 PASS, instrument control red on a reverted catch [E-748..E-750]
- [x] T-226 CORE-014 refused reload left a silent split brain (storage on the new palette, page painting the old): try/catch + one console.warn + `⟳ Apply pending theme` menu row gated on STORED_THEME_ID. | verify: node tools/test-theme-switch.js 40/40 PASS, control red on bare reload() [E-745..E-747]
- [x] T-225 CORE-013 setupRouteGuard not idempotent: a second run wrapped the first wrapper (double guard(), stacked listeners, unreachable layer one). window.__wintageRouteGuard latch. | verify: node tools/test-spa-exclude.js 26/26 PASS, control red with the latch removed [E-742..E-744]
- [x] T-224 SRC-002 (SHA e6534421) 22-ticket AUDIT_ALL_3 re-audit: triage + CORE-008 fix verified. 17/22 FIXED_LIVE, 5 LIVE, 0 unverifiable; user scope = CORE-008 only. | verify: node tools/test-theme-switch.js PASS, 9 JS gates green [E-738]
- [x] T-223 SRC-002 18-ticket AUDIT_ALL_3 repair shipped v1.29.0 (9ff576c): net-new CORE-002/004, W2-004/006, PERF-001/002/003/004/005/006/007; 8 pre-fixed verified. | verify: Run-Tests ALL PASSED, 9 JS gates PASS, v1.29.0 pushed main+tag [E-726..E-728]

## TODO

## BLOCKED
- [ ] T-065 YouTube Studio analytics bars disappear under the theme | blocker: requires authenticated user session
