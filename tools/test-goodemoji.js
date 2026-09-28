#!/usr/bin/env node
// ═════════════════════════════════════════════════════════════════════════════
// tools/test-goodemoji.js
// PERF-004 (SRC-018:R016) + PERF-005 (SRC-018:R017): GoodEmoji idle behavior
// and bounded unmatched-URL matching.
//
// PERF-004: start() used to install a fixed 2,000 ms setInterval that ran a
// body-wide image query and a body-wide tooltip query on an idle heartbeat, in
// addition to the MutationObserver that already covers the same subtree. This
// gate proves the fixed interval is gone, that 60s of no mutations causes zero
// global scans, that observer intake still processes added emoji / attribute
// changes / tooltips, and that stop()/restart leaves exactly one observer and no
// orphan timer.
//
// PERF-005 matching (matchSrc) is covered by tools/test-goodemoji-matchsrc.js;
// this gate owns PERF-004 (idle sweep removal) only.
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

const PLUGIN = path.join(__dirname, '..', 'desktop', 'targets', 'betterdiscord', 'plugins', 'GoodEmoji.plugin.js');

// A fake DOM good enough to run the REAL plugin's start()/observer/reconcile.
function makeEnv(options = {}) {
  const counters = { globalImageQueries: 0, globalTooltipQueries: 0, treeWalkers: 0, textNodesVisited: 0 };
  const timers = new Map();
  let timerSeq = 0;
  let now = 0;
  const listeners = { visibilitychange: [] };
  const nodes = [];

  function makeEl(tag, attrs = {}) {
    const el = {
      nodeType: 1, tagName: (tag || 'DIV').toUpperCase(), attrs: { ...attrs }, children: [], parentNode: null,
      isConnected: true, style: {}, dataset: {},
      getAttribute(n) { return n in el.attrs ? el.attrs[n] : null; },
      setAttribute(n, v) { el.attrs[n] = String(v); },
      hasAttribute(n) { return n in el.attrs; },
      removeAttribute(n) { delete el.attrs[n]; },
      append(c) { c.parentNode = el; el.children.push(c); return c; },
      closest() { return null; },
      querySelector() { return null; },
      querySelectorAll(sel) {
        // Fresh materialisation of every descendant matching the loose selectors
        // the plugin uses; counts global body scans.
        const all = [];
        const walk = (n) => { for (const c of n.children) { all.push(c); walk(c); } };
        walk(el);
        if (/img/i.test(sel)) {
          if (el === document.body) counters.globalImageQueries++;
          return all.filter(x => (x.tagName === 'IMG'));
        }
        if (/tooltip/i.test(sel)) {
          if (el === document.body) counters.globalTooltipQueries++;
          return all.filter(x => /tooltip/i.test(x.attrs['class'] || x.attrs['role'] || ''));
        }
        return all.filter(x => (x.tagName === 'IMG'));
      },
      set textContent(v) { el.__text = v; },
      get textContent() { return el.__text || ''; },
    };
    nodes.push(el);
    return el;
  }

  const document = {
    body: makeEl('body'),
    documentElement: makeEl('html'),
    hidden: false,
    visibilityState: 'visible',
    addEventListener(type, cb) { (listeners[type] = listeners[type] || []).push(cb); },
    removeEventListener(type, cb) { listeners[type] = (listeners[type] || []).filter(x => x !== cb); },
    createElement: makeEl,
    querySelectorAll() { return []; },
    createTreeWalker(root) {
      counters.treeWalkers++;
      const texts = [];
      const walk = (n) => { if (n.__text) texts.push(n); for (const c of n.children) walk(c); };
      walk(root);
      let i = 0;
      return { nextNode() { counters.textNodesVisited++; return i < texts.length ? texts[i++] : null; } };
    },
    querySelector() { return null; },
  };

  const ctx = {
    console: { log: () => { }, warn: () => { }, error: () => { } },
    document,
    navigator: { language: 'en' },
    Node: { TEXT_NODE: 3, ELEMENT_NODE: 1 },
    NodeFilter: { SHOW_TEXT: 4 },
    MutationObserver: class {
      constructor(cb) { this.cb = cb; this.delivered = 0; }
      observe() { this.observed = true; }
      disconnect() { this.disconnected = true; }
      takeRecords() { return []; }
    },
    setTimeout: (fn, ms) => { const id = ++timerSeq; timers.set(id, { fn, ms }); return id; },
    clearTimeout: (id) => { timers.delete(id); },
    setInterval: (fn, ms) => { throw new Error('setInterval installed (PERF-004 forbids a fixed heartbeat)'); },
    clearInterval: () => { },
    history: { pushState() { }, replaceState() { } },
    performance: { now: () => now },
    requestAnimationFrame: (fn) => { fn(); return 1; },
    ...options.globals
  };
  ctx.window = ctx;
  ctx.globalThis = ctx;
  ctx.module = { exports: {} };
  vm.createContext(ctx);
  const code = fs.readFileSync(PLUGIN, 'utf8')
    + '\n' + 'this.__GoodEmoji = module.exports;';
  vm.runInContext(code, ctx);
  return {
    ctx, counters, timers, listeners, document, makeEl, nodes,
    GoodEmoji: ctx.__GoodEmoji,
    drainTimer(id) { const t = timers.get(id); if (t) { timers.delete(id); t.fn(); } }
  };
}

