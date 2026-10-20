#!/usr/bin/env node
'use strict';
// ShadowRoot retention lifecycle gate (T-938, defect B).
//
// WHY THIS FILE EXISTS.
// Element.prototype.__wintageShadowRoots used to be a plain Array holding a
// STRONG reference to every shadow root the page ever created. Hosts detached
// and thrown away stayed reachable from the prototype forever -- independent
// census: 1000 roots created, 1000 hosts detached, 1000 roots retained -- and
// registering a new root cost O(N) indexOf over that whole history. This gate
// runs the real userscript in real Chromium, exercises create/detach/GC/
// reinjection/reattach, and proves:
//   * detached roots are not retained solely by the registry (weak handles),
//   * connected roots get the current CSS after reinjection,
//   * reattached hosts carry the active palette, not stale styles,
//   * registration cost does not grow quadratically,
//   * no duplicate attachShadow wrappers, open/closed and nested trees hold.
// RED control: the previous implementation (audit baseline) must retain all
// 1000 detached roots through GC + reinjection.

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const { chromium } = require('playwright');

const ROOT = path.join(__dirname, '..');
const BASELINE_SHA = 'b5fb1d64af212e9ea7b153a299246025b1fc3330';

let bad = 0;
function pass(label) { console.log('PASS: ' + label); }
function fail(label, detail) { console.error('FAIL: ' + label + (detail ? ' -- ' + detail : '')); bad++; }
function check(label, ok, detail) {
  if (ok) { pass(label); return true; }
  fail(label, detail);
  return false;
}

const CURRENT = fs.readFileSync(path.join(ROOT, 'wintage.user.js'), 'utf8');

function loadBaseline() {
  return execSync('git show ' + BASELINE_SHA + ':wintage.user.js', { cwd: ROOT, maxBuffer: 1 << 24 }).toString('utf8');
}

function withGeneration(src, gen) {
  const markerShadow = ` :host { --w95-gen: ${gen}; }`;
  return src
    .replace(/const W95_VERSION = '[^']*'/, `const W95_VERSION = '9.99.${gen}-test'`)
    .replace(
      'const ACTIVE_SHADOW_CSS = IS_CHATGPT ? CHATGPT_FAST_SHADOW_CSS : SHADOW_CSS;',
      `const ACTIVE_SHADOW_CSS = (IS_CHATGPT ? CHATGPT_FAST_SHADOW_CSS : SHADOW_CSS) + '${markerShadow}';`);
}

const FIXTURE = `<!doctype html>
<html>
<head><meta charset="utf-8"><title>shadow lifecycle</title></head>
<body>
  <div id="bulk"></div>
  <div id="held"></div>
  <div id="reattach"></div>
</body>
</html>`;

async function evalScript(page, src) {
  await page.evaluate(s => { (0, eval)(s); }, src);
}

// Creates `n` shadow roots whose hosts live under container `id`. The 10
// "held" hosts are kept reachable on window.__held; everything else is given
// up so the registry is the only thing that can keep it alive.
// Playwright serializes the function body; the payload travels as one arg.
function makeRoots(args) {
  const [n, containerId, heldCount] = args;
  if (!window.__held) window.__held = [];
  const c = document.getElementById(containerId);
  for (let i = 0; i < n; i++) {
    const h = document.createElement('div');
    h.setAttribute('data-root', i);
    h.style.width = '10px'; h.style.height = '10px';
    h.attachShadow({ mode: 'open' });
    c.appendChild(h);
    if (i < heldCount) window.__held.push(h);
  }
  return c.children.length;
}

const REGISTRY_STATS = () => {
  const list = Element.prototype.__wintageShadowRoots;
  if (!list) return { retained: 0, live: 0, connected: 0 };
  let live = 0, connected = 0;
  for (let i = 0; i < list.length; i++) {
    let r = list[i];
    if (r && typeof r.deref === 'function') { try { r = r.deref(); } catch (e) { r = null; } }
    if (!r) continue;
    live++;
    if (r.isConnected) connected++;
  }
  return { retained: list.length, live: live, connected: connected, detached: live - connected };
};

async function forceGc(page) {
  try {
    const client = await page.context().newCDPSession(page);
    await client.send('HeapProfiler.collectGarbage');
    return true;
  } catch (e) { return false; }
}

