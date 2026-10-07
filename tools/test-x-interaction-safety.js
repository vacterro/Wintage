#!/usr/bin/env node
// X / Twitter interaction-safety gate.
//
// WHY THIS EXISTS. X ships reply and post submission through the SAME rendered
// composer the theme paints, and the theme is delivered as page CSS on every
// frame of x.com. A reported live failure -- the composer looks themed, and
// posting a reply comes back as X's own red "Something went wrong" -- therefore
// has to be split into the two things CSS can actually do to it, and neither of
// them can be seen in the source:
//
//   (1) BREAK THE CONTROL. Mutating its interaction properties (a hit test that
//       lands on a covering box, `visibility`, `pointer-events`, `user-select`,
//       `display`) would stop the user's own click from reaching X's handler.
//   (2) BREAK THE CLASSIFICATION. Hardening X against a heavy repaint is what
//       made it stable; a later edit that dropped IS_X back out of
//       HIGH_CHURN_HOST, or that dropped the anti-fraud/challenge hosts back
//       out of EXCLUDE, would put the generic repainter or the route guard back
//       in the middle of the submit pipeline -- the 1.36.1 defect.
//
// Neither is a guessable selector problem, and this file deliberately does NOT
// guess one. It pins the two structural guarantees that must survive any future
// edit, plus the one thing a source read cannot see: that the shipped sheet,
// applied to an X-shaped composer, leaves a real click and a real keystroke
// reaching the page.
//
// WHAT IT DOES NOT CLAIM. It is not live acceptance. X's server-side rejection
// cannot be reproduced offline, and the handoff's own rule applies: a failure
// that persists with the theme disabled is NOT a theme defect. The operator A/B
// -- theme on / theme fully disabled for x.com, same account and text, no other
// change -- is the only thing that decides defect 2, and it stays a human step.
//
// RED CONTROLS. Four, each proven to go red: the sensor control proves a CSS
// interaction break would be caught at all, and the three static controls cut
// the classification, the EXCLUDE hardening and the rule-body-safety assertions
// in turn.
//
// PRIVACY. The fixture is synthetic and local: no page is loaded, no URL is
// fetched, no account exists. Nothing is submitted anywhere.

const fs = require('fs');
const path = require('path');

let chromium;
try {
  ({ chromium } = require('playwright'));
} catch (e) {
  console.error('FAIL: playwright is not installed in this checkout.');
  console.error('      It is a contributor test dependency declared in package.json');
  console.error('      ("devDependencies": { "playwright": "^1.62.1" }); neither the');
  console.error('      theme nor the installer ships it. Obtain it deterministically:');
  console.error('        npm ci');
  console.error('        npx playwright install chromium');
  console.error('      Underlying error: ' + (e && e.message ? e.message : e));
  process.exit(1);
}

const SRC = fs.readFileSync(path.join(__dirname, '..', 'wintage.user.js'), 'utf8');
let bad = 0;
function pass(label) { console.log('PASS: ' + label); }
function fail(label) { console.error('FAIL: ' + label); bad++; }
function check(label, ok, detail) {
  if (ok) { pass(label); return true; }
  fail(label + (detail ? ' -- ' + detail : ''));
  return false;
}

