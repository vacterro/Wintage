#!/usr/bin/env node
// Builds the desktop-application themes from the same themes/*.json packs the
// userscript uses. One palette source, many targets — a colour that drifts between
// the browser and the editor is the thing this prevents.
//
// Targets are declared in desktop/targets/<name>/. Each carries a template whose
// colour values are ${tokenName} placeholders, so adding a palette costs nothing
// and changing a token propagates everywhere at once.
//
// Usage: node tools/build-desktop.js            # (re)build everything
//        node tools/build-desktop.js --check    # exit 1 if any output is stale

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const THEME_DIR = path.join(ROOT, 'themes');
const DESKTOP = path.join(ROOT, 'desktop');
const OUT = path.join(DESKTOP, 'out');

const VERSION = (/\/\/ @version\s+(\d+\.\d+\.\d+)/.exec(
  fs.readFileSync(path.join(ROOT, 'wintage.user.js'), 'utf8')) || [, '0.0.0'])[1];

const checkOnly = process.argv.includes('--check');
let stale = 0, wrote = 0;

function loadPacks() {
  return fs.readdirSync(THEME_DIR).filter(f => f.endsWith('.json'))
    .map(f => JSON.parse(fs.readFileSync(path.join(THEME_DIR, f), 'utf8')))
    .sort((a, b) => (a.order || 99) - (b.order || 99) || a.slug.localeCompare(b.slug));
}

// Substitutes ${token} anywhere in a JSON structure. An unknown token is a hard
// error, never a silently surviving literal: `${textPrimaryy}` left in a colour
// value is accepted by VS Code's theme loader, which then renders that element
// with no colour at all — an invisible failure, which is exactly the class of bug
// the CSS gate exists to stop on the browser side.
function fill(node, tokens, ctx) {
  if (typeof node === 'string') {
    return node.replace(/\$\{(\w+)\}/g, (m, name) => {
      if (name in ctx) return ctx[name];
      if (name in tokens) return tokens[name];
      throw new Error('unknown token ${' + name + '} in ' + ctx.__file);
    });
  }
  if (Array.isArray(node)) return node.map(v => fill(v, tokens, ctx));
  if (node && typeof node === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(node)) out[k] = fill(v, tokens, ctx);
    return out;
  }
  return node;
}

function emit(file, content) {
  const prev = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : null;
  if (prev === content) return;
  if (checkOnly) { console.error('build-desktop: STALE ' + path.relative(ROOT, file)); stale++; return; }
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, content);
  wrote++;
}

// ─── TARGET: vscode ──────────────────────────────────────────────────────────
// Covers Antigravity and VS Code both — Antigravity is a VS Code fork and reads
// the identical extension format, so one build serves two applications.
//
// The template was derived from the hand-written Vintage Win 95 theme already
// installed on this machine, by replacing each hex with the token whose value it
// equalled: 96 of its 99 colour keys mapped exactly, and the three that did not are
// fully transparent (#00000000, a deliberate "no shadow") and stay literal. That
// derivation matters — it means the six generated themes are the author's own
// mapping of VS Code's surfaces, re-tinted, not someone's fresh guess at which
// editor element deserves which token.
function buildVscode(packs) {
  const dir = path.join(DESKTOP, 'targets', 'vscode');
  const template = JSON.parse(fs.readFileSync(path.join(dir, 'template.json'), 'utf8'));
  const outDir = path.join(OUT, 'vscode', 'wintage-themes');

  const contributes = [];
  for (const pack of packs) {
    const label = 'Wintage ' + pack.label;
    const theme = fill(template, pack.tokens, { label, __file: 'vscode/template.json' });
    const file = 'wintage-' + pack.slug + '-color-theme.json';
    emit(path.join(outDir, 'themes', file), JSON.stringify(theme, null, 2) + '\n');
    contributes.push({ label, uiTheme: 'vs-dark', path: './themes/' + file });
  }

  emit(path.join(outDir, 'package.json'), JSON.stringify({
    name: 'wintage-themes',
    displayName: 'Wintage — Win95 Vintage Themes',
    description: 'Dark Golden Windows 95 aesthetic, and five palettes derived from it. Generated from the Wintage theme packs.',
    // One version number for the whole project, taken from the userscript header
    // rather than kept separately — two version fields drift, and the second one
    // is always the one nobody remembers to bump.
    version: VERSION,
    publisher: 'vacterro',
    engines: { vscode: '^1.60.0' },
    categories: ['Themes'],
    contributes: { themes: contributes }
  }, null, 2) + '\n');
}

const packs = loadPacks();
buildVscode(packs);

if (stale) { console.error('\n' + stale + ' output(s) out of date — run `node tools/build-desktop.js`'); process.exit(1); }
console.log('build-desktop: ' + (wrote ? wrote + ' file(s) written' : 'everything up to date') +
  ' (' + packs.length + ' palette(s): ' + packs.map(p => p.slug).join(', ') + ')');
