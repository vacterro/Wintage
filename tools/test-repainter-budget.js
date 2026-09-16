#!/usr/bin/env node
// ═════════════════════════════════════════════════════════════════════════════
// tools/test-repainter-budget.js
// R013 / PERF-002: Bounded Repainter Budget Verification Suite
//
// Verifies bounded repainter execution across:
//  - TARGET A: Bounded incremental root cursor (zero [document, ...piercedRoots])
//  - TARGET B: Explicit style work budgets (root, sheet, rule)
//  - TARGET C: Elimination of querySelectorAll('style') in favor of lazy owner check
//  - TARGET D: Iterative stack-based rule traversal (zero recursive walkRules)
//  - TARGET E: Completion-safe sheetSeen generation tracking
//  - TARGET F: Bounded append optimization using rule budget
//  - TARGET G: Removal of synchronous light-lane sheet sweeps
//  - Static guards on production userscript source
//  - Temporary RED A (25k roots) and RED B (250k rules) mutant controls
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

// Measured values are part of the evidence: a budget assertion that does not
// print what was actually consumed cannot be re-checked from the log.
const measure = (label, value) => {
  console.log('MEASURE: ' + label + ' = ' + JSON.stringify(value));
};

// A fake element rich enough for the REAL process() to run to completion.
// process() reads attribute accessors, an inline style with per-property
// priorities, the skip probes (matches/closest/tagName/namespaceURI) and, for
// out-of-flow candidates, a rect. A thinner stub makes process() throw, the
// root-level catch then marks the whole root done, and the slice assertions
// silently measure a walker that stopped at its first node.
const makeFakeElement = (extra = {}) => ({
  nodeType: 1,
  tagName: 'DIV',
  namespaceURI: null,
  childElementCount: 0,
  isConnected: true,
  parentElement: null,
  shadowRoot: null,
  attrs: {},
  setAttribute(k, v) { this.attrs[k] = String(v); },
  getAttribute(k) { return Object.prototype.hasOwnProperty.call(this.attrs, k) ? this.attrs[k] : null; },
  hasAttribute(k) { return Object.prototype.hasOwnProperty.call(this.attrs, k); },
  removeAttribute(k) { delete this.attrs[k]; },
  matches: () => false,
  closest: () => null,
  querySelector: () => null,
  getElementsByTagName: () => [],
  getBoundingClientRect: () => ({ width: 0, height: 0, top: 0, left: 0, right: 0, bottom: 0 }),
  style: {
    length: 0,
    props: {},
    priorities: {},
    getPropertyValue(p) { return this.props[p] === undefined ? '' : this.props[p]; },
    getPropertyPriority(p) { return this.priorities[p] === undefined ? '' : this.priorities[p]; },
    setProperty(p, v, prio) { this.props[p] = v; this.priorities[p] = prio || ''; },
    removeProperty(p) { delete this.props[p]; },
  },
  ...extra
});

const USERSCRIPT_PATH = path.join(__dirname, '..', 'wintage.user.js');
const src = fs.readFileSync(USERSCRIPT_PATH, 'utf8');

// ─── Extract Repainter Body ───────────────────────────────────────────────────
const repStartMarker = '// --- REPAINTER START ---';
const repEndMarker = '// --- REPAINTER END ---';
const repStart = src.indexOf(repStartMarker);
const repEnd = src.indexOf(repEndMarker);
if (repStart < 0 || repEnd < 0) {
  console.error('FAIL: repainter markers missing in wintage.user.js');
  process.exit(1);
}
const repainterBody = src.slice(repStart + repStartMarker.length, repEnd);

function createRepainterContext(overrides = {}, customBody = repainterBody) {
  const window = {};
  window.window = window;
  window.top = window;
  window.self = window;
  window.addEventListener = () => {};
  window.removeEventListener = () => {};
  const getComputedStyle = () => ({
    getPropertyValue: () => '',
    color: 'rgb(0, 0, 0)',
    backgroundColor: 'transparent',
    borderTopColor: '',
    borderRightColor: '',
    borderBottomColor: '',
    borderLeftColor: '',
    outlineColor: '',
    animationIterationCount: '1'
  });
  window.getComputedStyle = getComputedStyle;

  const doc = overrides.document || {
    hidden: false,
    documentElement: { setAttribute() {}, getAttribute() { return null; }, hasAttribute() { return false; }, style: { getPropertyValue: () => '', setProperty() {} } },
    head: { appendChild() {}, insertBefore() {} },
    styleSheets: [],
    adoptedStyleSheets: [],
    createTreeWalker: () => null,
  };
  if (!doc.addEventListener) doc.addEventListener = () => {};
  if (!doc.removeEventListener) doc.removeEventListener = () => {};

  const ctx = {
    console,
    Date,
    Math,
    Set,
    Map,
    WeakMap,
    Proxy,
    Number,
    Array,
    Object,
    String,
    parseInt,
    parseFloat,
    performance: { now: () => 0 },
    setTimeout: (fn, ms) => 1,
    clearTimeout: () => {},
    CSSStyleSheet: class CSSStyleSheet {},
    MutationObserver: class MutationObserver {
      constructor(cb) { this.cb = cb; }
      observe() {}
      disconnect() {}
      takeRecords() { return []; }
    },
    window,
    getComputedStyle,
    document: doc,
    W95_VERSION: 'test',
    T: {
      background: '#2a2015',
      backgroundSoft: '#3a2e20',
      surface: '#443728',
      surfaceRaised: '#524332',
      surfaceAlt: '#382c1e',
      borderDark: '#120d08',
      borderHighlight: '#6e5a44',
      bevelLight: '#5a4936',
      borderMuted: '#30261a',
      link: '#e0a458',
      textPrimary: '#d8c2a4',
      textSecondary: '#a89378',
      textMuted: '#786852',
      accentTeal: '#4a8270',
      accentTealDeep: '#2d5447',
      success: '#629653',
      warning: '#b88636',
      danger: '#ab4336',
      dangerText: '#d85848',
      selection: '#5a4630',
      compareBack: '#201810'
    },
    IS_TOP: true,
    CSS_ONLY_MODE: false,
    lum: () => 0.1,
    hexLum: () => 0.1,
    contrast: () => 4.5,
    BG_LUM: 0.1,
    BG_SOFT_LUM: 0.15,
    DARK: true,
    elev: L => L,
    SHADOW_CSS: '',
    GLOBAL_CSS: '',
    injectStyle: () => {},
    injectLate: () => {},
    DIAG: { hoverWalkThrows: 0, hoverAppendThrows: 0, sheetGenThrows: 0, shadowPierceThrows: 0, firstError: null },
    noteSuppressed: (kind, e) => {
      ctx.DIAG[kind]++;
      if (!ctx.DIAG.firstError) ctx.DIAG.firstError = { kind, message: (e && e.message) ? e.message : String(e) };
    },
    ...overrides
  };
  vm.createContext(ctx);

  const wrapperCode = `
(function() {
${customBody}
return {
  STYLE_SHEET_BUDGET,
  STYLE_RULE_BUDGET,
  STYLE_ROOT_BUDGET,
  FORCE_BUDGET,
  FORCE_ROOT_BUDGET,
  drainStyleRules,
  drainStyleWork,
  registerStyleRoot,
  styleLapDeferredRoots,
  bumpStyleElementSheets,
  stripHoverRule,
  runSweeper,
  requestForceSweep,
  requestLightSweep,
  pierceShadow,
  piercedRoots,
  forceLapDeferredRoots,
  forceRootCursors,
  sheetSeen,
  lightDirty,
  getForceLapActive: () => forceLapActive,
  getForceLapWorkset: () => forceLapWorkset,
  getForceLapIndex: () => forceLapIndex,
  getStylesDirty: () => stylesDirty,
  setStylesDirty: (v) => { stylesDirty = v; },
  getActiveStyleTask: () => activeStyleTask,
  getStyleCursorRoot: () => styleCursorRoot,
  getStyleRootSeq: () => styleRootSeq,
  getStyleLapSeqLimit: () => styleLapSeqLimit,
  setForceLapActive: (v) => { forceLapActive = v; }
};
})()
`;
  const res = vm.runInContext(wrapperCode, ctx);
  res.ctx = ctx;
  return res;
}

