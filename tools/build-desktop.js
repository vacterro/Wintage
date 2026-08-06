#!/usr/bin/env node
// Builds the desktop-application themes from the same themes/*.json packs the
// userscript uses. One palette source, many targets вЂ” a colour that drifts between
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
const vm = require('vm');

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
    .map(f => JSON.parse(fs.readFileSync(path.join(THEME_DIR, f), 'utf8').replace(/^\uFEFF/, '')))
    .sort((a, b) => (a.order || 99) - (b.order || 99) || a.slug.localeCompare(b.slug));
}

// Substitutes ${token} anywhere in a JSON structure. An unknown token is a hard
// error, never a silently surviving literal: `${textPrimaryy}` left in a colour
// value is accepted by VS Code's theme loader, which then renders that element
// with no colour at all вЂ” an invisible failure, which is exactly the class of bug
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

// в”Ђв”Ђв”Ђ TARGET: vscode в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
// Covers Antigravity and VS Code both вЂ” Antigravity is a VS Code fork and reads
// the identical extension format, so one build serves two applications.
//
// The template was derived from the hand-written Vintage Win 95 theme already
// installed on this machine, by replacing each hex with the token whose value it
// equalled: 96 of its 99 colour keys mapped exactly, and the three that did not are
// fully transparent (#00000000, a deliberate "no shadow") and stay literal. That
// derivation matters вЂ” it means the six generated themes are the author's own
// mapping of VS Code's surfaces, re-tinted, not someone's fresh guess at which
// editor element deserves which token.
function buildVscode(packs) {
  const dir = path.join(DESKTOP, 'targets', 'vscode');
  const template = JSON.parse(fs.readFileSync(path.join(dir, 'template.json'), 'utf8').replace(/^\uFEFF/, ''));
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
    displayName: 'Wintage вЂ” Win95 Vintage Themes',
    description: 'Sixteen switchable Windows 95 palettes generated from the Wintage theme packs.',
    // One version number for the whole project, taken from the userscript header
    // rather than kept separately вЂ” two version fields drift, and the second one
    // is always the one nobody remembers to bump.
    version: VERSION,
    publisher: 'vacterro',
    engines: { vscode: '^1.60.0' },
    categories: ['Themes'],
    contributes: { themes: contributes }
  }, null, 2) + '\n');
}

