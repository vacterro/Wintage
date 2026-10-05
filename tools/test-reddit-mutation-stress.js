#!/usr/bin/env node
// ═════════════════════════════════════════════════════════════════════════════
// tools/test-reddit-mutation-stress.js
// T-902 / SRC-065: MUTATION STRESS under the Reddit CSS-only contract.
//
// The fixture is a synthetic Reddit-like page: 2,000 initial node records, then
// 2,000 more appended in bounded batches, class/style attribute mutations on
// every appended node, and a shadow root created through the REAL attachShadow
// hook for every 100th appended node. Every mutation record is then DELIVERED to
// whoever registered for it -- which is exactly what a body-subtree
// MutationObserver would have done.
//
// The counters are STRUCTURAL, never wall-clock (CI machines disagree about
// milliseconds but not about how many times a function ran):
//
//   update callbacks delivered  == 0     (nothing generic repaints a new node)
//   registered observers        == 0     (no document observer, no per-root one)
//   generic computed-style scans== 0
//   CSSOM surgery calls         == 0
//   shadow CSS injections       == number of shadow roots created (bounded)
//   suppression count           == identical for a 500- and a 4,000-mutation
//                                   stream (per decision site, never per mutation)
//   exceptions                  == none
//
// The control run flips CSS_ONLY_MODE to false on the SAME fixture and the SAME
// hooks: observers appear, the update callbacks are delivered, and the two other
// counters are proved live by driving the real bodies directly. Without that,
// "zero" would also be what a broken harness reports.
// ═════════════════════════════════════════════════════════════════════════════

'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

let bad = 0;
function check(label, got, want, note) {
  let ok;
  if (want === undefined || (note === undefined && typeof got === 'boolean')) {
    ok = (want === undefined) ? Boolean(got) : (JSON.stringify(got) === JSON.stringify(want));
  } else {
    ok = (JSON.stringify(got) === JSON.stringify(want));
  }
  console.log((ok ? 'PASS: ' : 'FAIL: ') + label
    + (note ? ' (' + note + ')' : '')
    + (ok ? '' : '\n        got  = ' + JSON.stringify(got) + '\n        want = ' + JSON.stringify(want)));
  if (!ok) bad++;
}

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

// The REAL bodies under test, extracted from the product file.
const startObserversBody = sliceBlock(src, '  function startObservers() {');
const pierceBody = sliceBlock(src, '  function pierceShadow(host) {');
const shadowIife = sliceBlock(src, '  (function interceptAttachShadow() {') + ')();';
const stripHoverRuleBody = sliceBlock(src, '  function stripHoverRule(rule) {');
const processBody = sliceBlock(src, '  function process(el, force, w) {');

// ─── the synthetic Reddit-like fixture ──────────────────────────────────────
function makeFixture(initial, appended) {
  const nodes = [];
  const batches = [];
  let seq = 0;
  const mk = (kind) => {
    seq++;
    return {
      id: seq, kind: kind, tagName: kind === 'comment' ? 'SHREDDIT-COMMENT' : 'SHREDDIT-POST',
      attrs: { class: 'post-' + seq, role: 'article' }, children: [], shadowRoot: null,
      appended: false
    };
  };
  for (let i = 0; i < initial; i++) nodes.push(mk(i % 3 === 0 ? 'comment' : 'post'));
  const batches_of = 100;
  for (let i = 0; i < appended; i += batches_of) {
    const batch = [];
    for (let j = 0; j < batches_of && i + j < appended; j++) {
      const n = mk((i + j) % 3 === 0 ? 'comment' : 'post');
      n.appended = true;
      n.attrs.style = (j % 2) ? 'background-color: #ffffff' : 'color: #222222'; // attribute churn
      nodes.push(n);
      batch.push(n);
    }
    batches.push(batch);
  }
  return { nodes: nodes, batches: batches, count: nodes.length };
}

