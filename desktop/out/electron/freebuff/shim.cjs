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
    if (cs.visibility === "hidden" || cs.display === "none" || cs.opacity === "0") return;
    // A click-through layer is a scrim or a measurement probe, never a panel.
    if (cs.pointerEvents === "none") return;

    const r = el.getBoundingClientRect();
    // Zero-size means the panel is closed or this is the wrapper that hosts it.
    // Neither is paintable, and the wrapper must stay transparent or it blacks out
    // a viewport-sized rectangle over the app. Re-decided rather than latched: a
    // popover is mounted closed, so a decision made while it measured nothing
    // would be the only decision ever made about it.
    if (r.width < 40 || r.height < 24) { el.removeAttribute(MARK); return; }
    if (r.width > innerWidth * 0.92 && r.height > innerHeight * 0.92) return;
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

  const fixTree = root => {
    if (!root.querySelectorAll) return;
    // Only out-of-flow elements can qualify, but there is no selector for that, so
    // the cheap filter is the one the DOM can answer: a panel is either portalled
    // to the top of the tree or it is not a panel. Scanning body's own descendants
    // wholesale is what the userscript's repainter exists for; here the point is to
    // stay cheap enough to run on every mutation batch.
    for (const el of root.querySelectorAll("*")) fixOne(el);
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
          for (const node of r.addedNodes) {
            if (node.nodeType === 1) { fixOne(node); fixTree(node); }
          }
        } else if (r.type === "attributes") {
          // A popover is usually mounted closed and then opened by a class or
          // style flip, so the element that matters was already in the tree when
          // it measured zero. Re-measuring on its own attribute change is the only
          // thing that catches it, and it is why the mark is re-decided rather
          // than latched on first sight.
          if (r.target.nodeType === 1) fixOne(r.target);
        }
      }
    });
  }).observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ["style", "class", "hidden", "open", "data-state", "aria-hidden", "aria-expanded"] });

  return "float fix installed";
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

// ─── A BAR THAT REPORTS A VALUE IS DATA, NOT DECORATION ──────────────────────
// Same family as the status dot, one step further out. A usage bar, a context
// meter, a quota strip -- the number they carry is not in the text next to them,
// it is in HOW MUCH OF THE TRACK IS FILLED. The stylesheet flattens surfaces so
// an app reads as one window, and in doing so it paints the fill and the track
// the same colour: the bar survives as a rectangle and loses the only thing it
// was drawn for. Reported as "the strip that shows how full it is is now solid".
//
// The state exclusions cannot catch these. They key on role="progressbar" and
// friends, and a fill is almost never marked -- it is an unmarked div inside a
// track, and the app renames both every redesign. What it CANNOT stop doing is
// computing the fill inline: the width is a live value, so it lands in a style
// attribute as a percentage or a scaleX, every time, in every framework. That is
// the signal, it is structural, and it costs nothing to read.
//
// So: a short wide box holding a child sized by a percentage is a track holding a
// fill. The track is sunk to a recessed surface, the fill is painted in the
// palette's accent, and the proportion between them is readable again. Nothing is
// matched by name; a bar that stops being computed inline stops being a bar.
const PROGRESS_FIX = `(() => {
  if (window.__wintageProgressFix) return "already running";
  window.__wintageProgressFix = true;

  const MARK = "data-w95-bar";
  const PCT = /(^|[^-\\w])width:\\s*[\\d.]+%/i;

  const looksLikeFill = el => {
    const style = el.getAttribute("style") || "";
    if (PCT.test(style) || /scaleX\\(/i.test(style)) return true;
    const tr = getComputedStyle(el).transform;
    // matrix(a, ...) with a != 1 is a scaleX in disguise, which is how the
    // smoother implementations animate a fill.
    const m = /^matrix\\(([\\d.-]+),/.exec(tr);
    return !!m && Math.abs(parseFloat(m[1]) - 1) > 0.001;
  };

  const fixTrack = track => {
    const tr = track.getBoundingClientRect();
    // A track is short, wide, and not the page. Everything taller than a line of
    // text is a layout box that happens to hold a percentage-sized child.
    if (tr.height < 2 || tr.height > 24 || tr.width < 40) return false;
    let painted = false;
    for (const fill of track.children) {
      if (!looksLikeFill(fill)) continue;
      const fr = fill.getBoundingClientRect();
      if (fr.width < 1 || fr.height < 1) continue;
      fill.style.setProperty("background-color", "var(--link)", "important");
      fill.style.setProperty("background-image", "none", "important");
      fill.style.setProperty("border-radius", "0", "important");
      fill.setAttribute(MARK, "fill");
      painted = true;
    }
    if (!painted) return false;
    // Win95 draws a progress track sunken, so the fill reads as sitting IN it.
    track.style.setProperty("background-color", "var(--surface)", "important");
    track.style.setProperty("background-image", "none", "important");
    track.style.setProperty("border-width", "2px", "important");
    track.style.setProperty("border-style", "solid", "important");
    track.style.setProperty("border-color", "var(--borderDark) var(--bevelLight) var(--bevelLight) var(--borderDark)", "important");
    track.style.setProperty("box-sizing", "border-box", "important");
    track.setAttribute(MARK, "track");
    return true;
  };

  const scan = root => {
    if (!root.querySelectorAll) return;
    for (const el of root.querySelectorAll("*")) {
      if (el.children.length) fixTrack(el);
    }
  };

  scan(document);
  let passes = 0;
  const settle = () => { if (++passes < 3) { scan(document); setTimeout(settle, 600); } };
  setTimeout(settle, 600);

  let queued = false;
  const pending = [];
  new MutationObserver(records => {
    pending.push(...records);
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => {
      queued = false;
      const recs = pending.splice(0, pending.length);
      for (const r of recs) {
        if (r.type === "attributes") {
          // The fill's own style attribute changing IS the value changing, so the
          // parent is re-read rather than trusted to have been done once.
          const p = r.target.parentElement;
          if (p) fixTrack(p);
        } else {
          for (const node of r.addedNodes) {
            if (node.nodeType !== 1) continue;
            if (node.parentElement) fixTrack(node.parentElement);
            scan(node);
          }
        }
      }
    });
  }).observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ["style", "aria-valuenow"] });

  return "progress fix installed";
})()`;

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
        wc.executeJavaScript(FLOAT_FIX, true)
          .then(r => stamp('floatfix: ' + r))
          .catch(err => stamp('floatfix FAILED: ' + (err && err.message)));
        wc.executeJavaScript(PROGRESS_FIX, true)
          .then(r => stamp('progressfix: ' + r))
          .catch(err => stamp('progressfix FAILED: ' + (err && err.message)));
        wc.executeJavaScript(SCROLL_INTENT_FIX, true)
          .then(r => stamp('scrollintent: ' + r))
          .catch(err => stamp('scrollintent FAILED: ' + (err && err.message)));
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
