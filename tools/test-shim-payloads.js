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
// FLOAT_FIX joined SCROLL_FIX and WCO_FIX: three executed JS payloads.
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

for (const name of ['SCROLL_FIX', 'WCO_FIX', 'FLOAT_FIX', 'PROGRESS_FIX']) {
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
for (const name of ['SCROLL_FIX', 'WCO_FIX', 'FLOAT_FIX', 'PROGRESS_FIX']) {
  check(src.indexOf('executeJavaScript(' + name) > 0, name + ' is wired into the injector');
}

// FLOAT_FIX exists because the CSS re-solidify list is name-based and missed the
// same app twice. Its whole value is that it decides by MEASUREMENT, so this gate
// pins the four measurements down: delete any one of them and the block degrades
// back into something that only looks like it covers popovers. Names are checked
// for too -- a "fix" that reintroduces role="menu" or [class*="popup"] here has
// quietly become the list it replaced.
const floatSrc = literalAfter('const FLOAT_FIX = `');
for (const [needle, what] of [
  ['cs.position', 'out of flow (position)'],
  ['getBoundingClientRect', 'big enough to read (measured rect)'],
  ['elementsFromPoint', 'actually floating (hit test at its own centre)'],
  ['.contains(el)', 'that the hit test ignores its own ancestors']
]) {
  check(floatSrc.indexOf(needle) > 0, 'FLOAT_FIX still tests ' + what);
}
check(!/role\s*=\s*"?menu|class\*=|data-radix|floating-ui-portal/i.test(floatSrc),
  'FLOAT_FIX has not regressed into matching component names');

// PROGRESS_FIX restores the one thing a usage bar is drawn for -- the proportion
// between fill and track -- which surface flattening erases by painting both the
// same colour. It finds the fill by the only thing an app cannot stop doing:
// computing a live width inline. Pin that, and pin that it stays name-free.
const barSrc = literalAfter('const PROGRESS_FIX = `');
for (const [needle, what] of [
  ['width:', 'a fill sized by an inline percentage width'],
  ['scaleX', 'a fill sized by a scaleX transform'],
  ['matrix', 'a fill whose scaleX arrives as a computed matrix'],
  ['getBoundingClientRect', 'that a track is short and wide (measured)']
]) {
  check(barSrc.indexOf(needle) > 0, 'PROGRESS_FIX still detects ' + what);
}
check(!/role\s*=\s*"?progressbar|class\*=|meter/i.test(barSrc),
  'PROGRESS_FIX has not regressed into matching component names');

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
