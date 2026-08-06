// Wintage shim for Electron applications.
//
// The application's archive is moved to `app.asar` INSIDE this folder and this
// file becomes the entry point. Nothing of the app is rewritten -- only relocated
// -- and the installer's --revert moves it straight back.
//
// (The tidier-looking idea, leaving app.asar where it is and relying on Electron
// preferring `resources/app`, does not work: Electron searches app.asar first and
// the theme silently never runs. tools/install-electron.js has the full note.)
//
// .cjs, not .js, and that is load-bearing. The package.json here is COPIED from the
// application's own so the app keeps its name and version -- and if the app declares
// "type": "module", a .js shim is parsed as ESM and dies on its first `require` with
// a main-process error dialog. Freebuff and CodeNomad both do exactly that. The
// extension pins CommonJS regardless of what the copied manifest says.

const path = require('path');
const fs = require('fs');

const CSS_FILE = path.join(__dirname, 'wintage.css');
const ASAR = path.join(__dirname, 'app.asar');

let css = '';
try { css = fs.readFileSync(CSS_FILE, 'utf8'); } catch (e) {
  console.error('[wintage] stylesheet missing, loading the app unthemed:', e.message);
}

// The two colours the NATIVE titlebar overlay needs are read back out of the
// stylesheet's own `:root` block rather than shipped as a second file. The
// generated CSS always opens with that block (tools/build-desktop.js), so this has
// exactly one source of truth and a palette switch cannot leave the caption
// buttons painted in the previous theme.
const token = name => {
  const m = new RegExp('--' + name + ':\\s*(#[0-9A-Fa-f]{6})').exec(css);
  return m ? m[1] : null;
};
const T_SURFACE = token('surface');
const T_TEXT = token('textPrimary');
const T_BACKGROUND = token('background');

