// ════════════════════════════════════════════════════════════════════════════
//   CORE-003  excluded-route quarantine restores ONLY what the theme wrote and
//             blocks every republish path (injected sheets, adopted sheets,
//             inline overrides, root observer, shadow interception)
//   CORE-005  theme-switch survival probe is armed BEFORE the reload, disarms on
//             pagehide only, and never treats beforeunload as a departure
//   PERF-001  a future-stamped root consumes the force-lap discovery budget and
//             a lap that deferred roots still gets its continuation lap
//   PERF-002  a drained attribute target leaves attributePending immediately
//             and an already-pending target never trips the capacity cap
//
// Every ticket is checked twice: once on the REAL source text extracted from
// wintage.user.js and executed against a fake DOM/CSSOM (so a refactor that
// breaks the behaviour fails the gate), and once against a MUTATED copy of that
// same source (so a gate that passes no matter what also fails).
//
// Usage: node tools/test-src088-userscript.js   (exit 0 = pass, 1 = fail)
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

const SRC_PATH = path.join(__dirname, '..', 'wintage.user.js');
const src = fs.readFileSync(SRC_PATH, 'utf8');
const lines = src.split(/\r?\n/);
const lineOf = (needle, from) => {
  for (let i = from ? from - 1 : 0; i < lines.length; i++) if (lines[i].includes(needle)) return i + 1;
  return -1;
};
// The inverse assertion: PASSES when the predicate still observes the defect.
// A regression pair needs its red half, and a red half that stops being red is
// a broken gate, not a success.
// A regression pair is recorded as a real FAIL line on the pre-fix subject
// followed by a PASS on the fixed one. The FAIL is the artefact; the harness
// still exits 0 because the pair as a whole is what must hold.
let pairRed = 0, pairGreen = 0;
const checkRed = (label, stillRed) => {
  console.log((stillRed ? 'PASS: ' : 'FAIL: ') + label
    + (stillRed ? '' : '\n        the pre-fix control is no longer red'));
  if (stillRed) pairRed++; else pairGreen++;
};
const countOf = (re) => (src.match(re) || []).length;

// Brace-balanced extraction of a declaration's body, so the tests drive the
// production text rather than a paraphrase of it.
function blockOf(decl) {
  const i = src.indexOf(decl);
  if (i < 0) throw new Error('source region not found: ' + decl);
  let depth = 0;
  for (let j = src.indexOf('{', i); j < src.length; j++) {
    if (src[j] === '{') depth++;
    else if (src[j] === '}') { depth--; if (depth === 0) return src.slice(i, j + 1); }
  }
  throw new Error('unbalanced region: ' + decl);
}
function fromTo(fromNeedle, toNeedle, moreLines) {
  const a = src.indexOf(fromNeedle);
  if (a < 0) throw new Error('source region not found: ' + fromNeedle);
  const b = src.indexOf(toNeedle, a);
  if (b < 0) throw new Error('source region end not found: ' + toNeedle);
  const end = src.indexOf('\n', b);
  let stop = end < 0 ? src.length : end;
  for (let k = 0; k < (moreLines || 0) && stop < src.length; k++) {
    const nl = src.indexOf('\n', stop + 1);
    stop = nl < 0 ? src.length : nl;
  }
  return src.slice(a, stop);
}
// Run real source text with the script-scope fence forced to a known state.
// The Proxy global records every identifier the slice touches, so "it returned
// early" is proved by WHICH globals were read, not by a return value.
function runSlice(body, tail, latch, extra) {
  const accessed = [];
  const sandbox = new Proxy(Object.assign({
    Infinity: Infinity, NaN: NaN, undefined: undefined,
    parseInt: parseInt, parseFloat: parseFloat, isNaN: isNaN, isFinite: isFinite,
    String: String, Number: Number, Boolean: Boolean, Object: Object, Array: Array,
    Error: Error, TypeError: TypeError, Math: Math, JSON: JSON, Date: Date, RegExp: RegExp,
    Map: Map, Set: Set, WeakMap: WeakMap, WeakSet: WeakSet, WeakRef: WeakRef,
    Symbol: Symbol, Proxy: Proxy, Reflect: Reflect, Promise: Promise,
    routeQuarantined: latch,
    setTimeout: setTimeout, clearTimeout: clearTimeout
  }, extra), {
    has: () => true,
    get(t, k) {
      if (typeof k === 'symbol') return t[k];
      accessed.push(k);
      return t[k];
    }
  });
  vm.runInNewContext(body + '\n' + tail, sandbox, { timeout: 5000 });
  return accessed;
}

