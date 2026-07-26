#!/usr/bin/env node
// Guards the two CSS template literals in wintage.user.js against errors that
// `node --check` cannot see, because to JavaScript a template literal is just a
// string and any garbage inside it is valid.
//
// Written after a real incident: an explanatory paragraph got pasted AFTER a
// comment's closing `*/`, leaving loose prose and a second, stray `*/` sitting in
// the middle of GLOBAL_CSS. `node --check` passed, the file loaded, and the
// browser's CSS parser silently discarded rules while recovering — the whole type
// ladder stopped applying and every heading and paragraph quietly reverted to the
// site's own sizes. Nothing failed loudly; it was only caught by measuring
// computed font sizes on a live page. This check turns that into an instant FAIL.
//
// Usage: node tools/check-css.js   (exit 0 = pass, 1 = fail)

const fs = require('fs');
const path = require('path');

const file = path.join(__dirname, '..', 'wintage.user.js');
const src = fs.readFileSync(file, 'utf8');

let failures = 0;

function fail(msg) { console.error('FAIL: ' + msg); failures++; }

for (const name of ['GLOBAL_CSS', 'SHADOW_CSS']) {
  const decl = 'const ' + name + ' = `';
  const i = src.indexOf(decl);
  if (i < 0) { fail(name + ' declaration not found'); continue; }
  const start = i + decl.length;
  // The closing backtick sits on its own line, optionally indented (GLOBAL_CSS
  // closes at column 0, SHADOW_CSS is indented two spaces).
  const closer = /\n[ \t]*`;/.exec(src.slice(start));
  if (!closer) { fail(name + ' has no closing backtick'); continue; }
  const css = src.slice(start, start + closer.index);

  // Comment nesting: CSS comments do not nest, so a `/*` while already inside a
  // comment is suspicious, and a `*/` while outside one is always an error.
  let depth = 0, stray = 0, nested = 0;
  for (let k = 0; k < css.length;) {
    if (css.startsWith('/*', k)) { if (depth > 0) nested++; depth++; k += 2; continue; }
    if (css.startsWith('*/', k)) { if (depth === 0) stray++; else depth--; k += 2; continue; }
    k++;
  }
  if (stray) fail(name + ': ' + stray + ' stray `*/` closing no comment');
  if (depth) fail(name + ': ' + depth + ' unclosed `/*`');
  if (nested) fail(name + ': ' + nested + ' nested `/*` (CSS comments do not nest)');

  // Every hex colour must trace to the UI.md palette (iron law 5). `#name` ID
  // selectors are excluded by requiring a full 3- or 6-digit hex not followed by
  // an identifier character.
  const PALETTE = new Set(['#1a0f05', '#1e1408', '#2a1c0a', '#362812', '#3a2a15',
    '#0e0803', '#c0a060', '#4a3820', '#d4b87a', '#b09558', '#7a6838',
    '#008080', '#004c4c', '#4a7a20', '#7a7a20', '#7a2020', '#0f0a04']);
  // Strip comments first: they legitimately mention retired colours by name.
  const bare = css.replace(/\/\*[\s\S]*?\*\//g, '');
  const hexes = bare.match(/#[0-9A-Fa-f]{6}\b|#[0-9A-Fa-f]{3}\b(?![0-9A-Za-z_-])/g) || [];
  for (const h of new Set(hexes)) {
    if (!PALETTE.has(h.toLowerCase())) fail(name + ': off-palette colour ' + h);
  }

  // Braces must balance, or a dropped rule silently swallows the next ones.
  const opens = (bare.match(/{/g) || []).length, closes = (bare.match(/}/g) || []).length;
  if (opens !== closes) fail(name + ': ' + opens + ' `{` vs ' + closes + ' `}`');

  if (!failures) console.log(name + ': PASS (' + css.split('\n').length + ' lines)');
}

if (failures) { console.error('\n' + failures + ' failure(s)'); process.exit(1); }
console.log('CSS check PASS');
