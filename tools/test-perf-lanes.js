#!/usr/bin/env node
// PERF-002/003/004/006/007 (SRC-004): the repaint and injection lanes must be
// bounded by the budgets they advertise, and the numbers below are the audit's
// own measurements reproduced against the REAL source.
//
// Every one of these is invisible from the outside: the theme looks right, the
// gates stay green, and the machine just costs more. That is why each check
// counts primitive calls (getComputedStyle, querySelectorAll, insertCSS,
// requestAnimationFrame) rather than asserting on shape.
//
//   PERF-002 userscript: onMutations kept ITERATING addedNodes past the 500-node
//            budget -- 20,000 iterations to do 500 units of work.
//   PERF-002 shim: SCROLL_FIX/AD_BLOCK retained one queue entry per added node
//            and deduplicated by identity only, so a queued parent and its
//            descendants each walked the same subtree (1,000 nested roots ->
//            501,500 getComputedStyle calls / 499,500 descendant visits).
//   PERF-003: the light lane materialised the COMPLETE
//            `*:not([data-w95-done])` NodeList before consulting the budget
//            (12,000 matches for 2,500 units), and cleared its pending token
//            AFTER the pass, so one isolated request always cost two sweeps.
//   PERF-004: detached shadow roots stayed registered with the shared
//            MutationObserver (no per-target unobserve exists) and a
//            removal-only batch scheduled no cleanup at all.
//   PERF-006: WCO_FIX queued one full layout-reading scan per resize EVENT --
//            requestAnimationFrame does not coalesce separate callbacks.
//   PERF-007: did-navigate-in-page bumped the document epoch, so a later
//            frame-finish event re-injected into the same document and the sole
//            removal key advanced past the previous stylesheet.
//
// Usage: node tools/test-perf-lanes.js   (exit 0 = pass, 1 = fail)

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.join(__dirname, '..');
const USERSCRIPT = fs.readFileSync(path.join(ROOT, 'wintage.user.js'), 'utf8');
const SHIM = fs.readFileSync(path.join(ROOT, 'desktop', 'targets', 'electron', 'shim.cjs'), 'utf8');

let bad = 0;
// R012: lazy budget-const reader (the SCROLL_FIX budgets are regexed out of
// the real shim source when the fixtures below run).
const budgetConsts = () => ({
  traverse: Number((SHIM.match(/const TRAVERSE_BUDGET = (\d+)/) || [])[1]),
  intake: Number((SHIM.match(/const INTAKE_BUDGET = (\d+)/) || [])[1]),
  queue: Number((SHIM.match(/const ROOT_QUEUE_BUDGET = (\d+)/) || [])[1]),
  maxTreeRoots: Number((SHIM.match(/const MAX_TREE_ROOTS = (\d+)/) || [])[1]),
  styling: Number((SHIM.match(/const BUDGET = (\d+)/) || [])[1])
});
const check = (label, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  console.log((ok ? 'PASS: ' : 'FAIL: ') + label
    + (ok ? '' : '\n        got  = ' + JSON.stringify(got) + '\n        want = ' + JSON.stringify(want)));
  if (!ok) bad++;
};

// Brace-matched slice by declaration text. The same discipline the other
// real-source gates here use: no regex that would need escaping for every
// backtick and brace inside the body.
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

function literalAfter(src, decl) {
  const i = src.indexOf(decl);
  if (i < 0) { console.error('FAIL: payload not found: ' + decl); process.exit(1); }
  const start = i + decl.length;
  const end = src.indexOf('\n})()`', start);
  if (end < 0) { console.error('FAIL: no closing backtick for ' + decl); process.exit(1); }
  return src.slice(start, end + '\n})()'.length);
}

// ══ A minimal element/document model ════════════════════════════════════════
// Only what the code under test actually touches. Counters live on the model so
// a check can read the primitive call count instead of trusting a shape.
function makeDom(counters) {
  let idSeq = 0;
  function makeEl(tag) {
    const el = {
      nodeType: 1,
      tagName: (tag || 'DIV').toUpperCase(),
      __id: ++idSeq,
      children: [],
      parentNode: null,
      isConnected: true,
      attrs: {},
      style: {
        setProperty() { }, removeProperty() { }, getPropertyValue() { return ''; }
      },
      hasAttribute(n) { return Object.prototype.hasOwnProperty.call(el.attrs, n); },
      getAttribute(n) { return el.attrs[n]; },
      setAttribute(n, v) { el.attrs[n] = String(v); },
      removeAttribute(n) { delete el.attrs[n]; },
      matches() { return false; },
      closest() { return null; },
      querySelector() { return null; },
      querySelectorAll() { counters.qsa++; return []; },
      getElementsByTagName() { return el.__descendants(); },
      getBoundingClientRect() {
        counters.rect++;
        return { top: 0, bottom: 10, left: 0, right: 10, width: 10, height: 10 };
      },
      contains(other) {
        for (let p = other; p; p = p.parentNode) if (p === el) return true;
        return false;
      },
      append(child) { child.parentNode = el; el.children.push(child); return child; },
      __descendants() {
        const out = [];
        const walk = n => { for (const c of n.children) { out.push(c); walk(c); } };
        walk(el);
        return out;
      }
    };
    return el;
  }
  const documentElement = makeEl('html');
  const document = {
    documentElement,
    hidden: false,
    nodeType: 9,
    querySelectorAll(sel) { counters.qsa++; counters.lastSel = sel; return counters.qsaResult || []; },
    querySelector() { return null; },
    addEventListener() { },
    createElement: makeEl,
    createTreeWalker() { let done = false; return { nextNode() { if (done) return null; done = true; return documentElement; } }; },
    styleSheets: { length: 0 },
    adoptedStyleSheets: null
  };
  return { document, documentElement, makeEl };
}

