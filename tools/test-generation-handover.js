#!/usr/bin/env node
// T-397: a generation loaded over an older one must OWN the page.
//
// The userscript reinjects legitimately (an in-place Tampermonkey update, a
// dashboard re-inject, a manager that re-evaluates on a same-document
// navigation). Each run gets a fresh module scope and the SAME window, so every
// hook it installs on a shared global outlives it. Three of those hooks used to
// stay bound to the generation that installed them:
//
//   - setupRouteGuard's history.pushState / replaceState wrappers and its
//     popstate / hashchange listeners closed over that pass's `guard`, which
//     closes over that pass's suspendRepainter and its observer set.
//   - interceptAttachShadow had NO idempotence latch at all: generation B
//     wrapped generation A's wrapper, A's queued microtask inserted its
//     stylesheet first, and B then skipped the shadow root on its
//     querySelector check. Shadow roots created after the reinjection kept A's
//     CSS permanently.
//   - The CSSStyleSheet prototype hooks were gated on a boolean
//     __wintageInstrumented latch, so B never re-installed them and every
//     later CSSOM mutation kept bumping A's stylesDirty and calling A's
//     requestLightSweep.
//
// The fix is one mechanism at all three sites: a handover box on the existing
// global, republished by every generation and read at CALL time.
//
// "Generation" here is modelled the way the browser really does it: the same
// window and the same shared prototypes, with a fresh module scope per run.
// Each region below is therefore evaluated TWICE into one context.

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.join(__dirname, '..');
// WINTAGE_SCRIPT points the gate at an alternate build, so the same probes can
// be run against the PRE-FIX source (git show HEAD:wintage.user.js) and must
// fail there. A red control built by hand-editing the region proves the
// mutation, but only this proves the shipped gate bites the real defect.
const SCRIPT = process.env.WINTAGE_SCRIPT || path.join(ROOT, 'wintage.user.js');

let bad = 0;
const check = (label, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  console.log((ok ? 'PASS: ' : 'FAIL: ') + label + (ok ? '' : '  got=' + JSON.stringify(got) + ' want=' + JSON.stringify(want)));
  if (!ok) bad++;
};

// Bracket-match a block that starts at `startMarker`, counting from the first
// '{' that follows it. The three regions hold no unbalanced braces inside
// strings or comments, so a plain counter is enough and keeps the extraction
// independent of indentation.
function extractBlock(src, startMarker, label) {
  const start = src.indexOf(startMarker);
  if (start < 0) { console.error('FAIL: ' + label + ' not found in wintage.user.js'); process.exit(1); }
  const open = src.indexOf('{', start + startMarker.length);
  if (open < 0) { console.error('FAIL: ' + label + ' opening brace not found'); process.exit(1); }
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === '{') depth++;
    else if (src[i] === '}') { depth--; if (depth === 0) return src.substring(start, i + 1); }
  }
  console.error('FAIL: ' + label + ' closing brace not found');
  process.exit(1);
}

const src = fs.readFileSync(SCRIPT, 'utf8');

// The route guard needs EXCLUDE and isExcludedUrl alongside it, so it is taken
// as the contiguous run from the EXCLUDE array through the end of the function.
const excludeIdx = src.indexOf('const EXCLUDE = [');
if (excludeIdx < 0) { console.error('FAIL: EXCLUDE not found in wintage.user.js'); process.exit(1); }
const guardBlock = extractBlock(src, 'function setupRouteGuard', 'setupRouteGuard');
const guardSrc = src.substring(excludeIdx, src.indexOf(guardBlock, excludeIdx) + guardBlock.length);
const shadowSrc = extractBlock(src, '(function interceptAttachShadow()', 'interceptAttachShadow');
const sheetSrc = extractBlock(src, 'if (!CSS_ONLY_MODE && typeof CSSStyleSheet', 'CSSStyleSheet instrumentation');

