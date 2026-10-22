#!/usr/bin/env node
'use strict';
// T-938 idle-CPU benchmark: 5 builds x 6 workloads, live Chromium, CDP metrics.
//
// Arms:
//   disabled  - fixture only, no userscript
//   baseline  - git show b5fb1d64:wintage.user.js (pre-T-938 build)
//   fixA      - current build with the OLD interceptAttachShadow IIFE spliced
//               back in (stylesheet single-sheet fix active, strong-Array
//               shadow registry active) -> isolates the A-fix from the B-fix
//   preFix    - git show 0e2bb1bf:wintage.user.js (the build immediately BEFORE
//               the T-987 fix) -> the single-variable "before" of T-987
//   both      - current wintage.user.js (the "after")
//
// T-987 added the preFix arm. The four original arms contain NO pair that
// differs by exactly the T-987 change: fixA differs from both in the whole
// interception IIFE, and the T-987 change (the shadow sheet re-parse) lives
// half inside that IIFE and half in injectStyle, outside it. A before/after
// measured across two arms that differ in more than the fix cannot prove the
// fix. preFix is pinned to a commit, not to HEAD, so the arm keeps its meaning
// after the fix is committed -- a HEAD-based arm would erase itself the moment
// the change lands. The four original arms keep their exact meanings, so the
// T-938 report's table stays reproducible.
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
// --workload <name> --arms a,b --repeats N --out <file>: a focused run of the
// SAME instrument and the SAME measurement path, for a workload whose run-to-run
// spread needs more samples than the 3-repeat matrix can settle.

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const { chromium } = require('playwright');

const ROOT = path.join(__dirname, '..');
const USER_JS = path.join(ROOT, 'wintage.user.js');
const BASELINE_SHA = 'b5fb1d64af212e9ea7b153a299246025b1fc3330';
// T-987: the build immediately before the T-987 change. Pinned, not HEAD.
const PRE_FIX_SHA = '0e2bb1bf8268ad02660ec0533e11e616380132dd';
const QUICK = process.argv.includes('--quick');
const argOf = (name, fallback) => {
  const i = process.argv.indexOf('--' + name);
  return i >= 0 ? process.argv[i + 1] : fallback;
};
const ONLY_WORKLOAD = argOf('workload', null);
const ONLY_ARMS = argOf('arms', null);
const OUT_FILE = argOf('out', 'bench-idle-cpu-results.json');

const CURRENT = fs.readFileSync(USER_JS, 'utf8');
function blobAt(sha) {
  return execSync('git -C "' + ROOT.replace(/"/g, '') + '" show ' + sha + ':wintage.user.js', {
    maxBuffer: 1 << 25, encoding: 'utf8'
  });
}
const BASELINE = blobAt(BASELINE_SHA);
const PRE_FIX = blobAt(PRE_FIX_SHA);

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
  preFix: PRE_FIX,
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
          // T-987: the PARAGRAPH is addressed by name, not by firstChild. The
          // old build injected a <style> element as the shadow root's first
          // child, so firstChild was the stylesheet and the workload spent its
          // writes re-parsing CSS instead of moving text -- which is why the
          // baseline arm measured 4ms of layout for a page that lays out 200
          // shadow roots. The arms were not doing the same work.
          var p = sr && sr.querySelector('p');
          if (p) p.textContent = 'shadow content ' + i + ' t' + (performance.now() | 0);
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
    // T-987: the end stamp is set BEFORE the counters start. It used to be set
    // after the frame loop was launched, so the loop compared performance.now()
    // against an undefined value on its first turn, exited at once, and every
    // run reported the same 0.3 fps -- the counter was dead, not the page slow.
    'window.__benchEnd = performance.now() + ' + ms + ';' +
    'window.__benchMut = 0;' +
    'new MutationObserver(function (recs) { window.__benchMut += recs.length; })' +
    '.observe(document.documentElement, { subtree: true, childList: true, attributes: true, characterData: true });' +
    'window.__benchFrames = 0;' +
    '(function f() { window.__benchFrames++; if (performance.now() < window.__benchEnd) requestAnimationFrame(f); })();' +
    body +
    'return new Promise(function (done) { var o = setInterval(function () { if (performance.now() >= window.__benchEnd) { clearInterval(o); done(); } }, 30); });' +
    '})()';
}

