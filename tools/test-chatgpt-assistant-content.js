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
  /* Rich embed surfaces: stock white cards, chips, anchor cards, tool panels.
     Generated atomic class on purpose: the fix must not depend on it. */
  .x-a1b2c3d4 { background-color: rgb(255, 255, 255); color: rgb(17, 24, 39); border-radius: 12px; padding: 8px; }
  .markdown-card-wrapper { background-color: rgb(255, 255, 255); color: rgb(17, 24, 39); border-radius: 12px; padding: 8px; margin: 8px 0; }
  .citation-chip { background-color: rgb(255, 255, 255); color: rgb(17, 24, 39); border-radius: 8px; padding: 1px 6px; }
  a.anchor-card { display: block; background-color: rgb(255, 255, 255); border-radius: 12px; padding: 8px; margin: 8px 0; }
  section.tool-panel { background-color: rgb(255, 255, 255); color: rgb(17, 24, 39); border-radius: 12px; padding: 8px; margin: 8px 0; }
  /* Intentional semantic surfaces (T-975): an orange banner with an ARIA role,
     a blue code-line div inside the code block, a purple details panel. */
  .callout-banner { background-color: rgb(245, 158, 11); color: rgb(255, 255, 255); border-radius: 12px; padding: 8px; margin: 8px 0; }
  .code-line { background-color: rgb(29, 78, 216); color: rgb(219, 234, 254); border-radius: 4px; padding: 2px 6px; }
  .details-panel { background-color: rgb(76, 29, 149); color: rgb(237, 233, 254); border-radius: 8px; padding: 8px; }
  /* Leaf text ownership (T-978): leaf nodes the shell colours independently.
     Stock white rgb(237, 237, 237) is the ChatGPT stock token these nodes
     carry on top of an already-palette ancestor. */
  .stock-leaf { color: rgb(237, 237, 237); }
  .stock-leaf-important { color: rgb(237, 237, 237) !important; }
  .stock-leaf-fill { color: rgb(209, 213, 219); -webkit-text-fill-color: rgb(237, 237, 237) !important; }
  .embed-label { color: rgb(237, 237, 237); }
  .attachment-label { color: rgb(237, 237, 237); }
  /* Page-header action surface (outside the assistant subtree). */
  #page-header { background-color: rgb(35, 32, 24); }
  #page-header .hdr-btn { background-color: rgb(107, 107, 107); color: rgb(237, 237, 237); -webkit-text-fill-color: rgb(237, 237, 237); }
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
          <div id="test-code-line" class="code-line"><span id="test-line-tok" class="hljs-keyword">kw</span></div>
          <button id="test-copy-btn">Copy code</button>
        </div>
        <p id="test-mark-p">Highlighted <mark id="test-mark">semantic mark</mark> text.</p>
        <!-- Rich embeds (T-974): stock white surfaces with generated atomic
             classes, wrapper divs, chips, anchor cards and tool panels. -->
        <div id="test-embed-atomic" class="x-a1b2c3d4"><p id="test-embed-atomic-p">Atomic card text</p></div>
        <div id="test-embed-wrapper" class="markdown-card-wrapper"><div id="test-embed-inner">Nested card body</div></div>
        <p id="test-cite-p">See <a id="test-citation" class="citation-chip" href="#">1</a> for details.</p>
        <a id="test-anchor-card" class="anchor-card" href="#"><span id="test-anchor-text">Search result card</span></a>
        <section id="test-tool-panel" class="tool-panel"><div id="test-tool-body">Tool result</div></section>
        <div id="test-banner" class="callout-banner" role="note">Intentional banner text</div>
        <details id="test-details"><summary id="test-summary">Details summary</summary><div id="test-details-panel" class="details-panel">Panel body</div></details>
        <!-- Leaf text ownership (T-978): independent colours and text-fills on
             leaf nodes the shell paints itself, not on a shared class. -->
        <p id="test-leaf-p">Prose with a <span id="test-leaf-span" class="stock-leaf">plain stock span</span>, an <span id="test-leaf-span-important" class="stock-leaf-important">important stock span</span> and an <span id="test-leaf-span-fill" class="stock-leaf-fill">text-fill override span</span>.</p>
        <div id="test-embed-label-box" class="markdown-card-wrapper"><span id="test-embed-label" class="embed-label">Embedded label</span></div>
        <div id="test-attachment"><span id="test-attachment-label" class="attachment-label">report-2026.pdf</span></div>
        <div id="test-media">
          <img id="test-img" src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='16' height='16'%3E%3Ccircle cx='8' cy='8' r='8' fill='%2300ff00'/%3E%3C/svg%3E" width="16" height="16" />
          <span id="test-provider-icon" class="provider-icon"></span>
        </div>
        <button id="test-action-btn">Regenerate</button>
      </div>
    </main>
    <header id="page-header"><button id="test-header-btn" class="hdr-btn"><span id="test-header-btn-label">Share</span></button></header>
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

  // T-978: -webkit-text-fill-color overrides color in Chromium, so BOTH must be
  // measured; a colour-only assertion passes on a white-fill leaf.
  const pair = (id) => {
    const s = cs(id);
    return s ? { color: s.color, fill: s.getPropertyValue('-webkit-text-fill-color') } : null;
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
    imgNaturalWidth: document.getElementById('test-img').naturalWidth,
    embedAtomicBg: cs('test-embed-atomic').backgroundColor,
    embedAtomicColor: cs('test-embed-atomic-p').color,
    embedAtomicIsWhite: isWhiteOrLight(cs('test-embed-atomic').backgroundColor),
    embedWrapperBg: cs('test-embed-wrapper').backgroundColor,
    embedInnerBg: cs('test-embed-inner').backgroundColor,
    embedWrapperIsWhite: isWhiteOrLight(cs('test-embed-wrapper').backgroundColor),
    citationBg: cs('test-citation').backgroundColor,
    citationColor: cs('test-citation').color,
    citationIsWhite: isWhiteOrLight(cs('test-citation').backgroundColor),
    anchorCardBg: cs('test-anchor-card').backgroundColor,
    anchorCardIsWhite: isWhiteOrLight(cs('test-anchor-card').backgroundColor),
    toolPanelBg: cs('test-tool-panel').backgroundColor,
    toolPanelIsWhite: isWhiteOrLight(cs('test-tool-panel').backgroundColor),
    bannerBg: cs('test-banner').backgroundColor,
    bannerColor: cs('test-banner').color,
    codeLineBg: cs('test-code-line').backgroundColor,
    codeLineColor: cs('test-code-line').color,
    lineTokColor: cs('test-line-tok').color,
    detailsPanelBg: cs('test-details-panel').backgroundColor,
    // T-978 leaf ownership pairs
    leafSpan: pair('test-leaf-span'),
    leafSpanImportant: pair('test-leaf-span-important'),
    leafSpanFill: pair('test-leaf-span-fill'),
    embedLabel: pair('test-embed-label'),
    attachmentLabel: pair('test-attachment-label'),
    headerBtn: pair('test-header-btn'),
    headerBtnLabel: pair('test-header-btn-label'),
    linkColor: cs('test-a').color,
    linkFill: cs('test-a').getPropertyValue('-webkit-text-fill-color'),
    syntaxKwFill: cs('test-kw').getPropertyValue('-webkit-text-fill-color'),
    syntaxStrColor: cs('test-str').color,
    syntaxStrFill: cs('test-str').getPropertyValue('-webkit-text-fill-color'),
    bannerFill: cs('test-banner').getPropertyValue('-webkit-text-fill-color'),
    codeLineFill: cs('test-code-line').getPropertyValue('-webkit-text-fill-color'),
    lineTokFill: cs('test-line-tok').getPropertyValue('-webkit-text-fill-color'),
  };
};