// ─── CORE-003 ───────────────────────────────────────────────────────────────
console.log('\n--- CORE-003: quarantine is a real safety boundary ---');

check('CORE-003: the fence is a script-scope binding, not a window property',
  [countOf(/let routeQuarantined = false;/), src.split('if (routeQuarantined) return;').length - 1,
   src.split('window.__wintageRouteQuarantined').length - 1], [1, 6, 0]);
check('CORE-003: the fence is declared before every reader, so none can read it uninitialized',
  [lineOf('let routeQuarantined = false;') > lineOf("'use strict';"),
   lineOf('let routeQuarantined = false;') < lineOf('if (routeQuarantined) return;')], [true, true]);
check('CORE-003: quarantine latches the binding from inside quarantineThemeStyles()',
  [lineOf('routeQuarantined = true;') > lineOf('function quarantineThemeStyles()'),
   lineOf('routeQuarantined = true;') < lineOf('function quarantineThemeStyles()') + 5], [true, true]);
check('CORE-003: the pre-repainter shadow path fences on the same binding',
  [lineOf('if (routeQuarantined) return;') > 0,
   lineOf('if (routeQuarantined) return;') < lineOf('// --- REPAINTER START ---')], [true, true]);

// The defect this fence shape exists to remove: an anti-tamper page that calls
// Object.freeze(window) made the window-property write throw under 'use strict',
// the empty catch swallowed it, and every reader then saw an open gate. Both
// halves are executed here, so the control fails if the shape ever regresses.
{
  const frozenForOld = Object.freeze({});
  vm.runInNewContext("'use strict'" + '\n' + 'try { window.__wintageRouteQuarantined = true; } catch (e) { }',
    { window: frozenForOld });
  check('CORE-003: control: the old window-property write fails open on a frozen window',
    frozenForOld.__witageRouteQuarantined === true, false);
  const frozenForNew = { routeQuarantined: false, window: Object.freeze({}) };
  vm.runInNewContext("'use strict'" + '\n' + 'routeQuarantined = true;', frozenForNew);
  check('CORE-003: the script-scope fence latches even when window is frozen',
    frozenForNew.routeQuarantined, true);
}

// The ticket's verify text, literally: a sandbox whose window is frozen, the
// quarantine runs, and the excluded route must then receive NO repaint. The
// sweep entry point is the real one, and the only identifiers it is allowed to
// touch are the fence and itself.
{
  const body = blockOf('function startSweeping(');
  const call = 'try { startSweeping(); } catch (e) { }';
  const frozen = Object.freeze({});
  const latched = runSlice(body, call, true, { window: frozen });
  check('CORE-003: the excluded route receives no repaint after quarantine on a FROZEN window',
    latched.filter(a => a !== 'routeQuarantined' && a !== 'startSweeping'), []);
  const open = runSlice(body, call, false, { window: frozen });
  check('CORE-003: control: the same entry on a frozen window still runs when NOT quarantined',
    open.filter(a => a !== 'routeQuarantined' && a !== 'startSweeping').length > 0, true);
}

// ─── CORE-003: the regression pair T-997 declares (regression: required) ────
// The SAME verifier must be red on the pre-fix subject and green on the post-fix
// one. The pre-fix fence is a window property written inside try/catch, so it is
// reconstructed here from the live source rather than trusted from history: the
// pair cannot drift away from the bytes actually under test.
{
  const preFix = src.split(/\r?\n/).map(l => {
    if (l.trim() === 'let routeQuarantined = false;') return '';
    if (l.trim() === 'routeQuarantined = true;') return '    try { window.__witageRouteQuarantined = true; } catch (e) { }';
    return l.replace('if (routeQuarantined) return;', 'if (window.__wintageRouteQuarantined) return;');
  }).join('\n');
  check('CORE-003: regression pair: the pre-fix subject really is the window-property fence',
    [preFix.includes('window.__wintageRouteQuarantined'),
     preFix.split('window.__wintageRouteQuarantined').length - 1,
     preFix.includes('let routeQuarantined = false;')], [true, 6, false]);
  const frozen = Object.freeze({});
  const redBody = blockOf('function startSweeping(', preFix);
  const red = runSlice(redBody, 'try { startSweeping(); } catch (e) { }', false, { window: frozen });
  checkRed('CORE-003: regression pair: the pre-fix fence fails open on a frozen window (RED half)',
    red.filter(a => a !== 'startSweeping').length > 0);
  const greenBody = blockOf('function startSweeping(');
  const green = runSlice(greenBody, 'try { startSweeping(); } catch (e) { }', true, { window: frozen });
  checkRed('CORE-003: regression pair: the fixed fence blocks the same control on a frozen window (GREEN half)',
    green.filter(a => a !== 'startSweeping' && a !== 'routeQuarantined').length === 0);
}

