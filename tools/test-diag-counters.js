#!/usr/bin/env node
// CORE-015: the deliberately-suppressed throws in the hover surgery and the
// shadow-root pierce must be COUNTED, not hidden. The visible symptom of a
// silent swallow there is "the site's hover highlight is still there", which
// looks exactly like a missing feature and leaves nothing to diagnose from.
//
// This runs the REAL source slice -- the DIAG block plus the bounded hover-rule
// cursor (drainStyleRules) -- against rule containers engineered to throw, and
// asserts the counters move and window.__wintageDiag() reports them. It also
// proves the gate can fail: a control run with a non-throwing container must
// leave every counter at zero, so a counter that is always non-zero cannot pass
// as working.
//
// R013: this used to drive the root-level stripHoverSheets() helper. That helper
// is gone from production (the light lane called it once per root, which is
// unbounded by construction); the gate now drives the scheduler's own
// drainStyleRules task, i.e. the primitive that actually ships.

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

// ---- slice 2: the hover surgery (HOVER_PAINT .. end of drainStyleRules) ----
// The bounded traversal is the ONLY path to hover rules now, so this slice ends
// at the last brace of drainStyleRules.
const hoverFrom = src.indexOf('  const HOVER_PAINT = ');
const drainIdx = src.indexOf('  function drainStyleRules(task, ruleBudget) {');
if (hoverFrom < 0 || drainIdx < 0) {
  console.error('FAIL: could not locate the hover surgery'); process.exit(1);
}
let depth = 0, hoverEnd = -1;
for (let i = drainIdx; i < src.length; i++) {
  if (src[i] === '{') depth++;
  else if (src[i] === '}') { depth--; if (depth === 0) { hoverEnd = i + 1; break; } }
}
if (hoverEnd < 0) { console.error('FAIL: drainStyleRules closing brace not found'); process.exit(1); }
const hoverSlice = src.slice(hoverFrom, hoverEnd);

// The unbounded root-level helper must not exist any more: if it comes back, the
// gate fails on the source rather than re-testing a dead function.
if (/function\s+stripHoverSheets\s*\(/.test(src)) {
  console.error('FAIL: production still defines stripHoverSheets (R013 removed it)'); process.exit(1);
}

function makeContainer(kind) {
  // A rule whose selectorText getter throws is the realistic shape: an engine
  // handing back a half-built rule, or a rule from an unresolved @import.
  const throwingRule = { get selectorText() { throw new Error('rule not ready'); }, style: null, cssRules: null };
  const plainRule = { selectorText: 'a:hover', style: { length: 0, removeProperty() { } }, cssRules: null };
  if (kind === 'throwOnRule') {
    return { length: 1, 0: throwingRule };
  }
  if (kind === 'clean') {
    return { length: 1, 0: plainRule };
  }
  if (kind === 'appendThrow') {
    // The other suppression class: the rule SLOT itself is unreadable, which is
    // what the append fast path hits when a sheet mutates under the cursor.
    return { length: 1, get 0() { throw new Error('rule not ready'); } };
  }
  throw new Error('unknown container kind ' + kind);
}

function run(containerKind) {
  const ctx = {
    console,
    W95_VERSION: 'test',
    THEME_ID: 'testpal',
    CSS_ONLY_MODE: false,
    CSSStyleSheet: undefined,
    window: {},
    // R013: the hover-surgery slice starts at HOVER_PAINT, which sits after the
    // declared style budgets. The budget values themselves are not under test
    // here (tools/test-repainter-budget.js owns them); the traversal just needs
    // them defined.
    STYLE_SHEET_BUDGET: 32,
    STYLE_RULE_BUDGET: 500,
    STYLE_ROOT_BUDGET: 16
  };
  ctx.window.window = ctx.window;
  vm.createContext(ctx);
  vm.runInContext(
    '(function(){\n' + diagSlice + '\n' + hoverSlice +
    '\nthis.__drain = drainStyleRules; this.__diagFn = window.__wintageDiag;\n}).call(this)',
    ctx
  );
  const container = makeContainer(containerKind);
  ctx.__drain({
    sheet: { __wintageGen: 0 },
    gen: 0,
    count: container.length,
    mode: containerKind === 'appendThrow' ? 'append' : 'full',
    stack: [{ container, index: 0, length: container.length }]
  }, 8);
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

// ---- Test 1b: the unreadable rule SLOT is counted under the append class ----
{
  const { diag } = run('appendThrow');
  check('unreadable rule slot increments hoverAppendThrows', diag.suppressed.hoverAppendThrows >= 1, true);
  check('the append error is retained with its kind',
    diag.firstError ? diag.firstError.kind : null, 'hoverAppendThrows');
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
