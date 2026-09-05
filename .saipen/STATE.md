---
phase: SHIP
task: T-240
next_action: "PHASE SHIP T-240"
blocker: none
agent: opencode
saipen_version: 7
schema_version: 3
saipen_home: V:\___VAC\__K\__CODE\_AI_STUFF_AGENTIC\_SAIPEN
mode: full
execution_intent: converge
converge_target: ship
last_event: 864
style_contract: ded-4ae736e4
updated: "2026-09-05T00:16:00Z"
transition_from: REVIEW
---

# Active Work

T-234 executes the SRC-004 audit inbox layer (audit/2.md, 19 findings). Eighteen are terminal. The last one is split out as T-240 rather than claimed here. Nothing in this pass is shipped: no commit, no tag, no push. v1.31.0 (eebcacb) is the last published release.

## SRC-004 coverage, current

VERIFIED (18): R001 CORE-001 Terminal owned-state snapshot schema 2, R002 CORE-002 relocation-revert unpacked rename, R003 CORE-003 excluded-route quarantine + per-url latch, R004 CORE-004 stale theme-switch harness (shipped as T-236), R005 CORE-005 present-empty INI keys, R006 W2-001 windows-theme epoch finalize, R007 W2-002 OBS recovery parse + case, R008 W2-003 install-epoch first-create race, R009 W2-004 transaction boundary, R010 W2-005 checked + honest rollback, R011 W2-006 -WhatIf zero-write, R012 W2-007 paths.json serialized update, R013 PERF-001 recovery memory, R014 PERF-002 bounded mutation intake, R015 PERF-003 bounded light discovery, R016 PERF-004 shadow-root lifetime, R018 PERF-006 WCO frame latch, R019 PERF-007 injection epoch + CSS key.

UNKNOWN (1): R017 PERF-005, the GUI dispatch model. Split out as T-240 on the TODO board with its own verify bar, because that bar is process count and UI responsiveness during a real multi-target Apply -- a fixture would measure the fixture.

## Wave 5 (this pass): recovery scaled in RAM with the size of the app it protected

`tools/install-electron.js`. Recovery was stacked whole-binary Buffers across BOTH transaction layers. `captureRevertPreState` read the live archive, its `.bak`, the executable and the fuse backup into memory; `captureAppDir` then read the MOVED archive and the whole `app.asar.unpacked` tree into more Buffers, so the same archive was resident TWICE (`pre.movedAsar` and `appPre['app.asar']`); `installInPlace` held a full pre-patch Buffer in ADDITION to the `.bak` copy it had just written; and the parent PowerShell transaction was independently copying all of it to disk anyway. Measured by the audit at +192.1 MiB RSS for a 64 MiB archive plus a 64 MiB unpacked file.

Recovery is now a durable on-disk vault plus in-memory identity (size + streamed SHA-256 through a 64 KiB window). `sameSnapshot` compares size+digest instead of `Buffer.equals`, and `describePath` answers the byte-identical question without copying at all.

Three consequences beyond the memory, and they are why this shape was chosen: the vault is DURABLE, so recovery evidence survives an incomplete rollback and is named in every INCOMPLETE message; the relocation-revert rollback restores the app dir FIRST, because that snapshot owns the moved archive's bytes; and the in-place rollback reads the `.bak`, digest-verified against the live archive before the first write, so an unverified copy can never become the rollback authority.

Vault lifetime is deliberate: dropped on exit for a clean run, retained ONLY when the rollback could not put everything back. A rename-only stock->relocation apply copies nothing and creates no vault at all.

verify: `node tools/test-perf-recovery.js` 56 PASS (new gate, wired into Run-Tests and release.ps1). Relocation Revert peak RSS 16/64/256 MiB fixtures -> 47.1/48.0/48.3 MiB; in-place lane 16/256 -> 48.7/51.8 MiB. Seven instrument controls, each red for its own reason, source restored byte-identical by SHA256.

## Full matrix, current

17 Node gates PASS (check-css, theme-switch, spa-exclude, diag-counters, perf-bounded, perf-lanes, perf-recovery, fs-retry, repainter-polarity, electron-shim, theme-packs, shim-payloads, terminal-font, electron-state, check-wiki-mirror, terminal-ownership, recovery-lifecycle) + 4 `--check` contracts clean. `tests/Run-Tests.ps1` ALL TESTS PASSED, 14 of 14 tool suites exit 0, every release gate reachable. No temp vault leaked across a full run.

## SAIOPS is refused in this project, deliberately

`E-837` records it in full: fast validation demands a CONSECUTIVE E-ID chain, and this project carries two documented T-222-era stub-backfill gaps (E-703->E-717, E-718->E-722). E-774 relaxed that rule in the shared install; the saipen project has since reverted it and proved on a fixture that the relaxed rule accepts a forged log line. So E-837..E-850 are hand-appended with no `[op: ...]` id and the validator's `[saio]` provenance check lists them by design.

## Not shipped, and untracked files that must ride along

`tools/test-transaction-boundary.ps1`, `tools/test-perf-lanes.js`, `tools/test-perf-recovery.js`, `tools/test-terminal-ownership.js` and `tools/test-recovery-lifecycle.js` are untracked but wired into `Run-Tests`; a ship must stage them or the suite fails on a missing gate. `desktop/out` was regenerated in wave 4 (16 shims changed) -- it is gitignored, so a ship must not stage it but must not skip the rebuild either.
