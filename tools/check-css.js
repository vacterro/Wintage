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

  // Every hex colour must trace to the active theme's palette (UI.md iron law 5).
  // Before 1.5.0 that was checked as membership in one frozen 18-colour set, which
  // stops working the moment a second palette exists: the same literal is on-palette
  // for one theme and off-palette for another, and the set has no way to know which
  // theme is live at that point in the file.
  //
  // The stronger rule, and the one that actually scales: this script reads the file
  // as TEXT, so a `${T.background}` interpolation is not a hex to it. Any hex that
  // DOES appear inside a CSS body is therefore hardcoded by definition — pinned to
  // one palette and immune to a theme switch. Zero of them is the correct count, and
  // that check needs no palette table at all. Palette validity itself moved to
  // checkThemes() below, which is per-theme and cannot be outgrown.
  //
  // `#name` ID selectors are excluded by requiring a full 3- or 6-digit hex not
  // followed by an identifier character. Comments are stripped first: they
  // legitimately quote retired colours and measured values by name.
  const bare = css.replace(/\/\*[\s\S]*?\*\//g, '');
  const hexes = bare.match(/#[0-9A-Fa-f]{6}\b|#[0-9A-Fa-f]{3}\b(?![0-9A-Za-z_-])/g) || [];
  for (const h of new Set(hexes)) {
    fail(name + ': hardcoded colour ' + h + ' — use a ${T.token} interpolation, a literal cannot follow the theme');
  }

  // Braces must balance, or a dropped rule silently swallows the next ones.
  const opens = (bare.match(/{/g) || []).length, closes = (bare.match(/}/g) || []).length;
  if (opens !== closes) fail(name + ': ' + opens + ' `{` vs ' + closes + ' `}`');

  if (!failures) console.log(name + ': PASS (' + css.split('\n').length + ' lines)');
}

// ─── THEME TABLE ────────────────────────────────────────────────────────────
// Each theme must carry the complete token set with well-formed hex values.
// A missing token is not a cosmetic gap: PALETTE_RGB, semanticToken() and the
// repainter all index the table by key, so `undefined` lands inside a CSS
// declaration and the browser drops the whole line without a word — the same
// silent-discard failure class this file was written to catch.
const REQUIRED_TOKENS = [
  'background', 'backgroundSoft',
  'surface', 'surfaceRaised', 'surfaceAlt',
  'borderDark', 'borderHighlight', 'borderMuted',
  'textPrimary', 'textSecondary', 'textMuted',
  'accentTeal', 'accentTealDeep',
  'success', 'warning', 'danger',
  'selection', 'compareBack', 'link'
];

function checkThemes() {
  const i = src.indexOf('const THEMES = {');
  if (i < 0) { fail('THEMES table not found'); return; }
  // Walk braces to find the table's own closing brace, so trailing code is not
  // swallowed and a truncated table is reported instead of silently half-read.
  let depth = 0, end = -1;
  for (let k = src.indexOf('{', i); k < src.length; k++) {
    if (src[k] === '{') depth++;
    else if (src[k] === '}') { depth--; if (depth === 0) { end = k; break; } }
  }
  if (end < 0) { fail('THEMES table has no closing brace'); return; }
  const table = src.slice(i, end + 1);

  // Top-level entries, found by brace depth rather than by matching the shape a
  // correct theme happens to have. A pattern like /(\w+):\s*\{\s*\n\s*label:/ reads
  // fine and is quietly the wrong tool: a theme that forgets `label` simply does not
  // match, so it is not listed, so none of the token checks below ever run on it —
  // the gate would report PASS on precisely the malformed entry it exists to catch.
  // A validator must never decide what to validate by looking for well-formedness.
  const entries = [];
  {
    let d = 0, k = table.indexOf('{'), slug = null;
    for (k++; k < table.length - 1; k++) {
      const ch = table[k];
      if (ch === '{') { if (d === 0 && slug) { entries.push([slug, k]); slug = null; } d++; continue; }
      if (ch === '}') { d--; continue; }
      if (d === 0) {
        const m = /^(\w+)\s*:/.exec(table.slice(k));
        if (m) { slug = m[1]; k += m[0].length - 1; }
      }
    }
  }
  if (!entries.length) { fail('THEMES table declares no themes'); return; }

  for (const [slug, open] of entries) {
    let d = 0, close = -1;
    for (let k = open; k < table.length; k++) {
      if (table[k] === '{') d++;
      else if (table[k] === '}') { d--; if (d === 0) { close = k; break; } }
    }
    const entry = table.slice(open, close < 0 ? table.length : close);
    if (!/\blabel\s*:\s*'[^']+'/.test(entry)) fail('theme ' + slug + ': missing label');
    const tokAt = entry.indexOf('tokens: {');
    if (tokAt < 0) { fail('theme ' + slug + ': no tokens block'); continue; }
    const tokEnd = entry.indexOf('}', tokAt);
    const body = entry.slice(tokAt, tokEnd);
    for (const tok of REQUIRED_TOKENS) {
      const m = new RegExp('\\b' + tok + '\\s*:\\s*\'(#[0-9A-Fa-f]{6})\'').exec(body);
      if (!m) fail('theme ' + slug + ': missing or malformed token ' + tok);
    }
    const stray = [...body.matchAll(/(\w+)\s*:\s*'([^']*)'/g)]
      .filter(m => !REQUIRED_TOKENS.includes(m[1]));
    for (const m of stray) fail('theme ' + slug + ': unknown token ' + m[1]);

    // WCAG AA on the three tokens that actually carry text, measured against the
    // backdrop this theme paints. A new palette is the easiest place in this
    // project to ship something unreadable: it looks fine in a swatch, and the
    // failure only shows up as squinting on a real page. Golden measures 9.44 /
    // 6.29 / 7.28, so the floor costs it nothing.
    //
    // textMuted (3.34 on golden) and accentTeal (3.80) are deliberately NOT gated:
    // both are non-text roles — placeholder/disabled and an accent surface — and
    // the file already documents why accentTeal must never be used as link text.
    const tok = {};
    for (const m of body.matchAll(/(\w+)\s*:\s*'(#[0-9A-Fa-f]{6})'/g)) tok[m[1]] = m[2];
    const lin = v => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4); };
    const L = h => 0.2126 * lin(parseInt(h.slice(1, 3), 16)) + 0.7152 * lin(parseInt(h.slice(3, 5), 16)) + 0.0722 * lin(parseInt(h.slice(5, 7), 16));
    if (tok.backgroundSoft) {
      for (const role of ['textPrimary', 'textSecondary', 'link']) {
        if (!tok[role]) continue;
        const a = L(tok[role]), b = L(tok.backgroundSoft);
        const ratio = (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
        if (ratio < 4.5) {
          fail('theme ' + slug + ': ' + role + ' ' + tok[role] + ' on backgroundSoft ' +
            tok.backgroundSoft + ' measures ' + ratio.toFixed(2) + ':1, under the WCAG AA 4.5:1 floor');
        }
      }
    }
    if (!failures) console.log('theme ' + slug + ': PASS (' + REQUIRED_TOKENS.length + ' tokens)');
  }
}

// The version appears twice in the userscript and they must agree -- see the note
// in release.ps1. This is the gate that makes "bump both" enforceable rather than
// remembered.
function checkVersion() {
  const header = /\/\/ @version\s+(\d+\.\d+\.\d+)/.exec(src);
  const konst = /const W95_VERSION = '(\d+\.\d+\.\d+)'/.exec(src);
  if (!header) return fail('no // @version line');
  if (!konst) return fail('no const W95_VERSION');
  if (header[1] !== konst[1]) {
    fail('@version ' + header[1] + ' but W95_VERSION ' + konst[1] + ' - the data-w95-ver stamp would report a stale build');
  } else if (!failures) console.log('version: PASS (' + header[1] + ' in both places)');
}

checkThemes();
checkVersion();

if (failures) { console.error('\n' + failures + ' failure(s)'); process.exit(1); }
console.log('CSS check PASS');