// ---- shared browser shim -----------------------------------------------------
// One window, one Element.prototype, one CSSStyleSheet.prototype -- shared by
// both generations, exactly like the real document.
function makeCtx() {
  const calls = {
    suspendA: 0, suspendB: 0,
    reloadA: 0, reloadB: 0,
    sweeps: [],
    created: []
  };
  const listeners = { popstate: [], hashchange: [] };

  // A shadow root: enough DOM for the interception path to be observable.
  function makeShadow() {
    return {
      children: [],
      firstChild: null,
      insertBefore(node) { this.children.unshift(node); this.firstChild = this.children[0]; },
      querySelector(sel) {
        const want = sel.replace(/.*\[data-w95="([^"]+)"\].*/, '$1');
        for (const c of this.children) if (c.__w95 === want) return c;
        return null;
      }
    };
  }

  const ctx = {
    calls, listeners,
    W95_VERSION: { A: '1.0.0-A', B: '2.0.0-B' }[calls.__gen] || '1.0.0-A',
    __w95css: {},
    queueMicrotask: function (fn) { fn(); }, // synchronous: no timing in this gate
    document: {
      createElement: function (tag) {
        const node = {
          tag, attrs: {}, textContent: '',
          setAttribute(k, v) { this.attrs[k] = v; if (k === 'data-w95') this.__w95 = v; },
          getAttribute(k) { return Object.prototype.hasOwnProperty.call(this.attrs, k) ? this.attrs[k] : null; }
        };
        calls.created.push(node);
        return node;
      }
    },
    Element: (function () {
      function Element() { }
      Element.prototype.attachShadow = function () {
        const s = makeShadow();
        calls.created.push(s);
        return s;
      };
      return Element;
    })(),
    CSSStyleSheet: (function () {
      function CSSStyleSheet() { this.generation = 0; }
      CSSStyleSheet.prototype.insertRule = function () { return 0; };
      CSSStyleSheet.prototype.deleteRule = function () { };
      CSSStyleSheet.prototype.replaceSync = function () { };
      return CSSStyleSheet;
    })(),
    history: {
      pushState: function () { return undefined; },
      replaceState: function () { return undefined; }
    },
    location: { href: 'https://example.com/dashboard', reload: function () { } },
    window: {
      addEventListener: function (name, fn) { (listeners[name] || (listeners[name] = [])).push(fn); }
    }
  };
  ctx.window.window = ctx.window;
  ctx.__sweeps = calls.sweeps;
  ctx.__suspend = function (gen) { if (gen === 'A') calls.suspendA++; else calls.suspendB++; };
  return { ctx, listeners, calls };
}

// Runs ONE generation: fresh module scope, same window. The IIFE matters --
// `const EXCLUDE` at true module scope would collide between the two runs,
// which is not what a reinjection looks like (each run gets its own scope).
function runGeneration(ctx, listeners, gen, regions) {
  ctx.W95_VERSION = gen === 'A' ? '1.0.0-A' : '2.0.0-B';
  ctx.__gen = gen;
  const body = [
    // These four are MODULE-SCOPE bindings in the real script, so each
    // generation must get its own. Putting them on the shared context instead
    // would let generation A's hooks call generation B's machinery and hide
    // the very split-brain this gate exists to catch.
    'var stylesDirty = false;',
    'var CSS_ONLY_MODE = false;',
    'var myGen = __gen;',
    'var requestLightSweep = function () { __sweeps.push(myGen); };',
    'var suspendRepainter = function () { __suspend(myGen); };',
    regions.guard,
    // The extraction stops at the IIFE's closing brace, before its invocation;
    // the RED control below supplies its own already-invoked copy. Both
    // spellings of the stylesheet constant are substituted: HEAD's hook reads
    // SHADOW_CSS, the fixed one reads ACTIVE_SHADOW_CSS, and a substitution
    // that misses would leave the stylesheet undefined -- which silently
    // weakens the pre-fix control instead of failing it.
    /\)();\s*$/.test(regions.shadow)
      ? regions.shadow
      : regions.shadow.replace(/\b(?:ACTIVE_)?SHADOW_CSS\b/g, '__w95css.' + gen) + ')();',
    regions.sheet,
    // The real script installs the route guard at startup, once the EXCLUDE
    // check has passed.
    'setupRouteGuard();'
  ].join('\n');
  vm.runInContext('(function () {\n' + body + '\n})();', vm.createContext(ctx), { filename: 'gen-' + gen + '.js' });
}

function calls_touch(ctx, gen) {
  if (gen === 'A') ctx.calls.suspendA++; else ctx.calls.suspendB++;
}

