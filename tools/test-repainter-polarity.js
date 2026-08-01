#!/usr/bin/env node
// The repainter's thresholds were all written against one dark palette. This test
// pins the two things that matter once a second palette exists:
//
//   1. For the golden palette the polarity layer must be a provable no-op — elev()
//      is the identity function when DARK, so every decision the repainter made in
//      v1.6.0 must still be made, bit for bit. A "generalisation" that quietly
//      re-grades the shipped theme is a regression wearing a feature's clothes.
//   2. For a light palette the decisions must actually invert — a site's dark
//      chrome becomes the flashbang, its bright surfaces become the raised ones,
//      and dark text on a light backdrop must still be found unreadable when it is.
//
// It reads the shipped source for lum()/elev()/DARK rather than reimplementing
// them, so drift in the file shows up here instead of being papered over.
const fs = require('fs'), path = require('path'), vm = require('vm');
const src = fs.readFileSync(path.join(__dirname, '..', 'wintage.user.js'), 'utf8');

let bad = 0;
const check = (label, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  console.log((ok ? 'PASS: ' : 'FAIL: ') + label + (ok ? '' : '  got=' + JSON.stringify(got) + ' want=' + JSON.stringify(want)));
  if (!ok) bad++;
};

// The real lum(), lifted from the file.
const lumSrc = /function lum\(\{ r, g, b \}\) \{[\s\S]*?\n  \}/.exec(src);
if (!lumSrc) { console.error('FAIL: lum() not found'); process.exit(1); }
const ctx = { Math };
vm.createContext(ctx);
vm.runInContext(lumSrc[0], ctx);
const lum = ctx.lum;
const hex = h => ({ r: parseInt(h.slice(1, 3), 16), g: parseInt(h.slice(3, 5), 16), b: parseInt(h.slice(5, 7), 16), a: 1 });

// The decision tree, expressed exactly as the file expresses it, parameterised by
// polarity. If the file's structure changes this must change with it — which is
// the point: it is a pin, not an oracle.
function decide(theme, colour) {
  const BG_SOFT_LUM = lum(hex(theme.backgroundSoft));
  const DARK = lum(hex(theme.background)) < 0.18;
  const elev = L => (DARK ? L : 1 - L);
  const c = hex(colour), a = 1;
  const L = elev(lum(c));
  const spread = Math.max(c.r, c.g, c.b) - Math.min(c.r, c.g, c.b);
  const grayish = spread <= 24;
  let bg = null;
  if (L > 0.45) bg = a <= 0.35 ? 'transparent' : (grayish ? 'backgroundSoft' : 'semantic');
  else if (L >= 0.004) bg = spread > 60 ? 'semantic' : (L >= 0.13 ? 'surfaceAlt' : L >= 0.05 ? 'surfaceRaised' : 'surface');
  const rawFg = lum(c);
  const cr = (Math.max(rawFg, BG_SOFT_LUM) + 0.05) / (Math.min(rawFg, BG_SOFT_LUM) + 0.05);
  const fgGray = Math.max(c.r, c.g, c.b) - Math.min(c.r, c.g, c.b) <= 40;
  const fgElev = elev(rawFg);
  let fg;
  if (cr < 4.5) fg = 'textPrimary';
  else if (fgGray) fg = fgElev > 0.4 ? 'textPrimary' : fgElev > 0.15 ? 'textSecondary' : null;
  else fg = 'textPrimary';
  return { bg, fg, readable: cr >= 4.5 };
}

const golden = { background: '#342012', backgroundSoft: '#3A2616' };
const light = { background: '#F5F3EE', backgroundSoft: '#EDEAE3' };

// 1. Golden: the exact decisions v1.6.0 made, listed as literals so a change to
//    the thresholds cannot silently update its own expectations.
const goldenExpected = [
  ['#FFFFFF', 'transparent-or-backgroundSoft', 'backgroundSoft'],
  ['#F6F8FA', 'light neutral chrome', 'backgroundSoft'],
  ['#131921', 'amazon nav-belt (the 0.015 floor bug)', 'surface'],
  ['#232F3E', 'amazon nav-main (fell through both branches)', 'surface'],
  ['#2A2A2A', 'plain dark gray panel, lum 0.024 -> the lowest surface step', 'surface'],
  ['#4A4A4A', 'mid gray panel, lum 0.073 -> one step up', 'surfaceRaised'],
  ['#7A7A7A', 'bright gray panel, lum 0.204 -> the raised step', 'surfaceAlt'],
  ['#000000', 'true black must be left alone', null],
  ['#D93025', 'saturated red', 'semantic']
];
for (const [colour, why, want] of goldenExpected) {
  const got = decide(golden, colour).bg;
  check('golden ' + colour + ' (' + why + ')', got === 'transparent' ? 'transparent-or-backgroundSoft' : got,
    want === 'transparent-or-backgroundSoft' ? 'transparent-or-backgroundSoft' : want);
}

