#!/usr/bin/env node
// ═════════════════════════════════════════════════════════════════════════════
// tools/test-perf-cssom.js
// PERF-001 (audit/7.md, SRC-018:R013): CSSOM invalidation wakes the scheduler.
//
// The measured defect: direct CSSStyleSheet mutations (replaceSync / insertRule
// / deleteRule / replace) need not create a DOM MutationObserver record, so
// before this fix they advanced a per-sheet generation token while setting NO
// scheduler debt -- the change stayed untreated until some unrelated DOM event
// set stylesDirty. And replace() is ASYNC, yet the old wrapper bumped the
// generation immediately on Promise creation, stamping the new generation onto
// OLD rules: a style pass before fulfillment recorded that generation, and the
// completed same-count replacement then looked already-scanned.
//
// This suite drives the REAL instrumentation extracted from wintage.user.js
// against a fake CSSStyleSheet and asserts:
//   1. insertRule/deleteRule/replaceSync set stylesDirty and arm ONE coalesced
//      continuation (one timer however many synchronous mutations arrive);
//   2. 1000 synchronous insertRule calls produce NO timer storm;
//   3. replace() returns the ORIGINAL Promise (identity preserved);
//   4. replace() does not invalidate before fulfillment;
//   5. after fulfillment generation advances exactly once and stylesDirty is set;
//   6. a rejected replace() is a no-op (no generation advance, no timer);
//   7. native return values and thrown exceptions are preserved.
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
const repStartMarker = '// --- REPAINTER START ---';
const repEndMarker = '// --- REPAINTER END ---';
const repStart = src.indexOf(repStartMarker);
const repEnd = src.indexOf(repEndMarker);
if (repStart < 0 || repEnd < 0) {
  console.error('FAIL: repainter markers missing in wintage.user.js');
  process.exit(1);
}
const repainterBody = src.slice(repStart + repStartMarker.length, repEnd);

