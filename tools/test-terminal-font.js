#!/usr/bin/env node
// The console font is named in TWO places -- $CONSOLE_FONT in desktop/install.ps1
// for conhost's registry keys, and TERMINAL_FONT in tools/install-terminal.js for
// Windows Terminal's settings.json. They configure the same machine, so a machine
// with both installed would render its two terminals in different faces the moment
// one of the constants is changed alone. This repo has already been bitten twice by
// a value kept in two hands (the -Target dispatch list, T-070; the version pair,
// checkVersion) and the answer both times was a gate, not a reminder.
//
// The second check is the one with the history behind it: Verdana is proportional
// (Verdana_m1 measures post.isFixedPitch = 0 with 323 distinct advance widths in
// hmtx), and a terminal lays glyphs on a fixed cell grid, so forcing it makes
// letters collide -- shipped once, reverted in v1.23.3, and asked for again since.
// If it is ever set here deliberately, this gate is the place that has to be
// changed too, which makes the decision explicit instead of accidental.
//
// Usage: node tools/test-terminal-font.js   (exit 0 = pass, 1 = fail)

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
let failures = 0;
const check = (ok, msg) => {
  console.log((ok ? 'PASS: ' : 'FAIL: ') + msg);
  if (!ok) failures++;
};

const ps = fs.readFileSync(path.join(ROOT, 'desktop', 'install.ps1'), 'utf8');
const js = fs.readFileSync(path.join(ROOT, 'tools', 'install-terminal.js'), 'utf8');

const psFont = (/\$CONSOLE_FONT\s*=\s*'([^']+)'/.exec(ps) || [])[1];
const jsFont = (/const TERMINAL_FONT\s*=\s*'([^']+)'/.exec(js) || [])[1];

check(!!psFont, 'install.ps1 declares $CONSOLE_FONT' + (psFont ? ' (' + psFont + ')' : ''));
check(!!jsFont, 'install-terminal.js declares TERMINAL_FONT' + (jsFont ? ' (' + jsFont + ')' : ''));
check(psFont === jsFont, 'conhost and Windows Terminal agree on the face (' + psFont + ' vs ' + jsFont + ')');
check(!/verdana/i.test(psFont || '') && !/verdana/i.test(jsFont || ''),
  'the console face is not Verdana -- proportional glyphs collide on a fixed cell grid');

if (failures) { console.error('\n' + failures + ' terminal-font check(s) failed'); process.exit(1); }
console.log('terminal font test PASS');