(async () => {
  const browser = await chromium.launch();

  const measure = async (wintageCss, fixtureHtml) => {
    const page = await browser.newPage({ viewport: { width: 800, height: 600 } });
    await page.setContent(fixtureHtml || FIXTURE, { waitUntil: 'load' });
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
  check('stock fixture paints white rich embed card (defect reproduced)', stock.embedAtomicIsWhite && stock.embedWrapperIsWhite && stock.citationIsWhite && stock.anchorCardIsWhite && stock.toolPanelIsWhite);
  check('stock fixture paints intentional semantic surfaces (banner/code-line/details reproduced)',
    stock.bannerBg === 'rgb(245, 158, 11)' && stock.codeLineBg === 'rgb(29, 78, 216)' && stock.detailsPanelBg === 'rgb(76, 29, 149)');
  // T-978 stock baseline: the leaf nodes ship stock white from the beginning.
  const STOCK_WHITE = 'rgb(237, 237, 237)';
  check('stock fixture paints white independent leaf text (T-978 defect reproduced)',
    stock.leafSpan.color === STOCK_WHITE && stock.leafSpanImportant.color === STOCK_WHITE &&
    stock.leafSpanFill.fill === STOCK_WHITE && stock.embedLabel.color === STOCK_WHITE &&
    stock.attachmentLabel.color === STOCK_WHITE && stock.headerBtnLabel.color === STOCK_WHITE &&
    stock.headerBtn.fill === STOCK_WHITE);

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

  console.log('\n-- rich embed surfaces (T-974): Golden Default (dark) --');
  check('rich embed atomic-class card is neutralized (no stock white)',
    !gdResult.embedAtomicIsWhite, `got ${gdResult.embedAtomicBg}`);
  check('rich embed atomic-class card text uses textPrimary',
    gdResult.embedAtomicColor === hexToRgb(gdTokens.textPrimary), `got ${gdResult.embedAtomicColor}`);
  check('rich embed wrapper div is neutralized (no stock white)',
    !gdResult.embedWrapperIsWhite, `got ${gdResult.embedWrapperBg}`);
  check('rich embed nested inner div is neutralized',
    gdResult.embedInnerBg === 'rgba(0, 0, 0, 0)', `got ${gdResult.embedInnerBg}`);
  check('citation chip is neutralized (no stock white)',
    !gdResult.citationIsWhite, `got ${gdResult.citationBg}`);
  check('citation chip keeps its own text colour (anchor contract)',
    gdResult.citationColor === hexToRgb(gdTokens.link), `got ${gdResult.citationColor}`);
  check('anchor-wrapped result card background is neutralized',
    !gdResult.anchorCardIsWhite, `got ${gdResult.anchorCardBg}`);
  check('anchor link color contract is preserved on the card',
    gdResult.linkColor === hexToRgb(gdTokens.link), `got ${gdResult.linkColor}`);
  check('tool-result panel is neutralized (no stock white)',
    !gdResult.toolPanelIsWhite, `got ${gdResult.toolPanelBg}`);
  check('second syntax token colour is preserved',
    gdResult.syntaxStrColor === 'rgb(206, 145, 120)', `got ${gdResult.syntaxStrColor}`);

  console.log('\n-- bounded neutralization (T-975): semantic surfaces preserved --');
  check('intentional orange banner keeps its background',
    gdResult.bannerBg === 'rgb(245, 158, 11)', `got ${gdResult.bannerBg}`);
  check('intentional banner keeps its own text colour',
    gdResult.bannerColor === 'rgb(255, 255, 255)', `got ${gdResult.bannerColor}`);
  check('nested code-block line wrapper keeps its styling',
    gdResult.codeLineBg === 'rgb(29, 78, 216)' && gdResult.codeLineColor === 'rgb(219, 234, 254)',
    `codeLineBg=${gdResult.codeLineBg} codeLineColor=${gdResult.codeLineColor}`);
  check('code token inside the line wrapper keeps its syntax colour',
    gdResult.lineTokColor === 'rgb(86, 156, 214)', `got ${gdResult.lineTokColor}`);
  check('details panel keeps its intended background',
    gdResult.detailsPanelBg === 'rgb(76, 29, 149)', `got ${gdResult.detailsPanelBg}`);

  console.log('\n-- leaf text ownership (T-978): Golden Default (dark) --');
  const gdTP = hexToRgb(gdTokens.textPrimary);
  check('independent stock leaf span uses textPrimary (colour)',
    gdResult.leafSpan.color === gdTP, `got ${gdResult.leafSpan.color}`);
  check('independent stock leaf span uses textPrimary (text-fill)',
    gdResult.leafSpan.fill === gdTP, `got ${gdResult.leafSpan.fill}`);
  check('!important stock leaf span is still overridden to textPrimary',
    gdResult.leafSpanImportant.color === gdTP && gdResult.leafSpanImportant.fill === gdTP,
    `color=${gdResult.leafSpanImportant.color} fill=${gdResult.leafSpanImportant.fill}`);
  check('stock -webkit-text-fill-color override is neutralized (colour AND fill)',
    gdResult.leafSpanFill.color === gdTP && gdResult.leafSpanFill.fill === gdTP,
    `color=${gdResult.leafSpanFill.color} fill=${gdResult.leafSpanFill.fill}`);
  check('rich-embed label uses textPrimary (colour AND fill)',
    gdResult.embedLabel.color === gdTP && gdResult.embedLabel.fill === gdTP,
    `color=${gdResult.embedLabel.color} fill=${gdResult.embedLabel.fill}`);
  check('attachment filename label uses textPrimary (colour AND fill)',
    gdResult.attachmentLabel.color === gdTP && gdResult.attachmentLabel.fill === gdTP,
    `color=${gdResult.attachmentLabel.color} fill=${gdResult.attachmentLabel.fill}`);
  check('page-header action button uses textPrimary (colour AND fill)',
    gdResult.headerBtn.color === gdTP && gdResult.headerBtn.fill === gdTP,
    `color=${gdResult.headerBtn.color} fill=${gdResult.headerBtn.fill}`);
  check('page-header action button label uses textPrimary',
    gdResult.headerBtnLabel.color === gdTP && gdResult.headerBtnLabel.fill === gdTP,
    `color=${gdResult.headerBtnLabel.color} fill=${gdResult.headerBtnLabel.fill}`);
  // Intentional colours must survive the leaf rule.
  check('anchor link contract is preserved on leaf-wrapped cards',
    gdResult.linkColor === hexToRgb(gdTokens.link) && gdResult.linkFill === hexToRgb(gdTokens.link),
    `color=${gdResult.linkColor} fill=${gdResult.linkFill}`);
  check('syntax highlighting tokens keep their colour AND fill',
    gdResult.syntaxKwColor === 'rgb(86, 156, 214)' &&
    gdResult.syntaxKwFill === 'rgb(86, 156, 214)' &&
    gdResult.syntaxStrColor === 'rgb(206, 145, 120)' &&
    gdResult.syntaxStrFill === 'rgb(206, 145, 120)');
  check('intentional banner keeps its background, colour and fill',
    gdResult.bannerBg === 'rgb(245, 158, 11)' && gdResult.bannerColor === 'rgb(255, 255, 255)' &&
    gdResult.bannerFill === 'rgb(255, 255, 255)');
  check('code-line wrapper/details panel keep their intentional colours',
    gdResult.codeLineBg === 'rgb(29, 78, 216)' && gdResult.codeLineColor === 'rgb(219, 234, 254)' &&
    gdResult.codeLineFill === 'rgb(219, 234, 254)' &&
    gdResult.detailsPanelBg === 'rgb(76, 29, 149)');

  console.log('\n-- additional dark palette: Claude Code --');
  const ccTokens = parsePaletteTokens('claudecode');
  const ccResolved = resolveCss(FAST_CSS_RAW, ccTokens, true);
  const ccResult = await measure(ccResolved);
  check('Claude Code: table cells use Claude Code backgroundSoft',
    ccResult.tdBg === hexToRgb(ccTokens.backgroundSoft));
  check('Claude Code: inline code uses Claude Code surface',
    ccResult.inlineCodeBg === hexToRgb(ccTokens.surface));
  check('Claude Code: no stock white survives', !ccResult.tdIsWhite && !ccResult.inlineCodeIsLight);
  check('Claude Code: rich embed card is neutralized', !ccResult.embedAtomicIsWhite);
  check('Claude Code: rich embed card text uses Claude Code textPrimary',
    ccResult.embedAtomicColor === hexToRgb(ccTokens.textPrimary));
  check('Claude Code: citation chip is neutralized', !ccResult.citationIsWhite);
  check('Claude Code: tool panel is neutralized', !ccResult.toolPanelIsWhite);
  check('Claude Code: leaf text ownership holds on every audit surface',
    ccResult.leafSpan.color === hexToRgb(ccTokens.textPrimary) && ccResult.leafSpan.fill === hexToRgb(ccTokens.textPrimary) &&
    ccResult.leafSpanImportant.color === hexToRgb(ccTokens.textPrimary) &&
    ccResult.leafSpanFill.fill === hexToRgb(ccTokens.textPrimary) &&
    ccResult.embedLabel.color === hexToRgb(ccTokens.textPrimary) &&
    ccResult.attachmentLabel.color === hexToRgb(ccTokens.textPrimary) &&
    ccResult.headerBtnLabel.color === hexToRgb(ccTokens.textPrimary) &&
    ccResult.bannerColor === 'rgb(255, 255, 255)');

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
  check('Vintage Classic: leaf text ownership holds (light palette polarity)',
    vcResult.leafSpan.color === hexToRgb(vcTokens.textPrimary) &&
    vcResult.leafSpan.fill === hexToRgb(vcTokens.textPrimary) &&
    vcResult.leafSpanFill.fill === hexToRgb(vcTokens.textPrimary) &&
    vcResult.attachmentLabel.color === hexToRgb(vcTokens.textPrimary) &&
    vcResult.headerBtnLabel.color === hexToRgb(vcTokens.textPrimary),
    `leafSpan=${vcResult.leafSpan.color}/${vcResult.leafSpan.fill}`);

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

  // RC5: Remove the T-974 rich-embed neutralization (block rule + anchor rule) -> white cards return
  const mutantNoEmbed = gdResolved.replace(
    /html\[data-w95-chatgpt="1"\] \[data-markdown-text-style="assistant-message"\] :where\(div, section[\s\S]*?\n  html\[data-w95-chatgpt="1"\] \[data-message-author-role="assistant"\] a\s*\{[^}]*\}/g,
    ''
  );
  check('RC5a: mutant actually removes the rich-embed block', !mutantNoEmbed.includes(':where(div, section'));
  const r5 = await measure(mutantNoEmbed);
  check('RC5: removing rich-embed repair restores stock white card', r5.embedAtomicIsWhite && r5.citationIsWhite && r5.anchorCardIsWhite && r5.toolPanelIsWhite);

  // RC6: Drop the named exclusions from the repair -> themed regressions (pre, code block)
  const mutantNoExclude = gdResolved
    // Robust to future selector edits: strip every exclusion clause after the
    // stable type list, not one hardcoded chain a later change would silently
    // stop matching (how a mutation control dies quiet).
    .replace(/:where\(div, section, article, aside, figure, fieldset\)[\s\S]*?\{/g,
      ':where(div, section, article, aside, figure, fieldset) {');
  const r6 = await measure(mutantNoExclude);
  // The NAMED code-block rules pin the container (compareBack !important) and
  // pre (transparent !important), so the exclusions can only be proven on a
  // target they do not cover: the line-wrapper div inside the code block.
  check('RC6: dropping the exclusions flattens the protected code-line wrapper',
    r6.codeLineBg === 'rgba(0, 0, 0, 0)' && r6.codeLineColor === hexToRgb(gdTokens.textPrimary),
    `codeLineBg=${r6.codeLineBg} codeLineColor=${r6.codeLineColor}`);
  check('RC6: with exclusions in place the same wrapper keeps its styling (control pair)',
    gdResult.codeLineBg === 'rgb(29, 78, 216)' && gdResult.codeLineColor === 'rgb(219, 234, 254)');

  // RC7: Scope - the same sheet on a NON-ChatGPT page leaves embed stock white
  const nonChatgptFixture = FIXTURE.replace('<html data-w95-chatgpt="1">', '<html>');
  const r7 = await measure(gdResolved, nonChatgptFixture);
  check('RC7: non-ChatGPT page keeps stock embed white (isolation)', r7.embedAtomicIsWhite && r7.citationIsWhite);

  // RC8: Static safety -- EXPLICIT rule discovery, not substring luck. The
  // old control sliced FAST_CSS_RAW at ':where(div, span', a string the
  // production selector never contains; indexOf returned -1, the slice was
  // empty and every banned-machinery assertion passed vacuously. Discovery
  // now has to locate a real rule, prove it non-empty and prove it is the
  // intended rule, and each audit is proven able to FAIL.
  const EMBED_ANCHOR = ':where(div, section, article, aside, figure, fieldset)';
  const extractEmbedRule = (css) => {
    const i = css.indexOf(EMBED_ANCHOR);
    if (i < 0) return null;
    const start = css.lastIndexOf('\n', i) + 1;
    const brace = css.indexOf('{', i);
    if (brace < 0) return null;
    const closeRe = /\n[ \t]*\}/g;
    closeRe.lastIndex = brace;
    const close = closeRe.exec(css);
    if (!close) return null;
    if (!close) return null;
    const text = css.slice(start, close.index + close[0].length);
    if (!text.trimStart().startsWith('html[data-w95-chatgpt="1"]')) return null;
    if (!text.includes('background-color: transparent !important')) return null;
    if (!text.includes('color: ${T.textPrimary} !important')) return null;
    return text;
  };
  const embedRule = extractEmbedRule(FAST_CSS_RAW);
  check('RC8a: rich-embed rule is discovered (non-empty, intended rule)',
    embedRule !== null && embedRule.length > 400,
    embedRule === null ? 'no rule matched' : 'len=' + embedRule.length);
  const bannedMachinery = (text) =>
    text.includes(':has(') || /\[class\*=/.test(text) || /(^|[\s>+~])\*/.test(text.split('{')[0]);
  check('RC8b: discovered rule carries no :has(), class-substring or universal',
    embedRule !== null && !bannedMachinery(embedRule));
  check('RC8c: rule discovery FAILS when the rich-embed block is removed',
    extractEmbedRule(mutantNoEmbed) === null);
  check('RC8d: injected :has() makes the banned-machinery audit fail',
    embedRule !== null && bannedMachinery(embedRule.replace('background-color: transparent', ':has(.x) background-color: transparent')));
  check('RC8e: injected class-substring makes the audit fail',
    embedRule !== null && bannedMachinery(embedRule.replace(EMBED_ANCHOR, '[class*="card"] ' + EMBED_ANCHOR)));
  check('RC8f: injected universal selector makes the audit fail',
    embedRule !== null && bannedMachinery(embedRule.replace('[data-markdown-text-style="assistant-message"] :where', '* [data-markdown-text-style="assistant-message"] :where')));

  // RC9: T-975 bounded neutralization. Dropping the protection clauses must
  // flatten the intentional surfaces; the positive assertions above are the
  // control pair proving the same gate passes with them in place.
  const protectionChain = ':not([role="note"]):not([role="status"]):not([role="alert"]):not(:is(pre, code, [data-markdown-copy="code-block"], details, button, .katex, .katex-display, [role="note"], [role="status"], [role="alert"]) :is(div, section, article, aside, figure, fieldset))';
  const mutantNoProtect = gdResolved.split(protectionChain).join('');
  check('RC9a: mutant actually removes the protection clauses',
    !mutantNoProtect.includes('[role="note"], [role="status"], [role="alert"]) :is(div, section, article, aside, figure, fieldset))') && mutantNoProtect !== gdResolved);
  const r9 = await measure(mutantNoProtect);
  check('RC9: without the protection clauses banner/code-line/details flatten (collateral reproduced)',
    r9.bannerBg === 'rgba(0, 0, 0, 0)' && r9.bannerColor === hexToRgb(gdTokens.textPrimary) &&
    r9.codeLineBg === 'rgba(0, 0, 0, 0)' && r9.codeLineColor === hexToRgb(gdTokens.textPrimary) &&
    r9.detailsPanelBg === 'rgba(0, 0, 0, 0)',
    `banner=${r9.bannerBg} codeLine=${r9.codeLineBg} details=${r9.detailsPanelBg}`);

  // RC10 (T-978): Explicit rule discovery for the leaf-ownership block. Removing
  // it must restore stock white on every audit surface, and discovery must be
  // able to FAIL (both directions), as RC8 established. The template literal is
  // CRLF on Windows, so every block terminator below is \r?\n-aware.
  const LEAF_ANCHOR = ':where(span, label, small, figcaption):not(:is(a, pre, code, kbd, samp';
  const leafRuleByAnchor = (css) => {
    const ruleRe = /\n[ \t]*html\[data-w95-chatgpt="1"\][^{}]*:where\(span, label, small, figcaption\)[\s\S]*?\{[^}]*\}/g;
    const hits = css.match(ruleRe);
    if (!hits) return null;
    const hit = hits.find(h => h.includes('-webkit-text-fill-color: currentColor !important') && h.includes('color: inherit !important'));
    return hit || null;
  };
  const leafRule = leafRuleByAnchor(gdResolved);
  check('RC10a: leaf-ownership rule is discovered (non-empty, intended rule)',
    typeof leafRule === 'string' && leafRule.includes(LEAF_ANCHOR), leafRule ? '' : 'no rule matched');
  const leafRuleCount = (gdResolved.match(/:where\(span, label, small, figcaption\):not\(/g) || []).length;
  check('RC10b: leaf-ownership rule is present on both assistant scopes + conversation turns',
    leafRuleCount === 3, 'count=' + leafRuleCount);
  // Remove the whole block (all three scopes) and prove RED.
  const mutantNoLeaf = gdResolved.replace(/\n[ \t]*html\[data-w95-chatgpt="1"\] \[data-markdown-text-style="assistant-message"\] :where\(span, label, small, figcaption\):not\([\s\S]*?\-webkit\-text\-fill\-color: currentColor !important;\r?\n[ \t]*\}/g,
    '\n');
  check('RC10c: mutant actually removes the leaf-ownership block',
    mutantNoLeaf !== gdResolved && !mutantNoLeaf.includes(LEAF_ANCHOR));
  // The page-header Share surface is owned by BOTH providers: the header rule
  // and the button-label descendant rule. Removing only one of them leaves the
  // other repainting the label, which is exactly how this defect shipped green.
  const mutantNoLeafProviders = mutantNoLeaf
    .replace(/\n[ \t]*html\[data-w95-chatgpt="1"\] button :where\(span, label, small, p, div\)[\s\S]*?\r?\n[ \t]*\}/g, '\n')
    .replace(new RegExp('\\n[ \\t]*html\\[data-w95-chatgpt="1"\\] header :is\\(button, \\[role="button"\\]\\) \\{[\\s\\S]*?\\r?\\n[ \\t]*\\}', 'g'), '\n');
  check('RC10e: mutant removes both header providers for the Share surface',
    !mutantNoLeafProviders.includes('header :is(button, [role="button"])') &&
    !mutantNoLeafProviders.includes('button :where(span, label, small, p, div)'));
  const r10 = await measure(mutantNoLeafProviders);
  check('RC10d: without leaf ownership the audit surfaces return stock white (RED)',
    r10.leafSpan.color === STOCK_WHITE && r10.leafSpanFill.fill === STOCK_WHITE &&
    r10.embedLabel.color === STOCK_WHITE && r10.attachmentLabel.color === STOCK_WHITE &&
    r10.headerBtnLabel.color === STOCK_WHITE,
    `leaf=${r10.leafSpan.color} embed=${r10.embedLabel.color} attach=${r10.attachmentLabel.color} hdr=${r10.headerBtnLabel.color}`);

  // RC11 (T-978): rule discovery itself can fail -- deleting the block breaks it.
  check('RC11a: discovery FAILS when the leaf block is removed', leafRuleByAnchor(mutantNoLeaf) === null);
  check('RC11b: injected :has() into the discovered block fails the machinery audit',
    leafRule !== null && /:has\(/.test((leafRule || '').replace('color: inherit !important', ':has(.x) color: inherit !important')));
  check('RC11c: injected class-substring into the discovered block fails the machinery audit',
    leafRule !== null && /\[class\*=/.test((leafRule || '').replace(':where(span, label', '[class*="stock"] :where(span, label')));
  check('RC11d: injected universal selector into the discovered block fails the machinery audit',
    leafRule !== null && /(^|[\s>+~])\*(?![a-zA-Z0-9_-])/.test((leafRule || '').replace(':where(span, label', '* :where(span, label')));

  // RC12 (T-978): header rule discovery is scoped to header landmarks only --
  // the same declaration outside a header is NOT the production rule.
  const HEADER_ANCHOR = 'html[data-w95-chatgpt="1"] header :is(button, [role="button"])';
  const headerRule = (() => {
    const i = gdResolved.indexOf(HEADER_ANCHOR);
    if (i < 0) return null;
    const start = gdResolved.lastIndexOf('\n', i) + 1;
    const close = /\r?\n[ \t]*\}/.exec(gdResolved.slice(i));
    if (!close) return null;
    const text = gdResolved.slice(start, i + close.index + close[0].length);
    if (!text.includes('-webkit-text-fill-color')) return null;
    return text;
  })();
  check('RC12a: page-header button rule is discovered (non-empty, intended rule)',
    headerRule !== null && headerRule.includes('header :is(button'), headerRule ? '' : 'no rule matched');
  const mutantNoHeader = gdResolved.replace(new RegExp('\\n[ \\t]*html\\[data-w95-chatgpt="1"\\] header :is\\(button, \\[role="button"\\]\\) \\{[\\s\\S]*?\\r?\\n[ \\t]*\\}', 'g'), '\n');
  check('RC12b: mutant actually removes the header rule', mutantNoHeader !== gdResolved && !mutantNoHeader.includes('header :is(button, [role="button"])'));
  const r12 = await measure(mutantNoHeader);
  check('RC12c: without the header rule the Share button returns stock white (RED)',
    r12.headerBtn.color === STOCK_WHITE, `got ${r12.headerBtn.color}`);

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