// ── measurement ─────────────────────────────────────────────────────────────
const METRIC_KEYS = ['TaskDuration', 'ScriptDuration', 'LayoutDuration',
  'RecalcStyleDuration', 'JSHeapUsedSize', 'Nodes', 'Documents'];

async function runOne(armName, kind, repeats, windowMs, repeatOffset) {
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
      arm: armName, workload: kind, repeat: (repeatOffset || 0) + r,
      wallMs,
      // T-987: TaskDuration arrives in SECONDS and wallMs in milliseconds. The
      // old expression divided seconds by milliseconds, so every arm reported
      // 0.0% busy and the headline number of this benchmark was always zero.
      rendererBusyPct: +(100 * dTask * 1000 / wallMs).toFixed(1),
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
  // T-987: the full matrix is 5 arms x 6 workloads, every cell measured.
  // The old plan skipped cells, and the cells it skipped were the ones that
  // carried the floor: with no 'disabled' arm for a workload there was no
  // no-script reference to subtract, so a number could not be called a
  // regression or not.
  const ARMS_ORDER = ['disabled', 'baseline', 'fixA', 'preFix', 'both'];
  const WORKLOADS_ORDER = ['longIdle', 'highChurn', 'generic', 'shadowHeavy', 'manyFrame', 'mountUnmount'];
  const repeats = QUICK ? 1 : Math.max(1, parseInt(argOf('repeats', '3'), 10) || 3);
  const windowMs = QUICK ? 1500 : 3000;
  const arms = ONLY_ARMS
    ? ONLY_ARMS.split(',').map(s => s.trim()).filter(s => ARMS_ORDER.includes(s))
    : ARMS_ORDER;
  const workloads = ONLY_WORKLOAD ? WORKLOADS_ORDER.filter(w => w === ONLY_WORKLOAD) : WORKLOADS_ORDER;
  if (!arms.length || !workloads.length) {
    console.error('bench-idle-cpu: --arms/--workload selected nothing known. arms=' +
      ARMS_ORDER.join(',') + ' workloads=' + WORKLOADS_ORDER.join(','));
    process.exit(1);
  }

  if (QUICK) {
    for (const kind of ['longIdle', 'highChurn']) {
      process.stderr.write('[bench] both / ' + kind + '\n');
      all.push(...await runOne('both', kind, 1, windowMs, 0));
    }
  } else {
    // T-987: the arms are INTERLEAVED. The matrix used to run all repeats of
    // one arm and then all repeats of the next, so any drift in the machine
    // (load, thermal state, page cache) landed on one arm and not on the
    // others: the same build measured 27.5% busy on the shadow workload in one
    // full run and 21.6% in the next -- a quarter of the number, larger than
    // most of the differences the matrix exists to measure. Every repeat now
    // runs every arm back to back, so drift is shared instead of charged to
    // whichever arm happened to run during it.
    // Rotation step: coprime with the arm count, so the offsets cycle through
    // EVERY slot instead of repeating one.
    const gcd = (a, b) => (b ? gcd(b, a % b) : a);
    let step = 1;
    while (gcd(step, arms.length) !== 1) step++;
    for (let wi = 0; wi < workloads.length; wi++) {
      const kind = workloads[wi];
      for (let r = 0; r < repeats; r++) {
        // Rotate the arm order every round. With a fixed order the arm that
        // ran last in a round always inherited that round's warm-up and the
        // machine's drift, so a difference between two arms could be the
        // position and not the build. Rotating spreads the position over the
        // arms: over N rounds every arm occupies N different slots.
        const rot = (wi * step + r * step) % arms.length;
        const order = arms.map((_, i) => arms[(i + rot) % arms.length]);
        for (const arm of order) {
          process.stderr.write('[bench] ' + arm + ' / ' + kind + ' #r' + (r + 1) + '\n');
          all.push(...await runOne(arm, kind, 1, windowMs, r));
        }
      }
    }
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
  fs.writeFileSync(path.join(__dirname, OUT_FILE),
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
    console.log('\nbench-idle-cpu --quick: PASS (smoke only; full 5-arm data in bench-idle-cpu-results.json on full run)');
  } else {
    console.log('\nbench-idle-cpu full run complete. Renderer busy% and recalc medians above;');
    console.log('browser-process CPU deliberately excluded from every figure.');
    console.log('Raw per-repeat rows: tools/' + OUT_FILE);
  }
  process.exit(0);
})().catch(e => {
  console.error('bench-idle-cpu unhandled error: ' + (e && e.stack ? e.stack : e));
  process.exit(1);
});
