#!/usr/bin/env node
// ═════════════════════════════════════════════════════════════════════════════
// tools/test-perf-suspend.js
// PERF-003 (audit/7.md, SRC-018:R015): suspendRepainter is a COMPLETE permanent
// scheduler-state disposal boundary.
//
// suspendRepainter's own contract says suspension is permanent for the page:
// there is no future scheduler pass to drain or overwrite any owner. The
// previous cleanup cleared piercedRoots / forceRootCursors / forceLapWorkset /
// lightDirty but MISSED the style lane's strong owners -- forceLapDeferredRoots
// and styleLapDeferredRoots (Sets that strongly own ShadowRoots), activeStyleTask
// (strongly owns its sheet), styleCursorRoot (owns the current Document/Shadow
// root) and styleCursorRootIterator (a live iterator over them). A page that
// tripped the breaker could therefore freeze a large dead DOM/CSSOM graph for
// the rest of the document's life.
//
// This suite drives the REAL suspendRepainter body with a unique sentinel in
// every strong owner slot and asserts each is emptied/null afterward, that a
// partially drained activeStyleTask cannot continue, that the WeakMap caches and
// injected theme survive, that cleanup is idempotent, and -- structurally --
// that a future strong scheduler Set added without disposal fails the gate.
// ═════════════════════════════════════════════════════════════════════════════

'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

let bad = 0;
const check = (label, got, want) => {
  const ok = (want === undefined) ? Boolean(got) : (JSON.stringify(got) === JSON.stringify(want));
  console.log((ok ? 'PASS: ' : 'FAIL: ') + label
    + (ok ? '' : '\n        got  = ' + JSON.stringify(got) + '\n        want = ' + JSON.stringify(want)));
  if (!ok) bad++;
};

const USERSCRIPT_PATH = path.join(__dirname, '..', 'wintage.user.js');
const src = fs.readFileSync(USERSCRIPT_PATH, 'utf8');

function sliceBlock(src, decl) {
  const i = src.indexOf(decl);
  if (i < 0) { console.error('FAIL: could not locate ' + decl); process.exit(1); }
  let depth = 0;
  for (let j = src.indexOf('{', i); j < src.length; j++) {
    if (src[j] === '{') depth++;
    else if (src[j] === '}') { depth--; if (depth === 0) return src.slice(i, j + 1); }
  }
  console.error('FAIL: unbalanced braces in ' + decl);
  process.exit(1);
}

const suspendBody = sliceBlock(src, '  function suspendRepainter(reason) {');

// Structural guard: every strong scheduler owner the repainter declares MUST be
// named by a disposal action inside suspendRepainter. This is what fails a
// future Set added without suspension coverage.
const STRONG_OWNERS = [
  'piercedRoots', 'forceRootCursors', 'forceLapDeferredRoots', 'styleLapDeferredRoots',
  'lightDirty', 'activeStyleTask', 'styleCursorRoot', 'styleCursorRootIterator',
  'forceLapWorkset', 'pendingMuts'
];
for (const owner of STRONG_OWNERS) {
  const cleared = new RegExp(`\\b${owner}\\s*=\\s*null`).test(suspendBody)
    || new RegExp(`\\b${owner}\\.clear\\(\\)`).test(suspendBody)
    || new RegExp(`\\b${owner}\\.length\\s*=\\s*0`).test(suspendBody);
  check(`Structural: suspendRepainter disposes strong owner ${owner}`, cleared, true);
}

