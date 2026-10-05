#!/usr/bin/env node
// ═════════════════════════════════════════════════════════════════════════════
// tools/test-reddit-repaint-gates.js
// T-902 / SRC-065: the SIDE-EFFECT GATES of the Reddit CSS-only contract.
//
// tools/test-reddit-cssonly.js proves the classification; this suite proves the
// consequence by driving the REAL function bodies in a vm with spies. Under a
// CSS-only host (which is what every Reddit host now is) the userscript must:
//
//   1. install no document-wide repaint observer,
//   2. run no CSSOM instrumentation / hover surgery,
//   3. schedule no force pass and no timer from the boot path,
//   4. attach no per-shadow-root repaint observer,
//   5. still inject the bounded creation-time shadow stylesheet.
//
// Each gate carries its OWN control with CSS_ONLY_MODE=false: without it a
// "nothing happened" assertion would also pass on a body that does nothing at
// all, which is not what is being claimed.
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

function sliceBlock(text, decl) {
  const i = text.indexOf(decl);
  if (i < 0) { console.error('FAIL: could not locate ' + decl); process.exit(1); }
  let depth = 0;
  for (let j = text.indexOf('{', i); j < text.length; j++) {
    if (text[j] === '{') depth++;
    else if (text[j] === '}') { depth--; if (depth === 0) return text.slice(i, j + 1); }
  }
  console.error('FAIL: unbalanced braces in ' + decl);
  process.exit(1);
}

// ─── GATE 1: no document-wide repaint observer ───────────────────────────────
const startObserversBody = sliceBlock(src, '  function startObservers() {');

function runStartObservers(cssOnly) {
  const st = { observeCalls: 0, skipped: 0 };
  const sandbox = {
    CSS_ONLY_MODE: cssOnly,
    repainterSuspended: false,
    observersStarted: false,
    mainObserver: { observe() { st.observeCalls++; } },
    document: { documentElement: {} },
    noteRepaintSkipped() { st.skipped++; }
  };
  vm.createContext(sandbox);
  vm.runInContext(startObserversBody + '\nstartObservers();', sandbox);
  st.observersStartedAfter = sandbox.observersStarted;
  return st;
}

const soReddit = runStartObservers(true);
check('GATE 1 (Reddit/CSS-only): startObservers installs NO document-wide observer',
  soReddit.observeCalls, 0);
check('GATE 1 (Reddit/CSS-only): the suppression is counted, not silent',
  soReddit.skipped, 1);
check('GATE 1 (Reddit/CSS-only): observersStarted stays false (no latch set)',
  soReddit.observersStartedAfter, false);
const soFull = runStartObservers(false);
check('GATE 1 control (non-churn host): the SAME body DOES install the observer',
  soFull.observeCalls, 1);
check('GATE 1 control (non-churn host): no suppression counted',
  soFull.skipped, 0);

