#!/usr/bin/env node
// Provider/icon artwork preservation gate.
//
// THE DEFECT THIS EXISTS FOR. Wintage's generic control wipe flattens a button
// into ONE Win95 control instead of a pile of nested boxes, and it reached that
// goal by deleting ARTWORK as well as surfaces:
//
//   button:not(...) *:not(i):not([class*="icon" i]) ... { background-image: none }
//   button::before, button::after, ... { background: transparent }
//
// The descendant carve-outs only spare elements whose CLASS says "icon", and the
// pseudo-element rule used the `background` SHORTHAND, which resets
// background-image too. So an anonymous span carrying a logo as
// `background-image: url(...)`, and a `::before` glyph painted the same way, both
// came back as empty beveled boxes. Reported live: a Register/Sign-in dialog
// rendered all five of its social/provider sign-in methods as empty bevels.
//
// The repair is an INVARIANT, not a name list: the wipe may flatten nested
// background COLOR, border and shadow -- those are what make nested boxes look
// like separate controls -- but it must not blanket-delete imagery it cannot
// judge. CSS cannot distinguish a url() glyph from a gradient (the JS repainter
// keeps url() and kills only gradient FUNCTIONS for exactly that reason), so the
// CSS rule stops at the property whose meaning is unambiguous.
//
// WHY A BROWSER. Every assertion here is about the cascade that reaches the
// pixels: a selector can be present in the sheet and still lose to another rule
// (the status-dot defect was exactly that -- the guard existed and a sibling
// selector in the same comma list still won). So the sheet is injected into real
// Chromium and the COMPUTED style is read.
//
// RED CONTROLS. Each fixture case is proven able to fail by re-applying the
// pre-repair declaration to the shipped sheet and requiring that case to go red,
// so a future edit that reintroduces either wipe cannot pass this file.
//
// PRIVACY. The fixture is synthetic: no page is loaded, no URL is fetched, and
// the glyph "artwork" is an inline data: URI. Nothing about any account, page or
// user is read or emitted.

const fs = require('fs');
const path = require('path');

let chromium;
try {
  ({ chromium } = require('playwright'));
} catch (e) {
  console.error('FAIL: playwright is not installed in this checkout.');
  console.error('      It is a contributor test dependency declared in package.json');
  console.error('      ("devDependencies": { "playwright": "^1.62.1" }); neither the');
  console.error('      theme nor the installer ships it. Obtain it deterministically:');
  console.error('        npm ci');
  console.error('        npx playwright install chromium');
  console.error('      Underlying error: ' + (e && e.message ? e.message : e));
  process.exit(1);
}

const SRC = fs.readFileSync(path.join(__dirname, '..', 'wintage.user.js'), 'utf8');
let bad = 0;
function pass(label) { console.log('PASS: ' + label); }
function fail(label) { console.error('FAIL: ' + label); bad++; }
function check(label, ok, detail) {
  if (ok) { pass(label); return true; }
  fail(label + (detail ? ' -- ' + detail : ''));
  return false;
}

