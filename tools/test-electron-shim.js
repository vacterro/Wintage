#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

let shim = fs.readFileSync(path.join(__dirname, '..', 'desktop', 'targets', 'electron', 'shim.cjs'), 'utf8');
if (process.argv.includes('--deliberate-red')) {
  shim = shim.replace(':not(svg):not(svg *)', '');
}
let failures = 0;

function check(condition, message) {
  if (condition) console.log('PASS: ' + message);
  else { console.error('FAIL: ' + message); failures += 1; }
}

const block = /const CLAUDE_FOREGROUND_CSS = `([\s\S]*?)`;/u.exec(shim);
check(Boolean(block), 'Claude foreground repair exists');
if (block) {
  check(block[1].includes('color: inherit !important'), 'Claude wrappers inherit palette foreground');
  check(block[1].includes('-webkit-text-fill-color: currentColor !important'), 'WebKit text fill follows computed colour');
  check(block[1].includes('button):not(svg):not(svg *)'), 'SVG exclusions stay in the text-bearing selector compound');
  check(!/\)\s+:not/u.test(block[1]), 'no exclusion is split into a descendant selector');
  check(block[1].includes(':not([aria-hidden="true"])'), 'decorative hidden glyphs are excluded');
  check(!/#[0-9a-f]{3,8}/i.test(block[1]), 'repair adds no palette-bypassing colour literal');
}

check(shim.includes('claude\\.ai\\/epitaxy'), 'repair matches Claude Epitaxy view');
check(shim.includes('/\\.vite\\/renderer\\/main_window\\/index\\.html'), 'repair matches Claude shell');
check(shim.includes('const payload = CLAUDE_VIEW.test(url) ? css + CLAUDE_FOREGROUND_CSS : css;'), 'non-Claude apps keep shared CSS unchanged');
check(shim.includes("wc.insertCSS(payload, { cssOrigin: 'author' })"), 'scoped payload reaches insertCSS');

if (failures) process.exit(1);
console.log('Electron shim regression checks passed.');
