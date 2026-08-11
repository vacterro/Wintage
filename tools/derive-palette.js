#!/usr/bin/env node
// Derives a UI.md-conformant palette from the golden one.
//
// UI.md's palette is not twenty-one colours, it is a STRUCTURE: a near-black ground,
// three surface steps a few percent apart, a highlight around 56% lightness that
// doubles as the bevel edge and the link, a text ladder at roughly 9.4 / 6.3 / 3.3
// to one, and desaturated semantic colours that never carry text. Hand-picking a
// second palette reproduces the hues and quietly loses the structure — which is
// exactly how a theme ends up looking "close enough" while its headings sit at the
// wrong step and its muted text turns unreadable.
//
// So every theme is the golden palette rotated to another hue family: same
// lightness per token, same saturation ratios, same contrasts. The identity lives
// in the hue, which is the only thing that should differ.
//
// Fixed across every theme, deliberately:
//   accentTeal / accentTealDeep  — UI.md names one accent and it is teal.
//   success / warning / danger   — semantic, not decorative. A green that means
//                                  "ok" must not become a project's brand colour,
//                                  and re-tinting them per theme is how a status
//                                  stops reading as a status.
//
// Usage: node tools/derive-palette.js            # rewrite every derived pack
//        node tools/derive-palette.js --check    # exit 1 if any is out of date

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const THEME_DIR = path.join(ROOT, 'themes');

// slug -> identity, and every hue below was read off the installed application
// rather than recalled. Surfaces and accent are specified separately because
// almost no real product uses one hue for both: Antigravity's chrome is cool
// slate while its brand is teal, and collapsing the two loses the thing that
// makes a theme recognisable.
//
//   hue / sat        — the surface ladder (background through surfaceAlt, borders)
//   accentHue / accentSat — borderHighlight and the text ladder
//   source           — where the colours came from, recorded in the pack itself so
//                      the next person does not have to re-derive the archaeology
const SPECS = {
  claudecode: {
    label: 'Claude Code', order: 2,
    hue: 40, sat: 0.35, accentHue: 17, accentSat: 0.95,
    source: "Anthropic's terminal palette: warm near-neutral surfaces (#1F1E1D/#262624), coral #D97757 accent, cream text"
  },
  antigravity: {
    label: 'Antigravity', order: 3,
    hue: 228, sat: 0.5, accentHue: 172, accentSat: 1.0,
    source: 'extensions/antigravity/tailwind.config.js in the installed IDE: brand-dark #09b6a2 teal on the cool gray ladder topped by #2D3142'
  },
  klite: {
    label: 'K-Lite (MPC-HC)', order: 4,
    hue: 210, sat: 0.12, accentHue: 210, accentSat: 0.1,
    source: 'HKCU\\Software\\MPC-HC\\MPC-HC\\Settings MPCTheme=1 (dark UI active); MPC-HC dark chrome is deliberately neutral, so this is graphite with a silver highlight rather than a hue'
  },
  freebuff: {
    label: 'FreeBuff', order: 5,
    hue: 215, sat: 0.45, accentHue: 100, accentSat: 1.0,
    source: 'strings in the installed app.asar: #0C0D0F ground, #1F2937 slate surface, lime #7CFF3F / green #22C55E accent'
  },
  codenomad: {
    label: 'CodeNomad', order: 6,
    hue: 212, sat: 0.4, accentHue: 249, accentSat: 0.9,
    source: 'AppData/@neuralnomads/codenomad-electron-app cache: #0E1116 ground, #24292E/#2F363D surfaces, indigo #624AFF / #615CED accent, #E1E4E8 text'
  }
};

// Tokens whose value is identity-neutral and therefore never rotated.
const FIXED = ['accentTeal', 'accentTealDeep', 'success', 'warning', 'danger'];
// Tokens that carry the theme's recognisable colour.
const ACCENT = ['borderHighlight', 'textPrimary', 'textSecondary', 'textMuted'];

function hexToRgb(h) {
  return [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
}
function rgbToHex(r, g, b) {
  const c = v => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0').toUpperCase();
  return '#' + c(r) + c(g) + c(b);
}
function rgbToHsl(r, g, b) {
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2;
  if (max === min) return [0, 0, l];
  const d = max - min;
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  let h;
  if (max === r) h = ((g - b) / d + (g < b ? 6 : 0));
  else if (max === g) h = (b - r) / d + 2;
  else h = (r - g) / d + 4;
  return [h * 60, s, l];
}
function hslToRgb(h, s, l) {
  h = ((h % 360) + 360) % 360 / 360;
  if (s === 0) { const v = l * 255; return [v, v, v]; }
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  const p = 2 * l - q;
  const hk = t => {
    t = (t + 1) % 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
  };
  return [hk(h + 1 / 3) * 255, hk(h) * 255, hk(h - 1 / 3) * 255];
}

const golden = JSON.parse(fs.readFileSync(path.join(THEME_DIR, 'golden.json'), 'utf8').replace(/^\uFEFF/, ''));
// Golden's own base hue, measured rather than assumed — its surfaces average ~30°.
const GOLDEN_BASE = 30;

function relLum(r, g, b) {
  const lin = v => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4); };
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
}
function ratio(a, b) { return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05); }