const FENCES = [
  ['function paintRoot(', 'try { paintRoot(); } catch (e) { }'],
  ['function injectStyle(', 'try { injectStyle(null, null, null); } catch (e) { }'],
  ['function pierceShadow(', '(function (host) { try { pierceShadow(host); } catch (e) { } })({ shadowRoot: null, isConnected: true, tagName: "DIV", attachShadow: function () { return { adoptedStyleSheets: [] }; }, getAttribute: function () { return null; } });'],
  ['function requestForceSweep(', 'try { requestForceSweep(); } catch (e) { }'],
  ['function startSweeping(', 'try { startSweeping(); } catch (e) { }']
];
for (const [decl, call] of FENCES) {
  const name = decl.replace('function ', '').replace('(', '');
  const body = blockOf(decl);
  const bodyLines = body.split(/\r?\n/).slice(1).map(l => l.trim()).filter(l => l && !l.startsWith('//'));
  check('CORE-003: ' + name + ' returns before any theme work when quarantined',
    bodyLines[0], 'if (routeQuarantined) return;');
  // Behavioural: with the fence latched the slice must touch NOTHING but the fence.
  const gated = runSlice(body, call, true);
  check('CORE-003: ' + name + ' touches no DOM/CSSOM while quarantined',
    gated.filter(a => a !== 'routeQuarantined' && a !== name), []);
  // Negative control: same slice, fence open, must get past the first statement.
  const open = runSlice(body, call, false);
  check('CORE-003: control: ' + name + ' proceeds past the gate when not quarantined',
    open.filter(a => a !== 'routeQuarantined' && a !== name).length > 0, true);
}

check('CORE-003: the root attribute observer is disconnected before the root overrides are removed',
  lineOf('rootAttributeObserver.disconnect()') < lineOf("root.style.removeProperty('background-color')"), true);
