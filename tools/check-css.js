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

const { REQUIRED_TOKENS, WCAG_ROLES, WCAG_BACKDROPS } = require('./theme-schema.js');

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

  // A BLANKET font rule must exclude icon-font carriers, or every icon in the
  // application becomes a tofu box. Reported three times across three apps before
  // anyone read the inline style and saw font-family: var(--font-anthropicons) --
  // the glyph simply has no counterpart in Verdana. The failure looks like a
  // missing feature rather than a CSS bug, which is why it needs a gate: nothing
  // errors, the icons just quietly turn into squares.
  // NOTE: do NOT split this text on '}' to find rules. The declarations here read
  // `font-family: ${FONT}`, so a split on '}' cuts through the interpolation itself
  // and every chunk comes back without a complete declaration in it — which is
  // exactly how the first version of this check reported a clean pass on a file
  // with the guard deliberately deleted. Walk back from each declaration instead.
  for (const m of css.matchAll(/font-family:\s*(?:\$\{FONT\}|Verdana_m1)/g)) {
    const open = css.lastIndexOf('{', m.index);
    if (open < 0) continue;
    const prev = Math.max(css.lastIndexOf('}', open), css.lastIndexOf('*/', open), css.lastIndexOf(';', open));
    const sel = css.slice(prev + 1, open).trim();
    if (!/^\*/.test(sel)) continue;               // only the universal ones are dangerous
    for (const marker of ['[class*="icon" i]', '[class*="codicon" i]', '[data-cds="Icon"]']) {
      if (!sel.includes(':not(' + marker + ')')) {
        fail(name + ': a universal font-family rule does not exclude ' + marker +
          ' — icons rendered with an icon font will turn into empty squares');
      }
    }
  }

  // A GUARD IS ONLY A GUARD IF EVERY SELECTOR IN THE LIST CARRIES IT.
  // The wipe that makes a button read as one control must not reach the small
  // coloured dot a button uses to report state -- running, waiting, done -- whose
  // entire meaning IS its background. The exclusions for that were added as
  // :not() on the wipe, correctly, and then defeated for a release by one bare
  // `button:not(.ytp-button) *,` left above them in the same comma list. One
  // unguarded sibling matches everything its guarded twin was written to spare,
  // and nothing about the CSS looks wrong: the guards are right there, in the
  // file, doing nothing. Measured on the live app while it was in that state:
  // span.status-dot[data-kind="running"], 6x6, background-color rgba(0,0,0,0).
  // So the check is structural -- find any rule that wipes a background on
  // descendants of a control, and require EVERY descendant selector in it to
  // carry the state exclusions.
  const STATE_GUARD = ':not([data-kind])';
  for (const m of bare.matchAll(/([^{}]+)\{([^{}]*background-color:\s*transparent[^{}]*)\}/g)) {
    const selectors = m[1].split(',').map(s => s.trim()).filter(Boolean);
    const controlDescendant = /(^|\s)(button|\.btn|\[class~="(button|btn)" i\]|\w+\[role="button"\])\b[^,]*\s\*/;
    for (const sel of selectors) {
      if (!controlDescendant.test(sel)) continue;
      if (!sel.includes(STATE_GUARD)) {
        fail(name + ': `' + sel.slice(0, 60) + '` wipes backgrounds on control descendants without ' +
          STATE_GUARD + ' — one unguarded selector in the list erases every status ' +
          'colour the guarded ones in the same rule were written to protect');
      }
    }
  }

  // Braces must balance, or a dropped rule silently swallows the next ones.
  const opens = (bare.match(/{/g) || []).length, closes = (bare.match(/}/g) || []).length;
  if (opens !== closes) fail(name + ': ' + opens + ' `{` vs ' + closes + ' `}`');

  // UI.md iron laws 1 and 2 -- the pixel laws nothing above measures.
  checkIronLaws(name, css, start);

  if (!failures) console.log(name + ': PASS (' + css.split('\n').length + ' lines)');
}

