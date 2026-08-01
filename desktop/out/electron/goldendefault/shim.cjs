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

// ─── WHAT THE PROBE ACTUALLY FOUND, AND WHY THE URL TEST WAS THE BUG ────────
// Measured on 1.24012.9, https://claude.ai/epitaxy: body color rgb(0,0,0), html
// background rgba(0,0,0,0), 129 of 135 sampled text nodes black, and ZERO
// elements with opacity below 1. So neither of the two suspects was real: the
// text is not dimmed, it is BLACK, and this theme's stylesheet is not in force on
// that document at all (it sets html's background unconditionally, and html came
// back transparent).
//
// The thing that made 1.23.2 look half-fixed is that CLAUDE_VIEW decides by URL.
// Claude spreads its interface over several webContents, and the status file
// shows a THIRD one at `about:blank` receiving 44225 bytes -- the shared
// stylesheet without the foreground repair, because "about:blank" matches no
// pattern. That frame gets the brown surfaces and bevels and keeps Claude's own
// near-black label colour: black on brown, which is exactly what was reported.
//
// A URL is the wrong key for a decision that is about WHICH APPLICATION this is.
// The app is asked directly now (see IS_CLAUDE_APP), so every frame Claude owns
// gets the repair including the unnamed ones, and no other application can ever
// receive it by having a frame that happens to sit on about:blank.
//
// The probe stays, and now runs on every frame of that app rather than the ones a
// pattern recognised -- the previous version could not see the very frame that
// was broken. It reads only: no element is modified and nothing is injected into
// the page's own state.
// ─── STOP ARGUING WITH THE CASCADE ──────────────────────────────────────────
// Four measurements in, this is what the numbers actually say about epitaxy: our
// stylesheet IS live there (--bevelLight reads back off :root, and nothing else
// declares it), the app does NOT clobber our variables (--background is still our
// value, so it never defined one), no wrapper is faded (zero elements under
// opacity 1) -- and `html { color: … !important }` from that same live sheet still
// loses, leaving html and body at rgb(0,0,0) with 129 identical black text nodes
// hanging off them.
//
// Identical is the tell: those nodes are not each painted black, they INHERIT it
// from a black body. So one element decides the colour of the whole transcript,
// and every attempt so far has tried to win that one declaration through a
// stylesheet -- author origin (lost to Tailwind's layered !important, which
// outranks unlayered !important), then user origin (no better, for reasons the
// numbers no longer justify guessing at).
//
// An inline declaration with `important` is not in that argument at all: it beats
// every author rule, layered or not, at any specificity. Two elements, two
// properties, and the existing `color: inherit` repair carries it to the rest.
// This is the repainter pattern the userscript has relied on for years for exactly
// this situation -- CSS that cannot win from a stylesheet gets written onto the
// element. The shim deliberately ships no general repainter; this is two nodes.
const CLAUDE_ROOT_PAINT = `(() => {
  if (window.__wintageRootPaint) return "already painting";
  window.__wintageRootPaint = true;
  const FG = "${T_TEXT || ''}", BG = "${T_BACKGROUND || ''}";
  if (!FG) return "no palette foreground, nothing painted";

  const need = (el, prop, val) =>
    el.style.getPropertyValue(prop) !== val || el.style.getPropertyPriority(prop) !== "important";

  const paint = () => {
    const els = [document.documentElement, document.body];
    for (const el of els) {
      if (!el) continue;
      // Checked before writing, and that is what keeps the observer below from
      // feeding itself: a write that changes nothing produces no new record.
      if (need(el, "color", FG)) el.style.setProperty("color", FG, "important");
    }
    if (BG && document.documentElement && need(document.documentElement, "background-color", BG)) {
      document.documentElement.style.setProperty("background-color", BG, "important");
    }
  };

  paint();
  // The app rewrites its root's style attribute as it themes itself, so the paint
  // has to be re-asserted rather than set once. childList as well as the style
  // attribute: a framework that swaps <body> out takes the inline declaration with
  // it, and observing only attributes would never notice.
  new MutationObserver(paint).observe(document.documentElement, { attributes: true, attributeFilter: ["style"], childList: true });
  if (document.body) new MutationObserver(paint).observe(document.body, { attributes: true, attributeFilter: ["style"] });
  // Long enough to outlast a late client-side render. Cheap: paint() writes nothing
  // when the values are already right, so a settled document costs two comparisons.
  let n = 0;
  const tick = () => { if (++n < 40) { paint(); setTimeout(tick, 500); } };
  setTimeout(tick, 400);

  return "root painted fg=" + FG + " bg=" + BG + " at " + location.href.slice(0, 60);
})()`;

