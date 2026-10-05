#!/usr/bin/env node
'use strict';

// Gate for tools/inject-wintage-web.js and for the two live findings that file exists
// to make reachable. Neither repair can be checked by looking at the shipped source:
// the first is "does the CSS that reaches a real page still come from the product",
// and the second is "does the classifier agree with what the product actually
// paints". Both are answered by BITE proofs below -- a mutated copy of
// wintage.user.js must turn this gate red, and the live page is not needed.
//
// Usage: node tools/test-inject-wintage-web.js   (exit 0 = pass, 1 = fail)

const fs = require('fs');
const path = require('path');
const os = require('os');
const Module = require('module');

const ROOT = path.join(__dirname, '..');
const USER_JS = path.join(ROOT, 'wintage.user.js');

let failures = 0;
const check = (ok, msg) => { console.log((ok ? 'PASS: ' : 'FAIL: ') + msg); if (!ok) failures++; };
const group = t => console.log('\n--- ' + t + ' ---');

const { buildInjectionExpression, bindings, literal, source } = require('./inject-wintage-web.js');
const inspector = require('./inspect-web.js');

// ── The injection is the product's CSS ────────────────────────────────────────
group('the injected sheet is the product\'s own');
const expr = buildInjectionExpression('goldendefault');
const b = bindings('goldendefault');

