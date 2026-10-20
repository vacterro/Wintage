#!/usr/bin/env node
'use strict';
// T-938 idle-CPU benchmark: 4 builds x 6 workloads, live Chromium, CDP metrics.
//
// Arms:
//   disabled  - fixture only, no userscript
//   baseline  - git show b5fb1d64:wintage.user.js (pre-T-938 build)
//   fixA      - current build with the OLD interceptAttachShadow IIFE spliced
//               back in (stylesheet single-sheet fix active, strong-Array
//               shadow registry active) -> isolates the A-fix from the B-fix
//   both      - current wintage.user.js
//
// Workloads: highChurn (ChatGPT-like SPA stream), generic (light app),
// shadowHeavy (200 roots + churn), manyFrame (20 iframes idle), longIdle
// (static page, the actual idle claim), mountUnmount (500-node subtree x 20).
//
// Per run: renderer main-thread busy % = TaskDuration delta / wall,
// RecalcStyleDuration, LayoutDuration, ScriptDuration, JSHeap, mutation record
// count, rAF frame count (responsiveness), stylesheet census + registry stats
// via __wintageDiag(). Browser-process CPU is NOT part of these numbers and is
// never mixed into them. 3 repeats with min/median/max in full mode.
//
// --quick: both-arm only, longIdle + highChurn, 1 repeat, smoke assertions
// (page boots, userscript installs, metrics finite). Wired into Run-Tests.ps1.

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const { chromium } = require('playwright');

const ROOT = path.join(__dirname, '..');
const USER_JS = path.join(ROOT, 'wintage.user.js');
const BASELINE_SHA = 'b5fb1d64af212e9ea7b153a299246025b1fc3330';
const QUICK = process.argv.includes('--quick');

const CURRENT = fs.readFileSync(USER_JS, 'utf8');
const BASELINE = execSync('git -C "' + ROOT.replace(/"/g, '') + '" show ' + BASELINE_SHA + ':wintage.user.js', {
  maxBuffer: 1 << 25, encoding: 'utf8'
});

// fixA = current source, but the interceptAttachShadow IIFE body replaced by
// the baseline's (old strong-Array registry + old dual-install wrapper).
function spliceOldInterception(current, baseline) {
  const START = '(function interceptAttachShadow()';
  const END = 'function injectStyle(';
  const cs = current.indexOf(START), ce = current.indexOf(END, cs);
  const bs = baseline.indexOf(START), be = baseline.indexOf(END, bs);
  if (cs < 0 || ce < 0 || bs < 0 || be < 0) {
    throw new Error('interceptAttachShadow splice anchors not found');
  }
  return current.slice(0, cs) + baseline.slice(bs, be) + current.slice(ce);
}
const FIXA = spliceOldInterception(CURRENT, BASELINE);

const ARMS = {
  disabled: null,
  baseline: BASELINE,
  fixA: FIXA,
  both: CURRENT
};

// ── fixtures ────────────────────────────────────────────────────────────────
const FIXTURES = {
  longIdle: '<!doctype html><html><head><meta charset="utf-8"></head><body>' +
    '<div id="app"><h1>static</h1>' + '<p>para</p>'.repeat(200) + '</div></body></html>',
  highChurn: '<!doctype html><html><head><meta charset="utf-8"></head><body>' +
    '<main id="stream"></main></body></html>',
  generic: '<!doctype html><html><head><meta charset="utf-8"></head><body>' +
    '<form id="form">' + '<label><input type="checkbox">opt</label>'.repeat(50) + '</form></body></html>',
  shadowHeavy: '<!doctype html><html><head><meta charset="utf-8"></head><body>' +
    '<div id="hosts"></div></body></html>',
  manyFrame: '<!doctype html><html><head><meta charset="utf-8"></head><body>' +
    Array.from({ length: 20 }, (_, i) => '<iframe id="f' + i + '" src="about:blank"></iframe>').join('') +
    '</body></html>',
  mountUnmount: '<!doctype html><html><head><meta charset="utf-8"></head><body>' +
    '<div id="stage"></div></body></html>'
};

