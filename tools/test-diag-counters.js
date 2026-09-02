#!/usr/bin/env node
// CORE-015: the deliberately-suppressed throws in the hover surgery and the
// shadow-root pierce must be COUNTED, not hidden. The visible symptom of a
// silent swallow there is "the site's hover highlight is still there", which
// looks exactly like a missing feature and leaves nothing to diagnose from.
//
// This runs the REAL source slice -- the DIAG block plus walkRules/
// stripHoverSheets -- against sheets engineered to throw, and asserts the
// counters move and window.__wintageDiag() reports them. It also proves the
// gate can fail: a control run with a non-throwing sheet must leave every
// counter at zero, so a counter that is always non-zero cannot pass as working.

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.join(__dirname, '..');
const src = fs.readFileSync(path.join(ROOT, 'wintage.user.js'), 'utf8');

let bad = 0;
const check = (label, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  console.log((ok ? 'PASS: ' : 'FAIL: ') + label + (ok ? '' : '  got=' + JSON.stringify(got) + ' want=' + JSON.stringify(want)));
  if (!ok) bad++;
};

// ---- slice 1: the DIAG block (declaration + reporter) ----
const diagFrom = src.indexOf('  const DIAG = {');
const diagTo = src.indexOf('  // ─── STRUCTURAL BEVEL CONSTANTS');
if (diagFrom < 0 || diagTo < 0 || diagTo < diagFrom) {
  console.error('FAIL: could not slice the DIAG block'); process.exit(1);
}
const diagSlice = src.slice(diagFrom, diagTo);

// ---- slice 2: the hover surgery (HOVER_PAINT .. end of stripHoverSheets) ----
const hoverFrom = src.indexOf('  const HOVER_PAINT = ');
const stripIdx = src.indexOf('  function stripHoverSheets(root) {');
if (hoverFrom < 0 || stripIdx < 0) {
  console.error('FAIL: could not locate the hover surgery'); process.exit(1);
}
let depth = 0, hoverEnd = -1;
for (let i = stripIdx; i < src.length; i++) {
  if (src[i] === '{') depth++;
  else if (src[i] === '}') { depth--; if (depth === 0) { hoverEnd = i + 1; break; } }
}
if (hoverEnd < 0) { console.error('FAIL: stripHoverSheets closing brace not found'); process.exit(1); }
const hoverSlice = src.slice(hoverFrom, hoverEnd);

function makeSheet(kind) {
  // A rule whose selectorText getter throws is the realistic shape: an engine
  // handing back a half-built rule, or a rule from an unresolved @import.
  const throwingRule = { get selectorText() { throw new Error('rule not ready'); }, style: null, cssRules: null };
  const plainRule = { selectorText: 'a:hover', style: { length: 0, removeProperty() { } }, cssRules: null };
  if (kind === 'throwOnRule') {
    return { cssRules: { length: 1, 0: throwingRule }, ownerNode: null };
  }
  if (kind === 'clean') {
    return { cssRules: { length: 1, 0: plainRule }, ownerNode: null };
  }
  throw new Error('unknown sheet kind ' + kind);
}

function run(sheetKind) {
  const styleEls = [];
  const ctx = {
    console,
    W95_VERSION: 'test',
    THEME_ID: 'testpal',
    CSS_ONLY_MODE: false,
    CSSStyleSheet: undefined,
    window: {}
  };
  ctx.window.window = ctx.window;
  const sheet = makeSheet(sheetKind);
  ctx.__root = {
    styleSheets: { length: 1, 0: sheet },
    adoptedStyleSheets: null,
    querySelectorAll: () => styleEls
  };
  vm.createContext(ctx);
  vm.runInContext(
    '(function(){\n' + diagSlice + '\n' + hoverSlice +
    '\nthis.__strip = stripHoverSheets; this.__diagFn = window.__wintageDiag;\n}).call(this)',
    ctx
  );
  ctx.__strip(ctx.__root);
  return { diag: ctx.__diagFn(), ctx };
}

// ---- Test 1: a throwing rule is COUNTED, not silently dropped ----
{
  const { diag } = run('throwOnRule');
  check('throwing rule increments hoverWalkThrows', diag.suppressed.hoverWalkThrows >= 1, true);
  check('the first error is retained', diag.firstError !== null && typeof diag.firstError === 'object', true);
  // Guarded: a silent-swallow regression leaves firstError null, and reading
  // .kind off null would abort the run with a stack instead of a FAIL line --
  // a gate that crashes reports nothing about the other cases.
  check('the retained error names its kind', diag.firstError ? diag.firstError.kind : null, 'hoverWalkThrows');
  check('the retained error carries the message', diag.firstError ? diag.firstError.message : null, 'rule not ready');
}

// ---- Test 2: control -- a clean sheet must leave every counter at zero ----
// A counter that is always non-zero would pass Test 1 while reporting nothing.
{
  const { diag } = run('clean');
  check('control: clean sheet leaves hoverWalkThrows at 0', diag.suppressed.hoverWalkThrows, 0);
  check('control: clean sheet leaves hoverAppendThrows at 0', diag.suppressed.hoverAppendThrows, 0);
  check('control: clean sheet leaves sheetGenThrows at 0', diag.suppressed.sheetGenThrows, 0);
  check('control: clean sheet leaves shadowPierceThrows at 0', diag.suppressed.shadowPierceThrows, 0);
  check('control: no first error', diag.firstError, null);
}

// ---- Test 3: the reporter is installed on window and reports identity ----
{
  const { diag } = run('clean');
  check('reporter returns the version', diag.version, 'test');
  check('reporter returns the theme', diag.theme, 'testpal');
  check('reporter returns cssOnlyMode', diag.cssOnlyMode, false);
  check('reporter exposes all four counters',
    Object.keys(diag.suppressed).sort(),
    ['hoverAppendThrows', 'hoverWalkThrows', 'sheetGenThrows', 'shadowPierceThrows'].sort());
}

// ---- Test 4: every catch that suppresses one of these classes reports it ----
// Source-level, because a swallow re-introduced by a later edit is exactly the
// regression this ticket fixed and it is invisible at runtime until it matters.
{
  const wantReported = [
    ["shadow pierce", /catch \(e\) \{ noteSuppressed\('shadowPierceThrows', e\); \}/],
    ["style-element generation bump", /catch \(e\) \{ noteSuppressed\('sheetGenThrows', e\); \}/],
    ["hover rule walk", /catch \(e\) \{ noteSuppressed\('hoverWalkThrows', e\); \}/],
    ["appended hover rules", /catch \(e\) \{ noteSuppressed\('hoverAppendThrows', e\); \}/]
  ];
  for (const [what, re] of wantReported) {
    check('source reports suppressed throws: ' + what, re.test(src), true);
  }
  check('source exposes window.__wintageDiag', /window\.__wintageDiag = function \(\)/.test(src), true);
}

console.log(bad ? '\n' + bad + ' failure(s)' : '\ndiagnostic counters test PASS');
process.exit(bad ? 1 : 0);