// ── The sheets the product actually ships ────────────────────────────────────
function templateLiteral(name) {
  const decl = 'const ' + name + ' = `';
  const i = SRC.indexOf(decl);
  if (i < 0) return '';
  const start = i + decl.length;
  const m = /\n[ \t]*`;/.exec(SRC.slice(start));
  return m ? SRC.slice(start, start + m.index) : '';
}
const GLOBAL_CSS_RAW = templateLiteral('GLOBAL_CSS');
const SHADOW_CSS_RAW = templateLiteral('SHADOW_CSS');
if (!GLOBAL_CSS_RAW || !SHADOW_CSS_RAW) {
  fail('GLOBAL_CSS / SHADOW_CSS template literals not found -- the shipped sheets are gone');
  console.error('\nprovider image preservation gate: 1 failure(s)');
  process.exit(1);
}

function goldenDefaultTokens() {
  const at = SRC.indexOf('goldendefault:');
  if (at < 0) return null;
  const open = SRC.indexOf('tokens: {', at);
  const close = SRC.indexOf('}', open);
  const out = {};
  for (const m of SRC.slice(open + 8, close).matchAll(/([A-Za-z][A-Za-z0-9]*)\s*:\s*'(#[0-9A-Fa-f]{6})'/g)) out[m[1]] = m[2];
  return out;
}
const TOKENS = goldenDefaultTokens();
if (!TOKENS || !TOKENS.backgroundSoft || !TOKENS.surfaceRaised) {
  fail('Golden Default tokens could not be parsed from wintage.user.js');
  console.error('\nprovider image preservation gate: 1 failure(s)');
  process.exit(1);
}
const hexToRgb = hex => {
  const n = parseInt(hex.replace('#', ''), 16);
  return 'rgb(' + ((n >> 16) & 255) + ', ' + ((n >> 8) & 255) + ', ' + (n & 255) + ')';
};
const SURFACE_RAISED = hexToRgb(TOKENS.surfaceRaised);
// The product's own status contract (see the .status-dot[data-kind="running"]
// rule): a dot inside a control is painted with the palette warning colour, and
// the wipe's state-marker exclusions exist so it is never flattened.
const WARNING = hexToRgb(TOKENS.warning);

// ${T.x} resolves to the real palette value. Any OTHER interpolation (the bevel
// macros, the font stack, the dark/light ternary) becomes `initial`: it cannot
// affect which background wins, and inventing a value for it would be guessing.
function resolve(css) {
  return css.replace(/\$\{([^}]*)\}/g, (whole, expr) => {
    const t = /^\s*T\.([A-Za-z][A-Za-z0-9]*)\s*$/.exec(expr);
    if (!t) return 'initial';
    if (!TOKENS[t[1]]) throw new Error('palette token T.' + t[1] + ' is not in Golden Default');
    return TOKENS[t[1]];
  });
}

// ── The fixture ──────────────────────────────────────────────────────────────
// The glyph is a real url() image, so `background-image: none` and the
// `background` shorthand both erase it -- which is the whole point.
const GLYPH = "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='16' height='16'%3E%3Crect width='16' height='16' fill='%23ff0000'/%3E%3C/svg%3E\")";

// What the SITE painted before Wintage runs. Each id is one case of the handoff's
// matrix:
//   logoDescendant  button > anonymous span whose provider glyph is a url() image
//   logoPseudo      button with a provider glyph on ::before
//   plainWrapper    ordinary nested wrapper with ONLY background-color decoration
//   statusDot       the existing status-dot / data-kind contract
const STOCK_CSS = `
  body { background: #ffffff; margin: 0; padding: 8px; }
  #logoButton { background-color: rgb(9, 9, 9); }
  #logoDescendant { display: inline-block; width: 16px; height: 16px; background-image: ${GLYPH}; }
  #plainWrapper { display: inline-block; width: 24px; height: 24px; background-color: rgb(12, 34, 56); border: 1px solid rgb(200, 200, 200); }
  #statusDot { display: inline-block; width: 6px; height: 6px; background-color: rgb(255, 0, 0); }
  #pseudoButton::before { content: ""; display: block; width: 16px; height: 16px; background-image: ${GLYPH}; }
  #pseudoButton { background-color: rgb(9, 9, 9); }
`;

const FIXTURE = `<!doctype html><html><head><meta charset="utf-8">
<style>${STOCK_CSS}</style></head>
<body>
  <button id="logoButton">
    <span id="logoDescendant"></span>
    <div id="plainWrapper"></div>
    <span id="statusDot" class="status-dot" data-kind="running"></span>
  </button>
  <button id="pseudoButton"></button>
  <div id="shadowHost"></div>
  <script>
    // The same three shapes inside a shadow root, styled by SHADOW_CSS. The
    // shadow sheet carried the identical shorthand wipe (the Electron shim
    // concatenates it into a whole-document stylesheet), so it gets the same
    // proof rather than an assumption. The shadow root paints its OWN glyph rule
    // first -- a shadow tree cannot be styled from the light DOM -- and the
    // sheet under test is appended after it, exactly as the product does.
    window.__w95buildShadow = function (shadowCss, glyph) {
      const root = document.getElementById('shadowHost').attachShadow({ mode: 'open' });
      const stock = document.createElement('style');
      stock.textContent = '#shadowPseudoButton::before { content: ""; display: block; ' +
        'width: 16px; height: 16px; background-image: ' + glyph + '; }';
      root.appendChild(stock);
      const b = document.createElement('button');
      b.id = 'shadowPseudoButton';
      root.appendChild(b);
      const s = document.createElement('style');
      s.textContent = shadowCss;
      root.appendChild(s);
    };
  </script>
</body></html>`;

// Structural identity + computed paint only. No text, no attributes beyond the
// ids the fixture itself created.
const PROBE = function () {
  const cs = (sel, pseudo) => {
    const el = document.querySelector(sel);
    return el ? getComputedStyle(el, pseudo || null) : null;
  };
  const shadow = document.getElementById('shadowHost').shadowRoot;
  const sBtn = shadow && shadow.getElementById('shadowPseudoButton');
  const sPseudo = sBtn ? getComputedStyle(sBtn, '::before') : null;
  const transparent = c => !c || c === 'transparent' ||
    /^rgba?\(\s*[\d.]+\s*,\s*[\d.]+\s*,\s*[\d.]+\s*,\s*0(\.0+)?\s*\)$/.test(c);
  const dColor = cs('#logoDescendant').backgroundColor;
  return {
    logoDescendantImage: cs('#logoDescendant').backgroundImage,
    logoDescendantFlattened: transparent(dColor),
    pseudoButtonGlyphImage: cs('#pseudoButton', '::before').backgroundImage,
    pseudoButtonSurface: cs('#pseudoButton').backgroundColor,
    plainWrapperColor: cs('#plainWrapper').backgroundColor,
    plainWrapperBorderTopWidth: cs('#plainWrapper').borderTopWidth,
    statusDotColor: cs('#statusDot').backgroundColor,
    shadowGlyphImage: sPseudo ? sPseudo.backgroundImage : null
  };
};

function hasUrl(v) { return typeof v === 'string' && /url\(/.test(v); }

const SHADOW_SHEET = resolve(SHADOW_CSS_RAW);

(async () => {
  const browser = await chromium.launch();
  const measure = async (css, shadowCss) => {
    const page = await browser.newPage({ viewport: { width: 640, height: 480 } });
    await page.setContent(FIXTURE, { waitUntil: 'load' });
    await page.evaluate(([c, g]) => window.__w95buildShadow(c, g), [shadowCss || SHADOW_SHEET, GLYPH]);
    if (css) await page.addStyleTag({ content: css });
    const out = await page.evaluate(PROBE);
    await page.close();
    return out;
  };

  const sheet = resolve(GLOBAL_CSS_RAW);

  // The stock build must already show the artwork, or every assertion below would
  // be a tautology (nothing was there to erase).
  console.log('-- fixture reproduces the live shapes --');
  const stock = await measure(null);
  check('stock build paints the descendant provider glyph (the fixture is not vacuous)',
    hasUrl(stock.logoDescendantImage), 'logoDescendantImage=' + stock.logoDescendantImage);
  check('stock build paints the ::before provider glyph (the fixture is not vacuous)',
    hasUrl(stock.pseudoButtonGlyphImage), 'pseudoGlyph=' + stock.pseudoButtonGlyphImage);
  check('stock build paints the nested wrapper decoration (the fixture is not vacuous)',
    stock.plainWrapperColor === 'rgb(12, 34, 56)', 'plainWrapper=' + stock.plainWrapperColor);
  check('stock build paints the status dot in the app colour (the fixture is not vacuous)',
    stock.statusDotColor === 'rgb(255, 0, 0)', 'statusDot=' + stock.statusDotColor);
  check('stock build paints the shadow-root ::before glyph (the fixture is not vacuous)',
    hasUrl(stock.shadowGlyphImage), 'shadowGlyph=' + stock.shadowGlyphImage);

  console.log('\n-- the four cases the repair has to keep apart --');
  const themed = await measure(sheet);

  // Case 1: button > anonymous span with a url() provider glyph.
  check('case 1: provider glyph on an anonymous button descendant SURVIVES the control wipe',
    hasUrl(themed.logoDescendantImage),
    'logoDescendantImage=' + themed.logoDescendantImage);
  // ...while the wipe still flattens the descendant's own surface colour.
  check('case 1: the same descendant still has its nested surface colour flattened',
    themed.logoDescendantFlattened,
    'flattened=' + themed.logoDescendantFlattened);

  // Case 2: provider glyph on the button's ::before.
  check('case 2: provider glyph on a button pseudo-element SURVIVES the paint wipe',
    hasUrl(themed.pseudoButtonGlyphImage),
    'pseudoGlyph=' + themed.pseudoButtonGlyphImage);
  // ...and the button itself is still one Win95 control.
  check('case 2: the button itself is still painted as the Wintage control surface',
    themed.pseudoButtonSurface === SURFACE_RAISED,
    'surface=' + themed.pseudoButtonSurface + ' expected ' + SURFACE_RAISED);

  // Case 3: an ordinary nested wrapper with ONLY background-color decoration.
  check('case 3: a nested wrapper with only colour decoration is still flattened',
    !themed.plainWrapperColor || /rgba?\([^)]*,\s*0\)$|^transparent$/.test(themed.plainWrapperColor),
    'plainWrapperColor=' + themed.plainWrapperColor);
  check('case 3: the nested wrapper border is still gone (the wipe is not weakened)',
    parseFloat(themed.plainWrapperBorderTopWidth || '1') === 0,
    'borderTopWidth=' + themed.plainWrapperBorderTopWidth);

  // Case 4: the status-dot / data-kind contract, unchanged.
  check('case 4: the status-dot / data-kind colour contract is preserved exactly',
    themed.statusDotColor === WARNING, 'statusDot=' + themed.statusDotColor + ' expected ' + WARNING);

  // Case 2 (shadow twin): the shadow sheet carried the same shorthand wipe.
  check('case 2s: the shadow-root ::before glyph also survives SHADOW_CSS',
    hasUrl(themed.shadowGlyphImage), 'shadowGlyph=' + themed.shadowGlyphImage);

  // ── RED controls ───────────────────────────────────────────────────────────
  // Each re-applies ONE pre-repair declaration to the shipped sheet and requires
  // the matching case to go red. The mutation is asserted to have applied: a
  // control that changed nothing proves nothing (VERIFY-ORACLE-01).
  console.log('\n-- red controls (each must go red) --');
  const controls = [
    {
      name: 'RC1 restore `background-image: none` on the button-descendant wipe',
      mutate: css => css.replace(/(button:not\(\.ytp-button\) \*:not\(i\)[^{}]*)\{\s*background-color: transparent !important;/,
        '$1{ background-color: transparent !important; background-image: none !important;'),
      caseOk: m => hasUrl(m.logoDescendantImage),
      caseName: 'case 1 (descendant glyph)'
    },
    {
      name: 'RC2 restore the `background` shorthand on the button pseudo-element wipe',
      // The selector list is multi-line in GLOBAL_CSS. The whole rule (selector
      // tail included) is replaced by a VALID one: a mutation that leaves a
      // dangling comma makes the rule unparseable, Chromium drops it, and the
      // control then passes for the wrong reason -- it proved the parser, not
      // the pre-repair declaration.
      mutate: css => css.replace(/button::before, button::after, \.btn::before, \.btn::after,[\s\S]{0,400}?\{[^}]*\}/,
        'button::before, button::after, .btn::before, .btn::after { background: transparent !important; box-shadow: none !important; filter: none !important; border: none !important; }'),
      caseOk: m => hasUrl(m.pseudoButtonGlyphImage),
      caseName: 'case 2 (::before glyph)'
    },
    {
      name: 'RC3 remove the non-icon descendant wipe entirely (the flattening it still owes)',
      mutate: css => css.replace(/button:not\(\.ytp-button\) \*:not\(i\)[^{}]*\{[^}]*\}/, ''),
      caseOk: m => /rgba?\([^)]*,\s*0\)$|^transparent$/.test(m.plainWrapperColor || '') &&
        parseFloat(m.plainWrapperBorderTopWidth || '1') === 0,
      caseName: 'case 3 (nested wrapper flattening)'
    },
    {
      name: 'RC4 restore the `background` shorthand on the shadow-DOM pseudo-element wipe',
      mutate: css => css.replace(/button::before, button::after, \.btn::before, \.btn::after \{ background-color: transparent !important/,
        'button::before, button::after, .btn::before, .btn::after { background: transparent !important'),
      caseOk: m => hasUrl(m.shadowGlyphImage),
      caseName: 'case 2s (shadow-root glyph)',
      shadowSheet: true
    }
  ];

  for (const c of controls) {
    // A control mutates exactly ONE shipped sheet and leaves the other as it
    // ships, so a red case can only come from the declaration it restored.
    const mutated = c.shadowSheet ? c.mutate(SHADOW_SHEET) : c.mutate(sheet);
    if (mutated === (c.shadowSheet ? SHADOW_SHEET : sheet)) {
      fail(c.name + ' -- RED control did not mutate the sheet, so it is inert and proves nothing');
      continue;
    }
    const m = await measure(c.shadowSheet ? sheet : mutated, c.shadowSheet ? mutated : null);
    check(c.name + ' -- ' + c.caseName + ' goes red', !c.caseOk(m), 'measured=' + JSON.stringify(m));
  }

  await browser.close();
  console.log('');
  if (bad) {
    console.error('provider image preservation gate: ' + bad + ' failure(s)');
    process.exit(1);
  }
  console.log('provider image preservation gate: PASS');
})().catch(e => {
  console.error('provider image preservation gate: harness error -- ' + (e && e.message ? e.message : e));
  process.exit(1);
});