// Each workload returns a page-side function string. It installs its own
// MutationObserver counter + rAF frame counter on window.__bench, runs for
// ms, resolves with nothing (host reads counters after).
function workloadRunner(kind, ms) {
  const body = {
longIdle: '/* static: no page-side work; idle window measured as-is */',
    highChurn: `
      var stream = document.getElementById('stream');
      var n = 0;
      function tick() {
        for (var i = 0; i < 12; i++) {
          var d = document.createElement('div');
          d.className = 'msg' + (n % 5);
          d.textContent = 'message body ' + (n++) + ' lorem ipsum dolor sit amet';
          d.style.padding = (n % 7) + 'px';
          stream.appendChild(d);
        }
        while (stream.childElementCount > 120) stream.removeChild(stream.firstChild);
        if (performance.now() < window.__benchEnd) requestAnimationFrame(tick); else { /* run ends via interval */ }
      }
      requestAnimationFrame(tick);`,
    generic: `
      var form = document.getElementById('form');
      var boxes = form.querySelectorAll('input');
      function tick() {
        for (var i = 0; i < boxes.length; i++) {
          boxes[i].classList.toggle('on', ((performance.now() | 0) + i) % 3 === 0);
        }
        if (performance.now() < window.__benchEnd) requestAnimationFrame(tick); else { /* run ends via interval */ }
      }
      requestAnimationFrame(tick);`,
    shadowHeavy: `
      var hosts = document.getElementById('hosts');
      for (var i = 0; i < 200; i++) {
        var h = document.createElement('div');
        var sr = h.attachShadow({ mode: 'open' });
        var inner = document.createElement('p');
        inner.textContent = 'shadow content ' + i;
        sr.appendChild(inner);
        hosts.appendChild(h);
      }
      function tick() {
        var ps = hosts.querySelectorAll('div');
        for (var i = 0; i < ps.length; i++) {
          var sr = ps[i].shadowRoot;
          if (sr) sr.firstChild.textContent = 'shadow content ' + i + ' t' + (performance.now() | 0);
        }
        if (performance.now() < window.__benchEnd) requestAnimationFrame(tick); else { /* run ends via interval */ }
      }
      requestAnimationFrame(tick);`,
    manyFrame: '/* 20 idle about:blank iframes */',
    mountUnmount: `
      var stage = document.getElementById('stage');
      function chunk() {
        var frag = document.createDocumentFragment();
        for (var i = 0; i < 500; i++) {
          var d = document.createElement('div');
          d.className = 'row';
          d.textContent = 'row ' + i;
          frag.appendChild(d);
        }
        stage.appendChild(frag);
        setTimeout(function () { stage.textContent = ''; }, 20);
        if (performance.now() < window.__benchEnd) setTimeout(chunk, 40); else { /* run ends via interval */ }
      }
      chunk();`
  }[kind];
  return '(function (res) {' +
    'window.__benchMut = 0;' +
    'new MutationObserver(function (recs) { window.__benchMut += recs.length; })' +
    '.observe(document.documentElement, { subtree: true, childList: true, attributes: true, characterData: true });' +
    'window.__benchFrames = 0;' +
    '(function f() { window.__benchFrames++; if (performance.now() < window.__benchEnd) requestAnimationFrame(f); })();' +
    'window.__benchEnd = performance.now() + ' + ms + ';' +
    body +
    'return new Promise(function (done) { var o = setInterval(function () { if (performance.now() >= window.__benchEnd) { clearInterval(o); done(); } }, 30); });' +
    '})()';
}

// ── measurement ─────────────────────────────────────────────────────────────
const METRIC_KEYS = ['TaskDuration', 'ScriptDuration', 'LayoutDuration',
  'RecalcStyleDuration', 'JSHeapUsedSize', 'Nodes', 'Documents'];

async function runOne(armName, kind, repeats, windowMs) {
  const runs = [];
  for (let r = 0; r < repeats; r++) {
    const browser = await chromium.launch();
    const page = await browser.newPage({ viewport: { width: 900, height: 700 } });
    await page.setContent(FIXTURES[kind], { waitUntil: 'load' });
    if (ARMS[armName]) await page.addScriptTag({ content: ARMS[armName] });
    // let boot settles (force sweeps are floor-limited; 1s clears first pass)
    await page.waitForTimeout(1000);
    const cdp = await page.context().newCDPSession(page);
    await cdp.send('Performance.enable');
    const read = async () => {
      const { metrics } = await cdp.send('Performance.getMetrics');
      const out = {};
      for (const m of metrics) if (METRIC_KEYS.includes(m.name)) out[m.name] = m.value;
      return out;
    };
    const before = await read();
    const wallStart = Date.now();
    await page.evaluate(workloadRunner(kind, windowMs));
    const wallMs = Date.now() - wallStart;
    const after = await read();
    const pageStats = await page.evaluate(() => {
      const adopted = (document.adoptedStyleSheets || []).length;
      const domStyles = document.querySelectorAll('style[data-w95]').length;
      let diag = null;
      try { diag = window.__wintageDiag ? window.__wintageDiag() : null; } catch (e) { diag = 'diag-error'; }
      return {
        benchMut: window.__benchMut | 0,
        benchFrames: window.__benchFrames | 0,
        adopted, domStyles,
        registry: diag && diag.shadowRegistry ? diag.shadowRegistry : null
      };
    });
    const dTask = after.TaskDuration - before.TaskDuration;
    runs.push({
      arm: armName, workload: kind, repeat: r,
      wallMs,
      rendererBusyPct: +(100 * dTask / wallMs).toFixed(1),
      taskMs: +(dTask * 1000).toFixed(0),
      scriptMs: +((after.ScriptDuration - before.ScriptDuration) * 1000).toFixed(0),
      recalcMs: +((after.RecalcStyleDuration - before.RecalcStyleDuration) * 1000).toFixed(1),
      layoutMs: +((after.LayoutDuration - before.LayoutDuration) * 1000).toFixed(1),
      heapKB: Math.round(after.JSHeapUsedSize / 1024),
      mutations: pageStats.benchMut,
      fps: +(pageStats.benchFrames / (wallMs / 1000)).toFixed(1),
      sheets: pageStats.adopted + '+' + pageStats.domStyles,
      registry: pageStats.registry
    });
    await browser.close();
  }
  return runs;
}

