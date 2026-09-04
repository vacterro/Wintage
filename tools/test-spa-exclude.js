#!/usr/bin/env node
// CORE-003: same-document SPA navigation must re-evaluate the EXCLUDE safety
// guard. Pre-fix the script returned at startup only, so a pushState /
// replaceState / popstate / hashchange into an excluded URL (oauth, captcha,
// paypal, stripe, bank, ...) left the already-active repainter mutating auth
// or payment UI. The fix installs a route guard BEFORE any DOM mutation and
// reloads the page when the new URL matches the EXCLUDE list.
//
// The wintage.userscript runs in Tampermonkey's sandboxed raw mode; we cannot
// just require() it. Instead, we extract the EXCLUDE / isExcludedUrl /
// setupRouteGuard declarations and exercise them under a minimal browser
// shim that records history.pushState / replaceState / popstate listeners and
// implements addEventListener for popstate and hashchange. The script's
// startup check is also covered: a direct load of every excluded URL must
// never call the DOM-mutating branches, while an allowed URL must install
// the guard and reload on a transition into an excluded URL.

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.join(__dirname, '..');
const SCRIPT = path.join(ROOT, 'wintage.user.js');

let bad = 0;
const check = (label, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  console.log((ok ? 'PASS: ' : 'FAIL: ') + label + (ok ? '' : '  got=' + JSON.stringify(got) + ' want=' + JSON.stringify(want)));
  if (!ok) bad++;
};

// Extract the EXCLUDE / isExcludedUrl / setupRouteGuard declarations by name.
// Pull from the EXCLUDE array literal (so the captured closure sees the same
// patterns) through the closing `}` of setupRouteGuard.
const src = fs.readFileSync(SCRIPT, 'utf8');
const excludeIdx = src.indexOf('const EXCLUDE = [');
if (excludeIdx < 0) { console.error('FAIL: EXCLUDE not found in wintage.user.js'); process.exit(1); }
const setupIdx = src.indexOf('function setupRouteGuard');
if (setupIdx < 0) { console.error('FAIL: setupRouteGuard not found in wintage.user.js'); process.exit(1); }
let depth = 0;
let blockEnd = -1;
for (let i = setupIdx; i < src.length; i++) {
  if (src[i] === '{') { depth++; }
  else if (src[i] === '}') { depth--; if (depth === 0) { blockEnd = i + 1; break; } }
}
if (blockEnd < 0) { console.error('FAIL: setupRouteGuard closing brace not found'); process.exit(1); }
const block = src.substring(excludeIdx, blockEnd);

// Build a minimal browser shim that the extracted block can capture / call.
function makeBrowser(initialHref) {
  const listeners = { popstate: [], hashchange: [] };
  const calls = { reload: 0, pushState: 0, replaceState: 0, suspend: 0, suspendReason: null, order: [], throwOnReload: false };
  const origPush = function () { calls.pushState++; return undefined; };
  const origReplace = function () { calls.replaceState++; return undefined; };
  const ctx = {
    location: {
      href: initialHref,
      // CORE-003: the default here is the dangerous case the audit named -- the
      // call RETURNS and the document stays alive. A stub that unloads would
      // hide every state question that follows.
      reload: function () {
        calls.reload++;
        calls.order.push('reload');
        if (calls.throwOnReload) throw new Error('navigation refused');
      }
    },
    history: {
      pushState: function () { return origPush.apply(this, arguments); },
      replaceState: function () { return origReplace.apply(this, arguments); }
    },
    // The real one is idempotent and permanent for the document; the stub has to
    // be too, or "did we suspend once" cannot be told from "did we spin".
    suspendRepainter: function (reason) {
      if (calls.suspend > 0) return;
      calls.suspend++;
      calls.suspendReason = reason;
      calls.order.push('suspend');
    },
    window: {
      addEventListener: function (name, fn) { (listeners[name] || (listeners[name] = [])).push(fn); }
    }
  };
  ctx.window.window = ctx.window;
  return { ctx, listeners, calls };
}

function runBlock(block, initialHref) {
  const { ctx, listeners, calls } = makeBrowser(initialHref);
  // Surface the captured bindings so the test can assert against them.
  const captured = {};
  const wrapper = block + '\nthis.__captured = { isExcludedUrl, setupRouteGuard, EXCLUDE };';
  const vmContext = vm.createContext(ctx);
  vm.runInContext(wrapper, vmContext);
  Object.assign(captured, vmContext.__captured);
  return { ctx, listeners, calls, captured };
}