check(!/\$\{[A-Za-z_]/.test(expr),
  'no build placeholder survives into the payload (an unresolved ${T.x} is dropped silently by the browser)');
check(expr.includes(b.T.background) && expr.includes(b.T.surface) && expr.includes(b.T.surfaceRaised),
  'the payload carries the shipped palette values, not a copy of them');
// Golden Default is the palette the T-373 handoff names, so pin it: a silent palette
// swap upstream would otherwise show up as a live run against a different theme.
check(b.T.background === '#1A1810' && b.T.backgroundSoft === '#232018' &&
      b.T.surface === '#332E22' && b.T.surfaceRaised === '#3D372A',
  'goldendefault is still the Golden Default palette the acceptance was written against');
check(b.DARK === true, 'polarity is derived from the palette, not assumed (goldendefault is dark)');

// CHATGPT_FAST_CSS, not GLOBAL_CSS. ACTIVE_GLOBAL_CSS routes ChatGPT to the fast
// sheet (wintage.user.js:2340), so injecting GLOBAL_CSS here would theme a page the
// product never themes -- the handoff prohibition, made checkable.
// eval resolves a template literal against the scope the literal is written in, so
// each sheet has to be evaluated with the same six bindings the product has in scope.
// All three sheets need exactly {DARK,T,FONT,B_OUTER,B_INNER,B_SUNK} -- anything more
// would make this resolver silently wrong rather than loudly unbound.
const resolved = name => {
  const { T, DARK, FONT, B_OUTER, B_INNER, B_SUNK } = b;
  return eval('`' + literal(source(), name) + '`');
};
// The payload carries the sheets as JSON string literals, so the text that reaches the
// page is the JSON-escaped form, not the CSS itself. Comparing against raw CSS compares
// against a string the payload can never contain.
const enc = s => JSON.stringify(s).slice(1, -1);
const fastCss = resolved('CHATGPT_FAST_CSS');
check(expr.includes(enc(fastCss).slice(0, 400)) && expr.includes(enc(fastCss).slice(-200)),
  'the global sheet is CHATGPT_FAST_CSS end to end');
check(!expr.includes(enc(resolved('GLOBAL_CSS')).slice(2000, 2400)),
  'no GLOBAL_CSS body is injected on a ChatGPT host');
check(expr.includes('data-w95-chatgpt'), 'the ChatGPT root marker is set, or every rule in the sheet is inert');
check(/setAttribute\('data-w95', 'global'\)/.test(expr) && expr.includes("setAttribute('data-w95-ver'"),
  'the sheet carries the product\'s own data-w95 stamp, which is what inspect-web looks for');

// Scope follows the marker, not the other way round: every rule in the sheet is keyed to
// the root attribute the payload sets, and a mismatch themes nothing while still looking
// like a successful injection.
const sheetRoots = [...new Set([...fastCss.matchAll(/html\[data-w95-[a-z-]+="1"\]/g)].map(m => m[0]))];
check(sheetRoots.length === 1 && sheetRoots[0] === 'html[data-w95-chatgpt="1"]',
  'every rule in the sheet is scoped to the attribute the payload actually sets (inert-theme guard)');

// Lean CSS-only path: no repainter, no observer, no sweep.
check(!/MutationObserver/.test(expr), 'no MutationObserver is installed (CSS-only mode has none)');
check(!/getComputedStyle\s*\(/.test(expr), 'the payload paints nothing by reading styles back');
check(!/\bx-[a-z0-9]{4,}\b/i.test(expr), 'no generated atomic class is referenced');

// Shadow handling is the shipped ChatGPT path, not an addition.
check(expr.includes('attachShadow'), 'shadow roots are styled as they are created, as the product does');
check(expr.includes('shadowRootsPainted'), 'the payload reports what it painted, so a silent no-op is visible');

group('idempotence');
check(/querySelector\('style\[data-w95="global"\]'\)/.test(expr),
  'a second run finds its own sheet instead of stacking a second copy');

// ── Live finding 1: <html> is held to --background, not --chat-background-color ──
group('the <html> expectation matches what paintRoot actually paints');
check(inspector.SURFACE_TOKENS.root === '--background',
  'root is held to --background, which is what paintRoot writes inline on <html>');
check(inspector.SURFACE_TOKENS['root-body'] === '--chat-background-color',
  'root-body is untouched: body really is backgroundSoft');
// The token has to be resolvable by the SURFACE probe. Its list and the opaque
// probe's list are two different arrays, and the raw getPropertyValue fallback
// yields "#1A1810" rather than a computed rgb() -- so an expectation naming a
// token the surface list omits reports "resolved to nothing" on a correct page.
// The window is the TOKEN_NAMES array itself, not a fixed span: the list is long enough
// that a fixed window silently stops covering its tail, and the tail is where a newly
// added token lands -- which is exactly the check that would then never fail.
const probe = String(inspector.buildProbeExpression(inspector.SURFACES, {}));
const tn = probe.indexOf('TOKEN_NAMES');
const tokenList = tn < 0 ? '' : probe.slice(tn, probe.indexOf(']', tn));
check(tokenList.includes("'--background'"),
  'the surface probe resolves --background, not only the opaque probe');

// ── Live finding 2: the composer root has a variant-dependent contract ────────
group('the composer root contract is judged with its sibling');
const prodCss = source();
check(prodCss.includes('[data-composer-dark][data-composer-utility-bar-variant="home"]'),
  'the product really does have the two-variant composer contract this gate models');
// A transparent composer member must not be able to pass on its own. `present` is what
// the probe reports and what classifySurface keys on -- omit it and both surfaces read as
// "absent", which summarize skips silently, so the test would pass by not testing anything.
// Both shapes were measured live: `home` leaves the root transparent, `default` leaves the
// body transparent. Each is a MISMATCH before the pairing and a pass after it.
const report = (rootBg, bodyBg) => ({
  surfaces: [
    { id: 'composer-root', label: 'composer root', selector: 'x', present: true, count: 1, style: { backgroundColor: rootBg } },
    { id: 'composer-body', label: 'composer body', selector: 'y', present: true, count: 1, style: { backgroundColor: bodyBg } }
  ],
  tokens: { '--composer-background-color': 'rgb(51, 46, 34)' },
  route: '/'
});
const CLEAR = 'rgba(0, 0, 0, 0)';
const PAINTED = 'rgb(51, 46, 34)';
for (const [label, rootBg, bodyBg, wantClean] of [
  ['the home variant leaves the root transparent', CLEAR, PAINTED, true],
  ['the default variant leaves the body transparent', PAINTED, CLEAR, true],
  ['a stock composer paints neither member', CLEAR, CLEAR, false],
  ['both members painted', PAINTED, PAINTED, true]
]) {
  const r = inspector.summarize(report(rootBg, bodyBg));
  const bad = r.mismatches.some(m => m.id === 'composer-root' || m.id === 'composer-body');
  check(bad !== wantClean, label + (wantClean ? ' -- passes' : ' -- still fails'));
}

// ── Red controls: each must bite ───────────────────────────────────────────────
group('red controls (each mutation must turn this gate red)');
const runGate = (userJsPath) => {
  // The injector reads wintage.user.js by path at call time, so a mutated copy is
  // exercised by pointing that one path at it -- no second implementation to keep
  // in sync, and no chance of the control proving something the product never does.
  const real = fs.readFileSync(USER_JS, 'utf8');
  fs.writeFileSync(USER_JS, fs.readFileSync(userJsPath, 'utf8'));
  try { return buildInjectionExpression('goldendefault'); }
  finally { fs.writeFileSync(USER_JS, real); }
};

const bite = (label, mutate, mustGoRed) => {
  const tmp = path.join(os.tmpdir(), 'w95-bite-' + process.pid + '-' + Math.abs(label.length) + '.js');
  fs.writeFileSync(tmp, mutate(fs.readFileSync(USER_JS, 'utf8')));
  let red = false, detail = '';
  try {
    const out = runGate(tmp);
    // Red means the payload is observably wrong, by the same rules the live run uses.
    const why = payloadDefect(out);
    red = !!why;
    detail = red ? why : 'payload still looked valid';
  } catch (e) { red = true; detail = e.message.slice(0, 90); }
  finally { try { fs.unlinkSync(tmp); } catch (e) { } }
  check(red === mustGoRed, label + (red ? ' [control: RED as required]' : ' [control did not bite]') + (detail ? ' -- ' + detail : ''));
};

// One predicate, so a control cannot go red for a reason the real gate does not care
// about, and cannot stay green on a defect the checks above would have caught. `undefined`
// is in the list on purpose: a theme token the CSS interpolates but the pack does not
// define emits "background-color: undefined", which the browser drops without a word --
// the payload still looks complete and the surface still looks stock.
// `undefined` in a CSS value position is the defect, not the word anywhere: the payload
// legitimately contains typeof guards against 'undefined'. An unresolved token lands as
// "background-color: undefined", which the browser drops without a word.
function payloadDefect(out) {
  if (!out) return 'payload is empty';
  if (/\$\{[A-Za-z_]/.test(out)) return 'a build placeholder survived into the payload';
  if (/: undefined\b/.test(out)) return 'an unresolved token emitted the value "undefined"';
  if (!out.includes("setAttribute('data-w95-chatgpt', '1')")) return 'the ChatGPT root marker is not set';
  if (/MutationObserver/.test(out)) return 'an observer crept into a CSS-only payload';
  const roots = [...new Set([...out.replace(/\\"/g, '"').matchAll(/html\[data-w95-[a-z-]+="1"\]/g)].map(m => m[0]))];
  if (roots.length !== 1 || roots[0] !== 'html[data-w95-chatgpt="1"]') return 'the sheet is scoped to an attribute nobody sets';
  return '';
}

bite('a palette token the CSS interpolates no longer exists',
  s => s.replace(/surfaceRaised:/g, 'surfaceRaisedRenamed:'), true);
bite('the sheet stops being scoped to the attribute the payload sets',
  s => s.replace(/html\[data-w95-chatgpt="1"\]/g, 'html[data-w95-nope="1"]'), true);
bite('an observer creeps into the injected payload',
  s => s.replace('const CHATGPT_FAST_CSS = `', 'const CHATGPT_FAST_CSS = ` /* MutationObserver */'), true);

// ── Shipped gate still green after the bite scripts restored the file ─────────
group('the product file is intact after the controls');
const finalSrc = fs.readFileSync(USER_JS, 'utf8');
check(finalSrc === source(), 'wintage.user.js was restored byte for byte by every control');
check(/\$\{[A-Za-z_]/.test(buildInjectionExpression('goldendefault')) === false,
  'the shipped payload is still placeholder-free');

if (failures) { console.error('\n' + failures + ' injector gate check(s) failed'); process.exit(1); }
console.log('\ninject-wintage-web gate: PASS');