// ─── IRON LAWS 1 AND 2 (UI.md) ─────────────────────────────────────────────
// The checks above own structure, colours, icons, braces and the theme table.
// These own what the pixels look like, which nothing measured: the size ladder,
// the anti-aliasing controls, and the zero-radius / zero-shadow / zero-gradient
// / zero-blur / zero-transparency / zero-motion laws.
//
// Every rule here is VALUE-aware, and that is the whole difficulty. This file
// re-skins foreign applications, so most declarations naming a banned property
// are RESETS the law requires (`border-radius: 0`, `box-shadow: none`,
// `filter: none`, `background-color: transparent`) or anti-motion SLAMS (a host
// transition driven to 0.001s so its animation lifecycle still fires but nothing
// moves). A check on the property NAME would fail the file for obeying the law
// and bury the one real violation in noise, so each rule names the values it
// allows and says why in the failure text:
//   border-radius                : 0 / 0px only
//   box-shadow, text-shadow      : none only
//   backdrop-filter, filter      : none / unset only
//   gradients                    : never painted by us
//   *-duration                   : <= 1ms -- a slam, not motion
//   animation-iteration-count    : 1 or 0; `infinite` re-strobes what the slam
//                                  was meant to stop
//   animation-fill-mode          : the four legal keywords
//   opacity                      : 0 (hide) or 1 (reveal) only -- a fractional
//                                  value is fading, and UI.md names the
//                                  substitute: --textMuted on the same surface
// NOTE: no module-level `const` here. The CSS loop above calls checkIronLaws()
// while that loop is still running, and a module-level const declared below it is
// in its temporal dead zone at that moment -- it crashed on the first run. A
// function DECLARATION hoists and is initialized; a const does not. So the size
// ladder lives inside the function that uses it.
function ironMaxMs(value) {
  const parts = String(value).split(',').map(s => s.trim()).filter(Boolean);
  if (!parts.length) return null;
  let max = 0;
  for (const part of parts) {
    const m = /^([0-9]*\.?[0-9]+)(ms|s)?$/.exec(part);
    if (!m) return null;                      // var(), calc(), a keyword: state it, do not guess
    const n = parseFloat(m[1]);
    max = Math.max(max, m[2] === 's' ? n * 1000 : n);
  }
  return max;
}