// ══ 1. PERF-002 (userscript): addedNodes intake stops AT the budget ══════════
{
  const counters = { qsa: 0, rect: 0 };
  const { document, makeEl } = makeDom(counters);
  const stats = { processCalls: 0, indexReads: 0, forceRequests: 0, lightRequests: 0, shadowPrunes: 0 };

  // The measurement that matters is how many addedNodes entries the loop TOUCHES.
  // A getter-backed array-like counts exactly that; the pre-fix loop read every
  // one of the 20,000, the fixed loop stops at the budget.
  const nodes = [];
  for (let i = 0; i < 20000; i++) nodes.push(makeEl('div'));
  const addedNodes = { length: nodes.length };
  for (let i = 0; i < nodes.length; i++) {
    Object.defineProperty(addedNodes, i, { get() { stats.indexReads++; return nodes[i]; }, enumerable: true });
  }
  addedNodes[Symbol.iterator] = function* () {
    for (let i = 0; i < nodes.length; i++) yield addedNodes[i];
  };

  const ctx = {
    console,
    performance: { now: () => 0 },
    Date,
    Set, Map, WeakMap, Symbol,
    document,
    setTimeout: (fn) => { fn(); return 1; },
    clearTimeout: () => { },
    repainterSuspended: false,
    noteMutationPressure: () => false,
    pendingMuts: [],
    debounceTimer: null,
    attrCooldown: new WeakMap(),
    ADDED_NODE_BUDGET: 500,
    stylesDirty: false,
    process: () => { stats.processCalls++; },
    flushWrites: () => { },
    requestForceSweep: () => { stats.forceRequests++; },
    requestLightSweep: () => { stats.lightRequests++; },
    markLightDirty: () => { },
    requestShadowPrune: () => { stats.shadowPrunes++; },
    addWorkPressure: () => { }
  };
  vm.createContext(ctx);
  vm.runInContext(sliceBlock(USERSCRIPT, '  function onMutations(mutations) {')
    + '\nthis.__onMutations = onMutations;', ctx);

  ctx.__onMutations([{ type: 'childList', target: document.documentElement, addedNodes, removedNodes: { length: 0 } }]);

  check('PERF-002 userscript: intake stops AT the 500-node budget (was 20,000 reads)',
    stats.indexReads <= 501, true);
  check('PERF-002 userscript: the budget still does its 500 units of work',
    stats.processCalls > 0 && stats.processCalls <= 500, true);
  check('PERF-002 userscript: truncation requests exactly one force continuation',
    stats.forceRequests, 1);
}

// ══ 2. PERF-004 (userscript): a removal-only batch schedules cleanup ═════════
{
  const counters = { qsa: 0, rect: 0 };
  const { document, makeEl } = makeDom(counters);
  const stats = { shadowPrunes: 0, processCalls: 0 };
  const ctx = {
    console,
    performance: { now: () => 0 },
    Date, Set, Map, WeakMap,
    document,
    setTimeout: (fn) => { fn(); return 1; },
    clearTimeout: () => { },
    repainterSuspended: false,
    noteMutationPressure: () => false,
    pendingMuts: [],
    debounceTimer: null,
    attrCooldown: new WeakMap(),
    ADDED_NODE_BUDGET: 500,
    stylesDirty: false,
    process: () => { stats.processCalls++; },
    flushWrites: () => { },
    requestForceSweep: () => { },
    requestLightSweep: () => { },
    markLightDirty: () => { },
    requestShadowPrune: () => { stats.shadowPrunes++; },
    addWorkPressure: () => { }
  };
  vm.createContext(ctx);
  vm.runInContext(sliceBlock(USERSCRIPT, '  function onMutations(mutations) {')
    + '\nthis.__onMutations = onMutations;', ctx);

  ctx.__onMutations([{
    type: 'childList',
    target: document.documentElement,
    addedNodes: { length: 0, [Symbol.iterator]: function* () { } },
    removedNodes: { length: 3 }
  }]);
  check('PERF-004: a removal-only batch schedules ONE bounded shadow prune (was zero)',
    stats.shadowPrunes, 1);

  stats.shadowPrunes = 0;
  ctx.__onMutations([{
    type: 'childList',
    target: document.documentElement,
    addedNodes: { length: 0, [Symbol.iterator]: function* () { } },
    removedNodes: { length: 0 }
  }]);
  check('PERF-004: a batch with no removals schedules no prune', stats.shadowPrunes, 0);
}

// ══ 3. PERF-004 (userscript): the prune rebuilds the shared registration ════
{
  const counters = { qsa: 0, rect: 0 };
  const { document, makeEl } = makeDom(counters);
  const obs = { observed: [], disconnects: 0, taken: 0 };
  const liveHost = makeEl('div');
  const deadHost = makeEl('div');
  deadHost.isConnected = false;
  const liveRoot = { host: liveHost };
  const deadRoot = { host: deadHost };
  const piercedRoots = new Set([liveRoot, deadRoot]);
  const forceRootCursors = new Map([[liveRoot, {}], [deadRoot, {}]]);
  const pendingRecords = [{ type: 'attributes', target: makeEl('div') }];
  const stats = { onMutations: 0, deliveredRecords: 0 };

  const ctx = {
    console, document, Set, Map,
    setTimeout: (fn) => { fn(); return 1; },
    repainterSuspended: false,
    CSS_ONLY_MODE: false,
    piercedRoots,
    forceRootCursors,
    SHADOW_OBS_OPTS: { childList: true, subtree: true, attributes: true, attributeFilter: ['class'] },
    shadowObserver: {
      observe(root, opts) { obs.observed.push({ root, opts }); },
      disconnect() { obs.disconnects++; },
      takeRecords() { obs.taken++; return pendingRecords; }
    },
    onMutations(records) { stats.onMutations++; stats.deliveredRecords += records.length; }
  };
  vm.createContext(ctx);
  vm.runInContext([
    'let shadowPruneQueued = false;',
    sliceBlock(USERSCRIPT, '  function pruneShadowRegistry() {'),
    sliceBlock(USERSCRIPT, '  function requestShadowPrune() {'),
    'this.__prune = pruneShadowRegistry; this.__request = requestShadowPrune;'
  ].join('\n'), ctx);

  ctx.__prune();
  check('PERF-004: the disconnected root is dropped from piercedRoots', piercedRoots.has(deadRoot), false);
  check('PERF-004: the connected root SURVIVES the prune', piercedRoots.has(liveRoot), true);
  check('PERF-004: its force cursor is dropped too', forceRootCursors.has(deadRoot), false);
  check('PERF-004: the shared observer registration is rebuilt (no per-target unobserve exists)',
    obs.disconnects, 1);
  check('PERF-004: only the surviving connected root is re-observed',
    obs.observed.map(o => o.root === liveRoot), [true]);
  check('PERF-004: the rebuild re-observes with the SAME options object',
    obs.observed[0] && obs.observed[0].opts === ctx.SHADOW_OBS_OPTS, true);
  check('PERF-004: pending records are taken before the disconnect, not dropped', obs.taken, 1);
  check('PERF-004: and handed back to the mutation handler', stats.deliveredRecords, 1);

  // A prune with nothing detached must not churn the observer.
  obs.disconnects = 0; obs.observed.length = 0; obs.taken = 0;
  ctx.__prune();
  check('PERF-004: a prune with nothing detached leaves the observer alone', obs.disconnects, 0);
}

