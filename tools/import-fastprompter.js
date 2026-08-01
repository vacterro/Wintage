#!/usr/bin/env node
// Imports FastPrompter's theme list into Wintage theme packs.
//
// FastPrompter describes a theme with nine colours; Wintage needs twenty-one tokens.
// The gap is not filled by inventing colours — every derived token is a blend of two
// the theme already declares, so an imported palette still reads as itself. What is
// NOT taken from FastPrompter: the semantic trio and the teal accent. Those stay at
// UI.md's values for the same reason they are fixed in tools/derive-palette.js — a
// green that means "ok" must not turn into a brand colour, and a status that changes
// hue per theme stops reading as a status.
//
// The one place this cannot be purely mechanical is contrast. FastPrompter's own
// widgets do not have to clear WCAG AA, Wintage's gate does, so the three
// text-carrying tokens are lifted until they pass — reported per lift, never silent.
// Vintage Classic is the interesting case: it is genuinely LIGHT (#c0c0c0), which is
// the first real exercise of the polarity work from T-019.
//
// Usage: node tools/import-fastprompter.js [--source <themes.py>] [--check]

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const THEME_DIR = path.join(ROOT, 'themes');
const DEFAULT_SOURCE = 'V:/___VAC/__K/__CODE/_PY/_FastPrompter/src/fastprompter/theme/themes.py';

const arg = (name, fallback) => {
  const i = process.argv.indexOf('--' + name);
  return i >= 0 ? process.argv[i + 1] : fallback;
};
const checkOnly = process.argv.includes('--check');

// slug (must be a JS identifier: apply-themes.js enforces it) + menu order.
const SLUGS = {
  'Default': ['fpdefault', 20],
  'Golden Vintage': ['goldenvintage', 21],
  'Golden Default': ['goldendefault', 22],
  'Vintage Dark': ['vintagedark', 23],
  'Vintage Classic': ['vintageclassic', 24],
  'Dark 2 (OLED)': ['oled', 25],
  'Dracula': ['dracula', 26],
  'Nord': ['nord', 27],
  'Solarized Dark': ['solarized', 28]
};

const FIXED = {
  accentTeal: '#008080', accentTealDeep: '#004C4C',
  success: '#4A7A20', warning: '#7A7A20', danger: '#7A2020'
};

const rgb = h => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
const hex = (r, g, b) => '#' + [r, g, b].map(v => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0').toUpperCase()).join('');
const blend = (a, b, t) => { const A = rgb(a), B = rgb(b); return hex(A[0] + (B[0] - A[0]) * t, A[1] + (B[1] - A[1]) * t, A[2] + (B[2] - A[2]) * t); };
const lin = v => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4); };
const lum = h => { const c = rgb(h); return 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2]); };
const ratio = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };

function rgbToHsl(r, g, b) {
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2;
  if (max === min) return [0, 0, l];
  const d = max - min;
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  let h;
  if (max === r) h = (g - b) / d + (g < b ? 6 : 0);
  else if (max === g) h = (b - r) / d + 2;
  else h = (r - g) / d + 4;
  return [h * 60, s, l];
}

function hslToRgb(h, s, l) {
  h = ((h % 360) + 360) % 360 / 360;
  if (s === 0) { const v = l * 255; return [v, v, v]; }
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  const p = 2 * l - q;
  const channel = t => {
    t = (t + 1) % 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
  };
  return [channel(h + 1 / 3) * 255, channel(h) * 255, channel(h - 1 / 3) * 255];
}

// Status-fill red is intentionally dark; text using the same token fails AA.
// Preserve its hue/saturation and move only lightness until text clears 4.5:1.
function dangerTextFor(colour, backdrop) {
  if (ratio(colour, backdrop) >= 4.5) return colour;
  const [h, s, start] = rgbToHsl(...rgb(colour));
  let low = start, high = 1;
  for (let i = 0; i < 32; i++) {
    const mid = (low + high) / 2;
    const candidate = hex(...hslToRgb(h, s, mid));
    if (ratio(candidate, backdrop) >= 4.52) high = mid;
    else low = mid;
  }
  return hex(...hslToRgb(h, s, high));
}

// Lift toward whichever end of the scale the backdrop is NOT, so a light theme's
// text gets darker rather than brighter. Blending toward black/white keeps the hue
// instead of washing it out, which a naive HSL lightness change does not.
function liftToAA(colour, backdrop, name, slug) {
  if (ratio(colour, backdrop) >= 4.6) return colour;
  const towards = lum(backdrop) > 0.18 ? '#000000' : '#FFFFFF';
  const from = colour;
  let out = colour;
  for (let t = 0.05; t <= 1.0001; t += 0.05) {
    out = blend(colour, towards, t);
    if (ratio(out, backdrop) >= 4.6) break;
  }
  console.log('import-fastprompter: ' + slug + ' lifted ' + name + ' ' + from + ' -> ' + out +
    ' (' + ratio(from, backdrop).toFixed(2) + ' -> ' + ratio(out, backdrop).toFixed(2) + ':1)');
  return out;
}