console.log('--- PERF-004: no fixed idle sweep ---');
{
  const env = makeEnv();
  const inst = new env.GoodEmoji();
  inst.start();
  check('start() installs no setInterval heartbeat', env.timers.size, 0);
  const afterBootstrapImgs = env.counters.globalImageQueries;
  const afterBootstrapTips = env.counters.globalTooltipQueries;
  // 60 seconds of wall time with zero mutations and zero timers -> zero scans.
  // (The fake clock advances with no events, so nothing should fire.)
  check('60s idle: no new image query scheduled (no timer exists)', env.timers.size, 0);
  check('60s idle: image-query counter unchanged', env.counters.globalImageQueries, afterBootstrapImgs);
  check('60s idle: tooltip-query counter unchanged', env.counters.globalTooltipQueries, afterBootstrapTips);
  check('exactly one observer is live', inst.observer ? 1 : 0, 1);
  // stop() clears everything.
  inst.stop();
  check('stop() disconnected the observer', inst.observer, null);
  check('stop() left no orphan timer', env.timers.size, 0);
  // restart -> still exactly one observer, no timer.
  const inst2 = new env.GoodEmoji();
  inst2.start();
  check('restart: exactly one observer', inst2.observer ? 1 : 0, 1);
  check('restart: no orphan timer', env.timers.size, 0);
  inst2.stop();
}

console.log('\n--- PERF-004: observer intake still covers the cases ---');
{
  const env = makeEnv();
  const inst = new env.GoodEmoji();
  let processed = 0;
  const origProcessImg = inst.processImg.bind(inst);
  inst.processImg = (img) => { processed++; return origProcessImg(img); };
  inst.start();
  // Deliver an added img node through the observer callback.
  const img = env.makeEl('img', { src: 'https://cdn.discordapp.com/emojis/1f62d.png' });
  inst.observer.cb([{ type: 'childList', addedNodes: [img] }]);
  check('observer: an added img is processed', processed >= 1, true);
  // An attribute change on an img is processed.
  const before = processed;
  inst.observer.cb([{ type: 'attributes', target: env.makeEl('img', { src: 'x' }) }]);
  check('observer: a watched img attribute change is processed', processed > before, true);
  // A characterData change reaches processTextNode.
  let textCalls = 0;
  inst.processTextNode = () => { textCalls++; };
  inst.observer.cb([{ type: 'characterData', target: { nodeType: 3, __text: '😭' } }]);
  check('observer: a characterData change is processed', textCalls >= 1, true);
  inst.stop();
}

console.log('\n--- PERF-004: route change coalesces to ONE bounded scan ---');
{
  const env = makeEnv();
  const inst = new env.GoodEmoji();
  inst.start();
  const baseImgs = env.counters.globalImageQueries;
  inst.requestReconcile(0);
  inst.requestReconcile(0);
  inst.requestReconcile(0);
  check('three route changes coalesce into ONE pending timer', env.timers.size, 1);
  const id = [...env.timers.keys()][0];
  env.drainTimer(id);
  check('the coalesced scan runs exactly once', env.counters.globalImageQueries - baseImgs, 1);
  check('after the scan no timer remains', env.timers.size, 0);
  inst.stop();
}