function summarize(runs) {
  const med = arr => { const s = [...arr].sort((a, b) => a - b); return s[s.length >> 1]; };
  const key = runs[0].arm + '/' + runs[0].workload;
  return {
    key,
    runs: runs.length,
    busyPct: runs.map(r => r.rendererBusyPct).join(','),
    medBusy: med(runs.map(r => r.rendererBusyPct)),
    medRecalcMs: med(runs.map(r => r.recalcMs)),
    medLayoutMs: med(runs.map(r => r.layoutMs)),
    medScriptMs: med(runs.map(r => r.scriptMs)),
    medMutations: med(runs.map(r => r.mutations)),
    medFps: med(runs.map(r => r.fps)),
    medHeapKB: med(runs.map(r => r.heapKB)),
    sheets: runs[0].sheets,
    registry: runs[0].registry
  };
}

(async () => {
  const all = [];
  const plan = QUICK
    ? [['both', 'longIdle'], ['both', 'highChurn']]
    : [['disabled', 'longIdle'], ['baseline', 'longIdle'], ['fixA', 'longIdle'], ['both', 'longIdle'],
       ['disabled', 'highChurn'], ['baseline', 'highChurn'], ['fixA', 'highChurn'], ['both', 'highChurn'],
       ['baseline', 'generic'], ['both', 'generic'],
       ['baseline', 'shadowHeavy'], ['fixA', 'shadowHeavy'], ['both', 'shadowHeavy'],
       ['baseline', 'manyFrame'], ['both', 'manyFrame'],
       ['baseline', 'mountUnmount'], ['both', 'mountUnmount']];
  const repeats = QUICK ? 1 : 3;
  const windowMs = QUICK ? 1500 : 3000;

  for (const [arm, kind] of plan) {
    process.stderr.write('[bench] ' + arm + ' / ' + kind + '\n');
    all.push(...await runOne(arm, kind, repeats, windowMs));
  }

  console.log('\narm/workload           runs  busy%(all repeats)  medBusy%  medRecalc  medLayout  medScript  muts   fps    heapKB  sheets(ad+dom)  registry');
  const groups = {};
  for (const r of all) {
    const k = r.arm + '/' + r.workload;
    (groups[k] = groups[k] || []).push(r);
  }
  for (const k of Object.keys(groups)) {
    const s = summarize(groups[k]);
    console.log(
      s.key.padEnd(22) + String(s.runs).padStart(4) +
      ('  ' + s.busyPct).padEnd(20) +
      String(s.medBusy).padStart(8) +
      String(s.medRecalcMs).padStart(10) +
      String(s.medLayoutMs).padStart(11) +
      String(s.medScriptMs).padStart(11) +
      String(s.medMutations).padStart(7) +
      String(s.medFps).padStart(6) +
      String(s.medHeapKB).padStart(8) +
      ('  ' + s.sheets).padEnd(15) +
      '  ' + JSON.stringify(s.registry)
    );
  }
  fs.writeFileSync(path.join(__dirname, 'bench-idle-cpu-results.json'),
    JSON.stringify(all, null, 1));

  if (QUICK) {
    const both = all.filter(r => r.arm === 'both');
    const ok = both.length === 2 &&
      both.every(r => isFinite(r.rendererBusyPct) && isFinite(r.recalcMs) && r.mutations >= 0) &&
      both.some(r => r.registry && typeof r.registry.retained === 'number');
    if (!ok) {
      console.error('bench-idle-cpu --quick: smoke assertions FAILED');
      process.exit(1);
    }
    console.log('\nbench-idle-cpu --quick: PASS (smoke only; full 4-arm data in bench-idle-cpu-results.json on full run)');
  } else {
    console.log('\nbench-idle-cpu full run complete. Renderer busy% and recalc medians above;');
    console.log('browser-process CPU deliberately excluded from every figure.');
    console.log('Raw per-repeat rows: tools/bench-idle-cpu-results.json');
  }
  process.exit(0);
})().catch(e => {
  console.error('bench-idle-cpu unhandled error: ' + (e && e.stack ? e.stack : e));
  process.exit(1);
});