// Claude 1.24012.9 started assigning an explicit near-black `color` to most
// layout wrappers. An important colour inherited from html/body still loses to
// any declaration made directly on a child, so the palette kept painting the
// surfaces and bevels while the ordinary labels became black-on-brown.
//
// Keep this repair Claude-only. The shared stylesheet also serves FreeBuff,
// CodeNomad and browser pages, where flattening every explicit text colour would
// erase useful semantic states. `inherit` walks Claude's wrappers back to the
// palette while retaining the stronger existing rules for links, controls and
// disabled text. The text-fill reset covers WebKit utility classes; SVG and the
// usual icon-font carriers stay outside it so glyphs do not turn into letters.
const CLAUDE_VIEW = /(?:^https:\/\/claude\.ai\/epitaxy(?:[/?#]|$)|\/\.vite\/renderer\/main_window\/index\.html(?:[?#]|$))/i;
const CLAUDE_FOREGROUND_CSS = `
body :where(div, span, p, section, article, aside, main, nav, header, footer,
  ul, ol, li, dl, dt, dd, h1, h2, h3, h4, h5, h6, label, small, strong, em,
  b, time, code, pre, kbd, samp, input, textarea, select, option, button):not(svg):not(svg *):not([aria-hidden="true"]):not([class*="icon" i]):not([class*="glyph" i]):not([class*="symbol" i]) {
  color: inherit !important;
  -webkit-text-fill-color: currentColor !important;
}`;

// ─── SCROLLBAR GUTTERS ───────────────────────────────────────────────────────
// Styling ::-webkit-scrollbar turns Chromium's OVERLAY scrollbars into classic
// ones. Overlay scrollbars are invisible until you scroll, so app authors write
// `overflow: scroll` freely and it costs them nothing — until a theme makes those
// scrollbars classic, and every one of those containers grows a permanent gutter
// with a full-length thumb, on panels that have room to spare. Reported on
// Antigravity, visible on several panels at once.
//
// CSS cannot fix this: there is no selector for "this element's overflow is scroll",
// and blanket-overriding overflow would break containers that need `hidden`. So the
// one narrow change is made from script: computed `scroll` becomes `auto`, which is
// identical when the content actually overflows and hides the gutter when it does
// not. Nothing else is touched.
//
// The SECOND pass is newer and answers the follow-up report — scrollbars that are
// pure decoration, and one that clipped the edge of the Settings button. Those
// containers are on `auto` and DO overflow, by a handful of pixels, because this
// theme itself added a 2px bevel to everything inside them. A scrollbar whose whole
// range is four pixels is not a control, and it costs the panel a full gutter.
//
// `scrollbar-width: none`, not `overflow: hidden`, and the difference is the whole
// safety argument: hiding overflow makes content UNREACHABLE if the guess is wrong
// and the panel later fills up (a chat log is the obvious victim). Hiding only the
// scrollbar keeps the element scrollable by wheel and trackpad no matter what, so
// the worst case of a wrong guess is a missing bar, not lost content. It also
// reclaims the gutter, which `overflow: hidden` would not have done any better.
//
// The decision is re-made, not remembered: a container that grows real content
// gets its scrollbar back on the next pass. That is why NOISE is compared against
// live measurements every time instead of being latched on first sight.
//
// Cost discipline is copied from the userscript, which already paid for this lesson:
// getComputedStyle over a whole document is expensive, so this runs a few bounded
// passes after load and then only on newly added subtrees, never on a timer.
const SCROLL_FIX = `(() => {
  if (window.__wintageScrollFix) return "already running";
  window.__wintageScrollFix = true;

  // Two bevels (2px each) plus sub-pixel rounding is 5px of overflow this theme
  // creates by itself. 8 leaves headroom without reaching anything a person would
  // recognise as a scrollable list.
  const NOISE = 8;
  const MARK = "__wintageNoScrollbar";

  const fixOne = el => {
    const cs = getComputedStyle(el);
    if (cs.overflowY === "scroll") el.style.setProperty("overflow-y", "auto", "important");
    if (cs.overflowX === "scroll") el.style.setProperty("overflow-x", "auto", "important");

    const scrollableY = cs.overflowY === "auto" || cs.overflowY === "scroll" || cs.overflowY === "overlay";
    const scrollableX = cs.overflowX === "auto" || cs.overflowX === "scroll" || cs.overflowX === "overlay";
    if (!scrollableY && !scrollableX) return;

    const rangeY = el.scrollHeight - el.clientHeight;
    const rangeX = el.scrollWidth - el.clientWidth;
    const noise = rangeY <= NOISE && rangeX <= NOISE;

    if (noise && !el[MARK]) {
      el[MARK] = true;
      el.style.setProperty("scrollbar-width", "none", "important");
    } else if (!noise && el[MARK]) {
      el[MARK] = false;
      el.style.removeProperty("scrollbar-width");
    }
  };

  const fixTree = root => {
    const els = root.querySelectorAll ? root.querySelectorAll("*") : [];
    for (const el of els) fixOne(el);
  };

  fixTree(document);
  let passes = 0;
  const settle = () => { if (++passes < 3) { fixTree(document); setTimeout(settle, 600); } };
  setTimeout(settle, 600);

  let queued = false;
  const mutations = [];
  new MutationObserver(records => {
    mutations.push(...records);
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => {
      queued = false;
      const recs = mutations.splice(0, mutations.length);
      for (const r of recs) {
        if (r.type === "childList") {
          // The TARGET matters as much as the added nodes here. It is the element
          // whose children changed -- i.e. the scroll container itself -- and it is
          // the only way a panel that was clipped while empty gets its scrollbar
          // back once something is put in it.
          if (r.target.nodeType === 1) fixOne(r.target);
          for (const node of r.addedNodes) {
            if (node.nodeType === 1) { fixOne(node); fixTree(node); }
          }
        } else if (r.type === "attributes") {
          if (r.target.nodeType === 1) fixOne(r.target);
        }
      }
    });
  }).observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ["style", "class"] });

  return "scroll fix installed";
})()`;

// ─── THE REPAINTER, SHIPPED WHOLE ────────────────────────────────────────────
// A stylesheet cannot win against an application that computes its colours in JS,
// and the attempt to paper over that with CSS -- a blanket that wiped backgrounds
// to transparent and re-solidified panels off a list of library NAMES -- lost the
// race against the app's own state writes and left panels unreadable. Both halves
// of that idea are gone now.
//
// The userscript already solves this properly: it measures computed styles and
// writes back only what is actually wrong. So the repainter is NOT reimplemented
// here. tools/build-desktop.js extracts it from wintage.user.js between its
// REPAINTER markers and drops it in below, exactly the way the stylesheet is
// extracted, so a fix made once is a fix made everywhere.
//
// It arrives as a JSON string literal rather than as text pasted inside a template
// literal, and that is not a style preference. The repainter is full of regex
// literals -- /rgba?\(\s*(\d+)/ and its relatives -- and inside a template literal
// every one of those backslashes is an escape: \s collapses to s, \d to d, \( to
// (. The result still parses and silently matches the wrong thing. A single
// backtick in any of its comments ends the string outright, which is precisely how
// this shim shipped unloadable. JSON.stringify is the only encoding that carries
// all of it through verbatim.
const REPAINTER_BODY = "\r\n\n  function parseRGB(str) {\n    if (!str) return null;\n    const m = str.match(/rgba?\\(\\s*(\\d+)\\s*,\\s*(\\d+)\\s*,\\s*(\\d+)(?:\\s*[,/]\\s*([\\d.]+))?/);\n    if (!m) return null;\n    return { r: +m[1], g: +m[2], b: +m[3], a: m[4] !== undefined ? parseFloat(m[4]) : 1 };\n  }\n  // Write-if-changed: re-verify passes revisit every element, so identical\n  // rewrites must not invalidate styles or churn the style attribute.\n  function setImp(el, prop, val) {\n    const st = el.style;\n    if (st.getPropertyValue(prop) !== val || st.getPropertyPriority(prop) !== 'important') {\n      st.setProperty(prop, val, 'important');\n    }\n  }\n\n  // 🚨 READ/WRITE SPLIT — this was THE idle-CPU bug (v1.3.0) 🚨\n  // process() used to read getComputedStyle and write inline styles in the same\n  // loop. Every inline write invalidates style, so the NEXT element's read had\n  // to force a whole-document style recalc — and this theme's own selectors make\n  // that the most expensive recalc shape there is (`*`, `*, *::before, *::after`,\n  // the 8-`:not([class*=\"…\" i])` icon-font selector, the 12-negation hover-freeze\n  // selector). One write per element therefore bought one full recalc per\n  // element. Measured live on en.wikipedia.org/wiki/World_War_II, 16921 elements,\n  // published v1.2.1 eval'd in-page:\n  //     2500 elements, reads only ................  70.6 ms\n  //     2500 elements, interleaved read+write ....  1069–1994 ms   ← old code\n  //     2500 elements, batched read-then-write ...  230.9 ms  (~190 ms of which\n  //                                                 is ONE whole-doc recalc)\n  // One real instrumented sweeper tick measured 253 ms per 1.5 s interval =\n  // 16.9 % of a core, permanently, on a page that was doing nothing.\n  //\n  // So process() now ONLY READS. Instead of writing, it appends [el, prop, val]\n  // triples to a queue that the caller flushes once at the end: N recalcs -> 1.\n  // A flat array (not objects) keeps the queue allocation-free per element.\n  //\n  // Correctness note on batching: `color` is inherited, so a child no longer\n  // sees its parent's just-corrected color while being read — it fails the\n  // contrast check against the ORIGINAL inherited value and gets its own\n  // explicit inline color. Identical final pixels, one extra declaration; it\n  // can never resolve to a DIFFERENT color, only to the same one stated twice.\n  // Non-inherited properties (background, border-*) are unaffected either way.\n  //\n  // Attribute writes stay inline and are deliberately NOT queued: setAttribute\n  // ('data-w95-done') is not referenced by any selector in this theme, so it\n  // invalidates nothing (measured: 6.7 ms for all 16921 elements), and\n  // removeAttribute('bgcolor'/'background') is a no-op when absent.\n  // 🚨 SELF-WRITE SUPPRESSION IS BY IDENTITY, NEVER BY A TIME WINDOW (v1.4.2) 🚨\n  // 'style' IS in the observer's attributeFilter, which ADR-002 said never to do.\n  // It is worth doing — a site mutating an existing element's inline style is\n  // otherwise invisible, and catching it with an event is what let the 30s\n  // polling heartbeat be deleted entirely. But setImp writes inline styles, so\n  // the observer WILL be handed its own output and the suppression has to be\n  // airtight.\n  //\n  // The first attempt muted all 'style' records for 100ms after each flush.\n  // Measured on a static article (16595 elements), 12-second window:\n  //     site alone, no theme .......    0 style mutations\n  //     with the theme ............. 9466 style mutations\n  // i.e. every single one was ours. The mute discarded them at flush time, so\n  // there was no runaway — but 9466 records were still allocated, delivered\n  // through a microtask, and pushed into pendingMuts to be walked by the next\n  // debounce. And it was only ever timing-safe by luck: the filter runs at the\n  // END of the 60ms debounce, so any flush that lands >100ms before its debounce\n  // fires (i.e. exactly when the main thread is busy, which is exactly during a\n  // heavy sweep) lets our own writes through, and each one that gets processed\n  // clears data-w95-done and re-processes the element, generating more writes.\n  // A blanket window also drops the SITE's real style changes for 100ms.\n  //\n  // So: record precisely which elements we wrote, then drain the observer queue\n  // ourselves with takeRecords() before the callback ever runs, keeping every\n  // record that was not ours. Timing-independent and scoped to the exact\n  // elements involved.\n  const selfWritten = new Set();\n\n  function flushWrites(w) {\n    if (!w.length) return;\n    for (let i = 0; i < w.length; i += 3) {\n      setImp(w[i], w[i + 1], w[i + 2]);\n      selfWritten.add(w[i]);\n    }\n    w.length = 0;\n    // takeRecords() returns AND clears the pending queue, so this runs before\n    // the observer callback is ever invoked for these mutations.\n    let kept = 0;\n    for (const obs of [mainObserver, shadowObserver]) {\n      let recs;\n      try { recs = obs.takeRecords(); } catch (e) { continue; }\n      for (let i = 0; i < recs.length; i++) {\n        const m = recs[i];\n        if (m.type === 'attributes' && m.attributeName === 'style' && selfWritten.has(m.target)) continue;\n        pendingMuts.push(m);\n        kept++;\n      }\n    }\n    selfWritten.clear();\n    // Anything genuinely foreign that was queued alongside our writes still has\n    // to be handled; the debounce is not running at this point (flushWrites is\n    // called at the END of it, and from runSweeper), so it needs re-arming.\n    // Known and accepted gap: a site style-change on an element WE also wrote to\n    // in the same batch is dropped. It is self-healing — the next sweep re-reads\n    // that element's computed style from scratch.\n    if (kept && !debounceTimer) onMutations(EMPTY_MUTATIONS);\n  }\n  const EMPTY_MUTATIONS = [];\n\n  // 🚨 SATURATED COLOUR -> ONE OF THREE SEMANTIC TOKENS (UI.md law 5) 🚨\n  // The pre-1.4.0 rule multiplied a light saturated background by 0.18, which\n  // \"preserved the hue\" — and in doing so emitted an unbounded set of arbitrary\n  // colours that trace to no token at all. GitHub's diff green became one\n  // brown-green, GitLab's a different one, a warning banner a third: iron law 5\n  // broken every time, and every site kept its own colour signature.\n  //\n  // UI.md ships exactly three semantic colours, so the site's own hue only has to\n  // answer one question: which of the three did it mean? Hue sectors, wide and\n  // deliberately coarse, because the answer only needs to be right to within\n  // \"green / amber / red\":\n  //   red-ish    (>=345 or <35 deg) -> --danger\n  //   yellow-ish (35..75 deg)       -> --warning\n  //   green-ish  (75..170 deg)      -> --success\n  // Everything else — blues, purples, teals, magentas — carries no shared meaning\n  // across sites, so it becomes plain --surfaceRaised rather than being forced\n  // into a status colour it never claimed.\n  function semanticToken(c) {\n    const max = Math.max(c.r, c.g, c.b), min = Math.min(c.r, c.g, c.b), d = max - min;\n    if (d === 0) return T.surfaceRaised;\n    let h;\n    if (max === c.r) h = 60 * (((c.g - c.b) / d) % 6);\n    else if (max === c.g) h = 60 * ((c.b - c.r) / d + 2);\n    else h = 60 * ((c.r - c.g) / d + 4);\n    if (h < 0) h += 360;\n    if (h >= 345 || h < 35) return T.danger;\n    if (h < 75) return T.warning;\n    if (h < 170) return T.success;\n    return T.surfaceRaised;\n  }\n\n  // UI.md's five permitted sizes, and the role mapping GLOBAL_CSS uses. Kept as\n  // lookups so the JS enforcement below can never drift from the CSS layer.\n  const SIZE_ALLOWED = new Set(['10px', '11px', '12px', '14px', '16px']);\n  const LADDER = {\n    H1: '16px', H2: '14px', H3: '14px', H4: '14px', H5: '14px', H6: '14px',\n    SMALL: '10px', SUB: '10px', SUP: '10px', FIGCAPTION: '10px'\n  };\n  // The palette as the browser serialises it, for cheap \"is this already one of\n  // ours?\" tests against a computed value.\n  const PALETTE_RGB = new Set(Object.keys(T).map(k => {\n    const h = T[k];\n    return 'rgb(' + parseInt(h.slice(1, 3), 16) + ', ' + parseInt(h.slice(3, 5), 16) + ', ' + parseInt(h.slice(5, 7), 16) + ')';\n  }));\n\n  const ICONISH = /icon|fa-|symbols|glyph|mdi|bi-/i;\n  function isIconish(el) {\n    // className is an SVGAnimatedString on SVG elements, not a string — read the\n    // attribute instead of trusting the property.\n    const c = el.getAttribute && el.getAttribute('class');\n    return c ? ICONISH.test(c) : false;\n  }\n\n  const JS_SKIP_SELECTOR = '#movie_player, .html5-video-player, ytd-player, ytd-thumbnail, yt-img-shadow, ytd-avatar-shape, yt-avatar-shape, #avatar, #author-thumbnail, ytd-logo, yt-icon, yt-icon-shape';\n  const SHADOW_SKIP_TAGS = new Set(['YTD-LOGO', 'YT-ICON', 'YT-ICON-SHAPE', 'YT-IMG-SHADOW', 'YTD-AVATAR-SHAPE', 'YT-AVATAR-SHAPE', 'VIDEO', 'AUDIO', 'CANVAS', 'IFRAME']);\n  const TAG_SKIP = /^(IMG|VIDEO|CANVAS|PICTURE|IFRAME|SVG|PATH|CIRCLE|RECT|LINE|POLYGON|POLYLINE|ELLIPSE|DEFS|SYMBOL|USE|STYLE|SCRIPT|LINK|META|HEAD|HTML|BR|HR|WBR)$/i;\n\n  const piercedRoots = new Set();\n\n  function pierceShadow(host) {\n    const tag = (host.tagName || '').toUpperCase();\n    if (SHADOW_SKIP_TAGS.has(tag)) return;\n    if (!host.shadowRoot || piercedRoots.has(host.shadowRoot)) return;\n    piercedRoots.add(host.shadowRoot);\n    try {\n      injectStyle(host.shadowRoot, 'shadow', SHADOW_CSS);\n      if (!CSS_ONLY_MODE) {\n        shadowObserver.observe(host.shadowRoot, {\n          childList: true,\n          subtree: true,\n          attributes: true,\n          attributeFilter: ['class', 'bgcolor', 'background', 'style']\n        });\n        stylesDirty = true;\n      }\n    } catch (e) { }\n  }\n\n\n  // ─── :hover RULE SURGERY (v29.1) ────────────────────────────────────────────\n  // Strips paint properties out of every readable :hover rule so sites cannot\n  // flashbang-highlight on hover. Functional props (display, visibility,\n  // opacity, transform) are left untouched so hover-opened menus keep working.\n  // Cross-origin sheets that throw on cssRules access are covered by the CSS\n  // freeze rule in GLOBAL_CSS/SHADOW_CSS instead.\n  const HOVER_PAINT = /^(background|box-shadow|filter|backdrop-filter|color|border|outline|text-decoration|text-shadow|--)/;\n  const sheetSeen = new WeakMap(); // sheet -> cssRules.length at last pass\n\n  function stripHoverRule(rule) {\n    const st = rule.style;\n    if (!st) return;\n    const names = [];\n    for (let i = 0; i < st.length; i++) names.push(st[i]);\n    for (let i = 0; i < names.length; i++) {\n      if (HOVER_PAINT.test(names[i])) st.removeProperty(names[i]);\n    }\n  }\n\n  function walkRules(container) {\n    let rules;\n    try { rules = container.cssRules; } catch (e) { return; } // cross-origin\n    if (!rules) return;\n    for (let i = 0; i < rules.length; i++) {\n      const r = rules[i];\n      try {\n        if (r.selectorText && r.selectorText.indexOf(':hover') !== -1) stripHoverRule(r);\n        if (r.cssRules && r.cssRules.length) walkRules(r); // @media/@supports/@layer/nesting\n      } catch (e) { }\n    }\n  }\n\n  // Returns true when at least one sheet had changed since the last pass — the\n  // caller treats that as \"late CSS is still landing\" and requests a force\n  // re-verify (v1.3.0). On a settled page it returns false every time, which is\n  // what lets the expensive pass go quiet.\n  function stripHoverSheets(root) {\n    let changed = false;\n    const lists = [root.styleSheets, root.adoptedStyleSheets];\n    for (let l = 0; l < lists.length; l++) {\n      const list = lists[l];\n      if (!list) continue;\n      for (let i = 0; i < list.length; i++) {\n        const sheet = list[i];\n        const node = sheet.ownerNode;\n        if (node && node.getAttribute && node.getAttribute('data-w95')) continue; // our own hover bevels stay\n        let count;\n        try { count = sheet.cssRules ? sheet.cssRules.length : 0; } catch (e) { continue; }\n        const seen = sheetSeen.get(sheet);\n        if (seen === count) continue; // unchanged since last pass\n        sheetSeen.set(sheet, count);\n        changed = true;\n        if (seen === undefined || count < seen) {\n          walkRules(sheet); // first sight or rules removed: full walk\n        } else {\n          // CSS-in-JS engines insertRule constantly; re-walking the whole sheet\n          // every tick was a jank source. Walk the appended rules only.\n          try {\n            const rules = sheet.cssRules;\n            for (let r = seen; r < count; r++) {\n              const rule = rules[r];\n              if (rule.selectorText && rule.selectorText.indexOf(':hover') !== -1) stripHoverRule(rule);\n              if (rule.cssRules && rule.cssRules.length) walkRules(rule);\n            }\n          } catch (e) { }\n        }\n      }\n    }\n    return changed;\n  }\n\n  // `w` is the caller's write queue (see flushWrites). Reads only — every style\n  // change is appended, never applied here.\n  function process(el, force, w) {\n    // v29 FIX: the old `el.closest(':hover')` guard was fatal — html/body match\n    // :hover whenever the cursor is anywhere over the viewport, so closest()\n    // returned truthy for EVERY element and the sweeper silently processed\n    // nothing while the mouse was on the page (= dark-on-dark text never got\n    // contrast-fixed). Only skip elements that are themselves in an interactive\n    // state chain; they get retried on later sweeps.\n    try {\n      if (el && el.matches && el.matches(':hover,:active,:focus')) return;\n    } catch (e) { }\n\n    if (!el || el.nodeType !== 1) return;\n    if (!force && el.hasAttribute('data-w95-done')) return;\n    el.setAttribute('data-w95-done', '1');\n\n    if (el.shadowRoot) pierceShadow(el);\n\n    const cs = window.getComputedStyle(el);\n\n    // 🚨 INFINITE ANIMATIONS GET PAUSED, NOT SPED UP (v1.4.1) 🚨\n    // The global 'animation-duration: 0.001s' makes FINITE animations instant,\n    // which is the goal. On an INFINITE animation it does the opposite of\n    // stopping it. Measured exactly, via the Web Animations API on a real\n    // spinner (duration 1ms, iterations Infinity):\n    //     iterations in 1 second .............. 1000   (site intended: 1)\n    //     iterations per 60fps frame ..........   16.7 (site intended: 0)\n    //     angle rendered on 6 consecutive frames:\n    //       240deg, 120deg, 0deg, 240deg, 120deg, 0deg\n    // 16.667ms per frame divided by a 1ms duration leaves a repeating 2/3\n    // remainder, so a spinner does not freeze — it strobes between exactly three\n    // rotations forever. That is worse than the smooth spin it replaced, and it\n    // makes this theme's \"zero animations\" claim false. ADR-001 checked that\n    // Chromium does not FLOOD animationiteration events here and stopped there;\n    // it never checked what was actually on screen. See ADR-004.\n    //\n    // Pausing is safe precisely where the 0.001s compromise is pointless: an\n    // infinite animation's 'animationend' NEVER fires, so no animationend-driven\n    // state machine can be waiting on one — and keeping animationend alive is the\n    // entire reason 0.001s was chosen over 0s/none in the first place (ADR-001).\n    // 'paused' rather than 'animation: none' because a paused animation keeps\n    // applying its current computed value: cancelling instead would snap the\n    // element back to its base state, which for a pulse/skeleton loop is often\n    // opacity 0 — i.e. it would make content vanish.\n    //\n    // Known residual risk: code that drives state from 'animationiteration'\n    // (some marquee and carousel loops) will stall. Rare, and the alternative is\n    // a permanent three-position strobe on every spinner on the web.\n    //\n    // This runs BEFORE shouldSkip on purpose. The two commonest spinner shapes\n    // are both in the skip set: Tailwind's 'svg.animate-spin' (SVG is in\n    // TAG_SKIP) and a spinner inside a loading <button> (shouldSkip matches\n    // closest('button')). Checking after the skip would miss exactly the cases\n    // that matter.\n    const iterCount = cs.animationIterationCount;\n    if (iterCount && iterCount.indexOf('infinite') !== -1) {\n      w.push(el, 'animation-play-state', 'paused');\n    }\n\n    // 🚨 UI.md HARD INVARIANTS, ENFORCED FROM JS BECAUSE CSS CANNOT WIN (v1.4.3) 🚨\n    // Our universal rules are '* { border-radius: 0 !important }' etc, which score\n    // specificity (0,0,0). A site's own '!important' beats them the moment it has\n    // any specificity at all, and an ID rule beats them absolutely — no number of\n    // ':root' prefixes can outrank (1,0,0). Measured on stackoverflow.com:\n    //     a.bar-sm ....................... border-radius 4px   (site .class wins)\n    //     h1.fs-headline1 ................ font-size 27px      (site .class wins)\n    //     h2.fs-body2 .................... font-size 15px\n    //     #onetrust-banner-sdk ........... box-shadow present  (site #id wins)\n    // Inline '!important' is the one declaration that outranks every author rule\n    // regardless of selector, and that is exactly what setImp writes. So these\n    // three invariants are re-asserted here whenever the computed value actually\n    // disagrees. The check is nearly free — 'cs' is already resolved, this is three\n    // more property reads — and the write is skipped entirely when the CSS layer\n    // already won, which is the overwhelming majority of elements (14 of 3362 on\n    // the page above).\n    //\n    // Runs BEFORE shouldSkip because these are universal invariants: a rounded\n    // corner or a drop shadow is just as wrong on a <button> or an <img> as\n    // anywhere else, and buttons are skipped by shouldSkip via closest('button').\n    if (cs.borderTopLeftRadius !== '0px' || cs.borderTopRightRadius !== '0px' ||\n      cs.borderBottomLeftRadius !== '0px' || cs.borderBottomRightRadius !== '0px') {\n      w.push(el, 'border-radius', '0');\n    }\n    if (cs.boxShadow && cs.boxShadow !== 'none') {\n      w.push(el, 'box-shadow', 'none');\n    }\n    // Type ladder, same role mapping as GLOBAL_CSS. Icon-font carriers are\n    // exempt for the same reason as in CSS: their font-size IS their glyph size.\n    const fs = cs.fontSize;\n    if (fs && !SIZE_ALLOWED.has(fs) && !isIconish(el)) {\n      w.push(el, 'font-size', LADDER[(el.tagName || '').toUpperCase()] || '12px');\n    }\n\n    if (shouldSkip(el)) {\n      // Controls and their contents are deliberately kept out of the generic\n      // repainter so our bevels and labels survive (that is what the\n      // closest('button') skip is for). But CSS alone cannot defend them: a site\n      // rule with ID specificity and !important beats our button rule outright.\n      // Measured on stackoverflow.com's cookie banner —\n      //     #onetrust-consent-sdk #onetrust-accept-btn-handler\n      //         { background: var(--black-600) !important; color: #fff !important }\n      // scores (2,0,0) against our 'button { … !important }' at (0,0,1), and\n      //     #onetrust-banner-sdk * { color: var(--black-600) !important }\n      // at (1,0,0) beats every universal colour rule we have. The result was\n      // near-black text on near-black surfaces inside the banner, on elements the\n      // repainter had explicitly excluded.\n      //\n      // So: clamp, but only what is PROVABLY off-palette. A correctly themed\n      // control already computes to a palette value and is skipped here, so this\n      // cannot flatten our own bevel colours or relabel button internals — which\n      // is exactly the regression the skip exists to prevent.\n      if (el.closest && el.closest('button')) {\n        if (cs.color && !PALETTE_RGB.has(cs.color)) {\n          w.push(el, 'color', T.textPrimary);\n        }\n        const cbg = parseRGB(cs.backgroundColor);\n        if (cbg && cbg.a > 0.3 && !PALETTE_RGB.has(cs.backgroundColor)) {\n          w.push(el, 'background-color', T.surfaceRaised);\n        }\n      }\n      return;\n    }\n\n    el.removeAttribute('background');\n    el.removeAttribute('bgcolor');\n\n    // Checkbox/radio: only force native appearance on a REAL, visible control\n    // (the confirmed invisible-checked-state bug). Skip entirely for the\n    // hidden-proxy pattern (opacity:0 / near-zero size / clipped) that custom\n    // switch components rely on — see the CSS comment above for why.\n    const tagUC = (el.tagName || '').toUpperCase();\n    if (tagUC === 'INPUT') {\n      const inputType = (el.type || '').toLowerCase();\n      if (inputType === 'checkbox' || inputType === 'radio') {\n        // opacity is the ONLY reliable signal — every accessible custom-switch\n        // technique uses it (keyboard/screen-reader focus requires the real\n        // input stay hit-testable, ruling out display:none). Size is NOT a\n        // reliable signal: a checkbox with appearance:none and no explicit\n        // width/height collapses to 0x0 in Chromium regardless of whether the\n        // site intentionally hid it — a live test confirmed a genuinely\n        // BROKEN, unstyled real checkbox (the original government-form bug\n        // shape) also measures 0x0, so a size check produces false positives\n        // that silently reintroduce that exact bug.\n        const hiddenProxy = parseFloat(cs.opacity) < 0.05;\n        if (!hiddenProxy) {\n          w.push(el, 'appearance', 'auto', el, '-webkit-appearance', 'auto');\n        }\n        return;\n      }\n    }\n\n    // UI.md law 2: zero gradients. Pre-1.4.0 this only killed LIGHT gradients,\n    // which left every dark-themed site's own coloured gradients intact — and a\n    // gradient is the most identity-carrying surface treatment there is, so\n    // leaving them meant sites still looked like themselves. Now ALL gradient\n    // functions go, whatever their hue.\n    //\n    // Only gradient FUNCTIONS, never url(): a huge number of sites still draw\n    // their icons as background-image sprites, and killing url() backgrounds\n    // deletes those icons outright. This is why the kill lives in JS at all — CSS\n    // cannot say \"background-image: none, but only if it is a gradient\".\n    //\n    // progress/meter/slider are exempt: their fill IS a gradient on many sites,\n    // and flattening it leaves a progress bar that cannot show progress — which\n    // UI.md itself wants preserved (\"long work reports progress in text\").\n    const bgImg = cs.backgroundImage;\n    if (bgImg && bgImg !== 'none' && /(^|\\s|,)(linear|radial|conic|repeating-linear|repeating-radial|repeating-conic)-gradient\\(/i.test(bgImg)) {\n      const tagG = (el.tagName || '').toUpperCase();\n      const roleG = el.getAttribute ? el.getAttribute('role') : null;\n      if (tagG !== 'PROGRESS' && tagG !== 'METER' && roleG !== 'progressbar' && roleG !== 'slider') {\n        w.push(el, 'background-image', 'none');\n      }\n    }\n\n    // PAGE-SIZED PHOTO BACKDROPS.\n    // url() backgrounds are deliberately kept (see above): on most elements they\n    // are icons, and killing them leaves invisible buttons. But at page scale the\n    // same rule is what left steamcommunity.com with its neon profile artwork\n    // blazing down both sides of a themed column -- the site paints a photo on a\n    // full-bleed div, our surfaces go brown around it, and the result is the\n    // screenshot the user sent.\n    //\n    // Size is the discriminator, and it is a safe one: nothing that is an icon is\n    // 70% of the viewport in BOTH dimensions.\n    //\n    // But getBoundingClientRect FORCES LAYOUT, and this whole file exists in its\n    // current shape because layout thrash once burned 94% of the main thread\n    // (ADR-004, and the sweep-rate hot loop in ADR-006). \"Only when a url() is\n    // present\" is not a tight enough guard on its own: an icon-sprite-heavy page\n    // has hundreds of those. So the measurement is gated behind a pure DOM-shape\n    // test first -- a page-level backdrop is always near the top of the tree,\n    // never buried twelve divs deep -- which costs no layout at all and leaves a\n    // handful of candidates per page.\n    if (bgImg && bgImg !== 'none' && /url\\(/i.test(bgImg)) {\n      let depth = 0, p = el;\n      while (p && p !== document.body && p !== document.documentElement && depth < 5) { p = p.parentElement; depth++; }\n      if (depth < 5) {\n        const r = el.getBoundingClientRect();\n        if (r.width > innerWidth * 0.7 && r.height > innerHeight * 0.7) {\n          w.push(el, 'background-image', 'none');\n        }\n      }\n    }\n\n    // 🚨 FLOATING SURFACES ARE MEASURED, NOT NAMED 🚨\n    // GLOBAL_CSS re-solidifies popovers off a list of NAMES -- role=\"menu\",\n    // [class*=\"popup\" i], [class*=\"dropdown\" i], the radix and floating-ui portal\n    // attributes -- because the surface-flattening wipe above would otherwise leave\n    // them see-through with the page behind them showing through. That list has\n    // missed the same app twice now (E-381, E-407): Claude's popovers carry none of\n    // those markers.\n    //\n    // Adding more names does not fix a name list, it postpones it. Every entry is\n    // one library's vocabulary, and an app that renames a component or swaps its\n    // popover library drops off the list at its next release with nothing to show\n    // for it -- no error, no failing gate, just a hole in the theme that the user\n    // finds. So the test below asks what a popover IS, in terms the layout engine\n    // answers and a rename cannot change: out of flow, big enough to read, and\n    // actually covering content it does not own. The same test runs in Electron\n    // apps as the shim's FLOAT_FIX, which is the only place it can run there --\n    // that path ships CSS with no repainter behind it.\n    //\n    // The last of the three replaced an \"explicit z-index, not auto\" test that\n    // shipped in the first pass and was wrong on the first app it met: Claude's\n    // Settings panel is role=\"dialog\", position: fixed, 606x720 over a 638x1079\n    // window, and z-index: auto. It stacks by paint order, which is ordinary.\n    // Requiring a number was requiring a habit, and a habit is a name in disguise.\n    if (cs.position === 'fixed' || cs.position === 'absolute') {\n      // Free checks first, all off the computed style already read above.\n      // pointer-events:none means a scrim or a measurement probe, never a panel.\n      // COST GATE, AND IT IS NOT OPTIONAL. Everything below this line forces\n      // layout -- a rect read, then a hit test -- and the first version of this\n      // block ran both for EVERY out-of-flow element on every pass, then took\n      // data-w95-done OFF the small ones so they were measured again forever.\n      // On a page with hundreds of absolutely-positioned icons that is a\n      // permanent hot loop: reported as the CPU pinned at idle on chatgpt.com,\n      // and it is exactly the thrash ADR-004/ADR-006 exist to prevent.\n      // A panel always has children, and childElementCount costs nothing.\n      if (el.childElementCount > 0 &&\n        cs.pointerEvents !== 'none' && cs.visibility !== 'hidden' && cs.opacity !== '0') {\n        // Layout reads start here, and only for the handful of elements that got\n        // this far -- the ordering is the ADR-004/ADR-006 discipline, same as the\n        // page-backdrop test above.\n        const r = el.getBoundingClientRect();\n        // Closed, or the zero-size wrapper that HOSTS the panel: nothing to do.\n        // It is NOT re-dirtied here. A popover is mounted closed and opened by a\n        // style or class flip, and both are in the observer's attributeFilter --\n        // so the open lands as a mutation, which clears data-w95-done and brings\n        // the element back through here already measuring its real size. Marking\n        // it dirty on every pass instead bought exactly nothing and cost a\n        // forced layout per element per sweep, forever.\n        // Covers the whole viewport: never solidified, that would black out the\n        // page -- but never ignored either. A backdrop that TAKES POINTER EVENTS\n        // owns the window, and the wipe erases the dim it announces itself with.\n        // An invisible modal still eats every click, which is how CodeNomad's tabs\n        // stopped responding. Give the dim back, translucent, so the page stays\n        // legible under it. No pointer events or no explicit stacking order means\n        // scenery rather than a modal, and scenery is left alone.\n        if (r.width > innerWidth * 0.92 && r.height > innerHeight * 0.92) {\n          if (cs.zIndex && cs.zIndex !== 'auto') {\n            w.push(el, 'background-color', 'color-mix(in srgb, ' + T.background + ' 55%, transparent)',\n              el, 'background-image', 'none');\n          }\n        } else if (r.width >= 40 && r.height >= 24) {\n          // The hit test decides. Everything above admits far too much: if the\n          // paint stack under this element's own centre holds nothing but its own\n          // ancestors, it is an adornment inside its own card and inheriting the\n          // surface is correct. Anything foreign under it means it covers content\n          // it does not own, which is what floating means.\n          // STATE COLOURS ARE NOT REPAINTED, AND THAT IS MEASURED TOO. The\n          // working/waiting/done indicators carry their whole meaning in a\n          // background colour, which is why the wipe already excludes them. That\n          // exclusion is what lets this be a measurement instead of a second name\n          // list: after the wipe, a surface that needs solidifying is transparent\n          // BY DEFINITION, so anything still holding a colour is holding it on\n          // purpose. A condition, not an early return -- an element that keeps its\n          // own colour still needs the rest of process(): contrast, borders, radius.\n          const ownBg = parseRGB(cs.backgroundColor);\n          const cx = Math.min(Math.max(r.left + r.width / 2, 1), innerWidth - 1);\n          const cy = Math.min(Math.max(r.top + r.height / 2, 1), innerHeight - 1);\n          let stack = null;\n          if (!(ownBg && ownBg.a > 0.08)) {\n            try { stack = document.elementsFromPoint(cx, cy); } catch (e) { }\n          }\n          const at = stack ? stack.indexOf(el) : -1;\n          for (let k = at + 1; at >= 0 && k < stack.length; k++) {\n            const under = stack[k];\n            if (under === document.body || under === document.documentElement) continue;\n            if (under.contains(el)) continue;\n            w.push(el, 'background-color', T.surfaceRaised,\n              el, 'background-image', 'none',\n              el, 'color', T.textPrimary,\n              el, 'border-width', '2px',\n              el, 'border-style', 'solid',\n              el, 'border-color', T.bevelLight + ' ' + T.borderDark + ' ' + T.borderDark + ' ' + T.bevelLight,\n              el, 'box-shadow', 'none',\n              // The bevel is added to a box the site already sized; absorb it.\n              el, 'box-sizing', 'border-box');\n            break;\n          }\n        }\n      }\n    }\n\n    // 🚨 NEVER RE-GRADE A COLOUR THAT IS ALREADY OURS 🚨\n    // The repainter classifies by luminance, and our own tokens have luminances\n    // that land in its buckets: --backgroundSoft #1E1408 (lum 0.0088) and\n    // --surfaceRaised #362812 (lum 0.0234) both fall in the \"< 0.05\" bucket and\n    // were being re-graded to --surface on every pass. Caught live on wikipedia\n    // the moment the dark band was widened: body went from #1E1408 to #2A1C0A,\n    // and dialogs / th / hovercards would have drifted the same way, so the whole\n    // surface hierarchy would slowly collapse onto one shade. A palette value is\n    // by definition already correct — leave it alone.\n    const bgColor = cs.backgroundColor;\n    if (bgColor && bgColor !== 'transparent' && !PALETTE_RGB.has(bgColor)) {\n      const bg = parseRGB(bgColor);\n      if (bg && bg.a > 0.08) {\n        const L = elev(lum(bg));\n        const spread = Math.max(bg.r, bg.g, bg.b) - Math.min(bg.r, bg.g, bg.b);\n        const grayish = spread <= 24;\n        let repaint = null;\n        if (L > 0.45) {\n          // Flashbang surface — the far end of our own polarity, so on the golden\n          // palette this is literally the old \"light surface\" branch and on a light\n          // palette it is the site's dark chrome. Low-alpha tints go fully transparent\n          // (the \"gray rectangle blocks\"), neutral solids go dark brown, and\n          // saturated light tints (GitHub diff green/red, warning yellows,\n          // highlight rows) snap to the semantic token they meant.\n          if (bg.a <= 0.35) repaint = 'transparent';\n          else if (grayish) repaint = T.backgroundSoft;\n          else repaint = semanticToken(bg);\n        } else if (L >= 0.004) {\n          // DARK SURFACES. Two gaps used to let a site keep its own dark palette\n          // here, both measured on amazon.com:\n          //   #nav-belt  #131921  spread 14, lum 0.0094 — grayish, but the old\n          //     \"near-black is left alone\" floor was 0.015, so it survived.\n          //   #nav-main  #232f3e  spread 27, lum 0.0274 — over the old grayish\n          //     cutoff of 24 but under the saturated cutoff of 60, so it fell\n          //     through BOTH branches and was never touched at all.\n          // A dark navy chrome bar is a surface, not an accent, so the neutral\n          // band is widened to spread <= 60 and the two branches are merged:\n          // anything genuinely saturated (> 60) still goes to a semantic token,\n          // everything else joins the vintage brown scale.\n          //\n          // The floor drops from 0.015 to 0.004, which still leaves true black\n          // alone — video players and modal scrims sit at or near lum 0 — while\n          // catching real chrome like #131921.\n          repaint = spread > 60\n            ? semanticToken(bg)\n            : (L >= 0.13 ? T.surfaceAlt : L >= 0.05 ? T.surfaceRaised : T.surface);\n        }\n        if (repaint) {\n          w.push(el, 'background', repaint, el, 'background-color', repaint, el, 'background-image', 'none');\n        }\n      }\n    }\n\n    // Same guard for text: --textSecondary #B09558 has a channel spread of 88, so\n    // the \"not grayish\" branch would have flattened every secondary label to\n    // --textPrimary on the next pass. Palette in, palette out, untouched.\n    const fgColor = cs.color;\n    if (fgColor && !PALETTE_RGB.has(fgColor)) {\n      const fg = parseRGB(fgColor);\n      if (fg && fg.a > 0.1) {\n        // Contrast is measured against the ACTUAL backdrop this theme paints, not\n        // against a constant. It used to read `const darkBg = 0.008` with the\n        // comment \"luminance of #1E1408\" — correct, and correct only for golden:\n        // on a light palette that constant claims every dark text colour is\n        // perfectly readable, so the whole 4.5:1 branch below stops firing exactly\n        // where it is needed most.\n        const rawFgLum = lum(fg);\n        const fgLum = elev(rawFgLum);\n        const cr = contrast(rawFgLum, BG_SOFT_LUM);\n        const grayish = Math.max(fg.r, fg.g, fg.b) - Math.min(fg.r, fg.g, fg.b) <= 40;\n\n        if (el.closest && el.closest('a')) {\n          // Anything inside a link takes the link colour when it is unreadable,\n          // washed out, OR simply not one of ours — the last clause is iron law 5\n          // and it was missing. Measured on amazon.com: span#nav-cart-count kept\n          // #f08804 and span.navFooterDescText kept #999999, because both are\n          // legible enough (7.1:1 and 6.3:1) that the first two tests passed them\n          // through. Legible is not the same as on-palette.\n          if (cr < 4.5 || (fgLum > 0.4 && grayish) || !PALETTE_RGB.has(fgColor)) {\n            w.push(el, 'color', T.link);\n          }\n        } else {\n          if (cr < 4.5) {\n            w.push(el, 'color', T.textPrimary);\n          } else if (grayish) {\n            if (fgLum > 0.4) w.push(el, 'color', T.textPrimary);\n            else if (fgLum > 0.15) w.push(el, 'color', T.textSecondary);\n          } else {\n            // Legible but SATURATED text — a site's own coloured heading, tag or\n            // status label. Left alone pre-1.4.0, which is another way sites kept\n            // their own voice, so it gets normalised too: to --textPrimary.\n            //\n            // Deliberately NOT to semanticToken() like the background path does.\n            // --success/--warning/--danger are BACKGROUND tokens; as text on\n            // --backgroundSoft they measure 2.6:1 / 3.4:1 / 1.8:1, all far under\n            // the WCAG AA 4.5:1 UI.md also demands. Snapping coloured text onto\n            // them would trade one iron law for a worse violation of the\n            // accessibility floor — and UI.md settles that tie itself: \"error\n            // text must be readable without color alone.\"\n            w.push(el, 'color', T.textPrimary);\n          }\n        }\n      }\n    }\n\n    // Light/white border lines (table rules, row separators, panel edges) →\n    // vintage brown, per side. Fields keep their golden bevels (buttons are\n    // already excluded by shouldSkip). Saturated colored borders (e.g. red\n    // error outlines) are left alone via the grayish check.\n    const tg = (el.tagName || '').toUpperCase();\n    if (!/^(INPUT|TEXTAREA|SELECT|BUTTON)$/.test(tg)) {\n      const SIDES = ['Top', 'Right', 'Bottom', 'Left'];\n      for (let i = 0; i < 4; i++) {\n        const s = SIDES[i];\n        if (cs['border' + s + 'Width'] === '0px' || cs['border' + s + 'Style'] === 'none') continue;\n        const bc = parseRGB(cs['border' + s + 'Color']);\n        if (!bc || bc.a <= 0.1) continue;\n        const grayish = Math.max(bc.r, bc.g, bc.b) - Math.min(bc.r, bc.g, bc.b) <= 60;\n        if (grayish && elev(lum(bc)) > 0.18) {\n          w.push(el, 'border-' + s.toLowerCase() + '-color', T.surfaceRaised);\n        }\n      }\n    }\n  }\n\n  function shouldSkip(el) {\n    const tag = (el.tagName || '').toUpperCase();\n    if (TAG_SKIP.test(tag)) return true;\n    if (tag === 'INPUT') {\n      const t = (el.type || '').toLowerCase();\n      // Natively-rendered controls: repainting them hides the checked state.\n      // checkbox/radio are handled specially in process() (need computed\n      // style to tell a real control from a hidden custom-switch proxy).\n      if (t === 'range' || t === 'color' || t === 'file') return true;\n    }\n    if (el.closest && el.closest('button')) return true;\n    // CSS above owns CodeNomad's native semantic state dot. Repainting it would\n    // erase the working/idle distinction after the first mutation batch.\n    try { if (el.matches && el.matches('.status-indicator.session-status > .status-dot')) return true; } catch (e) { }\n    try { if (el.closest && el.closest(JS_SKIP_SELECTOR)) return true; } catch (e) { }\n    return false;\n  }\n\n  // Mutations accumulate in a queue with a fixed 60ms flush. The previous\n  // clearTimeout+reset pattern silently DROPPED every batch except the last\n  // one (each reset discarded the prior closure's mutations) and could starve\n  // forever on continuously-mutating pages.\n  let debounceTimer = null;\n  let pendingMuts = [];\n  const attrCooldown = new WeakMap(); // element -> last attribute-triggered process time\n\n  // Generic circuit breaker for sites not on the known-host list. A universal\n  // userscript cannot predict every future SPA, so it must fail cold rather than\n  // turn a new framework's mutation storm into a space heater. Once tripped, the\n  // CSS theme remains active but all JavaScript repaint work stops for this page.\n  const MUTATION_WINDOW_MS = 2000;\n  const MUTATION_RECORD_LIMIT = 1200;\n  const MUTATION_WORK_LIMIT_MS = 180;\n  const ADDED_NODE_BUDGET = 500;\n  let mutationWindowStart = performance.now();\n  let mutationRecords = 0;\n  let mutationWorkMs = 0;\n  let repainterSuspended = CSS_ONLY_MODE;\n\n  function resetMutationWindow(now) {\n    mutationWindowStart = now;\n    mutationRecords = 0;\n    mutationWorkMs = 0;\n  }\n\n  function suspendRepainter(reason) {\n    if (repainterSuspended) return;\n    repainterSuspended = true;\n    try { mainObserver.disconnect(); } catch (e) { }\n    try { shadowObserver.disconnect(); } catch (e) { }\n    if (debounceTimer) { clearTimeout(debounceTimer); debounceTimer = null; }\n    if (sweepTimer) { clearTimeout(sweepTimer); sweepTimer = null; sweepPlannedAt = 0; }\n    pendingMuts.length = 0;\n    forcePassesOwed = 0;\n    try {\n      document.documentElement.setAttribute('data-w95-perf', 'css-only');\n      document.documentElement.setAttribute('data-w95-perf-reason', reason);\n    } catch (e) { }\n  }\n\n  function noteMutationPressure(records) {\n    const now = performance.now();\n    if (now - mutationWindowStart >= MUTATION_WINDOW_MS) resetMutationWindow(now);\n    mutationRecords += records;\n    if (mutationRecords > MUTATION_RECORD_LIMIT || mutationWorkMs > MUTATION_WORK_LIMIT_MS) {\n      suspendRepainter(mutationRecords > MUTATION_RECORD_LIMIT ? 'mutation-rate' : 'mutation-work');\n      return true;\n    }\n    return false;\n  }\n\n  function addWorkPressure(ms, reason) {\n    const now = performance.now();\n    if (now - mutationWindowStart >= MUTATION_WINDOW_MS) resetMutationWindow(now);\n    mutationWorkMs += ms;\n    if (mutationWorkMs > MUTATION_WORK_LIMIT_MS) suspendRepainter(reason);\n  }\n\n  function onMutations(mutations) {\n    if (repainterSuspended || noteMutationPressure(mutations.length)) return;\n    for (let i = 0; i < mutations.length; i++) pendingMuts.push(mutations[i]);\n    if (debounceTimer) return;\n    debounceTimer = setTimeout(() => {\n      debounceTimer = null;\n      if (repainterSuspended) { pendingMuts.length = 0; return; }\n      const workStarted = performance.now();\n      const batch = pendingMuts;\n      pendingMuts = [];\n      const w = [];\n      const added = [];\n      let styleishAdded = false;\n      for (const m of batch) {\n        // Class/bgcolor changes restyle existing elements (SPA hydration, lazy\n        // CSS-in-JS) — re-process them or they keep stale baked-in colors.\n        // Hover-chain elements are skipped inside process() and retried later,\n        // so hover class-toggles don't bake in highlight colors.\n        if (m.type === 'attributes') {\n          const t = m.target;\n          if (t && t.nodeType === 1) {\n            // No time-window mute here any more — our own style writes are\n            // filtered out by identity in flushWrites before this ever runs.\n            // Cooldown: carousels/virtual scrollers toggle classes many times a\n            // second; re-processing each toggle (computed-style read + writes)\n            // is a jank source. During the cooldown just mark the element dirty\n            // — the next light sweep picks up its settled state.\n            const now = Date.now();\n            if ((attrCooldown.get(t) || 0) + 500 > now) {\n              t.removeAttribute('data-w95-done');\n            } else {\n              attrCooldown.set(t, now);\n              t.removeAttribute('data-w95-done');\n              process(t, false, w);\n            }\n            const tag = (t.tagName || '').toUpperCase();\n            if (tag === 'STYLE' || (tag === 'LINK' && (t.rel || '').toLowerCase().includes('stylesheet'))) {\n              styleishAdded = true;\n            }\n          }\n          continue;\n        }\n        if (m.type === 'childList') {\n          const target = m.target;\n          if (target && target.nodeType === 1) {\n            const tag = (target.tagName || '').toUpperCase();\n            if (tag === 'STYLE' || (tag === 'LINK' && (target.rel || '').toLowerCase().includes('stylesheet'))) {\n              styleishAdded = true;\n            }\n          }\n        }\n        for (const node of m.addedNodes) {\n          if (node.nodeType !== 1) continue;\n          added.push(node);\n          if (!styleishAdded) {\n            const tag = (node.tagName || '').toUpperCase();\n            if (tag === 'STYLE' || (tag === 'LINK' && (node.rel || '').toLowerCase().includes('stylesheet'))) {\n              styleishAdded = true;\n            } else if (node.querySelector && node.querySelector('style,link[rel*=stylesheet i]')) {\n              styleishAdded = true;\n            }\n          }\n        }\n      }\n\n      // De-dup the batch before touching anything (v1.3.0). The parser and SPA\n      // hydration routinely report a container AND its descendants as separate\n      // addedNodes records in the SAME batch, and the old loop walked every\n      // record's whole subtree — so a node covered by an ancestor's walk was\n      // re-read, and the code even cleared its data-w95-done first to guarantee\n      // the redundant pass happened. Keep only records with no added ancestor in\n      // this batch; walking up parentNode is O(depth), never O(batch²).\n      if (added.length) {\n        const inBatch = new Set(added);\n        let addedProcessed = 0;\n        let addedTruncated = false;\n        for (const node of added) {\n          let covered = false;\n          for (let p = node.parentNode; p; p = p.parentNode) {\n            if (inBatch.has(p)) { covered = true; break; }\n          }\n          // Added then removed again inside the same 60ms window: a detached\n          // element has no computed style worth reading and no pixels to fix.\n          if (covered || !node.isConnected) continue;\n          node.removeAttribute && node.removeAttribute('data-w95-done');\n          process(node, false, w);\n          addedProcessed++;\n          const kids = node.getElementsByTagName('*');\n          for (let i = 0; i < kids.length; i++) {\n            if (addedProcessed >= ADDED_NODE_BUDGET) { addedTruncated = true; break; }\n            kids[i].removeAttribute && kids[i].removeAttribute('data-w95-done');\n            process(kids[i], false, w);\n            addedProcessed++;\n          }\n          if (addedProcessed >= ADDED_NODE_BUDGET) { addedTruncated = true; break; }\n        }\n        // Only stylesheet-bearing additions need a force re-verify. Plain DOM\n        // churn is already processed inline above and does not justify another\n        // full sweep.\n        if (styleishAdded || addedTruncated) {\n          stylesDirty = stylesDirty || styleishAdded;\n          requestForceSweep();\n        }\n      }\n      flushWrites(w);\n      addWorkPressure(performance.now() - workStarted, 'mutation-work');\n    }, 60);\n  }\n  const mainObserver = new MutationObserver(onMutations);\n  const shadowObserver = new MutationObserver(onMutations);\n\n  if (!CSS_ONLY_MODE && document.documentElement) {\n    mainObserver.observe(document.documentElement, {\n      childList: true,\n      subtree: true,\n      attributes: true,\n      attributeFilter: ['class', 'bgcolor', 'background', 'style']\n    });\n  }\n\n  // Force passes are budgeted: on huge pages (endless feeds) each pass\n  // re-verifies a rotating 2500-element window instead of the whole DOM, so a\n  // single pass never janks the main thread; full coverage arrives over a few\n  // rotations. The scheduler is now adaptive: when nothing changes, it backs\n  // off instead of ticking forever in the background like a stubborn appliance.\n  const FORCE_BUDGET = 2500;\n  let forceCursor = 0;\n\n  let forcePassesOwed = 0;\n  let sweepTimer = null;\n  let stylesDirty = true;\n\n  // 🚨 THE SWEEP RATE IS FLOOR-LIMITED. NOTHING MAY SCHEDULE A SWEEP AT 0ms 🚨\n  // Measured on a real chatgpt.com conversation (3392 elements, 15s, primitives\n  // counted by wrapping them on the prototypes):\n  //     querySelectorAll ....    151 calls  -> ~10 sweeps per SECOND\n  //     getComputedStyle ....  42563 calls\n  //     Element.closest .....  80114 calls\n  //     setAttribute ........  43080 calls\n  //     long tasks .......... 14158 ms out of 15000 (~94% of wall time)\n  // With the script disabled the same page spent 2517ms. So the engine was\n  // running roughly 150 full sweeps in 15 seconds instead of ten.\n  //\n  // Cause: requestForceSweep() ended in scheduleNextSweep(true), i.e. a 0ms\n  // timer, and it is called from the mutation handler on every batch that\n  // contains added nodes. On a React app that inserts nodes continuously, every\n  // insertion queued an immediate full sweep, whose own writes and stylesheet\n  // check queued the next one. Back-to-back sweeps with no floor.\n  //\n  // Two rules now make that impossible:\n  //   1. MIN_SWEEP_GAP — a hard minimum between the END of one sweep and the\n  //      START of the next. However much churn arrives, sweeps cannot exceed\n  //      one per second. This is the actual safety property; the adaptive\n  //      backoff below is only an idle optimisation on top of it.\n  //   2. A pending timer that already fires SOONER is never replaced by a later\n  //      one, and never cancelled and re-armed. The old code cleared and re-armed\n  //      the timer on every call, so a stream of requests could keep pushing the\n  //      timer around instead of letting it fire.\n  const MIN_SWEEP_GAP = 1000;\n  let lastSweepEnd = 0;\n  let sweepPlannedAt = 0;\n\n  function scheduleSweep(delay) {\n    if (repainterSuspended || document.hidden) return;\n    const now = Date.now();\n    // Never sooner than MIN_SWEEP_GAP after the last sweep finished.\n    const earliest = lastSweepEnd + MIN_SWEEP_GAP - now;\n    const d = Math.max(delay, earliest, 0);\n    const fireAt = now + d;\n    // An already-pending sweep that lands sooner wins; do not churn the timer.\n    if (sweepTimer && sweepPlannedAt <= fireAt) return;\n    if (sweepTimer) clearTimeout(sweepTimer);\n    sweepPlannedAt = fireAt;\n    sweepTimer = setTimeout(() => {\n      sweepTimer = null;\n      sweepPlannedAt = 0;\n      if (document.hidden) return;\n\n      const force = forcePassesOwed > 0;\n      if (force) forcePassesOwed--;\n\n      runSweeper(force);\n      lastSweepEnd = Date.now();\n\n      // No automatic reschedule here. Fresh work comes from mutations,\n      // stylesheet loads, visibility changes, or the explicit load-time passes.\n    }, d);\n  }\n\n  // A request means \"there is fresh work, revisit soon\" — soon being the fast\n  // lane, NEVER immediately. runSweeper itself calls this (via stripHoverSheets\n  // spotting a changed sheet), so an immediate schedule here is a direct\n  // sweep-calls-sweep loop.\n  function requestForceSweep() {\n    if (repainterSuspended) return;\n    if (forcePassesOwed < 2) forcePassesOwed++;\n    scheduleSweep(1500);\n  }\n\n  function runSweeper(force) {\n    if (repainterSuspended) return;\n    const sweepStarted = performance.now();\n    // Prune shadow roots whose hosts left the DOM (SPA navigations) — keeping\n    // them leaks memory and bloats every sweep on long sessions.\n    piercedRoots.forEach(root => { try { if (!root.host || !root.host.isConnected) piercedRoots.delete(root); } catch (e) { } });\n    // Hover-rule scanning is the expensive part. Only do it when we have a\n    // concrete stylesheet signal, or when the caller explicitly asked for a\n    // full re-verify.\n    const scanStyles = force || stylesDirty;\n    if (scanStyles) {\n      stylesDirty = false;\n      stripHoverSheets(document);\n      piercedRoots.forEach(root => { try { stripHoverSheets(root); } catch (e) { } });\n    }\n    const searchRoots = [document, ...piercedRoots];\n    // ONE write queue for the whole sweep across every root: the flush at the\n    // end is what collapses thousands of style invalidations into a single\n    // recalc. Never flush inside the loop (see the flushWrites comment).\n    const w = [];\n    searchRoots.forEach(root => {\n      try {\n        const all = root.querySelectorAll(force ? '*' : '*:not([data-w95-done])');\n        if (force && all.length > FORCE_BUDGET) {\n          const start = forceCursor % all.length;\n          for (let n = 0; n < FORCE_BUDGET; n++) { process(all[(start + n) % all.length], true, w); }\n          forceCursor += FORCE_BUDGET;\n        } else {\n          for (let i = 0; i < all.length; i++) { process(all[i], force, w); }\n        }\n      } catch (e) { }\n    });\n    flushWrites(w);\n    addWorkPressure(performance.now() - sweepStarted, 'sweep-work');\n  }\n\n  // Elements processed before the site's CSS finished loading bake in unstyled\n  // values and would otherwise stay wrong forever (white surfaces that \"heal\"\n  // only when the SPA happens to re-render them). Full re-verify passes\n  // (force=true) re-check EVERY element: at DOMContentLoaded, again 1s later\n  // once late CSS settled, then on demand whenever requestForceSweep() fires.\n  // The write-if-changed guard in setImp keeps repeat passes cheap.\n  function startSweeping() {\n    injectLate();\n    if (CSS_ONLY_MODE) {\n      try {\n        document.documentElement.setAttribute('data-w95-perf', 'css-only');\n        document.documentElement.setAttribute('data-w95-perf-reason', 'known-high-churn-host');\n      } catch (e) { }\n      // One final cascade-order correction after late app CSS arrives. No DOM\n      // scan, no observer, no repeating timer.\n      window.addEventListener('load', injectLate, { once: true });\n      return;\n    }\n    // The boot pass measured ONE 716ms long task on a 16921-element page, right\n    // when the site's own init scripts are competing for the main thread — the\n    // \"have to reload a couple of times before it comes up\" symptom. The\n    // read/write split above is what actually shrinks it; deferring the second\n    // pass past load keeps it out of the critical window as well.\n    // CSS already paints immediately. Corrective JS work is deferred and\n    // floor-limited instead of blocking DOMContentLoaded with a full traversal.\n    requestForceSweep();\n    setTimeout(() => { stylesDirty = true; requestForceSweep(); }, 1500);\n\n    if (!IS_TOP) {\n      // Sub-frame: bounded settling passes, then nothing. The MutationObserver\n      // stays live, so a late-loading embed still gets themed — that path is\n      // event-driven and costs zero while idle.\n      setTimeout(() => { stylesDirty = true; requestForceSweep(); }, 3000);\n      return;\n    }\n\n    // Top frame: event-driven sweeps only. Idle means idle; fresh work\n    // re-arms the scheduler through mutations, stylesheet loads, or focus/visibility changes.\n\n    // Pages that finished loading while the tab was hidden got no sweeps; on\n    // return, re-verify immediately so the user never sees stale white. This is\n    // the ONE place a sweep still runs synchronously without waiting for the\n    // floor — it is user-initiated (they just looked at the tab) and happens at\n    // most once per tab switch, so it cannot form a loop.\n    document.addEventListener('visibilitychange', () => {\n      if (!document.hidden) {\n        // A tab switch must not synchronously walk a 20,000-node conversation.\n        // Repaint later through the same rate-limited lane as every other cause.\n        stylesDirty = true;\n        requestForceSweep();\n      } else if (sweepTimer) {\n        clearTimeout(sweepTimer);\n        sweepTimer = null;\n        sweepPlannedAt = 0;\n      }\n    });\n\n    // Late external stylesheet loads can alter computed styles without DOM\n    // churn. Catch them once and reschedule a real pass instead of polling.\n    document.addEventListener('load', (evt) => {\n      const t = evt.target;\n      if (!t || t.nodeType !== 1) return;\n      if ((t.tagName || '').toUpperCase() !== 'LINK') return;\n      const rel = (t.rel || '').toLowerCase();\n      if (rel.includes('stylesheet')) {\n        stylesDirty = true;\n        requestForceSweep();\n      }\n    }, true);\n  }\n\n  if (document.readyState === 'loading') {\n    document.addEventListener('DOMContentLoaded', startSweeping, { once: true });\n  } else {\n    startSweeping();\n  }\n\n  ";

// The one place insertCSS cannot reach. It produces a DOCUMENT stylesheet, and a
// document stylesheet does not cross a shadow boundary, so every rule written for
// a shadow tree has to be carried in and injected root by root -- which is what
// the repainter's pierceShadow does with this.
const SHADOW_CSS = "\n    /* Height-only 1ms transition + near-zero animation (see GLOBAL_CSS motion\n       note): transitionend/animationend keep firing for collapse + rc-motion\n       state machines, without touching top/left/width/transform. */\n    /* animation-fill-mode: forwards for the same snapback reason as the global\n       layer -- a shadow tree reveals its content the same way a light one does. */\n    * { border-radius: 0 !important; transition-property: height, max-height, min-height !important; transition-duration: 0.001s !important; transition-delay: 0s !important; animation-duration: 0.001s !important; animation-delay: 0s !important; animation-iteration-count: 1 !important; animation-fill-mode: forwards !important; }\n    /* Zero shadow / zero blur, same as the global layer (UI.md law 2). Shadow\n       roots are where modern component libraries keep their elevation, so\n       skipping this here would leave every web-component card floating while the\n       rest of the page is flat. */\n    *, *::before, *::after { box-shadow: none !important; text-shadow: none !important; backdrop-filter: none !important; -webkit-backdrop-filter: none !important; }\n    *:not(img):not(svg):not(video):not(canvas):not(picture):not(image), *::before, *::after { filter: none !important; }\n    /* Type ladder, same five steps and the same disjoint-selector trick as the\n       global layer (see the specificity note there — layering the exceptions on\n       top instead silently flattens every heading to 12px). */\n    *:not(svg):not(path):not(i):not(h1):not(h2):not(h3):not(h4):not(h5):not(h6):not(small):not(sub):not(sup):not(figcaption):not([class*=\"icon\" i]):not([class*=\"fa-\" i]):not([class*=\"symbols\" i]):not([class*=\"glyph\" i]):not([class*=\"mdi\" i]):not([class*=\"bi-\" i]):not([class*=\"codicon\" i]):not([class*=\"lucide\" i]):not([class*=\"octicon\" i]):not([class*=\"remixicon\" i]):not([class*=\"phosphor\" i]):not([class*=\"iconify\" i]):not([class*=\"feather\" i]):not([data-icon]):not([data-cds=\"Icon\"]) {\n      font-size: 12px !important; line-height: 1.2 !important;\n    }\n    h1 { font-size: 16px !important; line-height: 1.2 !important; }\n    h2, h3, h4, h5, h6 { font-size: 14px !important; line-height: 1.2 !important; }\n    small, sub, sup, figcaption { font-size: 10px !important; line-height: 1.2 !important; }\n    *:not(svg):not(path) { font-weight: 400 !important; font-style: normal !important; }\n    /* ':host X' matches X inside this shadow tree and scores (0,1,1), beating the\n       (0,0,2) base rule above — the same specificity fix the global layer makes\n       with ':root'. A bare 'b' here would lose and nothing would be bold. */\n    :host b, :host strong, :host th, :host h1, :host h2, :host h3, :host h4, :host h5, :host h6,\n    :host summary, :host legend, :host label, :host button, :host shreddit-button, :host [role=\"button\"],\n    :host .btn, :host [class~=\"button\" i], :host [class~=\"btn\" i] { font-weight: 700 !important; }\n    :host i, :host em, :host cite, :host var, :host dfn, :host q, :host blockquote { font-style: italic !important; }\n    /* No 99,999-second hover freeze here either. Shadow-tree pseudo-elements\n       are exactly where shimmer loaders and decorative hover layers tend to live,\n       so keeping permanent transitions here is especially expensive. */\n    *:not(svg):not(path):not(i):not([class*=\"icon\" i]):not([class*=\"fa-\" i]):not([class*=\"symbols\" i]):not([class*=\"glyph\" i]):not([class*=\"mdi\" i]):not([class*=\"bi-\" i]):not([class*=\"codicon\" i]):not([class*=\"lucide\" i]):not([class*=\"octicon\" i]):not([class*=\"remixicon\" i]):not([class*=\"phosphor\" i]):not([class*=\"iconify\" i]):not([class*=\"feather\" i]):not([data-icon]):not([data-cds=\"Icon\"]) {\n      font-family: Verdana_m1, Verdana, Tahoma, \"MS Sans Serif\", sans-serif !important; -webkit-font-smoothing: none !important; -moz-osx-font-smoothing: unset !important; font-smooth: never !important; text-rendering: optimizeSpeed !important;\n    }\n    input, textarea, select, option, button, code, pre, kbd, samp, tt, [class*=\"code\" i], [class*=\"mono\" i] { font-family: Verdana_m1, Verdana, Tahoma, \"MS Sans Serif\", sans-serif !important; }\n    :host { --radius: 0px; --shreddit-border-radius: 0px; --md-sys-shape-corner-full: 0px; background-color: transparent !important; background-image: none !important; color: #93A1A1 !important; }\n    /* Ad-iframe load-flash fix, scoped to known ad hosts only — see GLOBAL_CSS note (unconditional would break transparent widget overlays) */\n    iframe[src*=\"doubleclick.net\" i], iframe[src*=\"googlesyndication.com\" i],\n    iframe[src*=\"google.com/ads\" i], iframe[id*=\"google_ads_iframe\" i],\n    iframe[id*=\"gpt_unit\" i], iframe[src*=\"adservice.google\" i],\n    iframe[src*=\"amazon-adsystem.com\" i], iframe[src*=\"taboola.com\" i],\n    iframe[src*=\"outbrain.com\" i] {\n      background-color: #073642 !important;\n    }\n    /* 🚨 :not(:root) IS LOAD-BEARING, DO NOT DROP IT 🚨\n       Inside a shadow tree an attribute selector can never match the document root,\n       so this guard costs nothing there — but this stylesheet does not only live in\n       shadow trees. tools/build-desktop.js CONCATENATES GLOBAL_CSS + SHADOW_CSS into\n       the single sheet the Electron shim injects into a whole document, and there\n       [class] matches <html class=\"dark\"> like any other element. The root then gets\n       color: inherit with nothing above it to inherit from, so it computes to the\n       INITIAL value — black — and every descendant inherits that same black through\n       this very rule. background-color: transparent does the same to the root's\n       background.\n       That is what made Claude unreadable: black text on the themed brown, immune\n       even to an inline important because the sheet is injected at user origin\n       there. Proved live over CDP: removing the class attribute from <html> turned\n       the whole transcript from rgb(0,0,0) to rgb(212,200,154) and restoring it put\n       the black back. Apps whose <html> carries no class (the Electron shell,\n       about:blank) were untouched, which is exactly why it read as a Claude-specific\n       mystery for eight rounds. :root is never a thing to hand inherit to.\n       (No backticks in this comment: it sits inside a template literal and one would\n       end it. node --check caught that too, on the very same edit.) */\n    div, span, section, article, aside, nav, header, footer, main {\n      /* Blanket wipe retired (T-121) */\n    }\n\n\n\n    button, input[type=\"button\"], input[type=\"submit\"], input[type=\"reset\"], shreddit-button, .btn,\n    [class~=\"button\" i], [class~=\"btn\" i], a[role=\"button\"], span[role=\"button\"], summary {\n      background-color: #1B444F !important; color: #93A1A1 !important; border: 2px solid !important; border-color: #36667D #001F27 #001F27 #36667D !important; box-shadow: none !important;\n      cursor: pointer !important; font-family: Verdana_m1, Verdana, Tahoma, \"MS Sans Serif\", sans-serif !important; box-sizing: border-box !important;\n      padding: 2px 6px !important; min-width: 24px !important; min-height: 20px !important;\n    }\n    button:active, shreddit-button:active, .btn:active, [class~=\"button\" i]:active, [class~=\"btn\" i]:active, summary:active { background-color: #073642 !important; border: 2px solid !important; border-color: #001F27 #36667D #36667D #001F27 !important; box-shadow: none !important; transform: translate(1px, 1px) !important; }\n    /* Disabled: label colour only, bevel and surface stay (UI.md bans opacity here) */\n    button:disabled, shreddit-button:disabled, button[aria-disabled=\"true\"], [role=\"button\"][aria-disabled=\"true\"] {\n      color: #426066 !important; background-color: #1B444F !important; opacity: 1 !important; cursor: not-allowed !important; border: 2px solid !important; border-color: #36667D #001F27 #001F27 #36667D !important; box-shadow: none !important;\n    }\n\n    /* Paint-only: display:none here deleted ::before icon glyphs (see GLOBAL_CSS) */\n    button::before, button::after, .btn::before, .btn::after { background: transparent !important; box-shadow: none !important; filter: none !important; }\n    /* Same exclusions as the light-DOM wipe retired in T-121 */\n\n    input:not([type=\"button\"]):not([type=\"submit\"]):not([type=\"reset\"]):not([type=\"checkbox\"]):not([type=\"radio\"]) { background-color: #002029 !important; color: #93A1A1 !important; border: 2px solid !important; border-color: #001F27 #36667D #36667D #001F27 !important; box-shadow: none !important; box-sizing: border-box !important; }\n    input:not([type=\"button\"]):not([type=\"submit\"]):not([type=\"reset\"]):not([type=\"checkbox\"]):not([type=\"radio\"]):not([type=\"range\"]):not([type=\"color\"]):not([type=\"file\"]), select { height: 20px !important; padding: 1px 3px !important; }\n    textarea { min-height: 64px !important; resize: none !important; padding: 1px 3px !important; }\n    /* appearance:auto not forced here either — see GLOBAL_CSS checkbox note */\n    input[type=\"checkbox\"], input[type=\"radio\"] { accent-color: #51A2DB !important; background-image: none !important; }\n    input::placeholder, textarea::placeholder { color: #426066 !important; }\n    input:focus-visible, textarea:focus-visible, select:focus-visible, button:focus-visible, a:focus-visible,\n    summary:focus-visible, [tabindex]:focus-visible, [role=\"button\"]:focus-visible, [contenteditable]:focus-visible {\n      outline: 1px dotted #93A1A1 !important; outline-offset: -4px !important;\n    }\n    th { background-color: #073642 !important; color: #93A1A1 !important; border: 2px solid !important; border-color: #36667D #001F27 #001F27 #36667D !important; box-shadow: none !important; }\n    ::selection { background-color: #1B444F !important; color: #93A1A1 !important; }\n\n    /* Hover recolor stays zeroed out here too — only real clickable controls respond. */\n    button:hover, shreddit-button:hover, .btn:hover { background-color: #2B4F59 !important; border: 2px solid !important; border-color: #36667D #001F27 #001F27 #36667D !important; box-shadow: none !important; }\n    a, a:link { color: #51A2DB !important; text-decoration: none !important; }\n    a:visited { color: #8D9EA1 !important; }\n    a:hover { text-decoration: underline !important; background-color: transparent !important; }";

// Everything the extracted body reads from the userscript's outer scope has to be
// handed to it here. That list is not maintained by hand and hope: build-desktop.js
// fails the build if the userscript ever starts reading something this prelude does
// not define, because the failure mode otherwise is a ReferenceError thrown inside
// executeJavaScript, which surfaces as "the theme just does not work" and nothing
// else.
const REPAINTER_FIX = `(() => {
  if (window.__wintageRepainter) return "already running";
  window.__wintageRepainter = true;

  const W95_VERSION = '1.26.0';

  // This pack's palette, whole. Not trimmed to what the repainter happens to read
  // today: it builds PALETTE_RGB from Object.keys(T) to recognise its own colours,
  // so a missing token would make it treat one of our own greys as the site's.
  const T = {
    background: '#002B36',
    backgroundSoft: '#073642',
    surface: '#073642',
    surfaceRaised: '#1B444F',
    surfaceAlt: '#2B4F59',
    borderDark: '#001F27',
    borderHighlight: '#51A2DB',
    bevelLight: '#36667D',
    borderMuted: '#586E75',
    link: '#51A2DB',
    textPrimary: '#93A1A1',
    textSecondary: '#8D9EA1',
    textMuted: '#426066',
    accentTeal: '#008080',
    accentTealDeep: '#004C4C',
    success: '#4A7A20',
    warning: '#7A7A20',
    danger: '#7A2020',
    dangerText: '#DD7D7D',
    selection: '#1B444F',
    compareBack: '#002029'
  };

  let IS_TOP = true;
  try { IS_TOP = window.top === window.self; } catch (e) { IS_TOP = false; }

  // The userscript drops to CSS-only on a short list of hosts whose DOM churns
  // hard enough that the repainter costs more than it wins. A desktop shell is one
  // known application rather than the open web, and shipping the repainter here is
  // the entire point of this block, so it stays on.
  const CSS_ONLY_MODE = false;

  // Polarity. Every luminance threshold downstream was written against a dark
  // palette; elev() normalises the incoming value so the same numbers keep their
  // meaning on a light one. Identical to the userscript's, deliberately.
  function lum({ r, g, b }) {
    const lin = v => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4); };
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
  }
  function hexLum(hex) {
    return lum({ r: parseInt(hex.slice(1, 3), 16), g: parseInt(hex.slice(3, 5), 16), b: parseInt(hex.slice(5, 7), 16) });
  }
  function contrast(a, b) { return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05); }
  const BG_LUM = hexLum(T.background);
  const BG_SOFT_LUM = hexLum(T.backgroundSoft);
  const DARK = BG_LUM < 0.18;
  const elev = L => (DARK ? L : 1 - L);

  const SHADOW_CSS = ` + JSON.stringify(SHADOW_CSS) + `;

  function injectStyle(root, id, content) {
    if (root.querySelector && root.querySelector('style[data-w95="' + id + '"]')) return;
    const s = document.createElement('style');
    s.setAttribute('data-w95', id);
    s.setAttribute('data-w95-ver', W95_VERSION);
    s.textContent = content;
    const target = root.head || root.documentElement || root;
    try { target.insertBefore(s, target.firstChild); } catch (e) {
      try { (document.head || document.documentElement).appendChild(s); } catch (e2) { }
    }
  }

  // In the browser the theme is a <style> node and injectLate's whole job is to
  // move it to the end of <head> so late application CSS cannot outrank it by
  // position. Here the stylesheet arrives through insertCSS, which is not a DOM
  // node at all and already applies at author origin after the document's own
  // sheets. There is nothing to move, so this is a deliberate no-op rather than a
  // reimplementation of something that does not apply.
  function injectLate() { }

` + REPAINTER_BODY + `

  return "repainter active";
})()`;

// ─── SCROLLING UP MUST MEAN SCROLLING UP ─────────────────────────────────────
// Reported as: read something in the middle of a long conversation, and the view
// snaps back down, repeatedly, until you drag the scrollbar by hand.
//
// Recorded on the live application before a line of this was written, with a
// stack captured on every programmatic scroll. The theme is not the mover, and
// that was worth proving rather than assuming -- the scroller carried zero inline
// writes from this shim, no scrollbar-width, no overflow-y, no bevel. What the
// recorder caught is the application pinning itself to the bottom:
//
//   t+0    scrollTo   from 4400 -> {top: 5896, behavior: "smooth"}   scrollToBottom
//   t+75   scrollTop  from 2600 -> 5896                              ResizeObserver
//
// The reader was at 2600, some 3300px from the bottom. Every chunk that streams in
// resizes the content, the resize observer re-pins, and the reader loses their
// place. A theme has no business rewriting an application's behaviour, so the rule
// here is as narrow as the evidence: keep the intent the USER expressed.
//
// The discriminator is transient activation, and it is exact. Clicking a
// "jump to latest" button leaves navigator.userActivation.isActive true; a
// ResizeObserver callback firing because a token arrived does not. So a
// programmatic scroll TO THE BOTTOM, aimed at a scroller the reader has
// deliberately left, with no user gesture behind it, is dropped. Everything else
// -- their own wheel, their own drag, their own click on the button, the app's
// pinning while they ARE at the bottom -- is untouched, and the moment they come
// back to the bottom the app is free to pin again.
const SCROLL_INTENT_FIX = `(() => {
  if (window.__wintageScrollIntent) return "already running";
  window.__wintageScrollIntent = true;

  // How close to the bottom still counts as "at the bottom". A couple of lines,
  // not a screenful: this decides when the app is allowed to pin again.
  const AT_BOTTOM = 64;
  // How far away counts as "deliberately reading something else". Well past any
  // rounding, sub-pixel or bevel noise.
  const AWAY = 200;

  const AWAY_FLAG = "__wintageReaderAway";
  const proto = Element.prototype;
  const desc = Object.getOwnPropertyDescriptor(proto, "scrollTop");
  const rawScrollTo = proto.scrollTo;

  const range = el => el.scrollHeight - el.clientHeight;
  const distance = el => range(el) - desc.get.call(el);
  // Called from inside an observer callback? Then this is the application
  // reacting, not a person acting. Reading a stack is not free, which is why it
  // happens only after every cheap test has already said "bottom-aimed scroll on
  // a scroller the reader left" -- a handful of times per session, not per frame.
  const reactive = () => {
    let st = "";
    try { st = new Error().stack || ""; } catch (e) { return false; }
    return /ResizeObserver|MutationObserver|IntersectionObserver/.test(st);
  };

  const gesture = () => {
    try { return !!(navigator.userActivation && navigator.userActivation.isActive); }
    catch (e) { return true; }        // cannot tell -> never block
  };

  // Only ever say yes when everything is known. Anything unmeasurable falls
  // through to "allow", because a theme dropping a scroll it did not understand
  // is a far worse failure than a scroll it should have dropped.
  const shouldDrop = (el, targetTop) => {
    if (!el || !el[AWAY_FLAG]) return false;
    const r = range(el);
    if (r < 400) return false;                     // nothing worth losing your place in
    if (r - targetTop > AT_BOTTOM) return false;   // not aimed at the bottom
    // WHO IS CALLING beats WHEN THEY LAST CLICKED.
    // The first version trusted transient activation alone, and it leaked: the
    // flag stays true for about five seconds after ANY click, so pressing send and
    // then scrolling up left the auto-scroll allowed for exactly the window in
    // which it happens. The recorder that diagnosed this printed the real
    // discriminator verbatim -- the re-pin arrives from
    // "at Object.current <- ResizeObserver.<anonymous>". An observer callback is
    // the application reacting to its own content growing; it is never the reader
    // asking for anything, whatever they clicked five seconds ago.
    if (reactive()) return true;
    if (gesture()) return false;                   // the reader asked for it
    return true;
  };

  Object.defineProperty(proto, "scrollTop", {
    configurable: true,
    get() { return desc.get.call(this); },
    set(v) {
      if (shouldDrop(this, Number(v))) return;
      return desc.set.call(this, v);
    }
  });

  proto.scrollTo = function (...args) {
    const opt = args[0];
    const top = opt && typeof opt === "object" ? opt.top : args[1];
    if (typeof top === "number" && shouldDrop(this, top)) return;
    return rawScrollTo.apply(this, args);
  };

  // The reader's own scrolling is what sets and clears the flag. A scroll event
  // fires for programmatic scrolls too, which is why the flag is derived from
  // POSITION rather than from "an event happened": at the bottom, the app may
  // pin; away from it, it may not. That holds no matter who moved it last.
  addEventListener("scroll", ev => {
    const el = ev.target;
    if (!el || el.nodeType !== 1 || range(el) < 400) return;
    const d = distance(el);
    if (d <= AT_BOTTOM) el[AWAY_FLAG] = false;
    else if (d >= AWAY) el[AWAY_FLAG] = true;
  }, { capture: true, passive: true });

  return "scroll intent fix installed";
})()`;

// ─── ADS DIE AT THE LAYER THAT CANNOT GO STALE ──────────────────────────────
// patch-freebuff-ads.js cuts FreeBuff's ads out of the renderer bundle and the
// orchestrator byte-for-byte. That is the primary layer, and it is exactly as
// durable as the strings it matches. A future FreeBuff release can rename every
// minified identifier, move the ad component, or renumber the API paths -- and
// the byte patch needs new strings after the first such release.
//
// This block is the layer that does NOT depend on any of that. It rides inside
// the shim and intercepts the two things the application cannot rename without
// breaking its own ad network:
//
//   1. the network calls. The renderer talks to the ad server over fetch/XHR to
//      URLs that contain /api/ad/. Any request whose URL matches that path is
//      turned into a rejection before it leaves the page, so the ad network is
//      unreachable even if a future bundle wires the call sites back up.
//   2. the painted card. Any element whose class contains `sponsored-ad` is
//      hidden (display:none) as soon as it appears, forever, so even a build
//      that renders ads with brand-new identifiers shows nothing.
//
// The block is harmless in non-FreeBuff apps: the URL pattern is unique to
// FreeBuff's ad network and the class does not exist elsewhere. It never
// touches requests that do not match, so no legitimate traffic is affected.
const AD_BLOCK = `(() => {
  if (window.__wintageAdBlock) return "already running";
  window.__wintageAdBlock = true;

  // Backslashes are DOUBLED, and that is load-bearing: this payload is a template
  // literal in the shim, so a single \/ collapses to / and a single \b to a
  // backspace character before the renderer ever sees the text. Written singly,
  // the emitted line was "const AD_PATH = //api/ad/(...)" -- a comment -- and the
  // payload died at parse with "Script failed to execute". It never ran once, on
  // any launch, while the status file reported the failure to nobody.
  // tools/test-shim-payloads.js now interpolates and parses this one too.
  const AD_PATH = /\\/api\\/ad\\/(slot|impression|click)\\b/;
  const AD_CLASS = /sponsored-ad/i;

  const rf = window.fetch && window.fetch.bind(window);
  if (rf) {
    window.fetch = function (input, init) {
      let url = "";
      try { url = typeof input === "string" ? input : (input && input.url) || ""; } catch (e) { }
      if (AD_PATH.test(url)) return Promise.reject(new TypeError("blocked by wintage"));
      return rf(input, init);
    };
  }

  const rxo = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (method, url) {
    if (AD_PATH.test(String(url))) {
      this.__wintageBlocked = true;
      setTimeout(() => { try { this.abort(); } catch (e) { } }, 0);
    }
    return rxo.apply(this, arguments);
  };
  const rxs = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function () {
    if (this.__wintageBlocked) return;
    return rxs.apply(this, arguments);
  };

  const hideAds = () => {
    for (const el of document.querySelectorAll('[class*="sponsored-ad"]')) {
      if (el.__wintageAdHidden) continue;
      el.__wintageAdHidden = true;
      el.style.setProperty("display", "none", "important");
    }
  };
  hideAds();
  let queued = false;
  new MutationObserver(() => {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => { queued = false; hideAds(); });
  }).observe(document.documentElement, { childList: true, subtree: true });

  return "ad block installed";
})()`;

// ─── A BAR THAT REPORTS A VALUE: TRIED, MEASURED, WITHDRAWN ──────────────────
// The problem is real and stays on the board. A usage or quota bar carries its
// number in the PROPORTION between fill and track, surface flattening paints both
// the same colour, and the bar survives as a rectangle that reports nothing.
//
// Two detections were tried, and both were withdrawn after counting what they
// actually hit in a live Claude window:
//
//   by shape   -- a child starting at the track's leading edge, as tall as the
//                 track and shorter than it ...................... 234 elements
//   by inline  -- a child whose width is computed inline as a percentage,
//                 or by a scaleX transform ....................... 111 elements
//
// Neither is a gauge detector. The first describes every button, tab and toolbar
// row ever written; the second describes ordinary layout, because a width of 60%
// in a style attribute is how half the web sizes a column. Extra guards -- carries
// no text, holds at most three children -- moved the counts and not the verdict.
//
// What those numbers settle is which way to fail. A gauge that is drawn but hard
// to read is a cosmetic complaint; a hundred controls repainted as solid golden
// blocks is an application nobody can work in, and that is what shipped, briefly.
// So nothing is painted here until a real gauge is read over CDP and a signal is
// found that a control cannot also satisfy. Guessing it from a screenshot has cost
// two rounds already.

// ─── NATIVE CAPTION BUTTONS SITTING ON TOP OF THE APP'S OWN CONTROLS ─────────
// Antigravity is a frameless window with Electron's titleBarOverlay: minimise,
// maximise and close are drawn by Chromium ON TOP of the page, in a strip the
// renderer does not own. The app reserves room for that strip in the layouts it
// knows about -- and not in the ones it does not, which is how the Settings
// section's own close button ended up underneath the caption buttons, visible but
// unclickable. No stylesheet can fix this, because the overlay is not in the DOM.
//
// Chromium does expose the geometry, though: navigator.windowControlsOverlay
// gives the rect the PAGE still owns, so everything outside it in the title strip
// is the overlay. Anything interactive that lands there is moved out from under it
// with a transform -- transform and not margin, because a control positioned
// absolutely (which these usually are) ignores margins entirely.
//
// Deliberately narrow: only small controls, only inside the title strip, and the
// shift is recomputed from scratch on every pass (the transform is cleared before
// measuring) so a resize cannot accumulate offsets. Getting it wrong nudges one
// button a few pixels; not doing it leaves that button unreachable.
const WCO_FIX = `(() => {
  if (window.__wintageWcoFix) return "already running";
  const wco = navigator.windowControlsOverlay;
  if (!wco) return "no window-controls overlay in this window";
  window.__wintageWcoFix = true;

  const SEL = "button, a, summary, input, select, [role=button], [role=tab], [class*=button i], [class*=btn i]";
  const touched = new Set();

  const apply = () => {
    for (const el of touched) el.style.removeProperty("transform");
    touched.clear();
    if (!wco.visible) return;

    const bar = wco.getTitlebarAreaRect();
    if (!bar || !bar.height) return;
    // Whatever the page does NOT own inside the title strip is the overlay. It sits
    // on the right on Windows and Linux, on the left on macOS; both are handled by
    // measuring rather than assuming.
    const rightStrip = bar.x + bar.width < window.innerWidth - 1;
    const from = rightStrip ? bar.x + bar.width : 0;
    const to = rightStrip ? window.innerWidth : bar.x;
    if (to - from < 1) return;

    for (const el of document.querySelectorAll(SEL)) {
      const r = el.getBoundingClientRect();
      if (!r.width || !r.height) continue;
      // In the title strip, and small enough to be a control rather than a panel
      // that merely starts up there.
      if (r.top >= bar.y + bar.height || r.bottom <= bar.y) continue;
      if (r.width > 200 || r.height > 60) continue;
      if (r.right <= from || r.left >= to) continue;
      // Signed by construction: positive when the control pokes into a strip on
      // the right, negative when it pokes into one on the left. Undoing it is the
      // same expression either way.
      const shift = rightStrip ? r.right - from : r.left - to;
      if (Math.abs(shift) < 1) continue;
      el.style.setProperty("transform", "translateX(" + (-shift) + "px)", "important");
      touched.add(el);
    }
  };

  apply();
  let passes = 0;
  const settle = () => { if (++passes < 4) { apply(); setTimeout(settle, 700); } };
  setTimeout(settle, 700);
  window.addEventListener("resize", () => requestAnimationFrame(apply));
  try { wco.addEventListener("geometrychange", () => requestAnimationFrame(apply)); } catch (e) { }

  return "window-controls overlay fix installed";
})()`;

// ─── app.getAppPath() MUST STILL POINT AT THE ARCHIVE ───────────────────────
// This is the one thing the relocation actually breaks, and it breaks loudly in a
// misleading way. Electron sets getAppPath() to the directory it loaded the app
// from -- now `resources/app`, the shim's own folder -- while every module INSIDE
// the archive was written expecting it to be the archive itself. Claude's main
// does exactly that:
//
//   mainWindow.loadFile(path.join(app.getAppPath(), '.vite/renderer/main_window/index.html'))
//
// With the shim in place that resolves to resources/app/.vite/... which does not
// exist, the local load fails, and the app falls back to opening claude.ai --
// so the desktop app silently becomes the web app. Reported as "after patching it
// opens the web version"; nothing about the theme was wrong.
//
// Pointing getAppPath() back at the archive restores exactly what an unpatched
// launch would report. The real value is kept for anything that wants the shim's
// own directory.
// ─── OPT-IN DEBUG PORT ──────────────────────────────────────────────────────
// Themed apps are the hardest thing here to diagnose: the only feedback is a
// screenshot and a restart, which turns every hypothesis into a round trip paid
// for by the user. A debug port replaces that with reading the live document --
// which is how the black-text bug was finally pinned, by asking Blink directly
// which rule won on <body> instead of guessing for eight rounds.
//
// OFF unless a file called `wintage-debug.port` sits next to this shim, holding
// the port number. Deliberate, greppable, and revoked by deleting the file. Never
// on for an ordinary install: a debugging port left open on someone's machine is
// not a detail to leave to memory. Loopback only.
try {
  const portFile = path.join(__dirname, 'wintage-debug.port');
  if (fs.existsSync(portFile)) {
    const port = (fs.readFileSync(portFile, 'utf8').trim() || '9222').replace(/[^0-9]/g, '') || '9222';
    const { app } = require('electron');
    app.commandLine.appendSwitch('remote-debugging-port', port);
    app.commandLine.appendSwitch('remote-debugging-address', '127.0.0.1');
    console.error('[wintage] DEBUG PORT ' + port + ' enabled by ' + portFile + ' - delete that file to turn it off');
  }
} catch (e) { }

try {
  const { app } = require('electron');
  const realGetAppPath = app.getAppPath.bind(app);
  app.getAppPath = () => ASAR;
  app.getShimPath = () => realGetAppPath();
} catch (e) {
  console.error('[wintage] could not redirect getAppPath, the app may load its web build:', e.message);
}

if (css) {
  try {
    const { app } = require('electron');

    // Injection either happened or it did not, and a themed-looking window is not
    // proof (the app may simply have a dark theme of its own). Each result is
    // stamped to a status file next to the stylesheet, so "is the theme actually
    // live in this app?" is answerable without a screenshot or a devtools port —
    // the same reason the userscript stamps data-w95-ver on every style tag.
    // Appended and capped, not overwritten: the stylesheet and the two script
    // fixes report separately and can fail independently, so one overwritten line
    // would hide whichever of them finished first.
    const stamp = text => {
      try {
        const f = path.join(__dirname, 'wintage-status.txt');
        let prev = '';
        try { prev = fs.readFileSync(f, 'utf8'); } catch (e) { }
        fs.writeFileSync(f, (prev + new Date().toISOString() + ' ' + text + '\n').split('\n').slice(-40).join('\n'));
      } catch (e) { }
    };

    // ─── EVERY webContents, NOT EVERY BrowserWindow ─────────────────────────
    // `browser-window-created` reaches a window's OWN webContents and nothing else,
    // and that is not where modern Electron apps keep their interface. Claude's
    // desktop app is the clean example: the BrowserWindow renders a thin shell
    // (.vite/renderer/main_window/index.html) and the entire visible application is
    // a WebContentsView attached to it --
    //
    //   exports.mainWindow = new BrowserWindow(...)
    //   exports.mainView   = new WebContentsView(...)   // the app you actually see
    //
    // -- so the shim faithfully injected 42 KB of stylesheet into the shell, wrote
    // "injected" to the status file, and the user correctly reported that nothing
    // had changed. The status file said the theme was live; the theme was live in a
    // frame with nothing in it.
    //
    // `web-contents-created` fires for every one of them: window contents,
    // WebContentsViews, BrowserViews, <webview> guests and popups. It is a strict
    // superset of what was hooked before, so the apps that already worked are
    // unaffected, and the failure mode it fixes is invisible by construction --
    // which is exactly why it should not be narrowed again without a reason.
    app.on('web-contents-created', (_e, wc) => {
      // dom-ready, did-finish-load and did-frame-finish-load all fire for the same
      // document, so an unguarded handler inserted the same 39 KB stylesheet three
      // times into every renderer. The status file is what made that visible. Keyed
      // on the URL, so a real navigation still re-injects (insertCSS does not
      // survive one) while the three events for one document inject once.
      let injectedFor = null;
      const inject = () => {
        let url = '';
        try { url = wc.getURL(); } catch (e) { return; }
        // Devtools is Chromium's own UI, not the application's. Theming it makes
        // the one tool you would use to debug the theme unreadable.
        if (!url || url.startsWith('devtools://')) return;
        if (url === injectedFor) return;
        injectedFor = url;
        wc.executeJavaScript(SCROLL_FIX, true)
          .then(r => stamp('scrollfix: ' + r))
          .catch(err => stamp('scrollfix FAILED: ' + (err && err.message)));
        wc.executeJavaScript(WCO_FIX, true)
          .then(r => stamp('wcofix: ' + r))
          .catch(err => stamp('wcofix FAILED: ' + (err && err.message)));
        wc.executeJavaScript(REPAINTER_FIX, true)
          .then(r => stamp('repainter: ' + r))
          .catch(err => stamp('repainter FAILED: ' + (err && err.message)));
        wc.executeJavaScript(SCROLL_INTENT_FIX, true)
          .then(r => stamp('scrollintent: ' + r))
          .catch(err => stamp('scrollintent FAILED: ' + (err && err.message)));
        wc.executeJavaScript(AD_BLOCK, true)
          .then(r => stamp('adblock: ' + r))
          .catch(err => stamp('adblock FAILED: ' + (err && err.message)));
        const payload = CLAUDE_VIEW.test(url) ? css + CLAUDE_FOREGROUND_CSS : css;
        wc.insertCSS(payload, { cssOrigin: 'author' })
          .then(key => { wc.__wintageCssKey = key; stamp('injected ' + payload.length + ' bytes into ' + url); })
          .catch(err => {
            stamp('FAILED: ' + (err && err.message));
            console.error('[wintage] insertCSS failed:', err && err.message);
          });
      };
      wc.on('dom-ready', inject);
      wc.on('did-finish-load', inject);
      // Child frames (iframes) of this contents.
      wc.on('did-frame-finish-load', inject);
    });

    // ─── THE NATIVE CAPTION STRIP ───────────────────────────────────────────
    // The caption buttons are painted by Chromium, outside the page and beyond the
    // reach of any stylesheet, so a frameless app kept a stripe of its stock
    // colours across the top of an otherwise fully themed window.
    //
    // Setting it once after the window is created is NOT enough, and Antigravity is
    // the proof: it ships an ipcMain handler for `window:set-title-bar-overlay` that
    // the renderer calls on every theme change, so our colours were applied at
    // startup and overwritten moments later by the app's own. Reported as "that
    // section top-right still is not painted", with the rest of the window themed.
    //
    // Patching the prototype makes the palette win by construction: the app can call
    // this as often as it likes and the colours are still ours, while everything else
    // it passes (notably `height`, which is layout, not colour) is left alone. Errors
    // are deliberately NOT swallowed here -- this stands in for a real Electron API
    // and a caller that expects it to throw must still see it throw.
    const { BrowserWindow } = require('electron');
    if (T_SURFACE && T_TEXT && BrowserWindow && BrowserWindow.prototype.setTitleBarOverlay) {
      const realSetOverlay = BrowserWindow.prototype.setTitleBarOverlay;
      BrowserWindow.prototype.setTitleBarOverlay = function (options) {
        return realSetOverlay.call(this, Object.assign({}, options, { color: T_SURFACE, symbolColor: T_TEXT }));
      };
      app.on('browser-window-created', (_e, win) => {
        // The CONSTRUCTOR takes titleBarOverlay as an option, not as a call, so the
        // patch above never sees the initial value -- this is what covers it. Throws
        // on a window that has no overlay at all, which is most of them: the normal
        // case, not an error, and the reason the result is stamped rather than logged.
        try {
          win.setTitleBarOverlay({});
          stamp('titlebar overlay repainted');
        } catch (e) { }
        // The window's own background shows through before the first paint and in
        // any gap the page does not cover, so a stock near-black flashed on every
        // launch of an otherwise warm-toned theme.
        if (T_BACKGROUND) { try { win.setBackgroundColor(T_BACKGROUND); } catch (e) { } }
      });
    }
  } catch (e) {
    console.error('[wintage] could not hook window creation, loading the app unthemed:', e.message);
  }
}

// Hand control to the real application. Anything thrown here is the app's own
// problem, not the theme's — but if the shim itself is what broke, the message
// says so plainly, because a user staring at an app that will not start needs to
// know which of the two to blame.
try {
  const { app } = require('electron');
  if (app && app.setAppPath) {
    app.setAppPath(ASAR);
  }
  require(ASAR);
} catch (e) {
  console.error('[wintage] failed to load the original app.asar at ' + ASAR);
  console.error('[wintage] delete this folder (resources/app) to restore the app exactly as it was.');
  throw e;
}