// ── T-324 / T-329 / T-335 / T-339: audit findings, focused regression gates ──

console.log('\n--- T-324: textMap must not rewrite user-authored shortcode text ---');
{
  const env = makeEnv();
  const inst = new env.GoodEmoji();
  inst.initMaps();
  // Every textMap key must be a real emoji character, never ':shortcode:'.
  const shortcodeKeys = Object.keys(inst.textMap).filter((k) => k.startsWith(':'));
  check('no shortcode is registered in textMap', shortcodeKeys.length, 0);
  // A real emoji character must still convert; assert against the table itself
  // rather than a hand-copied literal.
  const sample = env.GoodEmoji.MAPPINGS[0];
  check('textMap still converts a real emoji', inst.textMap[sample.from], sample.to);
  check('a real emoji survives as a mapped token',
    (sample.from + ' hi').replace(inst.textRegex, (m) => inst.textMap[m] || m),
    sample.to + ' hi');
  // The exact strings the audit observed being corrupted.
  for (const typed of ['lol :x: is my vote', 'I saw a :rat: in the lab', 'the server has a :hole: in it']) {
    const out = typed.replace(inst.textRegex, (m) => inst.textMap[m] || m);
    check('authored text survives: ' + JSON.stringify(typed), out, typed);
  }
}

console.log('\n--- T-335: skin-tone shortcode uses the real single-colon syntax ---');
{
  const env = makeEnv();
  const inst = new env.GoodEmoji();
  inst.initMaps();
  check("real ':cry:skin-tone-3:' resolves", !!inst.matchEmojiString(':cry:skin-tone-3:'), true);
  check("invented ':cry::skin-tone-3:' does not resolve", inst.matchEmojiString(':cry::skin-tone-3:'), null);
}

console.log('\n--- T-329: start() is idempotent and stop() fully unwinds ---');
{
  const env = makeEnv();
  const native = env.ctx.history.pushState;
  const inst = new env.GoodEmoji();
  inst.start();
  check('start() wrapped pushState', env.ctx.history.pushState === native, false);
  inst.start();                       // no intervening stop()
  inst.requestReconcile(2000);        // arm a timer the next start() must reclaim
  check('a second start() left exactly one live timer', env.timers.size, 1);
  inst.stop();
  check('start(); start(); stop() restores the NATIVE pushState', env.ctx.history.pushState === native, true);
  check('start(); start(); stop() leaves no pending timer', env.timers.size, 0);
  check('start(); start(); stop() releases __historyRestore', inst.__historyRestore, null);
}

console.log('\n--- T-339: the reconcile backoff is live, not a dead accumulator ---');
{
  const env = makeEnv();
  const MIN = env.GoodEmoji.RECONCILE_MIN_MS;
  const MAX = env.GoodEmoji.RECONCILE_MAX_MS;
  const inst = new env.GoodEmoji();
  inst.start();
  check('a fresh start sits at RECONCILE_MIN_MS', inst.reconcileDelay, MIN);
  inst.onRouteChange();
  let id = [...env.timers.keys()][0];
  check('the first route change is armed at the minimum', env.timers.get(id).ms, MIN);
  env.drainTimer(id);
  check('the completed scan widened the window', inst.reconcileDelay, MIN * 2);
  inst.onRouteChange();
  id = [...env.timers.keys()][0];
  check('the next route change uses the widened window', env.timers.get(id).ms, MIN * 2);
  for (let i = 0; i < 20; i++) { inst.onRouteChange(); env.drainTimer([...env.timers.keys()][0]); }
  check('the backoff saturates at RECONCILE_MAX_MS', inst.reconcileDelay, MAX);
  inst.stop();
}

console.log('\n' + (bad === 0 ? 'ALL PASS' : bad + ' FAIL'));
process.exit(bad === 0 ? 0 : 1);