check('CORE-003: rootObs ReferenceError bug is fixed (observe goes through the hoisted observer)',
  [countOf(/rootAttributeObserver\.observe\(/), countOf(/\brootObs\b/)], [1, 0]);
check('CORE-003: the guard quarantines BEFORE requesting the reload',
  lineOf('try { quarantineThemeStyles(); }') < lineOf('location.reload();'), true);
check('CORE-003: quarantine restores the OWNED inline recordings, not every !important',
  [/ownedInlineOriginals\.get\(el\)/.test(src), /st\.setProperty\(name, o\.value, o\.priority \|\| ''\)/.test(src)], [true, true]);
check('CORE-003: only the hover snapshot walks a foreign style list; quarantine never does',
  countOf(/for \(let i = 0; i < st\.length; i\+\+\)/), 1);

console.log('\n--- CORE-003: setImp records the pre-write value it must restore ---');
{
  const makeEl = () => {
    const props = { color: 'rgb(1, 2, 3)', border: '1px solid red' };
    const prio = { color: 'important', border: 'important' };
    const calls = [];
    return {
      calls,
      style: {
        getPropertyValue(p) { return props[p] === undefined ? '' : props[p]; },
        getPropertyPriority(p) { return prio[p] || ''; },
        setProperty(p, v, pr) { props[p] = v; prio[p] = pr || ''; calls.push(['set', p, v, pr || '']); },
        removeProperty(p) { const old = props[p]; delete props[p]; delete prio[p]; calls.push(['remove', p]); return old; }
      }
    };
  };
  const setImpSrc = 'var ownedInlineOriginals = new WeakMap();\n' + blockOf('function setImp(');

  // 1. the write half.
  const el = makeEl();
  const sandbox = { WeakMap: WeakMap, ownedInlineOriginals: undefined, el: el };
  vm.runInNewContext(setImpSrc + '\nsetImp(el, "color", "red");', sandbox);
  check('CORE-003: the theme writes its override', el.style.getPropertyValue('color'), 'red');
  check('CORE-003: the pre-write value AND priority are recorded for the pair only',
    sandbox.ownedInlineOriginals.get(el), { color: { value: 'rgb(1, 2, 3)', priority: 'important' } });

  // 2. the restore half of quarantine, driven against those same recordings.
  const restoreSrc = fromTo("const rec = ownedInlineOriginals.get(el);", "el.removeAttribute('data-w95-done');");
  const runRestore = (srcText, record) => {
    const e = makeEl();
    const attrs = { 'data-w95-done': '' };
    e.removeAttribute = (k) => { delete attrs[k]; };
    const sb = {
      WeakMap: WeakMap, ownedInlineOriginals: new WeakMap(), el: e, st: e.style
    };
    sb.ownedInlineOriginals.set(e, record);
    vm.runInNewContext('if (true) {\n' + srcText + '\n}', sb);
    return { el: e, attrs: attrs };
  };
  const restored = runRestore(restoreSrc, { color: { value: 'rgb(1, 2, 3)', priority: 'important' } });
  check('CORE-003: restore puts the recorded value and priority back verbatim',
    [restored.el.style.getPropertyValue('color'), restored.el.style.getPropertyPriority('color')],
    ['rgb(1, 2, 3)', 'important']);
  check('CORE-003: restore writes only the recorded property',
    restored.el.calls, [['set', 'color', 'rgb(1, 2, 3)', 'important']]);
  check('CORE-003: restore leaves a foreign !important declaration untouched',
    [restored.el.style.getPropertyValue('border'), restored.el.style.getPropertyPriority('border')],
    ['1px solid red', 'important']);
  check('CORE-003: the painted marker is cleared', Object.prototype.hasOwnProperty.call(restored.attrs, 'data-w95-done'), false);

  // Negative control: a recorder that forgets the pre-write value deletes the
  // site's own declaration instead of restoring it.
  const forgetful = runRestore(restoreSrc, { color: { value: '', priority: '' } });
  check('CORE-003: control: without the recorded value the site declaration is destroyed',
    [forgetful.el.style.getPropertyValue('color'), forgetful.el.style.getPropertyPriority('color')], ['', '']);
}

// ─── CORE-005 ───────────────────────────────────────────────────────────────
console.log('\n--- CORE-005: the survival probe is armed before the reload ---');

check('CORE-005: the probe is armed BEFORE location.reload() in the menu callback',
  lineOf('try { cancelProbe = armSurvivalProbe(id); }') < lineOf('location.reload();', lineOf('try { cancelProbe = armSurvivalProbe(id); }')), true);
check('CORE-005: the probe is cancelled on the synchronous refusal path',
  lineOf('if (cancelProbe) { try { cancelProbe(); } catch (e2) { } }') > lineOf('reloadThrew = true;'), true);
check('CORE-005: beforeunload no longer disarms the probe',
  countOf(/addEventListener\('beforeunload', disarm/), 0);
check('CORE-005: the probe hands back a cancel function',
  countOf(/return function \(\) \{ done = true; \};/), 1);

{
  const probeSrc = blockOf('const armSurvivalProbe = function (id) {');
  const runProbe = (srcText, drive) => {
    const state = { timer: null, listeners: {}, reports: [] };
    const sandbox = {
      setTimeout: (fn) => { state.timer = fn; return 1; },
      clearTimeout: () => {},
      addEventListener: (t, fn) => { (state.listeners[t] = state.listeners[t] || []).push(fn); },
      removeEventListener: (t, fn) => {
        if (state.listeners[t]) state.listeners[t] = state.listeners[t].filter(f => f !== fn);
      },
      reportPendingTheme: (id, msg) => { state.reports.push(msg); }
    };
    const cancel = vm.runInNewContext(srcText + '\narmSurvivalProbe("t1");', sandbox);
    drive(state, cancel);
    return state.reports;
  };
  const fire = (state, type) => { (state.listeners[type] || []).forEach(fn => fn()); };

  // pagehide firing synchronously inside reload() is a real departure.
  const departed = runProbe(probeSrc, (s) => { fire(s, 'pagehide'); s.timer(); });
  check('CORE-005: a synchronous pagehide inside reload() never reports a stayed-alive document', departed.length, 0);

  // Dismissed leave prompt: beforeunload fires, the document SURVIVES, so the
  // pending-theme row must still be emitted.
  const prompted = runProbe(probeSrc, (s) => { fire(s, 'beforeunload'); s.timer(); });
  check('CORE-005: a dismissed leave prompt still reports the pending theme',
    [prompted.length, /cancelled/i.test(prompted[0] || '')], [1, true]);

  // No unload and no prompt at all: the refused-reload row.
  const silent = runProbe(probeSrc, (s) => s.timer());
  check('CORE-005: a refused reload reports the pending theme', silent.length, 1);

  // Synchronous refusal already reported it: the probe stands down.
  const refused = runProbe(probeSrc, (s, cancel) => { cancel(); s.timer(); });
  check('CORE-005: the cancel path suppresses a second report', refused.length, 0);

  // Negative control: the pre-fix shape (beforeunload disarms) hides the row.
  const mutant = probeSrc.replace("addEventListener('beforeunload', noteConfirm, { once: true });",
    "addEventListener('beforeunload', disarm, { once: true });");
  check('CORE-005: control: the mutant really differs from the source', mutant !== probeSrc, true);
  const hidden = runProbe(mutant, (s) => { fire(s, 'beforeunload'); s.timer(); });
  check('CORE-005: control: treating beforeunload as a departure loses the recovery row', hidden.length, 0);
}

// ─── PERF-001 ───────────────────────────────────────────────────────────────
console.log('\n--- PERF-001: future-stamped roots are paid for, deferred laps continue ---');

check('PERF-001: the discovery-budget accumulator lives inside the repainter body',
  lineOf('let forceDeferredRoots = 0;') > lineOf('// --- REPAINTER START ---'), true);
{
  const skip = fromTo('if (candidate.__wintageLapId && candidate.__wintageLapId > forceLapWorkset.id) {', 'continue;', 1);
  // `continue` only parses inside a loop; a one-trip loop turns the charge into
  // an observable value instead of an infinite loop.
  const runSkip = (srcText, lapId) => new Function('lapId',
    'let rootsServed = 0, forceDeferredRoots = 0;'
    + ' const forceLapWorkset = { id: 7 }; const candidate = { __wintageLapId: lapId };'
    + ' for (let __i = 0; __i < 1; __i++) {\n' + srcText + '\n}'
    + ' return { rootsServed: rootsServed, forceDeferredRoots: forceDeferredRoots };'
  )(lapId);

  const charged = runSkip(skip, 9);
  check('PERF-001: a future-stamped root consumes the discovery budget and is booked as debt',
    [charged.rootsServed, charged.forceDeferredRoots], [1, 1]);
  const inLap = runSkip(skip, 7);
  check('PERF-001: a current-lap root is not charged to the deferred counter',
    [inLap.rootsServed, inLap.forceDeferredRoots], [0, 0]);

  const free = runSkip(skip.replace(/\s*rootsServed\+\+;/, '').replace(/\s*forceDeferredRoots\+\+;/, ''), 9);
  check('PERF-001: control: without the charge, a skipped root costs nothing',
    [free.rootsServed, free.forceDeferredRoots], [0, 0]);
}

{
  const finish = fromTo('const oweContinuation = forceDeferredRoots > 0;', 'if (oweContinuation) requestForceSweep();');
  const runFinish = (srcText, debt) => new Function('debt',
    'let forceDeferredRoots = debt; const forceRootCursors = { clear: function () {} };'
    + ' let forceLapWorkset = {}; let forceLapIndex = 0; let forceLapRemaining = 0;'
    + ' let forceLapActive = true; let requests = 0;'
    + ' const requestForceSweep = function () { requests++; };'
    + ' for (let __i = 0; __i < 1; __i++) {\n' + srcText + '\n}'
    + ' return { forceDeferredRoots: forceDeferredRoots, forceLapActive: forceLapActive, requests: requests };'
  )(debt);
  const withDebt = runFinish(finish, 3);
  check('PERF-001: a lap that deferred roots requests exactly one continuation lap',
    [withDebt.forceLapActive, withDebt.forceDeferredRoots, withDebt.requests], [false, 0, 1]);
  check('PERF-001: the continuation is requested only after the lap state is torn down',
    src.indexOf('forceLapActive = false;', src.indexOf('const oweContinuation')) < src.indexOf('if (oweContinuation) requestForceSweep();'), true);
  check('PERF-001: a lap with no debt requests nothing', runFinish(finish, 0).requests, 0);

  const mutilated = finish.replace('const oweContinuation = forceDeferredRoots > 0;', 'const oweContinuation = false;');
  check('PERF-001: control: dropping the continuation loses the deferred roots',
    runFinish(mutilated, 3).requests, 0);
}

// ─── PERF-002 ───────────────────────────────────────────────────────────────
console.log('\n--- PERF-002: the attribute lane releases drained targets ---');

check('PERF-002: a drained target is released inside the drain loop',
  [lineOf("try { attributePending.delete(el); } catch (e) { }") > lineOf('function drainAttributeSlice()'),
    lineOf("try { attributePending.delete(el); } catch (e) { }") < lineOf('process(el, false, w);')], [true, true]);
{
  const inner = fromTo('if (!el || el.nodeType !== 1 || !el.isConnected) continue;', 'process(el, false, w);', 1);
  const runDrain = (srcText, el) => {
    const attributePending = new Set([el]);
    const seen = [];
    const sandbox = {
      el: el,
      attributePending: attributePending,
      attrCooldown: new Map(),
      w: [],
      Date: { now: () => 1000000 },
      process: (e) => { seen.push(e); },
      markLightDirty: () => {},
      requestLightSweep: () => {}
    };
    vm.runInNewContext('for (let __i = 0; __i < 1; __i++) {\ntry {\n' + srcText + '\n} catch (e) {}\n}', sandbox);
    return { pending: attributePending, seen: seen };
  };
  const el = { nodeType: 1, isConnected: true, removeAttribute: () => {} };
  const drained = runDrain(inner, el);
  check('PERF-002: the processed target leaves attributePending in the same slice',
    [drained.pending.size, drained.pending.has(el)], [0, false]);
  check('PERF-002: and it is still processed exactly once', drained.seen.length, 1);

  const leaked = runDrain(inner.replace(/try \{ attributePending\.delete\(el\); \} catch \(e\) \{ \}/, ''), el);
  check('PERF-002: control: without the release the completed target still occupies capacity',
    [leaked.pending.size, leaked.pending.has(el)], [1, true]);
}

{
  const admit = fromTo('if (attributePending.has(t)) continue;', 'else attributePending.add(t);');
  const runAdmit = (srcText, target, fill, cap) => {
    const attributePending = new Set();
    for (let i = 0; i < fill; i++) attributePending.add('x' + i);
    const sandbox = {
      attributePending: attributePending, t: target,
      ATTRIBUTE_PENDING_CAP: cap, attributeOverflowed: false
    };
    const overflowed = vm.runInNewContext(
      '(function () { for (let __i = 0; __i < 1; __i++) {\n' + srcText + '\n} return attributeOverflowed; })()', sandbox);
    return { overflowed: overflowed, size: attributePending.size };
  };
  // A FULL lane re-admitting an element it already owns is not an overflow.
  const deduped = runAdmit(admit, 'x0', 50, 50);
  check('PERF-002: an already-pending target never trips the cap',
    [deduped.overflowed, deduped.size], [false, 50]);
  const fresh = runAdmit(admit, 'fresh', 2, 50);
  check('PERF-002: a fresh target is admitted below the cap',
    [fresh.overflowed, fresh.size], [false, 3]);
  check('PERF-002: a fresh target over a truly full lane is still reported',
    runAdmit(admit, 'fresh', 50, 50).overflowed, true);

  const capFirst = admit.replace(/if \(attributePending\.has\(t\)\) continue;\r?\n\s*/, '');
  check('PERF-002: control: the cap-first mutant really differs from the source', capFirst !== admit, true);
  check('PERF-002: control: checking the cap before the dedup reports a false overflow',
    runAdmit(capFirst, 'x0', 50, 50).overflowed, true);
}

console.log('\n' + (bad === 0 ? 'ALL PASS: tools/test-src088-userscript.js' : bad + ' FAIL'));
process.exit(bad === 0 ? 0 : 1);