function checkIronLaws(name, css, start) {
  const before = failures;
  const LADDER = new Set(['10px', '11px', '12px', '14px', '16px']);
  // Comments are blanked, not deleted. Blanking keeps every offset and newline in
  // place, so a failure can name a real line of the real file; deleting them (as
  // the checks above do) would shift every number after the first comment.
  const bare = css.replace(/\/\*[\s\S]*?\*\//g, m => m.replace(/[^\n]/g, ' '));
  const first = src.slice(0, start).split('\n').length;
  const at = off => String(first + bare.slice(0, off).split('\n').length - 1);
  let measured = 0;

  // ── iron law 1: the size ladder ──────────────────────────────────────────
  for (const m of bare.matchAll(/font-size:\s*([^;}!]+)/g)) {
    const v = m[1].trim();
    measured++;
    if (/^(inherit|unset|revert|revert-layer|initial)$/.test(v)) continue;  // host-derived, not a ladder step
    if (!LADDER.has(v)) {
      fail(name + ': font-size ' + v + ' at line ' + at(m.index) +
        ' is off the ladder -- iron law 1 allows 10/11/12/14/16px only (legitimate: inherit)');
    }
  }

  // ── iron law 1: AA is declared, and never requested ON ───────────────────
  for (const [prop, want] of [
    ['-webkit-font-smoothing', 'none'],
    ['-moz-osx-font-smoothing', 'unset'],
    ['font-smooth', 'never'],
    ['text-rendering', 'optimizeSpeed'],
  ]) {
    if (!new RegExp(prop + '\\s*:\\s*' + want).test(bare)) {
      fail(name + ': no `' + prop + ': ' + want + '` -- iron law 1 requires the anti-aliasing ' +
        'controls to be declared, not assumed, because a toolkit default silently re-enables smoothing');
    }
  }
  for (const m of bare.matchAll(/-(?:webkit|moz)-font-smoothing\s*:\s*([^;}!]+)/g)) {
    const v = m[1].trim();
    if (v === 'antialiased' || v === 'subpixel-antialiased' || v === 'grayscale') {
      fail(name + ': ' + m[0].split(':')[0].trim() + ': ' + v + ' at line ' + at(m.index) +
        ' requests smoothing -- iron law 1 is anti-aliasing OFF as a hard invariant');
    }
  }

  // ── iron law 2: depth and colour, by VALUE ───────────────────────────────
  for (const [prop, ok, why] of [
    ['border-radius', v => /^0(px|%)?$/.test(v), 'iron law 2 allows only 0'],
    ['box-shadow', v => v === 'none', 'iron law 2 allows only none'],
    ['text-shadow', v => v === 'none', 'iron law 2 allows only none'],
    ['backdrop-filter', v => v === 'none', 'iron law 2 allows only none'],
    ['filter', v => v === 'none' || v === 'unset', 'iron law 2 allows only none/unset'],
  ]) {
    for (const m of bare.matchAll(new RegExp(prop + '\\s*:\\s*([^;}!]+)', 'g'))) {
      const v = m[1].trim();
      measured++;
      if (!ok(v)) {
        fail(name + ': ' + prop + ': ' + v + ' at line ' + at(m.index) + ' -- ' + why +
          ' (a reset to the allowed value is the expected form here)');
      }
    }
  }
  for (const m of bare.matchAll(/(linear|radial|conic)-gradient/g)) {
    fail(name + ': ' + m[0] + ' at line ' + at(m.index) +
      ' -- iron law 2 bans gradients; depth is the 2px bevel and nothing else');
  }

  // ── iron law 2: motion, only as a sub-millisecond slam ───────────────────
  for (const m of bare.matchAll(/(transition|animation)-duration\s*:\s*([^;}!]+)/g)) {
    measured++;
    const ms = ironMaxMs(m[2]);
    if (ms === null || ms > 1) {
      fail(name + ': ' + m[1] + '-duration: ' + m[2].trim() + ' at line ' + at(m.index) +
        ' -- iron law 2 allows only a <= 1ms slam (long enough to fire ' +
        'animationstart/animationend, short enough that nothing visibly moves)');
    }
  }
  for (const m of bare.matchAll(/animation-iteration-count\s*:\s*([^;}!]+)/g)) {
    measured++;
    const v = m[1].trim();
    if (!/^[01]$/.test(v)) {
      fail(name + ': animation-iteration-count: ' + v + ' at line ' + at(m.index) +
        ' -- only 0 or 1; `infinite` turns the duration slam into a strobe, which is worse than the motion it replaced');
    }
  }
  for (const m of bare.matchAll(/animation-fill-mode\s*:\s*([^;}!]+)/g)) {
    measured++;
    const v = m[1].trim();
    if (!/^(none|forwards|backwards|both)$/.test(v)) {
      fail(name + ': animation-fill-mode: ' + v + ' at line ' + at(m.index) +
        ' -- one of the four legal keywords');
    }
  }

  // ── iron law 2: transparency, with the two sanctioned uses ──────────────
  // 0 hides (the ripple/scrollbar-proxy resets), 1 force-reveals (the repair
  // guards). Anything between them is a control being faded, which iron law 2
  // bans outright and UI.md replaces with --textMuted on the same surface.
  for (const m of bare.matchAll(/opacity\s*:\s*([^;}!]+)/g)) {
    measured++;
    const v = m[1].trim();
    if (/^0(\.0+)?$/.test(v) || /^1(\.0+)?$/.test(v)) continue;
    fail(name + ': opacity: ' + v + ' at line ' + at(m.index) +
      ' -- iron law 2 bans transparency; for a quieter control UI.md names the ' +
      'substitute: --textMuted on the same surface, never opacity');
  }

  if (failures === before) {
    console.log(name + ': PASS iron laws 1-2 (' + measured + ' pixel declarations measured, ' +
      'value-aware: resets and <= 1ms slams are legal)');
  }
}