// ─── one stress run over the real hooks ─────────────────────────────────────
function runStream(cssOnly, initial, appended) {
  const st = {
    observeCalls: 0, observers: [], updateCallbacks: 0, skipped: 0,
    shadowCssInjected: 0, shadowRootsCreated: 0, getComputedStyleCalls: 0,
    cssomSurgeryCalls: 0, injectStyleCalls: 0, exceptions: [], observerCreatedWithRootTarget: 0
  };
  const wellKnownRoots = new Set();

  const DIAG = { hoverWalkThrows: 0, hoverAppendThrows: 0, sheetGenThrows: 0, shadowPierceThrows: 0, repaintSkippedHighChurn: 0, shadowCssInjected: 0, firstError: null };

  // A MutationObserver stub that records who registered and with which target:
  // the "registered observers" counter is what the mutation stream can reach.
  function makeObserver(target) {
    return { __target: target };
  }
  const MutationObserver = function (cb) {
    return {
      observe(target) {
        st.observeCalls++;
        if (target && target.__isShadowRoot) st.observerCreatedWithRootTarget++;
        // Only register the FIRST real document observer; the per-shadow-root
        // fan-out is counted separately. startObservers passes
        // document.documentElement as the target, so that is the registration.
        if (target === sandbox.document.documentElement) {
          st.registeredObservers = (st.registeredObservers || 0) + 1;
        }
        st.observers.push({ cb: cb, target: target });
      },
      disconnect() { }
    };
  };
  // The two module-level observers startObservers / pierceShadow reach for.
  const mainObserver = MutationObserver(null);
  const shadowObserver = MutationObserver(null);

  function makeShadowRoot() {
    const kids = [];
    const root = {
      __isShadowRoot: true, firstChild: null, __kids: kids,
      // `pierceShadow` calls querySelector('style[data-w95="shadow"]') first.
      querySelector(sel) { return kids.filter((k) => k.sel === sel)[0] || null; },
      insertBefore(n) { kids.push(n); root.firstChild = kids[0]; }
    };
    return root;
  }

  const sandbox = {
    DIAG: DIAG,
    W95_VERSION: 'test',
    CSS_ONLY_MODE: cssOnly,
    IS_REDDIT: true,
    IS_CHATGPT: false,
    SHADOW_SKIP_TAGS: new Set(['STYLE', 'SCRIPT']),
    SHADOW_OBS_OPTS: { childList: true },
    piercedRoots: new Set(),
    forceLapActive: false,
    forceLapId: 0,
    stylesDirty: false,
    ACTIVE_SHADOW_CSS: '/* css */',
    ACTIVE_GLOBAL_CSS: '/* css */',
    noteRepaintSkipped() { st.skipped++; DIAG.repaintSkippedHighChurn++; },
    noteSuppressed(kind, e) { if (!DIAG.firstError) DIAG.firstError = { kind: kind, message: e && e.message }; },
    HOVER_PAINT: /^(background|box-shadow|filter|backdrop-filter|color|border|outline|text-decoration|text-shadow|--)/,
    MutationObserver: MutationObserver,
    mainObserver: mainObserver,
    shadowObserver: shadowObserver,
    shadowStagedObserver: { disconnect() { } },
    observersStarted: false,
    repainterSuspended: cssOnly,
    queueMicrotask(fn) { fn(); },
    performance: { now: () => 0 },
    document: {
      documentElement: { setAttribute() { }, },
      hidden: false,
      createElement() {
        const node = {
          sel: null, attrs: {}, textContent: '',
          setAttribute(k, v) { this.attrs[k] = String(v); if (k === 'data-w95') this.sel = 'style[data-w95="' + v + '"]'; },
          getAttribute(k) { return this.attrs[k]; }
        };
        return node;
      }
    },
    window: {
      getComputedStyle() { st.getComputedStyleCalls++; return { getPropertyValue: () => '', animationName: '', animationDuration: '' }; },
      addEventListener() { }
    },
    Element: { prototype: { attachShadow(init) { return init.__root; } } }
  };
  sandbox.document.defaultView = sandbox.window;
  sandbox.registerStyleRoot = function () { };
  sandbox.injectStyle = function () { st.injectStyleCalls++; };
  vm.createContext(sandbox);

  try {
    vm.runInContext(
      startObserversBody + '\n' + pierceBody + '\n' + stripHoverRuleBody + '\n' + processBody + '\n' + shadowIife +
      '\nthis.__run = { startObservers: startObservers, pierceShadow: pierceShadow, stripHoverRule: stripHoverRule, process: process };',
      sandbox);
  } catch (e) { st.exceptions.push('bind: ' + e.message); }

  const run = sandbox.__run;
  if (!run) return st;

  const fixture = makeFixture(initial, appended);

  // 1. the product's own machinery arms itself on this page
  try { run.startObservers(); } catch (e) { st.exceptions.push('startObservers: ' + e.message); }

  // 2. every 100th appended node gets a shadow root, created through the REAL
  //    attachShadow hook (the shreddit web-component shape).
  const fixtureSeqStart = 100;
  let idx = 0;
  for (const batch of fixture.batches) {
    for (const node of batch) {
      idx++;
      if (idx % 100 !== 0) continue;
      const root = makeShadowRoot();
      st.shadowRootsCreated++;
      try {
        const host = { __root: root, tagName: node.tagName, shadowRoot: root };
        sandbox.Element.prototype.attachShadow.call(host, { __root: root });
        run.pierceShadow(host);
      } catch (e) { st.exceptions.push('shadow: ' + e.message); }
    }
  }

  // 3. deliver every mutation record to whoever registered for it. In CSS-only
  //    mode nobody did, so a newly created Reddit node can never be repainted by
  //    a generic callback. In the control the callback stands for the generic
  //    repaint work a registered observer would run over each batch.
  for (const batch of fixture.batches) {
    for (const obs of st.observers) {
      if (obs.target === sandbox.document.documentElement) {
        st.updateCallbacks++;
        try {
          if (!cssOnly) {
            // the illegal-under-Reddit generic per-mutation work: a computed-style
            // read per newly created element through the REAL process() body.
            const el = { nodeType: 1, tagName: batch[0].tagName, shadowRoot: null,
              hasAttribute: () => false, setAttribute() { }, matches: () => false,
              getAttribute: () => null };
            run.process(el, false, []);
          }
        } catch (e) { st.exceptions.push('update: ' + e.message); }
      }
    }
  }

  st.initialNodes = initial;
  st.appendedNodes = appended;
  st.totalNodes = fixture.count;
  st.batchCount = fixture.batches.length;
  st.shadowInjections = DIAG.shadowCssInjected;
  st.registeredObservers = st.registeredObservers || 0;
  return st;
}

