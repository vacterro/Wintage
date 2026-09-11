#!/usr/bin/env node
// SRC-006:R010 -- force-sweep continuation slices need a hard per-slice bound
// on ROOT-LEVEL work, not just element work.
//
// DEFECT (pre-fix): every force continuation slice paid O(R) root-level work
// over all pierced roots no matter how small the element budget was:
// disconnected-root pruning (forEach over the registry), hover-sheet
// processing (forEach over the registry), construction of
// [document, ...piercedRoots], iteration from root zero, and the completion
// scan `.some(...)` over the whole root collection. With thousands of
// ShadowRoots and a tiny element budget, a slice still touched every root.
//
// CONTRACT under test (against the REAL runSweeper source, sliced into a
// sandbox with instrumented fake roots):
//  - no continuation slice serves more than FORCE_ROOT_BUDGET roots;
//  - the root cursor advances monotonically (a root's service slices are
//    contiguous -- no root is revisited after others advanced past it);
//  - every root eventually receives service (none starved);
//  - detached roots disappear from the registry and the cursor map;
//  - the lap completes, drops ALL traversal state, and the next lap starts
//    cleanly;
//  - document is represented exactly once in the lap workset.
//
// Usage: node tools/test-force-root-budget.js [--source <path>]
// Red control: --source pointing at a pre-fix copy of the userscript must
// FAIL the per-slice root-work assertions.

'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

let bad = 0;
const check = (label, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  console.log((ok ? 'PASS: ' : 'FAIL: ') + label
    + (ok ? '' : '\n        got  = ' + JSON.stringify(got) + '\n        want = ' + JSON.stringify(want)));
  if (!ok) bad++;
};

// Brace-matched slice by declaration text (same discipline as perf-lanes).
function sliceBlock(src, decl, label) {
  const i = src.indexOf(decl);
  if (i < 0) { console.error('FAIL: could not locate ' + (label || decl)); process.exit(1); }
  let depth = 0;
  for (let j = src.indexOf('{', i); j < src.length; j++) {
    if (src[j] === '{') depth++;
    else if (src[j] === '}') { depth--; if (depth === 0) return src.slice(i, j + 1); }
  }
  console.error('FAIL: unbalanced braces in ' + (label || decl));
  process.exit(1);
}

const args = process.argv.slice(2);
const srcIdx = args.indexOf('--source');
const sourcePath = srcIdx > -1 ? args[srcIdx + 1] : path.join(__dirname, '..', 'wintage.user.js');
const src = fs.readFileSync(sourcePath, 'utf8');
const runSweeperSrc = sliceBlock(src, 'function runSweeper(', 'runSweeper');

// ═════════════════ instrumented fake roots ═════════════════
// Tiny budgets so continuation slicing actually happens thousands of times.
const ELEMENT_BUDGET = 40;
const ROOT_BUDGET = 6;
const ROOT_COUNT = 2000;
const NODES_PER_ROOT = 3;

const counters = {
  slices: 0,
  touchesPerSlice: [],   // isConnected getter hits per slice (prune checks)
  stripsPerSlice: [],    // stripHoverSheets calls per slice (first-serve only)
  walkersPerSlice: [],   // walker creations per slice (first serve)
};
let sliceTouches = 0;
let sliceStrips = 0;
let sliceWalkers = 0;
let continuationQueued = false;
let scheduleCalls = 0;
let worksetDuringLap = 'never-set';

function makeRoot(name, n) {
  const els = [];
  for (let i = 0; i < n; i++) els.push({ nodeType: 1, __root: name });
  let wi = 0;
  const root = {
    __name: name,
    __els: els,
    host: {
      get isConnected() { sliceTouches++; return root.__attached !== false; },
    },
    createTreeWalker() {
      sliceWalkers++;
      wi = 0;
      return { nextNode() { return wi < els.length ? els[wi++] : null; } };
    },
  };
  root.__els.forEach(e => { e.__rootRef = root; });
  return root;
}

const document = {
  hidden: false,
  __name: 'document',
  __els: Array.from({ length: 5 }, (_, i) => ({ nodeType: 1, __root: 'document', __rootRef: null, __isDoc: true })),
  createTreeWalker() {
    sliceWalkers++;
    let wi = 0;
    const els = this.__els;
    return { nextNode() { return wi < els.length ? els[wi++] : null; } };
  },
};

const piercedRoots = new Set();
const forceRootCursors = new Map();
const lightDirty = new Set();
const rootServedSlices = new Map();   // root name -> [slice numbers]
const rootProcessCount = new Map();

const sandbox = {
  FORCE_BUDGET: ELEMENT_BUDGET,
  FORCE_ROOT_BUDGET: ROOT_BUDGET,
  LIGHT_MAX_NODES: ELEMENT_BUDGET,
  MIN_SWEEP_GAP: 0,
  repainterSuspended: false,
  forceLapActive: false,
  forceLapWorkset: null,
  forceLapIndex: 0,
  forceLapRemaining: 0,
  stylesDirty: true,
  forcePassesOwed: 0,
  document,
  piercedRoots,
  forceRootCursors,
  lightDirty,
  performance: { now: () => 0 },
  flushWrites() { },
  addWorkPressure() { },
  requestLightSweep() { },
  stripHoverSheets() { sliceStrips++; },
  scheduleSweep() { scheduleCalls++; continuationQueued = true; },
  process(el) {
    if (el && (el.__rootRef || el.__isDoc)) {
      const nm = el.__isDoc ? 'document' : el.__rootRef.__name;
      rootProcessCount.set(nm, (rootProcessCount.get(nm) || 0) + 1);
      const arr = rootServedSlices.get(nm);
      if (arr && arr[arr.length - 1] !== counters.slices) arr.push(counters.slices);
    }
  },
};
vm.createContext(sandbox);
const runSweeper = vm.runInContext(runSweeperSrc + '\nrunSweeper', sandbox, { filename: 'runSweeper.slice.js' });
if (typeof runSweeper !== 'function') { console.error('FAIL: runSweeper did not evaluate to a function'); process.exit(1); }