// ── Helpers shared with the other sheet gates ────────────────────────────────
function templateLiteral(name) {
  const decl = 'const ' + name + ' = `';
  const i = SRC.indexOf(decl);
  if (i < 0) return '';
  const start = i + decl.length;
  const m = /\n[ \t]*`;/.exec(SRC.slice(start));
  return m ? SRC.slice(start, start + m.index) : '';
}
function goldenDefaultTokens() {
  const at = SRC.indexOf('goldendefault:');
  if (at < 0) return null;
  const open = SRC.indexOf('tokens: {', at);
  const close = SRC.indexOf('}', open);
  const out = {};
  for (const m of SRC.slice(open + 8, close).matchAll(/([A-Za-z][A-Za-z0-9]*)\s*:\s*'(#[0-9A-Fa-f]{6})'/g)) out[m[1]] = m[2];
  return out;
}
const TOKENS = goldenDefaultTokens();
const GLOBAL_CSS_RAW = templateLiteral('GLOBAL_CSS');
if (!TOKENS || !GLOBAL_CSS_RAW) {
  fail('GLOBAL_CSS or the Golden Default palette could not be read from wintage.user.js');
  console.error('\nx interaction safety gate: 1 failure(s)');
  process.exit(1);
}
const hexToRgb = hex => {
  const n = parseInt(hex.replace('#', ''), 16);
  return 'rgb(' + ((n >> 16) & 255) + ', ' + ((n >> 8) & 255) + ', ' + (n & 255) + ')';
};
function resolve(css) {
  return css.replace(/\$\{([^}]*)\}/g, (whole, expr) => {
    const t = /^\s*T\.([A-Za-z][A-Za-z0-9]*)\s*$/.exec(expr);
    if (!t) return 'initial';
    if (!TOKENS[t[1]]) throw new Error('palette token T.' + t[1] + ' is not in Golden Default');
    return TOKENS[t[1]];
  });
}
// X is not a CSS_ONLY fast-host, so it receives the full GLOBAL_CSS sheet.
const sheet = resolve(GLOBAL_CSS_RAW);

// ── 1. X stays on the CSS-only path ─────────────────────────────────────────
// The generic DOM repainter is what the X composer cannot afford mid-typing.
// Each link in the chain is asserted, so removing any ONE of them is caught.
console.log('-- x stays on the css-only path --');
const HIGH_CHURN_LINE = /const HIGH_CHURN_HOST = ([^\n;]+);/.exec(SRC);
const churnExpr = HIGH_CHURN_LINE ? HIGH_CHURN_LINE[1] : '';
check('IS_X is classified from the host, not from a path or a frame',
  /const IS_X = \/\(\^\|\\\.\)\(x\\\.com\|twitter\\\.com\)\$\//.test(SRC));
check('IS_X is the FIRST disjunct of HIGH_CHURN_HOST (not a later, shadowed one)',
  /^IS_X \|\|/.test(churnExpr.trim()), 'HIGH_CHURN_HOST = ' + churnExpr.trim());
check('CSS_ONLY_MODE is derived from HIGH_CHURN_HOST',
  /const CSS_ONLY_MODE = HIGH_CHURN_HOST;/.test(SRC));
check('the repainter starts suspended whenever CSS_ONLY_MODE is set',
  /let repainterSuspended = CSS_ONLY_MODE;/.test(SRC));
check('startObservers refuses to install on a CSS-only host',
  /function startObservers\(\)\s*\{\s*if \(CSS_ONLY_MODE \|\| repainterSuspended \|\| observersStarted\)/.test(SRC));
check('the diagnostic surface reports cssOnlyMode, so live acceptance can read it',
  /cssOnlyMode: CSS_ONLY_MODE,/.test(SRC));

// ── 2. The anti-fraud / challenge hosts are still excluded ───────────────────
// 1.36.1 fixed exactly this symptom by not treating these providers as heavy web
// apps. The array is READ HERE AND EXECUTED, so a regex that was edited into
// something that no longer matches its provider is caught (a comment saying the
// provider is handled is not evidence).
console.log('\n-- anti-fraud / challenge hosts are still excluded --');
const exStart = SRC.indexOf('const EXCLUDE = [');
const exEnd = exStart < 0 ? -1 : SRC.indexOf('];', exStart);
const exBody = exStart < 0 || exEnd < 0 ? '' : SRC.slice(exStart + 'const EXCLUDE = ['.length, exEnd);
check('the EXCLUDE array is present and non-empty', exBody.trim().length > 0);
let EXCLUDE = [];
if (exBody) {
  try {
    // Strip `//` comments, then build the array for real. Building it (rather
    // than grepping text) means the check is about behaviour.
    EXCLUDE = new Function('return [' + exBody.replace(/\/\/[^\n]*/g, '') + '];')();
  } catch (e) {
    check('the EXCLUDE array literal evaluates', false, String(e && e.message));
  }
}
check('EXCLUDE is a list of regular expressions', EXCLUDE.length > 0 && EXCLUDE.every(r => r instanceof RegExp),
  'entries=' + EXCLUDE.length);
