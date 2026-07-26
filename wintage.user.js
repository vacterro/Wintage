// ==UserScript==
// @name         Wintage — Win95 Dark Golden Vintage Theme
// @namespace    https://github.com/vacterro/Wintage
// @version      1.3.0
// @description  Dark Golden Windows 95 vintage theme for every site: pixel-sharp 3D bevels, zero rounded corners, zero animations, site hover-highlighting fully disabled, gray surfaces remapped to warm browns, Verdana forced everywhere.
// @author       vacterro
// @license      MIT
// @homepageURL  https://github.com/vacterro/Wintage
// @supportURL   https://github.com/vacterro/Wintage/issues
// @updateURL    https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js
// @downloadURL  https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js
// @match        *://*/*
// @include      about:blank
// @run-at       document-start
// @grant        none
// ==/UserScript==

(function () {
  'use strict';

  // ─── EARLY RETURN GUARD ──────────────────────────────────────────────────────
  const EXCLUDE = [
    // Auth & Payments (don't break secure forms)
    /oauth/i, /captcha/i, /accounts\.google/i, /login\.microsoft/i, /paypal/i, /stripe/i, /bank/i,
    // Heavy Web Apps (lag too much or UI gets destroyed)
    /translate\.google/i, /maps\.google/i, /figma\.com/i, /canva\.com/i, /webflow\.com/i, /photopea\.com/i
  ];
  if (EXCLUDE.some(r => r.test(location.href))) return;

  // ─── FRAME ROLE ──────────────────────────────────────────────────────────────
  // @match *://*/* + @run-at document-start means this script runs in EVERY
  // frame, ads and tracking pixels included. The CSS and the event-driven
  // observers are cheap per frame and genuinely needed (an unthemed embed is a
  // white rectangle), but the periodic sweeper is not: on an ad-heavy page it
  // multiplied a permanent 1.5s wake-up by the frame count. Sub-frames get a few
  // bounded settling sweeps at load instead of an interval that never ends.
  // NOT solved with @noframes — that would leave every embed unthemed.
  let IS_TOP = true;
  try { IS_TOP = window.top === window.self; } catch (e) { IS_TOP = false; }

  // ─── IMMEDIATE DARK GOLDEN BACKGROUND ────────────────────────────────────────
  document.documentElement.style.setProperty('background-color', '#1A0F05', 'important');
  document.documentElement.style.setProperty('color', '#D4B87A', 'important');
  document.documentElement.setAttribute('data-w95-dark', '1');

  // ─── VINTAGE TOKENS (from /vintage SKILL.md) ────────────────────────────────
  // background #1A0F05 | backgroundSoft #1E1408 | surface #2A1C0A | surfaceRaised #362812
  // surfaceAlt #3A2A15 | borderDark #0E0803 | borderHighlight #C0A060 | borderMuted #4A3820
  // textPrimary #D4B87A | textSecondary #B09558 | textMuted #7A6838 | compareBack #0F0A04

  // Verdana forced 100% everywhere. Verdana_m1 = locally installed modified Verdana.
  const FONT = 'Verdana_m1, Verdana, Tahoma, "MS Sans Serif", sans-serif';

  // ─── STRUCTURAL BEVEL CONSTANTS (PHYSICAL BORDERS + 1 INSET) ───────────────
  const B_OUTER = 'border-top: 1px solid #C0A060 !important; border-left: 1px solid #C0A060 !important; border-bottom: 1px solid #0E0803 !important; border-right: 1px solid #0E0803 !important; box-shadow: inset 1px 1px 0 #7A6838, inset -1px -1px 0 #1E1408 !important;';
  const B_INNER = 'border-top: 1px solid #0E0803 !important; border-left: 1px solid #0E0803 !important; border-bottom: 1px solid #C0A060 !important; border-right: 1px solid #C0A060 !important; box-shadow: inset 1px 1px 0 #1E1408, inset -1px -1px 0 #7A6838 !important;';
  const B_SUNK = 'border-top: 1px solid #4A3820 !important; border-left: 1px solid #4A3820 !important; border-bottom: 1px solid #C0A060 !important; border-right: 1px solid #C0A060 !important; box-shadow: inset 1px 1px 0 #0E0803 !important;';

  // ═══════════════════════════════════════════════════════════════════════════════
  // GLOBAL CSS — v29.0
  // ═══════════════════════════════════════════════════════════════════════════════
  const GLOBAL_CSS = `
:root {
  color-scheme: dark !important;
  --w95-canvas:  #1A0F05; --w95-soft:    #1E1408; --w95-surface: #2A1C0A;
  --w95-raised:  #362812; --w95-alt:     #3A2A15;
  --w95-hi:      #C0A060; --w95-dk:      #0E0803; --w95-muted:   #4A3820;
  --w95-text:    #D4B87A; --w95-text2:   #B09558; --w95-dim:     #7A6838;
  --w95-accent:  #9DD9F9;
  --radius: 0px; --radius-none: 0px; --radius-2xs: 0px; --radius-xs: 0px; --radius-sm: 0px;
  --radius-md: 0px; --radius-lg: 0px;  --radius-xl: 0px; --radius-2xl: 0px;
  --radius-full: 0px; --radius-round: 0px; --radius-pill: 0px; --radius-circle: 0px;
  --border-radius: 0px; --border-radius-full: 0px; --border-radius-pill: 0px;
  --bs-border-radius: 0px; --bs-border-radius-pill: 0px;
  --mdc-shape-small: 0px; --md-sys-shape-corner-full: 0px;
  --shreddit-border-radius: 0px; --post-action-border-radius: 0px;
  --yt-border-radius: 0px; --ytd-searchbox-border-radius: 0px;
}

/* 🚨 STRICT RADIUS KILLER, NO GLOBAL BOX-SIZING TO PREVENT FLEX BREAKS 🚨 */
* { border-radius: 0 !important; }

/* 🚨 MOTION IS MOSTLY FORBIDDEN (SKILL.md), WITH A NARROW CARVE-OUT 🚨
   transition-duration is 0.001s, NOT "transition: none" — a none/zero transition
   never fires transitionend, and spoiler/accordion/modal JS commonly waits for
   that event to set height:auto and release scroll locks. transition:none left
   forum spoilers stuck mid-open with broken page scroll (aechat.ru report).
   1ms still reads as instant but the event pipeline keeps working.
   transition-property is ONLY height/max-height/min-height — the exact
   properties collapse/spoiler code actually toggles (max-height:0->N is the
   standard accordion trick, since height:auto itself doesn't transition).
   opened visually but were NOT clickable. Isolated with a live binary search
   (each candidate property list re-tested against a real dispatched click +
   elementFromPoint hit-test, not just visual inspection) down to this minimal
   set, which fixes Qwen and covers every confirmed height-based spoiler case.
   Do not widen the transition-property list again without a live repro proving
   the wider set is both necessary AND doesn't break a real interactive
   component — "might help some other site" is not sufficient justification —
   that reasoning broke two real sites already (button-descendant transform
   note above HOVER-HIGHLIGHT KILLER, and the top/left/width case here).

   animation-duration/-delay ARE forced to near-zero (v1.2.0). This was reverted
   in v1.0.9 on the HYPOTHESIS that it broke rc-motion (Ant Design) dropdowns —
   that hypothesis was never verified and turned out FALSE: the real culprit was
   always the transition-property list above. Re-verified live (chat.qwen.ai,
   wintage + blanket animation-duration:0.001s): the rc-motion "+" dropdown
   opens, its menu item is hit-test clickable, page stays responsive. 0.001s
   (not 0s) is used because a genuine-but-instant animation lifecycle reliably
   fires animationstart/animationend, so animationend-driven state machines
   still advance; 0s has engine edge cases where events may not fire. Finite
   entrance/reveal animations become instant (the vintage no-motion goal).
   Infinite animations (spinners): Chromium coalesces animationiteration to at
   most one per frame, so no event flood. Snapback (base opacity:0 + reveal
   animation with no fill-mode reverting to invisible after end) only affects
   already-broken sites — a correct reveal uses fill-mode:forwards or a final
   base state — so it is not a regression this rule introduces. */
*, *::before, *::after {
  transition-property: height, max-height, min-height !important;
  transition-duration: 0.001s !important;
  transition-delay: 0s !important;
  animation-duration: 0.001s !important;
  animation-delay: 0s !important;
}
html { scroll-behavior: auto !important; }

/* 🚨 HOVER-HIGHLIGHT KILLER — CSS FREEZE LAYER (v29.1) 🚨
   Sites' own :hover paints (white flashbang rows, gray tint blocks) are killed
   two ways: (1) JS surgery strips paint props from every readable :hover rule;
   (2) this rule covers unreadable cross-origin sheets — while an element is
   hovered, any paint-property change rides a 99999s step-end transition, so it
   visually never happens; on unhover the global 0.001s duration snaps it back
   instantly. Functional hover behavior (display/visibility/opacity/transform
   for dropdown menus) is deliberately NOT in the property list, so hover-opened
   menus keep working. Our own themed controls are excluded so buttons/links
   keep their instant bevel feedback, and :active/:focus are excluded so click
   feedback on focusable elements is never frozen. */
:root body *:hover:not(button):not(a):not(input):not(select):not(textarea):not(summary):not(.btn):not([class~="button" i]):not([class~="btn" i]):not([role="button"]):not(:active):not(:focus),
:root body *:hover::before, :root body *:hover::after {
  transition-property: background-color, background-image, background-position, box-shadow, filter, backdrop-filter, color, border-color, outline-color, text-decoration-color, text-shadow !important;
  transition-duration: 99999s !important;
  transition-delay: 0s !important;
  transition-timing-function: step-end !important;
}

html { background-color: #1A0F05 !important; color: #D4B87A !important; }
body { background-color: #1E1408 !important; color: #D4B87A !important; margin: 0 !important; padding: 0 !important; }

/* 🚨 VERDANA 100% FORCED EVERYWHERE — inputs/textareas included 🚨
   Only true icon-font carriers are excluded (glyphs would turn into letters). */
*:not(svg):not(path):not(i):not([class*="icon" i]):not([class*="fa-" i]):not([class*="symbols" i]):not([class*="glyph" i]):not([class*="mdi" i]):not([class*="bi-" i]) {
  font-family: ${FONT} !important;
  -webkit-font-smoothing: none !important;
  font-smooth: never !important;
}
input, textarea, select, option, button, code, pre, kbd, samp, tt,
[class*="code" i], [class*="mono" i] { font-family: ${FONT} !important; }

a, a:visited { color: #9DD9F9 !important; text-decoration: none !important; background-color: transparent !important; }
foreignObject { mask: none !important; -webkit-mask: none !important; }
rect { rx: 0 !important; ry: 0 !important; }
svg { background: transparent !important; }
[class*="avatar" i]:not(svg):not(path), img { clip-path: none !important; }
img, video, canvas, iframe, picture { max-width: 100% !important; }
/* Ad-network iframes (Reddit/most sites' "Advertisement" slots) flash white
   in the letterbox before their creative paints. Cross-origin iframe
   CONTENTS are fundamentally outside any userscript's reach — browser
   security sandbox, not fixable — but the iframe ELEMENT's own background,
   painted by the parent page, is ours, and covers that load-flash moment.
   Scoped to known ad-serving hosts ONLY: forcing this on every iframe would
   also hit deliberately-transparent overlay iframes (chat widgets, cookie
   banners, payment forms like Stripe/Intercom/Crisp commonly cover large or
   full-page areas with a transparent iframe so the page shows through except
   their own widget) — an opaque background on those paints a solid dark
   rectangle over otherwise normal pages, a worse bug than the one it fixes. */
iframe[src*="doubleclick.net" i], iframe[src*="googlesyndication.com" i],
iframe[src*="google.com/ads" i], iframe[id*="google_ads_iframe" i],
iframe[id*="gpt_unit" i], iframe[src*="adservice.google" i],
iframe[src*="amazon-adsystem.com" i], iframe[src*="taboola.com" i],
iframe[src*="outbrain.com" i] {
  background-color: #1E1408 !important;
}
main, section, article, aside, footer, .container, .wrapper, .main, #main, #wrapper { background-color: transparent !important; }

::selection { background-color: #4A3820 !important; color: #D4B87A !important; }

header, nav, [role="navigation"], [role="banner"],
[class*="header" i]:not(h1):not(h2):not(h3):not(h4):not(h5):not(h6):not([class*="heading" i]),
[class*="navbar" i], [class*="nav-bar" i], [class*="topbar" i], [class*="top-bar" i],
[class*="toolbar" i]:not([class*="ytp" i]), [id*="header" i]:not(h1):not(h2):not(h3), [id*="navbar" i], [id*="topbar" i] {
  background-color: #2A1C0A !important; background-image: none !important; color: #D4B87A !important;
}

/* 🚨 3D BEVELED BUTTONS 🚨
   Coverage beyond real <button>: word-matched button/btn classes ([class~=]
   avoids wrappers like "button-group"), link/span role=button (div[role=button]
   stays excluded — those are the nested-wrapper glitch containers), and
   <summary> disclosure controls. */
button, input[type="button"], input[type="submit"], input[type="reset"], .btn,
[class~="button" i], [class~="btn" i], a[role="button"], span[role="button"], summary {
  background-color: #362812 !important; background-image: none !important; color: #D4B87A !important;
  ${B_OUTER}
  cursor: pointer !important; font-family: ${FONT} !important; font-size: 12px !important;
  box-sizing: border-box !important;
}
button:active, input[type="button"]:active, input[type="submit"]:active, input[type="reset"]:active, .btn:active,
[class~="button" i]:active, [class~="btn" i]:active, a[role="button"]:active, span[role="button"]:active, summary:active {
  background-color: #2A1C0A !important;
  ${B_INNER}
  transform: translate(1px, 1px) !important;
}
button:disabled, input[type="button"]:disabled, input[type="submit"]:disabled, input[type="reset"]:disabled {
  color: #7A6838 !important; background-color: #2A1C0A !important; cursor: not-allowed !important; opacity: 1 !important;
  border: 1px solid #4A3820 !important; box-shadow: none !important;
}

/* Neutralize PAINT on button pseudo-elements (underlying squares/circles)
   WITHOUT display:none — hiding them also deleted ::before icon-font glyphs,
   leaving icon-only buttons as empty bevel boxes. Content stays, paint goes.
   Ripple effects are already killed by the dedicated ripple rule below. */
button::before, button::after, .btn::before, .btn::after,
[class~="button" i]::before, [class~="button" i]::after, [class~="btn" i]::before, [class~="btn" i]::after {
  background: transparent !important; box-shadow: none !important; filter: none !important; border: none !important;
}

button:not(.ytp-button) *, input[type="button"] *, input[type="submit"] *, input[type="reset"] *,
.btn *, [class~="button" i] *, [class~="btn" i] *, a[role="button"] *, span[role="button"] * {
  background-color: transparent !important; background-image: none !important; box-shadow: none !important;
  border: none !important; text-shadow: none !important; color: inherit !important;
}

yt-icon-button, yt-button-shape, [class*="yt-spec-button-shape"] { background: transparent !important; box-shadow: none !important; border: none !important; padding: 0 !important; margin: 0 !important; }
yt-icon-button button, yt-button-shape button, .ytp-button, [class*="yt-spec-button-shape"] button, .ytd-searchbox button {
  ${B_OUTER}
  min-height: 0 !important; min-width: 0 !important; font-size: inherit !important; padding: 4px !important; margin: 0 !important;
}
.ytp-button { border: none !important; box-shadow: none !important; background: transparent !important; }

/* Inputs & Textareas (No forced padding, let JS breathe) */
input:not([type="button"]):not([type="submit"]):not([type="reset"]):not([type="checkbox"]):not([type="radio"]):not([type="range"]):not([type="color"]),
textarea, select {
  background-color: #0F0A04 !important; background-image: none !important; color: #D4B87A !important;
  ${B_SUNK}
  box-sizing: border-box !important;
}
/* accent-color is harmless even on a visually-hidden checkbox (no-op if the
   box itself never paints). appearance:auto is NOT forced here — see the JS
   process() hiddenProxy check: forcing it unconditionally would un-hide the
   real <input> underneath every accessible custom-switch component (Tailwind,
   Radix, Bootstrap .custom-switch, react-toggle — all hide the native
   checkbox via opacity:0/1px sizing and paint a sibling graphic instead),
   doubling up a native box next to the custom switch. */
input[type="checkbox"], input[type="radio"] {
  accent-color: #C0A060 !important; background-image: none !important;
}
input::placeholder, textarea::placeholder { color: #7A6838 !important; }
input:focus-visible, textarea:focus-visible, select:focus-visible, button:focus-visible, a:focus-visible {
  outline: 1px dotted #D4B87A !important; outline-offset: -2px !important;
}

table { border-collapse: collapse !important; background-color: #1E1408 !important; border-spacing: 0 !important; }
/* Solid floor on plain cells: beats forum row-highlight CSS instantly (white
   flashbang rows on JS-hover sites like RuTracker, where the highlight comes
   from a class swap that :hover surgery cannot see). Diff/code cells are
   excluded so the JS repainter can keep their semantic tint (GitHub diff
   green/red), darkened with hue preserved. */
td, th { background-image: none !important; border: 1px solid #362812 !important; color: #D4B87A !important; box-sizing: border-box !important; }
td:not([class*="blob-" i]):not([class*="diff-" i]):not([class*="hunk" i]):not([class*="addition" i]):not([class*="deletion" i]), th { background-color: #1E1408 !important; }
.row1, .row2, .bg1, .bg2 { background-image: none !important; background-color: #1E1408 !important; border: 1px solid #362812 !important; color: #D4B87A !important; }
th { background-color: #2A1C0A !important; color: #D4B87A !important; font-weight: 700 !important; }
option { background-color: #0F0A04 !important; color: #D4B87A !important; }
hr { border-color: #4A3820 !important; background-color: #4A3820 !important; color: #4A3820 !important; }

/* 🚨 HOVER STATES: ZEROED OUT v3 🚨
   Generic hover recoloring stays dead (christmas-tree problem: :hover matches the
   whole ancestor chain). Only real clickable controls keep a tactile response. */
:root body button:hover, :root body input[type="button"]:hover, :root body input[type="submit"]:hover, :root body input[type="reset"]:hover, :root body .btn:hover,
:root body [class~="button" i]:hover, :root body [class~="btn" i]:hover, :root body a[role="button"]:hover, :root body span[role="button"]:hover, :root body summary:hover {
  background-color: #3A2A15 !important; color: #D4B87A !important; filter: none !important;
  ${B_OUTER}
}
:root body a:hover { color: #9DD9F9 !important; text-decoration: underline !important; background-color: transparent !important; }

yt-interaction, paper-ripple, .mdc-ripple-surface, .mdc-ripple-upgraded::before, .mdc-ripple-upgraded::after, [class*="ripple" i] {
  display: none !important; opacity: 0 !important; visibility: hidden !important; content: none !important;
}

ytd-app, ytd-page-manager, #content.ytd-app, #page-manager.ytd-app { background-color: #1E1408 !important; }
ytd-masthead, #masthead, #masthead-container, #container.ytd-masthead, #background.ytd-masthead { background-color: #2A1C0A !important; background-image: none !important; box-shadow: 0 1px 0 #0E0803 !important; }
tp-yt-app-header-layout, tp-yt-app-header, ytd-c4-tabbed-header-renderer, ytd-page-header-renderer, #channel-header, #page-header, #header.ytd-browse { background-color: #2A1C0A !important; background-image: none !important; }
tp-yt-app-header { border-bottom: 2px solid #362812 !important; box-shadow: none !important; }

/* 🚨 POPUPS AND MENUS — v29 FIX 🚨
   v28 forced "opacity: 1 !important; z-index: 9999" onto EVERYTHING whose class
   contained menu/dropdown/popup/tooltip. Sites keep those elements rendered but
   hidden at opacity:0 — so the theme was force-REVEALING them: phantom hovercards
   overlapping Reddit posts, permanently-open dropdown panels on forums, and footer
   nav columns turned into floating 4px-shadow "windows". v29 never touches
   opacity/z-index/visibility; it only recolors. If the site hides it, it stays hidden. */
dialog, [popover],
tp-yt-iron-dropdown, ytd-popup-container, ytcp-menu, ytcp-paper-tooltip, ytcp-navigation-drawer,
[role="menu"], [role="listbox"], [role="tooltip"], [role="dialog"], [role="alertdialog"] {
  background-color: #362812 !important; background-image: none !important; border: 1px solid #0E0803 !important; box-shadow: none !important;
}
[class*="menu" i]:not(a):not(button):not([class*="item" i]):not([class*="icon" i]),
[class*="dropdown" i]:not(a):not(button), [class*="popup" i], [class*="tooltip" i],
[class*="hovercard" i], [class*="hover-card" i], faceplate-hovercard {
  background-color: #362812 !important; background-image: none !important;
}

::-webkit-scrollbar { width: 16px !important; height: 16px !important; }
::-webkit-scrollbar-track { background: #1E1408 !important; box-shadow: inset 1px 1px 0 #0E0803, inset -1px -1px 0 #4A3820 !important; }
::-webkit-scrollbar-thumb { background: #362812 !important; ${B_OUTER} }
::-webkit-scrollbar-thumb:active { background: #2A1C0A !important; ${B_INNER} }
::-webkit-scrollbar-corner { background: #1E1408 !important; }
::-webkit-scrollbar-button { background: #362812 !important; ${B_OUTER} height: 16px !important; width: 16px !important; }
`;

  // ─── SHADOW DOM MINIMAL CSS ──────────────────────────────────────────────────
  const SHADOW_CSS = `
    /* Height-only 1ms transition + near-zero animation (see GLOBAL_CSS motion
       note): transitionend/animationend keep firing for collapse + rc-motion
       state machines, without touching top/left/width/transform. */
    * { border-radius: 0 !important; transition-property: height, max-height, min-height !important; transition-duration: 0.001s !important; transition-delay: 0s !important; animation-duration: 0.001s !important; animation-delay: 0s !important; }
    /* Hover-highlight freeze, same as the global layer (see GLOBAL_CSS). */
    *:hover:not(button):not(a):not(input):not(select):not(textarea):not(summary):not(.btn):not([class~="button" i]):not([class~="btn" i]):not(shreddit-button):not([role="button"]):not(:active):not(:focus),
    *:hover::before, *:hover::after {
      transition-property: background-color, background-image, background-position, box-shadow, filter, backdrop-filter, color, border-color, outline-color, text-decoration-color, text-shadow !important;
      transition-duration: 99999s !important;
      transition-delay: 0s !important;
      transition-timing-function: step-end !important;
    }
    *:not(svg):not(path):not(i):not([class*="icon" i]):not([class*="fa-" i]):not([class*="symbols" i]):not([class*="glyph" i]):not([class*="mdi" i]):not([class*="bi-" i]) {
      font-family: ${FONT} !important; -webkit-font-smoothing: none !important; font-smooth: never !important;
    }
    input, textarea, select, option, button, code, pre, kbd, samp, tt, [class*="code" i], [class*="mono" i] { font-family: ${FONT} !important; }
    :host { --radius: 0px; --shreddit-border-radius: 0px; --md-sys-shape-corner-full: 0px; background-color: transparent !important; background-image: none !important; color: #D4B87A !important; }
    /* Ad-iframe load-flash fix, scoped to known ad hosts only — see GLOBAL_CSS note (unconditional would break transparent widget overlays) */
    iframe[src*="doubleclick.net" i], iframe[src*="googlesyndication.com" i],
    iframe[src*="google.com/ads" i], iframe[id*="google_ads_iframe" i],
    iframe[id*="gpt_unit" i], iframe[src*="adservice.google" i],
    iframe[src*="amazon-adsystem.com" i], iframe[src*="taboola.com" i],
    iframe[src*="outbrain.com" i] {
      background-color: #1E1408 !important;
    }
    div, span, section, article, aside, nav, header, footer, main, [class], [id], [role="group"], [role="toolbar"], [role="region"], [role="presentation"], [role="none"] { background-color: transparent !important; background-image: none !important; color: inherit !important; }

    /* Re-solidify floating surfaces AFTER the transparency wipe above, otherwise
       hovercards/tooltips/menus inside shadow roots render see-through and their
       text overlaps the page underneath (the Reddit hovercard bug). Recolor only —
       never force opacity/z-index/visibility. */
    dialog, [popover], [role="menu"], [role="listbox"], [role="tooltip"], [role="dialog"], [role="alertdialog"],
    [class*="menu" i]:not(a):not(button):not([class*="item" i]):not([class*="icon" i]),
    [class*="dropdown" i]:not(a):not(button), [class*="popup" i], [class*="tooltip" i],
    [class*="hovercard" i], [class*="hover-card" i], faceplate-hovercard {
      background-color: #362812 !important; background-image: none !important; color: #D4B87A !important;
    }

    button, input[type="button"], input[type="submit"], input[type="reset"], shreddit-button, .btn,
    [class~="button" i], [class~="btn" i], a[role="button"], span[role="button"], summary {
      background-color: #362812 !important; color: #D4B87A !important; ${B_OUTER}
      cursor: pointer !important; font-family: ${FONT} !important; box-sizing: border-box !important;
    }
    button:active, shreddit-button:active, .btn:active, [class~="button" i]:active, [class~="btn" i]:active, summary:active { background-color: #2A1C0A !important; ${B_INNER} transform: translate(1px, 1px) !important; }

    /* Paint-only: display:none here deleted ::before icon glyphs (see GLOBAL_CSS) */
    button::before, button::after, .btn::before, .btn::after { background: transparent !important; box-shadow: none !important; filter: none !important; }
    button * { background-color: transparent !important; box-shadow: none !important; border: none !important; }

    input:not([type="button"]):not([type="submit"]):not([type="reset"]):not([type="checkbox"]):not([type="radio"]) { background-color: #0F0A04 !important; color: #D4B87A !important; ${B_SUNK} box-sizing: border-box !important; }
    /* appearance:auto not forced here either — see GLOBAL_CSS checkbox note */
    input[type="checkbox"], input[type="radio"] { accent-color: #C0A060 !important; background-image: none !important; }

    /* Hover recolor stays zeroed out here too — only real clickable controls respond. */
    button:hover, shreddit-button:hover, .btn:hover { background-color: #3A2A15 !important; ${B_OUTER} }
    a { color: #9DD9F9 !important; text-decoration: none !important; }
    a:hover { text-decoration: underline !important; background-color: transparent !important; }
  `;

  // ─── attachShadow INTERCEPTION ───────────────────────────────────────────────
  (function interceptAttachShadow() {
    const orig = Element.prototype.attachShadow;
    Element.prototype.attachShadow = function (init) {
      const shadow = orig.call(this, init);
      try {
        if (!shadow.querySelector('style[data-w95="shadow"]')) {
          const s = document.createElement('style');
          s.setAttribute('data-w95', 'shadow');
          s.textContent = SHADOW_CSS;
          shadow.insertBefore(s, shadow.firstChild);
        }
      } catch (e) { }
      return shadow;
    };
  })();

  function injectStyle(root, id, content) {
    if (root.querySelector && root.querySelector(`style[data-w95="${id}"]`)) return;
    const s = document.createElement('style');
    s.setAttribute('data-w95', id);
    s.textContent = content;
    // At document-start <head> may not exist yet; inserting into the Document
    // node itself throws HierarchyRequestError and would kill the whole script.
    // Fall back to documentElement and never let injection abort the userscript.
    const target = root.head || root.documentElement || root;
    try { target.insertBefore(s, target.firstChild); } catch (e) {
      try { (document.head || document.documentElement).appendChild(s); } catch (e2) { }
    }
  }

  injectStyle(document, 'global', GLOBAL_CSS);

  function injectLate() {
    if (document.querySelector('style[data-w95="global-late"]')) return;
    const s = document.createElement('style');
    s.setAttribute('data-w95', 'global-late');
    s.textContent = GLOBAL_CSS;
    (document.head || document.documentElement).appendChild(s);
  }

  function parseRGB(str) {
    if (!str) return null;
    const m = str.match(/rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*[,/]\s*([\d.]+))?/);
    if (!m) return null;
    return { r: +m[1], g: +m[2], b: +m[3], a: m[4] !== undefined ? parseFloat(m[4]) : 1 };
  }
  function lum({ r, g, b }) {
    const lin = v => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4); };
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
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
  function flushWrites(w) {
    for (let i = 0; i < w.length; i += 3) setImp(w[i], w[i + 1], w[i + 2]);
    w.length = 0;
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
      shadowObserver.observe(host.shadowRoot, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['class', 'bgcolor', 'background']
      });
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
    if (shouldSkip(el)) return;

    el.removeAttribute('background');
    el.removeAttribute('bgcolor');

    const cs = window.getComputedStyle(el);

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

    const bgImg = cs.backgroundImage;
    if (bgImg && bgImg !== 'none') {
      // Computed gradients serialize colors as rgb(); any gradient stop with all
      // channels >= 200 is a light surface. radial/conic covered too.
      if (/(linear|radial|conic)-gradient.*(white|#fff|2\d\d,\s*2\d\d,\s*2\d\d)/i.test(bgImg)) {
        w.push(el, 'background', 'transparent', el, 'background-image', 'none');
      }
    }

    const bgColor = cs.backgroundColor;
    if (bgColor && bgColor !== 'transparent') {
      const bg = parseRGB(bgColor);
      if (bg && bg.a > 0.08) {
        const L = lum(bg);
        const grayish = Math.max(bg.r, bg.g, bg.b) - Math.min(bg.r, bg.g, bg.b) <= 24;
        let repaint = null;
        if (L > 0.45) {
          // Light flashbang surface: low-alpha white tints go fully transparent
          // (the "gray rectangle blocks"), neutral solids go dark brown, and
          // SATURATED light tints (GitHub diff green/red, warning yellows,
          // highlight rows) are darkened with their hue preserved so semantic
          // colors survive the dark theme instead of being flattened.
          if (bg.a <= 0.35) repaint = 'transparent';
          else if (grayish) repaint = '#1E1408';
          else repaint = 'rgb(' + Math.round(bg.r * 0.18) + ', ' + Math.round(bg.g * 0.18) + ', ' + Math.round(bg.b * 0.18) + ')';
        } else if (grayish && L >= 0.015) {
          // Unthemed dark-mode grays (chips, tabs, cards) → vintage brown scale.
          // Near-black (< 0.015, e.g. video players, scrims) is left alone.
          repaint = L >= 0.13 ? '#3A2A15' : L >= 0.05 ? '#362812' : '#2A1C0A';
        }
        if (repaint) {
          w.push(el, 'background', repaint, el, 'background-color', repaint, el, 'background-image', 'none');
        }
      }
    }

    const fgColor = cs.color;
    if (fgColor) {
      const fg = parseRGB(fgColor);
      if (fg && fg.a > 0.1) {
        const fgLum = lum(fg);
        const darkBg = 0.008; // luminance of #1E1408 backdrop
        const contrast = (Math.max(fgLum, darkBg) + 0.05) / (Math.min(fgLum, darkBg) + 0.05);
        const grayish = Math.max(fg.r, fg.g, fg.b) - Math.min(fg.r, fg.g, fg.b) <= 40;
        
        if (el.closest && el.closest('a')) {
          if (contrast < 4.5 || (fgLum > 0.4 && grayish)) w.push(el, 'color', '#9DD9F9');
        } else {
          if (contrast < 4.5) {
            w.push(el, 'color', '#D4B87A');
          } else if (grayish) {
            if (fgLum > 0.4) w.push(el, 'color', '#D4B87A');
            else if (fgLum > 0.15) w.push(el, 'color', '#B09558');
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
        if (grayish && lum(bc) > 0.18) {
          w.push(el, 'border-' + s.toLowerCase() + '-color', '#362812');
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
  function onMutations(mutations) {
    for (let i = 0; i < mutations.length; i++) pendingMuts.push(mutations[i]);
    if (debounceTimer) return;
    debounceTimer = setTimeout(() => {
      debounceTimer = null;
      const batch = pendingMuts;
      pendingMuts = [];
      const w = [];
      const added = [];
      for (const m of batch) {
        // Class/bgcolor changes restyle existing elements (SPA hydration, lazy
        // CSS-in-JS) — re-process them or they keep stale baked-in colors.
        // Hover-chain elements are skipped inside process() and retried later,
        // so hover class-toggles don't bake in highlight colors.
        if (m.type === 'attributes') {
          const t = m.target;
          if (t && t.nodeType === 1) {
            // Cooldown: carousels/virtual scrollers toggle classes many times a
            // second; re-processing each toggle (computed-style read + writes)
            // is a jank source. During the cooldown just mark the element dirty
            // — the next light sweep (≤1.5s) picks up its settled state.
            const now = Date.now();
            if ((attrCooldown.get(t) || 0) + 500 > now) {
              t.removeAttribute('data-w95-done');
            } else {
              attrCooldown.set(t, now);
              t.removeAttribute('data-w95-done');
              process(t, false, w);
            }
          }
          continue;
        }
        for (const node of m.addedNodes) {
          if (node.nodeType !== 1) continue;
          added.push(node);
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
          const kids = node.getElementsByTagName('*');
          for (let i = 0; i < kids.length; i++) {
            kids[i].removeAttribute && kids[i].removeAttribute('data-w95-done');
            process(kids[i], false, w);
          }
        }
        // New DOM arrived, so late CSS may still be settling on it: this is the
        // one signal that earns a force re-verify. Attribute churn deliberately
        // does NOT request one — an animating spinner toggling classes must not
        // keep the expensive pass alive forever (that was half the idle burn).
        requestForceSweep();
      }
      flushWrites(w);
    }, 60);
  }

  const mainObserver = new MutationObserver(onMutations);
  const shadowObserver = new MutationObserver(onMutations);

  if (document.documentElement) {
    mainObserver.observe(document.documentElement, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['class', 'bgcolor', 'background']
    });
  }

  // Force passes are budgeted: on huge pages (endless feeds) each pass
  // re-verifies a rotating 2500-element window instead of the whole DOM, so a
  // single pass never janks the main thread; full coverage arrives over a few
  // rotations.
  const FORCE_BUDGET = 2500;
  let forceCursor = 0;

  // 🚨 FORCE SWEEPS ARE NOW DEMAND-DRIVEN, NOT UNCONDITIONAL (v1.3.0) 🚨
  // They used to fire every 3rd tick (~4.5s) forever, whether or not the page
  // had changed since the last one — so a fully settled, idle page kept paying
  // for a 2500-element re-verify until the tab closed. That is the permanent
  // idle CPU the user actually feels. Light sweeps are genuinely cheap and stay
  // unconditional (measured: 0.7ms on a settled 16921-element page, because
  // '*:not([data-w95-done])' matches nothing), so nothing is lost by gating the
  // expensive pass on real activity: new DOM nodes, a changed stylesheet, or a
  // return to a hidden tab. Each request buys enough budgeted rotations to cover
  // the document ONCE — otherwise the rotating cursor would never finish a lap
  // on a big page and elements past the first 2500 would never be re-verified.
  let forcePassesOwed = 0;
  function requestForceSweep() {
    let n = 1;
    try { n = Math.ceil((document.getElementsByTagName('*').length || 1) / FORCE_BUDGET); } catch (e) { }
    // Cap the debt: a 60k-element page must not queue 24 heavy passes back to
    // back if mutations keep arriving before the lap finishes.
    if (n > 8) n = 8;
    if (n > forcePassesOwed) forcePassesOwed = n;
  }

  function runSweeper(force) {
    // Prune shadow roots whose hosts left the DOM (SPA navigations) — keeping
    // them leaks memory and bloats every sweep on long sessions.
    piercedRoots.forEach(root => { try { if (!root.host || !root.host.isConnected) piercedRoots.delete(root); } catch (e) { } });
    if (stripHoverSheets(document)) requestForceSweep();
    piercedRoots.forEach(root => { try { if (stripHoverSheets(root)) requestForceSweep(); } catch (e) { } });
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
  }

  // Elements processed before the site's CSS finished loading bake in unstyled
  // values and would otherwise stay wrong forever (white surfaces that "heal"
  // only when the SPA happens to re-render them). Full re-verify passes
  // (force=true) re-check EVERY element: at DOMContentLoaded, again 1s later
  // once late CSS settled, then on demand whenever requestForceSweep() fires.
  // The write-if-changed guard in setImp keeps repeat passes cheap.
  let sweepCount = 0;
  function startSweeping() {
    injectLate();
    // The boot pass measured ONE 716ms long task on a 16921-element page, right
    // when the site's own init scripts are competing for the main thread — the
    // "have to reload a couple of times before it comes up" symptom. The
    // read/write split above is what actually shrinks it; deferring the second
    // pass past load keeps it out of the critical window as well.
    requestForceSweep();
    runSweeper(true);
    setTimeout(() => { requestForceSweep(); runSweeper(true); }, 1000);

    if (!IS_TOP) {
      // Sub-frame: bounded settling passes, then nothing. The MutationObserver
      // stays live, so a late-loading embed still gets themed — that path is
      // event-driven and costs zero while idle. What a frame must NOT own is a
      // forever-ticking interval; multiplied by an ad-heavy page's frame count
      // that was pure background burn on content the user often never sees.
      setTimeout(() => { requestForceSweep(); runSweeper(true); }, 3000);
      return;
    }

    // Top frame: cheap light sweep every 1.5s (0.7ms on a settled page — it only
    // touches elements missing data-w95-done), and the expensive force pass only
    // when requestForceSweep() has been called since the last one.
    setInterval(() => {
      if (document.hidden) return; // background tab: nothing visible, nothing to fix
      sweepCount++;
      const force = forcePassesOwed > 0 && sweepCount % 3 === 0;
      if (force) forcePassesOwed--;
      runSweeper(force);
    }, 1500);

    // Slow self-healing heartbeat. The demand-driven gate above covers new DOM,
    // attribute churn and new stylesheets — but NOT a site mutating an existing
    // element's own `style` attribute (custom properties, inline recolors).
    // `style` cannot be added to the observer's attributeFilter: setImp writes
    // inline styles, so the observer would fire on its own output and spin. The
    // old blind 4.5s force pass healed that case by accident, and dropping it
    // outright would be a real regression — so it is kept, just 20x rarer. One
    // lap costs ~7 budgeted passes at ~30ms on a 17k-element page, i.e. well
    // under 1% averaged, against the 16.9% the 4.5s version measured.
    setInterval(() => { if (!document.hidden) requestForceSweep(); }, 30000);

    // Pages that finished loading while the tab was hidden got no sweeps; on
    // return, re-verify immediately so the user never sees stale white.
    document.addEventListener('visibilitychange', () => {
      if (!document.hidden) { requestForceSweep(); runSweeper(true); }
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', startSweeping, { once: true });
  } else {
    startSweeping();
  }

})();
