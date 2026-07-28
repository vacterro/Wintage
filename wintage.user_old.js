// ==UserScript==
// @name         Wintage — Win95 Dark Golden Vintage Theme
// @namespace    https://github.com/vacterro/Wintage
// @version      1.4.7
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
  // Literal hex here, not T.* — this runs before the token table is declared, and
  // it must stay the very first thing that happens so nothing white ever paints.
  document.documentElement.style.setProperty('background-color', '#1A0F05', 'important');
  document.documentElement.style.setProperty('color', '#D4B87A', 'important');
  document.documentElement.setAttribute('data-w95-dark', '1');

  // ─── UI.md TOKENS — THE COMPLETE PALETTE, NOTHING OUTSIDE IT ────────────────
  // UI.md iron law 5: "Every visible color must trace back to the palette."
  // These are the only colours this file is allowed to emit. If a value below
  // does not appear in UI.md's token block, it is a bug.
  const T = {
    background: '#1A0F05', backgroundSoft: '#1E1408',
    surface: '#2A1C0A', surfaceRaised: '#362812', surfaceAlt: '#3A2A15',
    borderDark: '#0E0803', borderHighlight: '#C0A060', borderMuted: '#4A3820',
    textPrimary: '#D4B87A', textSecondary: '#B09558', textMuted: '#7A6838',
    accentTeal: '#008080', accentTealDeep: '#004C4C',
    success: '#4A7A20', warning: '#7A7A20', danger: '#7A2020',
    selection: '#362812', compareBack: '#0F0A04'
  };

  // Stamped as data-w95-ver on every injected <style>, so a console diagnostic can
  // report which build is actually live. Without it, "is this 1.4.2 or 1.4.3?"
  // costs a round trip to the Tampermonkey dashboard — and a stale install
  // silently invalidates whatever measurement is being taken, which already
  // wasted one full diagnostic round on a page where the script wasn't running.
  // Declared up here, not next to injectStyle: the attachShadow interception
  // reads it too and is installed earlier in the file.
  const W95_VERSION = '1.4.7';

  // Verdana forced 100% everywhere. Verdana_m1 = locally installed modified Verdana.
  const FONT = 'Verdana_m1, Verdana, Tahoma, "MS Sans Serif", sans-serif';

  // ─── STRUCTURAL BEVEL CONSTANTS — 2px, BORDERS ONLY, NO SHADOW ─────────────
  // UI.md law 3: "Depth is 2px bevel only." UI.md law 2: "zero shadow."
  // The pre-1.4.0 bevel was 1px borders PLUS an inset box-shadow to fake the
  // second bevel row — which broke both laws at once and, more practically, made
  // every site's depth read slightly differently depending on whether its own CSS
  // also set a box-shadow we happened to lose the specificity fight over. UI.md
  // spells the correct form out literally, as a 4-value border-color shorthand
  // (top right bottom left), so that is what is used verbatim here.
  const B_OUTER = `border: 2px solid !important; border-color: ${T.borderHighlight} ${T.borderDark} ${T.borderDark} ${T.borderHighlight} !important; box-shadow: none !important;`;
  const B_INNER = `border: 2px solid !important; border-color: ${T.borderDark} ${T.borderHighlight} ${T.borderHighlight} ${T.borderDark} !important; box-shadow: none !important;`;
  const B_SUNK = B_INNER;

  // ═══════════════════════════════════════════════════════════════════════════════
  // GLOBAL CSS — v29.0
  // ═══════════════════════════════════════════════════════════════════════════════
  const GLOBAL_CSS = `
:root {
  color-scheme: dark !important;
  /* UI.md token block, verbatim names — the single source of colour truth. */
  --background: ${T.background}; --backgroundSoft: ${T.backgroundSoft};
  --surface: ${T.surface}; --surfaceRaised: ${T.surfaceRaised}; --surfaceAlt: ${T.surfaceAlt};
  --borderDark: ${T.borderDark}; --borderHighlight: ${T.borderHighlight}; --borderMuted: ${T.borderMuted};
  --textPrimary: ${T.textPrimary}; --textSecondary: ${T.textSecondary}; --textMuted: ${T.textMuted};
  --accentTeal: ${T.accentTeal}; --accentTealDeep: ${T.accentTealDeep};
  --success: ${T.success}; --warning: ${T.warning}; --danger: ${T.danger};
  --selection: ${T.selection}; --compareBack: ${T.compareBack};
  --radius: 0px; --radius-none: 0px; --radius-2xs: 0px; --radius-xs: 0px; --radius-sm: 0px;
  --radius-md: 0px; --radius-lg: 0px;  --radius-xl: 0px; --radius-2xl: 0px;
  --radius-full: 0px; --radius-round: 0px; --radius-pill: 0px; --radius-circle: 0px;
  --border-radius: 0px; --border-radius-full: 0px; --border-radius-pill: 0px;
  --bs-border-radius: 0px; --bs-border-radius-pill: 0px;
  --mdc-shape-small: 0px; --md-sys-shape-corner-full: 0px;
  --shreddit-border-radius: 0px; --post-action-border-radius: 0px;
  --yt-border-radius: 0px; --ytd-searchbox-border-radius: 0px;
}

/* 🚨 STRICT RADIUS KILLER, NO GLOBAL BOX-SIZING TO PREVENT FLEX BREAKS 🚨
   No global 'margin: 0' and no global 'box-sizing: border-box' either, both of
   which UI.md's base CSS does specify — see the deviations note in
   .saipen/KNOWLEDGE/ADR-003.md. That block is written for BUILDING a saipen
   screen from scratch, where the author controls every margin. Retrofitted onto
   arbitrary sites, 'margin: 0' collapses every paragraph, list and heading gap
   into one unreadable wall of text, which fails UI.md's own "text must never
   feel jammed" and "screenshot legibility" requirements. Global box-sizing was
   already tried and reverted here for breaking flex layouts. */
* { border-radius: 0 !important; }

/* 🚨 ZERO SHADOW, ZERO BLUR (UI.md law 2) 🚨
   This is the rule that does the most work for "every site should look the
   same": modern sites carry their entire visual identity in elevation shadows,
   glows, focus rings and backdrop blur. Flattening all of it leaves nothing but
   the 2px bevel language to express depth, which is the point.
   - box-shadow/text-shadow: killed outright. Our own bevels are pure borders
     now (see B_OUTER/B_INNER) so nothing of ours is lost. Sites that draw a
     BORDER via 'box-shadow: 0 0 0 1px' do lose that line — acceptable, since
     surfaces are separated by token background steps instead, and a focus ring
     is re-provided as an outline below.
   - backdrop-filter: pure decoration (frosted glass), always safe to remove.
   - filter: killed on layout elements only. NOT on img/svg/video/canvas — sites
     legitimately use filter to recolour icons and correct media, and a blanket
     kill leaves white-on-white icons invisible. */
*, *::before, *::after {
  box-shadow: none !important;
  text-shadow: none !important;
  backdrop-filter: none !important;
  -webkit-backdrop-filter: none !important;
}
*:not(img):not(svg):not(video):not(canvas):not(picture):not(image), *::before, *::after {
  filter: none !important;
}

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

html { background-color: ${T.background} !important; color: ${T.textPrimary} !important; }
body { background-color: ${T.backgroundSoft} !important; color: ${T.textPrimary} !important; margin: 0 !important; padding: 0 !important; }

/* 🚨 VERDANA 100% FORCED EVERYWHERE — inputs/textareas included 🚨
   Only true icon-font carriers are excluded (glyphs would turn into letters). */
*:not(svg):not(path):not(i):not([class*="icon" i]):not([class*="fa-" i]):not([class*="symbols" i]):not([class*="glyph" i]):not([class*="mdi" i]):not([class*="bi-" i]) {
  font-family: ${FONT} !important;
  -webkit-font-smoothing: none !important;
  -moz-osx-font-smoothing: unset !important;
  font-smooth: never !important;
  text-rendering: optimizeSpeed !important;
}
input, textarea, select, option, button, code, pre, kbd, samp, tt,
[class*="code" i], [class*="mono" i] { font-family: ${FONT} !important; }

/* 🚨 TYPE LADDER — UI.md allows 10/11/12/14/16px AND NOTHING ELSE 🚨
   Second-biggest "all sites look identical" lever after the bevels: a site's
   typographic voice is mostly its size scale, so replacing every site's scale
   with the same five-step one is most of the uniformity.
   Mapped by UI.md's own stated roles, not by blind quantisation: 12px body,
   14px section headers, 16px reserved for the main page title, 10px for
   secondary metadata. h2..h6 all collapse to 14 because UI.md recognises exactly
   one "section header" size — six distinct heading sizes is a hierarchy UI.md
   does not have.
   Icon-font carriers are excluded: their font-size IS their glyph size, and
   forcing 12px there shrinks or inflates every icon on the page.
   line-height 1.2 comes from UI.md's base CSS and is what keeps the smaller
   text from reading as jammed.

   The exception tags are carved OUT of the base selector rather than layered on
   top of it, because the base selector's six ':not([class*="…" i])' attribute
   matches give it specificity (0,6,4) — a plain 'h1 { font-size: 16px }' is
   (0,0,1) and loses outright even with !important on both, which is exactly how
   the first cut of this rule silently flattened every heading to 12px. Disjoint
   selectors sidestep the specificity race entirely instead of trying to win it.

   10px is keyed to REAL TAGS only (small/sub/sup/figcaption), never to class
   names. Guessing "this is metadata" from a substring is the same over-reach
   rejected for the status colours above: '[class*="meta" i]' also matches a
   '.pagemeta' wrapper full of body copy, and shrinking that to 10px is worse
   than leaving it at 12px. */
*:not(svg):not(path):not(i):not(html):not(h1):not(h2):not(h3):not(h4):not(h5):not(h6):not(small):not(sub):not(sup):not(figcaption):not([class*="icon" i]):not([class*="fa-" i]):not([class*="symbols" i]):not([class*="glyph" i]):not([class*="mdi" i]):not([class*="bi-" i]) {
  font-size: 12px !important;
  line-height: 1.2 !important;
}
h1 { font-size: 16px !important; line-height: 1.2 !important; }
h2, h3, h4, h5, h6 { font-size: 14px !important; line-height: 1.2 !important; }
small, sub, sup, figcaption { font-size: 10px !important; line-height: 1.2 !important; }

/* Weight sparingly (UI.md typography): sites reach for 200/300 hairlines and
   800/900 blacks, both of which read as noise at 12px non-antialiased. Two
   weights only — normal, and bold where the site meant emphasis.
   The exceptions carry a ':root' prefix for the same specificity reason as
   above: '*:not(svg):not(path)' is (0,0,2) and a bare 'b' is (0,0,1), so without
   the prefix the base rule wins and NOTHING on the page is ever bold. ':root b'
   is (0,1,1) and wins cleanly — no attribute matches involved here, so the cheap
   fix works where font-size needed disjointness. */
*:not(svg):not(path) { font-weight: 400 !important; font-style: normal !important; }
:root b, :root strong, :root th, :root h1, :root h2, :root h3, :root h4, :root h5, :root h6,
:root summary, :root legend, :root label, :root button, :root [role="button"], :root .btn,
:root [class~="button" i], :root [class~="btn" i] { font-weight: 700 !important; }
:root i, :root em, :root cite, :root var, :root address, :root dfn, :root q, :root blockquote { font-style: italic !important; }

/* UI.md law 5 + the accessibility floor, together. The old link colour #9DD9F9
   traced to no token at all — an iron-law-5 violation on the single most common
   coloured element on the web. --accentTeal is the palette's accent, but #008080
   on #1A0F05 measures 3.7:1, under the WCAG AA 4.5:1 that UI.md also requires,
   so it is NOT usable as link TEXT. --borderHighlight #C0A060 measures 7.8:1, is
   a real token, and stays clearly distinct from --textPrimary body text. Visited
   uses --textSecondary (6.2:1); --textMuted was rejected at 3.3:1 for the same
   AA reason. */
a, a:link { color: ${T.borderHighlight} !important; text-decoration: none !important; background-color: transparent !important; }
a:visited { color: ${T.textSecondary} !important; }
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
  background-color: ${T.backgroundSoft} !important;
}
main, section, article, aside, footer, .container, .wrapper, .main, #main, #wrapper { background-color: transparent !important; }

::selection { background-color: ${T.selection} !important; color: ${T.textPrimary} !important; }

/* Site chrome reads as a Win95 title-bar strip: --surface, 20px per UI.md's
   window rules. Height is a MIN, not a fixed height — a real site header carries
   a search field and a row of controls, and clamping it to 20px would overlap
   them. UI.md's 20px is the floor that keeps the strip from being thinner than
   the controls inside it. */
header, nav, [role="navigation"], [role="banner"],
[class*="header" i]:not(h1):not(h2):not(h3):not(h4):not(h5):not(h6):not([class*="heading" i]),
[class*="navbar" i], [class*="nav-bar" i], [class*="topbar" i], [class*="top-bar" i],
[class*="toolbar" i]:not([class*="ytp" i]), [id*="header" i]:not(h1):not(h2):not(h3), [id*="navbar" i], [id*="topbar" i] {
  background-color: ${T.surface} !important; background-image: none !important; color: ${T.textPrimary} !important;
  min-height: 20px !important;
}

/* 🚨 3D BEVELED BUTTONS 🚨
   Coverage beyond real <button>: word-matched button/btn classes ([class~=]
   avoids wrappers like "button-group"), link/span role=button (div[role=button]
   stays excluded — those are the nested-wrapper glitch containers), and
   <summary> disclosure controls. */
button, input[type="button"], input[type="submit"], input[type="reset"], .btn,
[class~="button" i], [class~="btn" i], a[role="button"], span[role="button"], summary {
  background-color: ${T.surfaceRaised} !important; background-image: none !important; color: ${T.textPrimary} !important;
  ${B_OUTER}
  cursor: pointer !important; font-family: ${FONT} !important; font-size: 12px !important;
  box-sizing: border-box !important;
  /* UI.md button metrics + accessibility floor (primary targets >= 24px). Both
     are minimums, never fixed sizes: a site's own wider button keeps its width,
     it just can never be smaller than a reachable target. */
  padding: 2px 6px !important; min-width: 24px !important; min-height: 20px !important;
}
button:active, input[type="button"]:active, input[type="submit"]:active, input[type="reset"]:active, .btn:active,
[class~="button" i]:active, [class~="btn" i]:active, a[role="button"]:active, span[role="button"]:active, summary:active {
  background-color: ${T.surface} !important;
  ${B_INNER}
  /* The ONE sanctioned movement in the entire theme (UI.md predictability §9):
     instant 1px physical feedback for a press the user themselves caused. */
  transform: translate(1px, 1px) !important;
}
/* Disabled: quieter LABEL only. UI.md forbids 'opacity' here twice over — iron
   law 2 bans transparency, and a faded control fails the accessibility floor and
   disappears in screenshots. So the raised bevel and the surface both stay
   exactly as they are; only the text drops to --textMuted, which is the single
   visual difference between enabled and disabled. */
button:disabled, input[type="button"]:disabled, input[type="submit"]:disabled, input[type="reset"]:disabled,
button[aria-disabled="true"], [role="button"][aria-disabled="true"] {
  color: ${T.textMuted} !important; background-color: ${T.surfaceRaised} !important;
  cursor: not-allowed !important; opacity: 1 !important;
  ${B_OUTER}
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

/* 🚨 INPUTS — ALWAYS SUNKEN, --compareBack, 20px (UI.md component rules) 🚨
   Height/padding ARE forced on single-line fields: a site's 48px pill search bar
   is the most recognisable piece of its identity, so leaving those alone would
   defeat the whole point. 'height' (not min-height) is deliberate here, unlike
   buttons — UI.md states one input height and inputs are the control most likely
   to be inflated by a site. Cost: absolutely-positioned adornment icons inside a
   site's own search widget can end up vertically off-centre. That is cosmetic
   misalignment inside one widget, traded for every field on the web being the
   same field. Textareas are exempt (they get UI.md's own min-height instead). */
input:not([type="button"]):not([type="submit"]):not([type="reset"]):not([type="checkbox"]):not([type="radio"]):not([type="range"]):not([type="color"]):not([type="file"]),
select {
  height: 20px !important; padding: 1px 3px !important;
}
input:not([type="button"]):not([type="submit"]):not([type="reset"]):not([type="checkbox"]):not([type="radio"]):not([type="range"]):not([type="color"]),
textarea, select {
  background-color: ${T.compareBack} !important; background-image: none !important; color: ${T.textPrimary} !important;
  ${B_SUNK}
  box-sizing: border-box !important;
}
textarea { min-height: 64px !important; resize: none !important; padding: 1px 3px !important; }
/* accent-color is harmless even on a visually-hidden checkbox (no-op if the
   box itself never paints). appearance:auto is NOT forced here — see the JS
   process() hiddenProxy check: forcing it unconditionally would un-hide the
   real <input> underneath every accessible custom-switch component (Tailwind,
   Radix, Bootstrap .custom-switch, react-toggle — all hide the native
   checkbox via opacity:0/1px sizing and paint a sibling graphic instead),
   doubling up a native box next to the custom switch. */
input[type="checkbox"], input[type="radio"] {
  accent-color: ${T.borderHighlight} !important; background-image: none !important;
}
input::placeholder, textarea::placeholder { color: ${T.textMuted} !important; }
/* Focus must be visible on EVERY control (accessibility floor) and instant. The
   global box-shadow kill above removes the ring modern sites draw with
   box-shadow, so this outline is now the only focus affordance there is — the
   old input/textarea/select/button/a list was too narrow once that ring was gone. */
input:focus-visible, textarea:focus-visible, select:focus-visible, button:focus-visible, a:focus-visible,
summary:focus-visible, [tabindex]:focus-visible, [role="button"]:focus-visible, [contenteditable]:focus-visible {
  outline: 1px dotted ${T.textPrimary} !important; outline-offset: -4px !important;
}

table { border-collapse: collapse !important; background-color: ${T.backgroundSoft} !important; border-spacing: 0 !important; }
/* Solid floor on plain cells: beats forum row-highlight CSS instantly (white
   flashbang rows on JS-hover sites like RuTracker, where the highlight comes
   from a class swap that :hover surgery cannot see). Diff/code cells are
   excluded so the JS repainter can keep their semantic tint (GitHub diff
   green/red), darkened with hue preserved. */
td, th { background-image: none !important; border: 1px solid ${T.surfaceRaised} !important; color: ${T.textPrimary} !important; box-sizing: border-box !important; }
td:not([class*="blob-" i]):not([class*="diff-" i]):not([class*="hunk" i]):not([class*="addition" i]):not([class*="deletion" i]), th { background-color: ${T.backgroundSoft} !important; }
.row1, .row2, .bg1, .bg2 { background-image: none !important; background-color: ${T.backgroundSoft} !important; border: 1px solid ${T.surfaceRaised} !important; color: ${T.textPrimary} !important; }
/* Table headers are RAISED (UI.md tables/lists) — same 2px bevel language as
   buttons, so a header cell reads as a pressable column control the way it did
   in Win95's list views. */
th { background-color: ${T.surface} !important; color: ${T.textPrimary} !important; font-weight: 700 !important; ${B_OUTER} }
/* Selected row: --selection with a sunken feel (UI.md). Kept distinct from the
   focus outline above, which the accessibility floor requires. */
tr[aria-selected="true"] > td, tr[aria-selected="true"] > th, tr.selected > td,
li[aria-selected="true"], [role="option"][aria-selected="true"],
[role="row"][aria-selected="true"], [role="treeitem"][aria-selected="true"] {
  background-color: ${T.selection} !important; color: ${T.textPrimary} !important; ${B_INNER}
}
option { background-color: ${T.compareBack} !important; color: ${T.textPrimary} !important; }
hr { border: none !important; border-top: 2px solid ${T.borderMuted} !important; background-color: transparent !important; color: ${T.borderMuted} !important; height: 0 !important; }

/* Status colours (--success/--warning/--danger) are deliberately NOT applied by
   class-name substring here. '[class*="error" i]' matches 'error-boundary',
   '[class*="valid" i]' matches 'validation-container' — both are large wrappers,
   and painting one solid red or green is exactly the "might help some other site"
   over-reach that already broke two real sites in this file's history (see the
   transition-property note above). Semantic snapping happens in the JS repainter
   instead, gated on the site having ALREADY painted a saturated green/amber/red
   background — i.e. on evidence, not on a name. */

/* 🚨 HOVER STATES: ZEROED OUT v3 🚨
   Generic hover recoloring stays dead (christmas-tree problem: :hover matches the
   whole ancestor chain). Only real clickable controls keep a tactile response. */
:root body button:hover, :root body input[type="button"]:hover, :root body input[type="submit"]:hover, :root body input[type="reset"]:hover, :root body .btn:hover,
:root body [class~="button" i]:hover, :root body [class~="btn" i]:hover, :root body a[role="button"]:hover, :root body span[role="button"]:hover, :root body summary:hover {
  background-color: ${T.surfaceAlt} !important; color: ${T.textPrimary} !important; filter: none !important;
  ${B_OUTER}
}
/* Underline on hover, not on every link: UI.md bans decoration without function,
   and underlining every nav item, card title and icon link on a modern page is
   noise, not clarity. Colour (--borderHighlight vs --textPrimary body text)
   carries the "this is a link" signal on its own, so no control depends on hover
   alone — the hover underline is confirmation, not the only affordance. */
:root body a:hover { color: ${T.borderHighlight} !important; text-decoration: underline !important; background-color: transparent !important; }

yt-interaction, paper-ripple, .mdc-ripple-surface, .mdc-ripple-upgraded::before, .mdc-ripple-upgraded::after, [class*="ripple" i] {
  display: none !important; opacity: 0 !important; visibility: hidden !important; content: none !important;
}

ytd-app, ytd-page-manager, #content.ytd-app, #page-manager.ytd-app { background-color: ${T.backgroundSoft} !important; }
/* The masthead separator was a box-shadow, which the global zero-shadow rule now
   removes — re-expressed as a real border so the strip keeps its bottom edge. */
ytd-masthead, #masthead, #masthead-container, #container.ytd-masthead, #background.ytd-masthead { background-color: ${T.surface} !important; background-image: none !important; border-bottom: 2px solid ${T.borderDark} !important; }
tp-yt-app-header-layout, tp-yt-app-header, ytd-c4-tabbed-header-renderer, ytd-page-header-renderer, #channel-header, #page-header, #header.ytd-browse { background-color: ${T.surface} !important; background-image: none !important; }
tp-yt-app-header { border-bottom: 2px solid ${T.surfaceRaised} !important; }

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
  /* Dialog bodies use --surfaceRaised and a RAISED bevel (UI.md windows and
     dialogs) — a floating panel is the most window-like thing on a web page, so
     it gets the full Win95 window edge instead of the old flat 1px outline. */
  background-color: ${T.surfaceRaised} !important; background-image: none !important;
  ${B_OUTER}
}
[class*="menu" i]:not(a):not(button):not([class*="item" i]):not([class*="icon" i]),
[class*="dropdown" i]:not(a):not(button), [class*="popup" i], [class*="tooltip" i],
[class*="hovercard" i], [class*="hover-card" i], faceplate-hovercard {
  background-color: ${T.surfaceRaised} !important; background-image: none !important;
}

/* Scrollbars: the track's sunken look came from inset box-shadows, which the
   global zero-shadow rule removes — rebuilt out of 2px bevel borders so the
   depth language is identical to every other control. */
::-webkit-scrollbar { width: 16px !important; height: 16px !important; }
::-webkit-scrollbar-track { background: ${T.backgroundSoft} !important; ${B_INNER} }
::-webkit-scrollbar-thumb { background: ${T.surfaceRaised} !important; ${B_OUTER} }
::-webkit-scrollbar-thumb:active { background: ${T.surface} !important; ${B_INNER} }
::-webkit-scrollbar-corner { background: ${T.backgroundSoft} !important; }
::-webkit-scrollbar-button { background: ${T.surfaceRaised} !important; ${B_OUTER} height: 16px !important; width: 16px !important; }
`;

  // ─── SHADOW DOM MINIMAL CSS ──────────────────────────────────────────────────
  const SHADOW_CSS = `
    /* Height-only 1ms transition + near-zero animation (see GLOBAL_CSS motion
       note): transitionend/animationend keep firing for collapse + rc-motion
       state machines, without touching top/left/width/transform. */
    * { border-radius: 0 !important; transition-property: height, max-height, min-height !important; transition-duration: 0.001s !important; transition-delay: 0s !important; animation-duration: 0.001s !important; animation-delay: 0s !important; }
    /* Zero shadow / zero blur, same as the global layer (UI.md law 2). Shadow
       roots are where modern component libraries keep their elevation, so
       skipping this here would leave every web-component card floating while the
       rest of the page is flat. */
    *, *::before, *::after { box-shadow: none !important; text-shadow: none !important; backdrop-filter: none !important; -webkit-backdrop-filter: none !important; }
    *:not(img):not(svg):not(video):not(canvas):not(picture):not(image), *::before, *::after { filter: none !important; }
    /* Type ladder, same five steps and the same disjoint-selector trick as the
       global layer (see the specificity note there — layering the exceptions on
       top instead silently flattens every heading to 12px). */
    *:not(svg):not(path):not(i):not(h1):not(h2):not(h3):not(h4):not(h5):not(h6):not(small):not(sub):not(sup):not(figcaption):not([class*="icon" i]):not([class*="fa-" i]):not([class*="symbols" i]):not([class*="glyph" i]):not([class*="mdi" i]):not([class*="bi-" i]) {
      font-size: 12px !important; line-height: 1.2 !important;
    }
    h1 { font-size: 16px !important; line-height: 1.2 !important; }
    h2, h3, h4, h5, h6 { font-size: 14px !important; line-height: 1.2 !important; }
    small, sub, sup, figcaption { font-size: 10px !important; line-height: 1.2 !important; }
    *:not(svg):not(path) { font-weight: 400 !important; font-style: normal !important; }
    /* ':host X' matches X inside this shadow tree and scores (0,1,1), beating the
       (0,0,2) base rule above — the same specificity fix the global layer makes
       with ':root'. A bare 'b' here would lose and nothing would be bold. */
    :host b, :host strong, :host th, :host h1, :host h2, :host h3, :host h4, :host h5, :host h6,
    :host summary, :host legend, :host label, :host button, :host shreddit-button, :host [role="button"],
    :host .btn, :host [class~="button" i], :host [class~="btn" i] { font-weight: 700 !important; }
    :host i, :host em, :host cite, :host var, :host dfn, :host q, :host blockquote { font-style: italic !important; }
    /* Hover-highlight freeze, same as the global layer (see GLOBAL_CSS). */
    *:hover:not(button):not(a):not(input):not(select):not(textarea):not(summary):not(.btn):not([class~="button" i]):not([class~="btn" i]):not(shreddit-button):not([role="button"]):not(:active):not(:focus),
    *:hover::before, *:hover::after {
      transition-property: background-color, background-image, background-position, box-shadow, filter, backdrop-filter, color, border-color, outline-color, text-decoration-color, text-shadow !important;
      transition-duration: 99999s !important;
      transition-delay: 0s !important;
      transition-timing-function: step-end !important;
    }
    *:not(svg):not(path):not(i):not([class*="icon" i]):not([class*="fa-" i]):not([class*="symbols" i]):not([class*="glyph" i]):not([class*="mdi" i]):not([class*="bi-" i]) {
      font-family: ${FONT} !important; -webkit-font-smoothing: none !important; -moz-osx-font-smoothing: unset !important; font-smooth: never !important; text-rendering: optimizeSpeed !important;
    }
    input, textarea, select, option, button, code, pre, kbd, samp, tt, [class*="code" i], [class*="mono" i] { font-family: ${FONT} !important; }
    :host { --radius: 0px; --shreddit-border-radius: 0px; --md-sys-shape-corner-full: 0px; background-color: transparent !important; background-image: none !important; color: ${T.textPrimary} !important; }
    /* Ad-iframe load-flash fix, scoped to known ad hosts only — see GLOBAL_CSS note (unconditional would break transparent widget overlays) */
    iframe[src*="doubleclick.net" i], iframe[src*="googlesyndication.com" i],
    iframe[src*="google.com/ads" i], iframe[id*="google_ads_iframe" i],
    iframe[id*="gpt_unit" i], iframe[src*="adservice.google" i],
    iframe[src*="amazon-adsystem.com" i], iframe[src*="taboola.com" i],
    iframe[src*="outbrain.com" i] {
      background-color: ${T.backgroundSoft} !important;
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
      background-color: ${T.surfaceRaised} !important; background-image: none !important; color: ${T.textPrimary} !important; ${B_OUTER}
    }

    button, input[type="button"], input[type="submit"], input[type="reset"], shreddit-button, .btn,
    [class~="button" i], [class~="btn" i], a[role="button"], span[role="button"], summary {
      background-color: ${T.surfaceRaised} !important; color: ${T.textPrimary} !important; ${B_OUTER}
      cursor: pointer !important; font-family: ${FONT} !important; box-sizing: border-box !important;
      padding: 2px 6px !important; min-width: 24px !important; min-height: 20px !important;
    }
    button:active, shreddit-button:active, .btn:active, [class~="button" i]:active, [class~="btn" i]:active, summary:active { background-color: ${T.surface} !important; ${B_INNER} transform: translate(1px, 1px) !important; }
    /* Disabled: label colour only, bevel and surface stay (UI.md bans opacity here) */
    button:disabled, shreddit-button:disabled, button[aria-disabled="true"], [role="button"][aria-disabled="true"] {
      color: ${T.textMuted} !important; background-color: ${T.surfaceRaised} !important; opacity: 1 !important; cursor: not-allowed !important; ${B_OUTER}
    }

    /* Paint-only: display:none here deleted ::before icon glyphs (see GLOBAL_CSS) */
    button::before, button::after, .btn::before, .btn::after { background: transparent !important; box-shadow: none !important; filter: none !important; }
    button * { background-color: transparent !important; box-shadow: none !important; border: none !important; }

    input:not([type="button"]):not([type="submit"]):not([type="reset"]):not([type="checkbox"]):not([type="radio"]) { background-color: ${T.compareBack} !important; color: ${T.textPrimary} !important; ${B_SUNK} box-sizing: border-box !important; }
    input:not([type="button"]):not([type="submit"]):not([type="reset"]):not([type="checkbox"]):not([type="radio"]):not([type="range"]):not([type="color"]):not([type="file"]), select { height: 20px !important; padding: 1px 3px !important; }
    textarea { min-height: 64px !important; resize: none !important; padding: 1px 3px !important; }
    /* appearance:auto not forced here either — see GLOBAL_CSS checkbox note */
    input[type="checkbox"], input[type="radio"] { accent-color: ${T.borderHighlight} !important; background-image: none !important; }
    input::placeholder, textarea::placeholder { color: ${T.textMuted} !important; }
    input:focus-visible, textarea:focus-visible, select:focus-visible, button:focus-visible, a:focus-visible,
    summary:focus-visible, [tabindex]:focus-visible, [role="button"]:focus-visible, [contenteditable]:focus-visible {
      outline: 1px dotted ${T.textPrimary} !important; outline-offset: -4px !important;
    }
    th { background-color: ${T.surface} !important; color: ${T.textPrimary} !important; ${B_OUTER} }
    ::selection { background-color: ${T.selection} !important; color: ${T.textPrimary} !important; }

    /* Hover recolor stays zeroed out here too — only real clickable controls respond. */
    button:hover, shreddit-button:hover, .btn:hover { background-color: ${T.surfaceAlt} !important; ${B_OUTER} }
    a, a:link { color: ${T.borderHighlight} !important; text-decoration: none !important; }
    a:visited { color: ${T.textSecondary} !important; }
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
          s.setAttribute('data-w95', 'shadow'); s.setAttribute('data-w95-ver', W95_VERSION);
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
    s.setAttribute('data-w95-ver', W95_VERSION);
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
    s.setAttribute('data-w95', 'global-late'); s.setAttribute('data-w95-ver', W95_VERSION);
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
      shadowObserver.observe(host.shadowRoot, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['class', 'bgcolor', 'background', 'style']
      });
      stylesDirty = true;
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
        const L = lum(bg);
        const spread = Math.max(bg.r, bg.g, bg.b) - Math.min(bg.r, bg.g, bg.b);
        const grayish = spread <= 24;
        let repaint = null;
        if (L > 0.45) {
          // Light flashbang surface: low-alpha white tints go fully transparent
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
        const fgLum = lum(fg);
        const darkBg = 0.008; // luminance of #1E1408 backdrop
        const contrast = (Math.max(fgLum, darkBg) + 0.05) / (Math.min(fgLum, darkBg) + 0.05);
        const grayish = Math.max(fg.r, fg.g, fg.b) - Math.min(fg.r, fg.g, fg.b) <= 40;

        if (el.closest && el.closest('a')) {
          // Anything inside a link takes the link colour when it is unreadable,
          // washed out, OR simply not one of ours — the last clause is iron law 5
          // and it was missing. Measured on amazon.com: span#nav-cart-count kept
          // #f08804 and span.navFooterDescText kept #999999, because both are
          // legible enough (7.1:1 and 6.3:1) that the first two tests passed them
          // through. Legible is not the same as on-palette.
          if (contrast < 4.5 || (fgLum > 0.4 && grayish) || !PALETTE_RGB.has(fgColor)) {
            w.push(el, 'color', T.borderHighlight);
          }
        } else {
          if (contrast < 4.5) {
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
        if (grayish && lum(bc) > 0.18) {
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
        // Only stylesheet-bearing additions need a force re-verify. Plain DOM
        // churn is already processed inline above and does not justify another
        // full sweep.
        if (styleishAdded) {
          stylesDirty = true;
          requestForceSweep();
        }
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
    if (document.hidden) return;
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
    if (forcePassesOwed < 8) forcePassesOwed++;
    scheduleSweep(1500);
  }

  function runSweeper(force) {
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
  }

  // Elements processed before the site's CSS finished loading bake in unstyled
  // values and would otherwise stay wrong forever (white surfaces that "heal"
  // only when the SPA happens to re-render them). Full re-verify passes
  // (force=true) re-check EVERY element: at DOMContentLoaded, again 1s later
  // once late CSS settled, then on demand whenever requestForceSweep() fires.
  // The write-if-changed guard in setImp keeps repeat passes cheap.
  function startSweeping() {
    injectLate();
    // The boot pass measured ONE 716ms long task on a 16921-element page, right
    // when the site's own init scripts are competing for the main thread — the
    // "have to reload a couple of times before it comes up" symptom. The
    // read/write split above is what actually shrinks it; deferring the second
    // pass past load keeps it out of the critical window as well.
    runSweeper(true);
    setTimeout(() => { stylesDirty = true; runSweeper(true); }, 1000);

    if (!IS_TOP) {
      // Sub-frame: bounded settling passes, then nothing. The MutationObserver
      // stays live, so a late-loading embed still gets themed — that path is
      // event-driven and costs zero while idle.
      setTimeout(() => { stylesDirty = true; runSweeper(true); }, 3000);
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
        runSweeper(true);
        lastSweepEnd = Date.now();
      } else if (sweepTimer) {
        clearTimeout(sweepTimer);
        sweepTimer = null;
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

})();