check('isExcludedUrl routes every entry through the same predicate',
  /return EXCLUDE\.some\(r => r\.test\(url \|\| location\.href\)\);/.test(SRC));
const PROVIDERS = [
  ['Arkose Labs', 'https://iframerpc.arkoselabs.com/v2/index.html'],
  ['FunCaptcha/arkose', 'https://client-api.arkoselabs.com/fc/gc/'],
  ['Cloudflare challenge', 'https://challenges.cloudflare.com/cdn-cgi/challenge-platform/x'],
  ['Turnstile', 'https://challenges.cloudflare.com/turnstile/v0/api.js'],
  ['Kasada', 'https://api.kasada.io/x/kasada.js'],
  ['PerimeterX', 'https://client.perimeterx.net/abc/main.min.js'],
  ['OAuth callback', 'https://x.com/oauth/authorize?x=1'],
  ['Captcha step', 'https://x.com/account/access?captcha=1']
];
for (const [name, url] of PROVIDERS) {
  check('excluded route: ' + name + ' stops the theme from touching the page',
    EXCLUDE.some(r => r.test(url)), url);
}

// ── 3. No shipped rule mutates an interaction property ──────────────────────
// The generic control wipe reaches INSIDE X's submit button (it flattens nested
// surfaces, which is what makes the bevel read as one control). That is paint,
// and it must stay paint: any of these properties in a button/composer rule
// would break the user's own click before X ever saw it.
console.log('\n-- shipped rules touch paint, never interaction --');
const INTERACTION_PROPS = /(^|[\s{;])(pointer-events|user-select|-webkit-user-select|visibility|display|opacity)\s*:/g;
const RULE_SCOPES = [
  ['the button-pseudo-element paint wipe', /button::before, button::after, \.btn::before[\s\S]{0,400}?\{[^}]*\}/],
  ['the button-descendant flattening wipe', /button:not\(\.ytp-button\) \*:not\(i\)[^{}]*\{[^}]*\}/],
  ['the X composer/control paint block', /html\[data-w95-x="1"\] \[data-testid="SearchBox_Search_Input"\][\s\S]{0,400}?\{[^}]*\}/]
];
function interactionPropsIn(text) {
  const found = [];
  for (const m of text.matchAll(INTERACTION_PROPS)) found.push(m[2]);
  return found;
}
const scopesChecked = [];
for (const [name, re] of RULE_SCOPES) {
  const m = re.exec(sheet);
  if (!m) { check('rule present for inspection: ' + name, false); continue; }
  scopesChecked.push(name);
  check(name + ' sets paint only, never an interaction property',
    interactionPropsIn(m[0]).length === 0, 'found: ' + interactionPropsIn(m[0]).join(', '));
}
check('every interaction-relevant rule was found and inspected', scopesChecked.length === RULE_SCOPES.length,
  'inspected=' + scopesChecked.length + '/' + RULE_SCOPES.length);

