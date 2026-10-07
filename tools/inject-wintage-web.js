#!/usr/bin/env node
'use strict';

// Puts Wintage on a LIVE tab without Tampermonkey, so the ChatGPT acceptance pass
// is self-sufficient.
//
// WHY THIS EXISTS. tools/inspect-web.js measures whether Wintage's stylesheet
// wins the cascade on a real chatgpt.com DOM. It deliberately installs nothing: it
// reads the <style data-w95="..."> sheets the userscript injects and toggles them
// off to attribute a colour. On a browser where the userscript is NOT installed it
// therefore prints "wintage : stamp=false sheets=0", and every mismatch after that
// is ChatGPT's own styling rather than the product's. Measured on this machine:
// an authenticated Chrome on 127.0.0.1:9222 serving two chatgpt.com conversation
// tabs, whose Tampermonkey profile has never been given wintage.user.js (its
// dashboard carries zero occurrences of "Wintage"). That is why the acceptance was
// operator-only, and why it sat blocked.
//
// THE CSS IS THE PRODUCT'S, NOT A COPY. Nothing here is hand-transcribed. Both
// template literals are read out of wintage.user.js and evaluated against the
// palette object the product itself declares, so the bytes that land on the page
// are the bytes ACTIVE_GLOBAL_CSS would produce for a chatgpt.com host -- which
// routes to CHATGPT_FAST_CSS and never to GLOBAL_CSS (wintage.user.js:2340). Change
// a token in the product and the live sheet changes with it, no edit here. The
// interpolation is the eval-of-a-template-literal pattern tools/test-shim-payloads.js
// already proves; the set of free identifiers is enumerated by a control rather
// than assumed, so a seventh one appearing upstream turns this file red instead of
// silently interpolating `undefined` into live CSS.
//
// WHAT IS NOT INJECTED. No MutationObserver, no DOM sweep, no CSSOM hover
// surgery: chatgpt.com runs CSS_ONLY_MODE (wintage.user.js:220), so the repainter is
// off in the product too and stays off here. The one piece of JavaScript installed
// is the attachShadow wrapper, which belongs to the shipped ChatGPT path rather than
// to a repair -- it is what lets a surface inside a shadow root be themed as it is
// created, in CSS-only mode too. No generated x* atomic class is referenced or
// named; every selector is the one the product authored.
//
// SCOPE. It themes the tab it is pointed at and nothing else: no cookie, no
// storage, no network, no document HTML, no textContent. It cannot carry message
// text out, because it never reads any.
//
// Usage:
//   node tools/inject-wintage-web.js chatgpt.com [--theme goldendefault] [--json]

const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, '..', 'wintage.user.js');

function source() { return fs.readFileSync(SRC, 'utf8'); }