// в”Ђв”Ђв”Ђ TARGET: electron в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
// Claude Code's desktop app, FreeBuff and codenomad are all Electron, which means
// their UI is a web page and the userscript's own stylesheet already knows how to
// impose UI.md on one. So the CSS is not rewritten here вЂ” it is EXTRACTED from
// wintage.user.js and its ${T.x} interpolations resolved against the palette.
// Duplicating it would mean every bevel fix, scrollbar rebuild and type-ladder
// correction had to be made twice, and the second copy would rot.
//
// What does NOT come along is the repainter (the JS that fixes what CSS cannot win
// on arbitrary sites). For a single known application that is a much smaller loss
// than it is on the open web, and it keeps the injected payload to one stylesheet.
function buildElectron(packs) {
  const src = fs.readFileSync(path.join(ROOT, 'wintage.user.js'), 'utf8');

  const literal = name => {
    const decl = 'const ' + name + ' = `';
    const i = src.indexOf(decl);
    if (i < 0) throw new Error(name + ' not found in wintage.user.js');
    const start = i + decl.length;
    return src.slice(start, start + /\n[ \t]*`;/.exec(src.slice(start)).index);
  };
  // The two bevel constants and the font stack are themselves template literals
  // referencing tokens, so they are resolved first and then substituted.
  const constLiteral = name => {
    const m = new RegExp('const ' + name + " = [`']([^`']*)[`']").exec(src);
    if (!m) throw new Error(name + ' not found in wintage.user.js');
    return m[1];
  };

  const globalCss = literal('GLOBAL_CSS');
  // Never concatenated onto the document sheet -- see the long note below for why
  // that was incapable of working. It is carried into the repainter payload
  // instead, which injects it into each shadow root it pierces, one at a time.
  const shadowCss = literal('SHADOW_CSS');
  const bevels = {
    B_OUTER: constLiteral('B_OUTER'),
    B_INNER: constLiteral('B_INNER'),
    FONT: constLiteral('FONT')
  };
  bevels.B_SUNK = bevels.B_INNER;

  const shimTemplate = fs.readFileSync(path.join(DESKTOP, 'targets', 'electron', 'shim.cjs'), 'utf8');

  const repStartMarker = '// --- REPAINTER START ---';
  const repEndMarker = '// --- REPAINTER END ---';
  const repStart = src.indexOf(repStartMarker);
  const repEnd = src.indexOf(repEndMarker);
  if (repStart < 0 || repEnd < 0) throw new Error('repainter markers missing in wintage.user.js');
  const repainterBody = src.slice(repStart + repStartMarker.length, repEnd);

  // ─── THE PRELUDE MUST KEEP UP WITH THE USERSCRIPT ──────────────────────────
  // The extracted body is a slice out of the middle of an IIFE, so every helper it
  // reads from the enclosing scope -- T, elev, contrast, injectStyle -- has to be
  // re-declared by the shim's prelude. Nothing about moving a helper across the
  // REPAINTER marker looks dangerous while doing it, and the cost lands far away:
  // a ReferenceError thrown inside executeJavaScript, which the user experiences as
  // "the theme does nothing" with no error anywhere they would think to look.
  //
  // So the build refuses to ship that. Names declared at the top level of the
  // userscript's IIFE, referenced by the body, and NOT provided by the prelude are
  // a hard failure here.
  const preludeStart = shimTemplate.indexOf('const REPAINTER_FIX = `(() => {');
  const preludeEnd = shimTemplate.indexOf('` + REPAINTER_BODY + `');
  if (preludeStart < 0 || preludeEnd < 0) throw new Error('repainter prelude not found in shim template');
  const prelude = shimTemplate.slice(preludeStart, preludeEnd);
  const declared = (text, re) => new Set([...text.matchAll(re)].map(m => m[1]));

  const provided = declared(prelude, /(?:const|let|var|function)\s+([A-Za-z_$][\w$]*)/g);
  const outer = new Set([
    ...declared(src.slice(0, repStart) + src.slice(repEnd), /^ {2}(?:const|let|var)\s+([A-Za-z_$][\w$]*)/gm),
    ...declared(src.slice(0, repStart) + src.slice(repEnd), /^ {2}function\s+([A-Za-z_$][\w$]*)/gm)
  ]);
  const bodyCode = stripNonCode(repainterBody);
  const bodyOwn = new Set([
    ...declared(bodyCode, /(?:const|let|var)\s+([A-Za-z_$][\w$]*)/g),
    ...declared(bodyCode, /function\s+([A-Za-z_$][\w$]*)/g)
  ]);
  const orphans = [...outer].filter(n =>
    !provided.has(n) && !bodyOwn.has(n) &&
    new RegExp('(^|[^\\w$.])' + n + '([^\\w$]|$)').test(bodyCode));
  if (orphans.length) {
    throw new Error('repainter body reads ' + orphans.join(', ') + ' from the userscript\'s outer scope, ' +
      'and the shim prelude does not define ' + (orphans.length > 1 ? 'them' : 'it') + '. ' +
      'Add ' + (orphans.length > 1 ? 'them' : 'it') + ' to desktop/targets/electron/shim.cjs or move the ' +
      'declaration inside the REPAINTER markers.');
  }

  // A stray ${T.x} inside the body would be eaten by resolve() below and turned
  // into a bare colour in the middle of JS. Nothing in the repainter needs one, and
  // if that changes it should be a decision, not a surprise.
  const collides = /\$\{(T\.\w+|B_OUTER|B_INNER|B_SUNK|FONT|VERSION)\}/.exec(repainterBody);
  if (collides) throw new Error('repainter body contains a build placeholder: ' + collides[0]);

  // JSON, not paste. See the note in the shim template: pasted into a template
  // literal, every \d in the repainter's regexes silently becomes a d.
  for (const marker of ['/* __REPAINTER__ */ ""', '/* __SHADOW_CSS__ */ ""']) {
    if (!shimTemplate.includes(marker)) throw new Error('shim template marker missing: ' + marker);
  }
  for (const pack of packs) {
    const resolve = text => text
      .replace(/\$\{(B_OUTER|B_INNER|B_SUNK|FONT)\}/g, (m, k) => bevels[k])
      .replace(/\$\{T\.(\w+)\}/g, (m, k) => {
        if (!(k in pack.tokens)) throw new Error('unknown token T.' + k);
        return pack.tokens[k];
      })
      .replace(/\$\{DARK \? '(\w+)' : '(\w+)'\}/g, '$1')
      .replace(/\$\{VERSION\}/g, VERSION);
    // Two passes: the bevel constants themselves contain ${T.x}.
    // GLOBAL_CSS ONLY. SHADOW_CSS used to be concatenated on here, and that was a
    // straight mistake: the shim delivers this through insertCSS, which produces a
    // DOCUMENT stylesheet, and a document stylesheet cannot reach inside a shadow
    // root at all. So every SHADOW_CSS rule shipped here was incapable of doing the
    // job it was written for, and could only ever match light-DOM elements it was
    // never designed for -- with no guard, because inside a shadow tree the cases it
    // would need to guard against do not exist.
    //
    // Both of the bugs that cost this project a long debugging session came from
    // exactly that. Its `[class] { color: inherit }` matched <html class="…"> and
    // handed the document root an inherit with nothing above it, computing to black
    // and dragging every descendant down with it. Its `background-color:
    // transparent` on the same selector wiped the background off floating panels, so
    // menus and popovers rendered see-through with the text behind them showing
    // straight through. Neither could happen in the shadow tree it was written for.
    //
    // The userscript still injects SHADOW_CSS where it belongs -- into shadow roots,
    // one at a time. That path is unaffected; this one just stops pretending it is
    // the same thing.
    const css = resolve(resolve(globalCss));
    const left = /\$\{/.exec(css);
    if (left) throw new Error('unresolved placeholder in ' + pack.slug + ' css near: ' + css.slice(left.index, left.index + 60));
    emit(path.join(OUT, 'electron', pack.slug, 'wintage.css'),
      '/* Wintage ' + pack.label + ' - generated from wintage.user.js v' + VERSION + '. Do not edit. */\n' + css + '\n');
    // The shim is loaded by Electron's MAIN process, before any window exists. A
    // syntax error there is not a broken theme, it is an application that will not
    // start -- which is exactly what shipped once, from a template literal closed
    // early by a backtick. Both gates are cheap and neither is optional.
    // SHADOW_CSS is resolved BEFORE it is JSON-encoded, not after. ${FONT} expands
    // to a stack containing "MS Sans Serif" -- double quotes, dropped raw into the
    // middle of an already-quoted JSON string, which ends it early. Encoding last is
    // the only order that can be right.
    const shimOut = resolve(shimTemplate
      .replace('/* __REPAINTER__ */ ""', () => JSON.stringify(repainterBody))
      .replace('/* __SHADOW_CSS__ */ ""', () => JSON.stringify(resolve(resolve(shadowCss)))));
    const stray = /\$\{/.exec(shimOut);
    if (stray) throw new Error('unresolved placeholder in ' + pack.slug + ' shim near: ' + shimOut.slice(stray.index, stray.index + 60));
    try {
      new vm.Script(shimOut, { filename: pack.slug + '/shim.cjs' });
    } catch (e) {
      throw new Error('generated shim for ' + pack.slug + ' does not parse: ' + e.message);
    }
    emit(path.join(OUT, 'electron', pack.slug, 'shim.cjs'), shimOut);
  }
}

// Comments, strings, template text and regex literals go before the free-identifier
// gate reads the repainter, because each of them can hold a word that looks exactly
// like a reference and is not one -- the body discusses GLOBAL_CSS and CSS_ONLY_MODE
// in prose, and a gate that cannot tell prose from code is a gate someone deletes.
function stripNonCode(src) {
  let out = '', i = 0, last = '';
  let depth = 0;                 // brace depth
  const tplStack = [];           // brace depth at which each open ${ } started
  let inTpl = false;
  const push = ch => { out += ch; if (!/\s/.test(ch)) last = ch; };
  // `return /x/` is a regex; `a / b` is division. The difference is the token
  // before the slash, so keywords that can precede a value are checked too.
  const KEYWORD = /(?:^|[^\w$])(return|typeof|case|in|of|delete|void|instanceof|new|do|else|yield|await)\s*$/;

  while (i < src.length) {
    const c = src[i], d = src[i + 1];

    if (inTpl) {
      if (c === '\\') { i += 2; continue; }
      if (c === '`') { inTpl = false; i++; push('0'); continue; }
      if (c === '$' && d === '{') { tplStack.push(depth); depth++; inTpl = false; i += 2; out += ' '; continue; }
      if (c === '\n') out += '\n';
      i++; continue;
    }

    if (c === '/' && d === '/') { while (i < src.length && src[i] !== '\n') i++; continue; }
    if (c === '/' && d === '*') { i += 2; while (i < src.length && !(src[i] === '*' && src[i + 1] === '/')) i++; i += 2; continue; }
    if (c === '"' || c === "'") {
      const q = c; i++;
      while (i < src.length && src[i] !== q) { if (src[i] === '\\') i++; i++; }
      i++; push('0'); continue;
    }
    if (c === '`') { inTpl = true; i++; continue; }
    if (c === '/' && (!/[\w$)\]]/.test(last) || KEYWORD.test(out))) {
      i++;
      let cls = false;
      while (i < src.length) {
        const r = src[i];
        if (r === '\\') { i += 2; continue; }
        if (r === '\n') break;
        if (r === '[') cls = true;
        else if (r === ']') cls = false;
        else if (r === '/' && !cls) { i++; break; }
        i++;
      }
      while (i < src.length && /[a-z]/.test(src[i])) i++;   // flags
      push('0'); continue;
    }
    if (c === '{') depth++;
    if (c === '}') {
      if (tplStack.length && depth === tplStack[tplStack.length - 1] + 1) {
        tplStack.pop(); depth--; inTpl = true; i++; out += ' '; continue;
      }
      depth--;
    }
    push(c); i++;
  }
  return out;
}

// в”Ђв”Ђв”Ђ TARGET: browser в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
// A Chromium theme so the browser's own chrome matches the pages the userscript is
// repainting. Its colours are RGB triples, not hex, so the fill happens on the hex
// and is converted after -- a `${token}` inside a JSON array would not survive
// JSON.parse in the first place.
function buildBrowser(packs) {
  const template = JSON.parse(fs.readFileSync(path.join(DESKTOP, 'targets', 'browser', 'template.json'), 'utf8').replace(/^\uFEFF/, ''));
  const toRgb = h => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];

  for (const pack of packs) {
    const colors = {};
    for (const [k, v] of Object.entries(template.colors)) {
      const filled = fill(v, pack.tokens, { __file: 'browser/template.json' });
      colors[k] = toRgb(filled);
    }
    const manifest = {
      manifest_version: 3,
      version: VERSION,
      name: 'Wintage ' + pack.label,
      description: 'Wintage ' + pack.label + ' for the browser chrome. Companion to the Wintage userscript.',
      theme: { colors, properties: template.properties }
    };
    emit(path.join(OUT, 'browser', pack.slug, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
  }
}

// ─── TARGET: obsidian ────────────────────────────────────────────────────────
// A community theme, one per palette, installed per-vault into
// <vault>/.obsidian/themes/. Same shape as the VS Code target: it lives in the
// user's own vault, so an Obsidian update cannot remove it, and Obsidian keeps
// every installed theme so all palettes coexist and the user picks in Appearance.
// The template was derived from the hand-written VintageWin95 theme already in the
// vault, each hex replaced by the token whose value it equalled -- the same
// author-mapping-re-tinted approach the VS Code target uses.
function buildObsidian(packs) {
  const template = fs.readFileSync(path.join(DESKTOP, 'targets', 'obsidian', 'template.css'), 'utf8');
  for (const pack of packs) {
    const name = 'Wintage ' + pack.label;
    const css = fill(template, pack.tokens, { label: name, __file: 'obsidian/template.css' });
    const left = /\$\{/.exec(css);
    if (left) throw new Error('unresolved placeholder in obsidian ' + pack.slug + ' near: ' + css.slice(left.index, left.index + 60));
    const dir = path.join(OUT, 'obsidian', pack.slug);
    emit(path.join(dir, 'theme.css'), css);
    emit(path.join(dir, 'manifest.json'), JSON.stringify({
      name, version: VERSION, minAppVersion: '0.16.0', author: 'Wintage', authorUrl: 'https://github.com/vacterro/Wintage'
    }, null, 2) + '\n');
  }
}

// ─── TARGET: OBS Studio ─────────────────────────────────────────────────────
// OBS 30.2+ composes .ovt variants over a maintained base theme. Extending Yami
// Classic keeps new OBS widgets covered while Wintage owns the palette, Verdana,
// square corners and bevel states. One stable ID lets repainting replace the file
// in place instead of leaving a dead dropdown entry per palette.
function buildObs(packs) {
  const template = fs.readFileSync(path.join(DESKTOP, 'targets', 'obs', 'template.ovt'), 'utf8');
  for (const pack of packs) {
    const theme = fill(template, pack.tokens, { label: pack.label, __file: 'obs/template.ovt' });
    const left = /\$\{/.exec(theme);
    if (left) throw new Error('unresolved placeholder in obs ' + pack.slug + ' near: ' + theme.slice(left.index, left.index + 60));
    emit(path.join(OUT, 'obs', pack.slug, 'Wintage.ovt'), theme);
  }
}

// ─── TARGET: Windows system theme ───────────────────────────────────────────
// The generated file owns only Windows' colour/mode sections. At install time it
// is merged over the user's active .theme, preserving wallpaper, sounds and desktop
// icons while selecting the user's ___CURRENT___ cursor scheme. Microsoft documents .theme as INI and these sections as
// the supported colour/visual-style surface; no private msstyles is replaced.
function buildWindows(packs) {
  const template = fs.readFileSync(path.join(DESKTOP, 'targets', 'windows', 'template.theme'), 'utf8');
  const rgb = hex => [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16)).join(' ');
  for (const pack of packs) {
    const context = { label: pack.label, __file: 'windows/template.theme' };
    for (const [name, value] of Object.entries(pack.tokens)) {
      context[name + 'Rgb'] = rgb(value);
      context[name + 'Hex'] = value.slice(1).toUpperCase();
    }
    const theme = fill(template, pack.tokens, context);
    const left = /\$\{/.exec(theme);
    if (left) throw new Error('unresolved placeholder in windows ' + pack.slug + ' near: ' + theme.slice(left.index, left.index + 60));
    emit(path.join(OUT, 'windows', pack.slug, 'Wintage.theme'), theme);
  }
}

// Renaming or removing a palette used to leave its output behind forever: the
// emit() path only ever writes, so desktop/out/<target>/nomadcode survived the
// rename to codenomad and would have been installed as a ghost theme. Prune any
// per-slug output directory whose slug is not a current pack, so the tree always
// reflects themes/ exactly.
function prune(packs) {
  const live = new Set(packs.map(p => p.slug));
  for (const target of ['electron', 'browser', 'obsidian', 'obs', 'windows']) {
    const dir = path.join(OUT, target);
    if (!fs.existsSync(dir)) continue;
    for (const slug of fs.readdirSync(dir)) {
      if (live.has(slug)) continue;
      if (checkOnly) { console.error('build-desktop: ORPHAN ' + path.relative(ROOT, path.join(dir, slug))); stale++; continue; }
      fs.rmSync(path.join(dir, slug), { recursive: true, force: true });
      console.log('build-desktop: pruned orphan ' + target + '/' + slug);
      wrote++;
    }
  }
}

const packs = loadPacks();
buildVscode(packs);
buildElectron(packs);
buildBrowser(packs);
buildObsidian(packs);
buildObs(packs);
buildWindows(packs);
prune(packs);

if (stale) { console.error('\n' + stale + ' output(s) out of date вЂ” run `node tools/build-desktop.js`'); process.exit(1); }
console.log('build-desktop: ' + (wrote ? wrote + ' file(s) written' : 'everything up to date') +
  ' (' + packs.length + ' palette(s): ' + packs.map(p => p.slug).join(', ') + ')');