// ─── GATE 2: no CSSOM instrumentation / hover-surgey on changing sheets ──────
// The two statements are read as one region: the suppression bump, then the
// real predicate that guards the prototype instrumentation.
const CSSOM_ANCHOR = /if \(CSS_ONLY_MODE\) noteRepaintSkipped\(\);\s*if \(!CSS_ONLY_MODE && typeof CSSStyleSheet/;
const cssomHeaderStart = src.search(CSSOM_ANCHOR);
check('GATE 2: the CSSOM gate region is present in the source', cssomHeaderStart > 0, true);
let cssomGate = '';
if (cssomHeaderStart > 0) {
  const stmtStart = src.lastIndexOf('if (CSS_ONLY_MODE) noteRepaintSkipped();', cssomHeaderStart);
  const brace = src.indexOf('{', src.indexOf("if (!CSS_ONLY_MODE && typeof CSSStyleSheet", stmtStart));
  cssomGate = src.slice(stmtStart, brace + 1) + ' __instrumented = true; }';
  check('GATE 2: the extracted region is the gate, not the whole instrumentation body',
    cssomGate.length < 260 && /^if \(CSS_ONLY_MODE\)/.test(cssomGate), true);
}

function runCssomGate(cssOnly) {
  const st = { skipped: 0, instrumented: false };
  const sandbox = {
    CSS_ONLY_MODE: cssOnly,
    CSSStyleSheet: { prototype: {} },
    noteRepaintSkipped() { st.skipped++; }
  };
  vm.createContext(sandbox);
  if (cssomGate) vm.runInContext(cssomGate, sandbox);
  st.instrumented = !!sandbox.__instrumented;
  return st;
}

const cgReddit = runCssomGate(true);
check('GATE 2 (Reddit/CSS-only): the CSSStyleSheet instrumentation block never runs',
  cgReddit.instrumented, false);
check('GATE 2 (Reddit/CSS-only): the CSSOM surgery suppression is counted',
  cgReddit.skipped, 1);
const cgFull = runCssomGate(false);
check('GATE 2 control: on a non-churn host the SAME predicate instruments the sheet prototype',
  cgFull.instrumented, true);
check('GATE 2 control: no suppression counted', cgFull.skipped, 0);

// ─── GATE 3: no force pass, no timer, no polling from the boot path ─────────
const startSweepingBody = sliceBlock(src, '  function startSweeping() {');

function runStartSweeping(opts) {
  const st = {
    forceSweeps: 0, timers: 0, injectLateCalls: 0, startObserversCalls: 0,
    skipped: 0, attrs: {}, loadListeners: 0
  };
  const sandbox = {
    CSS_ONLY_MODE: opts.cssOnly,
    IS_REDDIT: !!opts.isReddit,
    IS_CHATGPT: !!opts.isChatGPT,
    IS_TOP: true,
    noteRepaintSkipped() { st.skipped++; },
    injectLate() { st.injectLateCalls++; },
    startObservers() { st.startObserversCalls++; },
    requestForceSweep() { st.forceSweeps++; },
    setTimeout() { st.timers++; return 1; },
    document: {
      documentElement: { setAttribute(n, v) { st.attrs[n] = String(v); } },
      hidden: false,
      addEventListener(type, fn, o) { if (type === 'load' && o && o.once) st.loadListeners++; }
    },
    window: { addEventListener(type, fn, o) { if (type === 'load' && o && o.once) st.loadListeners++; } }
  };
  vm.createContext(sandbox);
  vm.runInContext(startSweepingBody + '\nstartSweeping();', sandbox);
  return st;
}

const ssReddit = runStartSweeping({ cssOnly: true, isReddit: true });
check('GATE 3 (Reddit/CSS-only): no force pass requested', ssReddit.forceSweeps, 0);
check('GATE 3 (Reddit/CSS-only): no timer scheduled (no 1.5s/3s settling pass)', ssReddit.timers, 0);
check('GATE 3 (Reddit/CSS-only): the boot path still injects the late stylesheet once', ssReddit.injectLateCalls, 1);
check('GATE 3 (Reddit/CSS-only): still calls startObservers (which is itself gated)', ssReddit.startObserversCalls, 1);
check('GATE 3 (Reddit/CSS-only): exactly one `load`-once listener, no repeating listener',
  ssReddit.loadListeners, 1);
check('GATE 3 (Reddit/CSS-only): stamps data-w95-perf=css-only',
  ssReddit.attrs['data-w95-perf'], 'css-only');
check('GATE 3 (Reddit/CSS-only): stamps the reason as reddit-lean-css',
  ssReddit.attrs['data-w95-perf-reason'], 'reddit-lean-css');
check('GATE 3 (Reddit/CSS-only): suppression counted once at the boot decision',
  ssReddit.skipped, 1);

const ssChatGpt = runStartSweeping({ cssOnly: true, isChatGPT: true });
check('GATE 3 (ChatGPT/CSS-only): the reason string is host-derived, not hardcoded',
  ssChatGpt.attrs['data-w95-perf-reason'], 'chatgpt-lean-css');
const ssOther = runStartSweeping({ cssOnly: true });
check('GATE 3 (other high-churn/CSS-only): generic reason is kept for the other hosts',
  ssOther.attrs['data-w95-perf-reason'], 'known-high-churn-host');

const ssFull = runStartSweeping({ cssOnly: false });
check('GATE 3 control (non-churn host): the SAME body DOES request a force pass',
  ssFull.forceSweeps, 1);
check('GATE 3 control (non-churn host): the settling timer is scheduled',
  ssFull.timers, 1);
check('GATE 3 control (non-churn host): no css-only stamp is written',
  Object.prototype.hasOwnProperty.call(ssFull.attrs, 'data-w95-perf'), false);

// ─── GATE 4: no per-shadow-root repaint observer, injection retained ────────
const pierceBody = sliceBlock(src, '  function pierceShadow(host) {');

function runPierce(cssOnly) {
  const st = { observeCalls: 0, injectCalls: 0, skipped: 0, suppressed: 0 };
  const root = { __kind: 'shadow-root' };
  const sandbox = {
    CSS_ONLY_MODE: cssOnly,
    SHADOW_SKIP_TAGS: new Set(['STYLE', 'SCRIPT']),
    SHADOW_OBS_OPTS: { childList: true },
    piercedRoots: new Set(),
    forceLapActive: false,
    forceLapId: 0,
    stylesDirty: false,
    ACTIVE_SHADOW_CSS: '/* css */',
    shadowObserver: { observe() { st.observeCalls++; } },
    registerStyleRoot() { },
    injectStyle() { st.injectCalls++; },
    noteRepaintSkipped() { st.skipped++; },
    noteSuppressed() { st.suppressed++; }
  };
  vm.createContext(sandbox);
  sandbox.host = { tagName: 'SHREDDIT-POST', shadowRoot: root };
  vm.runInContext(pierceBody + '\npierceShadow(host);\nstylesDirty = stylesDirty;', sandbox);
  st.stylesDirtyAfter = sandbox.stylesDirty;
  return st;
}

const pReddit = runPierce(true);
check('GATE 4 (Reddit/CSS-only): no per-shadow-root observer is attached',
  pReddit.observeCalls, 0);
check('GATE 4 (Reddit/CSS-only): the creation-time shadow stylesheet IS still injected',
  pReddit.injectCalls, 1);
check('GATE 4 (Reddit/CSS-only): the skipped observer is counted', pReddit.skipped, 1);
check('GATE 4 (Reddit/CSS-only): no stylesheet-dirty wake is raised for a new root',
  pReddit.stylesDirtyAfter, false);
const pFull = runPierce(false);
check('GATE 4 control: on a non-churn host the SAME body does observe the root',
  pFull.observeCalls, 1);
check('GATE 4 control: it also marks styles dirty for a repaint',
  pFull.stylesDirtyAfter, true);
check('GATE 4: pierceShadow never walks into the root (no recursion, no fan-out)',
  /querySelectorAll|childNodes|\.children\b/.test(pierceBody), false);

// ─── GATE 5: creation-time injection survives; no observer inside the hook ──
const shadowIife = sliceBlock(src, '  (function interceptAttachShadow() {');
// sliceBlock stops at the closing brace of the function expression; the source
// closes the statement with `)();` after it, so the call is appended here.
check('GATE 5: the attachShadow hook slice is the IIFE itself',
  /^\s*\(function interceptAttachShadow\(\)/.test(shadowIife), true);
const shadowIifeCall = shadowIife + ')();';

function runShadowHook(rootCount) {
  const st = { injected: 0, observerRefs: 0, roots: [] };
  const DIAG = { shadowCssInjected: 0, firstError: null };
  function makeRoot() {
    const kids = [];
    const root = {
      firstChild: null,
      querySelector(sel) { return kids.filter((k) => k.sel === sel)[0] || null; },
      insertBefore(node) { kids.push(node); root.firstChild = kids[0]; },
      __kids: kids
    };
    return root;
  }
  const sandbox = {
    DIAG: DIAG,
    W95_VERSION: 'test',
    ACTIVE_SHADOW_CSS: '/* css */',
    queueMicrotask(fn) { fn(); },
    document: {
      createElement() {
        const node = { sel: null, attrs: {}, setAttribute(n, v) { this.attrs[n] = String(v); if (n === 'data-w95') this.sel = 'style[data-w95="shadow"]'; } };
        return node;
      }
    },
    Element: { prototype: { attachShadow(init) { return init.__root; } } },
    MutationObserver: function () { st.observerRefs++; }
  };
  vm.createContext(sandbox);
  vm.runInContext(shadowIifeCall, sandbox);
  const hosts = [];
  for (let i = 0; i < rootCount; i++) {
    const root = makeRoot();
    const host = { __root: root };
    hosts.push(host);
    sandbox.Element.prototype.attachShadow.call(host, { __root: root });
    st.roots.push(root);
  }
  st.injected = DIAG.shadowCssInjected;
  st.registry = sandbox.Element.prototype.__wintageShadowRoots;
  return st;
}

const sh = runShadowHook(5);
check('GATE 5 (Reddit/CSS-only): one creation-time shadow stylesheet per shadow root',
  sh.injected, 5);
check('GATE 5 (Reddit/CSS-only): every root carries the injected style as its first child',
  sh.roots.every((r) => r.__kids.length === 1 && r.__kids[0].attrs['data-w95'] === 'shadow'), true);
check('GATE 5 (Reddit/CSS-only): the hook builds no MutationObserver at all',
  sh.observerRefs, 0);
check('GATE 5: the hook body registers no observer and no timer',
  /\.observe\(|MutationObserver|setInterval|setTimeout/.test(shadowIife), false);
check('GATE 5: a second generation restyles instead of double-injecting', (() => {
  // Run the same hook twice over the same prototype: the handover box must make
  // the re-install a no-op for the roots, not a second stylesheet.
  const st2 = { injected: 0 };
  const DIAG = { shadowCssInjected: 0, firstError: null };
  const kids = [];
  const root = {
    firstChild: null,
    querySelector(sel) { return kids.filter((k) => k.sel === sel)[0] || null; },
    insertBefore(n) { kids.push(n); root.firstChild = kids[0]; }
  };
  const sandbox = {
    DIAG, W95_VERSION: 'test', ACTIVE_SHADOW_CSS: '/* css */',
    queueMicrotask(fn) { fn(); },
    document: { createElement() { const n = { sel: null, attrs: {}, setAttribute(k, v) { this.attrs[k] = String(v); if (k === 'data-w95') this.sel = 'style[data-w95="shadow"]'; }, getAttribute(k) { return this.attrs[k]; }, textContent: '' }; return n; } },
    Element: { prototype: { attachShadow() { return root; } } }
  };
  vm.createContext(sandbox);
  vm.runInContext(shadowIifeCall, sandbox);
  vm.runInContext(shadowIifeCall, sandbox);
  sandbox.Element.prototype.attachShadow.call({}, {});
  st2.injected = DIAG.shadowCssInjected;
  st2.kids = kids.length;
  return st2.kids === 1 && st2.injected === 1;
})(), true);

// ─── static complements (bounded, not a substitute for the gates above) ─────
check('static: no setInterval anywhere (no periodic repaint timer)',
  (src.match(/setInterval/g) || []).length, 0);
check('static: no requestAnimationFrame anywhere (no per-frame repaint loop)',
  (src.match(/requestAnimationFrame/g) || []).length, 0);
check('static: shadowObserver.observe appears exactly once in the source',
  (src.match(/shadowObserver\.observe\(/g) || []).length, 1);
const soIdx = src.indexOf('shadowObserver.observe(');
check('static: that one shadow registration sits behind the !CSS_ONLY_MODE guard',
  src.lastIndexOf('if (!CSS_ONLY_MODE) {', soIdx) > src.lastIndexOf('if (CSS_ONLY_MODE)', soIdx), true);
check('static: mainObserver.observe appears exactly once and inside startObservers',
  (src.match(/mainObserver\.observe\(/g) || []).length === 1
  && startObserversBody.includes('mainObserver.observe('), true);
check('static: the repainter is pre-suspended by the same single authority',
  /let repainterSuspended = CSS_ONLY_MODE;/.test(src), true);
check('static: every sweep entry point re-checks repainterSuspended (the second belt)',
  (src.match(/if \(repainterSuspended\) return;/g) || []).length >= 3, true);
// Reachability of the ONE computed-style read (PERF-002's rule: process reads,
// it never writes). It lives inside process(), and every process() call site
// lives in one of the three lanes CSS-only mode never starts -- the mutation
// handler (whose only driver is the un-observed MutationObserver), the sweeper,
// and the attribute slice the mutation lane arms. Each lane refuses to run while
// the repainter is suspended.
const stripped = src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^[ \t]*\/\/.*$/gm, '');
const processBody = sliceBlock(stripped, 'function process(el, force, w) {');
check('static: exactly one real computed-style read exists in code (comments excluded)',
  (stripped.match(/window\.getComputedStyle\(/g) || []).length, 1);
check('static: that read lives inside process()',
  processBody.includes('window.getComputedStyle('), true);
const onMutationsBody = sliceBlock(stripped, 'function onMutations(mutations) {');
const runSweeperBody = sliceBlock(stripped, 'function runSweeper(force) {');
const drainAttributeBody = sliceBlock(stripped, 'function drainAttributeSlice() {');
const noDef = (t) => t.replace('function process(el, force, w) {', '');
check('static: every process() call site is inside a sweep lane (none is reachable idle)',
  (noDef(stripped).match(/\bprocess\(/g) || []).length,
  (noDef(onMutationsBody + runSweeperBody + drainAttributeBody).match(/\bprocess\(/g) || []).length);
check('static: the mutation handler refuses a suspended repainter before it queues work',
  /^function onMutations\(mutations\) \{\s*if \(repainterSuspended\b/.test(onMutationsBody.trim()), true);
check('static: the sweeper refuses a suspended repainter at its entry',
  /^function runSweeper\(force\) \{\s*if \(repainterSuspended\) return;/.test(runSweeperBody.trim()), true);
check('static: the attribute slice bails out mid-lane if suspension lands',
  /if \(repainterSuspended\) \{ finishAttributeLane\(\); return; \}/.test(drainAttributeBody), true);
check('static: the diagnostic surface exposes the Reddit CSS-only facts',
  ['redditCssOnly', 'repaintSkippedHighChurn', 'shadowCssInjected'].every((k) => src.includes(k)), true);

console.log(bad === 0 ? '\nRESULT: reddit-repaint-gates OK' : '\nRESULT: ' + bad + ' FAIL');
process.exit(bad ? 1 : 0);
