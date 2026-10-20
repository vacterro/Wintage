#!/usr/bin/env node
'use strict';
// Stylesheet census gate (T-938, defect A).
//
// WHY THIS FILE EXISTS.
// wintage.user.js used to install the SAME CSS twice on every compatible
// browser: once as a constructable CSSStyleSheet on adoptedStyleSheets and once
// as a DOM <style data-w95> element with identical content (independent census
// at the audit: adopted_sheet_count = 1, dom_style_count = 1, identical_css =
// true). Both copies were parsed, stored and matched against every element for
// the whole life of the page. The gate runs the REAL userscript in real
// Chromium across every installation environment and asserts the single-
// effective-sheet invariant, the fallbacks, and reinjection behaviour.
//
// Cases (mission A3):
//   A. constructable stylesheets supported      -> adopted 1, DOM 0
//   B. constructable stylesheets unsupported    -> DOM 1, adopted 0, themed
//   C. replaceSync throws                       -> DOM fallback installs
//   D. adoptedStyleSheets assignment refused    -> DOM fallback, no phantom
//   E. strict-CSP page                          -> adopted install, themed
//   F. existing stylesheet + reinjection        -> single copy, new generation only
//   G. existing ShadowRoot + reinjection        -> shadow sheet refreshed in place
//   H. palette generation change                -> no stale rule survives
//   I. repeated reinjection (injectLate path)   -> census stays stable
//   J. document and ShadowRoot census independently
// RED control: the PREVIOUS implementation (audit baseline commit) must
// reproduce the dual install; the gate is red against the old code by design.

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const { chromium } = require('playwright');

const ROOT = path.join(__dirname, '..');
const USER_JS = path.join(ROOT, 'wintage.user.js');
const BASELINE_SHA = 'b5fb1d64af212e9ea7b153a299246025b1fc3330';

let bad = 0;
function pass(label) { console.log('PASS: ' + label); }
function fail(label, detail) { console.error('FAIL: ' + label + (detail ? ' -- ' + detail : '')); bad++; }
function check(label, ok, detail) {
  if (ok) { pass(label); return true; }
  fail(label, detail);
  return false;
}

const CURRENT = fs.readFileSync(USER_JS, 'utf8');

function loadBaseline() {
  // The RED control must run the actual previous implementation, not a paraphrase.
  return execSync('git show ' + BASELINE_SHA + ':wintage.user.js', { cwd: ROOT, maxBuffer: 1 << 24 }).toString('utf8');
}

// Builds a next-generation script the way a reinjection arrives: new version
// stamp plus a marker rule appended to BOTH active sheets, so "is the current
// generation's CSS the only one installed?" is answerable from cssRules alone.
function withGeneration(src, gen) {
  const markerDoc = ` html { --w95-gen: ${gen}; }`;
  const markerShadow = ` :host { --w95-gen: ${gen}; }`;
  const probeDoc = ` #census-probe { --w95-probe: rgb(${10 + gen}, ${20 + gen}, ${30 + gen}); }`;
  return src
    .replace(/const W95_VERSION = '[^']*'/, `const W95_VERSION = '9.99.${gen}-test'`)
    .replace(
      'const ACTIVE_GLOBAL_CSS = IS_CHATGPT ? CHATGPT_FAST_CSS : GLOBAL_CSS;',
      `const ACTIVE_GLOBAL_CSS = (IS_CHATGPT ? CHATGPT_FAST_CSS : GLOBAL_CSS) + '${markerDoc}${probeDoc}';`)
    .replace(
      'const ACTIVE_SHADOW_CSS = IS_CHATGPT ? CHATGPT_FAST_SHADOW_CSS : SHADOW_CSS;',
      `const ACTIVE_SHADOW_CSS = (IS_CHATGPT ? CHATGPT_FAST_SHADOW_CSS : SHADOW_CSS) + '${markerShadow}';`);
}

const FIXTURE = `<!doctype html>
<html>
<head><meta charset="utf-8"><title>stylesheet census</title></head>
<body>
  <div id="census-probe">probe</div>
  <div id="shadow-host"><span id="shadow-probe"></span></div>
</body>
</html>`;