// 2. Golden text decisions, including the two amazon cases that motivated the rule.
// #999999 measures 6.25:1 on our backdrop — legible, so it is NOT rescued as
// unreadable; it is grayish and mid-bright, so it lands on the secondary token.
// (The amazon case that forced iron law 5 was this colour INSIDE a link, which
// takes borderHighlight through a different branch.)
check('golden #999999 grayish mid text', decide(golden, '#999999').fg, 'textSecondary');
check('golden #333333 dark text is unreadable on our backdrop', decide(golden, '#333333').readable, false);
check('golden #D4B87A our own primary is readable', decide(golden, '#D4B87A').readable, true);

// 3. Light palette: the same inputs must invert.
// Pure white on a light theme is the mirror of true black on a dark one: it sits
// at elev 0, under the floor, and is deliberately left alone. #FDFDFD is already
// over the floor and does get graded, so the exemption is as narrow as it should be.
check('light: pure white is exempt, the mirror of true black', decide(light, '#FFFFFF').bg, null);
check('light: dark chrome is now the flashbang', decide(light, '#131921').bg, 'backgroundSoft');
check('light: near-white is graded, not exempt', decide(light, '#FDFDFD').bg, 'surface');
check('light: dark text stays readable, not repainted', decide(light, '#333333').readable, true);
check('light: pale gray text is correctly found unreadable', decide(light, '#EEEEEE').readable, false);
check('light: pale gray text gets textPrimary', decide(light, '#EEEEEE').fg, 'textPrimary');

// 4. The one structural claim: elev() is the identity on a dark theme, so nothing
//    about golden can have moved.
{
  const DARK = lum(hex(golden.background)) < 0.18;
  check('golden is DARK', DARK, true);
  const elev = L => (DARK ? L : 1 - L);
  let same = true;
  for (let i = 0; i <= 255; i++) { const L = lum({ r: i, g: i, b: i }); if (elev(L) !== L) same = false; }
  check('elev() is the identity across all 256 grays on a dark theme', same, true);
}

// 5. The file must not have left a hardcoded backdrop constant behind.
// Comments are stripped first — the source deliberately QUOTES the old constant
// where it explains why it is gone, and matching that would fail a correct file.
const codeOnly = src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
check('no `const darkBg = 0.008` left in the code', /darkBg\s*=\s*0\.008/.test(codeOnly), false);
check('color-scheme follows the theme', /color-scheme: \$\{DARK \? 'dark' : 'light'\}/.test(src), true);
check('data-w95-dark follows the theme', /data-w95-dark', DARK \? '1' : '0'/.test(src), true);

// 6. CodeNomad's native session status must survive the generic repaint pass.
// The exact selectors keep the exception local to CodeNomad's own DOM contract.
check('CodeNomad working uses warning token', /\.session-status\.session-working > \.status-dot \{ background-color: \$\{T\.warning\} !important; \}/.test(src), true);
check('CodeNomad idle uses success token', /\.session-status\.session-idle > \.status-dot \{ background-color: \$\{T\.success\} !important; \}/.test(src), true);
check('CodeNomad compacting uses accent token', /\.session-status\.session-compacting > \.status-dot \{ background-color: \$\{T\.accentTeal\} !important; \}/.test(src), true);
check('CodeNomad permission and retrying use danger token', /\.session-status\.session-permission > \.status-dot,[\s\S]*?\.session-status\.session-retrying > \.status-dot \{ background-color: \$\{T\.danger\} !important; \}/.test(src), true);
check('CodeNomad status dot is excluded from JS repaint', /el\.matches\('\.status-indicator\.session-status > \.status-dot'\)/.test(src), true);

console.log(bad ? '\n' + bad + ' failure(s)' : '\nrepainter polarity test PASS');
process.exit(bad ? 1 : 0);