// ── 4. The sheet, applied to an X-shaped composer, keeps it usable ──────────
// The fixture reproduces the reported shape: themed shell (primaryColumn), a
// themed contenteditable composer inside a form, and a themed submit button with
// a nested <span> -- the structure the generic wipe reaches into. The STOCK
// paint is X's own blue, so "the sheet applied" is visible as a colour change
// rather than assumed.
const X_BLUE = 'rgb(29, 155, 240)';
const STOCK_CSS = `
  html, body { margin: 0; background-color: rgb(0, 0, 0); }
  body { font: 14px sans-serif; }
  #primaryColumn { width: 600px; padding: 8px; }
  #composerWrap { width: 400px; min-height: 40px; padding: 8px; background-color: rgb(22, 24, 28); color: rgb(231, 233, 234); }
  #composerInner { display: inline-block; min-width: 40px; }
  #submit { width: 80px; height: 32px; margin-top: 8px; background-color: ${X_BLUE}; color: rgb(255, 255, 255); border: 0; }
  #stockOverlayNone { display: none; }
`;
const FIXTURE = `<!doctype html><html data-w95-x="1"><head><meta charset="utf-8">
<style>${STOCK_CSS}</style></head><body>
  <main id="primaryColumn" data-testid="primaryColumn">
    <div data-testid="cellInnerDiv"><div data-testid="tweet">
      <div data-testid="tweetText">a post</div>
      <form id="replyForm" action="#">
        <div id="composerWrap" role="textbox" data-testid="tweetTextarea_0" contenteditable="true"><span id="composerInner" data-text="true">draft</span></div>
        <button id="submit" type="submit" data-testid="tweetButtonInline"><span id="submitLabel">Reply</span></button>
      </form>
    </div></div>
  </main>
  <script>
    window.__xProbeClicks = 0;
    window.__xProbeSubmitted = 0;
    document.getElementById('submit').addEventListener('click', function () { window.__xProbeClicks++; });
    document.getElementById('replyForm').addEventListener('submit', function (e) { e.preventDefault(); window.__xProbeSubmitted++; });
  </script>
</body></html>`;

const PROBE = () => {
  const out = {};
  const submit = document.getElementById('submit');
  const wrap = document.getElementById('composerWrap');
  const inner = document.getElementById('composerInner');
  const cs = el => getComputedStyle(el);
  out.submitBackground = cs(submit).backgroundColor;
  out.submitPointerEvents = cs(submit).pointerEvents;
  out.submitVisibility = cs(submit).visibility;
  out.submitDisplay = cs(submit).display;
  out.submitUserSelect = cs(submit).userSelect;
  out.composerPointerEvents = cs(wrap).pointerEvents;
  out.composerVisibility = cs(wrap).visibility;
  out.composerDisplay = cs(wrap).display;
  out.composerUserSelect = cs(wrap).userSelect;
  out.composerBackground = cs(wrap).backgroundColor;
  out.labelVisibility = cs(document.getElementById('submitLabel')).visibility;
  out.labelDisplay = cs(document.getElementById('submitLabel')).display;
  // The real question: does a point inside each control BELONG to that control?
  // A covering box, an overlay or a pointer-events change answers this wrong even
  // when every individual property still looks fine.
  const hitOwner = el => {
    const r = el.getBoundingClientRect();
    const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
    if (!hit) return 'none';
    return hit === el || el.contains(hit) ? 'self' : (hit.id || hit.tagName.toLowerCase());
  };
  out.composerHitOwner = hitOwner(wrap);
  out.submitHitOwner = hitOwner(submit);
  out.clicks = window.__xProbeClicks;
  out.submits = window.__xProbeSubmitted;
  out.composerText = inner.textContent;
  return out;
};

async function measure(css) {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(String(e && e.message)));
  await page.setContent(FIXTURE);
  if (css) {
    // Exactly what the product does: the resolved sheet, after the page's own.
    await page.addStyleTag({ content: css });
  }
  const stock = await page.evaluate(PROBE);
  // A REAL click on the submit button and a REAL keystroke in the composer. Both
  // go through Chromium's own hit test, so a covering box or a hidden control
  // fails here rather than at the user.
  let clickError = null;
  try {
    await page.click('#submit', { timeout: 2000 });
  } catch (e) { clickError = String(e && e.message).split('\n')[0]; }
  let typeError = null;
  let typed = '';
  try {
    await page.click('#composerWrap', { timeout: 2000 });
    await page.keyboard.type('XY');
    typed = await page.evaluate(() => document.getElementById('composerInner').textContent);
  } catch (e) { typeError = String(e && e.message).split('\n')[0]; }
  const after = await page.evaluate(PROBE);
  await browser.close();
  return {
    stock,
    themed: after,
    clickError,
    typeError,
    typed,
    submitColorBefore: stock.submitBackground,
    composerColorBefore: stock.composerBackground,
    errors
  };
}