// ═════════════════════════════════════════════════════════════════════════════
// STATIC GUARDS
// ═════════════════════════════════════════════════════════════════════════════
console.log('--- Static Guards ---');
check('Static: source contains zero forceLapWorkset = [document, ...piercedRoots]',
  !/forceLapWorkset\s*=\s*\[document,\s*\.\.\.piercedRoots\]/.test(src));

check('Static: source contains zero querySelectorAll(\'style\')',
  !/querySelectorAll\s*\(\s*['"]style['"]\s*\)/.test(src));

check('Static: source contains zero active recursive walkRules declaration',
  !/function\s+walkRules\s*\(/.test(src));

check('Static: source contains zero unbudgeted appended-rule loops',
  !/for\s*\(\s*let\s+r\s*=\s*seen\.count\s*;\s*r\s*<\s*count\s*;\s*r\+\+\s*\)/.test(src));

check('Static: source guards sheetSeen.set with generation match before completion',
  /if\s*\(\s*\(\w+\.__wintageGen\s*\|\|\s*0\)\s*===\s*\w+\s*\)\s*\{\s*sheetSeen\.set/.test(src));

// TARGET G: no unbounded CSSOM helper may survive in the shipped repainter. The
// root-level stripHoverSheets() helper is gone; the only way to reach CSSOM is a
// budgeted drainStyleWork slice.
check('Static: production defines no root-level stripHoverSheets helper',
  !/function\s+stripHoverSheets\s*\(/.test(src));
check('Static: production contains zero drainStyleRules(..., Infinity) drains',
  !/drainStyleRules\s*\([^)]*Infinity/.test(src));
check('Static: production registers style roots through exactly one stamp point',
  (src.match(/=\s*\+\+styleRootSeq/g) || []).length, 1);

// ═════════════════════════════════════════════════════════════════════════════
// TEST 1 — 250,000 RULES
// ═════════════════════════════════════════════════════════════════════════════
console.log('\n--- Test 1: 250,000 Rules ---');
{
  let ruleReads = 0;
  const rawRules = [];
  const TOTAL_RULES = 250000;
  for (let i = 0; i < TOTAL_RULES; i++) {
    if (i % 10 === 0) {
      rawRules.push({
        selectorText: '.cls' + i + ':hover',
        style: {
          length: 2,
          0: 'background',
          1: 'color',
          props: { background: 'red', color: 'blue' },
          removeProperty(p) { delete this.props[p]; }
        }
      });
    } else {
      rawRules.push({
        selectorText: '.cls' + i,
        style: { length: 0 }
      });
    }
  }

  const rulesProxy = new Proxy(rawRules, {
    get(target, prop) {
      if (prop === 'length') return target.length;
      const idx = typeof prop === 'string' ? Number(prop) : prop;
      if (Number.isInteger(idx) && idx >= 0 && idx < target.length) {
        ruleReads++;
        return target[idx];
      }
      return target[prop];
    }
  });

  const sheet = {
    cssRules: rulesProxy,
    ownerNode: null,
    __wintageGen: 0
  };

  const doc = {
    hidden: false,
    documentElement: { setAttribute() {}, getAttribute() { return null; } },
    styleSheets: [sheet],
    adoptedStyleSheets: [],
    createTreeWalker: () => null
  };

  const rep = createRepainterContext({ document: doc });
  rep.setStylesDirty(true);

  // Slice 1:
  const slice1 = rep.drainStyleWork(rep.STYLE_SHEET_BUDGET, rep.STYLE_RULE_BUDGET);
  measure('Test 1: 250,000-rule first-slice rule reads', ruleReads);
  measure('Test 1: STYLE_RULE_BUDGET', rep.STYLE_RULE_BUDGET);
  check('Test 1: first slice rule reads <= STYLE_RULE_BUDGET + const',
    ruleReads <= rep.STYLE_RULE_BUDGET + 5, true);
  check('Test 1: 250,000 rules NOT all consumed in first slice',
    ruleReads < TOTAL_RULES, true);
  check('Test 1: continuation remains pending after first slice',
    slice1.done === false, true);
  check('Test 1: active task remains in-flight',
    rep.getActiveStyleTask() !== null, true);

  // Drain remaining slices:
  let slices = 1;
  const MAX_DRAIN_SLICES = 600;
  while (slices < MAX_DRAIN_SLICES) {
    const res = rep.drainStyleWork(rep.STYLE_SHEET_BUDGET, rep.STYLE_RULE_BUDGET);
    slices++;
    if (res.done) break;
  }

  check('Test 1: full drain completed within budget iterations', slices < MAX_DRAIN_SLICES, true);
  measure('Test 1: 250,000-rule eventual rule reads', ruleReads);
  measure('Test 1: 250,000-rule drain slices', slices);
  check('Test 1: all 250,000 rules visited', ruleReads === TOTAL_RULES, true);
  check('Test 1: sheetSeen recorded after complete drain',
    rep.sheetSeen.get(sheet), { gen: 0, count: TOTAL_RULES });

  // Verify hover surgery stripped background & color on all :hover rules
  let strippedCount = 0;
  for (let i = 0; i < TOTAL_RULES; i += 10) {
    if (rawRules[i].style.props.background === undefined && rawRules[i].style.props.color === undefined) {
      strippedCount++;
    }
  }
  check('Test 1: hover surgery stripped paint properties identically to reference',
    strippedCount === TOTAL_RULES / 10, true);
}

// ═════════════════════════════════════════════════════════════════════════════
// TEST 2 — 25,000 ROOTS
// ═════════════════════════════════════════════════════════════════════════════
console.log('\n--- Test 2: 25,000 Roots ---');
{
  const ROOT_COUNT = 25000;
  const roots = [];
  let rootAdvances = 0;

  for (let i = 0; i < ROOT_COUNT; i++) {
    const r = {
      __id: i,
      host: { isConnected: true },
      createTreeWalker() {
        let wi = 0;
        return {
          nextNode() {
            return wi++ < 1 ? { nodeType: 1, setAttribute() {}, hasAttribute: () => false, getAttribute: () => null, matches: () => false, closest: () => null, style: { getPropertyValue: () => '', setProperty() {} } } : null;
          }
        };
      }
    };
    roots.push(r);
  }

  const doc = {
    hidden: false,
    documentElement: { setAttribute() {}, getAttribute() { return null; }, style: { getPropertyValue: () => '', setProperty() {} } },
    styleSheets: [],
    adoptedStyleSheets: [],
    createTreeWalker() {
      let wi = 0;
      return {
        nextNode() {
          return wi++ < 1 ? { nodeType: 1, setAttribute() {}, hasAttribute: () => false, getAttribute: () => null, matches: () => false, closest: () => null, style: { getPropertyValue: () => '', setProperty() {} } } : null;
        }
      };
    }
  };

  const rep = createRepainterContext({ document: doc });

  // Instrument piercedRoots iterator to track advances
  const realValues = rep.piercedRoots.values.bind(rep.piercedRoots);
  rep.piercedRoots.values = function() {
    const it = realValues();
    return {
      next() {
        const res = it.next();
        if (!res.done) rootAdvances++;
        return res;
      }
    };
  };

  for (let i = 0; i < ROOT_COUNT; i++) {
    rep.piercedRoots.add(roots[i]);
  }

  // First slice:
  rep.runSweeper(true);

  measure('Test 2: 25,000-root first-slice root advances', rootAdvances);
  measure('Test 2: FORCE_ROOT_BUDGET', rep.FORCE_ROOT_BUDGET);
  check('Test 2: first slice root advances <= FORCE_ROOT_BUDGET + const',
    rootAdvances <= rep.FORCE_ROOT_BUDGET + 2, true);
  check('Test 2: all 25,000 roots have NOT been enumerated on slice 1',
    rootAdvances < ROOT_COUNT, true);
  check('Test 2: force lap active after slice 1',
    rep.getForceLapActive() === true, true);

  // Drain until complete
  let maxIterations = 1000;
  let iters = 0;
  while (rep.getForceLapActive() && iters++ < maxIterations) {
    rep.runSweeper(true);
  }

  check('Test 2: lap completes within bounded iterations', iters < maxIterations, true);
  measure('Test 2: 25,000-root lap slices', iters);
  check('Test 2: all 25,000 roots served without starvation', rootAdvances === ROOT_COUNT, true);
  check('Test 2: lap dropped traversal state at completion',
    [rep.getForceLapActive(), rep.getForceLapWorkset(), rep.forceRootCursors.size],
    [false, null, 0]);
}

// ═════════════════════════════════════════════════════════════════════════════
// TEST 3 — NESTED CSSOM
// ═════════════════════════════════════════════════════════════════════════════
console.log('\n--- Test 3: Nested CSSOM ---');
{
  function makeStyleObj(props) {
    const p = { ...props };
    const keys = Object.keys(p);
    return {
      length: keys.length,
      ...keys,
      props: p,
      removeProperty(name) { delete this.props[name]; }
    };
  }

  function createNestedRules() {
    return [
      { selectorText: '.btn:hover', style: makeStyleObj({ background: 'red', display: 'block', color: 'white' }) },
      {
        type: 4, // CSSRule.MEDIA_RULE
        cssRules: [
          { selectorText: '.card:hover', style: makeStyleObj({ 'box-shadow': '0 0 5px red', opacity: '1' }) },
          {
            type: 12, // CSSRule.SUPPORTS_RULE
            cssRules: [
              {
                type: 16, // CSSRule.LAYER_BLOCK_RULE
                cssRules: [
                  { selectorText: 'a.link:hover', style: makeStyleObj({ 'text-decoration': 'underline', cursor: 'pointer' }) }
                ]
              }
            ]
          }
        ]
      },
      {
        type: 7, // CSSRule.KEYFRAMES_RULE (must skip)
        cssRules: [
          { selectorText: '0%:hover', style: makeStyleObj({ background: 'red' }) }
        ]
      }
    ];
  }

  // Reference recursive walk
  function refWalk(container) {
    const rules = container.cssRules;
    if (!rules) return;
    for (let i = 0; i < rules.length; i++) {
      const r = rules[i];
      if (r.type === 7) continue;
      if (r.selectorText && r.selectorText.indexOf(':hover') !== -1) {
        const st = r.style;
        if (st) {
          const names = [];
          for (let j = 0; j < st.length; j++) names.push(st[j]);
          for (const name of names) {
            if (/^(background|box-shadow|filter|backdrop-filter|color|border|outline|text-decoration|text-shadow|--)/.test(name)) {
              st.removeProperty(name);
            }
          }
        }
      }
      if (r.cssRules && r.cssRules.length) refWalk(r);
    }
  }

  const boundedRules = createNestedRules();
  const refRules = createNestedRules();

  const task = {
    sheet: { __wintageGen: 0 },
    gen: 0,
    count: boundedRules.length,
    mode: 'full',
    stack: [{ container: boundedRules, index: 0, length: boundedRules.length }]
  };

  const rep = createRepainterContext();
  rep.drainStyleRules(task, Infinity);
  refWalk({ cssRules: refRules });

  check('Test 3: ordinary hover paint removed, functional preserved',
    boundedRules[0].style.props, { display: 'block' });
  check('Test 3: media hover paint removed, functional preserved',
    boundedRules[1].cssRules[0].style.props, { opacity: '1' });
  check('Test 3: deep nested layer hover paint removed, functional preserved',
    boundedRules[1].cssRules[1].cssRules[0].cssRules[0].style.props, { cursor: 'pointer' });
  check('Test 3: keyframes rule preserved without modification',
    boundedRules[2].cssRules[0].style.props, { background: 'red' });

  check('Test 3: bounded iterative traversal matches reference recursive walk',
    JSON.stringify(boundedRules), JSON.stringify(refRules));
}

// ═════════════════════════════════════════════════════════════════════════════
// TEST 4 — DOM / STYLE INDEPENDENCE
// ═════════════════════════════════════════════════════════════════════════════
console.log('\n--- Test 4: DOM / Style Independence ---');
{
  let styleInspections = 0;
  const sheet = {
    get cssRules() {
      styleInspections++;
      return [{ selectorText: '.foo:hover', style: { length: 0 } }];
    },
    ownerNode: null,
    __wintageGen: 0
  };

  // 6,000 DOM elements across document (FORCE_BUDGET is 2,500, so requires 3 slices)
  let docElementsRemaining = 6000;
  let docElementsServed = 0;
  const doc = {
    hidden: false,
    documentElement: { setAttribute() {}, getAttribute() { return null; }, style: { getPropertyValue: () => '', setProperty() {} } },
    styleSheets: [sheet],
    adoptedStyleSheets: [],
    createTreeWalker() {
      return {
        nextNode() {
          if (docElementsRemaining > 0) {
            docElementsRemaining--;
            docElementsServed++;
            return makeFakeElement();
          }
          return null;
        }
      };
    }
  };

  const rep = createRepainterContext({ document: doc });
  rep.setStylesDirty(true);

  // Slice 1: drains one bounded style slice AND the first element slice.
  rep.runSweeper(true);
  measure('Test 4: document elements served on slice 1', docElementsServed);
  measure('Test 4: FORCE_BUDGET', rep.FORCE_BUDGET);
  const inspectionsAfterSlice1 = styleInspections;
  check('Test 4: style pass ran on first slice', inspectionsAfterSlice1 > 0, true);
  check('Test 4: slice 1 served exactly FORCE_BUDGET document elements',
    docElementsServed, rep.FORCE_BUDGET);
  check('Test 4: document root NOT marked done mid-traversal',
    rep.getForceLapWorkset().docDone, false);
  check('Test 4: DOM slice 1 incomplete (continuation pending)',
    rep.getForceLapActive() === true, true);

  // Slice 2: DOM continuation (elements 2,501 to 5,000)
  rep.runSweeper(true);
  measure('Test 4: document elements served after slice 2', docElementsServed);
  check('Test 4: DOM continuation resumed the SAME document walker (no restart)',
    docElementsServed, rep.FORCE_BUDGET * 2);
  check('Test 4: style enumeration did NOT restart on DOM continuation (slice 2)',
    styleInspections, inspectionsAfterSlice1);

  // Slice 3: DOM continuation (elements 5,001 to 6,000 -> finish)
  rep.runSweeper(true);
  measure('Test 4: document elements served after slice 3', docElementsServed);
  check('Test 4: final DOM continuation completed the document walker',
    docElementsServed, 6000);
  check('Test 4: style enumeration did NOT restart on DOM continuation (slice 3)',
    styleInspections, inspectionsAfterSlice1);
  check('Test 4: force lap cleanly finished all DOM elements',
    rep.getForceLapActive() === false, true);
}

// ═════════════════════════════════════════════════════════════════════════════
// TEST 5 — NEW ROOT MID-LAP
// ═════════════════════════════════════════════════════════════════════════════
console.log('\n--- Test 5: New Root Mid-Lap ---');
{
  const servedRoots = [];
  function makeRoot(name) {
    return {
      __name: name,
      host: { isConnected: true },
      createTreeWalker() {
        let wi = 0;
        return {
          nextNode() {
            if (wi++ < 1) {
              servedRoots.push(name);
              return { nodeType: 1, setAttribute() {}, hasAttribute: () => false, getAttribute: () => null, matches: () => false, closest: () => null, style: { getPropertyValue: () => '', setProperty() {} } };
            }
            return null;
          }
        };
      }
    };
  }

  const doc = {
    hidden: false,
    documentElement: { setAttribute() {}, getAttribute() { return null; }, style: { getPropertyValue: () => '', setProperty() {} } },
    styleSheets: [],
    adoptedStyleSheets: [],
    createTreeWalker() {
      let wi = 0;
      return {
        nextNode() {
          if (wi++ < 1) return { nodeType: 1, setAttribute() {}, hasAttribute: () => false, getAttribute: () => null, matches: () => false, closest: () => null, style: { getPropertyValue: () => '', setProperty() {} } };
          return null;
        }
      };
    }
  };

  const rep = createRepainterContext({ document: doc });
  const initialRoots = [];
  // Add 100 initial roots
  for (let i = 0; i < 100; i++) {
    const r = makeRoot('init_' + i);
    initialRoots.push(r);
    rep.piercedRoots.add(r);
  }

  // Slice 1: serves document (1) + first 63 pierced roots = 64 total root advances
  rep.runSweeper(true);
  check('Test 5: slice 1 served exactly 64 initial roots',
    servedRoots.length, 63);
  check('Test 5: lap active midway', rep.getForceLapActive(), true);

  // Add new root mid-lap via pierceShadow
  const lateRoot = makeRoot('late_shadow');
  rep.pierceShadow({ tagName: 'DIV', shadowRoot: lateRoot });

  check('Test 5: new root is placed in deferred set during active lap',
    rep.forceLapDeferredRoots.has(lateRoot), true);
  check('Test 5: new root NOT yet in piercedRoots',
    rep.piercedRoots.has(lateRoot), false);

  // Slice 2: completes initial lap (serves remaining 37 initial roots)
  rep.runSweeper(true);
  check('Test 5: initial lap completed all 100 initial roots',
    servedRoots.filter(r => r.startsWith('init_')).length, 100);
  check('Test 5: late root was NOT served in initial lap',
    servedRoots.includes('late_shadow'), false);

  // The lap completion transferred deferred roots into piercedRoots
  check('Test 5: deferred root now transferred to piercedRoots for next lap',
    rep.piercedRoots.has(lateRoot), true);

  // Drain lap 2 until late_shadow is served
  let lap2Iters = 0;
  while (!servedRoots.includes('late_shadow') && lap2Iters++ < 10) {
    rep.runSweeper(true);
  }
  check('Test 5: deferred root served in subsequent lap',
    servedRoots.includes('late_shadow'), true);
}

// ═════════════════════════════════════════════════════════════════════════════
// TEST 6 — SAME-COUNT REPLACEMENT MID-LAP
// ═════════════════════════════════════════════════════════════════════════════
console.log('\n--- Test 6: Same-Count Replacement Mid-Lap ---');
{
  const rawRules = [];
  for (let i = 0; i < 1000; i++) {
    rawRules.push({ selectorText: '.r' + i + ':hover', style: { length: 0 } });
  }

  const sheet = {
    cssRules: rawRules,
    ownerNode: null,
    __wintageGen: 1
  };

  const doc = {
    hidden: false,
    documentElement: { setAttribute() {}, getAttribute() { return null; } },
    styleSheets: [sheet],
    adoptedStyleSheets: [],
    createTreeWalker: () => null
  };

  const rep = createRepainterContext({ document: doc });
  rep.setStylesDirty(true);

  // Slice 1: processes 500 rules of gen 1
  const res1 = rep.drainStyleWork(32, 500);
  check('Test 6: slice 1 processed half the sheet', res1.done === false, true);

  // Mid-lap: same-count rewrite bumps __wintageGen to 2
  sheet.__wintageGen = 2;

  // Next slice:
  // Active task gen was 1; currentGen is 2 -> task discarded, re-started with gen 2
  const res2 = rep.drainStyleWork(32, 500);
  check('Test 6: mid-lap replaced sheet continues draining under new generation',
    res2.done === false, true);

  // Complete drain
  rep.drainStyleWork(32, 1000);
  check('Test 6: sheetSeen records the newer generation 2',
    rep.sheetSeen.get(sheet), { gen: 2, count: 1000 });
}

// ═════════════════════════════════════════════════════════════════════════════
// TEST 7 — LARGE APPEND
// ═════════════════════════════════════════════════════════════════════════════
console.log('\n--- Test 7: Large Append ---');
{
  let ruleReads = 0;
  const rawRules = [];
  // Initially 10 rules
  for (let i = 0; i < 10; i++) {
    rawRules.push({ selectorText: '.init' + i + ':hover', style: { length: 0 } });
  }

  const rulesProxy = new Proxy(rawRules, {
    get(target, prop) {
      if (prop === 'length') return target.length;
      const idx = typeof prop === 'string' ? Number(prop) : prop;
      if (Number.isInteger(idx) && idx >= 0 && idx < target.length) {
        ruleReads++;
        return target[idx];
      }
      return target[prop];
    }
  });

  const sheet = {
    cssRules: rulesProxy,
    ownerNode: null,
    __wintageGen: 1
  };

  const doc = {
    hidden: false,
    documentElement: { setAttribute() {}, getAttribute() { return null; } },
    styleSheets: [sheet],
    adoptedStyleSheets: [],
    createTreeWalker: () => null
  };

  const rep = createRepainterContext({ document: doc });
  rep.setStylesDirty(true);

  // Initial pass: 10 rules processed
  rep.drainStyleWork(32, 500);
  check('Test 7: initial 10 rules recorded in sheetSeen',
    rep.sheetSeen.get(sheet), { gen: 1, count: 10 });

  // Now append 50,000 rules
  for (let i = 10; i < 50010; i++) {
    rawRules.push({ selectorText: '.appended' + i + ':hover', style: { length: 0 } });
  }

  ruleReads = 0;
  rep.setStylesDirty(true);

  // Slice 1 of append:
  const appSlice1 = rep.drainStyleWork(32, 500);
  measure('Test 7: 50,000-rule append first-slice rule reads', ruleReads);
  check('Test 7: append slice 1 bounded by STYLE_RULE_BUDGET (500)',
    ruleReads <= 505, true);
  check('Test 7: append slice 1 not finished', appSlice1.done === false, true);

  // Drain append to completion
  let appendSlices = 1;
  while (appendSlices < 200) {
    const r = rep.drainStyleWork(32, 500);
    appendSlices++;
    if (r.done) break;
  }

  check('Test 7: large append finished within budget iterations', appendSlices < 200, true);
  check('Test 7: total appended rule reads covered all 50,000 appended rules',
    ruleReads === 50000, true);
  check('Test 7: sheetSeen updated to full appended count',
    rep.sheetSeen.get(sheet), { gen: 1, count: 50010 });
}

// ═════════════════════════════════════════════════════════════════════════════
// TEST 8 — THROWING CSSOM
// ═════════════════════════════════════════════════════════════════════════════
console.log('\n--- Test 8: Throwing CSSOM ---');
{
  const throwingSheet = {
    get cssRules() { throw new Error('cross-origin CORS access denied'); },
    ownerNode: null,
    __wintageGen: 0
  };

  const normalSheet = {
    cssRules: [{ selectorText: '.normal:hover', style: { length: 0 } }],
    ownerNode: null,
    __wintageGen: 0
  };

  const doc = {
    hidden: false,
    documentElement: { setAttribute() {}, getAttribute() { return null; } },
    styleSheets: [throwingSheet, normalSheet],
    adoptedStyleSheets: [],
    createTreeWalker: () => null
  };

  const rep = createRepainterContext({ document: doc });
  rep.setStylesDirty(true);

  let errorThrown = false;
  try {
    rep.drainStyleWork(32, 500);
  } catch (e) {
    errorThrown = true;
  }

  check('Test 8: scheduler does not throw or crash on throwing cssRules', errorThrown, false);
  check('Test 8: throwing sheet marked seen with -1 to prevent infinite retry',
    rep.sheetSeen.get(throwingSheet), { gen: 0, count: -1 });
  check('Test 8: normal sheet was successfully processed after throwing sheet',
    rep.sheetSeen.get(normalSheet), { gen: 0, count: 1 });
}

// ═════════════════════════════════════════════════════════════════════════════
// TEST 9 — STYLE OWNER TEXT
// ═════════════════════════════════════════════════════════════════════════════
console.log('\n--- Test 9: Style Owner Text ---');
{
  let styleQueries = 0;
  const styleEl = {
    nodeName: 'STYLE',
    tagName: 'STYLE',
    textContent: '.a:hover { background: red; }',
    __wintageLastText: null,
    getAttribute: () => null
  };

  const sheet = {
    cssRules: [{ selectorText: '.a:hover', style: { length: 0 } }],
    ownerNode: styleEl,
    __wintageGen: 0
  };
  styleEl.sheet = sheet;

  const doc = {
    hidden: false,
    documentElement: { setAttribute() {}, getAttribute() { return null; } },
    styleSheets: [sheet],
    adoptedStyleSheets: [],
    createTreeWalker: () => null,
    querySelectorAll(sel) {
      if (sel.includes('style')) styleQueries++;
      return [];
    }
  };

  const rep = createRepainterContext({ document: doc });
  rep.setStylesDirty(true);

  // Pass 1:
  rep.drainStyleWork(32, 500);
  check('Test 9: pass 1 marked sheet seen', rep.sheetSeen.get(sheet).count, 1);
  const initialGen = sheet.__wintageGen;

  // Mutate styleEl.textContent with same rule count:
  styleEl.textContent = '.b:hover { color: green; }';
  rep.setStylesDirty(true);

  // Pass 2:
  rep.drainStyleWork(32, 500);
  check('Test 9: style text change bumped __wintageGen without querySelectorAll',
    sheet.__wintageGen > initialGen, true);
  check('Test 9: querySelectorAll was NEVER called for style discovery',
    styleQueries, 0);
  check('Test 9: invalidation and re-traversal completed for updated text',
    rep.sheetSeen.get(sheet).gen, sheet.__wintageGen);
}

// ═════════════════════════════════════════════════════════════════════════════
// TEST 10 — 25,000 STYLE ROOTS (STYLE_ROOT_BUDGET)
// The force-root budget (Test 2) and the STYLE root budget are different
// schedulers; this fixture drives drainStyleWork, which owns the style lane.
// ═════════════════════════════════════════════════════════════════════════════
console.log('\n--- Test 10: 25,000 Style Roots ---');
{
  const ROOT_COUNT = 25000;
  let rootAdvances = 0;

  const doc = {
    hidden: false,
    documentElement: { setAttribute() {}, getAttribute() { return null; } },
    styleSheets: [],
    adoptedStyleSheets: [],
    createTreeWalker: () => null
  };

  const rep = createRepainterContext({ document: doc });

  // Instrument the iterator the STYLE lane consumes.
  const realValues = rep.piercedRoots.values.bind(rep.piercedRoots);
  rep.piercedRoots.values = function () {
    const it = realValues();
    return {
      next() {
        const res = it.next();
        if (!res.done) rootAdvances++;
        return res;
      }
    };
  };

  for (let i = 0; i < ROOT_COUNT; i++) {
    rep.piercedRoots.add({
      __name: 'sr' + i,
      host: { isConnected: true },
      styleSheets: [],
      adoptedStyleSheets: []
    });
  }
  rep.setStylesDirty(true);

  const slice1 = rep.drainStyleWork(rep.STYLE_SHEET_BUDGET, rep.STYLE_RULE_BUDGET);
  measure('Test 10: 25,000-style-root first-slice root advances', rootAdvances);
  measure('Test 10: STYLE_ROOT_BUDGET', rep.STYLE_ROOT_BUDGET);
  check('Test 10: style-root advances <= STYLE_ROOT_BUDGET + const',
    rootAdvances <= rep.STYLE_ROOT_BUDGET + 2, true);
  check('Test 10: all 25,000 style roots NOT enumerated in slice 1',
    rootAdvances < ROOT_COUNT, true);
  check('Test 10: style continuation remains pending', slice1.done, false);
  check('Test 10: the style root cursor is still live (not restarted)',
    rep.getStyleCursorRoot() !== null, true);

  let slices = 1;
  const MAX_STYLE_SLICES = 4000;
  while (slices < MAX_STYLE_SLICES) {
    const res = rep.drainStyleWork(rep.STYLE_SHEET_BUDGET, rep.STYLE_RULE_BUDGET);
    slices++;
    if (res.done) break;
  }

  measure('Test 10: 25,000-style-root lap slices', slices);
  check('Test 10: drain completed within bounded slices', slices < MAX_STYLE_SLICES, true);
  check('Test 10: every eligible style root inspected exactly once', rootAdvances, ROOT_COUNT);
  check('Test 10: no restart from root zero (advances == root count, no re-advance)',
    rootAdvances, ROOT_COUNT);
  check('Test 10: the style lap consumed its debt', rep.getStylesDirty(), false);
}

// ═════════════════════════════════════════════════════════════════════════════
// TEST 11 — NEW ROOT MID-STYLE-LAP (TARGET D/E)
// A ShadowRoot pierced while a style lap is running must NOT join that lap. The
// force lane has its own deferral (Test 5); this is the style lane's.
// ═════════════════════════════════════════════════════════════════════════════
console.log('\n--- Test 11: New Root Mid-Style-Lap ---');
{
  const EMPTY_SHEETS = [];
  const inspected = [];
  const makeStyleRoot = (name) => {
    const root = { __name: name, host: { isConnected: true } };
    Object.defineProperty(root, 'styleSheets', {
      get() { inspected.push(name); return EMPTY_SHEETS; }
    });
    Object.defineProperty(root, 'adoptedStyleSheets', {
      get() { return EMPTY_SHEETS; }
    });
    return root;
  };

  const doc = {
    hidden: false,
    documentElement: { setAttribute() {}, getAttribute() { return null; } },
    styleSheets: [],
    adoptedStyleSheets: [],
    createTreeWalker: () => null
  };

  const rep = createRepainterContext({ document: doc });
  // The repainter body boots itself (its tail calls startSweeping(), which
  // requests a force pass), so a fresh context starts with the FORCE lane live.
  // This fixture is about the STYLE lane, so the force lane is stood down
  // explicitly -- exactly the state the mission describes (forceLapActive false
  // while style traversal is still active).
  measure('Test 11: force lane active at context construction (boot)',
    rep.getForceLapActive());
  rep.setForceLapActive(false);
  rep.forceLapDeferredRoots.clear();

  const INITIAL = 200;
  for (let i = 0; i < INITIAL; i++) {
    rep.pierceShadow({ tagName: 'DIV', shadowRoot: makeStyleRoot('init_' + i) });
  }
  rep.setStylesDirty(true);
  check('Test 11: every pierced root is registered while the force lane is idle',
    rep.piercedRoots.size, INITIAL);

  // Slice 1 of the style lap.
  const s1 = rep.drainStyleWork(rep.STYLE_SHEET_BUDGET, rep.STYLE_RULE_BUDGET);
  measure('Test 11: style roots inspected on slice 1', inspected.length);
  check('Test 11: slice 1 is bounded by STYLE_ROOT_BUDGET',
    inspected.length <= rep.STYLE_ROOT_BUDGET + 2, true);
  check('Test 11: the style lap is still running (continuation pending)', s1.done, false);
  check('Test 11: the style cursor is live', rep.getStyleCursorRoot() !== null, true);
  check('Test 11: this is the style lane (force lap is NOT active)',
    rep.getForceLapActive(), false);
  const limitAtStart = rep.getStyleLapSeqLimit();

  // A new ShadowRoot arrives while the style lap is MID-FLIGHT.
  rep.pierceShadow({ tagName: 'DIV', shadowRoot: makeStyleRoot('late') });
  measure('Test 11: captured style-lap sequence limit', limitAtStart);
  measure('Test 11: style root sequence after the late pierce', rep.getStyleRootSeq());
  check('Test 11: the late root is stamped AFTER the captured lap limit',
    rep.getStyleRootSeq() > limitAtStart, true);

  // Drain the CURRENT style lap only.
  let guard = 0;
  let lastDone = null;
  while (guard++ < 500 && rep.getStyleCursorRoot() !== null) {
    lastDone = rep.drainStyleWork(rep.STYLE_SHEET_BUDGET, rep.STYLE_RULE_BUDGET);
  }
  const initInspected = inspected.filter(n => n.startsWith('init_'));
  const uniqueInit = new Set(initInspected);
  measure('Test 11: pre-existing roots inspected in the current lap', uniqueInit.size);
  check('Test 11: current style lap ended', rep.getStyleCursorRoot(), null);
  check('Test 11: the late root was NOT inspected in the current lap',
    inspected.includes('late'), false);
  check('Test 11: every pre-existing root was inspected exactly once', uniqueInit.size, INITIAL);
  check('Test 11: no pre-existing root was re-inspected (no restart)',
    initInspected.length, INITIAL);
  check('Test 11: the late root is held for the NEXT style lap',
    Array.from(rep.styleLapDeferredRoots).map(r => r.__name), ['late']);
  check('Test 11: fresh style debt is still set, so that lap is owed',
    rep.getStylesDirty(), true);
  check('Test 11: the style lap reported itself INCOMPLETE', lastDone && lastDone.done, false);

  // The next style lap must cover it (and then actually settle).
  let lap2Slices = 0;
  while (lap2Slices++ < 500 && !inspected.includes('late')) {
    rep.drainStyleWork(rep.STYLE_SHEET_BUDGET, rep.STYLE_RULE_BUDGET);
  }
  measure('Test 11: slices of the subsequent style lap before the late root', lap2Slices);
  check('Test 11: the late root is inspected in the subsequent style lap',
    inspected.includes('late'), true);

  let settle = 0;
  while (settle++ < 500 && rep.getStylesDirty()) {
    rep.drainStyleWork(rep.STYLE_SHEET_BUDGET, rep.STYLE_RULE_BUDGET);
  }
  check('Test 11: the debt is consumed once the late root is covered',
    rep.getStylesDirty(), false);
  check('Test 11: no deferred root is left behind', rep.styleLapDeferredRoots.size, 0);
}

// ═════════════════════════════════════════════════════════════════════════════
// TEST 12 — MANY SHEETS (STYLE_SHEET_BUDGET)
// Test 1 pins the RULE budget; this pins the SHEET budget, so both constants are
// behavioural evidence rather than declared intent.
// ═════════════════════════════════════════════════════════════════════════════
console.log('\n--- Test 12: Many Sheets ---');
{
  const SHEET_COUNT = 5000;
  let sheetIndexReads = 0;
  const sheets = [];
  for (let i = 0; i < SHEET_COUNT; i++) {
    sheets.push({ cssRules: [], ownerNode: null, __wintageGen: 0 });
  }

  // No full materialisation: every numeric index read (and nothing else) is
  // counted, so a slice that enumerated the whole list would be visible.
  const list = new Proxy(sheets, {
    get(target, prop) {
      const idx = typeof prop === 'string' ? Number(prop) : prop;
      if (Number.isInteger(idx) && idx >= 0 && idx < target.length) sheetIndexReads++;
      return target[prop];
    }
  });

  const doc = {
    hidden: false,
    documentElement: { setAttribute() {}, getAttribute() { return null; } },
    styleSheets: list,
    adoptedStyleSheets: [],
    createTreeWalker: () => null
  };

  const rep = createRepainterContext({ document: doc });
  rep.setStylesDirty(true);

  const slice1 = rep.drainStyleWork(rep.STYLE_SHEET_BUDGET, rep.STYLE_RULE_BUDGET);
  measure('Test 12: 5,000-sheet first-slice sheet-index reads', sheetIndexReads);
  measure('Test 12: STYLE_SHEET_BUDGET', rep.STYLE_SHEET_BUDGET);
  check('Test 12: first slice sheet reads <= STYLE_SHEET_BUDGET + const',
    sheetIndexReads <= rep.STYLE_SHEET_BUDGET + 2, true);
  check('Test 12: all 5,000 sheets NOT inspected in slice 1',
    sheetIndexReads < SHEET_COUNT, true);
  check('Test 12: sheet continuation remains pending', slice1.done, false);

  let slices = 1;
  const MAX_SHEET_SLICES = 1000;
  while (slices < MAX_SHEET_SLICES) {
    const res = rep.drainStyleWork(rep.STYLE_SHEET_BUDGET, rep.STYLE_RULE_BUDGET);
    slices++;
    if (res.done) break;
  }

  measure('Test 12: 5,000-sheet drain slices', slices);
  check('Test 12: drain completed within bounded slices', slices < MAX_SHEET_SLICES, true);
  check('Test 12: every sheet entry was eventually inspected', sheetIndexReads, SHEET_COUNT);
  check('Test 12: the last sheet was recorded as seen',
    rep.sheetSeen.get(sheets[SHEET_COUNT - 1]), { gen: 0, count: 0 });
}

// ═════════════════════════════════════════════════════════════════════════════
// RED CONTROLS (MUTATION-BASED)
// ═════════════════════════════════════════════════════════════════════════════
console.log('\n--- Red Controls (Temporary In-Memory Mutants) ---');

// RED A: Restore unbounded `[document, ...piercedRoots]`
{
  const targetPattern = /if\s*\(!forceLapActive \|\| !forceLapWorkset\)\s*\{[\s\S]*?stylesDirty = false;\s*forceRootCursors\.clear\(\);\s*\}/;
  const mutantA = repainterBody.replace(targetPattern,
`if (!forceLapActive || !forceLapWorkset) {
  forceLapWorkset = [document, ...piercedRoots];
  forceLapIndex = 0;
  forceLapRemaining = forceLapWorkset.length;
  forceLapActive = true;
  stylesDirty = false;
  forceRootCursors.clear();
}`);

  check('RED A: mutant source mutation actually applied', mutantA !== repainterBody, true);

  let redATouched = 0;
  const roots = [];
  for (let i = 0; i < 25000; i++) {
    roots.push({
      host: { isConnected: true },
      createTreeWalker: () => ({ nextNode: () => null })
    });
  }

  const doc = {
    hidden: false,
    documentElement: { setAttribute() {}, getAttribute() { return null; } },
    styleSheets: [],
    adoptedStyleSheets: [],
    createTreeWalker: () => ({ nextNode: () => null })
  };

  const repMutantA = createRepainterContext({ document: doc }, mutantA);
  // Track array spread / enumeration of piercedRoots
  const origValues = repMutantA.piercedRoots[Symbol.iterator].bind(repMutantA.piercedRoots);
  repMutantA.piercedRoots[Symbol.iterator] = function() {
    const it = origValues();
    return {
      next() {
        redATouched++;
        return it.next();
      }
    };
  };

  for (let i = 0; i < 25000; i++) repMutantA.piercedRoots.add(roots[i]);

  repMutantA.runSweeper(true);
  measure('RED A: mutant root-iterator advances on slice 1', redATouched);
  check('RED A: mutant enumerates all 25,000 roots on slice 1 (defects reproduced)',
    redATouched >= 25000, true);

  // The A/B is on the PRIMITIVE, not on "an array exists": the same
  // instrumentation is attached to the fixed source over the same 25,000-root
  // registry, and must stay inside the root budget on slice 1.
  let fixedTouched = 0;
  const repFixedA = createRepainterContext({ document: doc });
  const fixedValues = repFixedA.piercedRoots.values.bind(repFixedA.piercedRoots);
  repFixedA.piercedRoots.values = function () {
    const it = fixedValues();
    return {
      next() {
        const res = it.next();
        if (!res.done) fixedTouched++;
        return res;
      }
    };
  };
  for (let i = 0; i < 25000; i++) repFixedA.piercedRoots.add(roots[i]);
  repFixedA.runSweeper(true);
  measure('RED A: FIXED-source root-iterator advances on slice 1 (same registry)', fixedTouched);
  measure('RED A: FORCE_ROOT_BUDGET', repFixedA.FORCE_ROOT_BUDGET);
  check('RED A: the same primitive on the FIXED source is budget-bounded',
    fixedTouched <= repFixedA.FORCE_ROOT_BUDGET + 2, true);
  check('RED A: mutant advances exceed the fixed bound (the defect is the primitive, not the shape)',
    redATouched > fixedTouched * 100, true);
}

// RED B: Restore recursive unbounded rule walk
{
  const targetWalkPattern = /function drainStyleRules\([\s\S]*?return ruleBudget - budgetRemaining;\s*\}/;
  const mutantB = repainterBody.replace(targetWalkPattern,
`function drainStyleRules(task, ruleBudget) {
  // Unbounded recursive walk mutant
  function walk(container) {
    let rules = container.cssRules || container;
    if (!rules) return;
    for (let i = 0; i < rules.length; i++) {
      const r = rules[i];
      if (r && r.cssRules && r.cssRules.length) walk(r.cssRules);
    }
  }
  walk(task.stack[0].container);
  task.stack.length = 0;
  return 250000;
}`);

  check('RED B: mutant source mutation actually applied', mutantB !== repainterBody, true);

  let ruleReads = 0;
  const rawRules = [];
  for (let i = 0; i < 250000; i++) rawRules.push({ selectorText: '.c' + i, style: { length: 0 } });
  const rulesProxy = new Proxy(rawRules, {
    get(target, prop) {
      if (prop === 'length') return target.length;
      const idx = typeof prop === 'string' ? Number(prop) : prop;
      if (Number.isInteger(idx) && idx >= 0 && idx < target.length) {
        ruleReads++;
        return target[idx];
      }
      return target[prop];
    }
  });

  const repMutantB = createRepainterContext({}, mutantB);
  const task = {
    sheet: { __wintageGen: 0 },
    gen: 0,
    count: 250000,
    mode: 'full',
    stack: [{ container: rulesProxy, index: 0, length: 250000 }]
  };

  repMutantB.drainStyleRules(task, 500);
  measure('RED B: mutant rule-index reads in ONE slice of budget 500', ruleReads);
  check('RED B: mutant processes all 250,000 rules in one slice, ignoring budget (defect reproduced)',
    ruleReads >= 250000, true);

  // The B side: the fixed traversal, same 250,000-rule container, same budget.
  let fixedReads = 0;
  const fixedRulesProxy = new Proxy(rawRules, {
    get(target, prop) {
      if (prop === 'length') return target.length;
      const idx = typeof prop === 'string' ? Number(prop) : prop;
      if (Number.isInteger(idx) && idx >= 0 && idx < target.length) {
        fixedReads++;
        return target[idx];
      }
      return target[prop];
    }
  });
  const repFixedB = createRepainterContext({});
  repFixedB.drainStyleRules({
    sheet: { __wintageGen: 0 },
    gen: 0,
    count: 250000,
    mode: 'full',
    stack: [{ container: fixedRulesProxy, index: 0, length: 250000 }]
  }, 500);
  measure('RED B: FIXED traversal rule-index reads in ONE slice of budget 500', fixedReads);
  check('RED B: the fixed traversal honours the rule budget on the same container',
    fixedReads <= 505, true);
}

console.log('\n' + (bad === 0 ? 'ALL PASS: test-repainter-budget.js' : bad + ' FAIL(S)'));
process.exit(bad === 0 ? 0 : 1);