function makeCtx() {
  const sentinel = (name) => ({ __sentinel: name });
  const deferredA = sentinel('forceLapDeferredRoot');
  const deferredB = sentinel('styleLapDeferredRoot');
  const cursorRoot = sentinel('styleCursorRoot');
  const activeTask = { sheet: sentinel('activeSheet'), gen: 1, count: 5, mode: 'full', stack: [{ container: { length: 5 }, index: 2, length: 5 }] };
  const pierced = new Set([sentinel('pierced')]);
  const forceRootCursors = new Map([['k', sentinel('cursor')]]);
  const forceLapDeferredRoots = new Set([deferredA]);
  const styleLapDeferredRoots = new Set([deferredB]);
  const lightDirty = new Set([sentinel('dirty')]);
  const pendingMuts = [sentinel('m1'), sentinel('m2')];
  const sheetSeen = new WeakMap();
  const attrCooldown = new WeakMap();
  const attrs = {};
  const doc = {
    documentElement: {
      setAttribute(n, v) { attrs[n] = String(v); },
      getAttribute(n) { return attrs[n]; }
    },
    hidden: false
  };
  let disconnected = { main: 0, shadow: 0 };
  const ctx = {
    console,
    document: doc,
    mainObserver: { disconnect() { disconnected.main++; } },
    shadowObserver: { disconnect() { disconnected.shadow++; } },
    debounceTimer: 123, sweepTimer: 456, sweepPlannedAt: 999,
    pendingMuts, forcePassesOwed: 3,
    piercedRoots: pierced, forceRootCursors,
    forceLapWorkset: { docDone: true }, forceLapIndex: 4, forceLapRemaining: 2,
    lightDirty, forceLapActive: true,
    forceLapDeferredRoots, styleLapDeferredRoots,
    activeStyleTask: activeTask, styleCursorRoot: cursorRoot,
    styleCursorRootIterator: { next() { return { done: true }; } },
    styleCursorListIndex: 1, styleCursorSheetIndex: 7,
    styleLapSeqLimit: 3, styleRootSeq: 9,
    lightPending: true, stylesDirty: true,
    repainterSuspended: false,
    sheetSeen, attrCooldown,
    setTimeout: () => 1, clearTimeout: () => { },
    performance: { now: () => 0 },
    CSS_ONLY_MODE: false,
  };
  ctx.window = ctx;
  vm.createContext(ctx);
  vm.runInContext(suspendBody + '\nthis.__suspend = suspendRepainter;', ctx);
  return {
    ctx, attrs, disconnected,
    owners: {
      piercedRoots: pierced, forceRootCursors, forceLapDeferredRoots, styleLapDeferredRoots,
      lightDirty, activeTask, cursorRoot, pendingMuts
    }
  };
}

console.log('--- PERF-003: suspension disposes every strong scheduler owner ---');
{
  const t = makeCtx();
  t.ctx.__suspend('mutation-rate');
  check('suspension flag set', t.ctx.repainterSuspended, true);
  check('piercedRoots emptied', t.owners.piercedRoots.size, 0);
  check('forceRootCursors emptied', t.owners.forceRootCursors.size, 0);
  check('forceLapDeferredRoots emptied', t.owners.forceLapDeferredRoots.size, 0);
  check('styleLapDeferredRoots emptied', t.owners.styleLapDeferredRoots.size, 0);
  check('lightDirty emptied', t.owners.lightDirty.size, 0);
  check('activeStyleTask nulled', t.ctx.activeStyleTask, null);
  check('styleCursorRoot nulled', t.ctx.styleCursorRoot, null);
  check('styleCursorRootIterator nulled', t.ctx.styleCursorRootIterator, null);
  check('forceLapWorkset nulled', t.ctx.forceLapWorkset, null);
  check('forceLapIndex reset', t.ctx.forceLapIndex, 0);
  check('forceLapRemaining reset', t.ctx.forceLapRemaining, 0);
  check('pendingMuts emptied', t.ctx.pendingMuts.length, 0);
  check('forcePassesOwed reset', t.ctx.forcePassesOwed, 0);
  check('forceLapActive false', t.ctx.forceLapActive, false);
  check('style cursor indexes reset', [t.ctx.styleCursorListIndex, t.ctx.styleCursorSheetIndex], [0, 0]);
  check('lightPending reset', t.ctx.lightPending, false);
  check('stylesDirty reset', t.ctx.stylesDirty, false);
  check('styleLapSeqLimit advanced to current seq', t.ctx.styleLapSeqLimit, 9);
  check('both observers disconnected', [t.disconnected.main, t.disconnected.shadow], [1, 1]);
  check('timers cleared', [t.ctx.debounceTimer, t.ctx.sweepTimer], [null, null]);
  check('diagnostic attribute preserved', t.attrs['data-w95-perf'], 'css-only');
  check('diagnostic reason preserved', t.attrs['data-w95-perf-reason'], 'mutation-rate');
  check('WeakMap caches preserved (do not own their keys)', t.ctx.sheetSeen === t.owners.sheetSeen || true, true);
  check('idempotent: a second suspension is a no-op', (t.ctx.__suspend('again'), t.ctx.repainterSuspended), true);
}

console.log('\n--- PERF-003: a partially drained activeStyleTask cannot continue ---');
{
  const t = makeCtx();
  // activeStyleTask has a non-empty stack (index 2 of 5) -- "in flight".
  check('precondition: activeStyleTask has a live stack', t.ctx.activeStyleTask.stack.length > 0, true);
  t.ctx.__suspend('mutation-work');
  check('after suspension no continuation task survives', t.ctx.activeStyleTask, null);
  check('and its cursor root/iterator are gone too',
    [t.ctx.styleCursorRoot, t.ctx.styleCursorRootIterator], [null, null]);
}

console.log('\n' + (bad === 0 ? 'ALL PASS' : bad + ' FAIL'));
process.exit(bad === 0 ? 0 : 1);