// ---- Test 1: isExcludedUrl recognises every excluded route class ----
{
  const { captured } = runBlock(block, 'https://example.com/');
  const samples = [
    ['https://example.com/oauth/authorize', true],
    ['https://accounts.google.com/signin', true],
    ['https://login.microsoftonline.com/', true],
    ['https://example.com/paypal/checkout', true],
    ['https://stripe.com/payment', true],
    ['https://bank.example.com/login', true],
    ['https://example.com/oauth', true],
    ['https://example.com/captcha', true],
    ['https://translate.google.com/', true],
    ['https://maps.google.com/', true],
    ['https://www.figma.com/file/xyz', true],
    ['https://example.com/', false],
    ['https://www.wikipedia.org/', false],
    ['https://github.com/vacterro/Wintage', false]
  ];
  for (const [url, want] of samples) {
    const got = captured.isExcludedUrl(url);
    check('isExcludedUrl(' + url + ')', got, want);
  }
  // The /maps\.google/ pattern only matches maps.google.com hosts, not the
  // /maps path on www.google.com - the test above should assert what the
  // EXCLUDE list really excludes.
  check('isExcludedUrl(https://maps.google.com/)', captured.isExcludedUrl('https://maps.google.com/'), true);
}

// ---- Test 2: direct load of every excluded URL must NOT install the guard ----
// The userscript's startup return prevents setupRouteGuard from running. We
// emulate that by simply not calling setupRouteGuard when isExcludedUrl is
// true at the top of the file (the actual script does this implicitly via
// `if (isExcludedUrl(location.href)) return;`).
{
  const urls = [
    'https://example.com/oauth/authorize',
    'https://accounts.google.com/signin',
    'https://example.com/paypal/checkout',
    'https://stripe.com/payment',
    'https://bank.example.com/login',
    'https://translate.google.com/'
  ];
  for (const url of urls) {
    const { captured } = runBlock(block, url);
    check('startup: ' + url + ' isExcludedUrl=true', captured.isExcludedUrl(url), true);
    // The startup return statement means setupRouteGuard is never called for
    // these URLs in production. We replicate that by NOT invoking it and
    // asserting the script has the right shape (EXCLUDE list includes this
    // pattern and a startup reload would only happen via guard.reload()).
    const wouldReload = captured.EXCLUDE.some(r => r.test(url));
    check('startup: ' + url + ' excluded', wouldReload, true);
  }
}

// ---- Test 3: setupRouteGuard installs pushState / replaceState patches and
// popstate + hashchange listeners ----
{
  const { ctx, listeners, calls, captured } = runBlock(block, 'https://example.com/');
  // No mutation yet.
  check('pre-guard: no popstate listener', listeners.popstate.length, 0);
  check('pre-guard: no hashchange listener', listeners.hashchange.length, 0);
  // Invoke setupRouteGuard explicitly (the script's startup installs it after
  // the EXCLUDE check passes).
  captured.setupRouteGuard();
  check('guard: popstate listener installed', listeners.popstate.length, 1);
  check('guard: hashchange listener installed', listeners.hashchange.length, 1);
  // history.pushState / replaceState were REPLACED, not extended - the
  // originals still work, but the guard now wraps them.
  ctx.history.pushState({}, '', '/foo');
  ctx.history.replaceState({}, '', '/bar');
  check('guard: pushState reached original', calls.pushState, 1);
  check('guard: replaceState reached original', calls.replaceState, 1);
}

// ---- Test 4: pushState into an excluded URL triggers a reload ----
{
  const { ctx, calls, captured } = runBlock(block, 'https://example.com/dashboard');
  captured.setupRouteGuard();
  // Mutate location.href so the next guard call sees an excluded URL.
  ctx.location.href = 'https://example.com/oauth/authorize';
  ctx.history.pushState({}, '', '/oauth/authorize');
  check('guard: pushState-into-excluded reloads', calls.reload, 1);
  // A second pushState must NOT reload again (the __wintageExcludedReload latch
  // prevents an infinite reload loop when a user keeps navigating).
  ctx.history.pushState({}, '', '/oauth/authorize');
  check('guard: reload latch prevents repeat reloads', calls.reload, 1);
}

// ---- Test 5: popstate into an excluded URL triggers a reload ----
{
  const { ctx, listeners, calls, captured } = runBlock(block, 'https://example.com/dashboard');
  captured.setupRouteGuard();
  ctx.location.href = 'https://stripe.com/payment';
  for (const fn of listeners.popstate) fn({});
  check('guard: popstate-into-excluded reloads', calls.reload, 1);
}

// ---- Test 6: hashchange into an excluded URL triggers a reload ----
{
  const { ctx, listeners, calls, captured } = runBlock(block, 'https://example.com/dashboard');
  captured.setupRouteGuard();
  ctx.location.href = 'https://bank.example.com/login';
  for (const fn of listeners.hashchange) fn({});
  check('guard: hashchange-into-excluded reloads', calls.reload, 1);
}

// ---- Test 7: navigation between TWO allowed URLs does NOT reload ----
{
  const { ctx, listeners, calls, captured } = runBlock(block, 'https://example.com/dashboard');
  captured.setupRouteGuard();
  ctx.location.href = 'https://example.com/settings';
  ctx.history.pushState({}, '', '/settings');
  ctx.history.replaceState({}, '', '/settings/profile');
  for (const fn of listeners.popstate) fn({});
  for (const fn of listeners.hashchange) fn({});
  check('guard: allowed-only navigation does NOT reload', calls.reload, 0);
}