// ══ 4. PERF-003 (userscript): one isolated light request = ONE sweep ════════
{
  const stats = { sweeps: 0, timers: 0, forceArg: [] };
  let clock = 0;
  const timers = [];
  const ctx = {
    console, Set, Map,
    Date: { now: () => clock },
    document: { hidden: false },
    setTimeout: (fn, d) => { stats.timers++; timers.push({ fn, at: clock + d }); return timers.length; },
    clearTimeout: () => { },
    repainterSuspended: false,
    sweepTimer: null,
    sweepPlannedAt: 0,
    lastSweepEnd: 0,
    forcePassesOwed: 0,
    lightPending: false,
    forceLapActive: false,
    MIN_SWEEP_GAP: 1000,
    runSweeper: (force) => { stats.sweeps++; stats.forceArg.push(Boolean(force)); },
    requestForceSweep: () => { }
  };
  vm.createContext(ctx);
  vm.runInContext([
    sliceBlock(USERSCRIPT, '  function scheduleSweep(delay, kind) {'),
    sliceBlock(USERSCRIPT, '  function markLightDirty(el) {'),
    sliceBlock(USERSCRIPT, '  function requestLightSweep() {'),
    'const lightDirty = new Set();',
    'this.__requestLight = requestLightSweep; this.__lightDirty = lightDirty;'
  ].join('\n'), ctx);

  ctx.__requestLight();
  // Drain the timer queue the way a real event loop would, advancing the clock.
  let guard = 0;
  while (timers.length && guard++ < 20) {
    const t = timers.shift();
    clock = Math.max(clock, t.at);
    t.fn();
  }
  check('PERF-003: one isolated light request runs exactly ONE sweep (was 2)', stats.sweeps, 1);
  check('PERF-003: and arms exactly one timer (was 2)', stats.timers, 1);
  check('PERF-003: the pass it caused is a LIGHT pass', stats.forceArg, [false]);
}

// ══ 5. PERF-003 (userscript): light discovery is the registry, not a selector ═
{
  const counters = { qsa: 0, rect: 0, qsaResult: [] };
  const { document, makeEl } = makeDom(counters);
  // A settled page whose negative selector would still return 12,000 matches --
  // the exact shape the audit measured. The fixed lane must not ask for it.
  counters.qsaResult = [];
  for (let i = 0; i < 12000; i++) counters.qsaResult.push(makeEl('div'));

  const stats = { processCalls: 0, lightRequests: 0, forceRequests: 0, styleDrains: 0 };
  const lightDirty = new Set();
  for (let i = 0; i < 3000; i++) lightDirty.add(makeEl('div'));

  const ctx = {
    console, Set, Map,
    performance: { now: () => 0 },
    Date: { now: () => 0 },
    document,
    setTimeout: () => 1,
    clearTimeout: () => { },
    repainterSuspended: false,
    piercedRoots: new Set(),
    forceRootCursors: new Map(),
    stylesDirty: false,
    forceLapActive: false,
    forcePassesOwed: 0,
    FORCE_BUDGET: 2500,
    // SRC-006:R010: the light lane budgets through LIGHT_MAX_NODES and the
    // force lane keeps its lap workset + cursor state outside the slice.
    LIGHT_MAX_NODES: 2500,
    FORCE_ROOT_BUDGET: 64,
    forceLapWorkset: null,
    forceLapIndex: 0,
    forceLapRemaining: 0,
    lightDirty,
    // R013 / PERF-002: the light pass no longer strips hover sheets per root.
    // Dirty style work is scheduler debt drained as ONE bounded slice, so the
    // style lane is stubbed and counted here (a reintroduced per-root strip
    // call has no stub and would raise ReferenceError).
    STYLE_SHEET_BUDGET: 32,
    STYLE_RULE_BUDGET: 500,
    forceLapId: 0,
    forceLapDeferredRoots: new Set(),
    drainStyleWork: () => { stats.styleDrains++; return { done: true, changed: false }; },
    process: () => { stats.processCalls++; },
    flushWrites: () => { },
    addWorkPressure: () => { },
    scheduleSweep: () => { },
    requestLightSweep: () => { stats.lightRequests++; },
    requestForceSweep: () => { stats.forceRequests++; },
    MIN_SWEEP_GAP: 1000
  };
  vm.createContext(ctx);
  vm.runInContext(sliceBlock(USERSCRIPT, '  function runSweeper(force) {')
    + '\nthis.__runSweeper = runSweeper;', ctx);

  ctx.__runSweeper(false);
  check('PERF-003: the light lane never runs the document-wide negative selector',
    counters.qsa, 0);
  check('R013: the light pass drains ONE bounded style slice, not per-root strips',
    stats.styleDrains, 1);
  check('PERF-003: it does exactly its budget of work from the registry',
    stats.processCalls, 2500);
  check('PERF-003: the unfinished remainder stays queued for the next pass',
    lightDirty.size, 500);
  check('PERF-003: an incomplete light pass re-arms itself', stats.lightRequests, 1);

  // Second pass drains the rest and stops.
  stats.processCalls = 0; stats.lightRequests = 0; stats.styleDrains = 0;
  ctx.__runSweeper(false);
  check('PERF-003: the next pass drains the remainder', stats.processCalls, 500);
  check('PERF-003: a completed light pass does not re-arm', stats.lightRequests, 0);
  check('PERF-003: and still never touched the selector', counters.qsa, 0);
  check('R013: a second light pass does not restart style enumeration',
    stats.styleDrains, 1);
}

// ══ 6. PERF-003: overflow promotes ONCE to the force lane ═══════════════════
{
  const stats = { forceRequests: 0 };
  const limit = Number((USERSCRIPT.match(/const LIGHT_DIRTY_MAX = (\d+)/) || [])[1]);
  check('PERF-003: the light registry declares a hard cap', Number.isFinite(limit) && limit > 0, true);
  const ctx = {
    console, Set,
    repainterSuspended: false,
    requestForceSweep: () => { stats.forceRequests++; }
  };
  vm.createContext(ctx);
  vm.runInContext([
    'const LIGHT_DIRTY_MAX = ' + limit + ';',
    'const lightDirty = new Set();',
    sliceBlock(USERSCRIPT, '  function markLightDirty(el) {'),
    'this.__mark = markLightDirty; this.__dirty = lightDirty;'
  ].join('\n'), ctx);
  for (let i = 0; i < limit + 50; i++) ctx.__mark({ nodeType: 1, __i: i });
  check('PERF-003: the registry never grows past its cap', ctx.__dirty.size, limit);
  check('PERF-003: overflow is promoted to the force lane', stats.forceRequests, 50);
}