// The raw, uninterpolated template literal. The closing backtick sits on a line of
// its own, which is what makes it findable without a regex that would have to
// escape every backtick inside the CSS.
function literal(src, name) {
  const decl = name + ' = `';
  const i = src.indexOf(decl);
  if (i < 0) throw new Error('template literal not found in wintage.user.js: ' + name);
  const start = i + decl.length;
  const m = /\n[ \t]*`;/.exec(src.slice(start));
  if (!m) throw new Error('unterminated template literal: ' + name);
  return src.slice(start, start + m.index);
}

// Brace-balanced, so THEMES is read whole rather than stopping at the first `};`
// that happens to appear inside a token block.
function objectLiteral(src, decl) {
  const i = src.indexOf(decl);
  if (i < 0) throw new Error('declaration not found: ' + decl);
  const start = src.indexOf('{', i);
  let depth = 0;
  for (let k = start; k < src.length; k++) {
    if (src[k] === '{') depth++;
    else if (src[k] === '}') { depth--; if (depth === 0) return src.slice(start, k + 1); }
  }
  throw new Error('unbalanced object literal: ' + decl);
}

// A whole `function name(...) { ... }` definition, header included, so the text
// can be dropped into a scope as a declaration. The parameter list is skipped
// before the body's brace is taken, because `lum` destructures: the first `{` after
// its header belongs to the pattern, not the body, and taking it yields `{ r, g, b }`.
function functionSource(src, name) {
  const head = 'function ' + name + '(';
  const i = src.indexOf(head);
  if (i < 0) throw new Error('function not found: ' + name);
  let k = i + head.length, pdepth = 0;
  for (; k < src.length; k++) {
    const ch = src[k];
    if (ch === '(') pdepth++;
    else if (ch === ')') { if (pdepth === 0) { k++; break; } pdepth--; }
  }
  // The body brace sits after the closing paren, usually across a space.
  while (k < src.length && src[k] !== '{') k++;
  if (k >= src.length) throw new Error('no body brace for function: ' + name);
  const start = k;
  let depth = 0;
  for (let k = start; k < src.length; k++) {
    if (src[k] === '{') depth++;
    else if (src[k] === '}') { depth--; if (depth === 0) return src.slice(i, k + 1); }
  }
  throw new Error('unbalanced function: ' + name);
}

// The interpolations both sheets depend on, read from the product rather than
// restated here: the palette object, the polarity test, the font stack and the
// three border strings the CSS inlines.
function bindings(themeId) {
  const src = source();
  const THEMES = eval('(' + objectLiteral(src, 'const THEMES =') + ')');
  const pack = THEMES[themeId];
  if (!pack) throw new Error('no such theme pack in wintage.user.js: ' + themeId);
  // hexLum closes over lum, so both declarations are evaluated inside one scope --
  // pulling hexLum out on its own would leave its lum reference unbound and throw at
  // build time rather than fail visibly in the sheet.
  const hexLum = eval('(function(){' + functionSource(src, 'lum') + '\n' +
    functionSource(src, 'hexLum') + '\nreturn hexLum;})()');
  const T = pack.tokens;
  const DARK = hexLum(T.background) < 0.18;          // wintage.user.js:503-505
  const FONT = eval('(' + /const FONT = ('[^']*')/.exec(src)[1] + ')');
  const bevel = names => names.map(n => T[n]).join(' ');
  const B_OUTER = `border: 2px solid !important; border-color: ${bevel(['bevelLight', 'borderDark', 'borderDark', 'bevelLight'])} !important; box-shadow: none !important;`;
  const B_INNER = `border: 2px solid !important; border-color: ${bevel(['borderDark', 'bevelLight', 'bevelLight', 'borderDark'])} !important; box-shadow: none !important;`;
  const B_SUNK = B_INNER;   // wintage.user.js:724
  const ver = /const W95_VERSION = '([^']*)'/.exec(src);
  return { T, DARK, FONT, B_OUTER, B_INNER, B_SUNK, VERSION: ver ? ver[1] : 'unknown' };
}

// The page-side expression. Idempotent: a second run finds its own sheet and says
// so rather than stacking a second copy, which would double the style cost and
// make the attribution in inspect-web ambiguous.
function buildInjectionExpression(themeId) {
  const b = bindings(themeId);
  // These six are the entire free-identifier set of the two sheets, and they have
  // to be in scope as LOCALS because eval resolves a template literal against the
  // scope it is written in -- the product's own scope, which does not exist here.
  const { T, DARK, FONT, B_OUTER, B_INNER, B_SUNK } = b;
  const css = eval('`' + literal(source(), 'CHATGPT_FAST_CSS') + '`');
  const shadowCss = eval('`' + literal(source(), 'CHATGPT_FAST_SHADOW_CSS') + '`');
  const meta = JSON.stringify({ theme: themeId, version: b.VERSION, dark: b.DARK, cssBytes: css.length, shadowBytes: shadowCss.length });
  return `(function(){
  var M = ${meta};
  var root = document.documentElement;
  if (!root) return JSON.stringify({ ok: false, why: 'no documentElement' });
  root.setAttribute('data-w95-chatgpt', '1');
  root.setAttribute('data-w95-dark', M.dark ? '1' : '0');
  root.setAttribute('data-w95-theme', M.theme);
  // The product stamps these in CSS_ONLY_MODE; carrying them keeps an injected page
  // indistinguishable from an installed one for anything that keys off them.
  root.setAttribute('data-w95-perf', 'css-only');
  root.setAttribute('data-w95-perf-reason', 'chatgpt-lean-css');
  try {
    root.style.setProperty('background-color', ${JSON.stringify(b.T.background)}, 'important');
    root.style.setProperty('color', ${JSON.stringify(b.T.textPrimary)}, 'important');
  } catch (e) { }

  var FAST = ${JSON.stringify(css)};
  var SHADOW = ${JSON.stringify(shadowCss)};
  var existing = document.querySelector('style[data-w95="global"]');
  var created = 0;
  if (!existing) {
    var s = document.createElement('style');
    s.setAttribute('data-w95', 'global');
    s.setAttribute('data-w95-ver', M.version);
    s.textContent = FAST;
    var host = document.head || root;
    host.insertBefore(s, host.firstChild);
    created = 1;
  }

  // Shadow roots cannot be reached by a document-level selector, and insertCSS
  // cannot cross the boundary either, so they take the sheet directly. Both the
  // already-open ones and any created later -- which is the same interception the
  // product installs (wintage.user.js:2344), and the only JavaScript here.
  function paintShadow(shadow) {
    try {
      if (!shadow || shadow.querySelector('style[data-w95="shadow"]')) return false;
      var el = document.createElement('style');
      el.setAttribute('data-w95', 'shadow');
      el.setAttribute('data-w95-ver', M.version);
      el.textContent = SHADOW;
      (shadow.head || shadow).appendChild(el);
      return true;
    } catch (e) { return false; }
  }
  var shadowed = 0;
  try {
    var all = document.querySelectorAll('*');
    for (var i = 0; i < all.length && i < 4000; i++) {
      if (all[i].shadowRoot && paintShadow(all[i].shadowRoot)) shadowed++;
    }
  } catch (e) { }
  if (typeof Element !== 'undefined' && Element.prototype && !Element.prototype.__w95Injected) {
    Element.prototype.__w95Injected = true;
    var orig = Element.prototype.attachShadow;
    Element.prototype.attachShadow = function (init) {
      var sh = orig.call(this, init);
      try { if (sh) paintShadow(sh); } catch (e) { }
      return sh;
    };
  }

  return JSON.stringify({
    ok: true, theme: M.theme, version: M.version, createdGlobalSheet: created,
    shadowRootsPainted: shadowed, cssBytes: FAST.length, shadowBytes: SHADOW.length
  });
})()`;
}

module.exports = { buildInjectionExpression, bindings, literal, objectLiteral, functionSource, source };

async function main(argv) {
  const { pageTargets, connect, debugPort } = require('./cdp-client.js');
  const { evaluate } = require('./inspect-web.js');
  const urlPart = argv[0];
  if (!urlPart || urlPart[0] === '-') {
    console.error('usage: node tools/inject-wintage-web.js <url-part> [--theme ID] [--json]');
    process.exit(1);
  }
  let theme = 'goldendefault', json = false;
  for (let i = 1; i < argv.length; i++) {
    if (argv[i] === '--theme') theme = argv[++i];
    else if (argv[i] === '--json') json = true;
  }
  // The port is explicit: cdp-client's listTargets defaults an omitted port to 80,
  // which is not a debugging port and fails as a connection refusal rather than as
  // "no such page".
  const target = (await pageTargets(debugPort())).find(t => (t.url || '').includes(urlPart));
  if (!target) {
    console.error('no page target matching ' + urlPart + ' is open over CDP');
    process.exit(1);
  }
  const cdp = connect(target);
  await cdp.ready;
  try {
    const result = JSON.parse(await evaluate(cdp, buildInjectionExpression(theme)));
    if (json) { console.log(JSON.stringify(result, null, 1)); }
    else {
      console.log('injected ' + result.theme + ' ' + result.version +
        ' into ' + urlPart + ' -- global sheet ' + (result.createdGlobalSheet ? 'created' : 'already present') +
        ', shadow roots painted ' + result.shadowRootsPainted +
        ', ' + result.cssBytes + ' + ' + result.shadowBytes + ' CSS bytes');
    }
    process.exitCode = result.ok ? 0 : 1;
  } finally {
    cdp.close();
  }
}

if (require.main === module) {
  main(process.argv.slice(2)).catch(e => { console.error('inject-wintage-web: ' + ((e && e.message) || e)); process.exit(1); });
}