function blendHex(a, b, amount) {
  const A = hexToRgb(a), B = hexToRgb(b);
  return rgbToHex(
    A[0] + (B[0] - A[0]) * amount,
    A[1] + (B[1] - A[1]) * amount,
    A[2] + (B[2] - A[2]) * amount
  );
}

function dangerTextFor(colour, backdrop) {
  const bgLum = relLum(...hexToRgb(backdrop));
  if (ratio(relLum(...hexToRgb(colour)), bgLum) >= 4.5) return colour;
  const [h, s, start] = rgbToHsl(...hexToRgb(colour));
  let low = start, high = 1;
  for (let i = 0; i < 32; i++) {
    const mid = (low + high) / 2;
    if (ratio(relLum(...hslToRgb(h, s, mid)), bgLum) >= 4.52) high = mid;
    else low = mid;
  }
  return rgbToHex(...hslToRgb(h, s, high));
}

// Rotating a hue does not preserve contrast: at golden's lightness a violet is far
// darker than an amber, so CodeNomad's indigo came out at 4.02:1 while the amber it
// was derived from sits at 7.28:1. Structure is the thing being preserved, and a
// text token that fails AA is not the same structure — so the three tokens that
// carry text get lifted in lightness until they clear the floor. It is a small,
// bounded correction (a few percent of L) and it is reported, never silent.
const AA_GATED = ['borderHighlight', 'textPrimary', 'textSecondary'];
function liftToAA(h, s, l, bgLum, name, slug) {
  let out = hslToRgb(h, s, l);
  if (ratio(relLum(...out), bgLum) >= 4.6) return out;
  const from = l;
  while (l < 0.95) {
    l += 0.01;
    out = hslToRgb(h, s, l);
    if (ratio(relLum(...out), bgLum) >= 4.6) break;
  }
  console.log('derive-palette: ' + slug + ' lifted ' + name + ' L ' +
    (from * 100).toFixed(0) + '% -> ' + (l * 100).toFixed(0) + '% to clear WCAG AA');
  return out;
}

function derive(slug, spec) {
  const tokens = {};
  // backgroundSoft is what every contrast in this file is measured against, so it
  // is resolved first — the AA lift below needs it before the text tokens exist.
  const gsoft = rgbToHsl(...hexToRgb(golden.tokens.backgroundSoft));
  const softRgb = hslToRgb(spec.hue + (gsoft[0] - GOLDEN_BASE), Math.min(1, gsoft[1] * spec.sat), gsoft[2]);
  const bgLum = relLum(...softRgb);

  for (const [name, hex] of Object.entries(golden.tokens)) {
    if (name === 'bevelLight') {
      tokens[name] = blendHex(tokens.surfaceAlt, tokens.borderHighlight, 0.28);
      continue;
    }
    if (name === 'dangerText') {
      tokens[name] = dangerTextFor(tokens.danger, tokens.backgroundSoft);
      continue;
    }
    if (FIXED.includes(name)) { tokens[name] = hex; continue; }
    const [h, s, l] = rgbToHsl(...hexToRgb(hex));
    // Preserve each token's OFFSET from golden's base hue, so the internal
    // relationships (the highlight running warmer than the surfaces, for one)
    // survive the rotation instead of being flattened onto a single hue.
    const offset = h - GOLDEN_BASE;
    const accent = ACCENT.includes(name);
    const base = accent ? spec.accentHue : spec.hue;
    const scale = accent ? spec.accentSat : spec.sat;
    const hh = base + offset, ss = Math.min(1, s * scale);
    const [r, g, b] = AA_GATED.includes(name)
      ? liftToAA(hh, ss, l, bgLum, name, slug)
      : hslToRgb(hh, ss, l);
    tokens[name] = rgbToHex(r, g, b);
  }
  // Every derived palette is dark (they are golden's hue rotated), so the bevel
  // highlight doubles as a readable link exactly as it does on golden -- link is
  // just borderHighlight. The split only earns its keep on a light palette, which
  // this generator never produces; the imported FastPrompter side handles those.
  tokens.link = tokens.borderHighlight;
  return { slug, label: spec.label, order: spec.order, source: spec.source, tokens };
}

const checkOnly = process.argv.includes('--check');
let stale = 0;

for (const [slug, spec] of Object.entries(SPECS)) {
  const file = path.join(THEME_DIR, slug + '.json');
  const next = JSON.stringify(derive(slug, spec), null, 2) + '\n';
  const prev = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null;
  if (prev === next) { console.log('derive-palette: ' + slug + ' up to date'); continue; }
  if (checkOnly) { console.error('derive-palette: ' + slug + '.json is OUT OF DATE'); stale++; continue; }
  fs.writeFileSync(file, next);
  console.log('derive-palette: wrote ' + slug + '.json (hue ' + spec.hue + ', saturation x' + spec.sat + ')');
}

if (stale) { console.error('\n' + stale + ' pack(s) out of date — run `node tools/derive-palette.js`'); process.exit(1); }