// ══ 7. PERF-002 (shim): SCROLL_FIX collapses nested roots ═══════════════════
function runScrollFix(mutantSrc) {
  const counters = { qsa: 0, rect: 0, gcs: 0 };
  const { document, documentElement, makeEl } = makeDom(counters);
  let observerCb = null;
  let seenSink = null;
  const frames = [];
  const ctx = {
    console,
    window: {},
    document,
    getComputedStyle: (el) => {
      counters.gcs++;
      if (seenSink) seenSink.add(el);
      return { overflowY: 'visible', overflowX: 'visible' };
    },
    requestAnimationFrame: fn => { frames.push(fn); return frames.length; },
    setTimeout: () => 1,
    clearTimeout: () => { },
    MutationObserver: class { constructor(cb) { observerCb = cb; } observe() { } disconnect() { } }
  };
  ctx.window.window = ctx.window;
  ctx.window.requestAnimationFrame = ctx.requestAnimationFrame;
  vm.createContext(ctx);
  // mutantSrc (TARGET B): a temporary in-memory mutation of the SCROLL_FIX
  // source; when absent, the shipped payload runs unmodified.
  const payload = eval('`' + (mutantSrc || literalAfter(SHIM, 'const SCROLL_FIX = `')) + '`');
  vm.runInContext(payload, ctx);
const drain = (max) => {
     let n = 0;
     while (frames.length && n++ < max) frames.shift()();
     return n;
   };
   const drainOneFrame = () => drain(1);
   drain(50); // initial documentElement pass
   return {
     counters, documentElement, makeEl,
     deliver: recs => observerCb(recs),
     drain, drainOneFrame, frames,
     markSeen: sink => { seenSink = sink; },
     win: ctx.window
   };
}

{
  // 1,000 NESTED added roots: parent and every descendant queued in one batch.
  const h = runScrollFix();
  let node = h.documentElement;
  const chain = [];
  for (let i = 0; i < 1000; i++) { node = node.append(h.makeEl('div')); chain.push(node); }
  const before = h.counters.gcs;
  h.deliver(chain.map(n => ({ type: 'childList', target: n.parentNode, addedNodes: [n] })));
  const frames = h.drain(4000);
  const cost = h.counters.gcs - before;
  // Pre-fix: 501,500 getComputedStyle calls over 2,508 frames. The collapsed
  // queue walks the shared subtree once, so the cost is linear in the chain.
  check('PERF-002 shim: 1,000 nested roots cost a LINEAR walk, not a quadratic one',
    cost <= 3000, true);
  check('PERF-002 shim: and it settles in a bounded number of frames (was 2,508)',
    frames <= 60, true);
}

{
  // 20,000 FLAT added roots: intake must not retain one queue entry per node.
  // The observable proof that overflow is ONE continuation token rather than a
  // per-node queue is that the continuation re-walks from documentElement: an
  // element that was NEVER in the batch gets visited. Without the cap the queue
  // holds 20,000 entries and that off-batch element is never reached.
  const h = runScrollFix();
  const offBatch = h.documentElement.append(h.makeEl('section'));
  h.drain(50);
  const seen = new Set();
  const flat = [];
  for (let i = 0; i < 20000; i++) flat.push(h.documentElement.append(h.makeEl('div')));
  const before = h.counters.gcs;
  h.markSeen(seen);
  h.deliver(flat.map(n => ({ type: 'childList', target: h.documentElement, addedNodes: [n] })));
  const frames = h.drain(4000);
  const cost = h.counters.gcs - before;
  check('PERF-002 shim: a 20,000-root burst stays bounded (was 20,001 extra reads)',
    cost <= 25000, true);
  // R012 reworks intake into bounded frames; the burst now drains over ~500
  // small frames (intake + styling), still far below one frame per node pair.
  // The superset property (off-batch coverage) is asserted separately below.
  check('PERF-002 shim: the overflow continuation is ONE re-walk, not one entry per node',
    frames <= 1000, true);
  check('PERF-002 shim: and that re-walk covers an element that was never in the batch',
    seen.has(offBatch), true);
}

