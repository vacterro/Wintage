#!/usr/bin/env node
// T-283 / SRC-026 -- the "two hands" guard, generalized.
//
// The pre-T-283 defect class this file pinned: a console face named in TWO
// places (install.ps1's $CONSOLE_FONT and install-terminal.js's TERMINAL_FONT)
// could be changed in one and not the other, so a machine with both installed
// rendered its two terminals in different faces.
//
// The fix removed the second hard-coded constant: the canonical preference
// (tools/terminal-font-preference.js) is the SINGLE source, and its DEFAULT is
// the face install.ps1 still names as its fallback. This gate now proves:
//   1. install.ps1 still declares the legacy $CONSOLE_FONT fallback;
//   2. install-terminal.js no longer hard-codes a face (it reads the preference);
//   3. the preference DEFAULT family equals that $CONSOLE_FONT fallback, so the
//      documented default and the runtime default cannot drift;
//   4. the catalog carries the same default slug/family;
//   5. no console face is Verdana -- proportional glyphs collide on a fixed cell.
//
// Usage: node tools/test-terminal-font.js   (exit 0 = pass, 1 = fail)

const fs = require('fs');
const path = require('path');
const { DEFAULT_PREFERENCE } = require('./terminal-font-preference');
const { readCatalog } = require('./terminal-font-catalog');

const ROOT = path.join(__dirname, '..');
let failures = 0;
const check = (ok, msg) => {
  console.log((ok ? 'PASS: ' : 'FAIL: ') + msg);
  if (!ok) failures++;
};

const ps = fs.readFileSync(path.join(ROOT, 'desktop', 'install.ps1'), 'utf8');
const js = fs.readFileSync(path.join(ROOT, 'tools', 'install-terminal.js'), 'utf8');

const psFont = (/\$CONSOLE_FONT\s*=\s*'([^']+)'/.exec(ps) || [])[1];
check(!!psFont, 'install.ps1 declares the $CONSOLE_FONT default fallback' + (psFont ? ` (${psFont})` : ''));
check(!/const TERMINAL_FONT\s*=/.test(js), 'install-terminal.js no longer hard-codes a second face (reads the preference)');
check(/readPreference|preference/i.test(js), 'install-terminal.js resolves typography from the canonical preference');

check(DEFAULT_PREFERENCE.family === psFont,
  `preference default family equals the $CONSOLE_FONT fallback (${DEFAULT_PREFERENCE.family} vs ${psFont})`);

const catalog = readCatalog();
const defaultEntry = catalog.fonts.find((f) => f.slug === DEFAULT_PREFERENCE.fontSlug);
check(!!defaultEntry, `catalog carries the preference default slug (${DEFAULT_PREFERENCE.fontSlug})`);
check(!!defaultEntry && defaultEntry.family === DEFAULT_PREFERENCE.family,
  `catalog default family matches the preference default (${defaultEntry && defaultEntry.family})`);

check(!/verdana/i.test(psFont || '') && !/verdana/i.test(DEFAULT_PREFERENCE.family || ''),
  'the console face is not Verdana -- proportional glyphs collide on a fixed cell grid');

if (failures) { console.error(`\n${failures} terminal-font check(s) failed`); process.exit(1); }
console.log('terminal font test PASS');