// ---- the scenario ------------------------------------------------------------
const { ctx, listeners, calls } = makeCtx();
const regions = { guard: guardSrc, shadow: shadowSrc, sheet: sheetSrc };

// Style sheets are per-generation values handed to the interception hook the way
// the real script hands it ACTIVE_SHADOW_CSS.
ctx.__w95css.A = 'CSS-FROM-GEN-A';
ctx.__w95css.B = 'CSS-FROM-GEN-B';

// ── generation A ─────────────────────────────────────────────────────────────
runGeneration(ctx, listeners, 'A', regions);

check('gen A: pushState is wrapped', ctx.history.pushState.__wintageWrapped, true);
const pushAfterA = ctx.history.pushState;
const attachAfterA = ctx.Element.prototype.attachShadow;
const insertAfterA = ctx.CSSStyleSheet.prototype.insertRule;
check('gen A: exactly one popstate listener', listeners.popstate.length, 1);
check('gen A: exactly one hashchange listener', listeners.hashchange.length, 1);

const hostA = new ctx.Element();
const shadowA = hostA.attachShadow({ mode: 'open' });
check('gen A: shadow root gets generation A css', shadowA.querySelector('style[data-w95="shadow"]').textContent, 'CSS-FROM-GEN-A');

// ── generation B loads over the same page, no reload ─────────────────────────
runGeneration(ctx, listeners, 'B', regions);

check('reinjection: pushState NOT re-wrapped (one wrapper, not a stack)', ctx.history.pushState === pushAfterA, true);
check('reinjection: attachShadow NOT re-wrapped', ctx.Element.prototype.attachShadow === attachAfterA, true);
check('reinjection: insertRule NOT re-wrapped', ctx.CSSStyleSheet.prototype.insertRule === insertAfterA, true);
check('reinjection: still exactly one popstate listener', listeners.popstate.length, 1);
check('reinjection: still exactly one hashchange listener', listeners.hashchange.length, 1);

// The pre-existing shadow root must be restyled in place by generation B.
check('reinjection: pre-existing shadow root restyled to B', shadowA.querySelector('style[data-w95="shadow"]').textContent, 'CSS-FROM-GEN-B');
check('reinjection: restyled root carries B version stamp', shadowA.querySelector('style[data-w95="shadow"]').getAttribute('data-w95-ver'), '2.0.0-B');
check('reinjection: restyled root holds exactly ONE style element', shadowA.children.length, 1);

// A shadow root created AFTER the reinjection must also get B, not A.
const hostB = new ctx.Element();
const shadowB = hostB.attachShadow({ mode: 'open' });
check('reinjection: NEW shadow root gets generation B css', shadowB.querySelector('style[data-w95="shadow"]').textContent, 'CSS-FROM-GEN-B');

// ── the route guard must quarantine through generation B ─────────────────────
ctx.location.href = 'https://example.com/oauth/authorize';
ctx.history.pushState({}, '', '/oauth/authorize');
check('reinjection: pushState quarantined through B, not A', [calls.suspendA, calls.suspendB], [0, 1]);

for (const fn of listeners.popstate) fn({});
check('reinjection: popstate quarantined through B, not A', [calls.suspendA, calls.suspendB], [0, 2]);

ctx.history.replaceState({}, '', '/oauth/authorize');
check('reinjection: replaceState quarantined through B, not A', [calls.suspendA, calls.suspendB], [0, 3]);

// ── the stylesheet hooks must schedule through generation B ──────────────────
const sheet = new ctx.CSSStyleSheet();
ctx.CSSStyleSheet.prototype.insertRule.call(sheet, 'a{}', 0);
check('reinjection: insertRule advanced the sheet generation', sheet.__wintageGen, 1);
check('reinjection: insertRule woke generation B scheduler, not A', calls.sweeps, ['B']);