{
  const src = SHIM;
  check('PERF-002 shim: the root queue is drained by a head index, not Array.shift',
    /const takeRoot = \(\) => \{/.test(src) && !/trees\.shift\(\)/.test(src), true);
  check('PERF-002 shim: the root queue declares a hard cap',
    /const MAX_TREE_ROOTS = \d+/.test(src), true);
  check('PERF-002 shim: the dirty set declares a hard cap',
    /const MAX_DIRTY = \d+/.test(src), true);
}

// ══ 8. (retired): AD_BLOCK removed for FreeBuff ToS compliance ══════════════
{
  check('PERF-002 shim: AD_BLOCK retired for FreeBuff ToS compliance', true, true);
}


// ══ 9. PERF-006 (shim): one geometry scan per rendered frame ════════════════
{
  const counters = { qsa: 0, rect: 0 };
  const { document } = makeDom(counters);
  const listeners = {};
  const wcoListeners = {};
  const frames = [];
  const ctx = {
    console,
    document,
    navigator: {
      windowControlsOverlay: {
        visible: true,
        getTitlebarAreaRect: () => ({ x: 0, y: 0, width: 500, height: 32 }),
        addEventListener: (n, fn) => { (wcoListeners[n] || (wcoListeners[n] = [])).push(fn); }
      }
    },
    window: {
      innerWidth: 1000,
      addEventListener: (n, fn) => { (listeners[n] || (listeners[n] = [])).push(fn); }
    },
    requestAnimationFrame: fn => { frames.push(fn); return frames.length; },
    setTimeout: () => 1
  };
  ctx.window.window = ctx.window;
  ctx.window.navigator = ctx.navigator;
  ctx.window.innerWidth = 1000;
  vm.createContext(ctx);
  vm.runInContext(eval('`' + literalAfter(SHIM, 'const WCO_FIX = `') + '`'), ctx);

  const scansBefore = counters.qsa;
  for (let i = 0; i < 100; i++) listeners.resize.forEach(fn => fn());
  check('PERF-006: 100 same-frame resize events queue exactly ONE frame (was 100)',
    frames.length, 1);
  while (frames.length) frames.shift()();
  check('PERF-006: and perform exactly ONE geometry scan',
    counters.qsa - scansBefore, 1);

  // A mixed burst is still one frame.
  const scans2 = counters.qsa;
  for (let i = 0; i < 40; i++) listeners.resize.forEach(fn => fn());
  for (let i = 0; i < 40; i++) (wcoListeners.geometrychange || []).forEach(fn => fn());
  check('PERF-006: a mixed resize + geometrychange burst is still one frame', frames.length, 1);
  while (frames.length) frames.shift()();
  check('PERF-006: and still one scan', counters.qsa - scans2, 1);

  // Events spread across rendered frames still get their own scan each.
  const scans3 = counters.qsa;
  for (let f = 0; f < 5; f++) {
    listeners.resize.forEach(fn => fn());
    while (frames.length) frames.shift()();
  }
  check('PERF-006: events across 5 rendered frames still get 5 scans (latest geometry wins)',
    counters.qsa - scans3, 5);
}

// ══ 10. PERF-007 (shim): same-document navigation does not re-inject ════════
function runInjector() {
  const stats = { inserts: 0, removes: 0, exec: 0, keys: [], removedKeys: [] };
  const handlers = {};
  let keySeq = 0;
  const wc = {
    getURL: () => 'https://app.example/main',
    executeJavaScript: () => { stats.exec++; return Promise.resolve('ok'); },
    insertCSS: () => { stats.inserts++; const k = 'key-' + (++keySeq); stats.keys.push(k); return Promise.resolve(k); },
    removeInsertedCSS: (k) => { stats.removes++; stats.removedKeys.push(k); return Promise.resolve(); },
    on: (name, fn) => { (handlers[name] || (handlers[name] = [])).push(fn); }
  };
  const ctx = {
    console, Promise,
    app: { on: (_name, fn) => { ctx.__created = fn; } },
    SCROLL_FIX: '1', WCO_FIX: '1', REPAINTER_FIX: '1', SCROLL_INTENT_FIX: '1',
    THEME_REASSERT_FIX: '1',
    IS_FREEBUFF: false,
    CLAUDE_VIEW: /never-matches-this/,
    CLAUDE_FOREGROUND_CSS: '',
    css: 'body{}',
    stamp: () => { }
  };
  vm.createContext(ctx);
  // sliceBlock stops at the arrow function's closing brace; the call's own `);`
  // is not part of it.
  vm.runInContext(sliceBlock(SHIM, "    app.on('web-contents-created'") + ');', ctx);
  ctx.__created(null, wc);
  const fire = name => (handlers[name] || []).forEach(fn => fn(null, 'https://app.example/main', true));
  return { stats, fire, wc };
}

{
  const h = runInjector();
  h.fire('dom-ready');
  h.fire('did-finish-load');
  h.fire('did-frame-finish-load');
  check('PERF-007: the three events of ONE document inject once', h.stats.inserts, 1);
  h.fire('did-navigate-in-page');
  h.fire('did-frame-finish-load');
  check('PERF-007: a same-document in-page navigation does NOT re-inject (was 2)',
    h.stats.inserts, 1);
  check('PERF-007: and costs no extra executeJavaScript round trips (was 8)',
    h.stats.exec, 4);
}

{
  // A real navigation must still reinject exactly once, and must retire the
  // previous stylesheet by key BEFORE installing the replacement.
  const h = runInjector();
  h.fire('dom-ready');
  return new Promise(resolve => setImmediate(resolve)).then(() => {
    h.fire('did-navigate');
    h.fire('dom-ready');
    return new Promise(resolve => setImmediate(resolve));
  }).then(() => {
    check('PERF-007: a true did-navigate reinjects exactly once more', h.stats.inserts, 2);
    check('PERF-007: the previous stylesheet is retired by its own key',
      h.stats.removedKeys, ['key-1']);
    check('PERF-007: the stored key is the NEW one after the replacement lands',
      h.wc.__wintageCssKey, 'key-2');

    check('PERF-007: did-navigate-in-page is not wired to the epoch at all',
      /did-navigate-in-page/.test(SHIM) && /injectedEpoch\+\+/.test(SHIM)
        ? !/did-navigate-in-page[^\n]*injectedEpoch\+\+/.test(SHIM) : true, true);

    // R012 fixtures + red control. Called here (inside the settled chain) so
    // every top-level const in this file is initialised; the R012 budget
    // constants are declared near the bottom of the file.
    runR012();
    runR012Red();

    console.log('\n' + (bad === 0 ? 'perf lanes test PASS' : bad + ' FAILURE(S)'));
    process.exit(bad === 0 ? 0 : 1);
  });
}

// ═══════════════ R012 / PERF-001 (SRC-007): SCROLL_FIX budget closure ═════
// The upstream styling loop has BUDGET=200, but pre-fix two earlier operations
// could still perform arbitrary synchronous work before that budget meant
// anything: nextTreeNode enumerated and pushed EVERY child of a popped node
// (one node with 250,000 direct children = 250,000 array touches to style ONE
// node), and the MutationObserver callback synchronously looped every delivered
// record AND every addedNodes entry of every childList record (queue caps only
// bounded RETENTION, never INTAKE). Every fixture below counts deterministic
// primitives against the real payload; no assertion uses wall-clock timing.

function instrumentChildren(el, stats) {
   // Use a Proxy for efficient lazy counting
   const real = Array.isArray(el.children) ? el.children : [];
   el.__kids = real;
   el.append = (c) => { c.parentNode = el; real.push(c); return c; };
   
   // Create a proxy that counts actual accesses without creating N property descriptors
   const handler = {
     get(target, prop, receiver) {
       // Handle length property access
       if (prop === 'length') {
         // Optionally count length accesses if needed for the test
         // stats.childIndexAccesses++; // Uncomment if length accesses should count
         return Reflect.get(target, prop, receiver);
       }
       
     // Handle index access (numeric properties); guard symbols (for..of reads
     // Symbol.iterator through the proxy) and non-index strings.
     if (typeof prop === 'string' && !isNaN(prop)) {
       const index = Number(prop);
       if (Number.isInteger(index) && index >= 0 && index < target.length) {
         stats.childIndexAccesses++;
       }
       return Reflect.get(target, prop, receiver);
     }
       
       // For all other properties/methods, delegate to the original array
       return Reflect.get(target, prop, receiver);
     }
   };
   
   Object.defineProperty(el, 'children', {
     get() {
       // Return a new proxy each time to ensure we capture all accesses
       // Alternatively, we could cache it, but creating a new one is safer
       return new Proxy(real, handler);
},
      configurable: true
   });
}

function instrumentRecords(records, stats) {
   // Lazily instrumented records: records are only accessed through a counted proxy,
   // so any bulk consumption of a large record batch lights the counter up.
   // Any records added BEFORE instrumentation are adopted so the shape the
   // traversal sees is unchanged.
   const real = Array.isArray(records) ? records : [];
   // Create a proxy that counts actual record accesses without creating N property descriptors
   const handler = {
     get(target, prop, receiver) {
       // Handle length property access
       if (prop === 'length') {
         // Optionally count length accesses if needed for the test
         // stats.recordIndexAccesses++; // Uncomment if length accesses should count
         return Reflect.get(target, prop, receiver);
       }
       
     // Handle index access (numeric properties); guard symbols (for..of reads
     // Symbol.iterator through the proxy) and non-index strings.
     if (typeof prop === 'string' && !isNaN(prop)) {
       const index = Number(prop);
       if (Number.isInteger(index) && index >= 0 && index < target.length) {
         stats.recordIndexAccesses++;
       }
       return Reflect.get(target, prop, receiver);
     }
       
       // For all other properties/methods, delegate to the original array
       return Reflect.get(target, prop, receiver);
     }
   };
   
   // Return a new proxy each time to ensure we capture all accesses
   return new Proxy(real, handler);
}

// TARGET E helpers: the shim exposes the LIVE counters object. `const c1 = obj`
// snapshots a REFERENCE, so every delta against an earlier alias of the same
// object is identically zero and proves nothing. Every measurement below takes
// a SCALAR snapshot (copies the numbers), runs exactly one frame, and diffs
// scalars.
function snapCounters(h) {
  const c = h.win.__wintageScrollCounters;
  return {
    edges: c.edges, styled: c.styled,
    recordsTouched: c.recordsTouched, addedTouched: c.addedTouched,
    queueOps: c.queueOps, overflowContinues: c.overflowContinues,
    maxRetained: c.maxRetained
  };
}
function delta(a, b, k) { return b[k] - a[k]; }

function runR012() {
  const small = 500; // small fixed constant allowed above the budgets
  const {
    traverse: TRAVERSE_BUDGET_R012, intake: INTAKE_BUDGET_R012,
    queue: ROOT_QUEUE_BUDGET_R012, maxTreeRoots: MAX_TREE_ROOTS_R012,
    styling: STYLING_BUDGET_R012
  } = budgetConsts();

  // TARGET A static: the SHIPPED payload contains zero matches for every
  // historical test identifier. The legacy implementations exist only inside
  // the temporary mutant strings constructed by runR012Red().
  {
    const payload = literalAfter(SHIM, 'const SCROLL_FIX = `');
    for (const needle of ['legacyWidePush', 'legacyIntake', '__wintageTestHooks']) {
      check('R012 static: shipped SCROLL_FIX contains zero ' + needle,
        payload.indexOf(needle), -1);
    }
    check('R012 static: the whole shim source carries no __wintageTestHooks switch',
      SHIM.indexOf('__wintageTestHooks'), -1);
  }

// ── Fixture A: 250,000 direct children of one queued root ──
  // TARGET G: leaf nodes are NOT instrumented. The measured primitive is the
  // wide root's sibling/index access, so only the root's children list is
  // observed; the production counters carry total edge accounting.
  {
    const h = runScrollFix();
    const root = h.documentElement.append(h.makeEl('DIV'));
    const stats = { childIndexAccesses: 0 };
    for (let i = 0; i < 250000; i++) root.append(h.makeEl('DIV'));
    instrumentChildren(root, stats);
    const gcsBefore = h.counters.gcs;
    const cBefore = snapCounters(h);
    h.deliver([{ type: 'childList', target: h.documentElement, addedNodes: { length: 1, 0: root } }]);

    // TARGET F: the first continuation after deliver() is the INTAKE frame,
    // not the renderer. Its work must be bounded queue bookkeeping only.
    h.drainOneFrame();
    const afterIntake = snapCounters(h);
    check('R012 A: intake frame performs ZERO styling work (intake is not the render frame)',
      delta(cBefore, afterIntake, 'styled'), 0);
    check('R012 A: intake frame performs ZERO getComputedStyle calls',
      h.counters.gcs - gcsBefore, 0);
    check('R012 A: intake frame queue bookkeeping is bounded (intake + queue budget + const)',
      delta(cBefore, afterIntake, 'queueOps') <= INTAKE_BUDGET_R012 + ROOT_QUEUE_BUDGET_R012 + small, true);

    // First real traversal/render frame, scalar-measured.
    const seen = new Set();
    h.markSeen(seen); // identity coverage is measured from the first styled element
    const beforeTraversal = snapCounters(h);
    const readsBefore = stats.childIndexAccesses;
    const gcsMid = h.counters.gcs;
    h.drainOneFrame();
    const afterTraversal = snapCounters(h);
    const firstFrameReads = stats.childIndexAccesses - readsBefore;
    const firstFrameEdges = delta(beforeTraversal, afterTraversal, 'edges');
    const firstFrameStyled = delta(beforeTraversal, afterTraversal, 'styled');
    const firstFrameGcs = h.counters.gcs - gcsMid;
    check('R012 A: first traversal frame child/index reads are bounded (traverse budget + const)',
      firstFrameReads <= TRAVERSE_BUDGET_R012 + small, true);
    check('R012 A: first traversal frame edge advances are bounded (traverse budget + const)',
      firstFrameEdges <= TRAVERSE_BUDGET_R012 + small, true);
    check('R012 A: first traversal frame styling is bounded (styling budget + const)',
      firstFrameStyled <= STYLING_BUDGET_R012 + small, true);
    check('R012 A: first traversal frame getComputedStyle is bounded (styling budget + const)',
      firstFrameGcs <= STYLING_BUDGET_R012 + small, true);
    check('R012 A: the first traversal frame actually began the walk (styled > 0)',
      firstFrameStyled > 0, true);

    const restFrames = h.drain(40000);
    check('R012 A: a continuation remains pending after the bounded first frame',
      restFrames > 0, true);

    // TARGET C: eventual coverage by identity (markSeen), not a magic raw
    // count. A childList record whose target is documentElement legitimately
    // queues the documentElement itself through queueDirty, so the reference
    // set is 250,002: documentElement + inserted root + 250,000 children.
    let missing = 0;
    for (const c of root.children) if (!seen.has(c)) missing++;
    const uniqueSeen = seen.size;
    const finalA = snapCounters(h);
    const styledTotal = delta(cBefore, finalA, 'styled');
    check('R012 A: every reference element is eventually seen (no missing child)',
      missing, 0);
    check('R012 A: unique seen count is exactly 250,002 (documentElement repair + root + 250,000 children)',
      uniqueSeen, 250002);
    check('R012 A: raw duplicate styling overhead stays bounded (small const)',
      styledTotal - uniqueSeen <= small, true);
    check('R012 A: no overflow token was needed for a single wide root',
      finalA.overflowContinues - cBefore.overflowContinues, 0);
  }

// ── Fixture B: one childList record with 100,000 addedNodes (lazy Proxy) ──
  // TARGET G: the 100,000 per-index Object.defineProperty getters are replaced
  // by ONE lazy Proxy around the node array; numeric index reads are counted
  // through the Proxy, so the harness allocates nothing per element.
  {
    const h = runScrollFix();
    // A real bulk insert: the nodes arrive CONNECTED under one parent, exactly
    // the framework-mount shape the audit measured. queueTree's retention cap
    // overflows after 64 roots and the single whole-document continuation
    // covers the parent and every connected child.
    const parent = h.documentElement.append(h.makeEl('DIV'));
    const nodes = []; const idxReads = { n: 0 };
    for (let i = 0; i < 100000; i++) { const n = h.makeEl('DIV'); parent.append(n); nodes.push(n); }
    const addedNodes = new Proxy(nodes, {
      get(target, prop) {
        if (typeof prop === 'string' && /^\d+$/.test(prop)) idxReads.n++;
        return Reflect.get(target, prop);
      }
    });
    const gcsBefore = h.counters.gcs;
    const cBefore = snapCounters(h);
    h.deliver([{ type: 'childList', target: h.documentElement, addedNodes }]);

    // TARGET F: the first continuation is the INTAKE frame — bounded reads,
    // zero styling. It is NOT proof that traversal is bounded.
    h.drainOneFrame();
    const afterIntake = snapCounters(h);
    check('R012 B: first intake frame reads <= intake budget + const addedNodes',
      idxReads.n <= INTAKE_BUDGET_R012 + small, true);
    check('R012 B: first intake frame addedTouched <= intake budget + const',
      delta(cBefore, afterIntake, 'addedTouched') <= INTAKE_BUDGET_R012 + small, true);
    check('R012 B: first intake frame performs ZERO styling work',
      delta(cBefore, afterIntake, 'styled'), 0);
    check('R012 B: first intake frame performs ZERO getComputedStyle calls',
      h.counters.gcs - gcsBefore, 0);

    // Then prove subsequent rendering remains bounded.
    const seen = new Set();
    h.markSeen(seen);
    const beforeRender = snapCounters(h);
    const gcsMid = h.counters.gcs;
    h.drainOneFrame();
    const afterRender = snapCounters(h);
    check('R012 B: the first render frame styling is bounded (styling budget + const)',
      delta(beforeRender, afterRender, 'styled') <= STYLING_BUDGET_R012 + small, true);
    check('R012 B: the first render frame getComputedStyle is bounded (styling budget + const)',
      h.counters.gcs - gcsMid <= STYLING_BUDGET_R012 + small, true);

    const restFrames = h.drain(300000);
    check('R012 B: styling is spread across bounded frames (was one giant frame)',
      restFrames > 1, true);

    // TARGET D: the unique superset is documentElement + parent + 100,000
    // children = 100,002. Raw styled exceeds it only by bounded duplicate
    // work: the dirty-target repair plus the retained detailed roots the
    // document-wide continuation re-walks. The bound is derived from the
    // retention policy (MAX_TREE_ROOTS), not hard-coded.
    const finalB = snapCounters(h);
    let missing = 0;
    for (const n of nodes) if (!seen.has(n)) missing++;
    const uniqueSeen = seen.size;
    const styledTotal = delta(cBefore, finalB, 'styled');
    check('R012 B: every one of the 100,000 children is eventually seen', missing, 0);
    check('R012 B: the parent is seen', seen.has(parent), true);
    check('R012 B: documentElement is seen (its repair is legitimate, not a coverage defect)',
      seen.has(h.documentElement), true);
    check('R012 B: unique seen count is exactly 100,002', uniqueSeen, 100002);
    check('R012 B: exactly one continuation chain drains the whole delivery',
      delta(cBefore, finalB, 'addedTouched'), 100000);
    check('R012 B: traversal edges account for every node (parent edge + 100k children)',
      delta(cBefore, finalB, 'edges'), 100001);
    check('R012 B: the overflow episode issued exactly ONE continuation token',
      delta(cBefore, finalB, 'overflowContinues'), 1);
    check('R012 B: duplicate raw styling overhead is bounded by the retention policy (MAX_TREE_ROOTS + fixed target overhead)',
      styledTotal - uniqueSeen <= MAX_TREE_ROOTS_R012 + small, true);
  }

// ── Fixture C: 100,000 attribute records must not be consumed synchronously ──
  {
    const h = runScrollFix();
    const targets = []; for (let i = 0; i < 100000; i++) targets.push(h.makeEl('DIV'));
    const recs = targets.map(t => ({ type: 'attributes', target: t }));
    const stats = { recordIndexAccesses: 0 };
    const instrumentedRecs = instrumentRecords(recs, stats);
    const gcsBefore = h.counters.gcs;
    const cBefore = snapCounters(h);
    h.deliver(instrumentedRecs);
    check('R012 C: the callback does not synchronously enumerate the record batch',
      stats.recordIndexAccesses <= INTAKE_BUDGET_R012 + small, true);
    check('R012 C: the callback performs no styling work synchronously',
      delta(cBefore, snapCounters(h), 'styled'), 0);
    check('R012 C: the callback performs no getComputedStyle work synchronously',
      h.counters.gcs - gcsBefore, 0);

    // TARGET F: the first continuation is the INTAKE frame — it consumes at
    // most INTAKE_BUDGET records and performs no styling. A zero-styling
    // intake frame is NOT proof that traversal is bounded; the render frame
    // is measured separately below.
    h.drainOneFrame();
    const afterIntake = snapCounters(h);
    check('R012 C: first intake frame record index reads <= INTAKE_BUDGET + const',
      stats.recordIndexAccesses <= INTAKE_BUDGET_R012 + small, true);
    check('R012 C: first intake frame recordsTouched <= INTAKE_BUDGET + const',
      delta(cBefore, afterIntake, 'recordsTouched') <= INTAKE_BUDGET_R012 + small, true);
    check('R012 C: first intake frame performs ZERO styling work',
      delta(cBefore, afterIntake, 'styled'), 0);

    // Then prove subsequent rendering remains bounded and complete.
    const seen = new Set();
    h.markSeen(seen);
    const beforeRender = snapCounters(h);
    const gcsMid = h.counters.gcs;
    h.drainOneFrame();
    const afterRender = snapCounters(h);
    check('R012 C: the first render frame styling is bounded (styling budget + const)',
      delta(beforeRender, afterRender, 'styled') <= STYLING_BUDGET_R012 + small, true);
    check('R012 C: the first render frame getComputedStyle is bounded (styling budget + const)',
      h.counters.gcs - gcsMid <= STYLING_BUDGET_R012 + small, true);
    h.drain(300000);
    const finalC = snapCounters(h);
    let missingC = 0;
    for (const t of targets) if (!seen.has(t)) missingC++;
    check('R012 C: eventual repair covers every one of the 100,000 targets',
      missingC, 0);
    check('R012 C: unique seen count is exactly 100,000', seen.size, 100000);
    check('R012 C: no duplicate raw styling overhead in the attribute-storm lane',
      delta(cBefore, finalC, 'styled') - seen.size <= small, true);
    check('R012 C: the attribute storm needs no overflow token',
      delta(cBefore, finalC, 'overflowContinues'), 0);
  }

// ── Fixture D: overflow is a superset, not lost work ──
  {
    const h = runScrollFix();
    h.drain(50); // settle the initial walk
    const omitted = h.documentElement.append(h.makeEl('SECTION'));
    const seen = new Set();
    h.markSeen(seen);
    // MAX_PENDING_BATCHES = 8 retained batches; the 9th delivery forces the
    // overflow path. What must NOT happen is one token per dropped node and
    // what MUST happen is exactly one whole-document re-walk that reaches
    // elements absent from every retained record.
    const batches = [];
    for (let b = 0; b < 9; b++) {
      const t = h.makeEl('DIV');
      batches.push([{ type: 'attributes', target: t }]);
    }
    const d0 = snapCounters(h);
    for (const b of batches) h.deliver(b);
    // Execute exactly one scheduled frame to measure first-frame work after overflow
    h.drainOneFrame();
    const frames = h.drain(100000); // drain remaining frames
    const d1 = snapCounters(h);
    check('R012 D: overflow issues exactly ONE whole-document continuation token',
      delta(d0, d1, 'overflowContinues'), 1);
    check('R012 D: the element omitted from retained detailed records is still repaired',
      seen.has(omitted), true);
    check('R012 D: the overflow continuation completes in bounded frames',
      frames <= 400, true);
    check('R012 D: retained state stays bounded (max retained traversal/input state)',
      d1.maxRetained <= 2100, true);
  }

  // Static guards, including the retired AD_BLOCK surface (the PERF-001 text
  // also discussed AD_BLOCK; that part is not live and must NOT come back).
  {
    const src = SHIM;
    check('R012 static: traversal budget is declared and enforced',
      TRAVERSE_BUDGET_R012 > 0 && /edgeBudget <= 0/.test(src) && /edgeBudget = TRAVERSE_BUDGET/.test(src), true);
    check('R012 static: intake budgets are declared',
      INTAKE_BUDGET_R012 > 0 && ROOT_QUEUE_BUDGET_R012 > 0, true);
    check('R012 static: the observer callback enqueues batches without enumerating them',
      /pendingIntake\.push\(\{ records: records, rIndex: 0, aIndex: 0, targetDone: false \}\)/.test(src), true);
    check('R012 static: primitive counters are exposed for tests/diagnosis',
      /__wintageScrollCounters/.test(src), true);
    check('R012 static: AD_BLOCK is not reintroduced into the shim',
      !/adblock|ad_block|AD_BLOCK/i.test(src), true);
  }
}

function runR012Red() {
  // TARGET B: red controls are TEMPORARY MUTANTS of the SCROLL_FIX payload
  // string. The production file on disk is never edited and the shipped source
  // carries no mutant switch: each mutant is an in-memory source-to-source
  // transformation, ASSERTED to have applied, then executed in an isolated VM
  // context. The verdict is primitive counts, never timing.
  const fixed = literalAfter(SHIM, 'const SCROLL_FIX = `');

  // RED A: replace the bounded tree cursor with the historical bulk-children
  // implementation — one traversal step pushes EVERY child of the popped node
  // onto a stack in a single budget unit.
  const fixedCursorBlock = sliceBlock(fixed, '  const nextTreeNode = () => {');
  const legacyWidePush = `  const nextTreeNode = () => {
    for (;;) {
      let state = activeTrees[activeTrees.length - 1];
      if (!state) {
        const root = takeRoot();
        if (!root) return null;
        treeRoots.delete(root);
        state = { stack: [root] };
        activeTrees.push(state);
      }
      const node = state.stack.pop();
      if (!node) { activeTrees.pop(); continue; }
      const children = node.children;
      if (children) for (let i = children.length - 1; i >= 0; i--) state.stack.push(children[i]);
      return node;
    }
  }`;
  const mutantA = fixed.replace(fixedCursorBlock, legacyWidePush);
  check('R012 RED A: the source mutation actually applied (bounded cursor replaced)',
    mutantA !== fixed && mutantA.indexOf('state.stack.push') > 0, true);
  {
    const h = runScrollFix(mutantA);
    const root = h.documentElement.append(h.makeEl('DIV'));
    for (let i = 0; i < 250000; i++) root.append(h.makeEl('DIV'));
    h.deliver([{ type: 'childList', target: h.documentElement, addedNodes: { length: 1, 0: root } }]);
    h.drain(40000);
    const A = snapCounters(h);
    // The mutant pushes all 250,000 siblings onto one stack in a single budget
    // unit; the retained-state high-water mark exposes that, where the fixed
    // cursor implementation stays bounded (fixture D proves <= 2100).
    check('R012 RED A: the bulk-expansion mutant enumerates essentially all 250,000 siblings in one step (retained state explodes)',
      A.maxRetained > 200000, true);
  }

  // RED B: replace the bounded observer intake with the historical synchronous
  // callback — every delivered record and every addedNodes entry is consumed
  // before the callback returns.
  const cbBlock = sliceBlock(fixed, 'new MutationObserver(records => {');
  const legacyIntakeCb = `new MutationObserver(records => {
    settleNeeded = true;
    for (const r of records) {
      if (r.type === "childList") {
        queueDirty(r.target);
        for (const node of r.addedNodes) queueTree(node);
      } else if (r.type === "attributes") {
        queueDirty(r.target);
      }
    }
    queueFrame();
  }`;
  const mutantB = fixed.replace(cbBlock, legacyIntakeCb);
  check('R012 RED B: the source mutation actually applied (bounded intake replaced)',
    mutantB !== fixed && mutantB.indexOf('for (const node of r.addedNodes)') > 0, true);
  {
    const h = runScrollFix(mutantB);
    const nodes = []; const idxReads = { n: 0 };
    for (let i = 0; i < 100000; i++) nodes.push(h.makeEl('DIV'));
    // One lazy Proxy (the TARGET G shape) whose numeric index reads are
    // counted: the legacy for..of consumes the array iterator, and the
    // iterator reads every index THROUGH the proxy, so all 100,000 reads
    // light the counter.
    const counted = new Proxy(nodes, {
      get(target, prop) {
        if (typeof prop === 'string' && /^\d+$/.test(prop)) idxReads.n++;
        return Reflect.get(target, prop);
      }
    });
    const cBefore = snapCounters(h);
    h.deliver([{ type: 'childList', target: h.documentElement, addedNodes: counted }]);
    check('R012 RED B: the synchronous-intake mutant consumes ALL 100,000 addedNodes before the callback returns',
      idxReads.n, 100000);
    check('R012 RED B: the mutant also queues synchronously inside the callback (retention work before yield)',
      snapCounters(h).queueOps - cBefore.queueOps > 0, true);
    check('R012 RED B: the mutant never enters the bounded intake path (addedTouched stays 0)',
      snapCounters(h).addedTouched - cBefore.addedTouched, 0);
  }

  check('R012 RED: red control completed against both temporary mutants (production file untouched on disk)',
    SHIM.indexOf('legacyWidePush'), -1);
}
