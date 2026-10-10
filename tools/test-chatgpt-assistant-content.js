#!/usr/bin/env node
'use strict';
// ChatGPT Assistant-Message Content Surface Regression Gate.
//
// WHY THIS FILE EXISTS.
// Proves that assistant message content (tables, inline code, blockquotes,
// code blocks, highlights, buttons) renders in the active Wintage palette
// with ZERO unintended white or incorrectly light-colored surfaces in real Chromium,
// while preserving legitimate imagery, syntax highlighting, and interaction.
//
// RED CONTROLS:
// 1. Removing the assistant-message content rules fails the gate.
// 2. Restoring a stock white background fails the gate.
// 3. Removing required palette mappings fails the gate.
// 4. Breaking protective image-preservation fails the gate.
// 5. Negative fixture proves that theming ancestor alone leaves child white.

const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const ROOT = path.join(__dirname, '..');
const USER_JS = path.join(ROOT, 'wintage.user.js');

let bad = 0;
function pass(label) { console.log('PASS: ' + label); }
function fail(label, detail) { console.error('FAIL: ' + label + (detail ? ' -- ' + detail : '')); bad++; }
function check(label, ok, detail) {
  if (ok) { pass(label); return true; }
  fail(label, detail);
  return false;
}

const SRC = fs.readFileSync(USER_JS, 'utf8');

