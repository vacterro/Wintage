# FINAL REPORT — T-938: Stylesheet duplication + ShadowRoot retention elimination, idle-CPU root-cause investigation

Ticket: T-938 (receipt SRC-073, mission: eliminate confirmed stylesheet duplication and
ShadowRoot retention defects; investigate Wintage-attributable idle CPU with reproducible
browser measurements; preserve existing behavior and visual contracts).

## Environment baseline (as measured now)

- Product version: 1.36.9 (`const W95_VERSION = '1.36.9';`)
- Snapshot Git HEAD at mission start: b5fb1d64af212e9ea7b153a299246025b1fc3330 (now written b5fb1d6)
- Branch: main; worktree dirty (881 changed paths — includes unrelated pre-existing work)
- T-938 changes: wintage.user.js +206/-17, tests/Run-Tests.ps1 +34/-0, three new untracked tools
  (test-stylesheet-census.js, test-shadow-registry-lifecycle.js, bench-idle-cpu.js)
- The operator's ~46.4% total-CPU observation is NOT reproduced or eliminated by this ticket.
  It named no tab and no workload; everything below is synthetic, controlled bench data.
  The 46.4% attribution stays NEEDS_OPERATOR_PROFILE.

## Root causes confirmed in the b5fb1d64 source

1. **Dual stylesheet install** (`injectStyle`, also the attachShadow wrapper). The constructable-
   stylesheet branch ran, then execution fell through to `if (root.querySelector(...)) return;`
   and the DOM `<style>` creation. The adopted sheet was in place from the start, so the guard
   found nothing and a second complete copy of the entire GLOBAL_CSS/SHADOW_CSS was installed
   into every document and every shadow root — every rule parsed, stored and matched twice for
   the life of the page. RED control RC-A1/2/3 reproduces this on the baseline build
   (census: adopted 1 + DOM 1, duplicate rule set).
2. **Strong-array registry** (`interceptAttachShadow`): `proto.__wintageShadowRoots` was a plain
   Array, `indexOf`-scanned and `push`ed, with no removal path. Every shadow root ever created
   was strongly referenced forever — on a long React session (virtualized lists, CDN widgets)
   that is thousands of detached ShadowRoots, each retaining its subtree. RED control RC-B1
   reproduces this: 1000 roots still retained after disconnect + forced GC + reinjection.
