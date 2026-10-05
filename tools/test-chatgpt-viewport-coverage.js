#!/usr/bin/env node
// ChatGPT viewport-owner coverage gate.
//
// WHY A STRING GATE CANNOT DO THIS JOB. test-chatgpt-2026.js proves the October
// selectors EXIST. It could stay green through the exact regression it was
// supposed to catch, because the regression is not a missing selector:
//
//     PARENT THEMED / CHILD VIEWPORT OWNER OPAQUE STOCK => visible page still wrong.
//
// Four ancestors are themed and all four are irrelevant, because the element
// that actually covers the middle of the screen is a CHILD of them and paints
// its own opaque background over everything above. Every parent-selector
// assertion still passes; the page is still stock charcoal. So this gate reads
// the CASCADE in a real browser and asks one question: what colour does a user
// actually see in the centre of the conversation viewport?
//
// The fixture is built from the shell structure the handoff recorded from live
// ChatGPT -- scroll container owning a header, the conversation region and the
// composer footer -- with the stock stylesheet declaring the scroll container
// opaque `#000000` exactly as the live page does. The Wintage sheet is injected
// AFTER the stock sheet, so specificity and source order are real cascade
// facts, not a string comparison.
//
// FOUR RED CONTROLS. Every assertion below is proven able to fail: the sheet is
// mutated by a single anchored replacement and the same assertions are required
// to go red against it. A control that cannot go red is a check that proves
// nothing (VERIFY-ORACLE-01).
//
// PRIVACY. The page probe emits structural identity only -- tag, element id,
// data-testid, role -- never text, never attribute values beyond those four,
// never conversation content. The fixture contains no user data to leak.

const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const SRC = fs.readFileSync(path.join(__dirname, '..', 'wintage.user.js'), 'utf8');
let bad = 0;

function pass(label) { console.log('PASS: ' + label); }
function fail(label) { console.error('FAIL: ' + label); bad++; }
function check(label, ok, detail) {
  if (ok) { pass(label); return true; }
  fail(label + (detail ? ' -- ' + detail : ''));
  return false;
}