function templateLiteral(src, name) {
  const decl = 'const ' + name + ' = `';
  const i = src.indexOf(decl);
  if (i < 0) return '';
  const start = i + decl.length;
  const m = /\n[ \t]*`;/.exec(src.slice(start));
  return m ? src.slice(start, start + m.index) : '';
}

const FAST_CSS_RAW = templateLiteral(SRC, 'CHATGPT_FAST_CSS');
if (!FAST_CSS_RAW) {
  fail('CHATGPT_FAST_CSS template literal not found in wintage.user.js');
  process.exit(1);
}

function parsePaletteTokens(paletteName) {
  const at = SRC.indexOf(paletteName + ':');
  if (at < 0) return null;
  const open = SRC.indexOf('tokens: {', at);
  const close = SRC.indexOf('}', open);
  const body = SRC.slice(open + 8, close);
  const out = {};
  for (const m of body.matchAll(/([A-Za-z][A-Za-z0-9]*)\s*:\s*'(#[0-9A-Fa-f]{6})'/g)) {
    out[m[1]] = m[2];
  }
  return out;
}

const hexToRgb = hex => {
  const n = parseInt(hex.replace('#', ''), 16);
  return 'rgb(' + ((n >> 16) & 255) + ', ' + ((n >> 8) & 255) + ', ' + (n & 255) + ')';
};

function resolveCss(css, tokens, isDark) {
  const FONT = 'Verdana, sans-serif';
  const B_OUTER = 'border: 2px solid;';
  const B_INNER = 'border: 2px solid;';
  const B_SUNK = B_INNER;
  const DARK = isDark;

  return css.replace(/\$\{([^}]*)\}/g, (whole, expr) => {
    const trimmed = expr.trim();
    if (trimmed === 'FONT') return FONT;
    if (trimmed === 'B_OUTER') return B_OUTER;
    if (trimmed === 'B_INNER') return B_INNER;
    if (trimmed === 'B_SUNK') return B_SUNK;
    if (trimmed.startsWith('DARK ?')) return isDark ? 'dark' : 'light';
    const t = /^T\.([A-Za-z][A-Za-z0-9]*)$/.exec(trimmed);
    if (t) {
      if (!tokens[t[1]]) throw new Error('Unknown palette token T.' + t[1]);
      return tokens[t[1]];
    }
    return 'initial';
  });
}

// Inline SVG data URL for image preservation test
const GLYPH = "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='16' height='16'%3E%3Crect width='16' height='16' fill='%23ff0000'/%3E%3C/svg%3E\")";

// Stock ChatGPT markdown styles that reproduce the reported defects
const STOCK_CSS = `
  html, body { margin: 0; padding: 0; background: #ffffff; color: #000000; font-family: sans-serif; }
  .thread-scroll-container { background-color: #000000; padding: 16px; }
  [data-markdown-text-style="assistant-message"] { background-color: transparent; color: #d1d5db; }
  p { margin: 8px 0; color: #d1d5db; }
  code:not(pre code) { background-color: rgb(243, 244, 246); color: rgb(31, 41, 55); padding: 2px 4px; }
  blockquote { border-left: 4px solid rgb(229, 231, 235); background-color: rgb(249, 250, 251); color: rgb(75, 85, 99); margin: 8px 0; padding: 4px 8px; }
  table { border-collapse: collapse; background-color: rgb(255, 255, 255); }
  th { background-color: rgb(249, 250, 251); color: rgb(17, 24, 39); border: 1px solid rgb(229, 231, 235); padding: 6px; }
  td { background-color: rgb(255, 255, 255); color: rgb(55, 65, 81); border: 1px solid rgb(229, 231, 235); padding: 6px; }
  pre { background-color: rgb(30, 30, 30); color: rgb(212, 212, 212); padding: 8px; }
  .hljs-keyword { color: rgb(86, 156, 214); }
  .hljs-string { color: rgb(206, 145, 120); }
  mark { background-color: rgb(255, 255, 0); color: rgb(0, 0, 0); }
  button { background-color: rgb(243, 244, 246); color: rgb(55, 65, 81); border: 1px solid rgb(209, 213, 219); padding: 4px 8px; }
  .provider-icon { display: inline-block; width: 16px; height: 16px; background-image: ${GLYPH}; }
`;

const FIXTURE = `<!doctype html>
<html data-w95-chatgpt="1">
<head>
  <meta charset="utf-8">
  <style id="stock-style">${STOCK_CSS}</style>
</head>
<body>
  <div class="thread-scroll-container">
    <main>
      <div data-markdown-text-style="assistant-message" id="assistant-root">
        <p id="test-p">Assistant prose with <strong id="test-strong">bold text</strong>, a <a id="test-a" href="#">link</a> and inline <code id="test-inline-code">let x = 1;</code>.</p>
        <blockquote id="test-blockquote"><p id="test-quote-p">Blockquote content</p></blockquote>
        <table id="test-table">
          <thead><tr><th id="test-th">Table Header</th></tr></thead>
          <tbody><tr><td id="test-td">Table Cell</td></tr></tbody>
        </table>
        <div id="test-code-block" data-markdown-copy="code-block">
          <pre id="test-pre"><code id="test-code"><span id="test-kw" class="hljs-keyword">function</span> <span id="test-str" class="hljs-string">test</span>() {}</code></pre>
          <button id="test-copy-btn">Copy code</button>
        </div>
        <p id="test-mark-p">Highlighted <mark id="test-mark">semantic mark</mark> text.</p>
        <div id="test-media">
          <img id="test-img" src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='16' height='16'%3E%3Ccircle cx='8' cy='8' r='8' fill='%2300ff00'/%3E%3C/svg%3E" width="16" height="16" />
          <span id="test-provider-icon" class="provider-icon"></span>
        </div>
        <button id="test-action-btn">Regenerate</button>
      </div>
    </main>
  </div>
</body>
</html>`;

const PROBE = () => {
  const cs = (id, pseudo) => {
    const el = document.getElementById(id);
    return el ? getComputedStyle(el, pseudo || null) : null;
  };

  const isWhiteOrLight = (rgbStr) => {
    if (!rgbStr) return false;
    const m = /rgb\((\d+),\s*(\d+),\s*(\d+)\)/.exec(rgbStr);
    if (!m) return false;
    const r = parseInt(m[1], 10), g = parseInt(m[2], 10), b = parseInt(m[3], 10);
    // Lum > 0.85 indicates bright white/light grey surface
    const lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
    return lum > 0.85;
  };

  return {
    tdBg: cs('test-td').backgroundColor,
    tdColor: cs('test-td').color,
    tdIsWhite: isWhiteOrLight(cs('test-td').backgroundColor),
    thBg: cs('test-th').backgroundColor,
    thIsLight: isWhiteOrLight(cs('test-th').backgroundColor),
    inlineCodeBg: cs('test-inline-code').backgroundColor,
    inlineCodeColor: cs('test-inline-code').color,
    inlineCodeIsLight: isWhiteOrLight(cs('test-inline-code').backgroundColor),
    blockquoteBg: cs('test-blockquote').backgroundColor,
    blockquoteBorderLeftColor: cs('test-blockquote').borderLeftColor,
    codeBlockBg: cs('test-code-block').backgroundColor,
    preBg: cs('test-pre').backgroundColor,
    syntaxKwColor: cs('test-kw').color,
    markBg: cs('test-mark').backgroundColor,
    markColor: cs('test-mark').color,
    markIsYellow: cs('test-mark').backgroundColor === 'rgb(255, 255, 0)',
    actionBtnBg: cs('test-action-btn').backgroundColor,
    actionBtnIsLight: isWhiteOrLight(cs('test-action-btn').backgroundColor),
    providerIconBgImage: cs('test-provider-icon').backgroundImage,
    imgNaturalWidth: document.getElementById('test-img').naturalWidth
  };
};

(async () => {
  const browser = await chromium.launch();

  const measure = async (wintageCss) => {
    const page = await browser.newPage({ viewport: { width: 800, height: 600 } });
    await page.setContent(FIXTURE, { waitUntil: 'load' });
    if (wintageCss) {
      await page.addStyleTag({ content: wintageCss });
    }
    const result = await page.evaluate(PROBE);
    await page.close();
    return result;
  };

  console.log('-- fixture reproduces stock white/light surfaces before repair --');
  const stock = await measure(null);
  check('stock fixture paints white table cells (defect reproduced)', stock.tdIsWhite);
  check('stock fixture paints light inline code background (defect reproduced)', stock.inlineCodeIsLight);
  check('stock fixture paints light table headers (defect reproduced)', stock.thIsLight);
  check('stock fixture paints bright yellow mark (defect reproduced)', stock.markIsYellow);
  check('stock fixture paints light action buttons (defect reproduced)', stock.actionBtnIsLight);

  console.log('\n-- repair verification: Golden Default (dark) --');
  const gdTokens = parsePaletteTokens('goldendefault');
  const gdResolved = resolveCss(FAST_CSS_RAW, gdTokens, true);
  const gdResult = await measure(gdResolved);

  check('table cells have Wintage backgroundSoft (no stock white)',
    gdResult.tdBg === hexToRgb(gdTokens.backgroundSoft),
    `expected ${hexToRgb(gdTokens.backgroundSoft)}, got ${gdResult.tdBg}`);
  check('table cells are NOT white', !gdResult.tdIsWhite);
  check('table headers have Wintage surface (no stock light)',
    gdResult.thBg === hexToRgb(gdTokens.surface),
    `expected ${hexToRgb(gdTokens.surface)}, got ${gdResult.thBg}`);
  check('inline code has Wintage surface background',
    gdResult.inlineCodeBg === hexToRgb(gdTokens.surface),
    `expected ${hexToRgb(gdTokens.surface)}, got ${gdResult.inlineCodeBg}`);
  check('inline code is NOT light/white', !gdResult.inlineCodeIsLight);
  check('inline code text color matches textPrimary',
    gdResult.inlineCodeColor === hexToRgb(gdTokens.textPrimary));
  check('blockquote has Wintage borderHighlight accent',
    gdResult.blockquoteBorderLeftColor === hexToRgb(gdTokens.borderHighlight));
  check('code block container has compareBack background',
    gdResult.codeBlockBg === hexToRgb(gdTokens.compareBack));
  check('syntax highlighting color is preserved on code tokens',
    gdResult.syntaxKwColor === 'rgb(86, 156, 214)',
    `expected rgb(86, 156, 214), got ${gdResult.syntaxKwColor}`);
  check('mark background is mapped to surfaceAlt (no bright yellow)',
    gdResult.markBg === hexToRgb(gdTokens.surfaceAlt) && !gdResult.markIsYellow);
  check('mark text color is mapped to borderHighlight',
    gdResult.markColor === hexToRgb(gdTokens.borderHighlight));
  check('assistant action button has Wintage surface background',
    gdResult.actionBtnBg === hexToRgb(gdTokens.surface));
  check('provider icon url() background image is preserved',
    gdResult.providerIconBgImage.includes('data:image/svg+xml'));
  check('image element remains intact', gdResult.imgNaturalWidth > 0);

  console.log('\n-- additional dark palette: Claude Code --');
  const ccTokens = parsePaletteTokens('claudecode');
  const ccResolved = resolveCss(FAST_CSS_RAW, ccTokens, true);
  const ccResult = await measure(ccResolved);
  check('Claude Code: table cells use Claude Code backgroundSoft',
    ccResult.tdBg === hexToRgb(ccTokens.backgroundSoft));
  check('Claude Code: inline code uses Claude Code surface',
    ccResult.inlineCodeBg === hexToRgb(ccTokens.surface));
  check('Claude Code: no stock white survives', !ccResult.tdIsWhite && !ccResult.inlineCodeIsLight);

  console.log('\n-- polarity verification: Vintage Classic (light) --');
  const vcTokens = parsePaletteTokens('vintageclassic');
  const vcResolved = resolveCss(FAST_CSS_RAW, vcTokens, false);
  const vcResult = await measure(vcResolved);
  check('Vintage Classic: table cells use Vintage Classic backgroundSoft',
    vcResult.tdBg === hexToRgb(vcTokens.backgroundSoft));
  check('Vintage Classic: inline code uses Vintage Classic surface',
    vcResult.inlineCodeBg === hexToRgb(vcTokens.surface));
  check('Vintage Classic: text is dark (polarity preserved)',
    vcResult.tdColor === hexToRgb(vcTokens.textPrimary) &&
    vcResult.inlineCodeColor === hexToRgb(vcTokens.textPrimary));

  console.log('\n-- red controls --');
  // RC1: Remove assistant-message content rules -> td returns stock white
  const mutantNoAssistant = gdResolved
    .replace(/html\[data-w95-chatgpt="1"\] table\s*\{[^}]*\}/g, '')
    .replace(/html\[data-w95-chatgpt="1"\] table td\s*\{[^}]*\}/g, '');
  const r1 = await measure(mutantNoAssistant);
  check('RC1: removing table repair rule restores stock white table cell', r1.tdIsWhite);

  // RC2: Restoring inline code stock background
  const mutantNoCode = gdResolved.replace(
    /html\[data-w95-chatgpt="1"\]\s*\[data-markdown-text-style="assistant-message"\]\s*code:not\(pre code\)[\s\S]*?\{[^}]*\}/g,
    ''
  );
  const r2 = await measure(mutantNoCode);
  check('RC2: removing inline code rule restores stock light inline code', r2.inlineCodeIsLight);

  // RC3: Breaking image preservation
  const mutantBrokenImg = gdResolved + '\nhtml[data-w95-chatgpt="1"] span { background-image: none !important; }\n';
  const r3 = await measure(mutantBrokenImg);
  check('RC3: image-wiping rule turns icon check red', !r3.providerIconBgImage || r3.providerIconBgImage === 'none');

  // RC4: Negative fixture - theming ancestor (.thread-scroll-container) alone leaves child td white
  const ancestorOnlyCss = 'html[data-w95-chatgpt="1"] .thread-scroll-container { background-color: rgb(35, 32, 24) !important; }';
  const r4 = await measure(ancestorOnlyCss);
  check('RC4: negative fixture proves theming ancestor alone leaves child td stock white', r4.tdIsWhite);

  await browser.close();

  if (bad > 0) {
    console.error('\ntest-chatgpt-assistant-content: ' + bad + ' failure(s)');
    process.exit(1);
  }
  console.log('\ntest-chatgpt-assistant-content gate: PASS');
  process.exit(0);
})().catch(e => {
  console.error('test-chatgpt-assistant-content unhandled error: ' + (e && e.stack ? e.stack : e));
  process.exit(1);
});