// ─── THE REPAINTER, WHICH THIS SHIM HAS ALWAYS GONE WITHOUT ─────────────────
// tools/build-desktop.js says it plainly: the stylesheet comes over from the
// userscript, "what does NOT come along is the repainter (the JS that fixes what
// CSS cannot win on arbitrary sites)", on the reasoning that a single known
// application is a smaller loss than the open web. Claude is the case that
// disproves it. Its interface carries its own greys, and a grey that was chosen
// against Claude's own near-black background is simply dim once this theme puts a
// warm brown behind it -- no cascade fight involved, nothing overriding anything.
// That is what "unreadable" has been the whole time, and it is why five rounds of
// origin and specificity work changed nothing anyone could see.
//
// So contrast is MEASURED here and repaired only where it actually fails, rather
// than repainting every label and flattening the hierarchy the app designed.
//
// Cost discipline from ADR-002/ADR-004, which this project paid for once already:
// getComputedStyle over a whole document is expensive, so this visits only
// elements that directly own text, remembers what it fixed, runs a few bounded
// passes and then only on mutations, batched into one frame. Never on a timer.
const CLAUDE_CONTRAST = `(() => {
  if (window.__wintageContrast) return "already running";
  window.__wintageContrast = true;

  const FG = "${T_TEXT || ''}";
  if (!FG) return "no palette foreground, nothing repainted";

  const rgb = s => {
    const m = /rgba?\\(([^)]+)\\)/.exec(s || "");
    if (!m) return null;
    const p = m[1].split(",").map(n => parseFloat(n));
    return p.length >= 3 ? { r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1 } : null;
  };
  const lin = v => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4); };
  const lum = c => 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
  const ratio = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };

  // The colour a label is really sitting on: the nearest ancestor that actually
  // paints something. Anything else compares text against transparency.
  const backdrop = el => {
    for (let p = el; p; p = p.parentElement) {
      const c = rgb(getComputedStyle(p).backgroundColor);
      if (c && c.a > 0.5) return c;
    }
    return rgb(getComputedStyle(document.documentElement).backgroundColor) || { r: 26, g: 24, b: 16, a: 1 };
  };

  const ownsText = el => {
    for (const n of el.childNodes) if (n.nodeType === 3 && n.nodeValue.trim()) return true;
    return false;
  };

  const fixed = new WeakMap();
  let repaired = 0, seen = 0;

  const fixOne = el => {
    if (!ownsText(el)) return;
    seen++;
    const cs = getComputedStyle(el);
    const col = rgb(cs.color);
    if (!col) return;
    // Our own previous repair, still standing: nothing to do.
    if (fixed.get(el) === cs.color) return;
    const bg = backdrop(el);
    // A fully transparent label is deliberate (screen-reader text, fade-ins) and
    // painting it would REVEAL something the app is hiding -- the v29 lesson.
    if (col.a < 0.05) return;
    if (ratio(col, bg) >= 4.5) return;
    el.style.setProperty("color", FG, "important");
    el.style.setProperty("-webkit-text-fill-color", FG, "important");
    fixed.set(el, getComputedStyle(el).color);
    repaired++;
  };

  const fixTree = root => {
    if (root.nodeType !== 1 && root.nodeType !== 9) return;
    if (root.nodeType === 1) fixOne(root);
    const els = root.querySelectorAll ? root.querySelectorAll("*") : [];
    for (const el of els) fixOne(el);
  };

  fixTree(document);
  let passes = 0;
  const settle = () => { if (++passes < 4) { fixTree(document); setTimeout(settle, 700); } };
  setTimeout(settle, 700);

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
        if (r.type === "childList") {
          for (const n of r.addedNodes) if (n.nodeType === 1) fixTree(n);
          if (r.target.nodeType === 1) fixOne(r.target);
        } else if (r.target.nodeType === 1) {
          fixOne(r.target);
        }
      }
    });
  }).observe(document.documentElement, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ["class", "style"] });

  return "contrast repainter installed, repaired " + repaired + " of " + seen + " text-owning elements";
})()`;

