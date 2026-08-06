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
const REPAINTER_BODY = /* __REPAINTER__ */ "";

// The one place insertCSS cannot reach. It produces a DOCUMENT stylesheet, and a
// document stylesheet does not cross a shadow boundary, so every rule written for
// a shadow tree has to be carried in and injected root by root -- which is what
// the repainter's pierceShadow does with this.
const SHADOW_CSS = /* __SHADOW_CSS__ */ "";

// Everything the extracted body reads from the userscript's outer scope has to be
// handed to it here. That list is not maintained by hand and hope: build-desktop.js
// fails the build if the userscript ever starts reading something this prelude does
// not define, because the failure mode otherwise is a ReferenceError thrown inside
// executeJavaScript, which surfaces as "the theme just does not work" and nothing
// else.
const REPAINTER_FIX = `(() => {
  if (window.__wintageRepainter) return "already running";
  window.__wintageRepainter = true;

  const W95_VERSION = '${VERSION}';

  // This pack's palette, whole. Not trimmed to what the repainter happens to read
  // today: it builds PALETTE_RGB from Object.keys(T) to recognise its own colours,
  // so a missing token would make it treat one of our own greys as the site's.
  const T = {
    background: '${T.background}',
    backgroundSoft: '${T.backgroundSoft}',
    surface: '${T.surface}',
    surfaceRaised: '${T.surfaceRaised}',
    surfaceAlt: '${T.surfaceAlt}',
    borderDark: '${T.borderDark}',
    borderHighlight: '${T.borderHighlight}',
    bevelLight: '${T.bevelLight}',
    borderMuted: '${T.borderMuted}',
    link: '${T.link}',
    textPrimary: '${T.textPrimary}',
    textSecondary: '${T.textSecondary}',
    textMuted: '${T.textMuted}',
    accentTeal: '${T.accentTeal}',
    accentTealDeep: '${T.accentTealDeep}',
    success: '${T.success}',
    warning: '${T.warning}',
    danger: '${T.danger}',
    dangerText: '${T.dangerText}',
    selection: '${T.selection}',
    compareBack: '${T.compareBack}'
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
