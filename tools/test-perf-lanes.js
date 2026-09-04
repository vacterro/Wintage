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

  const stats = { processCalls: 0, lightRequests: 0, forceRequests: 0 };
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
    lightDirty,
    stripHoverSheets: () => { },
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
  check('PERF-003: it does exactly its budget of work from the registry',
    stats.processCalls, 2500);
  check('PERF-003: the unfinished remainder stays queued for the next pass',
    lightDirty.size, 500);
  check('PERF-003: an incomplete light pass re-arms itself', stats.lightRequests, 1);

  // Second pass drains the rest and stops.
  stats.processCalls = 0; stats.lightRequests = 0;
  ctx.__runSweeper(false);
  check('PERF-003: the next pass drains the remainder', stats.processCalls, 500);
  check('PERF-003: a completed light pass does not re-arm', stats.lightRequests, 0);
  check('PERF-003: and still never touched the selector', counters.qsa, 0);
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
function runScrollFix() {
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
  const payload = eval('`' + literalAfter(SHIM, 'const SCROLL_FIX = `') + '`');
  vm.runInContext(payload, ctx);
  const drain = (max) => {
    let n = 0;
    while (frames.length && n++ < max) frames.shift()();
    return n;
  };
  drain(50); // initial documentElement pass
  return {
    counters, documentElement, makeEl,
    deliver: recs => observerCb(recs),
    drain, frames,
    markSeen: sink => { seenSink = sink; }
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
  check('PERF-002 shim: the overflow continuation is ONE re-walk, not one entry per node',
    frames <= 400, true);
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

// ══ 8. PERF-002 (shim): AD_BLOCK collapses overlapping roots ════════════════
{
  const counters = { qsa: 0, rect: 0 };
  const { document, documentElement, makeEl } = makeDom(counters);
  let observerCb = null;
  const frames = [];
  const ctx = {
    console,
    window: { fetch: null },
    document,
    XMLHttpRequest: function () { },
    requestAnimationFrame: fn => { frames.push(fn); return frames.length; },
    MutationObserver: class { constructor(cb) { observerCb = cb; } observe() { } disconnect() { } }
  };
  ctx.XMLHttpRequest.prototype = { open() { }, send() { } };
  ctx.window.window = ctx.window;
  vm.createContext(ctx);
  vm.runInContext(eval('`' + literalAfter(SHIM, 'const AD_BLOCK = `') + '`'), ctx);
  while (frames.length) frames.shift()();

  let node = documentElement;
  const chain = [];
  for (let i = 0; i < 1000; i++) { node = node.append(makeEl('div')); chain.push(node); }
  const before = counters.qsa;
  observerCb(chain.map(n => ({ addedNodes: [n] })));
  while (frames.length) frames.shift()();
  const queries = counters.qsa - before;
  // Pre-fix: one descendant query PER retained root -> 499,500 visits for this
  // shape. Collapsed, the ancestor's single query covers the chain.
  check('PERF-002 shim: AD_BLOCK queries once for a nested chain, not once per node',
    queries <= 2, true);

  // A FLAT burst past the cap must become ONE document-wide pass, not one query
  // per retained root. Observable because the document pass queries `document`
  // itself, which no per-root pass ever does.
  const flat = [];
  for (let i = 0; i < 500; i++) flat.push(documentElement.append(makeEl('div')));
  let docQueries = 0;
  const realDocQsa = document.querySelectorAll;
  document.querySelectorAll = function (sel) { docQueries++; return realDocQsa.call(document, sel); };
  const before2 = counters.qsa;
  observerCb(flat.map(n => ({ addedNodes: [n] })));
  while (frames.length) frames.shift()();
  document.querySelectorAll = realDocQsa;
  check('PERF-002 shim: a 500-root flat burst collapses to ONE document-wide pass',
    docQueries, 1);
  check('PERF-002 shim: and that pass is bounded, not 500 per-root queries',
    counters.qsa - before2 <= 2, true);
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
    AD_BLOCK: '1', THEME_REASSERT_FIX: '1',
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

    console.log('\n' + (bad === 0 ? 'perf lanes test PASS' : bad + ' FAILURE(S)'));
    process.exit(bad === 0 ? 0 : 1);
  });
}