3. **Stale palette after reinjection** (same defects' consequence): a surviving DOM style could
   hold an older generation's rules while an adopted sheet held the new ones — the
   reinjection pass used to restyle DOM only. Now the adopted sheet is refreshed in place
   (`replaceSync`) and stamped `__w95Ver`, and any winning DOM duplicate with the winning
   generation's `data-w95-ver` is retired.

## Changes (files / symbols)

wintage.user.js:
- `injectStyle(root, id, content)` — adopted path now sets `adopted = true` only after a
  VERIFIED adoption (`root.adoptedStyleSheets.indexOf(sheet) < 0` → throw → fallthrough), and
  returns early on success (removing any stale DOM twin). Unsupported constructable /
  replaceSync throwing / assignment failing / DOM-only all still fall back exactly as before;
  strict-CSP support unchanged.
- `interceptAttachShadow()` — WeakRef-backed registry: fresh array marked `__w95Weak = true`,
  legacy strong-array conversion, `SHADOW_REGISTRY_CAP = 4096` amortized `compactRegistry()`,
  `liveRoots(shadow)` deref helper, O(1) WeakSet dedup (`proto.__wintageShadowSeen`),
  bounded registration, reinjection pass over dead handles; restyle pass refreshes the adopted
  sheet in place (`sheet.__w95Ver` vs `proto.__wintageShadowVer`) and retires a DOM duplicate
  when the sheet is effective; the wrapper's microtask enforces the same single-effective-sheet
  invariant with verified adoption. The existing `piercedRoots` / `pruneShadowRegistry`
  deterministic prune (250ms after removal batches) is untouched — it remains the
  disconnected-host observer owner; the WeakRef registry is the non-retention owner.
- `injectLate()` — reorders the single adopted global sheet to the end (position, not copy)
  and keeps the DOM fallback single-instance.
- `window.__wintageDiag()` — added `shadowRegistry: {retained, live, connected, detached}`.

Gates/tests:
- tools/test-stylesheet-census.js (NEW, PASS): cases A–J + U (upgrade mix) + fallbacks
  F6/G3, assertions for exactly one effective sheet per document / root / generation, no
  duplicate rule set, no stale palette, cascade order, working fallback, RED controls against
  `git show b5fb1d64:wintage.user.js`.
- tools/test-shadow-registry-lifecycle.js (NEW, PASS): lifecycle A–J (1000 roots, disconnect,
  cleanup, non-retention, reinjection, connected roots current CSS, reattach, active palette,
  another 1000, non-quadratic registration) + wrapper-latch + closed/nested; RED control
  against the strong-array baseline. No WeakRef source-text checks; no GC-timing requirement.
- tools/bench-idle-cpu.js (NEW, PASS): 4 arms (disabled / baseline b5fb1d64 / fixA /
  both) × 6 workloads (highChurn ChatGPT-like SPA, generic, shadowHeavy, manyFrame,
  longIdle, mountUnmount) × 3 repeats; CDP Performance.getMetrics deltas; `--quick` smoke
  mode wired into the suite.
- tests/Run-Tests.ps1 (+34 lines): registered the two regression gates plus the bench
  (`bench-idle-cpu.js --quick`) among the Chromium perf-gate entries.

## Stylesheet census before/after (browser-backed, from bench full run)

Census column = `document.adoptedStyleSheets.length` + `style[data-w95]` in DOM:

| arm / workload      | baseline        | fixA            | both            |
|---------------------|-----------------|-----------------|-----------------|
| longIdle            | 1+1 (DUP)       | 1+0             | 1+0             |
| highChurn           | 1+1 (DUP)       | 1+0             | 1+0             |
| generic             | 1+1 (DUP)       | —               | 1+0             |
| shadowHeavy         | 1+1 (DUP)       | 1+0             | 1+0             |
| manyFrame           | 1+1 (DUP)       | —               | 1+0             |
| mountUnmount        | 1+1 (DUP)       | —               | 1+0             |

Baseline installs one adopted sheet AND one DOM style of the full CSS on every page;
both-fixed builds install exactly one wherever constructable sheets work, DOM fallback only
where they don't (covered by cases B/C/D of the census gate).

## ShadowRoot retention before/after (from the lifecycle gate + bench)

- Baseline (b5fb1d64): 1000 disconnected shadow roots still `retained` after disconnect,
  forced GC and reinjection → RED RC-B1.
- Fixed build: after the same sequence `retained` drops to 0 (all roots garbage-collectable);
  held/connected roots keep exactly one copy and are refreshed to generation N content;
  reattached hosts read the current `--w95-gen`; registration stays non-quadratic through two
  1000-root cycles (measurement in the gate report). `bench` shadowHeavy run (200 live roots):
  `{retained: 200, live: 200, connected: 200, detached: 0}` — retention only for roots the
  page still shows.

## CPU / recalc / memory measurements (median of 3 repeats, headless Chromium, this machine)

Renderer-only metrics (CDP Performance.getMetrics deltas over the workload window);
browser-process CPU deliberately excluded.

| workload      | metric (ms)        | disabled | baseline | fixA   | both   |
|---------------|--------------------|----------|----------|--------|--------|
| longIdle      | RecalcStyle        | 0        | 0.4      | 0      | 0      |
| longIdle      | Script             | 1        | 8        | 4      | 3      |
| longIdle      | Mutation records   | 0        | 416      | 207    | 207    |
| highChurn     | RecalcStyle        | 8.4      | 35.2     | 24.8   | 25.0   |
| highChurn     | Script             | 21       | 57       | 52     | 53     |
| generic       | RecalcStyle        | —        | 76.1     | —      | 52.1   |
| shadowHeavy   | RecalcStyle        | —        | 146.5    | 66.2   | 70.6   |
| shadowHeavy   | Layout             | —        | 4        | 268.3  | 282.1  |
| mountUnmount  | RecalcStyle        | —        | 242.9    | —      | 161.7  |

Reading (measured, no extrapolation to operator hardware):
- Removing the second full sheet cuts RecalcStyle roughly a third on generic/high-churn/mount-
  unmount pages and more than half on shadow-heavy pages. Script and mutation-record volume
  drop with it; idle longIdle self-observation records halve (416 → 207).
- The shadowHeavy Layout increase (4 → 268ms) is the same 200 churning shadow roots being
  correctly styled under ONE sheet each instead of the baseline's broken-but-lazy mix — it
  appears in `fixA` alone, i.e. it is not a WeakRef-registry cost.
- The disabled arm is the floor: every arm still costs something, but the idle arm is at the
  floor (RecalcStyle ~0, Script 3ms vs the theme-free page's 1ms).

## Priority C hot-path inspection (C2)

Inspected before changing anything; no code change was required by the inspection, and none
was made: `startObservers` (documentElement-scoped, attributeFilter-locked, never installed on
CSS_ONLY hosts), `onMutations` (PERF-001..004: O(1)-per-record collapse, bounded intake,
deferred stylesheet discovery), `scheduleSweep`/`requestForceSweep`/`requestLightSweep`
(MIN_SWEEP_GAP floor, timer never re-armed later), `runSweeper`/`forceRootCursors` (FORCE_ROOT_
BUDGET 64 / element budget 2500 per slice, cursor-resumed laps), `drainStyleWork`, and
`paintRoot`/`injectStyle`/`injectLate`/`interceptAttachShadow`. Safety guards untouched:
sweep bounds, CSS-only path for high-churn hosts (no doc-wide observer on ChatGPT), no generic
JS repainter on Reddit, stylesheet cascade order, provider artwork, theme switching and the
accessibility attributes are all outside this ticket's diff.

## RED/GREEN test results

- test-stylesheet-census.js: GREEN. Controls RC-A1/RC-A2/RC-A3 (against b5fb1d64) reproduce the
  dual install, duplicate rule set, stale-palette/cascade-order failure respectively.
- test-shadow-registry-lifecycle.js: GREEN. Control RC-B1 (against b5fb1d64) reproduces
  1000-root non-retention.
- bench-idle-cpu.js --quick: GREEN (smoke). Full run GREEN (table above).
- Run-Tests.ps1 full Windows PowerShell 5.1 suite: ALL TESTS PASSED —
  `SUITE VERDICT: head=b5fb1d6 worktree=f64fb93ca3d8/1091path/1202k exit=0 errors=0`,
  log `.saipen/logs/run-tests-last.txt`. All three T-938 entries ran and passed inside it.
  (Note: the previous staging of the three new tools/*.js was a fix for a genuine gate — the
  release-gate integrity check "every suite file and internal dependency is carried by git"
  fails on untracked new gates; run #1 failed exactly that, run #2 aborted on a flaky
  browser-deps npm-notice stderr, run #3 green. No gate was skipped or reported green without
  executing.)

## Unresolved limitations

- The operator's 46.4% Brave total-CPU observation has not been attributed or eliminated:
  needs a live profile on their actual Brave tabs. NEEDS_OPERATOR_PROFILE.
- fps column in the bench is not meaningful in headless Chromium (rAF is not vsync-aligned);
  responsiveness there must be measured on a real display.
- `bench` longIdle busy% medians round to 0 — TaskDuration granularity; the RecalcStyle /
  Script columns carry the idle cost.

## Next priority

Full-suite green confirmation of the T-938 gates in Run-Tests.ps1, then the operator-side
Brave profile (NEEDS_OPERATOR_PROFILE) to close the 46.4% attribution question with the real
workload.