function toPack(name, raw) {
  const [slug, order] = SLUGS[name];
  const bgMain = raw.bg_main, bgText = raw.bg_text;
  // Wintage's `background` is the deepest surface. FastPrompter does not promise
  // which of its two is darker (Vintage Classic's text area is LIGHTER than its
  // window), so it is decided by measurement rather than by field name.
  const darker = lum(bgMain) <= lum(bgText) ? bgMain : bgText;
  const lighter = darker === bgMain ? bgText : bgMain;

  const tokens = {
    background: darker,
    backgroundSoft: lighter,
    surface: raw.btn_bg,
    surfaceRaised: blend(raw.btn_bg, raw.border_light, 0.25),
    surfaceAlt: blend(raw.btn_bg, raw.border_light, 0.45),
    borderDark: raw.border_dark,
    borderHighlight: raw.accent,
    bevelLight: null,
    borderMuted: raw.border_light,
    textPrimary: raw.text_main,
    textSecondary: blend(raw.text_main, darker, 0.30),
    textMuted: blend(raw.text_main, darker, 0.55)
  };
  Object.assign(tokens, FIXED);
  tokens.dangerText = null;
  tokens.selection = tokens.surfaceRaised;
  tokens.compareBack = blend(darker, lum(darker) > 0.18 ? '#FFFFFF' : '#000000', 0.25);

  const backdrop = tokens.backgroundSoft;
  const light = lum(backdrop) > 0.18;

  // borderHighlight is the bevel light edge; link is the hyperlink colour. On a dark
  // palette one value serves both, so link = the AA-lifted accent and the bevel keeps
  // it. On a LIGHT palette they pull apart: the bevel highlight must be near-white to
  // read as raised, and near-white fails AA as link text -- so the accent, lifted
  // DARK for readability, becomes link, and the bevel goes bright on its own.
  tokens.link = liftToAA(tokens.borderHighlight, backdrop, 'link', slug);
  for (const k of ['textPrimary', 'textSecondary']) {
    tokens[k] = liftToAA(tokens[k], backdrop, k, slug);
  }
  tokens.borderHighlight = light ? blend(tokens.surface, '#FFFFFF', 0.85) : tokens.link;
  tokens.bevelLight = light
    ? tokens.borderHighlight
    : blend(tokens.surfaceAlt, tokens.borderHighlight, 0.28);
  tokens.dangerText = dangerTextFor(tokens.danger, backdrop);

  // Uppercase everywhere: check-css.js and apply-themes.js both compare hex as
  // written, and a mixed-case table looks like two different colours in a diff.
  for (const k of Object.keys(tokens)) tokens[k] = tokens[k].toUpperCase();

  return {
    slug, label: name, order,
    source: 'imported from FastPrompter (src/fastprompter/theme/themes.py): nine declared colours, the rest blended from them; semantic trio and teal kept at UI.md values',
    tokens
  };
}

const source = arg('source', DEFAULT_SOURCE);
if (!fs.existsSync(source)) {
  console.error('import-fastprompter: source not found: ' + source);
  console.error('  pass --source <path to fastprompter themes.py>');
  process.exit(1);
}
const src = fs.readFileSync(source, 'utf8');
const start = src.indexOf('THEMES = {');
if (start < 0) { console.error('import-fastprompter: no THEMES table in ' + source); process.exit(1); }
const body = src.slice(start);

// Two shapes coexist in that file: inline `{ "raw_colors": {...} }` blocks and
// `generate_custom_theme({...})` calls. Both are read; a theme present in neither is
// reported rather than skipped silently.
const found = {};
for (const m of body.matchAll(/^\s{4}"([^"]+)":\s*\{(.*?)\n\s{4}\},?\s*$/gms)) {
  const raw = /"raw_colors"\s*:\s*\{(.*?)\}/s.exec(m[2]);
  found[m[1]] = Object.fromEntries([...(raw ? raw[1] : m[2]).matchAll(/"(\w+)":\s*"(#[0-9A-Fa-f]{3,8})"/g)].map(x => [x[1], x[2]]));
}
for (const m of body.matchAll(/^\s{4}"([^"]+)":\s*generate_custom_theme\(\{(.*?)\n\s{4}\}\)/gms)) {
  found[m[1]] = Object.fromEntries([...m[2].matchAll(/"(\w+)":\s*"(#[0-9A-Fa-f]{3,8})"/g)].map(x => [x[1], x[2]]));
}

let stale = 0, wrote = 0;
for (const name of Object.keys(SLUGS)) {
  const raw = found[name];
  if (!raw || !raw.bg_main) { console.error('import-fastprompter: "' + name + '" not found in the source - skipped'); continue; }
  const pack = toPack(name, raw);
  const file = path.join(THEME_DIR, pack.slug + '.json');
  const next = JSON.stringify(pack, null, 2) + '\n';
  const prev = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null;
  if (prev === next) continue;
  if (checkOnly) { console.error('import-fastprompter: STALE ' + pack.slug + '.json'); stale++; continue; }
  fs.writeFileSync(file, next);
  wrote++;
}

if (stale) { console.error('\n' + stale + ' pack(s) out of date - run `node tools/import-fastprompter.js`'); process.exit(1); }
console.log('import-fastprompter: ' + (wrote ? wrote + ' pack(s) written' : 'everything up to date'));