// Environment overrides run BEFORE the userscript, the way a hostile or legacy
// host would present itself. NOTE: instance-level defineProperty is used on
// purpose -- this Chromium build does not let a prototype redefinition of
// these WebIDL members shadow the native accessor (measured: prototype
// redefinition succeeds per descriptor yet the instance keeps returning the
// native value).
const ENV = {
  noAdopted: `(() => {
    Object.defineProperty(document, 'adoptedStyleSheets', { configurable: true, get: () => undefined });
  })();`,
  replaceSyncThrows: `(() => {
    const Orig = window.CSSStyleSheet;
    window.CSSStyleSheet = function () {
      const s = new Orig();
      s.replaceSync = function () { throw new Error('synthetic replaceSync failure'); };
      return s;
    };
  })();`,
  adoptedAssignThrows: `(() => {
    Object.defineProperty(document, 'adoptedStyleSheets', {
      configurable: true,
      get: () => [],
      set: function () { throw new Error('synthetic frozen adoptedStyleSheets'); }
    });
  })();`
};

// The census itself: everything asserted by the gate, measured the same way in
// every environment.
const CENSUS_FN = () => {
  const sheets = (document.__w95Sheets || {});
  const adopted = Array.isArray(document.adoptedStyleSheets) ? document.adoptedStyleSheets : [];
  const w95Adopted = adopted.filter(s => Object.keys(sheets).some(k => sheets[k] === s));
  const dom = Array.from(document.querySelectorAll('style[data-w95="global"]'));
  const shadowHost = document.getElementById('shadow-host');
  const shadow = shadowHost && shadowHost.shadowRoot;
  const shadowSheets = (shadow && shadow.__w95Sheets) || {};
  const shadowAdopted = (shadow && Array.isArray(shadow.adoptedStyleSheets))
    ? shadow.adoptedStyleSheets.filter(s => Object.keys(shadowSheets).some(k => shadowSheets[k] === s))
    : [];
  const shadowDom = shadow ? Array.from(shadow.querySelectorAll('style[data-w95="shadow"]')) : [];
  const ruleText = (sheet) => {
    try { return Array.from(sheet.cssRules || []).map(r => r.cssText).join('\\n'); } catch (e) { return ''; }
  };
  const docRuleCount = w95Adopted.reduce((n, s) => n + (s.cssRules ? s.cssRules.length : 0), 0) +
    dom.reduce((n, s) => n + (s.sheet ? s.sheet.cssRules.length : 0), 0);
  const shadowRuleCount = shadowAdopted.reduce((n, s) => n + (s.cssRules ? s.cssRules.length : 0), 0) +
    shadowDom.reduce((n, s) => n + (s.sheet ? s.sheet.cssRules.length : 0), 0);
  return {
    docAdoptedCount: w95Adopted.length,
    docDomCount: dom.length,
    docAdoptedText: w95Adopted.map(ruleText).join('\n'),
    docDomText: dom.map(s => s.textContent).join('\n'),
    docAdoptedRules: w95Adopted.reduce((n, s) => n + (s.cssRules ? s.cssRules.length : 0), 0),
    docDomRules: dom.reduce((n, s) => n + (s.sheet ? s.sheet.cssRules.length : 0), 0),
    docRuleCount: docRuleCount,
    docSheetIdentity: sheets['global'] ? adopted.indexOf(sheets['global']) : -2,
    docIsLastAdopted: !!(sheets['global'] && adopted.length && adopted[adopted.length - 1] === sheets['global']),
    shadowPresent: !!shadow,
    shadowAdoptedCount: shadowAdopted.length,
    shadowDomCount: shadowDom.length,
    shadowAdoptedText: shadowAdopted.map(ruleText).join('\n'),
    shadowDomText: shadowDom.map(s => s.textContent).join('\n'),
    shadowAdoptedRules: shadowAdopted.reduce((n, s) => n + (s.cssRules ? s.cssRules.length : 0), 0),
    shadowDomRules: shadowDom.reduce((n, s) => n + (s.sheet ? s.sheet.cssRules.length : 0), 0),
    shadowRuleCount: shadowRuleCount,
    shadowVerAttr: shadowDom.length ? shadowDom[0].getAttribute('data-w95-ver') : null,
    probeColor: (() => {
      const el = document.getElementById('census-probe');
      return el ? getComputedStyle(el).getPropertyValue('--w95-probe').trim() : null;
    })(),
    htmlThemed: (() => {
      const st = document.documentElement.style;
      return !!(st && st.backgroundColor);
    })()
  };
};