// ── Read the sheet ChatGPT actually receives ─────────────────────────────────
// GLOBAL_CSS keeps a compatibility copy of the ChatGPT rules. If this gate read
// that copy it would validate a stylesheet the runtime never applies to
// chatgpt.com, which is how test-chatgpt-2026.js once stayed green against a
// fully stock page.
function templateLiteral(name) {
  const decl = 'const ' + name + ' = `';
  const i = SRC.indexOf(decl);
  if (i < 0) return '';
  const start = i + decl.length;
  const m = /\n[ \t]*`;/.exec(SRC.slice(start));
  return m ? SRC.slice(start, start + m.index) : '';
}

const FAST_CSS_RAW = templateLiteral('CHATGPT_FAST_CSS');
if (!FAST_CSS_RAW) {
  fail('CHATGPT_FAST_CSS template literal not found -- the sheet ChatGPT actually receives is gone');
  console.error('\nChatGPT viewport coverage gate: 1 failure(s)');
  process.exit(1);
}

// Golden Default, parsed from the theme table so the gate cannot drift from the
// palette the user actually selects.
function goldenDefaultTokens() {
  const at = SRC.indexOf('goldendefault:');
  if (at < 0) return null;
  const open = SRC.indexOf('tokens: {', at);
  const close = SRC.indexOf('}', open);
  const body = SRC.slice(open + 8, close);
  const out = {};
  for (const m of body.matchAll(/([A-Za-z][A-Za-z0-9]*)\s*:\s*'(#[0-9A-Fa-f]{6})'/g)) out[m[1]] = m[2];
  return out;
}

const TOKENS = goldenDefaultTokens();
if (!TOKENS || !TOKENS.backgroundSoft) {
  fail('Golden Default tokens could not be parsed from vintage.user.js');
  console.error('\nChatGPT viewport coverage gate: 1 failure(s)');
  process.exit(1);
}

// Every other ChatGPT gate extracts CHATGPT_FAST_CSS as TEXT and never evaluates
// it. That is the right call for reading rules, and it is also blind to the
// file not being valid JavaScript: a stray backtick inside the template literal
// closes the string early, the regex that finds the closing delimiter walks
// straight past it, and the extracted "stylesheet" still contains every rule the
// gates assert on. Three green gates, and a userscript that throws on line one
// in the browser. Only a real parse sees it.
try {
  new Function(SRC);                                    // eslint-disable-line no-new-func
  pass('wintage.user.js parses as JavaScript');
} catch (e) {
  fail('wintage.user.js does not parse -- ' + (e && e.message ? e.message : e));
}

// ...and proven able to fail. A backtick inside the ChatGPT template literal is
// the exact defect that reached this gate once: it closes the string early, the
// extraction regex walks past it, and every rule-level assertion still passes.
(() => {
  const ANCHOR = 'law and the cheap path.';
  if (!SRC.includes(ANCHOR)) {
    fail('RC5 parse control -- cannot run: its anchor text is no longer in the source');
    return;
  }
  const broken = SRC.replace(ANCHOR, '`law` and the cheap path.');
  let threw = null;
  try { new Function(broken); } catch (e) { threw = e; }
  check('RED control: a backtick inside CHATGPT_FAST_CSS fails the parse assertion', !!threw,
    threw ? '' : 'the mutated source still parsed, so the parse assertion cannot bite');
})();

// Resolve the template. ${T.x} becomes the real palette value -- that is the
// value the cascade has to produce. Every OTHER interpolation (border macros,
// font stack, the dark/light ternary) becomes `initial`: they cannot affect
// which background wins, and inventing values for them would be guessing.
function resolve(css) {
  return css.replace(/\$\{([^}]*)\}/g, (whole, expr) => {
    const t = /^\s*T\.([A-Za-z][A-Za-z0-9]*)\s*$/.exec(expr);
    if (!t) return 'initial';
    if (!TOKENS[t[1]]) throw new Error('palette token T.' + t[1] + ' is not in Golden Default');
    return TOKENS[t[1]];
  });
}

const hexToRgb = hex => {
  const n = parseInt(hex.replace('#', ''), 16);
  return 'rgb(' + ((n >> 16) & 255) + ', ' + ((n >> 8) & 255) + ', ' + (n & 255) + ')';
};

const BACKGROUND_SOFT = hexToRgb(TOKENS.backgroundSoft);   // #232018 -> rgb(35, 32, 24)
const STOCK_BLACK = 'rgb(0, 0, 0)';
const STOCK_CHARCOAL = 'rgb(33, 33, 33)';

// The acceptance floor from the handoff: none of these may survive in the
// middle of the viewport.
const STOCK_FORBIDDEN = [STOCK_BLACK, STOCK_CHARCOAL, 'rgb(0,0,0)', '#000000', '#212121'];

// ── The stock sheet ──────────────────────────────────────────────────────────
// What the current shell paints before Wintage runs. The scroll container owns
// the viewport with an opaque stock background; the elements above it are
// transparent, which is the shape that makes the parent rules non-load-bearing.
const STOCK_CSS = `
  html, body { margin: 0; padding: 0; background: #ffffff; }
  #web-mobile-root, [data-testid="desktop-app-shell"], main[aria-label="ChatGPT"],
  [role="region"][aria-label="Conversation"] { background-color: transparent; }
  [data-testid="mobile-app-shell-scroll-container"] {
    position: relative; height: 100vh; overflow: hidden;
    background-color: #000000;
  }
  [data-testid="mobile-app-shell-scroll-container"] > header {
    background-image: linear-gradient(to bottom, #212121 0%, rgba(33,33,33,0) 100%);
    height: 56px;
  }
  [data-testid="mobile-app-shell-scroll-container"] > footer {
    background-image: linear-gradient(to top, #212121 0%, rgba(33,33,33,0) 100%);
    height: 120px;
  }
  [role="complementary"][aria-label="Sidebar"] { background-color: #171717; width: 260px; height: 100%; }
  [role="complementary"][aria-label="Sidebar"].collapsed { width: 68px; }
  .msg, .composer-body { background-color: transparent; }
  /* A message embed paints its own header and footer. Wintage must not reach in. */
  .embed > header { background-color: #2f2f2f; height: 32px; }
  .embed > footer { background-color: #262626; height: 28px; }
  .embed { background-color: #1f1f1f; margin: 8px 0; }
`;

// ── The fixture ──────────────────────────────────────────────────────────────
// `regionHeight` is the knob that matters. At '100%' the conversation region
// covers the whole scroll container, so a themed region would hide a stock
// child even in the broken build -- the assertion would be vacuous. At '60%' the
// lower band of the viewport is owned by the scroll container alone, so the
// measurement below can only return stock colour when the viewport owner is
// unthemed. That shape is the red control's whole reason for existing.
function fixture(state) {
  const messages = state === 'empty' ? '' :
    new Array(state === 'composer' ? 2 : 9).fill(0).map((_, i) =>
      '        <div class="msg" data-testid="message-row">' +
      '<div style="height:56px"></div>' +
      (i === 1 ? '        <div class="embed"><header data-testid="embed-header"></header><div style="height:40px"></div><footer data-testid="embed-footer"></footer></div>\n' : '') +
      '</div>').join('\n');

  const sidebarClass = state === 'sidebar-open' ? '' : 'collapsed';
  const composerFocus = state === 'composer' ? ' data-focus="1"' : '';

  return `<!doctype html><html data-w95-chatgpt="1"><head><meta charset="utf-8">
<style>${STOCK_CSS}</style></head>
<body>
<div id="web-mobile-root">
  <div data-testid="desktop-app-shell" style="display:flex">
    <div role="complementary" aria-label="Sidebar" class="${sidebarClass}"></div>
    <div data-testid="mobile-app-shell-scroll-container" style="flex:1">
      <header id="page-header"></header>
      <main aria-label="ChatGPT" style="height:60%">
        <div role="region" aria-label="Conversation" style="height:100%;padding:8px">
${messages}
        </div>
      </main>
      <div id="thread-bottom-container" style="height:40px"></div>
      <footer id="composer-footer">
        <div class="composer-body" data-testid="chat-input"${composerFocus} style="height:60px"></div>
      </footer>
    </div>
  </div>
</div>
</body></html>`;
}

const STATES = [
  ['A empty new-chat viewport', 'empty', 0.90],
  ['B populated conversation', 'populated', 0.90],
  ['C composer focused', 'composer', 0.90],
  ['D sidebar expanded', 'sidebar-open', 0.90],
  ['E viewport band below a short conversation region', 'populated', 0.55]
];

// ── The measurement ──────────────────────────────────────────────────────────
// Runs in the page. Walks up from a point to the first element that actually
// PAINTS something opaque, so it answers "what does the user see", not "is the
// rule present". Structural identity only -- no text, no href, no src.
const PROBE = function () {
  window.__w95probe = function (fx, fy) {
    const transparent = c => !c || c === 'transparent' ||
      /^rgba?\(\s*[\d.]+\s*,\s*[\d.]+\s*,\s*[\d.]+\s*,\s*0(\.0+)?\s*\)$/.test(c);
    const desc = n => {
      if (!n || n.nodeType !== 1) return '(none)';
      const bits = [n.tagName.toLowerCase()];
      if (n.id) bits.push('#' + n.id);
      if (n.getAttribute('data-testid')) bits.push('[data-testid="' + n.getAttribute('data-testid') + '"]');
      if (n.getAttribute('role')) bits.push('[role="' + n.getAttribute('role') + '"]');
      return bits.join('');
    };
    const r = document.documentElement.getBoundingClientRect();
    const x = Math.round(r.width * fx);
    const y = Math.round(r.height * fy);
    const hit = document.elementFromPoint(x, y);
    const chain = [];
    let n = hit;
    let owner = null;
    while (n && n.nodeType === 1) {
      const cs = getComputedStyle(n);
      chain.push(desc(n));
      const img = cs.backgroundImage;
      if (img && img !== 'none') { owner = desc(n); break; }
      if (!transparent(cs.backgroundColor)) { owner = desc(n); break; }
      n = n.parentElement;
    }
    const ownerColor = owner ? getComputedStyle(
      [...document.querySelectorAll('*')].find(e => desc(e) === owner) || hit).backgroundColor : null;
    const sc = document.querySelector('[data-testid="mobile-app-shell-scroll-container"]');
    const scCs = sc ? getComputedStyle(sc) : null;
    const hdr = document.querySelector('#page-header');
    const embeds = [...document.querySelectorAll('.embed > header, .embed > footer')]
      .map(e => getComputedStyle(e).backgroundColor);
    return {
      point: { x, y },
      hit: desc(hit),
      chain,
      owner,
      // The colour a user sees. If the owner paints a background-IMAGE it is
      // recorded as such rather than as a flat colour -- a gradient owner is
      // still a stock-coloured owner and must not read as themed.
      ownerPaintsImage: owner
        ? getComputedStyle([...document.querySelectorAll('*')].find(e => desc(e) === owner) || hit).backgroundImage !== 'none'
        : false,
      ownerBackground: ownerColor,
      scrollContainerBackground: scCs ? scCs.backgroundColor : null,
      headerBackgroundImage: hdr ? getComputedStyle(hdr).backgroundImage : null,
      headerBackgroundColor: hdr ? getComputedStyle(hdr).backgroundColor : null,
      embedChrome: embeds,
      // Proof the parent contracts are LIVE, so a green cannot come from them
      // having silently stopped matching.
      parentContracts: {
        root: !!document.querySelector('#web-mobile-root'),
        shell: !!document.querySelector('[data-testid="desktop-app-shell"]'),
        main: !!document.querySelector('main[aria-label="ChatGPT"]'),
        conversation: !!document.querySelector('[role="region"][aria-label="Conversation"]'),
        scrollContainer: !!sc
      }
    };
  };
};

// ── Runner ───────────────────────────────────────────────────────────────────
async function measure(browser, css, state, fx, fy) {
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  await page.setContent(fixture(state), { waitUntil: 'load' });
  await page.addStyleTag({ content: STOCK_CSS });
  if (css) await page.addStyleTag({ content: css });
  await page.evaluate(PROBE);
  const out = await page.evaluate(([a, b]) => window.__w95probe(a, b), [fx, fy]);
  await page.close();
  return out;
}

function visibleColorIsThemed(m) {
  if (!m.owner) return false;
  if (m.ownerPaintsImage) return false;               // a gradient owner is never proven themed
  return m.ownerBackground === BACKGROUND_SOFT;
}

(async () => {
  const browser = await chromium.launch();
  let sheet = resolve(FAST_CSS_RAW);

  // ── The product assertions ─────────────────────────────────────────────────
  console.log('-- viewport ownership, themed vs stock --');
  for (const [label, state, fy] of STATES) {
    const themed = await measure(browser, sheet, state, 0.5, fy);
    const stock = await measure(browser, null, state, 0.5, fy);

    // The stock build must be WRONG here, or there is nothing to repair and
    // every assertion below would be a tautology.
    if (fy > 0.6) {
      check(label + ' -- fixture reproduces the defect (stock viewport owner is not themed)',
        stock.scrollContainerBackground === STOCK_BLACK && !visibleColorIsThemed(stock),
        'stock scrollContainer=' + stock.scrollContainerBackground + ' owner=' + stock.owner + '/' + stock.ownerBackground);
    }

    check(label + ' -- Wintage themes the viewport owner',
      themed.scrollContainerBackground === BACKGROUND_SOFT,
      'scrollContainer=' + themed.scrollContainerBackground + ' expected ' + BACKGROUND_SOFT);

    check(label + ' -- the colour a user sees is the Wintage backgroundSoft',
      visibleColorIsThemed(themed),
      'owner=' + themed.owner + ' bg=' + themed.ownerBackground + ' paintsImage=' + themed.ownerPaintsImage);

    check(label + ' -- no stock black or charcoal survives in the viewport',
      !STOCK_FORBIDDEN.includes(themed.ownerBackground) && themed.scrollContainerBackground !== STOCK_BLACK,
      'ownerBg=' + themed.ownerBackground + ' scrollContainer=' + themed.scrollContainerBackground);

    check(label + ' -- the parent shell contracts are all still live',
      Object.values(themed.parentContracts).every(Boolean),
      JSON.stringify(themed.parentContracts));
  }

  // Page header / footer fade: stock charcoal gradient must not survive, and the
  // direct-child scope must not reach a message embed's chrome.
  const hf = await measure(browser, sheet, 'populated', 0.5, 0.90);
  check('page header gradient is stripped and repainted in the palette',
    hf.headerBackgroundImage === 'none' && hf.headerBackgroundColor === BACKGROUND_SOFT,
    'bgImage=' + hf.headerBackgroundImage + ' bgColor=' + hf.headerBackgroundColor);

  const hfStock = await measure(browser, null, 'populated', 0.5, 0.90);
  check('fixture reproduces the stock header gradient (so the assertion above is not vacuous)',
    /gradient/.test(String(hfStock.headerBackgroundImage)),
    'stock bgImage=' + hfStock.headerBackgroundImage);

  check('message-embed header/footer are left exactly as stock painted them',
    JSON.stringify(hf.embedChrome) === JSON.stringify(hfStock.embedChrome) && hf.embedChrome.length > 0,
    'themed=' + JSON.stringify(hf.embedChrome) + ' stock=' + JSON.stringify(hfStock.embedChrome));
  await browser.close();

  // ── Red controls ───────────────────────────────────────────────────────────
  // Each mutates the SHIPPED sheet by one anchored replacement and requires the
  // same measurement to go red. Without these, every assertion above is a check
  // that cannot fail.
  console.log('\n-- red controls (each must go red) --');

  // RC1 is the control the whole gate exists for. It removes ONLY the
  // scroll-container viewport-owner rule and leaves #web-mobile-root,
  // [data-testid="desktop-app-shell"], main[aria-label="ChatGPT"] and
  // [role="region"][aria-label="Conversation"] exactly as shipped. If that
  // build still renders themed, the gate is measuring parent selectors instead
  // of the viewport, which is the defect the handoff named.
  const CONTROLS = [
    {
      name: 'RC1 remove ONLY the scroll-container viewport-owner rule',
      expectGone: /\[data-testid="mobile-app-shell-scroll-container"\]\s*\{[^}]*background-color/,
      expectKept: [
        /#web-mobile-root/,
        /\[data-testid="desktop-app-shell"\]/,
        /main\[aria-label="ChatGPT"\]/,
        /\[role="region"\]\[aria-label="Conversation"\]/
      ],
      mutate: css => css.replace(/^\s*html\[data-w95-chatgpt="1"\] \[data-testid="mobile-app-shell-scroll-container"\]\s*\{[^}]*\}/m, ''),
      assert: 'visible viewport returns stock black while every parent contract survives',
      broken: async (b, css) => {
        const m = await measure(b, css, 'populated', 0.5, 0.90);
        return m.scrollContainerBackground === STOCK_BLACK && !visibleColorIsThemed(m);
      }
    },
    {
      name: 'RC2 remove ONLY the header/footer fade scope',
      expectGone: /#page-header\s*\{[^}]*background-image/,
      expectKept: [/#web-mobile-root/, /\[data-testid="mobile-app-shell-scroll-container"\]\s*\{/],
      // Anchored on `... > header,`, which is unique to the fade scope. A looser
      // anchor (`main[aria-label="ChatGPT"]`) also matches the parent block and
      // would eat the very contracts this control has to leave standing.
      mutate: css => css.replace(/^\s*html\[data-w95-chatgpt="1"\] main\[aria-label="ChatGPT"\] \[data-testid="desktop-app-shell"\]\s*>\s*header,[\s\S]*?#page-header\s*\{[^}]*\}/m, ''),
      assert: 'page header keeps the stock gradient',
      broken: async (b, css) => {
        const m = await measure(b, css, 'populated', 0.5, 0.90);
        return /gradient/.test(String(m.headerBackgroundImage));
      }
    },
    {
      name: 'RC3 palette token backgroundSoft replaced by `inherit`',
      expectGone: /background-color:\s*#232018\s*!important/,
      expectKept: [/#web-mobile-root/],
      mutate: css => css.split('background-color: ' + TOKENS.backgroundSoft).join('background-color: inherit'),
      assert: 'nothing is painted with the palette colour',
      broken: async (b, css) => {
        const m = await measure(b, css, 'populated', 0.5, 0.90);
        return m.scrollContainerBackground !== BACKGROUND_SOFT && !visibleColorIsThemed(m);
      }
    },
    {
      name: 'RC4 the entire Wintage ChatGPT sheet removed',
      expectGone: /html\[data-w95-chatgpt="1"\]/,
      expectKept: [],
      mutate: () => '',
      assert: 'every viewport is stock',
      broken: async (b, css) => {
        const m = await measure(b, css, 'populated', 0.5, 0.90);
        return m.scrollContainerBackground === STOCK_BLACK && !visibleColorIsThemed(m);
      }
    }
  ];

  for (const c of CONTROLS) {
    const mutated = c.mutate(sheet);
    if (mutated === sheet) {
      fail(c.name + ' -- RED control did not mutate the sheet, so it is inert and proves nothing');
      continue;
    }
    // The cut must remove the intended rule AND leave everything else standing.
    // A control that silently cut more than it claimed would go red for the
    // wrong reason, which is its own kind of green.
    if (c.expectGone.test(mutated)) {
      fail(c.name + ' -- the cut left the rule it claims to remove in place');
      continue;
    }
    const survivors = c.expectKept.filter(re => re.test(mutated));
    if (survivors.length !== c.expectKept.length) {
      fail(c.name + ' -- the cut also removed contracts it must leave standing (' +
        (c.expectKept.length - survivors.length) + ' gone)');
      continue;
    }
    const rcBrowser = await chromium.launch();
    let red = false;
    try {
      red = await c.broken(rcBrowser, mutated);
    } finally {
      await rcBrowser.close();
    }
    check(c.name + ' -- ' + c.assert, red, 'the control failed to turn the shipped sheet red');
  }

  console.log('');
  if (bad) {
    console.error('ChatGPT viewport coverage gate: ' + bad + ' failure(s)');
    process.exit(1);
  }
  console.log('ChatGPT viewport coverage gate: PASS');
})().catch(e => {
  console.error('ChatGPT viewport coverage gate: harness error -- ' + (e && e.message ? e.message : e));
  process.exit(1);
});