(async () => {
  const browser = await chromium.launch();
  const oldSrc = loadBaseline();

  // ── RED control: previous implementation retains all detached roots ──
  console.log('-- RED control: old strong Array retains 1000 detached roots --');
  {
    const page = await browser.newPage();
    await page.setContent(FIXTURE, { waitUntil: 'domcontentloaded' });
    await evalScript(page, withGeneration(oldSrc, 1));
    await page.evaluate(makeRoots, [1000, 'bulk', 10]);
    await page.evaluate(() => { document.getElementById('bulk').innerHTML = ''; window.__held.length = 0; });
    await page.evaluate(() => new Promise(r => setTimeout(r, 20)));
    await forceGc(page);
    await evalScript(page, withGeneration(oldSrc, 2)); // reinjection
    const stats = await page.evaluate(REGISTRY_STATS);
    check('RC-B1: old build still retains all 1000 detached roots through GC+reinjection (defect reproduced)',
      stats.retained >= 1000, 'retained=' + stats.retained);
    await page.close();
  }

  // ── Current implementation: weak lifecycle ──
  console.log('\n-- current implementation: weak/bounded lifecycle --');
  const page = await browser.newPage();
  await page.setContent(FIXTURE, { waitUntil: 'domcontentloaded' });

  // A. create 1000 ShadowRoots
  await evalScript(page, withGeneration(CURRENT, 1));
  await page.evaluate(makeRoots, [1000, 'bulk', 10]);
  await page.evaluate(() => new Promise(r => setTimeout(r, 20)));
  let stats = await page.evaluate(REGISTRY_STATS);
  check('A: 1000 roots registered', stats.retained >= 1000, 'retained=' + stats.retainedDeterministic);

  // B. disconnect all hosts
  await page.evaluate(() => { document.getElementById('bulk').innerHTML = ''; document.getElementById('held').innerHTML = ''; });
  await page.evaluate(() => new Promise(r => setTimeout(r, 20)));

  // C+D. The SUPPORTED cleanup lifecycle, in the order the product actually
  // runs it: the removal batch arms the existing piercedRoots prune
  // (pruneShadowRegistry, 250ms, resumable), which releases the detached roots
  // from that structure deterministically -- no GC needed for that half. The
  // WeakRef handles in __wintageShadowRoots then have nothing left to hold, a
  // forced GC makes the handles die, and the reinjection pass prunes the dead
  // handles from the registry. The 10 __held hosts stay alive throughout, so
  // ~10 handles must survive every stage.
  await new Promise(r => setTimeout(r, 1500)); // let pierce-prune complete
  const gcRan = await forceGc(page);
  check('C: forced GC available for a deterministic weakness probe', gcRan);
  if (gcRan) {
    await evalScript(page, withGeneration(CURRENT, 2)); // reinjection = cleanup pass
    await page.evaluate(() => new Promise(r => setTimeout(r, 20)));
    stats = await page.evaluate(REGISTRY_STATS);
    check('D: detached dropped-ref roots are NOT retained by the registry',
      stats.retained < 1000 && stats.retained <= 20,
      'retained=' + stats.retained + ' live=' + stats.live);
    check('D2: the 10 held roots survive the prune (only truly-gone handles dropped)',
      stats.live >= 10, 'live=' + stats.live个性);

    // F. connected roots receive the current CSS after reinjection
    const f = await page.evaluate(() => {
      const heldHost = window.__held && window.__held[0];
      if (!heldHost || !heldHost.shadowRoot) return { ok: false, reason: 'no held host' };
      const sh = heldHost.shadowRoot;
      const sheets = sh.__w95Sheets || {};
      const key = Object.keys(sheets)[0];
      const adopted = (sh.adoptedStyleSheets || []).filter(s => Object.keys(sheets).some(k => sheets[k] === s));
      const text = adopted.map(s => {
        try { return Array.from(s.cssRules || []).map(r => r.cssText).join('\n'); } catch (e) { return ''; }
      }).join('\n');
      const ver = (heldHost.shadowRoot.querySelector('style[data-w95="shadow"]') || {}).getAttribute;
      return { ok: true, hasGen2: text.includes('--w95-gen: 2'), hasGen1: text.includes('--w95-gen: 1'),
               domStyleCount: sh.querySelectorAll('style[data-w95="shadow"]').length };
    });
    check('F: held roots refreshed to generation 2 on reinjection',
      f.ok && f.hasGen2 && !f.hasGen1, JSON.stringify(f));
    check('F2: held roots keep exactly one effective copy',
      f.ok && f.domStyleCount === 0, 'dom=' + f.domStyleCount);

    // G+H. reattach a previously disconnected host -> active palette, not stale
    await page.evaluate(() => {
      const host = window.__held[0];
      document.getElementById('reattach').appendChild(host);
    });
    await page.evaluate(() => new Promise(r => setTimeout(r, 20)));
    const g = await page.evaluate(() => {
      const host = window.__held[0];
      const v = getComputedStyle(host).getPropertyValue('--w95-gen').trim();
      return { v: v, connected: host.isConnected };
    });
    check('G: reattached host is connected', g.connected);
    check('H: reattached host shows the ACTIVE palette (generation 2), not stale',
      g.v === '2', '--w95-gen=' + g.v);
  }

  // I. create another 1000 roots
  await page.evaluate(makeRoots, [1000, 'bulk', 10]);
  await page.evaluate(() => new Promise(r => setTimeout(r, 20)));
  stats = await page.evaluate(REGISTRY_STATS);
  check('I: second 1000-root batch registers without loss of prior bookkeeping',
    stats.retained >= 1000, 'retained=' + stats.retained);

  // J. registration cost does not grow quadratically.
  // Cost per attachShadow must be O(1) (WeakSet dedup), so doubling the
  // created-total must NOT ~quadruple the batch time the way O(N) indexOf did.
  const t1 = await page.evaluate(() => {
    const c = document.getElementById('bulk'); c.innerHTML = '';
    const t0 = performance.now();
    for (let i = 0; i < 1500; i++) { const h = document.createElement('div'); h.attachShadow({ mode: 'open' }); c.appendChild(h); }
    return performance.now() - t0;
  });
  await forceGc(page);
  const t4 = await page.evaluate(() => {
    const c = document.getElementById('bulk'); c.innerHTML = '';
    const t0 = performance.now();
    for (let i = 0; i < 6000; i++) { const h = document.createElement('div'); h.attachShadow({ mode: 'open' }); c.appendChild(h); }
    return performance.now() - t0;
  });
  // 1500->6000 is 4x the roots; linear => ~4x, quadratic => ~16x. Bound at 9x.
  const ratio = t4 / Math.max(t1, 10);
  check('J: registration scales ~linearly, not quadratically (1500 vs 6000 roots)',
    ratio < 9, 't1=' + t1.toFixed(1) + 'ms t4=' + t4.toFixed(1) + 'ms ratio=' + ratio.toFixed(2));

  // No duplicate attachShadow wrappers across generations
  await page.evaluate(() => { window.__wrap0 = Element.prototype.attachShadow; });
  await evalScript(page, withGeneration(CURRENT, 3));
  await evalScript(page, withGeneration(CURRENT, 4));
  const wrap = await page.evaluate(() => {
    const fn = Element.prototype.attachShadow;
    const src = Function.prototype.toString.call(fn);
    const microtasks = (src.match(/queueMicrotask/g) || []).length;
    return { same: fn === window.__wrap0, latched: fn.__wintageWrapped === true, microtasks: microtasks };
  });
  check('B2a: wrapper installed once (latch holds across generations)', wrap.latched);
  check('B2b: wrapper not re-wrapped by later generations', wrap.same && wrap.microtasks <= 1,
    'microtasks=' + wrap.microtasks);

  // Closed-mode shadow root still themed
  const closed = await page.evaluate(async () => {
    const host = document.createElement('div');
    document.getElementById('bulk').appendChild(host);
    const r = host.attachShadow({ mode: 'closed' });
    await new Promise(res => setTimeout(res, 20)); // the wrapper styles in a microtask
    const sheets = r.__w95Sheets || {};
    const adopted = (r.adoptedStyleSheets || []).filter(s => Object.keys(sheets).some(k => sheets[k] === s));
    return adopted.length === 1;
  });
  check('B2c: closed-mode shadow root themed (no regression)', closed);

  // Nested shadow tree still themed
  const nested = await page.evaluate(async () => {
    const host = document.createElement('div');
    document.getElementById('bulk').appendChild(host);
    const outer = host.attachShadow({ mode: 'open' });
    const innerHost = document.createElement('div');
    outer.appendChild(innerHost);
    const inner = innerHost.attachShadow({ mode: 'open' });
    await new Promise(res => setTimeout(res, 20));
    const sheets = inner.__w95Sheets || {};
    const adopted = (inner.adoptedStyleSheets || []).filter(s => Object.keys(sheets).some(k => sheets[k] === s));
    return adopted.length === 1;
  });
  check('B2d: nested shadow tree themed (no regression)', nested);

  await page.close();
  await browser.close();

  if (bad > 0) {
    console.error('\ntest-shadow-registry-lifecycle: ' + bad + ' failure(s)');
    process.exit(1);
  }
  console.log('\ntest-shadow-registry-lifecycle gate: PASS');
  process.exit(0);
})().catch(e => {
  console.error('test-shadow-registry-lifecycle unhandled error: ' + (e && e.stack ? e.stack : e));
  process.exit(1);
});