async function newCensusPage(browser) {
  const page = await browser.newPage({ viewport: { width: 800, height: 600 } });
  await page.setContent(FIXTURE, { waitUntil: 'domcontentloaded' });
  return page;
}

// Environment overrides must land on the LIVE document/window: addInitScript
// runs on the navigation that setContent discards, so instance-level patches
// made there are lost (measured). Applied here, immediately before the
// userscript eval, against the document the userscript will actually see.
async function applyEnv(page, env) {
  if (!env) return;
  await page.evaluate(code => { (0, eval)(code); }, ENV[env]);
}

async function evalScript(page, src) {
  await page.evaluate(s => { (0, eval)(s); }, src);
}

// In the noAdopted environment the shadow root itself must present as
// legacy: the override lands on the root instance before the wrapper's
// microtask reads it (same task, microtask later).
async function attachShadowLegacy(page) {
  await page.evaluate(() => {
    const host = document.getElementById('shadow-host');
    const r = host.attachShadow({ mode: 'open' });
    if (r.adoptedStyleSheets) {
      Object.defineProperty(r, 'adoptedStyleSheets', { configurable: true, get: () => undefined });
    }
    return !!r;
  });
}

(async () => {
  const browser = await chromium.launch();
  const oldSrc = loadBaseline();

  // ── RED control: the previous implementation reproduces both dual installs ──
  console.log('-- RED control: previous implementation (audit baseline ' + BASELINE_SHA.slice(0, 8) + ') --');
  {
    const page = await newCensusPage(browser);
    await evalScript(page, oldSrc);
    await page.evaluate(() => { const h = document.getElementById('shadow-host'); h.attachShadow({ mode: 'open' }); });
    await page.evaluate(() => new Promise(r => setTimeout(r, 20)));
    const c = await page.evaluate(CENSUS_FN);
    const squash = t => String(t || '').replace(/\s+/g, ' ');
    check('RC-A1: old build installs adopted sheet (reproduced)', c.docAdoptedCount === 1, 'adopted=' + c.docAdoptedCount);
    check('RC-A2: old build ALSO installs identical DOM duplicate (defect reproduced)',
      c.docDomCount === 1 && c.docAdoptedRules === c.docDomRules && c.docAdoptedRules > 0,
      'dom=' + c.docDomCount + ' adoptedRules=' + c.docAdoptedRules + ' domRules=' + c.docDomRules);
    check('RC-A3: old shadow path also dual-installs (defect reproduced)',
      c.shadowAdoptedCount === 1 && c.shadowDomCount === 1 && c.shadowAdoptedRules === c.shadowDomRules && c.shadowAdoptedRules > 0,
      'shadowAdopted=' + c.shadowAdoptedCount + ' shadowDom=' + c.shadowDomCount);
    await page.close();
  }

  // ── A. constructable stylesheets supported ──
  console.log('\n-- A. supported environment --');
  {
    const page = await newCensusPage(browser);
    await evalScript(page, CURRENT);
    await page.evaluate(() => { document.getElementById('shadow-host').attachShadow({ mode: 'open' }); });
    await page.evaluate(() => new Promise(r => setTimeout(r, 20)));
    const c = await page.evaluate(CENSUS_FN);
    check('A1: document has exactly one adopted Wintage sheet', c.docAdoptedCount === 1, 'adopted=' + c.docAdoptedCount);
    check('A2: document has ZERO DOM Wintage styles', c.docDomCount === 0, 'dom=' + c.docDomCount);
    check('A3: shadow root has exactly one adopted Wintage sheet', c.shadowAdoptedCount === 1, 'shadowAdopted=' + c.shadowAdoptedCount);
    check('A4: shadow root has ZERO DOM Wintage styles', c.shadowDomCount === 0, 'shadowDom=' + c.shadowDomCount);
    check('A5: page is themed (paintRoot wrote the palette background)', c.htmlThemed);
    await page.close();
  }

  // ── B. constructable stylesheets unsupported ──
  console.log('\n-- B. constructable stylesheets unsupported --');
  {
    const page = await newCensusPage(browser); await applyEnv(page, 'noAdopted');
    await evalScript(page, CURRENT);
    await attachShadowLegacy(page);
    await page.evaluate(() => new Promise(r => setTimeout(r, 20)));
    const c = await page.evaluate(CENSUS_FN);
    check('B1: document falls back to exactly one DOM Wintage style', c.docDomCount === 1, 'dom=' + c.docDomCount);
    check('B2: no adopted sheet claimed', c.docAdoptedCount === 0);
    check('B3: shadow root falls back to exactly one DOM Wintage style', c.shadowDomCount === 1, 'shadowDom=' + c.shadowDomCount);
    check('B4: fallback content is non-empty and themed', c.htmlThemed && c.docDomText.length > 100);
    await page.close();
  }

  // ── C. replaceSync failure ──
  console.log('\n-- C. replaceSync failure --');
  {
    const page = await newCensusPage(browser); await applyEnv(page, 'replaceSyncThrows');
    await evalScript(page, CURRENT);
    await page.evaluate(() => new Promise(r => setTimeout(r, 20)));
    const c = await page.evaluate(CENSUS_FN);
    check('C1: replaceSync failure falls back to one DOM style', c.docDomCount === 1, 'dom=' + c.docDomCount);
    check('C2: no adopted sheet leaked in', c.docAdoptedCount === 0);
    check('C3: no phantom bookkeeping entry', c.docSheetIdentity === -2 || c.docSheetIdentity === -1);
    await page.close();
  }

  // ── D. adoptedStyleSheets assignment refused ──
  console.log('\n-- D. adoptedStyleSheets assignment refused --');
  {
    const page = await newCensusPage(browser); await applyEnv(page, 'adoptedAssignThrows');
    await evalScript(page, CURRENT);
    await page.evaluate(() => new Promise(r => setTimeout(r, 20)));
    const c = await page.evaluate(CENSUS_FN);
    check('D1: refused assignment falls back to one DOM style', c.docDomCount === 1, 'dom=' + c.docDomCount);
    check('D2: refused sheet is not registered as adopted', c.docAdoptedCount === 0);
    check('D3: no phantom bookkeeping entry', c.docSheetIdentity === -2 || c.docSheetIdentity === -1);
    await page.close();
  }

  // ── E. strict-CSP page ──
  console.log('\n-- E. strict-CSP page (style-src with no unsafe-inline) --');
  {
    const page = await browser.newPage({ viewport: { width: 800, height: 600 } });
    const cspViolations = [];
    page.on('console', msg => {
      if (/Content Security Policy/i.test(msg.text())) cspViolations.push(msg.text());
    });
    const cspFixture = FIXTURE.replace('<head>',
      '<head><meta http-equiv="Content-Security-Policy" content="style-src \'self\'">');
    await page.setContent(cspFixture, { waitUntil: 'domcontentloaded' });
    await evalScript(page, CURRENT);
    const c = await page.evaluate(CENSUS_FN);
    check('E1: strict CSP still receives the constructable sheet', c.docAdoptedCount === 1, 'adopted=' + c.docAdoptedCount);
    check('E2: strict CSP installs no blocked DOM duplicate', c.docDomCount === 0, 'dom=' + c.docDomCount);
    check('E3: theme applies from the sheet', c.docAdoptedText.length > 100);
    check('E4: no CSP violation raised by our install path', cspViolations.length === 0, cspViolations[0] || '');
    await page.close();
  }

  // ── F. existing stylesheet followed by reinjection (supported) ──
  console.log('\n-- F. reinjection over an existing stylesheet --');
  {
    const page = await newCensusPage(browser);
    await evalScript(page, withGeneration(CURRENT, 1));
    const c1 = await page.evaluate(CENSUS_FN);
    check('F0: generation 1 installed with marker', c1.docAdoptedText.includes('--w95-gen: 1'), c1.docAdoptedText.slice(0, 80));
    await evalScript(page, withGeneration(CURRENT, 2));
    const c2 = await page.evaluate(CENSUS_FN);
    check('F1: reinjection keeps exactly one adopted copy', c2.docAdoptedCount === 1, 'adopted=' + c2.docAdoptedCount);
    check('F2: reinjection adds no DOM duplicate', c2.docDomCount === 0, 'dom=' + c2.docDomCount);
    check('F3: new generation content replaced old in place',
      c2.docAdoptedText.includes('--w95-gen: 2') && !c2.docAdoptedText.includes('--w95-gen: 1'));
    check('F4: rule count equals one copy (no accumulation)', c2.docRuleCount === c1.docRuleCount,
      'gen1=' + c1.docRuleCount + ' gen2=' + c2.docRuleCount);
    check('F5: sheet stays last in the adopted list (cascade order)', c2.docIsLastAdopted);
    await page.close();
  }

  // ── F2. reinjection in DOM-fallback environment ──
  {
    const page = await newCensusPage(browser); await applyEnv(page, 'noAdopted');
    await evalScript(page, withGeneration(CURRENT, 1));
    await evalScript(page, withGeneration(CURRENT, 2));
    const c = await page.evaluate(CENSUS_FN);
    check('F6: fallback reinjection refreshes the single DOM style',
      c.docDomCount === 1 && c.docDomText.includes('--w95-gen: 2') && !c.docDomText.includes('--w95-gen: 1'),
      'dom=' + c.docDomCount);
    await page.close();
  }

  // ── G. existing ShadowRoot followed by reinjection ──
  console.log('\n-- G. reinjection over an existing ShadowRoot --');
  {
    const page = await newCensusPage(browser);
    await evalScript(page, withGeneration(CURRENT, 1));
    await page.evaluate(() => { document.getElementById('shadow-host').attachShadow({ mode: 'open' }); });
    await page.evaluate(() => new Promise(r => setTimeout(r, 20)));
    await evalScript(page, withGeneration(CURRENT, 2));
    await page.evaluate(() => new Promise(r => setTimeout(r, 20)));
    const c = await page.evaluate(CENSUS_FN);
    check('G1: shadow keeps exactly one effective copy', c.shadowAdoptedCount === 1 && c.shadowDomCount === 0,
      'adopted=' + c.shadowAdoptedCount + ' dom=' + c.shadowDomCount);
    check('G2: shadow adopted sheet refreshed to generation 2',
      c.shadowAdoptedText.includes('--w95-gen: 2') && !c.shadowAdoptedText.includes('--w95-gen: 1'),
      c.shadowAdoptedText.slice(0, 120));
    await page.close();
  }

  // ── G2. ShadowRoot reinjection in fallback environment ──
  {
    const page = await newCensusPage(browser); await applyEnv(page, 'noAdopted');
    await evalScript(page, withGeneration(CURRENT, 1));
    await attachShadowLegacy(page);
    await page.evaluate(() => new Promise(r => setTimeout(r, 20)));
    await evalScript(page, withGeneration(CURRENT, 2));
    await page.evaluate(() => new Promise(r => setTimeout(r, 20)));
    const c = await page.evaluate(CENSUS_FN);
    check('G3: fallback shadow style refreshed to generation 2',
      c.shadowDomCount === 1 && c.shadowDomText.includes('--w95-gen: 2'),
      'dom=' + c.shadowDomCount);
    await page.close();
  }

  // ── H. palette generation change: no stale rule survives ──
  console.log('\n-- H. palette generation change --');
  {
    const page = await newCensusPage(browser);
    await evalScript(page, withGeneration(CURRENT, 1));
    const before = await page.evaluate(CENSUS_FN);
    check('H0: generation 1 paints its probe colour', before.probeColor === 'rgb(11, 21, 31)', 'color=' + before.probeColor);
    await evalScript(page, withGeneration(CURRENT, 2));
    const after = await page.evaluate(CENSUS_FN);
    check('H1: probe paints the NEW generation colour only', after.probeColor === 'rgb(12, 22, 32)',
      'color=' + after.probeColor);
    await page.close();
  }

  // ── I. repeated reinjection keeps the census stable ──
  console.log('\n-- I. repeated reinjection --');
  {
    const page = await newCensusPage(browser);
    await evalScript(page, withGeneration(CURRENT, 1));
    let last = await page.evaluate(CENSUS_FN);
    let stable = true;
    for (let g = 2; g <= 4; g++) {
      await evalScript(page, withGeneration(CURRENT, g));
      last = await page.evaluate(CENSUS_FN);
      if (last.docAdoptedCount !== 1 || last.docDomCount !== 0) stable = false;
    }
    check('I1: after 3 reinjections still exactly one adopted, zero DOM', stable,
      'adopted=' + last.docAdoptedCount + ' dom=' + last.docDomCount);
    check('I2: latest generation marker only', last.docAdoptedText.includes('--w95-gen: 4') && !last.docAdoptedText.includes('--w95-gen: 3'));
    check('I3: rule count did not accumulate across reinjections', last.docRuleCount > 0 && last.docAdoptedCount === 1);
    await page.close();
  }

  // ── upgrade mix: old build left the dual install, new build takes over ──
  console.log('\n-- upgrade mix: baseline dual install, then current build --');
  {
    const page = await newCensusPage(browser);
    await evalScript(page, withGeneration(oldSrc, 1));
    await page.evaluate(() => { document.getElementById('shadow-host').attachShadow({ mode: 'open' }); });
    await page.evaluate(() => new Promise(r => setTimeout(r, 20)));
    const dual = await page.evaluate(CENSUS_FN);
    check('U0: baseline dual install present before upgrade',
      dual.docAdoptedCount === 1 && dual.docDomCount === 1, 'adopted=' + dual.docAdoptedCount + ' dom=' + dual.docDomCount);
    await evalScript(page, withGeneration(CURRENT, 2));
    await page.evaluate(() => new Promise(r => setTimeout(r, 20)));
    const healed = await page.evaluate(CENSUS_FN);
    check('U1: current build retires the inherited DOM duplicate', healed.docDomCount === 0 && healed.docAdoptedCount === 1,
      'adopted=' + healed.docAdoptedCount + ' dom=' + healed.docDomCount);
    check('U2: current build retires the inherited shadow DOM duplicate',
      healed.shadowAdoptedCount === 1 && healed.shadowDomCount === 0,
      'shadowAdopted=' + healed.shadowAdoptedCount + ' shadowDom=' + healed.shadowDomCount);
    check('U3: upgraded content is the new generation everywhere',
      healed.docAdoptedText.includes('--w95-gen: 2') && healed.shadowAdoptedText.includes('--w95-gen: 2'));
    await page.close();
  }

  // ── J. document and ShadowRoot coverage asserted independently ──
  console.log('\n-- J. independent document/shadow census --');
  {
    const page = await newCensusPage(browser);
    await evalScript(page, CURRENT);
    // nested shadow trees: inner host lives INSIDE the outer shadow root
    await page.evaluate(() => {
      const host = document.getElementById('shadow-host');
      const r1 = host.attachShadow({ mode: 'open' });
      r1.innerHTML = '<span id="shadow-probe"></span>';
      const inner = document.createElement('div');
      inner.id = 'inner-host';
      r1.appendChild(inner);
      const r2 = inner.attachShadow({ mode: 'open' });
      r2.innerHTML = '<span id="deep">deep</span>';
    });
    await page.evaluate(() => new Promise(r => setTimeout(r, 20)));
    const c = await page.evaluate(CENSUS_FN);
    check('J1: outer shadow root themed independently of the document',
      c.shadowAdoptedCount === 1 && c.shadowDomCount === 0);
    const nested = await page.evaluate(() => {
      const innerHost = document.getElementById('shadow-host').shadowRoot &&
        document.getElementById('shadow-host').shadowRoot.getElementById('inner-host');
      const nested = innerHost && innerHost.shadowRoot;
      if (!nested) return { present: false };
      const sheets = nested.__w95Sheets || {};
      const adopted = (nested.adoptedStyleSheets || []).filter(s => Object.keys(sheets).some(k => sheets[k] === s));
      return {
        present: true,
        adopted: adopted.length,
        dom: nested.querySelectorAll('style[data-w95="shadow"]').length,
        deepOk: !!nested.querySelector('#deep')
      };
    });
    check('J2: nested shadow root themed', nested.present && nested.adopted === 1 && nested.dom === 0 && nested.deepOk,
      JSON.stringify(nested));
    check('J3: document census independent of shadow census', c.docAdoptedCount === 1 && c.docDomCount === 0);
    await page.close();
  }

  await browser.close();

  if (bad > 0) {
    console.error('\ntest-stylesheet-census: ' + bad + ' failure(s)');
    process.exit(1);
  }
  console.log('\ntest-stylesheet-census gate: PASS');
  process.exit(0);
})().catch(e => {
  console.error('test-stylesheet-census unhandled error: ' + (e && e.stack ? e.stack : e));
  process.exit(1);
});
