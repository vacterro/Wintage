#!/usr/bin/env node
// T-065: every chart family the theme claims to support must carry a
// VISIBILITY guard, and the guard must be able to fail.
//
// Why this is a gate and not a comment. T-065 ("YouTube Studio analytics bars
// disappear under the theme") sat BLOCKED for months because reproducing it
// needs an authenticated Studio session. The bar family turned out to be guarded
// already -- added in v1.35.0, two months AFTER the report -- while the sibling
// families the same Reach view renders (line, area, stacked, sparkline) were
// not, and the global surface wipe is exactly the rule class that hides a data
// mark. So the class of failure was still open for everything the bar guard did
// not name, and no live session was needed to see that from the source.
//
// The contract pinned here:
//   1. every family listed in CHART_FAMILIES appears in the userscript;
//   2. every family appears in a rule that also sets `visibility: visible`
//      and `opacity: 1` -- a family named only in a selector, with no
//      visibility guard, is the exact shape of the open defect;
//   3. RED CONTROL: the checker reports the miss when a family is named but
//      unguarded, so a future rename cannot quietly reopen it.
const fs = require('fs');
const path = require('path');

const src = fs.readFileSync(path.join(__dirname, '..', 'wintage.user.js'), 'utf8');

// The chart families one Studio analytics view renders. Bar is here because its
// guard predates this gate; the rest are here because the report named the
// symptom, not the component.
const CHART_FAMILIES = [
  'ytcp-bar-chart',
  'ytcp-line-chart',
  'ytcp-area-chart',
  'ytcp-stacked-bar-chart',
  'ytcp-sparkline'
];

// A family counts as guarded only where a visibility guard follows it.
//
// NOT by parsing rules with a brace regex: GLOBAL_CSS is a template literal,
// so every `${T.link}` is a brace pair, and a `([^{}]*)\}` split terminates on
// the interpolation instead of on the rule. tools/check-css.js documents the
// same trap for the same file. So this walks forward from each occurrence
// instead -- which is also how a reader checks a rule, and it cannot be fooled
// by a declaration whose value contains a brace.
const GUARD_WINDOW = 700;

function guardedAt(index) {
  // Collapse `${T.link}` interpolations first. They are brace pairs inside a
  // template literal, so an un-collapsed window ends on the INTERPOLATION's `}`
  // and never reaches the declarations -- which is exactly the trap
  // tools/check-css.js documents for this same file.
  const window = src
    .slice(index, index + GUARD_WINDOW)
    .replace(/\$\{[^}]*\}/g, ' __WINTAGE_INTERPOLATION__ ');
  const ruleEnd = window.indexOf('}');
  const body = ruleEnd >= 0 ? window.slice(0, ruleEnd) : window;
  return /visibility\s*:\s*visible/i.test(body) && /opacity\s*:\s*1\b/i.test(body);
}

let bad = 0;
const report = [];
for (const family of CHART_FAMILIES) {
  const occurrences = [];
  for (let at = src.indexOf(family); at >= 0; at = src.indexOf(family, at + 1)) {
    occurrences.push(at);
  }
  if (!occurrences.length) {
    bad++;
    report.push(`FAIL  ${family}: absent from the userscript`);
  } else if (!occurrences.some(guardedAt)) {
    bad++;
    report.push(`FAIL  ${family}: named in ${occurrences.length} place(s), none carrying a visibility guard`);
  } else {
    report.push(`PASS  ${family}: present and guarded`);
  }
}

// RED CONTROL: a family that is present but never guarded must be reported, or
// this gate cannot fail and proves nothing.
{
  const synthetic = 'ytcp-synthetic-uncharted';
  if (src.includes(synthetic) || guardedAt(src.indexOf(synthetic))) {
    bad++;
    report.push('FAIL  RED: an undeclared family was reported as guarded -- the checker cannot fail');
  } else {
    report.push('PASS  RED: an undeclared family is correctly reported as unguarded');
  }
}

console.log(report.join('\n'));
if (bad) {
  console.error('\nchart guard coverage: ' + bad + ' problem(s)');
  process.exit(1);
}
console.log('\nchart guard coverage: PASS (' + CHART_FAMILIES.length + ' families)');