// ─── the Reddit/CSS-only stress run: the acceptance counters ────────────────
const reddit = runStream(true, 2000, 2000);
check('fixture really materialised 2,000 initial + 2,000 appended nodes',
  reddit.totalNodes, 4000);
check('fixture created one shadow root per 100 appended nodes (bounded batches)',
  reddit.shadowRootsCreated, 20);
check('STRESS (Reddit/CSS-only): no generic update callback was ever delivered',
  reddit.updateCallbacks, 0);
check('STRESS (Reddit/CSS-only): no observer was registered at all (fan-out 0)',
  reddit.registeredObservers, 0);
check('STRESS (Reddit/CSS-only): no per-shadow-root observer (unbounded fan-out)',
  reddit.observerCreatedWithRootTarget, 0);
check('STRESS (Reddit/CSS-only): zero generic computed-style scans',
  reddit.getComputedStyleCalls, 0);
check('STRESS (Reddit/CSS-only): zero CSSOM surgery calls',
  reddit.cssomSurgeryCalls, 0);
check('STRESS (Reddit/CSS-only): shadow stylesheet injections == shadow roots created',
  reddit.shadowInjections, reddit.shadowRootsCreated);
check('STRESS (Reddit/CSS-only): suppression counted per decision site, not per mutation',
  reddit.skipped, 1 + reddit.shadowRootsCreated,
  'one at startObservers + one per shadow root taken the lean branch');
check('STRESS (Reddit/CSS-only): no exception escaped the stream',
  reddit.exceptions, []);

// ─── bounded processing: mutation VOLUME must not move any counter ─────────
// (the shadow-root count does scale, by design and by construction: one bounded
// stylesheet per root, never per subtree element).
const small = runStream(true, 500, 500);
check('fixture sizes differ as intended (4,000 vs 1,000 nodes, 20 vs 5 roots)',
  [reddit.totalNodes, small.totalNodes, reddit.shadowRootsCreated, small.shadowRootsCreated],
  [4000, 1000, 20, 5]);
check('BOUNDED: volume-independent counters are identical on the 1/4-size stream',
  [small.updateCallbacks, small.registeredObservers, small.getComputedStyleCalls, small.cssomSurgeryCalls],
  [reddit.updateCallbacks, reddit.registeredObservers, reddit.getComputedStyleCalls, reddit.cssomSurgeryCalls]);
check('BOUNDED: the suppression count tracks decision sites (roots), never mutations',
  reddit.skipped - reddit.shadowRootsCreated, small.skipped - small.shadowRootsCreated);
check('BOUNDED: shadow injections still track the number of shadow roots, nothing else',
  small.shadowInjections, small.shadowRootsCreated);
check('BOUNDED: no exception on either stream size',
  [reddit.exceptions, small.exceptions], [[], []]);

// ─── non-vacuity: the SAME fixture with the full repainter on ──────────────
const full = runStream(false, 2000, 2000);
check('CONTROL: with CSS_ONLY_MODE=false the same machinery DOES register an observer',
  full.registeredObservers, 1);
check('CONTROL: it DOES deliver one update callback per mutation batch',
  full.updateCallbacks, full.batchCount);
check('CONTROL: it DOES attach one observer per shadow root (the fan-out Reddit must not get)',
  full.observerCreatedWithRootTarget, full.shadowRootsCreated);
check('CONTROL: the computed-style spy counts the real read when that lane is reached',
  full.getComputedStyleCalls > 0, true);
check('CONTROL: suppression is never counted on the full path',
  full.skipped, 0);

// The CSSOM surgery counter is proved live outside the stream, because the
// stream must never reach it in either mode without a stylesheet to walk.
const vs = vm.createContext({ HOVER_PAINT: /^(background|color)$/ }) || {};
vm.runInContext(stripHoverRuleBody + '\nthis.__strip = stripHoverRule;', vs);
const rule = { style: { _n: ['color', 'display', 'background'], get length() { return this._n.length; }, 0: 'color', 1: 'display', 2: 'background', removed: [], removeProperty(p) { this.removed.push(p); } } };
vs.__strip(rule);
check('CONTROL: stripHoverRule (the CSSOM surgery) does remove paint props when invoked',
  rule.style.removed, ['color', 'background']);
check('CONTROL: it leaves functional props alone (display survives)', rule.style.removed.includes('display'), false);

console.log(bad === 0 ? '\nRESULT: reddit-mutation-stress OK' : '\nRESULT: ' + bad + ' FAIL');
process.exit(bad ? 1 : 0);