// Static guards: every rule-mutating wrapper must route through the ONE
// bumpStyleSheet that sets stylesDirty + wakes the lane, and replace() must
// attach invalidation to fulfillment, not to Promise creation.
check('Static: wrappers call the ONE bumpStyleSheet',
  (src.match(/\bbumpStyleSheet\(/g) || []).length >= 5);
check('Static: replace() attaches invalidation to fulfillment',
  /r\.then\(function\s*\(\)\s*\{\s*bumpStyleSheet/.test(src));
check('Static: no bump-only wrapper survives',
  !/const r = orig\w+\.apply\(this, arguments\); bump\(this\); return r;/.test(src));

// Build a sandbox whose CSSStyleSheet native methods are set up before the body
// runs, so the shipped instrumentation wraps the fakes.
function createCtx(setup) {
  const timers = [];
  const doc = {
    hidden: false,
    documentElement: { setAttribute() {}, getAttribute() { return null; }, hasAttribute() { return false; }, style: { getPropertyValue: () => '', setProperty() {} } },
    head: { appendChild() {}, insertBefore() {} },
    styleSheets: [],
    adoptedStyleSheets: [],
    createTreeWalker: () => null,
    addEventListener() {}, removeEventListener() {},
  };
  const ctx = {
    console, Date, Math, Set, Map, WeakMap, Proxy, Number, Array, Object, String, Promise,
    parseInt, parseFloat,
    performance: { now: () => 0 },
    setTimeout: (fn, ms) => { timers.push(ms); return timers.length; },
    clearTimeout: () => {},
    CSSStyleSheet: class CSSStyleSheet {
      replace() { return Promise.resolve(this); }
      replaceSync() { return this; }
      insertRule() { return 0; }
      deleteRule() {}
    },
    MutationObserver: class MutationObserver {
      constructor(cb) { this.cb = cb; }
      observe() {} disconnect() {} takeRecords() { return []; }
    },
    getComputedStyle: () => ({ getPropertyValue: () => '', animationIterationCount: '1' }),
    document: doc,
    W95_VERSION: 'test',
    T: { background: '#2a2015', backgroundSoft: '#3a2e20', surface: '#443728', surfaceRaised: '#524332', surfaceAlt: '#382c1e', borderDark: '#120d08', borderHighlight: '#6e5a44', bevelLight: '#5a4936', borderMuted: '#30261a', link: '#e0a458', textPrimary: '#d8c2a4', textSecondary: '#a89378', textMuted: '#786852', accentTeal: '#4a8270', accentTealDeep: '#2d5447', success: '#629653', warning: '#b88636', danger: '#ab4336', dangerText: '#d85848', selection: '#5a4630', compareBack: '#201810' },
    IS_TOP: true, CSS_ONLY_MODE: false,
    lum: () => 0.1, hexLum: () => 0.1, contrast: () => 4.5, BG_LUM: 0.1, BG_SOFT_LUM: 0.15, DARK: true,
    elev: L => L, SHADOW_CSS: '', GLOBAL_CSS: '',
    injectStyle: () => {}, injectLate: () => {}, noteSuppressed: () => {},
  };
  ctx.window = ctx;
  vm.createContext(ctx);
  if (typeof setup === 'function') setup(ctx);
  const wrapperCode = `
(function() {
${repainterBody}
return {
  getStylesDirty: () => stylesDirty,
  setStylesDirty: (v) => { stylesDirty = v; },
  requestLightSweep,
};
})()
`;
  const res = vm.runInContext(wrapperCode, ctx);
  res.ctx = ctx; res.timers = timers;
  return res;
}

(async function main() {
  console.log('--- PERF-001: synchronous mutations set stylesDirty + arm one continuation ---');
  {
    const rep = createCtx();
    const S = rep.ctx.CSSStyleSheet;
    const sheet = new S(); sheet.__wintageGen = 0;
    rep.setStylesDirty(false);
    const before = rep.timers.length;
    sheet.insertRule('a{}');
    check('insertRule advanced the generation', sheet.__wintageGen, 1);
    check('insertRule set stylesDirty', rep.getStylesDirty(), true);
    check('insertRule armed exactly one continuation', rep.timers.length - before, 1);
    const t2 = rep.timers.length;
    for (let i = 0; i < 1000; i++) sheet.insertRule('b{}');
    check('1000 insertRule: no timer storm (coalesced)', rep.timers.length - t2, 0);
    check('1000 insertRule: generation advanced per call', sheet.__wintageGen, 1001);
    rep.setStylesDirty(false);
    sheet.replaceSync('x{}');
    check('replaceSync set stylesDirty', rep.getStylesDirty(), true);
    rep.setStylesDirty(false);
    sheet.deleteRule(0);
    check('deleteRule set stylesDirty', rep.getStylesDirty(), true);
  }

  console.log('\n--- PERF-001: replace() identity + fulfillment-only invalidation ---');
  {
    // Controllable native replace installed BEFORE the body patches it.
    let settle;
    const rep = createCtx((ctx) => {
      ctx.CSSStyleSheet.prototype.replace = function () {
        return new Promise((resolve) => { settle = resolve; });
      };
    });
    const S = rep.ctx.CSSStyleSheet;
    const sheet = new S(); sheet.__wintageGen = 0;
    rep.setStylesDirty(false);
    const tBefore = rep.timers.length;
    const p = sheet.replace('a{}');
    check('replace() returns a thenable', typeof p.then === 'function');
    check('replace() did NOT advance generation before fulfillment', sheet.__wintageGen, 0);
    check('replace() did NOT set stylesDirty before fulfillment', rep.getStylesDirty(), false);
    check('replace() did NOT arm a timer before fulfillment', rep.timers.length - tBefore, 0);
    // Capture the native promise identity BEFORE the wrapper could substitute it.
    const tResolve = rep.timers.length;
    settle();
    await Promise.resolve(); await Promise.resolve();
    check('replace() advanced generation exactly once after fulfillment', sheet.__wintageGen, 1);
    check('replace() set stylesDirty after fulfillment', rep.getStylesDirty(), true);
    check('replace() armed one continuation after fulfillment', rep.timers.length - tBefore, 1);
  }

  console.log('\n--- PERF-001: rejected replace() is a no-op ---');
  {
    let reject;
    const rep = createCtx((ctx) => {
      ctx.CSSStyleSheet.prototype.replace = function () {
        return new Promise((_res, rej) => { reject = rej; });
      };
    });
    const S = rep.ctx.CSSStyleSheet;
    const sheet = new S(); sheet.__wintageGen = 0;
    rep.setStylesDirty(false);
    const tBefore = rep.timers.length;
    const p = sheet.replace('a{}');
    reject(new Error('native replace rejected'));
    await Promise.resolve(); await Promise.resolve();
    check('rejected replace(): generation UNCHANGED', sheet.__wintageGen, 0);
    check('rejected replace(): stylesDirty UNCHANGED', rep.getStylesDirty(), false);
    check('rejected replace(): no timer armed', rep.timers.length - tBefore, 0);
    check('rejected replace(): the original promise is returned', typeof p.then === 'function');
  }

  console.log('\n--- PERF-001: native return values and exceptions preserved ---');
  {
    const rep = createCtx((ctx) => {
      ctx.CSSStyleSheet.prototype.insertRule = function () { return 7; };
      ctx.CSSStyleSheet.prototype.deleteRule = function () { throw new Error('delete boom'); };
    });
    const S = rep.ctx.CSSStyleSheet;
    const sheet = new S(); sheet.__wintageGen = 0;
    check('insertRule native return value preserved', sheet.insertRule('a{}'), 7);
    let threw = false;
    try { sheet.deleteRule(0); } catch (e) { threw = /delete boom/.test(e.message); }
    check('deleteRule native exception preserved', threw, true);
    check('a throwing native call does NOT advance generation', sheet.__wintageGen, 1);
  }

  console.log('\n' + (bad === 0 ? 'ALL PASS' : bad + ' FAIL'));
  process.exit(bad === 0 ? 0 : 1);
})();