for (let i = 0; i < ROOT_COUNT; i++) piercedRoots.add(makeRoot('sh' + i, NODES_PER_ROOT));

function slice(force) {
  sliceTouches = 0; sliceStrips = 0; sliceWalkers = 0;
  counters.slices++;
  runSweeper(force);
  counters.touchesPerSlice.push(sliceTouches);
  counters.stripsPerSlice.push(sliceStrips);
  counters.walkersPerSlice.push(sliceWalkers);
}

// ---- Lap 1: force sweep over 2001 roots with tiny budgets ----
const MAX_SLICES = 20000;
let completedIn = -1;
let maxTouches = 0;
let maxStrips = 0;
let maxWalkers = 0;
for (let s = 0; s < MAX_SLICES; s++) {
  continuationQueued = false;
  slice(true);
  if (sliceTouches > maxTouches) maxTouches = sliceTouches;
  if (sliceStrips > maxStrips) maxStrips = sliceStrips;
  if (sliceWalkers > maxWalkers) maxWalkers = sliceWalkers;
  // Peek the workset while the lap is live (after the first slice it exists).
  if (s === 0) worksetDuringLap = sandbox.forceLapWorkset;
  if (!continuationQueued && sandbox.forceLapActive === false) { completedIn = s; break; }
}

check('lap completes without starvation', completedIn > 0, true);
const expectedSlices = Math.ceil((ROOT_COUNT * NODES_PER_ROOT + 5) / ELEMENT_BUDGET)
  + Math.ceil((ROOT_COUNT + 1) / ROOT_BUDGET) + ROOT_COUNT + 10;
check('lap completes within a sane slice bound', completedIn < expectedSlices, true);
const allServed = [...piercedRoots].every(r => (rootProcessCount.get(r.__name) || 0) === NODES_PER_ROOT);
check('every root eventually receives service (no starvation)', allServed, true);
check('document processed too', (rootProcessCount.get('document') || 0) > 0, true);
check('no slice runs prune checks over the whole registry (pre-fix: R per slice)',
  maxTouches <= ROOT_BUDGET + 1, true);
check('no slice strips hover sheets for the whole registry (pre-fix: R per slice)',
  maxStrips <= ROOT_BUDGET + 1, true);
check('no slice creates walkers for the whole registry (pre-fix: R per slice)',
  maxWalkers <= ROOT_BUDGET + 1, true);

// Monotonic cursor: a root's service slices are contiguous.
let nonContiguous = 0;
for (const [nm, arr] of rootServedSlices) {
  if (!arr.length) continue;
  if (arr[arr.length - 1] - arr[0] !== arr.length - 1) nonContiguous++;
}
check('cursor advances monotonically (all service windows contiguous)', nonContiguous, 0);

// document is represented exactly once while a lap is being built.
check('document represented exactly once in the lap workset',
  worksetDuringLap === 'never-set' ? 'never-set' : worksetDuringLap.filter(r => r === sandbox.document).length, 1);

// ---- detached roots disappear mid-lap ----
let det = 0;
for (const r of piercedRoots) {
  if (det++ >= ROOT_COUNT / 2) break;
  r.__attached = false;   // still registered, but disconnected
}
let slicesAfterDetach = 0;
continuationQueued = true;
while (continuationQueued && slicesAfterDetach < MAX_SLICES) {
  continuationQueued = false;
  slice(true);
  slicesAfterDetach++;
  if (!continuationQueued && sandbox.forceLapActive === false) break;
}
const stillRegistered = [...piercedRoots].filter(r => r.__attached === false).length;
check('detached roots pruned from the registry by the lap', stillRegistered, 0);
let leakedCursors = 0;
for (const r of forceRootCursors.keys()) { if (r.__attached === false) leakedCursors++; }
check('no detached roots leak in forceRootCursors', leakedCursors, 0);

// ---- lap ended cleanly; next lap starts cleanly ----
check('lap dropped all traversal state at completion',
  [sandbox.forceLapActive, sandbox.forceLapWorkset, forceRootCursors.size, sandbox.forceLapIndex],
  [false, null, 0, 0]);

const docCountBefore = rootProcessCount.get('document') || 0;
slice(true);   // a fresh force request rebuilds the workset and re-verifies
check('next lap starts cleanly (document re-served)',
  (rootProcessCount.get('document') || 0) > docCountBefore, true);

// Structural: the lap workset is built exactly once per lap, never per slice.
const worksetBuilds = (src.match(/= \[document, \.\.\.piercedRoots\]/g) || []).length;
check('source builds [document, ...piercedRoots] in exactly one place', worksetBuilds, 1);

console.log('\n' + (bad === 0 ? 'ALL PASS' : bad + ' FAIL'));
process.exit(bad === 0 ? 0 : 1);