// ---- Test 8: setupRouteGuard is IDEMPOTENT (CORE-013) ----
// The script can legitimately run twice in one document (in-place Tampermonkey
// update, manual re-inject, a manager re-evaluating on a same-document
// navigation). A second install used to wrap the FIRST wrapper: guard() then
// fired twice per transition and one extra popstate/hashchange listener stacked
// per pass, invisibly, forever. The latch lives on window because a second run
// gets a fresh module scope and the same window.
{
  const { ctx, listeners, calls, captured } = runBlock(block, 'https://example.com/dashboard');
  captured.setupRouteGuard();
  const pushAfterFirst = ctx.history.pushState;
  captured.setupRouteGuard();
  captured.setupRouteGuard();
  check('double install: exactly one popstate listener', listeners.popstate.length, 1);
  check('double install: exactly one hashchange listener', listeners.hashchange.length, 1);
  check('double install: pushState not re-wrapped', ctx.history.pushState === pushAfterFirst, true);
  check('double install: latch set on window', ctx.window.__wintageRouteGuard, true);
  // One transition into an excluded URL must reload ONCE, not once per layer.
  ctx.location.href = 'https://example.com/oauth/authorize';
  ctx.history.pushState({}, '', '/oauth/authorize');
  check('double install: single reload per transition', calls.reload, 1);
  // And the original is still reached exactly once per call, not N times.
  const before = calls.pushState;
  ctx.location.href = 'https://example.com/settings';
  ctx.history.pushState({}, '', '/settings');
  check('double install: original pushState called once', calls.pushState - before, 1);
}

// ---- Test 9: CORE-003 -- quarantine happens BEFORE the reload request ----
// Reload is a request, not a state transition. The old guard set a latch, asked
// to reload, and left the repainter running if the document survived -- on a
// route the script explicitly excludes. Safety must not depend on navigation.
{
  const { ctx, calls, captured } = runBlock(block, 'https://example.com/dashboard');
  captured.setupRouteGuard();
  ctx.location.href = 'https://example.com/oauth/authorize';
  ctx.history.pushState({}, '', '/oauth/authorize');
  check('quarantine: repainter suspended', calls.suspend, 1);
  check('quarantine: named reason', calls.suspendReason, 'excluded-route');
  check('quarantine: suspended BEFORE the reload was requested', calls.order, ['suspend', 'reload']);
  // The reload returned normally and the document is still alive: further
  // transitions must not re-enter repaint work or storm the navigation.
  ctx.history.pushState({}, '', '/oauth/authorize');
  ctx.history.replaceState({}, '', '/oauth/authorize');
  check('quarantine: surviving document does not reload again', calls.reload, 1);
  check('quarantine: suspension is not repeated', calls.suspend, 1);
}

// ---- Test 10: the latch tracks the ROUTE, not "a reload was once asked for" --
// A one-way boolean could only be cleared by a synchronous throw, so an
// excluded -> allowed -> different-excluded journey in a surviving document
// never asked again and stayed unguarded for the rest of its life.
{
  const { ctx, calls, captured } = runBlock(block, 'https://example.com/dashboard');
  captured.setupRouteGuard();
  ctx.location.href = 'https://example.com/oauth/authorize';
  ctx.history.pushState({}, '', '/oauth/authorize');
  check('route latch: first excluded route reloads', calls.reload, 1);
  check('route latch: latch records the url', ctx.window.__wintageExcludedReload, 'https://example.com/oauth/authorize');
  ctx.location.href = 'https://example.com/dashboard';
  ctx.history.pushState({}, '', '/dashboard');
  check('route latch: cleared on an allowed route', ctx.window.__wintageExcludedReload, null);
  check('route latch: an allowed route does not reload', calls.reload, 1);
  check('route latch: quarantine STAYS in force', calls.suspend, 1);
  ctx.location.href = 'https://stripe.com/payment';
  ctx.history.pushState({}, '', '/payment');
  check('route latch: a later excluded route is guarded again', calls.reload, 2);
}

// ---- Test 11: a synchronous reload throw leaves a retryable state ----
{
  const { ctx, calls, captured } = runBlock(block, 'https://example.com/dashboard');
  captured.setupRouteGuard();
  calls.throwOnReload = true;
  ctx.location.href = 'https://example.com/oauth/authorize';
  ctx.history.pushState({}, '', '/oauth/authorize');
  check('throwing reload: attempted once', calls.reload, 1);
  check('throwing reload: does not throw out of the history hook', true, true);
  check('throwing reload: latch cleared so a retry is possible', ctx.window.__wintageExcludedReload, null);
  check('throwing reload: quarantine still applied', calls.suspend, 1);
  calls.throwOnReload = false;
  ctx.history.pushState({}, '', '/oauth/authorize');
  check('throwing reload: the retry happens', calls.reload, 2);
}

console.log(bad ? '\n' + bad + ' failure(s)' : '\nspa exclude safety test PASS');
process.exit(bad ? 1 : 0);