const CLAUDE_PROBE = `(() => {
  const cs = getComputedStyle(document.body);
  const out = ["title=" + JSON.stringify(document.title) + " nodes=" + document.body.querySelectorAll("*").length];
  out.push("body color=" + cs.color + " bg=" + cs.backgroundColor + " opacity=" + cs.opacity);
  const rt = getComputedStyle(document.documentElement);
  out.push("html color=" + rt.color + " bg=" + rt.backgroundColor + " opacity=" + rt.opacity);

  // Is this theme in force on THIS document at all? html's background is set
  // unconditionally by the shared stylesheet, so a transparent one means the
  // insertCSS that reported success is not affecting the document being measured
  // -- a different question from "the colours are wrong", and the two were
  // indistinguishable until it was asked directly.
  const want = "${T_BACKGROUND || ''}".toLowerCase();
  const got = rt.backgroundColor.replace(/^rgba?\\(|\\)$/g, "").split(",").map(n => Number(n.trim()));
  const transparent = got.length >= 4 && got[3] === 0;
  const asHex = transparent ? "transparent" : (got.length >= 3 ? "#" + got.slice(0, 3).map(n => n.toString(16).padStart(2, "0")).join("") : "n/a");
  out.push("wintage stylesheet in force: " + (asHex === want ? "YES" : "NO (html bg " + asHex + ", palette " + want + ")"));

  // ─── PRESENT-BUT-OUTVOTED, OR NOT PRESENT AT ALL? ─────────────────────────
  // These are two different bugs with two different fixes, and every measurement
  // so far has been unable to tell them apart. If the sheet is in the document
  // and html is still untouched, this theme is losing the cascade and the answer
  // is specificity or insertion order. If the sheet is simply absent, insertCSS
  // reported success against a document that no longer exists -- and the fix is
  // in WHEN it is inserted, not in what it says.
  let ours = 0, sheets = 0, unreadable = 0;
  for (const sh of document.styleSheets) {
    sheets++;
    let rules = null;
    try { rules = sh.cssRules; } catch (e) { unreadable++; continue; }
    if (!rules) continue;
    for (const r of rules) {
      if (r.cssText && r.cssText.indexOf("--bevelLight") >= 0) { ours++; break; }
    }
  }
  out.push("styleSheets=" + sheets + " unreadable=" + unreadable + " carrying our token=" + ours +
    " (author-origin only -- a USER-origin sheet is invisible here, which is why the next line exists)");

  // The question the sheet count can no longer answer. A user-origin stylesheet
  // does not appear in document.styleSheets at all, so "is it live?" has to be
  // asked of the CASCADE instead of the sheet list:
  //   --bevelLight  is declared by nothing but this theme, so reading it back off
  //                 :root proves our declarations reached this document.
  //   --background  is a generic name a Tailwind design system also uses; if the
  //                 app declares one, it must now WIN (ours is non-important at
  //                 user origin), and seeing the app's value here is the proof
  //                 that we stopped breaking hsl(var(--background)).
  const rootStyle = getComputedStyle(document.documentElement);
  out.push("our token via cascade: --bevelLight=" + JSON.stringify(rootStyle.getPropertyValue("--bevelLight").trim()) +
    "  --background=" + JSON.stringify(rootStyle.getPropertyValue("--background").trim()));
  // NOT border-radius: 0px is also its initial value, so that witness proved
  // nothing and cost a round trip. This one cannot be confused with a default --
  // the inline declaration is either on the element or it is not, and if it is
  // there while the computed colour is still black, the document being measured is
  // not the document that was painted.
  out.push("inline on <html>: " + JSON.stringify((document.documentElement.getAttribute("style") || "").slice(0, 120)));
  out.push("inline on <body>: " + JSON.stringify((document.body.getAttribute("style") || "").slice(0, 120)));

  // ─── A CONTROLLED EXPERIMENT, BECAUSE THE CASCADE SAYS THIS CANNOT HAPPEN ──
  // The line above proves an inline important colour is ON <html> while the
  // computed colour is still rgb(0,0,0). Author inline important is beaten by
  // exactly two things: user origin and UA origin -- and forced-colors mode is the
  // one that does it wholesale, which also matches 150 text nodes landing on the
  // identical black. Rather than argue the point, put a fresh element in this
  // document with an inline red and read it back. Red means only the root is
  // special and the hunt continues there; black means this document ignores author
  // colours entirely and the fix is forced-color-adjust, not the cascade.
  // (No backticks in here: this comment lives inside a template literal, and one
  // would end it. node --check caught that, which is the only reason it is a note
  // and not a shipped syntax error.)
  try {
    const t = document.createElement("div");
    t.style.setProperty("color", "rgb(255, 0, 0)", "important");
    t.style.setProperty("background-color", "rgb(0, 255, 0)", "important");
    document.documentElement.appendChild(t);
    const tc = getComputedStyle(t);
    out.push("control div with inline !important red/green -> color=" + tc.color + " bg=" + tc.backgroundColor);
    t.remove();
  } catch (e) { out.push("control div failed: " + e.message); }

  out.push("forced-colors active=" + matchMedia("(forced-colors: active)").matches +
    " prefers-contrast=" + (matchMedia("(prefers-contrast: more)").matches ? "more" : "no-preference") +
    " prefers-color-scheme=" + (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light") +
    " forcedColorAdjust=" + rootStyle.forcedColorAdjust +
    " color-scheme=" + rootStyle.colorScheme);

  out.push("frame: top=" + (window.top === window) + " iframes=" + document.querySelectorAll("iframe").length +
    " visibility=" + document.visibilityState + " focus=" + document.hasFocus());
  // insertCSS reaches the MAIN frame only. If the interface people actually look at
  // lives in a child frame, every measurement above describes the wrong document.
  [].forEach.call(document.querySelectorAll("iframe"), (f, i) => {
    let inner = "cross-origin";
    try {
      const d = f.contentDocument;
      inner = d ? ("nodes=" + d.body.querySelectorAll("*").length +
        " color=" + getComputedStyle(d.body).color +
        " ourToken=" + JSON.stringify(getComputedStyle(d.documentElement).getPropertyValue("--bevelLight").trim())) : "no document";
    } catch (e) { inner = "cross-origin (" + e.name + ")"; }
    out.push("  iframe[" + i + "] src=" + JSON.stringify((f.getAttribute("src") || "").slice(0, 80)) + " " + inner);
  });

  // Any ancestor with opacity < 1 dims its whole subtree, and one such wrapper
  // high in the tree is enough to explain a uniformly washed window.
  const faded = [];
  for (const el of document.querySelectorAll("*")) {
    const o = parseFloat(getComputedStyle(el).opacity);
    if (o < 0.999) {
      let depth = 0; for (let p = el; p; p = p.parentElement) depth++;
      faded.push({ o, depth, tag: el.tagName.toLowerCase(), cls: (el.className && el.className.baseVal !== undefined ? el.className.baseVal : el.className || "").toString().slice(0, 60), n: el.querySelectorAll("*").length });
    }
  }
  faded.sort((a, b) => b.n - a.n);
  out.push("elements with opacity<1: " + faded.length);
  for (const f of faded.slice(0, 5)) out.push("  opacity=" + f.o + " depth=" + f.depth + " <" + f.tag + " class='" + f.cls + "'> wrapping " + f.n + " nodes");

  // What the ordinary prose actually computes to, sampled from real text nodes.
  const seen = new Map();
  const walk = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  let node, sampled = 0;
  while ((node = walk.nextNode()) && sampled < 400) {
    if (!node.nodeValue.trim() || !node.parentElement) continue;
    sampled++;
    const s = getComputedStyle(node.parentElement);
    const key = s.color + " | " + s.webkitTextFillColor + " | " + s.opacity;
    seen.set(key, (seen.get(key) || 0) + 1);
  }
  out.push("text colours over " + sampled + " sampled text nodes:");
  for (const [k, v] of [...seen].sort((a, b) => b[1] - a[1]).slice(0, 6)) out.push("  x" + v + "  " + k);
  return out.join("\\n");
})()`;

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
// Eight rounds of "change one thing, ask the user to restart, read a status file"
// is the wrong shape of work, and it is expensive for the person doing the
// restarting. A debug port turns that into a session where the live application
// can be inspected directly -- every frame, its real computed styles, and which
// one is actually on screen.
//
// OFF unless a file called `wintage-debug.port` sits next to this shim, and its
// contents are the port. That makes it deliberate, greppable and trivially
// revoked: delete the file, restart, gone. It is never on for an ordinary
// install, because a debugging port left open on someone's machine is not a
// detail to leave to memory.
try {
  const portFile = path.join(__dirname, 'wintage-debug.port');
  if (fs.existsSync(portFile)) {
    const port = (fs.readFileSync(portFile, 'utf8').trim() || '9222').replace(/[^0-9]/g, '') || '9222';
    const { app } = require('electron');
    app.commandLine.appendSwitch('remote-debugging-port', port);
    // Bound to loopback explicitly rather than relying on the default.
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

    // WHICH APPLICATION is this? The foreground repair must reach every frame
    // Claude renders into and no frame of anything else, and the URL could not
    // answer that: Claude's own interface appears at claude.ai/epitaxy, at a
    // file:// shell and at about:blank, and "about:blank" is not a name any
    // pattern can safely claim -- FreeBuff and CodeNomad have blank frames too.
    //
    // The name comes from the archive's package.json, which the installer copies
    // verbatim precisely so the app keeps its identity, so this is the same string
    // an unpatched launch would report and it does not depend on where the app is
    // installed or which URL it happens to be showing.
    // Two independent signals, because neither is guaranteed on its own. Claude's
    // manifest carries name "@ant/desktop" and productName "Claude": getName() is
    // documented to prefer productName, so it should say "claude" -- but a detection
    // that silently turns into a no-op when that preference changes is how this bug
    // survived two releases already. The install location is the second witness and
    // does not depend on any manifest field. Whichever answered is stamped, so the
    // status file says what was detected rather than leaving it to be inferred.
    let appName = '';
    try { appName = (app.getName() || '').toLowerCase(); } catch (e) { }
    const IS_CLAUDE_APP = /claude/.test(appName) || /anthropicclaude/.test(__dirname.toLowerCase());

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
        fs.writeFileSync(f, (prev + new Date().toISOString() + ' ' + text + '\n').split('\n').slice(-200).join('\n'));
      } catch (e) { }
    };
    stamp('app "' + appName + '" claude=' + IS_CLAUDE_APP);

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
        // The TYPE settles which of these frames is the interface and which are
        // scaffolding, which five rounds of DOM measurement could not: the page can
        // report visibility "visible" and focus true while sitting in a view nobody
        // has attached. Only the main process knows.
        let kind = '?';
        try { kind = wc.getType() + (wc.isDestroyed() ? ' destroyed' : '') + ' title=' + JSON.stringify(wc.getTitle()); } catch (e) { }
        stamp('frame ' + kind + ' url=' + url.slice(0, 70));
        wc.executeJavaScript(SCROLL_FIX, true)
          .then(r => stamp('scrollfix: ' + r))
          .catch(err => stamp('scrollfix FAILED: ' + (err && err.message)));
        wc.executeJavaScript(WCO_FIX, true)
          .then(r => stamp('wcofix: ' + r))
          .catch(err => stamp('wcofix FAILED: ' + (err && err.message)));
        // App first, URL second. The URL test is kept because it still identifies
        // Claude's views when they are hosted by something else (its web build in a
        // browser profile), but the app name is what covers about:blank.
        const isClaude = IS_CLAUDE_APP || CLAUDE_VIEW.test(url);
        const payload = isClaude ? css + CLAUDE_FOREGROUND_CSS : css;
        // ─── USER ORIGIN, NOT AUTHOR ───────────────────────────────────────
        // Measured on https://claude.ai/epitaxy: our sheet IS in the document
        // (styleSheets=25, exactly one carrying our own --bevelLight) and html is
        // still untouched. So this was never a delivery problem, and the page-held
        // <style> written for that hypothesis has been removed rather than left in
        // as a second thing to reason about.
        //
        // Two mechanisms, one cure. Claude's UI is Tailwind-shaped, and for
        // `!important` declarations cascade LAYERS INVERT the usual order --
        // important rules in a layer beat important rules that are unlayered, which
        // is what every rule in this stylesheet is. Author origin could not win that
        // fight no matter how the selectors were written. User origin sits above the
        // whole author origin for important declarations, layered or not.
        //
        // It also fixes the black text, which was never Claude painting anything
        // black: the :root block here redefines generic token names (--background,
        // --surface, --textPrimary) that a Tailwind design system also uses, but in
        // a different format, so `hsl(var(--background))` became invalid and every
        // colour collapsed to its initial value. Those declarations are NOT
        // !important, so from user origin they now lose to the app's own and its
        // variables survive intact -- the theme stops breaking the thing it is
        // trying to paint.
        // Claude only, and that scope is the whole lesson. User origin outranks the
        // entire author origin for important declarations, which is what Claude's
        // Tailwind cascade layers require -- but applied everywhere it makes this
        // theme win fights it was previously LOSING on purpose. CodeNomad reported
        // it within minutes: its list rows went pale grey, because rules that the
        // app used to override were suddenly beating it. Author origin is not a
        // weaker choice, it is the co-operative one, and it stays the default for
        // every app that does not need otherwise.
        wc.insertCSS(payload, { cssOrigin: isClaude ? 'user' : 'author' })
          .then(() => {
            stamp('injected ' + payload.length + ' bytes into ' + url);
            // AFTER the stylesheet, or the probe measures the unthemed document and
            // reports numbers that describe nothing. Delayed because Claude paints
            // its shell first and the transcript a beat later, and a probe that runs
            // against an empty body samples no text at all.
            if (isClaude) {
              wc.executeJavaScript(CLAUDE_ROOT_PAINT, true)
                .then(r => stamp('rootpaint: ' + r))
                .catch(err => stamp('rootpaint FAILED: ' + (err && err.message)));
              wc.executeJavaScript(CLAUDE_CONTRAST, true)
                .then(r => stamp('contrast: ' + r))
                .catch(err => stamp('contrast FAILED: ' + (err && err.message)));
              setTimeout(() => {
                wc.executeJavaScript(CLAUDE_PROBE, true)
                  .then(r => stamp('probe ' + url + '\n' + r))
                  .catch(err => stamp('probe FAILED: ' + (err && err.message)));
              }, 4000);
            }
          })
          .catch(err => {
            stamp('FAILED: ' + (err && err.message));
            console.error('[wintage] insertCSS failed:', err && err.message);
          });
      };
      // insertCSS does not survive a navigation, and the guard above is keyed on the
      // URL -- so a reload of the SAME url (a sign-in round trip, an in-app refresh,
      // a renderer recovering from a crash) was indistinguishable from the three
      // events that fire for one document, and the theme silently never came back.
      // Clearing the key when a load STARTS keeps the de-duplication and drops the
      // false negative.
      wc.on('did-start-loading', () => { injectedFor = null; });
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