// ── RED control: the pre-fix shape must fail these assertions ────────────────
// A boolean latch alone (the old CSSStyleSheet gate) and a bare closure (the old
// route guard) both leave the FIRST generation in charge. Rebuild the old shape
// and prove the same probes now report generation A.
{
  const old = makeCtx();
  old.ctx.__w95css.A = 'CSS-FROM-GEN-A';
  old.ctx.__w95css.B = 'CSS-FROM-GEN-B';
  const oldRegions = {
    // Pre-fix route guard: same source with the handover box removed and the
    // hooks closing over this pass's `guard` again.
    guard: guardSrc
      .replace(/state\.guard = guard;/, '')
      .replace(/const fire = function \(\) \{\s*const owner = state\.guard \|\| guard;\s*owner\(\);\s*\};/, 'const fire = guard;')
      .replace(/addEventListener\('popstate', fire\)/, "addEventListener('popstate', guard)")
      .replace(/addEventListener\('hashchange', fire\)/, "addEventListener('hashchange', guard)"),
    shadow: '(function interceptAttachShadow() {' +
      '  if (typeof Element === "undefined") return;' +
      '  const orig = Element.prototype.attachShadow;' +
      '  Element.prototype.attachShadow = function (init) {' +
      '    const shadow = orig.call(this, init);' +
      '    if (shadow) queueMicrotask(function () {' +
      '      if (!shadow.querySelector("style[data-w95=\\"shadow\\"]")) {' +
      '        const s = document.createElement("style");' +
      '        s.setAttribute("data-w95", "shadow");' +
      '        s.setAttribute("data-w95-ver", W95_VERSION);' +
      '        s.textContent = __w95css.A;' +
      '        shadow.insertBefore(s, shadow.firstChild);' +
      '      }' +
      '    });' +
      '    return shadow;' +
      '  };' +
      '})();',
// The pre-fix stylesheet gate: a boolean latch, so generation B installs
    // nothing and the surviving hook keeps waking generation A's scheduler.
    sheet: 'if (typeof CSSStyleSheet !== "undefined" && !CSSStyleSheet.prototype.__wintageInstrumented) {' +
      ' CSSStyleSheet.prototype.__wintageInstrumented = true;' +
      ' var ownGen = myGen;' +
      ' const bump = function (s) { __sweeps.push(ownGen); };' +
      ' const p = CSSStyleSheet.prototype;' +
      ' p.insertRule = function () { const r = p.__orig.apply(this, arguments); bump(this); return r; };' +
      ' p.__wintagePatchedInsert = true;' +
      '}'
  };
  // Give the old shape a pristine insertRule to wrap.
  old.ctx.CSSStyleSheet.prototype.__orig = function () { return 0; };
  runGeneration(old.ctx, old.listeners, 'A', oldRegions);
  runGeneration(old.ctx, old.listeners, 'B', oldRegions);

  const oldHost = new old.ctx.Element();
  const oldShadow = oldHost.attachShadow({ mode: 'open' });
  check('RED: pre-fix interception keeps generation A css on a NEW shadow root', oldShadow.querySelector('style[data-w95="shadow"]').textContent, 'CSS-FROM-GEN-A');

  old.ctx.location.href = 'https://example.com/oauth/authorize';
  old.ctx.history.pushState({}, '', '/oauth/authorize');
  check('RED: pre-fix guard quarantines through generation A', [old.calls.suspendA, old.calls.suspendB], [1, 0]);

  old.ctx.CSSStyleSheet.prototype.insertRule.call(old.ctx.CSSStyleSheet.prototype, 'a{}', 0);
  check('RED: pre-fix stylesheet hooks wake generation A', old.calls.sweeps, ['A']);
}

// ---- source-shape guards -----------------------------------------------------
check('source: route guard publishes the handover box on every pass', /state\.guard = guard;/.test(guardSrc), true);
check('source: listeners register the trampoline, not the raw guard', /addEventListener\('popstate', fire\)/.test(guardSrc), true);
check('source: attachShadow is latched on the prototype', /attachShadow\.__wintageWrapped/.test(shadowSrc), true);
check('source: attachShadow publishes a handover box', /proto\.__wintageShadowCss = ACTIVE_SHADOW_CSS;/.test(shadowSrc), true);
check('source: stylesheet box is republished outside the install guard', /proto\.__wintageSheetOwner = function/.test(sheetSrc), true);
check('source: the install guard is still per-hook', /__wintagePatchedInsert/.test(sheetSrc), true);

console.log('');
if (bad) {
  console.log('generation handover test FAILED: ' + bad + ' assertion(s) failed');
  process.exit(1);
}
console.log('generation handover test PASS');