#!/usr/bin/env node
// Every string the shim hands to executeJavaScript must be valid JavaScript, and
// `node --check` on the shim CANNOT SEE THAT: to the parser a template literal is
// just a string, so a broken payload is a syntactically perfect file that fails at
// runtime, in a renderer, with the error going nowhere a user would look. This is
// the same blind spot tools/check-css.js exists for on the CSS side.
//
// Each is interpolated exactly the way the shim interpolates it, then parsed.
//
// The shim once carried five of these payloads; the Claude probe/root-paint/
// contrast trio was reverted (6e18ec1, "revert inherit-all, use targeted floating
// surface selectors only") in favour of a single stylesheet append. "Targeted
// selectors" is precisely what then missed Claude's popovers twice, which is why
// REPAINTER_FIX joined SCROLL_FIX and WCO_FIX: three executed JS payloads.
// CLAUDE_FOREGROUND_CSS is a stylesheet the
// shim hands to insertCSS, not executeJavaScript, so it is checked as CSS: the
// declaration must exist and be referenced, and its literal must balance braces.
//
// Usage: node tools/test-shim-payloads.js   (exit 0 = pass, 1 = fail)

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const src = fs.readFileSync(path.join(__dirname, '..', 'desktop', 'targets', 'electron', 'shim.cjs'), 'utf8');

let failures = 0;
const check = (ok, msg) => { console.log((ok ? 'PASS: ' : 'FAIL: ') + msg); if (!ok) failures++; };

// The payloads all close on a line of their own, which is what makes them findable
// without a regex that would need escaping for every backtick inside them.
function literalAfter(decl) {
  const i = src.indexOf(decl);
  if (i < 0) throw new Error('declaration not found: ' + decl);
  const start = i + decl.length;
  const end = src.indexOf('\n})()`', start);
  if (end < 0) throw new Error('no closing backtick for ' + decl);
  return src.slice(start, end + '\n})()'.length);
}

// Interpolated by the shim at load time from the palette it read out of the CSS.
// Every token a payload can reference has to be stubbed here, or this gate reports
// a payload broken when only the stub was -- and a missing one is itself worth
// catching, since the shim would interpolate `undefined` into live JS.
const T_BACKGROUND = '#1A1810';
const T_TEXT = '#D4C89A';
const T_SURFACE = '#332E22';

for (const name of ['SCROLL_FIX', 'WCO_FIX', 'SCROLL_INTENT_FIX', 'AD_BLOCK']) {
  try {
    const produced = eval('`' + literalAfter('const ' + name + ' = `') + '`');
    new vm.Script(produced);
    check(true, name + ' is valid JS (' + produced.split('\n').length + ' lines)');
  } catch (e) {
    check(false, name + ': ' + e.message);
  }
}

// A payload that parses but is never handed to a renderer is dead code that reads
// like a shipped fix -- exactly how the theme spent two reports believing floating
// surfaces were covered. Each executed payload must be wired into the injector.
for (const name of ['SCROLL_FIX', 'WCO_FIX', 'REPAINTER_FIX', 'SCROLL_INTENT_FIX', 'AD_BLOCK']) {
  check(src.indexOf('executeJavaScript(' + name) > 0, name + ' is wired into the injector');
}



// PROGRESS_FIX was withdrawn after counting what it actually hit on a live
// window: 234 elements by shape, 111 by inline width. Neither is a gauge
// detector -- the shim carries the full reasoning. This gate keeps it withdrawn,
// because the failure was not cosmetic: it repainted controls as solid blocks.
// Reinstating it needs a signal read off a real gauge, not another screenshot.
check(src.indexOf('executeJavaScript(PROGRESS_FIX') < 0,
  'PROGRESS_FIX stays out of the injector until a gauge is measured live');

// AD_BLOCK shipped broken and silent: its regexes were written with single
// backslashes inside a template literal, so \/ collapsed to / and the emitted
// line read `const AD_PATH = //api/ad/(...)` -- a comment. The payload died at
// parse on every launch and the only trace was one line in a status file. Parsing
// it here is what makes that impossible to repeat, but the regex must also still
// MEAN what it says after interpolation.
// Checked on the INTERPOLATED text, not the source. Counting backslashes in the
// source is the same mistake one level up -- what matters is the regex the
// renderer ends up with, so build it and look at that.
const adProduced = eval('`' + literalAfter('const AD_BLOCK = `') + '`');
// Anchored, because the explanatory comment above the declaration quotes the
// broken form verbatim and an unanchored match reads the comment instead.
const adPathLine = adProduced.split('\n').filter(l => /^\s*const AD_PATH =/.test(l))[0] || '';
check(adPathLine.includes('/\\/api\\/ad\\/'),
  'AD_BLOCK emits a real regex, not a comment (its backslashes survive the template literal)');
check(/\/api\/ad\/(slot|impression|click)\b/.test('/api/ad/slot'),
  'the emitted ad-path pattern still matches a real ad request');


// SCROLL_INTENT_FIX changes an application's BEHAVIOUR, which is further than a
// theme normally goes, so its narrowness is the thing worth pinning. It may only
// drop a scroll that is (a) aimed at the bottom, (b) on a scroller the reader has
// deliberately left, and (c) not backed by a user gesture. Lose the gesture check
// and it starts eating the reader's own "jump to latest" click; lose the distance
// checks and it fights the app on every pin.
const intentSrc = literalAfter('const SCROLL_INTENT_FIX = `');
for (const [needle, what] of [
  ['ResizeObserver', 'that a re-pin arriving from an observer callback is the app, not the reader'],
  ['userActivation', 'that a real user gesture is always allowed through'],
  ['AT_BOTTOM', 'that only bottom-aimed scrolls are candidates'],
  ['AWAY_FLAG', 'that the reader must have deliberately scrolled away'],
  ['scrollHeight - el.clientHeight', 'that the scroller is measured, not assumed']
]) {
  check(intentSrc.indexOf(needle) > 0, 'SCROLL_INTENT_FIX still requires ' + what);
}
check(/return false;/.test(intentSrc) && intentSrc.indexOf('catch (e) { return true; }') > 0,
  'SCROLL_INTENT_FIX fails open -- an unmeasurable case allows the scroll');

// CLAUDE_FOREGROUND_CSS is a stylesheet appended via insertCSS on Claude's
// renderer, never executed. It must exist, be referenced by the injector, and be
// brace-balanced enough to survive the browser's parser.
const cssDecl = 'const CLAUDE_FOREGROUND_CSS = `';
const cssI = src.indexOf(cssDecl);
check(cssI >= 0, 'CLAUDE_FOREGROUND_CSS declaration present');
check(src.indexOf('css + CLAUDE_FOREGROUND_CSS') > 0, 'CLAUDE_FOREGROUND_CSS is referenced by the injector');
if (cssI >= 0) {
  const cssStart = cssI + cssDecl.length;
  const cssEnd = src.indexOf('`', cssStart);
  const cssBody = src.slice(cssStart, cssEnd);
  let depth = 0;
  for (const ch of cssBody) {
    if (ch === '{') depth++;
    else if (ch === '}') depth--;
  }
  check(depth === 0 && /^\s*body\s+:where/.test(cssBody), 'CLAUDE_FOREGROUND_CSS is a balanced stylesheet with the :where selector (' + cssBody.split('\n').length + ' lines)');
}

if (failures) { console.error('\n' + failures + ' shim payload check(s) failed'); process.exit(1); }
console.log('shim payload test PASS');
