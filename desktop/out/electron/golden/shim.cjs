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

// ─── FLOATING SURFACES ARE MEASURED, NOT NAMED ───────────────────────────────
// The stylesheet flattens surfaces so an app reads as one window instead of a
// stack of vendor greys, and then re-solidifies the panels that must stay opaque
// -- menus, tooltips, popovers -- off a list of NAMES: role="menu",
// [class*="popup" i], [class*="dropdown" i], the radix and floating-ui portal
// attributes. That list has now missed the same app twice. Claude Desktop's
// popovers carry none of those markers, so the wipe reaches them and the text
// behind reads straight through the panel.
//
// The list cannot be finished by adding more names to it, and that is the whole
// point of this block. Every entry on it is one library's vocabulary; an app that
// renames a component, swaps its popover library, or ships its own design system
// -- which all three agent shells targeted here do -- drops off the list at its
// next release, silently. Nothing errors. The theme just quietly gets a hole in
// it, and the person who finds it is the user.
//
// So the test is what a popover IS rather than what it is called, in terms the
// layout engine can answer and an app rename cannot change:
//   1. out of flow            position: fixed | absolute
//   2. big enough to read     and not the full-viewport scrim, nor the zero-size
//                             wrapper that HOSTS the panel
//   3. actually floating      at its own centre, the paint stack UNDER it holds
//                             something that is not one of its ancestors
// Both size tests and the hit test must hold. Colours are written as var() rather
// than resolved hex so a palette switch repaints these with everything else, and
// so this file stays palette-independent -- it is copied byte-identical into all
// sixteen packs.
//
// Rule 3 replaced an earlier "has an explicit z-index, not auto" test, and the
// swap is the whole reason this works now. That test sounded right and was wrong
// on the first app it met: Claude's Settings panel is `role="dialog"`,
// `position: fixed`, 606x720 over a 638x1079 window -- and `z-index: auto`. It
// stacks by paint order, not by a number, which is ordinary and extremely common.
// Requiring a number is requiring a habit, and a habit is just another name in
// disguise. What cannot be opted out of is the hit test: an element that is
// painted over content it does not own IS floating, however it got there, and an
// absolutely-positioned adornment inside its own card is not -- everything under
// that one is its own ancestor. Measured live against this app: of ~1500
// elements, 1332 rejected as in-flow, 116 as too small, 5 as viewport-sized, and
// exactly 3 marked -- the Settings dialog, an open popover, and the caption strip.
const FLOAT_FIX = `(() => {
  if (window.__wintageFloatFix) return "already running";
  window.__wintageFloatFix = true;

  const MARK = "data-w95-float";

  const solidify = el => {
    const s = el.style;
    s.setProperty("background-color", "var(--surfaceRaised)", "important");
    s.setProperty("background-image", "none", "important");
    s.setProperty("color", "var(--textPrimary)", "important");
    s.setProperty("border-width", "2px", "important");
    s.setProperty("border-style", "solid", "important");
    s.setProperty("border-color", "var(--bevelLight) var(--borderDark) var(--borderDark) var(--bevelLight)", "important");
    s.setProperty("box-shadow", "none", "important");
    // The 2px bevel is added to an element the app already sized, so the box model
    // has to absorb it rather than grow by 4px in each axis.
    s.setProperty("box-sizing", "border-box", "important");
    el.setAttribute(MARK, "1");
  };

  const fixOne = el => {
    let cs;
    try { cs = getComputedStyle(el); } catch (e) { return; }
    if (cs.position !== "fixed" && cs.position !== "absolute") return;
    // Refused for a reason time can change: it may be mid-entry. Ask again later.
    if (cs.visibility === "hidden" || cs.display === "none" || cs.opacity === "0") { recheck(el); return; }
    // A click-through layer is a scrim or a measurement probe, never a panel.
    if (cs.pointerEvents === "none") return;

    const r = el.getBoundingClientRect();
    // Zero-size means the panel is closed or this is the wrapper that hosts it.
    // Neither is paintable, and the wrapper must stay transparent or it blacks out
    // a viewport-sized rectangle over the app. Re-decided rather than latched: a
    // popover is mounted closed, so a decision made while it measured nothing
    // would be the only decision ever made about it.
    if (r.width < 40 || r.height < 24) { el.removeAttribute(MARK); recheck(el); return; }
    // COVERS THE WHOLE VIEWPORT: not a panel, but not nothing either.
    // This used to be a plain return, and the guard is still right about what it
    // was written for -- painting a full-screen layer opaque blacks out the
    // application. What it got wrong is treating "do not solidify" as "do not
    // touch", and that cost a user their app: CodeNomad's tabs stopped responding
    // because the application had a modal open -- div.fixed inset-0 bg-black/50
    // z-50, pointer-events auto -- and the flattening wipe had erased the dim it
    // announces itself with. An invisible modal still eats every click. Read off
    // the live app with elementsFromPoint at a tab's centre, which returned that
    // layer rather than the tab.
    //
    // A backdrop that TAKES POINTER EVENTS is a claim on the whole window, and the
    // reader has to be able to see it. So it gets the dim back -- translucent, so
    // the app stays legible underneath, which is also what the app itself asked
    // for. Everything unmeasurable is left alone: no pointer events (a decorative
    // gradient layer, a drag-and-drop helper) or no explicit stacking order and it
    // is not a modal backdrop, it is scenery.
    if (r.width > innerWidth * 0.92 && r.height > innerHeight * 0.92) {
      if (cs.zIndex && cs.zIndex !== "auto" && !el.hasAttribute(MARK)) {
        el.style.setProperty("background-color", "rgba(0, 0, 0, 0.45)", "important");
        // Preferred when the engine has it: the dim is made from the palette's own
        // background rather than a hardcoded black, so it follows a theme switch.
        el.style.setProperty("background-color", "color-mix(in srgb, var(--background) 55%, transparent)", "important");
        el.style.setProperty("background-image", "none", "important");
        el.setAttribute(MARK, "scrim");
      }
      return;
    }
    if (!el.childElementCount && !(el.textContent || "").trim()) return;
    if (el.hasAttribute(MARK)) return;

    // STATE COLOURS ARE NOT REPAINTED, AND THIS IS MEASURED TOO.
    // The working/waiting/done indicators -- blue while running, amber when the
    // agent wants the user, grey when finished -- carry their whole meaning in a
    // background colour, which is why the stylesheet's transparency wipe already
    // excludes them. That exclusion is what makes this test possible without
    // naming anything: after the wipe, a panel that needs solidifying is
    // transparent BY DEFINITION, and anything still holding its own colour is
    // holding it on purpose. So a non-transparent background is the app saying
    // "this colour is load-bearing", and the correct move is to leave it alone.
    // Cheaper and stricter than re-listing status/indicator/dot markers here, and
    // it cannot go stale when an app renames its indicator.
    const own = cs.backgroundColor;
    if (own && own !== "transparent") {
      const m = /^rgba?\(([^)]+)\)/.exec(own);
      const a = m ? parseFloat(m[1].split(",")[3]) : 1;
      if (!(a >= 0) || a > 0.08) return;
    }

    // THE hit test. Everything above this line is cheap and admits far too much;
    // this is the line that decides. Read the paint stack at the element's own
    // centre: if what lies under it is nothing but its own ancestors, it is an
    // adornment sitting inside its own card -- an icon, a focus ring, a corner
    // badge -- and the app is right to have it inherit the surface. If something
    // foreign is under it, it is covering content it does not own, which is the
    // definition of floating and the reason it has to be opaque.
    const cx = Math.min(Math.max(r.left + r.width / 2, 1), innerWidth - 1);
    const cy = Math.min(Math.max(r.top + r.height / 2, 1), innerHeight - 1);
    let stack;
    try { stack = document.elementsFromPoint(cx, cy); } catch (e) { return; }
    const i = stack.indexOf(el);
    if (i < 0) return;                                   // covered by something else
    for (let k = i + 1; k < stack.length; k++) {
      const under = stack[k];
      if (under === document.body || under === document.documentElement) continue;
      if (under.contains(el)) continue;                  // its own ancestor
      solidify(el);
      return;
    }
  };

  // A PANEL IS NOT ITS FINAL SIZE WHEN IT IS BORN.
  // Reported as "sometimes it is see-through", and intermittent is the tell. A
  // dialog is mounted and then animated in: at the moment the mutation arrives it
  // can still measure zero, or sit at opacity 0, or carry an entering transform.
  // fixOne correctly refuses to paint that -- and if nothing else ever touches the
  // element, nothing ever asks again, so the one measurement that decided its
  // whole appearance was taken before it had one.
  //
  // So a candidate that was refused for a reason that TIME CAN CHANGE is asked
  // again, twice, and then never: once on the next frame, once after the animation
  // budget. Bounded per element by a counter, so this can never become a loop --
  // an element that is genuinely closed simply fails all three and is dropped.
  const RETRIES = new WeakMap();
  const recheck = el => {
    const n = RETRIES.get(el) || 0;
    if (n >= 2) return;
    RETRIES.set(el, n + 1);
    requestAnimationFrame(() => requestAnimationFrame(() => fixOne(el)));
    setTimeout(() => fixOne(el), 260);
const REPAINTER_FIX = `(() => {
  if (window.__wintageRepainter) return "already running";
  window.__wintageRepainter = true;

  const THEME_ID = 'electron';
  const THEMES = {
    electron: {
      tokens: {
        background: '#342012',
        backgroundSoft: '#3A2616',
        surface: '#4A341B',
        surfaceRaised: '#5A4324',
        surfaceAlt: '#634B2B',
        borderDark: '#1C1208',
        borderHighlight: '#D3B57A',
        bevelLight: '#826941',
        borderMuted: '#665033',
        link: '#D3B57A',
        textPrimary: '#E2CA95',
        textSecondary: '#C5AB6E',
        textMuted: '#95804C',
        accentTeal: '#008080',
        accentTealDeep: '#006060',
        success: '#5B9630',
        warning: '#969630',
        danger: '#963030',
        dangerText: '#D37676',
        selection: '#5A4324',
        compareBack: '#24170C'
      }
    }
  };
  
  let B_OUTER = \`border: 2px solid !important; border-color: #826941 #1C1208 #1C1208 #826941 !important; box-shadow: none !important;\`;
  let B_INNER = \`border: 2px solid !important; border-color: #1C1208 #826941 #826941 #1C1208 !important; box-shadow: none !important;\`;
  let B_SUNK = \`border: 2px solid !important; border-color: #1C1208 #826941 #826941 #1C1208 !important; box-shadow: none !important;\`;
  let FONT = \`Verdana_m1, Verdana, Tahoma, "MS Sans Serif", sans-serif\`;

  

  function parseRGB(str) {
    if (!str) return null;
    const m = str.match(/rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*[,/]\s*([\d.]+))?/);
    if (!m) return null;
    return { r: +m[1], g: +m[2], b: +m[3], a: m[4] !== undefined ? parseFloat(m[4]) : 1 };
  }
  // Write-if-changed: re-verify passes revisit every element, so identical
  // rewrites must not invalidate styles or churn the style attribute.
  function setImp(el, prop, val) {
    const st = el.style;
    if (st.getPropertyValue(prop) !== val || st.getPropertyPriority(prop) !== 'important') {
      st.setProperty(prop, val, 'important');
    }
  }

  // 🚨 READ/WRITE SPLIT — this was THE idle-CPU bug (v1.3.0) 🚨
  // process() used to read getComputedStyle and write inline styles in the same
  // loop. Every inline write invalidates style, so the NEXT element's read had
  // to force a whole-document style recalc — and this theme's own selectors make
  // that the most expensive recalc shape there is (`*`, `*, *::before, *::after`,
  // the 8-`:not([class*="…" i])` icon-font selector, the 12-negation hover-freeze
  // selector). One write per element therefore bought one full recalc per
  // element. Measured live on en.wikipedia.org/wiki/World_War_II, 16921 elements,
  // published v1.2.1 eval'd in-page:
  //     2500 elements, reads only ................  70.6 ms
  //     2500 elements, interleaved read+write ....  1069–1994 ms   ← old code
  //     2500 elements, batched read-then-write ...  230.9 ms  (~190 ms of which
  //                                                 is ONE whole-doc recalc)
  // One real instrumented sweeper tick measured 253 ms per 1.5 s interval =
  // 16.9 % of a core, permanently, on a page that was doing nothing.
  //
  // So process() now ONLY READS. Instead of writing, it appends [el, prop, val]
  // triples to a queue that the caller flushes once at the end: N recalcs -> 1.
  // A flat array (not objects) keeps the queue allocation-free per element.
  //
  // Correctness note on batching: `color` is inherited, so a child no longer
  // sees its parent's just-corrected color while being read — it fails the
  // contrast check against the ORIGINAL inherited value and gets its own
  // explicit inline color. Identical final pixels, one extra declaration; it
  // can never resolve to a DIFFERENT color, only to the same one stated twice.
  // Non-inherited properties (background, border-*) are unaffected either way.
  //
  // Attribute writes stay inline and are deliberately NOT queued: setAttribute
  // ('data-w95-done') is not referenced by any selector in this theme, so it
  // invalidates nothing (measured: 6.7 ms for all 16921 elements), and
  // removeAttribute('bgcolor'/'background') is a no-op when absent.
  // 🚨 SELF-WRITE SUPPRESSION IS BY IDENTITY, NEVER BY A TIME WINDOW (v1.4.2) 🚨
  // 'style' IS in the observer's attributeFilter, which ADR-002 said never to do.
  // It is worth doing — a site mutating an existing element's inline style is
  // otherwise invisible, and catching it with an event is what let the 30s
  // polling heartbeat be deleted entirely. But setImp writes inline styles, so
  // the observer WILL be handed its own output and the suppression has to be
  // airtight.
  //
  // The first attempt muted all 'style' records for 100ms after each flush.
  // Measured on a static article (16595 elements), 12-second window:
  //     site alone, no theme .......    0 style mutations
  //     with the theme ............. 9466 style mutations
  // i.e. every single one was ours. The mute discarded them at flush time, so
  // there was no runaway — but 9466 records were still allocated, delivered
  // through a microtask, and pushed into pendingMuts to be walked by the next
  // debounce. And it was only ever timing-safe by luck: the filter runs at the
  // END of the 60ms debounce, so any flush that lands >100ms before its debounce
  // fires (i.e. exactly when the main thread is busy, which is exactly during a
  // heavy sweep) lets our own writes through, and each one that gets processed
  // clears data-w95-done and re-processes the element, generating more writes.
  // A blanket window also drops the SITE's real style changes for 100ms.
  //
  // So: record precisely which elements we wrote, then drain the observer queue
  // ourselves with takeRecords() before the callback ever runs, keeping every
  // record that was not ours. Timing-independent and scoped to the exact
  // elements involved.
  const selfWritten = new Set();

  function flushWrites(w) {
    if (!w.length) return;
    for (let i = 0; i < w.length; i += 3) {
      setImp(w[i], w[i + 1], w[i + 2]);
      selfWritten.add(w[i]);
    }
    w.length = 0;
    // takeRecords() returns AND clears the pending queue, so this runs before
    // the observer callback is ever invoked for these mutations.
    let kept = 0;
    for (const obs of [mainObserver, shadowObserver]) {
      let recs;
      try { recs = obs.takeRecords(); } catch (e) { continue; }
      for (let i = 0; i < recs.length; i++) {
        const m = recs[i];
        if (m.type === 'attributes' && m.attributeName === 'style' && selfWritten.has(m.target)) continue;
        pendingMuts.push(m);
        kept++;
      }
    }
    selfWritten.clear();
    // Anything genuinely foreign that was queued alongside our writes still has
    // to be handled; the debounce is not running at this point (flushWrites is
    // called at the END of it, and from runSweeper), so it needs re-arming.
    // Known and accepted gap: a site style-change on an element WE also wrote to
    // in the same batch is dropped. It is self-healing — the next sweep re-reads
    // that element's computed style from scratch.
    if (kept && !debounceTimer) onMutations(EMPTY_MUTATIONS);
  }
  const EMPTY_MUTATIONS = [];

  // 🚨 SATURATED COLOUR -> ONE OF THREE SEMANTIC TOKENS (UI.md law 5) 🚨
  // The pre-1.4.0 rule multiplied a light saturated background by 0.18, which
  // "preserved the hue" — and in doing so emitted an unbounded set of arbitrary
  // colours that trace to no token at all. GitHub's diff green became one
  // brown-green, GitLab's a different one, a warning banner a third: iron law 5
  // broken every time, and every site kept its own colour signature.
  //
  // UI.md ships exactly three semantic colours, so the site's own hue only has to
  // answer one question: which of the three did it mean? Hue sectors, wide and
  // deliberately coarse, because the answer only needs to be right to within
  // "green / amber / red":
  //   red-ish    (>=345 or <35 deg) -> --danger
  //   yellow-ish (35..75 deg)       -> --warning
  //   green-ish  (75..170 deg)      -> --success
  // Everything else — blues, purples, teals, magentas — carries no shared meaning
  // across sites, so it becomes plain --surfaceRaised rather than being forced
  // into a status colour it never claimed.
  function semanticToken(c) {
    const max = Math.max(c.r, c.g, c.b), min = Math.min(c.r, c.g, c.b), d = max - min;
    if (d === 0) return T.surfaceRaised;
    let h;
    if (max === c.r) h = 60 * (((c.g - c.b) / d) % 6);
    else if (max === c.g) h = 60 * ((c.b - c.r) / d + 2);
    else h = 60 * ((c.r - c.g) / d + 4);
    if (h < 0) h += 360;
    if (h >= 345 || h < 35) return T.danger;
    if (h < 75) return T.warning;
    if (h < 170) return T.success;
    return T.surfaceRaised;
  }

  // UI.md's five permitted sizes, and the role mapping GLOBAL_CSS uses. Kept as
  // lookups so the JS enforcement below can never drift from the CSS layer.
  const SIZE_ALLOWED = new Set(['10px', '11px', '12px', '14px', '16px']);
  const LADDER = {
    H1: '16px', H2: '14px', H3: '14px', H4: '14px', H5: '14px', H6: '14px',
    SMALL: '10px', SUB: '10px', SUP: '10px', FIGCAPTION: '10px'
  };
  // The palette as the browser serialises it, for cheap "is this already one of
  // ours?" tests against a computed value.
  const PALETTE_RGB = new Set(Object.keys(T).map(k => {
    const h = T[k];
    return 'rgb(' + parseInt(h.slice(1, 3), 16) + ', ' + parseInt(h.slice(3, 5), 16) + ', ' + parseInt(h.slice(5, 7), 16) + ')';
  }));

  const ICONISH = /icon|fa-|symbols|glyph|mdi|bi-/i;
  function isIconish(el) {
    // className is an SVGAnimatedString on SVG elements, not a string — read the
    // attribute instead of trusting the property.
    const c = el.getAttribute && el.getAttribute('class');
    return c ? ICONISH.test(c) : false;
  }

  const JS_SKIP_SELECTOR = '#movie_player, .html5-video-player, ytd-player, ytd-thumbnail, yt-img-shadow, ytd-avatar-shape, yt-avatar-shape, #avatar, #author-thumbnail, ytd-logo, yt-icon, yt-icon-shape';
  const SHADOW_SKIP_TAGS = new Set(['YTD-LOGO', 'YT-ICON', 'YT-ICON-SHAPE', 'YT-IMG-SHADOW', 'YTD-AVATAR-SHAPE', 'YT-AVATAR-SHAPE', 'VIDEO', 'AUDIO', 'CANVAS', 'IFRAME']);
  const TAG_SKIP = /^(IMG|VIDEO|CANVAS|PICTURE|IFRAME|SVG|PATH|CIRCLE|RECT|LINE|POLYGON|POLYLINE|ELLIPSE|DEFS|SYMBOL|USE|STYLE|SCRIPT|LINK|META|HEAD|HTML|BR|HR|WBR)$/i;

  const piercedRoots = new Set();

  function pierceShadow(host) {
    const tag = (host.tagName || '').toUpperCase();
    if (SHADOW_SKIP_TAGS.has(tag)) return;
    if (!host.shadowRoot || piercedRoots.has(host.shadowRoot)) return;
    piercedRoots.add(host.shadowRoot);
    try {
      injectStyle(host.shadowRoot, 'shadow', SHADOW_CSS);
      if (!CSS_ONLY_MODE) {
        shadowObserver.observe(host.shadowRoot, {
          childList: true,
          subtree: true,
          attributes: true,
          attributeFilter: ['class', 'bgcolor', 'background', 'style']
        });
        stylesDirty = true;
      }
    } catch (e) { }
  }


  // ─── :hover RULE SURGERY (v29.1) ────────────────────────────────────────────
  // Strips paint properties out of every readable :hover rule so sites cannot
  // flashbang-highlight on hover. Functional props (display, visibility,
  // opacity, transform) are left untouched so hover-opened menus keep working.
  // Cross-origin sheets that throw on cssRules access are covered by the CSS
  // freeze rule in GLOBAL_CSS/SHADOW_CSS instead.
  const HOVER_PAINT = /^(background|box-shadow|filter|backdrop-filter|color|border|outline|text-decoration|text-shadow|--)/;
  const sheetSeen = new WeakMap(); // sheet -> cssRules.length at last pass

  function stripHoverRule(rule) {
    const st = rule.style;
    if (!st) return;
    const names = [];
    for (let i = 0; i < st.length; i++) names.push(st[i]);
    for (let i = 0; i < names.length; i++) {
      if (HOVER_PAINT.test(names[i])) st.removeProperty(names[i]);
    }
  }

  function walkRules(container) {
    let rules;
    try { rules = container.cssRules; } catch (e) { return; } // cross-origin
    if (!rules) return;
    for (let i = 0; i < rules.length; i++) {
      const r = rules[i];
      try {
        if (r.selectorText && r.selectorText.indexOf(':hover') !== -1) stripHoverRule(r);
        if (r.cssRules && r.cssRules.length) walkRules(r); // @media/@supports/@layer/nesting
      } catch (e) { }
    }
  }

  // Returns true when at least one sheet had changed since the last pass — the
  // caller treats that as "late CSS is still landing" and requests a force
  // re-verify (v1.3.0). On a settled page it returns false every time, which is
  // what lets the expensive pass go quiet.
  function stripHoverSheets(root) {
    let changed = false;
    const lists = [root.styleSheets, root.adoptedStyleSheets];
    for (let l = 0; l < lists.length; l++) {
      const list = lists[l];
      if (!list) continue;
      for (let i = 0; i < list.length; i++) {
        const sheet = list[i];
        const node = sheet.ownerNode;
        if (node && node.getAttribute && node.getAttribute('data-w95')) continue; // our own hover bevels stay
        let count;
        try { count = sheet.cssRules ? sheet.cssRules.length : 0; } catch (e) { continue; }
        const seen = sheetSeen.get(sheet);
        if (seen === count) continue; // unchanged since last pass
        sheetSeen.set(sheet, count);
        changed = true;
        if (seen === undefined || count < seen) {
          walkRules(sheet); // first sight or rules removed: full walk
        } else {
          // CSS-in-JS engines insertRule constantly; re-walking the whole sheet
          // every tick was a jank source. Walk the appended rules only.
          try {
            const rules = sheet.cssRules;
            for (let r = seen; r < count; r++) {
              const rule = rules[r];
              if (rule.selectorText && rule.selectorText.indexOf(':hover') !== -1) stripHoverRule(rule);
              if (rule.cssRules && rule.cssRules.length) walkRules(rule);
            }
          } catch (e) { }
        }
      }
    }
    return changed;
  }

  // `w` is the caller's write queue (see flushWrites). Reads only — every style
  // change is appended, never applied here.
  function process(el, force, w) {
    // v29 FIX: the old `el.closest(':hover')` guard was fatal — html/body match
    // :hover whenever the cursor is anywhere over the viewport, so closest()
    // returned truthy for EVERY element and the sweeper silently processed
    // nothing while the mouse was on the page (= dark-on-dark text never got
    // contrast-fixed). Only skip elements that are themselves in an interactive
    // state chain; they get retried on later sweeps.
    try {
      if (el && el.matches && el.matches(':hover,:active,:focus')) return;
    } catch (e) { }

    if (!el || el.nodeType !== 1) return;
    if (!force && el.hasAttribute('data-w95-done')) return;
    el.setAttribute('data-w95-done', '1');

    if (el.shadowRoot) pierceShadow(el);

    const cs = window.getComputedStyle(el);

    // 🚨 INFINITE ANIMATIONS GET PAUSED, NOT SPED UP (v1.4.1) 🚨
    // The global 'animation-duration: 0.001s' makes FINITE animations instant,
    // which is the goal. On an INFINITE animation it does the opposite of
    // stopping it. Measured exactly, via the Web Animations API on a real
    // spinner (duration 1ms, iterations Infinity):
    //     iterations in 1 second .............. 1000   (site intended: 1)
    //     iterations per 60fps frame ..........   16.7 (site intended: 0)
    //     angle rendered on 6 consecutive frames:
    //       240deg, 120deg, 0deg, 240deg, 120deg, 0deg
    // 16.667ms per frame divided by a 1ms duration leaves a repeating 2/3
    // remainder, so a spinner does not freeze — it strobes between exactly three
    // rotations forever. That is worse than the smooth spin it replaced, and it
    // makes this theme's "zero animations" claim false. ADR-001 checked that
    // Chromium does not FLOOD animationiteration events here and stopped there;
    // it never checked what was actually on screen. See ADR-004.
    //
    // Pausing is safe precisely where the 0.001s compromise is pointless: an
    // infinite animation's 'animationend' NEVER fires, so no animationend-driven
    // state machine can be waiting on one — and keeping animationend alive is the
    // entire reason 0.001s was chosen over 0s/none in the first place (ADR-001).
    // 'paused' rather than 'animation: none' because a paused animation keeps
    // applying its current computed value: cancelling instead would snap the
    // element back to its base state, which for a pulse/skeleton loop is often
    // opacity 0 — i.e. it would make content vanish.
    //
    // Known residual risk: code that drives state from 'animationiteration'
    // (some marquee and carousel loops) will stall. Rare, and the alternative is
    // a permanent three-position strobe on every spinner on the web.
    //
    // This runs BEFORE shouldSkip on purpose. The two commonest spinner shapes
    // are both in the skip set: Tailwind's 'svg.animate-spin' (SVG is in
    // TAG_SKIP) and a spinner inside a loading <button> (shouldSkip matches
    // closest('button')). Checking after the skip would miss exactly the cases
    // that matter.
    const iterCount = cs.animationIterationCount;
    if (iterCount && iterCount.indexOf('infinite') !== -1) {
      w.push(el, 'animation-play-state', 'paused');
    }

    // 🚨 UI.md HARD INVARIANTS, ENFORCED FROM JS BECAUSE CSS CANNOT WIN (v1.4.3) 🚨
    // Our universal rules are '* { border-radius: 0 !important }' etc, which score
    // specificity (0,0,0). A site's own '!important' beats them the moment it has
    // any specificity at all, and an ID rule beats them absolutely — no number of
    // ':root' prefixes can outrank (1,0,0). Measured on stackoverflow.com:
    //     a.bar-sm ....................... border-radius 4px   (site .class wins)
    //     h1.fs-headline1 ................ font-size 27px      (site .class wins)
    //     h2.fs-body2 .................... font-size 15px
    //     #onetrust-banner-sdk ........... box-shadow present  (site #id wins)
    // Inline '!important' is the one declaration that outranks every author rule
    // regardless of selector, and that is exactly what setImp writes. So these
    // three invariants are re-asserted here whenever the computed value actually
    // disagrees. The check is nearly free — 'cs' is already resolved, this is three
    // more property reads — and the write is skipped entirely when the CSS layer
    // already won, which is the overwhelming majority of elements (14 of 3362 on
    // the page above).
    //
    // Runs BEFORE shouldSkip because these are universal invariants: a rounded
    // corner or a drop shadow is just as wrong on a <button> or an <img> as
    // anywhere else, and buttons are skipped by shouldSkip via closest('button').
    if (cs.borderTopLeftRadius !== '0px' || cs.borderTopRightRadius !== '0px' ||
      cs.borderBottomLeftRadius !== '0px' || cs.borderBottomRightRadius !== '0px') {
      w.push(el, 'border-radius', '0');
    }
    if (cs.boxShadow && cs.boxShadow !== 'none') {
      w.push(el, 'box-shadow', 'none');
    }
    // Type ladder, same role mapping as GLOBAL_CSS. Icon-font carriers are
    // exempt for the same reason as in CSS: their font-size IS their glyph size.
    const fs = cs.fontSize;
    if (fs && !SIZE_ALLOWED.has(fs) && !isIconish(el)) {
      w.push(el, 'font-size', LADDER[(el.tagName || '').toUpperCase()] || '12px');
    }

    if (shouldSkip(el)) {
      // Controls and their contents are deliberately kept out of the generic
      // repainter so our bevels and labels survive (that is what the
      // closest('button') skip is for). But CSS alone cannot defend them: a site
      // rule with ID specificity and !important beats our button rule outright.
      // Measured on stackoverflow.com's cookie banner —
      //     #onetrust-consent-sdk #onetrust-accept-btn-handler
      //         { background: var(--black-600) !important; color: #fff !important }
      // scores (2,0,0) against our 'button { … !important }' at (0,0,1), and
      //     #onetrust-banner-sdk * { color: var(--black-600) !important }
      // at (1,0,0) beats every universal colour rule we have. The result was
      // near-black text on near-black surfaces inside the banner, on elements the
      // repainter had explicitly excluded.
      //
      // So: clamp, but only what is PROVABLY off-palette. A correctly themed
      // control already computes to a palette value and is skipped here, so this
      // cannot flatten our own bevel colours or relabel button internals — which
      // is exactly the regression the skip exists to prevent.
      if (el.closest && el.closest('button')) {
        if (cs.color && !PALETTE_RGB.has(cs.color)) {
          w.push(el, 'color', T.textPrimary);
        }
        const cbg = parseRGB(cs.backgroundColor);
        if (cbg && cbg.a > 0.3 && !PALETTE_RGB.has(cs.backgroundColor)) {
          w.push(el, 'background-color', T.surfaceRaised);
        }
      }
      return;
    }

    el.removeAttribute('background');
    el.removeAttribute('bgcolor');

    // Checkbox/radio: only force native appearance on a REAL, visible control
    // (the confirmed invisible-checked-state bug). Skip entirely for the
    // hidden-proxy pattern (opacity:0 / near-zero size / clipped) that custom
    // switch components rely on — see the CSS comment above for why.
    const tagUC = (el.tagName || '').toUpperCase();
    if (tagUC === 'INPUT') {
      const inputType = (el.type || '').toLowerCase();
      if (inputType === 'checkbox' || inputType === 'radio') {
        // opacity is the ONLY reliable signal — every accessible custom-switch
        // technique uses it (keyboard/screen-reader focus requires the real
        // input stay hit-testable, ruling out display:none). Size is NOT a
        // reliable signal: a checkbox with appearance:none and no explicit
        // width/height collapses to 0x0 in Chromium regardless of whether the
        // site intentionally hid it — a live test confirmed a genuinely
        // BROKEN, unstyled real checkbox (the original government-form bug
        // shape) also measures 0x0, so a size check produces false positives
        // that silently reintroduce that exact bug.
        const hiddenProxy = parseFloat(cs.opacity) < 0.05;
        if (!hiddenProxy) {
          w.push(el, 'appearance', 'auto', el, '-webkit-appearance', 'auto');
        }
        return;
      }
    }

    // UI.md law 2: zero gradients. Pre-1.4.0 this only killed LIGHT gradients,
    // which left every dark-themed site's own coloured gradients intact — and a
    // gradient is the most identity-carrying surface treatment there is, so
    // leaving them meant sites still looked like themselves. Now ALL gradient
    // functions go, whatever their hue.
    //
    // Only gradient FUNCTIONS, never url(): a huge number of sites still draw
    // their icons as background-image sprites, and killing url() backgrounds
    // deletes those icons outright. This is why the kill lives in JS at all — CSS
    // cannot say "background-image: none, but only if it is a gradient".
    //
    // progress/meter/slider are exempt: their fill IS a gradient on many sites,
    // and flattening it leaves a progress bar that cannot show progress — which
    // UI.md itself wants preserved ("long work reports progress in text").
    const bgImg = cs.backgroundImage;
    if (bgImg && bgImg !== 'none' && /(^|\s|,)(linear|radial|conic|repeating-linear|repeating-radial|repeating-conic)-gradient\(/i.test(bgImg)) {
      const tagG = (el.tagName || '').toUpperCase();
      const roleG = el.getAttribute ? el.getAttribute('role') : null;
      if (tagG !== 'PROGRESS' && tagG !== 'METER' && roleG !== 'progressbar' && roleG !== 'slider') {
        w.push(el, 'background-image', 'none');
      }
    }

    // PAGE-SIZED PHOTO BACKDROPS.
    // url() backgrounds are deliberately kept (see above): on most elements they
    // are icons, and killing them leaves invisible buttons. But at page scale the
    // same rule is what left steamcommunity.com with its neon profile artwork
    // blazing down both sides of a themed column -- the site paints a photo on a
    // full-bleed div, our surfaces go brown around it, and the result is the
    // screenshot the user sent.
    //
    // Size is the discriminator, and it is a safe one: nothing that is an icon is
    // 70% of the viewport in BOTH dimensions.
    //
    // But getBoundingClientRect FORCES LAYOUT, and this whole file exists in its
    // current shape because layout thrash once burned 94% of the main thread
    // (ADR-004, and the sweep-rate hot loop in ADR-006). "Only when a url() is
    // present" is not a tight enough guard on its own: an icon-sprite-heavy page
    // has hundreds of those. So the measurement is gated behind a pure DOM-shape
    // test first -- a page-level backdrop is always near the top of the tree,
    // never buried twelve divs deep -- which costs no layout at all and leaves a
    // handful of candidates per page.
    if (bgImg && bgImg !== 'none' && /url\(/i.test(bgImg)) {
      let depth = 0, p = el;
      while (p && p !== document.body && p !== document.documentElement && depth < 5) { p = p.parentElement; depth++; }
      if (depth < 5) {
        const r = el.getBoundingClientRect();
        if (r.width > innerWidth * 0.7 && r.height > innerHeight * 0.7) {
          w.push(el, 'background-image', 'none');
        }
      }
    }

    // 🚨 FLOATING SURFACES ARE MEASURED, NOT NAMED 🚨
    // GLOBAL_CSS re-solidifies popovers off a list of NAMES -- role="menu",
    // [class*="popup" i], [class*="dropdown" i], the radix and floating-ui portal
    // attributes -- because the surface-flattening wipe above would otherwise leave
    // them see-through with the page behind them showing through. That list has
    // missed the same app twice now (E-381, E-407): Claude's popovers carry none of
    // those markers.
    //
    // Adding more names does not fix a name list, it postpones it. Every entry is
    // one library's vocabulary, and an app that renames a component or swaps its
    // popover library drops off the list at its next release with nothing to show
    // for it -- no error, no failing gate, just a hole in the theme that the user
    // finds. So the test below asks what a popover IS, in terms the layout engine
    // answers and a rename cannot change: out of flow, big enough to read, and
    // actually covering content it does not own. The same test runs in Electron
    // apps as the shim's FLOAT_FIX, which is the only place it can run there --
    // that path ships CSS with no repainter behind it.
    //
    // The last of the three replaced an "explicit z-index, not auto" test that
    // shipped in the first pass and was wrong on the first app it met: Claude's
    // Settings panel is role="dialog", position: fixed, 606x720 over a 638x1079
    // window, and z-index: auto. It stacks by paint order, which is ordinary.
    // Requiring a number was requiring a habit, and a habit is a name in disguise.
    if (cs.position === 'fixed' || cs.position === 'absolute') {
      // Free checks first, all off the computed style already read above.
      // pointer-events:none means a scrim or a measurement probe, never a panel.
      // COST GATE, AND IT IS NOT OPTIONAL. Everything below this line forces
      // layout -- a rect read, then a hit test -- and the first version of this
      // block ran both for EVERY out-of-flow element on every pass, then took
      // data-w95-done OFF the small ones so they were measured again forever.
      // On a page with hundreds of absolutely-positioned icons that is a
      // permanent hot loop: reported as the CPU pinned at idle on chatgpt.com,
      // and it is exactly the thrash ADR-004/ADR-006 exist to prevent.
      // A panel always has children, and childElementCount costs nothing.
      if (el.childElementCount > 0 &&
        cs.pointerEvents !== 'none' && cs.visibility !== 'hidden' && cs.opacity !== '0') {
        // Layout reads start here, and only for the handful of elements that got
        // this far -- the ordering is the ADR-004/ADR-006 discipline, same as the
        // page-backdrop test above.
        const r = el.getBoundingClientRect();
        // Closed, or the zero-size wrapper that HOSTS the panel: nothing to do.
        // It is NOT re-dirtied here. A popover is mounted closed and opened by a
        // style or class flip, and both are in the observer's attributeFilter --
        // so the open lands as a mutation, which clears data-w95-done and brings
        // the element back through here already measuring its real size. Marking
        // it dirty on every pass instead bought exactly nothing and cost a
        // forced layout per element per sweep, forever.
        // Covers the whole viewport: never solidified, that would black out the
        // page -- but never ignored either. A backdrop that TAKES POINTER EVENTS
        // owns the window, and the wipe erases the dim it announces itself with.
        // An invisible modal still eats every click, which is how CodeNomad's tabs
        // stopped responding. Give the dim back, translucent, so the page stays
        // legible under it. No pointer events or no explicit stacking order means
        // scenery rather than a modal, and scenery is left alone.
        if (r.width > innerWidth * 0.92 && r.height > innerHeight * 0.92) {
          if (cs.zIndex && cs.zIndex !== 'auto') {
            w.push(el, 'background-color', 'color-mix(in srgb, ' + T.background + ' 55%, transparent)',
              el, 'background-image', 'none');
          }
        } else if (r.width >= 40 && r.height >= 24) {
          // The hit test decides. Everything above admits far too much: if the
          // paint stack under this element's own centre holds nothing but its own
          // ancestors, it is an adornment inside its own card and inheriting the
          // surface is correct. Anything foreign under it means it covers content
          // it does not own, which is what floating means.
          // STATE COLOURS ARE NOT REPAINTED, AND THAT IS MEASURED TOO. The
          // working/waiting/done indicators carry their whole meaning in a
          // background colour, which is why the wipe already excludes them. That
          // exclusion is what lets this be a measurement instead of a second name
          // list: after the wipe, a surface that needs solidifying is transparent
          // BY DEFINITION, so anything still holding a colour is holding it on
          // purpose. A condition, not an early return -- an element that keeps its
          // own colour still needs the rest of process(): contrast, borders, radius.
          const ownBg = parseRGB(cs.backgroundColor);
          const cx = Math.min(Math.max(r.left + r.width / 2, 1), innerWidth - 1);
          const cy = Math.min(Math.max(r.top + r.height / 2, 1), innerHeight - 1);
          let stack = null;
          if (!(ownBg && ownBg.a > 0.08)) {
            try { stack = document.elementsFromPoint(cx, cy); } catch (e) { }
          }
          const at = stack ? stack.indexOf(el) : -1;
          for (let k = at + 1; at >= 0 && k < stack.length; k++) {
            const under = stack[k];
            if (under === document.body || under === document.documentElement) continue;
            if (under.contains(el)) continue;
            w.push(el, 'background-color', T.surfaceRaised,
              el, 'background-image', 'none',
              el, 'color', T.textPrimary,
              el, 'border-width', '2px',
              el, 'border-style', 'solid',
              el, 'border-color', T.bevelLight + ' ' + T.borderDark + ' ' + T.borderDark + ' ' + T.bevelLight,
              el, 'box-shadow', 'none',
              // The bevel is added to a box the site already sized; absorb it.
              el, 'box-sizing', 'border-box');
            break;
          }
        }
      }
    }

    // 🚨 NEVER RE-GRADE A COLOUR THAT IS ALREADY OURS 🚨
    // The repainter classifies by luminance, and our own tokens have luminances
    // that land in its buckets: --backgroundSoft #1E1408 (lum 0.0088) and
    // --surfaceRaised #362812 (lum 0.0234) both fall in the "< 0.05" bucket and
    // were being re-graded to --surface on every pass. Caught live on wikipedia
    // the moment the dark band was widened: body went from #1E1408 to #2A1C0A,
    // and dialogs / th / hovercards would have drifted the same way, so the whole
    // surface hierarchy would slowly collapse onto one shade. A palette value is
    // by definition already correct — leave it alone.
    const bgColor = cs.backgroundColor;
    if (bgColor && bgColor !== 'transparent' && !PALETTE_RGB.has(bgColor)) {
      const bg = parseRGB(bgColor);
      if (bg && bg.a > 0.08) {
        const L = elev(lum(bg));
        const spread = Math.max(bg.r, bg.g, bg.b) - Math.min(bg.r, bg.g, bg.b);
        const grayish = spread <= 24;
        let repaint = null;
        if (L > 0.45) {
          // Flashbang surface — the far end of our own polarity, so on the golden
          // palette this is literally the old "light surface" branch and on a light
          // palette it is the site's dark chrome. Low-alpha tints go fully transparent
          // (the "gray rectangle blocks"), neutral solids go dark brown, and
          // saturated light tints (GitHub diff green/red, warning yellows,
          // highlight rows) snap to the semantic token they meant.
          if (bg.a <= 0.35) repaint = 'transparent';
          else if (grayish) repaint = T.backgroundSoft;
          else repaint = semanticToken(bg);
        } else if (L >= 0.004) {
          // DARK SURFACES. Two gaps used to let a site keep its own dark palette
          // here, both measured on amazon.com:
          //   #nav-belt  #131921  spread 14, lum 0.0094 — grayish, but the old
          //     "near-black is left alone" floor was 0.015, so it survived.
          //   #nav-main  #232f3e  spread 27, lum 0.0274 — over the old grayish
          //     cutoff of 24 but under the saturated cutoff of 60, so it fell
          //     through BOTH branches and was never touched at all.
          // A dark navy chrome bar is a surface, not an accent, so the neutral
          // band is widened to spread <= 60 and the two branches are merged:
          // anything genuinely saturated (> 60) still goes to a semantic token,
          // everything else joins the vintage brown scale.
          //
          // The floor drops from 0.015 to 0.004, which still leaves true black
          // alone — video players and modal scrims sit at or near lum 0 — while
          // catching real chrome like #131921.
          repaint = spread > 60
            ? semanticToken(bg)
            : (L >= 0.13 ? T.surfaceAlt : L >= 0.05 ? T.surfaceRaised : T.surface);
        }
        if (repaint) {
          w.push(el, 'background', repaint, el, 'background-color', repaint, el, 'background-image', 'none');
        }
      }
    }

    // Same guard for text: --textSecondary #B09558 has a channel spread of 88, so
    // the "not grayish" branch would have flattened every secondary label to
    // --textPrimary on the next pass. Palette in, palette out, untouched.
    const fgColor = cs.color;
    if (fgColor && !PALETTE_RGB.has(fgColor)) {
      const fg = parseRGB(fgColor);
      if (fg && fg.a > 0.1) {
        // Contrast is measured against the ACTUAL backdrop this theme paints, not
        // against a constant. It used to read `const darkBg = 0.008` with the
        // comment "luminance of #1E1408" — correct, and correct only for golden:
        // on a light palette that constant claims every dark text colour is
        // perfectly readable, so the whole 4.5:1 branch below stops firing exactly
        // where it is needed most.
        const rawFgLum = lum(fg);
        const fgLum = elev(rawFgLum);
        const cr = contrast(rawFgLum, BG_SOFT_LUM);
        const grayish = Math.max(fg.r, fg.g, fg.b) - Math.min(fg.r, fg.g, fg.b) <= 40;

        if (el.closest && el.closest('a')) {
          // Anything inside a link takes the link colour when it is unreadable,
          // washed out, OR simply not one of ours — the last clause is iron law 5
          // and it was missing. Measured on amazon.com: span#nav-cart-count kept
          // #f08804 and span.navFooterDescText kept #999999, because both are
          // legible enough (7.1:1 and 6.3:1) that the first two tests passed them
          // through. Legible is not the same as on-palette.
          if (cr < 4.5 || (fgLum > 0.4 && grayish) || !PALETTE_RGB.has(fgColor)) {
            w.push(el, 'color', T.link);
          }
        } else {
          if (cr < 4.5) {
            w.push(el, 'color', T.textPrimary);
          } else if (grayish) {
            if (fgLum > 0.4) w.push(el, 'color', T.textPrimary);
            else if (fgLum > 0.15) w.push(el, 'color', T.textSecondary);
          } else {
            // Legible but SATURATED text — a site's own coloured heading, tag or
            // status label. Left alone pre-1.4.0, which is another way sites kept
            // their own voice, so it gets normalised too: to --textPrimary.
            //
            // Deliberately NOT to semanticToken() like the background path does.
            // --success/--warning/--danger are BACKGROUND tokens; as text on
            // --backgroundSoft they measure 2.6:1 / 3.4:1 / 1.8:1, all far under
            // the WCAG AA 4.5:1 UI.md also demands. Snapping coloured text onto
            // them would trade one iron law for a worse violation of the
            // accessibility floor — and UI.md settles that tie itself: "error
            // text must be readable without color alone."
            w.push(el, 'color', T.textPrimary);
          }
        }
      }
    }

    // Light/white border lines (table rules, row separators, panel edges) →
    // vintage brown, per side. Fields keep their golden bevels (buttons are
    // already excluded by shouldSkip). Saturated colored borders (e.g. red
    // error outlines) are left alone via the grayish check.
    const tg = (el.tagName || '').toUpperCase();
    if (!/^(INPUT|TEXTAREA|SELECT|BUTTON)$/.test(tg)) {
      const SIDES = ['Top', 'Right', 'Bottom', 'Left'];
      for (let i = 0; i < 4; i++) {
        const s = SIDES[i];
        if (cs['border' + s + 'Width'] === '0px' || cs['border' + s + 'Style'] === 'none') continue;
        const bc = parseRGB(cs['border' + s + 'Color']);
        if (!bc || bc.a <= 0.1) continue;
        const grayish = Math.max(bc.r, bc.g, bc.b) - Math.min(bc.r, bc.g, bc.b) <= 60;
        if (grayish && elev(lum(bc)) > 0.18) {
          w.push(el, 'border-' + s.toLowerCase() + '-color', T.surfaceRaised);
        }
      }
    }
  }

  function shouldSkip(el) {
    const tag = (el.tagName || '').toUpperCase();
    if (TAG_SKIP.test(tag)) return true;
    if (tag === 'INPUT') {
      const t = (el.type || '').toLowerCase();
      // Natively-rendered controls: repainting them hides the checked state.
      // checkbox/radio are handled specially in process() (need computed
      // style to tell a real control from a hidden custom-switch proxy).
      if (t === 'range' || t === 'color' || t === 'file') return true;
    }
    if (el.closest && el.closest('button')) return true;
    // CSS above owns CodeNomad's native semantic state dot. Repainting it would
    // erase the working/idle distinction after the first mutation batch.
    try { if (el.matches && el.matches('.status-indicator.session-status > .status-dot')) return true; } catch (e) { }
    try { if (el.closest && el.closest(JS_SKIP_SELECTOR)) return true; } catch (e) { }
    return false;
  }

  // Mutations accumulate in a queue with a fixed 60ms flush. The previous
  // clearTimeout+reset pattern silently DROPPED every batch except the last
  // one (each reset discarded the prior closure's mutations) and could starve
  // forever on continuously-mutating pages.
  let debounceTimer = null;
  let pendingMuts = [];
  const attrCooldown = new WeakMap(); // element -> last attribute-triggered process time

  // Generic circuit breaker for sites not on the known-host list. A universal
  // userscript cannot predict every future SPA, so it must fail cold rather than
  // turn a new framework's mutation storm into a space heater. Once tripped, the
  // CSS theme remains active but all JavaScript repaint work stops for this page.
  const MUTATION_WINDOW_MS = 2000;
  const MUTATION_RECORD_LIMIT = 1200;
  const MUTATION_WORK_LIMIT_MS = 180;
  const ADDED_NODE_BUDGET = 500;
  let mutationWindowStart = performance.now();
  let mutationRecords = 0;
  let mutationWorkMs = 0;
  let repainterSuspended = CSS_ONLY_MODE;

  function resetMutationWindow(now) {
    mutationWindowStart = now;
    mutationRecords = 0;
    mutationWorkMs = 0;
  }

  function suspendRepainter(reason) {
    if (repainterSuspended) return;
    repainterSuspended = true;
    try { mainObserver.disconnect(); } catch (e) { }
    try { shadowObserver.disconnect(); } catch (e) { }
    if (debounceTimer) { clearTimeout(debounceTimer); debounceTimer = null; }
    if (sweepTimer) { clearTimeout(sweepTimer); sweepTimer = null; sweepPlannedAt = 0; }
    pendingMuts.length = 0;
    forcePassesOwed = 0;
    try {
      document.documentElement.setAttribute('data-w95-perf', 'css-only');
      document.documentElement.setAttribute('data-w95-perf-reason', reason);
    } catch (e) { }
  }

  function noteMutationPressure(records) {
    const now = performance.now();
    if (now - mutationWindowStart >= MUTATION_WINDOW_MS) resetMutationWindow(now);
    mutationRecords += records;
    if (mutationRecords > MUTATION_RECORD_LIMIT || mutationWorkMs > MUTATION_WORK_LIMIT_MS) {
      suspendRepainter(mutationRecords > MUTATION_RECORD_LIMIT ? 'mutation-rate' : 'mutation-work');
      return true;
    }
    return false;
  }

  function addWorkPressure(ms, reason) {
    const now = performance.now();
    if (now - mutationWindowStart >= MUTATION_WINDOW_MS) resetMutationWindow(now);
    mutationWorkMs += ms;
    if (mutationWorkMs > MUTATION_WORK_LIMIT_MS) suspendRepainter(reason);
  }

  function onMutations(mutations) {
    if (repainterSuspended || noteMutationPressure(mutations.length)) return;
    for (let i = 0; i < mutations.length; i++) pendingMuts.push(mutations[i]);
    if (debounceTimer) return;
    debounceTimer = setTimeout(() => {
      debounceTimer = null;
      if (repainterSuspended) { pendingMuts.length = 0; return; }
      const workStarted = performance.now();
      const batch = pendingMuts;
      pendingMuts = [];
      const w = [];
      const added = [];
      let styleishAdded = false;
      for (const m of batch) {
        // Class/bgcolor changes restyle existing elements (SPA hydration, lazy
        // CSS-in-JS) — re-process them or they keep stale baked-in colors.
        // Hover-chain elements are skipped inside process() and retried later,
        // so hover class-toggles don't bake in highlight colors.
        if (m.type === 'attributes') {
          const t = m.target;
          if (t && t.nodeType === 1) {
            // No time-window mute here any more — our own style writes are
            // filtered out by identity in flushWrites before this ever runs.
            // Cooldown: carousels/virtual scrollers toggle classes many times a
            // second; re-processing each toggle (computed-style read + writes)
            // is a jank source. During the cooldown just mark the element dirty
            // — the next light sweep picks up its settled state.
            const now = Date.now();
            if ((attrCooldown.get(t) || 0) + 500 > now) {
              t.removeAttribute('data-w95-done');
            } else {
              attrCooldown.set(t, now);
              t.removeAttribute('data-w95-done');
              process(t, false, w);
            }
            const tag = (t.tagName || '').toUpperCase();
            if (tag === 'STYLE' || (tag === 'LINK' && (t.rel || '').toLowerCase().includes('stylesheet'))) {
              styleishAdded = true;
            }
          }
          continue;
        }
        if (m.type === 'childList') {
          const target = m.target;
          if (target && target.nodeType === 1) {
            const tag = (target.tagName || '').toUpperCase();
            if (tag === 'STYLE' || (tag === 'LINK' && (target.rel || '').toLowerCase().includes('stylesheet'))) {
              styleishAdded = true;
            }
          }
        }
        for (const node of m.addedNodes) {
          if (node.nodeType !== 1) continue;
          added.push(node);
          if (!styleishAdded) {
            const tag = (node.tagName || '').toUpperCase();
            if (tag === 'STYLE' || (tag === 'LINK' && (node.rel || '').toLowerCase().includes('stylesheet'))) {
              styleishAdded = true;
            } else if (node.querySelector && node.querySelector('style,link[rel*=stylesheet i]')) {
              styleishAdded = true;
            }
          }
        }
      }

      // De-dup the batch before touching anything (v1.3.0). The parser and SPA
      // hydration routinely report a container AND its descendants as separate
      // addedNodes records in the SAME batch, and the old loop walked every
      // record's whole subtree — so a node covered by an ancestor's walk was
      // re-read, and the code even cleared its data-w95-done first to guarantee
      // the redundant pass happened. Keep only records with no added ancestor in
      // this batch; walking up parentNode is O(depth), never O(batch²).
      if (added.length) {
        const inBatch = new Set(added);
        let addedProcessed = 0;
        let addedTruncated = false;
        for (const node of added) {
          let covered = false;
          for (let p = node.parentNode; p; p = p.parentNode) {
            if (inBatch.has(p)) { covered = true; break; }
          }
          // Added then removed again inside the same 60ms window: a detached
          // element has no computed style worth reading and no pixels to fix.
          if (covered || !node.isConnected) continue;
          node.removeAttribute && node.removeAttribute('data-w95-done');
          process(node, false, w);
          addedProcessed++;
          const kids = node.getElementsByTagName('*');
          for (let i = 0; i < kids.length; i++) {
            if (addedProcessed >= ADDED_NODE_BUDGET) { addedTruncated = true; break; }
            kids[i].removeAttribute && kids[i].removeAttribute('data-w95-done');
            process(kids[i], false, w);
            addedProcessed++;
          }
          if (addedProcessed >= ADDED_NODE_BUDGET) { addedTruncated = true; break; }
        }
        // Only stylesheet-bearing additions need a force re-verify. Plain DOM
        // churn is already processed inline above and does not justify another
        // full sweep.
        if (styleishAdded || addedTruncated) {
          stylesDirty = stylesDirty || styleishAdded;
          requestForceSweep();
        }
      }
      flushWrites(w);
      addWorkPressure(performance.now() - workStarted, 'mutation-work');
    }, 60);
  }
  const mainObserver = new MutationObserver(onMutations);
  const shadowObserver = new MutationObserver(onMutations);

  if (!CSS_ONLY_MODE && document.documentElement) {
    mainObserver.observe(document.documentElement, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['class', 'bgcolor', 'background', 'style']
    });
  }

  // Force passes are budgeted: on huge pages (endless feeds) each pass
  // re-verifies a rotating 2500-element window instead of the whole DOM, so a
  // single pass never janks the main thread; full coverage arrives over a few
  // rotations. The scheduler is now adaptive: when nothing changes, it backs
  // off instead of ticking forever in the background like a stubborn appliance.
  const FORCE_BUDGET = 2500;
  let forceCursor = 0;

  let forcePassesOwed = 0;
  let sweepTimer = null;
  let stylesDirty = true;

  // 🚨 THE SWEEP RATE IS FLOOR-LIMITED. NOTHING MAY SCHEDULE A SWEEP AT 0ms 🚨
  // Measured on a real chatgpt.com conversation (3392 elements, 15s, primitives
  // counted by wrapping them on the prototypes):
  //     querySelectorAll ....    151 calls  -> ~10 sweeps per SECOND
  //     getComputedStyle ....  42563 calls
  //     Element.closest .....  80114 calls
  //     setAttribute ........  43080 calls
  //     long tasks .......... 14158 ms out of 15000 (~94% of wall time)
  // With the script disabled the same page spent 2517ms. So the engine was
  // running roughly 150 full sweeps in 15 seconds instead of ten.
  //
  // Cause: requestForceSweep() ended in scheduleNextSweep(true), i.e. a 0ms
  // timer, and it is called from the mutation handler on every batch that
  // contains added nodes. On a React app that inserts nodes continuously, every
  // insertion queued an immediate full sweep, whose own writes and stylesheet
  // check queued the next one. Back-to-back sweeps with no floor.
  //
  // Two rules now make that impossible:
  //   1. MIN_SWEEP_GAP — a hard minimum between the END of one sweep and the
  //      START of the next. However much churn arrives, sweeps cannot exceed
  //      one per second. This is the actual safety property; the adaptive
  //      backoff below is only an idle optimisation on top of it.
  //   2. A pending timer that already fires SOONER is never replaced by a later
  //      one, and never cancelled and re-armed. The old code cleared and re-armed
  //      the timer on every call, so a stream of requests could keep pushing the
  //      timer around instead of letting it fire.
  const MIN_SWEEP_GAP = 1000;
  let lastSweepEnd = 0;
  let sweepPlannedAt = 0;

  function scheduleSweep(delay) {
    if (repainterSuspended || document.hidden) return;
    const now = Date.now();
    // Never sooner than MIN_SWEEP_GAP after the last sweep finished.
    const earliest = lastSweepEnd + MIN_SWEEP_GAP - now;
    const d = Math.max(delay, earliest, 0);
    const fireAt = now + d;
    // An already-pending sweep that lands sooner wins; do not churn the timer.
    if (sweepTimer && sweepPlannedAt <= fireAt) return;
    if (sweepTimer) clearTimeout(sweepTimer);
    sweepPlannedAt = fireAt;
    sweepTimer = setTimeout(() => {
      sweepTimer = null;
      sweepPlannedAt = 0;
      if (document.hidden) return;

      const force = forcePassesOwed > 0;
      if (force) forcePassesOwed--;

      runSweeper(force);
      lastSweepEnd = Date.now();

      // No automatic reschedule here. Fresh work comes from mutations,
      // stylesheet loads, visibility changes, or the explicit load-time passes.
    }, d);
  }

  // A request means "there is fresh work, revisit soon" — soon being the fast
  // lane, NEVER immediately. runSweeper itself calls this (via stripHoverSheets
  // spotting a changed sheet), so an immediate schedule here is a direct
  // sweep-calls-sweep loop.
  function requestForceSweep() {
    if (repainterSuspended) return;
    if (forcePassesOwed < 2) forcePassesOwed++;
    scheduleSweep(1500);
  }

  function runSweeper(force) {
    if (repainterSuspended) return;
    const sweepStarted = performance.now();
    // Prune shadow roots whose hosts left the DOM (SPA navigations) — keeping
    // them leaks memory and bloats every sweep on long sessions.
    piercedRoots.forEach(root => { try { if (!root.host || !root.host.isConnected) piercedRoots.delete(root); } catch (e) { } });
    // Hover-rule scanning is the expensive part. Only do it when we have a
    // concrete stylesheet signal, or when the caller explicitly asked for a
    // full re-verify.
    const scanStyles = force || stylesDirty;
    if (scanStyles) {
      stylesDirty = false;
      stripHoverSheets(document);
      piercedRoots.forEach(root => { try { stripHoverSheets(root); } catch (e) { } });
    }
    const searchRoots = [document, ...piercedRoots];
    // ONE write queue for the whole sweep across every root: the flush at the
    // end is what collapses thousands of style invalidations into a single
    // recalc. Never flush inside the loop (see the flushWrites comment).
    const w = [];
    searchRoots.forEach(root => {
      try {
        const all = root.querySelectorAll(force ? '*' : '*:not([data-w95-done])');
        if (force && all.length > FORCE_BUDGET) {
          const start = forceCursor % all.length;
          for (let n = 0; n < FORCE_BUDGET; n++) { process(all[(start + n) % all.length], true, w); }
          forceCursor += FORCE_BUDGET;
        } else {
          for (let i = 0; i < all.length; i++) { process(all[i], force, w); }
        }
      } catch (e) { }
    });
    flushWrites(w);
    addWorkPressure(performance.now() - sweepStarted, 'sweep-work');
  }

  // Elements processed before the site's CSS finished loading bake in unstyled
  // values and would otherwise stay wrong forever (white surfaces that "heal"
  // only when the SPA happens to re-render them). Full re-verify passes
  // (force=true) re-check EVERY element: at DOMContentLoaded, again 1s later
  // once late CSS settled, then on demand whenever requestForceSweep() fires.
  // The write-if-changed guard in setImp keeps repeat passes cheap.
  function startSweeping() {
    injectLate();
    if (CSS_ONLY_MODE) {
      try {
        document.documentElement.setAttribute('data-w95-perf', 'css-only');
        document.documentElement.setAttribute('data-w95-perf-reason', 'known-high-churn-host');
      } catch (e) { }
      // One final cascade-order correction after late app CSS arrives. No DOM
      // scan, no observer, no repeating timer.
      window.addEventListener('load', injectLate, { once: true });
      return;
    }
    // The boot pass measured ONE 716ms long task on a 16921-element page, right
    // when the site's own init scripts are competing for the main thread — the
    // "have to reload a couple of times before it comes up" symptom. The
    // read/write split above is what actually shrinks it; deferring the second
    // pass past load keeps it out of the critical window as well.
    // CSS already paints immediately. Corrective JS work is deferred and
    // floor-limited instead of blocking DOMContentLoaded with a full traversal.
    requestForceSweep();
    setTimeout(() => { stylesDirty = true; requestForceSweep(); }, 1500);

    if (!IS_TOP) {
      // Sub-frame: bounded settling passes, then nothing. The MutationObserver
      // stays live, so a late-loading embed still gets themed — that path is
      // event-driven and costs zero while idle.
      setTimeout(() => { stylesDirty = true; requestForceSweep(); }, 3000);
      return;
    }

    // Top frame: event-driven sweeps only. Idle means idle; fresh work
    // re-arms the scheduler through mutations, stylesheet loads, or focus/visibility changes.

    // Pages that finished loading while the tab was hidden got no sweeps; on
    // return, re-verify immediately so the user never sees stale white. This is
    // the ONE place a sweep still runs synchronously without waiting for the
    // floor — it is user-initiated (they just looked at the tab) and happens at
    // most once per tab switch, so it cannot form a loop.
    document.addEventListener('visibilitychange', () => {
      if (!document.hidden) {
        // A tab switch must not synchronously walk a 20,000-node conversation.
        // Repaint later through the same rate-limited lane as every other cause.
        stylesDirty = true;
        requestForceSweep();
      } else if (sweepTimer) {
        clearTimeout(sweepTimer);
        sweepTimer = null;
        sweepPlannedAt = 0;
      }
    });

    // Late external stylesheet loads can alter computed styles without DOM
    // churn. Catch them once and reschedule a real pass instead of polling.
    document.addEventListener('load', (evt) => {
      const t = evt.target;
      if (!t || t.nodeType !== 1) return;
      if ((t.tagName || '').toUpperCase() !== 'LINK') return;
      const rel = (t.rel || '').toLowerCase();
      if (rel.includes('stylesheet')) {
        stylesDirty = true;
        requestForceSweep();
      }
    }, true);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', startSweeping, { once: true });
  } else {
    startSweeping();
  }

  

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