console.log('\n-- sheet applied to an X-shaped composer --');
// The browser half lives in an async IIFE: this file is CommonJS (require) and
// top-level await would make Node guess the module format and refuse to run it.
(async () => {
const stockRun = await measure(null);
const themedRun = await measure(sheet);
const S = stockRun.stock, T = themedRun.themed;

// Non-vacuity: the fixture itself is usable and stock-painted before the sheet.
check('fixture is not vacuous: the stock submit button is X blue before the sheet',
  S.submitBackground === X_BLUE, 'before=' + S.submitBackground);
check('fixture is not vacuous: the stock composer is clickable and hit-testable before the sheet',
  S.composerHitOwner === 'self' && S.composerPointerEvents !== 'none', JSON.stringify(S.composerHitOwner));
check('fixture is not vacuity: a stock click on submit is delivered before the sheet',
  stockRun.clickError === null && T.clicks >= 1,
  'clickError=' + stockRun.clickError + ' clicks=' + T.clicks);

// The sheet actually applied (otherwise the safety assertions below are inert).
check('the shipped sheet paints the submit button (the controls are themed, not stock)',
  T.submitBackground !== X_BLUE, 'bg=' + T.submitBackground + ' stock=' + X_BLUE);
check('the shipped sheet paints the composer surface',
  T.composerBackground !== S.composerBackground,
  'before=' + S.composerBackground + ' after=' + T.composerBackground);

// The safety contract.
check('the composer keeps pointer-events auto (the user can click into it)',
  T.composerPointerEvents !== 'none', 'pointerEvents=' + T.composerPointerEvents);
check('the composer keeps its selection behaviour (user-select is not none)',
  T.composerUserSelect !== 'none', 'userSelect=' + T.composerUserSelect);
check('the composer is still visible and displayed',
  T.composerVisibility === 'visible' && T.composerDisplay !== 'none',
  'visibility=' + T.composerVisibility + ' display=' + T.composerDisplay);
check('the composer is the topmost element at its own centre (nothing covers it)',
  T.composerHitOwner === 'self', 'hitOwner=' + T.composerHitOwner);
check('the composer is still editable: a real keystroke lands in it',
  themedRun.typeError === null && /XY/.test(themedRun.typed || ''),
  'typeError=' + themedRun.typeError + ' text=' + JSON.stringify(themedRun.typed));

check('the submit button keeps pointer-events auto',
  T.submitPointerEvents !== 'none', 'pointerEvents=' + T.submitPointerEvents);
check('the submit button is still visible and displayed',
  T.submitVisibility === 'visible' && T.submitDisplay !== 'none',
  'visibility=' + T.submitVisibility + ' display=' + T.submitDisplay);
check('the submit button is the topmost element at its own centre (the flattened '
  + 'descendant does not cover it)',
  T.submitHitOwner === 'self', 'hitOwner=' + T.submitHitOwner);
check('the label inside the submit button is not hidden by the descendant wipe',
  T.labelVisibility === 'visible' && T.labelDisplay !== 'none',
  'label=' + T.labelVisibility + '/' + T.labelDisplay);
check('a REAL click on submit is still delivered to the page (clicks >= 1)',
  themedRun.clickError === null && T.clicks >= 1,
  'clickError=' + themedRun.clickError + ' clicks=' + T.clicks);
check('the click also reached X\'s own submit handler (submit dispatched)',
  T.submits >= 1, 'submits=' + T.submits);
check('no page error was raised by applying the sheet', themedRun.errors.length === 0,
  themedRun.errors.join(' | '));

// ── RED controls ────────────────────────────────────────────────────────────
console.log('\n-- red controls (each must go red) --');
let rcBad = 0;
const rcCheck = (label, ok, detail) => {
  if (ok) { pass(label); return; }
  rcBad++; fail(label + (detail ? ' -- ' + detail : ''));
};

// RC1 SENSOR: this is not a "restore the pre-repair declaration" control,
// because there is no proven interaction declaration to restore -- the theme
// has none. It proves the SENSOR is live: the moment a future edit does add one,
// this file sees it. Without it, every pass above could be measuring nothing.
{
  const CRIPPLING = '\n[contenteditable="true"] { pointer-events: none !important; user-select: none !important; }\n'
    + '#submit { visibility: hidden !important; }\n';
  const r = await measure(sheet + CRIPPLING);
  rcCheck('RC1 sensor: a pointer-events/user-select/visibility break is DETECTED',
    r.themed.composerPointerEvents === 'none' && r.themed.composerUserSelect === 'none'
    && r.themed.submitVisibility !== 'visible' && r.clickError !== null,
    'composerPe=' + r.themed.composerPointerEvents + ' submitVis=' + r.themed.submitVisibility
    + ' clickError=' + r.clickError);
}
// RC2 the classification: drop IS_X from HIGH_CHURN_HOST.
{
  const mutated = SRC.replace(/const HIGH_CHURN_HOST = IS_X \|\|/, 'const HIGH_CHURN_HOST = false ||');
  rcCheck('RC2 control: dropping IS_X from HIGH_CHURN_HOST is DETECTED',
    mutated !== SRC && !/^IS_X \|\|/.test((/const HIGH_CHURN_HOST = ([^\n;]+);/.exec(mutated) || [])[1] || ''),
    'mutated=' + (mutated !== SRC));
}
// RC3 the hardening: remove the anti-fraud/challenge line from EXCLUDE.
{
  const mutated = SRC.replace(/\/arkoselabs\/i, \/funcaptcha\/i, \/challenges\\\.cloudflare\/i, \/turnstile\/i, \/kasada\/i, \/perimeterx\/i,/, '');
  let mutatedExclude = [];
  const s = mutated.indexOf('const EXCLUDE = [');
  const e = mutated.indexOf('];', s);
  try { mutatedExclude = new Function('return [' + mutated.slice(s + 19, e).replace(/\/\/[^\n]*/g, '') + '];')(); } catch (err) { }
  rcCheck('RC3 control: removing the anti-fraud/challenge line is DETECTED',
    mutated !== SRC && !mutatedExclude.some(r => r.test('https://api.kasada.io/x/kasada.js')),
    'mutated=' + (mutated !== SRC) + ' stillExcludes=' + mutatedExclude.some(r => r.test('https://api.kasada.io/x/kasada.js')));
}
// RC4 the rule-body assertion: it must fail on a rule that does set an
// interaction property, so the pass above is not a regex that matches nothing.
{
  const injected = sheet.replace(/(button:not\(\.ytp-button\) \*:not\(i\)[^{}]*)\{/,
    '$1{ pointer-events: none !important;');
  const m = /button:not\(\.ytp-button\) \*:not\(i\)[^{}]*\{[^}]*\}/.exec(injected);
  rcCheck('RC4 control: an interaction property injected into the wipe body is DETECTED',
    injected !== sheet && !!m && interactionPropsIn(m[0]).includes('pointer-events'),
    'injected=' + (injected !== sheet) + ' found=' + (m ? interactionPropsIn(m[0]).join(',') : 'no-rule'));
}

console.log('');
if (bad) {
  console.error('x interaction safety gate: ' + bad + ' failure(s)');
  process.exit(1);
}
console.log('x interaction safety gate: PASS');
})().catch(e => {
  console.error('x interaction safety gate: fatal -- ' + (e && e.stack ? e.stack : e));
  process.exit(1);
});