// ─── THEME TABLE ────────────────────────────────────────────────────────────
// Each theme must carry the complete token set with well-formed hex values.
// A missing token is not a cosmetic gap: PALETTE_RGB, semanticToken() and the
// repainter all index the table by key, so `undefined` lands inside a CSS
// declaration and the browser drops the whole line without a word — the same
// silent-discard failure class this file was written to catch.
// REQUIRED_TOKENS and WCAG_ROLES are imported from tools/theme-schema.js, the
// single canonical owner — no second copy to drift.

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

    // WCAG AA on the roles that actually carry text, measured against every
    // backdrop the theme's own CSS can put that text on. The role list and the
    // backdrop list are the shared WCAG_ROLES / WCAG_BACKDROPS from
    // theme-schema.js — the same contract the GUI warns about, so what the
    // editor predicts and what the gate enforces can never disagree again. A
    // new palette is the easiest place in this project to ship something
    // unreadable: it looks fine in a swatch, and the failure only shows up as
    // squinting on a real page. Golden measures 9.44 / 6.29 / 7.28, so the floor
    // costs it nothing.
    //
    // T-988: the old contract measured every role against backgroundSoft ONLY.
    // That is the soft ground — on a light palette it is the LIGHTEST surface in
    // the pack, so the one backdrop where a dark link always looks fine, and the
    // gray page the user actually reads was never measured. Two measured misses
    // came out of that blind spot (a 2.54:1 link on the gray page, 3.91:1 and
    // 3.32:1 button labels on the control faces) and they are fixed by the
    // widened contract below.
    //
    // textMuted (3.34 on golden) and accentTeal (3.80) are deliberately NOT gated:
    // both are non-text roles — placeholder/disabled and an accent surface — and
    // the file already documents why accentTeal must never be used as link text.
    // borderHighlight is also deliberately absent: it is a decorative bevel edge,
    // near-white on light palettes, and gating it made every light palette FAIL
    // on a token that is never text (T-187).
    const tok = {};
    for (const m of body.matchAll(/(\w+)\s*:\s*'(#[0-9A-Fa-f]{6})'/g)) tok[m[1]] = m[2];
    const lin = v => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4); };
    const L = h => 0.2126 * lin(parseInt(h.slice(1, 3), 16)) + 0.7152 * lin(parseInt(h.slice(3, 5), 16)) + 0.0722 * lin(parseInt(h.slice(5, 7), 16));
    const contrast = (a, b) => {
      const x = L(a), y = L(b);
      return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
    };
    for (const role of WCAG_ROLES) {
      if (!tok[role]) continue;
      for (const backdrop of WCAG_BACKDROPS[role]) {
        if (!tok[backdrop]) continue;
        const ratio = contrast(tok[role], tok[backdrop]);
        if (ratio < 4.5) {
          fail('theme ' + slug + ': ' + role + ' ' + tok[role] + ' on ' + backdrop + ' ' +
            tok[backdrop] + ' measures ' + ratio.toFixed(2) + ':1, under the WCAG AA 4.5:1 floor');
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

// The surface-flattening wipe in GLOBAL_CSS makes every panel transparent and then
// hands back the ones that must stay opaque through a list of component NAMES.
// That list missed Claude's popovers twice (E-381, E-407), and it will miss the
// next app the same way: an app that renames a component or swaps its popover
// library drops off it at its next release, silently -- nothing errors, the theme
// just develops a hole and the user finds it. The repainter therefore carries a
// MEASURED test alongside the names, and this gate keeps it measured. Losing any
// one of the four checks leaves a block that still reads like it covers popovers.
function checkFloatingSurfaces() {
  if (!/background-color:\s*transparent\s*!important/.test(src)) return; // no wipe, no duty
  const i = src.indexOf('FLOATING SURFACES ARE MEASURED, NOT NAMED');
  if (i < 0) {
    return fail('the repainter has no measured floating-surface test -- with the ' +
      'transparency wipe in place, any popover the CSS name list does not know ' +
      'renders see-through with the page showing through it');
  }
  // Wide enough to reach the hit test at the end of the block. It was 3000 and
  // the block outgrew it, which reported the two measurements at the bottom as
  // missing -- a gate lying in the safe direction is still a gate lying. It was
  // 6000 and the block outgrew that too (a comment about the repainter's shim
  // split added two lines), so the hit test now lives past the window's end.
  const block = src.slice(i, i + 8000);
  for (const [needle, what] of [
    ['cs.position', 'out of flow (position)'],
    ['getBoundingClientRect', 'big enough to read (measured rect)'],
    ['elementsFromPoint', 'actually floating (hit test at its own centre)'],
    ['under.contains(el)', 'that the hit test ignores its own ancestors']
  ]) {
    if (block.indexOf(needle) < 0) {
      fail('the measured floating-surface test no longer checks ' + what +
        ' -- it decides by name again for that half of the rule');
    }
  }
  if (!failures) console.log('floating surfaces: PASS (measured, not named)');
}

checkThemes();
checkVersion();
checkFloatingSurfaces();

if (failures) { console.error('\n' + failures + ' failure(s)'); process.exit(1); }
console.log('CSS check PASS');
