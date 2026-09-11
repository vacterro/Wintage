// ==UserScript==
// @name         Wintage — Win95 Dark Golden Vintage Theme
// @namespace    https://github.com/vacterro/Wintage
// @version      1.35.1
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
// @grant        GM_getValue
// @grant        GM_setValue
// @grant        GM_registerMenuCommand
// @sandbox      raw
// ==/UserScript==

// @sandbox raw is load-bearing, not a preference. A plain @grant moves the script
// into Tampermonkey's isolated world, where Element.prototype is a DIFFERENT object
// than the page's — and the attachShadow interception below (the only way shadow
// DOM ever gets themed) would then patch a prototype no site ever calls. It would
// fail silently: every other feature keeps working, shadow roots just quietly stop
// being themed. `raw` keeps the script in page context while still injecting the GM
// API, which is the one combination that supports both. Every GM_* call is
// typeof-guarded anyway, so a manager that provides neither degrades to the default
// palette rather than throwing at document-start.

(function () {
  'use strict';

  // ─── EARLY RETURN GUARD ──────────────────────────────────────────────────────
  const EXCLUDE = [
    // Auth & Payments (don't break secure forms)
    /oauth/i, /captcha/i, /accounts\.google/i, /login\.microsoft/i, /paypal/i, /stripe/i, /bank/i,
    // Heavy Web Apps (lag too much or UI gets destroyed)
    /translate\.google/i, /maps\.google/i, /figma\.com/i, /canva\.com/i, /webflow\.com/i, /photopea\.com/i
  ];

  // CORE-003: the exclusion predicate is centralized so the SAME check that
  // runs at startup can be re-evaluated on every same-document route change.
  function isExcludedUrl(url) {
    return EXCLUDE.some(r => r.test(url || location.href));
  }

  // CORE-003: SPA safety guard. Once this script is active on an allowed route,
  // a same-document navigation into an excluded URL (/oauth, /captcha,
  // /paypal, /stripe, /bank, ...) must NOT leave the theme mutating auth or
  // payment UI. The inline repainter cannot be cheaply unwound, so the
  // smallest fail-safe is a forced normal reload: the userscript restarts,
  // observes the excluded URL at startup, and returns before any mutation.
  // The guard is installed BEFORE any DOM/CSS/observer mutation so an excluded
  // transition is caught as early as possible. It is only installed after the
  // startup check passes, so a reload on an excluded URL restarts cleanly and
  // never enters an infinite reload loop.
  function setupRouteGuard() {
    // CORE-013: install EXACTLY ONCE per document. This script can legitimately
    // run twice in the same document -- an in-place Tampermonkey update, a
    // manual re-inject from the dashboard, a manager that re-evaluates on a
    // same-document navigation -- and a second pass wraps `history.pushState`
    // around the FIRST wrapper. Three things then go wrong at once: `guard()`
    // fires twice per transition, the two `popstate`/`hashchange` listeners
    // stack one extra copy per pass, and layer one holds a permanent reference
    // to layer two so neither can ever be unwound. None of it is visible: the
    // guard still works, it just costs double and grows every re-inject.
    //
    // The latch lives on `window`, not in a module variable, because a second
    // run gets a fresh module scope and the same window. A window that refuses
    // the write (locked-down host object) falls through deliberately: one wrap
    // too many is strictly better than no safety guard at all.
    //
    // SRC-005 CORE-002: the latch used to be ONE boolean committed BEFORE any
    // hook was installed, so it really meant "installation was ATTEMPTED" while
    // callers read it as "the guard is complete". A single hook assignment
    // throwing (a locked-down host, an extension fighting for history.pushState)
    // left the marker set with that hook missing forever: reinjection returned
    // early and same-document pushState could walk into an excluded OAuth or
    // payment route with no quarantine at all. The latch is now a per-component
    // state object -- pushState, replaceState and the listeners each track their
    // own installation, reinjection retries ONLY the still-missing parts, and
    // the wrapped function itself carries a marker so a hook wrapped by any
    // earlier version of this script is recognised without guessing. A legacy
    // boolean `true` from an older build still means "listeners were installed
    // by that pass" (they always were when the old latch survived); the history
    // hooks are re-derived from the marker, not from the latch, so nothing is
    // ever re-wrapped on top of an existing layer.
    let state = null;
    try { state = window.__wintageRouteGuard; } catch (e) { state = null; }
    if (!state || typeof state !== 'object' || !('push' in state)) {
      state = { push: false, replace: false, listeners: state === true };
      try { window.__wintageRouteGuard = state; } catch (e) { }
    }
    const guard = function () {
      // CORE-003: reload is a REQUEST, not a state transition. If the navigation
      // is refused, cancelled, intercepted, or simply returns without unloading,
      // this document stays alive -- and it used to stay alive with the whole
      // repaint machinery running on a route the script explicitly excludes.
      // Quarantine FIRST, then ask to reload: the safety boundary must not
      // depend on the navigation succeeding.
      if (isExcludedUrl(location.href)) {
        // Best-effort: `suspendRepainter` is hoisted, but the observers it
        // disconnects are declared far below, so a same-tick route change during
        // script evaluation could reach it in the temporal dead zone. Losing the
        // suspension is survivable; throwing out of a history hook is not.
        try { suspendRepainter('excluded-route'); } catch (e) { }
        try {
          // The latch records WHICH url a reload was already requested for, not
          // merely that one was. A one-way boolean could only ever be cleared by
          // a synchronous throw, so an excluded -> allowed -> excluded journey
          // in a surviving document never asked again.
          if (window.__wintageExcludedReload !== location.href) {
            window.__wintageExcludedReload = location.href;
            try {
              location.reload();
            } catch (e) {
              window.__wintageExcludedReload = null;
              throw e;
            }
          }
        } catch (e) { }
      } else {
        // Back on an allowed route in a document that survived the request.
        // Clear the latch so a later excluded route is guarded again; the
        // quarantine deliberately STAYS, because thousands of inline !important
        // writes are already on this document and un-suspending mid-life is a
        // bigger risk than leaving it CSS-only until the next load.
        try {
          if (window.__wintageExcludedReload) window.__wintageExcludedReload = null;
        } catch (e) { }
      }
    };
    // Each component installs independently and flips its own flag only on
    // success, so one hostile hook can no longer poison the record of the
    // others -- and a partially-installed guard is REPAIRED by the next run
    // instead of being pinned as complete.
    if (!state.push) {
      const ps = (typeof history !== 'undefined') ? history.pushState : null;
      if (ps && ps.__wintageWrapped) {
        state.push = true;
      } else {
        try {
          const origPush = ps;
          history.pushState = function () {
            const ret = origPush.apply(this, arguments);
            guard();
            return ret;
          };
          try { history.pushState.__wintageWrapped = true; } catch (e) { }
          state.push = true;
        } catch (e) { }
      }
    }
    if (!state.replace) {
      const rs = (typeof history !== 'undefined') ? history.replaceState : null;
      if (rs && rs.__wintageWrapped) {
        state.replace = true;
      } else {
        try {
          const origReplace = rs;
          history.replaceState = function () {
            const ret = origReplace.apply(this, arguments);
            guard();
            return ret;
          };
          try { history.replaceState.__wintageWrapped = true; } catch (e) { }
          state.replace = true;
        } catch (e) { }
      }
    }
    if (!state.listeners) {
      try {
        window.addEventListener('popstate', guard);
        window.addEventListener('hashchange', guard);
        state.listeners = true;
      } catch (e) { }
    }
  }

  if (isExcludedUrl(location.href)) return;
  setupRouteGuard();

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

  // ─── PERFORMANCE SAFETY MODE ────────────────────────────────────────────────
  // Long-lived AI chats are unusually hostile to a universal DOM repainter:
  // React continuously mutates class/style attributes, message trees become very
  // large, and a single getComputedStyle() pass can invalidate/recalculate style
  // across the whole conversation. The CSS layer already supplies the visual
  // theme; the JavaScript repainter is only a corrective second layer.
  //
  // On known high-churn chat SPAs we therefore run CSS-only from the first byte:
  // no document-wide MutationObserver, no full-DOM sweeps, no CSSOM hover surgery.
  // Shadow roots are still styled at creation time by attachShadow interception.
  // This is the hard guarantee that an idle long chat cannot keep reheating the
  // CPU merely because the site twitches a class or inline style in the background.
  const HOST = (location.hostname || '').toLowerCase();
  const IS_X = /(^|\.)(x\.com|twitter\.com)$/.test(HOST);
  const IS_REDDIT = /(^|\.)(reddit\.com|redd\.it)$/.test(HOST);
  const IS_GOOGLE = /(^|\.)google\.[a-z.]+$/.test(HOST);
  const HIGH_CHURN_HOST = IS_X || /(^|\.)(chatgpt\.com|chat\.openai\.com|claude\.ai|gemini\.google\.com|chat\.qwen\.ai|perplexity\.ai)$/.test(HOST);
  const CSS_ONLY_MODE = HIGH_CHURN_HOST;

  // ─── UI.md TOKENS — THE COMPLETE PALETTE, NOTHING OUTSIDE IT ────────────────
  // UI.md iron law 5: "Every visible color must trace back to the palette."
  // These are the only colours this file is allowed to emit. If a value below
  // does not appear in a theme's token block, it is a bug.
  //
  // Every theme MUST carry all 21 token names. That is not stylistic tidiness:
  // PALETTE_RGB, semanticToken() and the repainter all read the table by key, so
  // a missing token surfaces as `undefined` inside a CSS declaration, which the
  // browser drops silently — the same class of invisible failure that made
  // tools/check-css.js necessary in the first place. check-css.js enforces the
  // full set per theme.
  //
  // Declared ABOVE the first paint, not below it. The pre-1.5.0 file painted a
  // literal '#1A0F05' here because the token table came later in the file; with
  // more than one palette that literal would be a second, silently diverging
  // source of truth — the very first thing the user sees would keep painting
  // golden no matter which theme was selected.
  // ─── THEME PACKS ── GENERATED by tools/apply-themes.js, DO NOT EDIT BY HAND ──
  const THEMES = {
    golden: {
      label: 'Dark Golden (Win95)',
      tokens: {
        background: '#342012', backgroundSoft: '#3A2616',
        surface: '#4A341B', surfaceRaised: '#5A4324', surfaceAlt: '#634B2B',
        borderDark: '#1C1208', borderHighlight: '#D3B57A', bevelLight: '#826941', borderMuted: '#665033',
        textPrimary: '#E2CA95', textSecondary: '#C5AB6E', textMuted: '#95804C',
        accentTeal: '#008080', accentTealDeep: '#006060',
        success: '#5B9630', warning: '#969630', danger: '#963030', dangerText: '#D37676',
        selection: '#5A4324', compareBack: '#24170C',
        link: '#D3B57A'
      }
    },
    claudecode: {
      label: 'Claude Code',
      tokens: {
        background: '#29241D', backgroundSoft: '#2E2922',
        surface: '#3B362A', surfaceRaised: '#484436', surfaceAlt: '#514C3D',
        borderDark: '#15130F', borderHighlight: '#D1A27C', bevelLight: '#75644F', borderMuted: '#555144',
        textPrimary: '#E0B997', textSecondary: '#C39870', textMuted: '#93704E',
        accentTeal: '#008080', accentTealDeep: '#006060',
        success: '#5B9630', warning: '#969630', danger: '#963030', dangerText: '#D37575',
        selection: '#484436', compareBack: '#1C1914',
        link: '#D1A27C'
      }
    },
    antigravity: {
      label: 'Antigravity',
      tokens: {
        background: '#1B1F2C', backgroundSoft: '#1F2431',
        surface: '#272B3E', surfaceRaised: '#31354D', surfaceAlt: '#393D55',
        borderDark: '#0D0F17', borderHighlight: '#7AD0D3', bevelLight: '#4B6678', borderMuted: '#404359',
        textPrimary: '#95DEE2', textSecondary: '#6EBFC5', textMuted: '#4C8F95',
        accentTeal: '#008080', accentTealDeep: '#006060',
        success: '#5B9630', warning: '#969630', danger: '#963030', dangerText: '#D06D6D',
        selection: '#31354D', compareBack: '#12151E',
        link: '#7AD0D3'
      }
    },
    klite: {
      label: 'K-Lite (MPC-HC)',
      tokens: {
        background: '#212325', backgroundSoft: '#26282A',
        surface: '#303235', surfaceRaised: '#3C3F42', surfaceAlt: '#44474A',
        borderDark: '#111213', borderHighlight: '#A2A5AB', bevelLight: '#5E6165', borderMuted: '#494C50',
        textPrimary: '#B8BABF', textSecondary: '#95989E', textMuted: '#6D6F74',
        accentTeal: '#008080', accentTealDeep: '#006060',
        success: '#5B9630', warning: '#969630', danger: '#963030', dangerText: '#D27272',
        selection: '#3C3F42', compareBack: '#171819',
        link: '#A2A5AB'
      }
    },
    freebuff: {
      label: 'FreeBuff',
      tokens: {
        background: '#1B232B', backgroundSoft: '#202830',
        surface: '#28303D', surfaceRaised: '#333B4B', surfaceAlt: '#3A4354',
        borderDark: '#0E1116', borderHighlight: '#89D37A', bevelLight: '#506B5F', borderMuted: '#414958',
        textPrimary: '#A0E295', textSecondary: '#7AC56E', textMuted: '#55954C',
        accentTeal: '#008080', accentTealDeep: '#006060',
        success: '#5B9630', warning: '#969630', danger: '#963030', dangerText: '#D27272',
        selection: '#333B4B', compareBack: '#13181D',
        link: '#89D37A'
      }
    },
    codenomad: {
      label: 'CodeNomad',
      tokens: {
        background: '#1C242A', backgroundSoft: '#21282F',
        surface: '#29313C', surfaceRaised: '#343D4A', surfaceAlt: '#3C4552',
        borderDark: '#0E1216', borderHighlight: '#9D86D1', bevelLight: '#575776', borderMuted: '#424A57',
        textPrimary: '#B099DE', textSecondary: '#9C84C8', textMuted: '#675091',
        accentTeal: '#008080', accentTealDeep: '#006060',
        success: '#5B9630', warning: '#969630', danger: '#963030', dangerText: '#D27272',
        selection: '#343D4A', compareBack: '#13181D',
        link: '#9D86D1'
      }
    },
    fpdefault: {
      label: 'Default',
      tokens: {
        background: '#1A1A1A', backgroundSoft: '#2C2C2C',
        surface: '#2B2B2B', surfaceRaised: '#343434', surfaceAlt: '#3A3A3A',
        borderDark: '#0A0A0A', borderHighlight: '#839BB0', bevelLight: '#4E555B', borderMuted: '#4D4D4D',
        textPrimary: '#C0C0C0', textSecondary: '#949494', textMuted: '#656565',
        accentTeal: '#008080', accentTealDeep: '#004C4C',
        success: '#4A7A20', warning: '#7A7A20', danger: '#7A2020', dangerText: '#DB7575',
        selection: '#343434', compareBack: '#141414',
        link: '#839BB0'
      }
    },
    goldenvintage: {
      label: 'Golden Vintage',
      tokens: {
        background: '#0F0F0F', backgroundSoft: '#1A1A1A',
        surface: '#2B2B2B', surfaceRaised: '#333333', surfaceAlt: '#393939',
        borderDark: '#050505', borderHighlight: '#D6BE76', bevelLight: '#655E4A', borderMuted: '#4A4A4A',
        textPrimary: '#C4BA9F', textSecondary: '#8E8774', textMuted: '#605C50',
        accentTeal: '#008080', accentTealDeep: '#004C4C',
        success: '#4A7A20', warning: '#7A7A20', danger: '#7A2020', dangerText: '#D45C5C',
        selection: '#333333', compareBack: '#0B0B0B',
        link: '#D6BE76'
      }
    },
    goldendefault: {
      label: 'Golden Default',
      tokens: {
        background: '#1A1810', backgroundSoft: '#232018',
        surface: '#332E22', surfaceRaised: '#3D372A', surfaceAlt: '#453D30',
        borderDark: '#100E08', borderHighlight: '#F0D060', bevelLight: '#75663D', borderMuted: '#5A5040',
        textPrimary: '#D4C89A', textSecondary: '#9C9371', textMuted: '#6E674E',
        accentTeal: '#008080', accentTealDeep: '#004C4C',
        success: '#4A7A20', warning: '#7A7A20', danger: '#7A2020', dangerText: '#D66464',
        selection: '#3D372A', compareBack: '#14120C',
        link: '#F0D060'
      }
    },
    vintagedark: {
      label: 'Vintage Dark',
      tokens: {
        background: '#181818', backgroundSoft: '#1B1B1B',
        surface: '#2B2B2B', surfaceRaised: '#343434', surfaceAlt: '#3A3A3A',
        borderDark: '#0A0A0A', borderHighlight: '#738EA6', bevelLight: '#4A5258', borderMuted: '#4D4D4D',
        textPrimary: '#C0C0C0', textSecondary: '#8E8E8E', textMuted: '#646464',
        accentTeal: '#008080', accentTealDeep: '#004C4C',
        success: '#4A7A20', warning: '#7A7A20', danger: '#7A2020', dangerText: '#D45D5D',
        selection: '#343434', compareBack: '#121212',
        link: '#738EA6'
      }
    },
    vintageclassic: {
      label: 'Vintage Classic',
      tokens: {
        background: '#C0C0C0', backgroundSoft: '#FFFFFF',
        surface: '#C0C0C0', surfaceRaised: '#D0D0D0', surfaceAlt: '#DCDCDC',
        borderDark: '#808080', borderHighlight: '#F6F6F6', bevelLight: '#F6F6F6', borderMuted: '#FFFFFF',
        textPrimary: '#000000', textSecondary: '#3A3A3A', textMuted: '#6A6A6A',
        accentTeal: '#008080', accentTealDeep: '#004C4C',
        success: '#4A7A20', warning: '#7A7A20', danger: '#7A2020', dangerText: '#7A2020',
        selection: '#D0D0D0', compareBack: '#D0D0D0',
        link: '#5E7A7A'
      }
    },
    oled: {
      label: 'Dark 2 (OLED)',
      tokens: {
        background: '#000000', backgroundSoft: '#000000',
        surface: '#0A0A0A', surfaceRaised: '#141414', surfaceAlt: '#1C1C1C',
        borderDark: '#1A1A1A', borderHighlight: '#FFFFFF', bevelLight: '#5C5C5C', borderMuted: '#333333',
        textPrimary: '#A0A0A0', textSecondary: '#777777', textMuted: '#484848',
        accentTeal: '#008080', accentTealDeep: '#004C4C',
        success: '#4A7A20', warning: '#7A7A20', danger: '#7A2020', dangerText: '#CE4444',
        selection: '#141414', compareBack: '#000000',
        link: '#FFFFFF'
      }
    },
    dracula: {
      label: 'Dracula',
      tokens: {
        background: '#21222C', backgroundSoft: '#282A36',
        surface: '#44475A', surfaceRaised: '#4C526D', surfaceAlt: '#525A7B',
        borderDark: '#191A21', borderHighlight: '#BD93F9', bevelLight: '#706A9E', borderMuted: '#6272A4',
        textPrimary: '#F8F8F2', textSecondary: '#B8B8B7', textMuted: '#828285',
        accentTeal: '#008080', accentTealDeep: '#004C4C',
        success: '#4A7A20', warning: '#7A7A20', danger: '#7A2020', dangerText: '#DA7373',
        selection: '#4C526D', compareBack: '#191A21',
        link: '#BD93F9'
      }
    },
    nord: {
      label: 'Nord',
      tokens: {
        background: '#272C36', backgroundSoft: '#2E3440',
        surface: '#3B4252', surfaceRaised: '#3F4758', surfaceAlt: '#434B5D',
        borderDark: '#232831', borderHighlight: '#88C0D0', bevelLight: '#566C7D', borderMuted: '#4C566A',
        textPrimary: '#D8DEE9', textSecondary: '#A3A9B3', textMuted: '#777C87',
        accentTeal: '#008080', accentTealDeep: '#004C4C',
        success: '#4A7A20', warning: '#7A7A20', danger: '#7A2020', dangerText: '#DE8282',
        selection: '#3F4758', compareBack: '#1D2129',
        link: '#88C0D0'
      }
    },
    solarized: {
      label: 'Solarized Dark',
      tokens: {
        background: '#002B36', backgroundSoft: '#073642',
        surface: '#073642', surfaceRaised: '#1B444F', surfaceAlt: '#2B4F59',
        borderDark: '#001F27', borderHighlight: '#51A2DB', bevelLight: '#36667D', borderMuted: '#586E75',
        textPrimary: '#93A1A1', textSecondary: '#8D9EA1', textMuted: '#426066',
        accentTeal: '#008080', accentTealDeep: '#004C4C',
        success: '#4A7A20', warning: '#7A7A20', danger: '#7A2020', dangerText: '#DD7D7D',
        selection: '#1B444F', compareBack: '#002029',
        link: '#51A2DB'
      }
    },
    custom: {
      label: 'Custom',
      tokens: {
        background: '#1A1810', backgroundSoft: '#232018',
        surface: '#332E22', surfaceRaised: '#3D372A', surfaceAlt: '#453D30',
        borderDark: '#100E08', borderHighlight: '#F0D060', bevelLight: '#75663D', borderMuted: '#5A5040',
        textPrimary: '#D4C89A', textSecondary: '#9C9371', textMuted: '#6E674E',
        accentTeal: '#008080', accentTealDeep: '#004C4C',
        success: '#4A7A20', warning: '#7A7A20', danger: '#7A2020', dangerText: '#D66464',
        selection: '#3D372A', compareBack: '#14120C',
        link: '#F0D060'
      }
    }
  };
  // ─── END THEME PACKS ─────────────────────────────────────────────────────────

  // Which theme is live. Resolved from GM storage, which is per-USER and not
  // per-origin — the distinction that rules out localStorage/cookies for this:
  // either would make the theme reset on every new domain, which for a script
  // matching *://*/* is every other page load.
  //
  // Resolution is deliberately total: an unknown slug (a theme pack removed after
  // it was selected, a hand-edited value) falls back to the default rather than
  // throwing, because this runs at document-start and an exception here means the
  // page paints unthemed white.
  const DEFAULT_THEME = 'goldendefault';
  const THEME_KEY = 'w95-theme';
  let requested = DEFAULT_THEME;
  try {
    if (typeof GM_getValue === 'function') requested = GM_getValue(THEME_KEY, DEFAULT_THEME);
  } catch (e) { }
  const THEME_ID = THEMES[requested] ? requested
    : (THEMES[DEFAULT_THEME] ? DEFAULT_THEME : Object.keys(THEMES)[0]);
  const T = THEMES[THEME_ID].tokens;
  // CORE-014/CORE-003: what STORAGE says, before the fallback above collapses it
  // onto a real pack. Kept for diagnostics and for the pending-palette recovery:
  // note that at startup it can never disagree with THEME_ID in a way the old
  // menu predicate could detect (a valid slug IS adopted at :390, an invalid one
  // fails the THEMES lookup), so the pending row is driven by RUNTIME state set
  // when a switch persists without reloading -- never by this constant.
  const STORED_THEME_ID = requested;
  // The palette storage now names but this document is not painting. Mutable on
  // purpose: it is set by the switch callback when the reload does not land.
  let pendingThemeId = null;
  let pendingRowRegistered = false;

  function lum({ r, g, b }) {
    const lin = v => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4); };
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
  }
  function hexLum(hex) {
    return lum({ r: parseInt(hex.slice(1, 3), 16), g: parseInt(hex.slice(3, 5), 16), b: parseInt(hex.slice(5, 7), 16) });
  }
  function contrast(a, b) { return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05); }

  // ─── THEME POLARITY ──────────────────────────────────────────────────────────
  // Every luminance threshold in the repainter was written against the golden
  // palette and silently assumes "our theme is dark, so BRIGHT means the site is
  // shouting". On a light palette every one of those tests inverts: there, a dark
  // site surface is the flashbang and a bright one is already close to home.
  // Rather than duplicate the whole decision tree per polarity, the incoming
  // luminance is normalised once — `elev(L)` answers "how far is this colour from
  // MY background, in the direction that reads as raised on MY theme" — and the
  // existing numbers keep their meaning against that.
  //
  // For the golden palette DARK is true and elev() is the identity function, so
  // this is provably a no-op there: same numbers, same comparisons, same result.
  const BG_LUM = hexLum(T.background);
  const BG_SOFT_LUM = hexLum(T.backgroundSoft);
  const DARK = BG_LUM < 0.18;
  const elev = L => (DARK ? L : 1 - L);

  // ─── IMMEDIATE BACKGROUND ────────────────────────────────────────────────────
  // Must stay the first thing that touches the document so nothing white ever
  // paints, and it now paints the ACTIVE theme rather than a hardcoded golden.
  if (document.documentElement) {
    document.documentElement.style.setProperty('background-color', T.background, 'important');
    document.documentElement.style.setProperty('color', T.textPrimary, 'important');
    document.documentElement.setAttribute('data-w95-dark', DARK ? '1' : '0');
    document.documentElement.setAttribute('data-w95-theme', THEME_ID);
    if (IS_X) document.documentElement.setAttribute('data-w95-x', '1');
    if (IS_REDDIT) document.documentElement.setAttribute('data-w95-reddit', '1');
    if (IS_GOOGLE) document.documentElement.setAttribute('data-w95-google', '1');
  }

  // ─── THEME MENU ──────────────────────────────────────────────────────────────
  // Top frame only. The script runs in every frame (see FRAME ROLE above), so
  // registering per frame would stack one duplicate menu entry per ad iframe on
  // the page — the menu is a per-tab UI, not a per-document one.
  //
  // A userscript cannot restyle a live page from one palette to another: the CSS
  // is one injected <style> but the repainter has already written thousands of
  // inline !important values keyed to the old tokens, and there is no cheap,
  // correct way to unwind them. Reload is the honest answer, and it is what the
  // user expects from a theme switch anyway.
  //
  // CORE-014: a reload that does not happen must not leave a silent split brain.
  // The write lands first (it has to -- the new palette is read at the next
  // document-start), so if the navigation is then refused -- a `beforeunload`
  // confirm the user cancels, a host that blocks programmatic navigation -- the
  // page keeps painting the OLD palette while storage already says the NEW one.
  // The theme did switch; only this tab did not, and nothing on screen says so.
  // That reads as "the switcher is broken", and the next reload silently
  // "fixes" it, which is worse than a visible failure.
  //
  // A DOM banner is not available here: this runs at document-start where
  // document.body does not exist yet, and the menu callback fires much later
  // against a page the repainter owns. The one channel that is always present
  // and cannot be styled away by the host page is the menu itself, so the
  // pending palette is re-advertised there on the next registration pass, and
  // the failure is stated once in the console with the exact recovery step.
  if (IS_TOP && typeof GM_registerMenuCommand === 'function') {
    // CORE-003: the recovery row is registered AT THE MOMENT the split-brain
    // state is created, not from a startup comparison. The old predicate
    // (`STORED_THEME_ID !== THEME_ID && THEMES[STORED_THEME_ID]`) was
    // algebraically unreachable: a valid stored slug is adopted as THEME_ID one
    // line after it is read, so the two can only differ when the slug is invalid
    // -- and then the THEMES lookup is false. The row it advertised could never
    // appear, which is worse than not advertising it.
    const registerPendingRow = function (id) {
      pendingThemeId = id;
      if (pendingRowRegistered) return;
      pendingRowRegistered = true;
      try {
        GM_registerMenuCommand('⟳ Apply pending theme: ' + THEMES[id].label, function () {
          try { location.reload(); } catch (e) { }
        });
      } catch (e) { pendingRowRegistered = false; }
    };
    // One idempotent recovery helper for BOTH refusal classes: the synchronous
    // throw and the survival-probe hit below. Two paths, one row, one warning.
    const reportPendingTheme = function (id, reason) {
      registerPendingRow(id);
      try {
        console.warn('[Wintage] theme set to "' + id + '" but this tab could not reload (' + reason +
          '). Reload the page manually to apply it.');
      } catch (e2) { }
    };
    // SRC-005 CORE-001: `location.reload()` returning normally does NOT prove
    // the old document will unload. A cancelled `beforeunload` -- or a host that
    // silently declines programmatic navigation -- leaves THIS document alive
    // while storage already selects the new palette: the exact split brain
    // CORE-014 fixed for the throwing class only. The catch cannot see it, so
    // the switch arms a one-shot survival probe: an actual pagehide/beforeunload
    // disarms it, and if the timer fires while the same document is still alive,
    // the pending row and the warning are emitted through the same helper the
    // throw path uses. No live repaint across palettes; the reload stays the
    // architecture.
    const armSurvivalProbe = function (id) {
      if (typeof setTimeout !== 'function') return;
      let survived = true;
      const disarm = function () { survived = false; };
      try { addEventListener('pagehide', disarm, { once: true }); } catch (e) { }
      try { addEventListener('beforeunload', disarm, { once: true }); } catch (e) { }
      setTimeout(function () {
        try { removeEventListener('pagehide', disarm); } catch (e) { }
        try { removeEventListener('beforeunload', disarm); } catch (e) { }
        if (!survived) return;
        reportPendingTheme(id, 'the reload was cancelled without unloading this document');
      }, 350);
    };
    for (const id of Object.keys(THEMES)) {
      const active = id === THEME_ID;
      GM_registerMenuCommand((active ? '● ' : '○ ') + THEMES[id].label, function () {
        if (active) return;
        try { GM_setValue(THEME_KEY, id); } catch (e) { return; }
        let reloadThrew = false;
        try {
          location.reload();
        } catch (e) {
          reloadThrew = true;
          // Navigation refused. Storage is already the new palette, so say so
          // rather than letting the tab look unchanged for no stated reason,
          // and put a working retry in the one channel the host cannot style.
          reportPendingTheme(id, e && e.message ? e.message : 'navigation refused');
        }
        if (!reloadThrew) armSurvivalProbe(id);
      });
    }
    GM_registerMenuCommand('🤍 Support developer', function () {
      window.open('https://buymeacoffee.com/vacuum34', '_blank');
    });
  }

  // Stamped as data-w95-ver on every injected <style>, so a console diagnostic can
  // report which build is actually live. Without it, "is this 1.4.2 or 1.4.3?"
  // costs a round trip to the Tampermonkey dashboard — and a stale install
  // silently invalidates whatever measurement is being taken, which already
  // wasted one full diagnostic round on a page where the script wasn't running.
  // Declared up here, not next to injectStyle: the attachShadow interception
  // reads it too and is installed earlier in the file.
  const W95_VERSION = '1.35.1';

  // Verdana forced 100% everywhere. Verdana_m1 = locally installed modified Verdana.
  const FONT = 'Verdana_m1, Verdana, Tahoma, "MS Sans Serif", sans-serif';

  // ─── DIAGNOSTIC COUNTERS (CORE-015) ─────────────────────────────────────────
  // Several passes below run inside try/catch by necessity: a cross-origin sheet
  // throws on cssRules, an unresolved @import throws, an engine can hand back a
  // half-built rule, and a shadow root can be detached between discovery and
  // injection. Swallowing those is correct -- one hostile sheet must not stop the
  // pass. Swallowing them SILENTLY is not: the visible symptom of a suppressed
  // throw in the hover surgery is "the site's hover highlight is still there",
  // which looks exactly like a missing feature and leaves nothing to diagnose.
  //
  // So the swallow is counted rather than hidden. Cost on the happy path is one
  // integer bump that never happens; there is deliberately NO per-throw logging,
  // because a churning CSS-in-JS page would flood the console with thousands of
  // identical lines. One snapshot is readable on demand, from the page console:
  //     window.__wintageDiag()
  //
  // Declared up here with the other cross-cutting constants, not next to the
  // hover surgery: pierceShadow (far above it) reports through the same counters,
  // and a `const` used before its declaration line is a TDZ ReferenceError, not
  // a hoisted undefined.
  const DIAG = { hoverWalkThrows: 0, hoverAppendThrows: 0, sheetGenThrows: 0, shadowPierceThrows: 0, firstError: null };
  function noteSuppressed(kind, e) {
    DIAG[kind]++;
    // Only the FIRST error is kept: it carries the untangled stack, and a hostile
    // page can throw thousands. The counters carry the volume.
    if (!DIAG.firstError) DIAG.firstError = { kind: kind, message: (e && e.message) ? e.message : String(e) };
  }
  try {
    window.__wintageDiag = function () {
      return {
        version: W95_VERSION,
        theme: THEME_ID,
        cssOnlyMode: CSS_ONLY_MODE,
        suppressed: {
          hoverWalkThrows: DIAG.hoverWalkThrows,
          hoverAppendThrows: DIAG.hoverAppendThrows,
          sheetGenThrows: DIAG.sheetGenThrows,
          shadowPierceThrows: DIAG.shadowPierceThrows
        },
        firstError: DIAG.firstError
      };
    };
  } catch (e) { }

  // ─── STRUCTURAL BEVEL CONSTANTS — 2px, BORDERS ONLY, NO SHADOW ─────────────
  // UI.md law 3: "Depth is 2px bevel only." UI.md law 2: "zero shadow."
  // The pre-1.4.0 bevel was 1px borders PLUS an inset box-shadow to fake the
  // second bevel row — which broke both laws at once and, more practically, made
  // every site's depth read slightly differently depending on whether its own CSS
  // also set a box-shadow we happened to lose the specificity fight over. UI.md
  // spells the correct form out literally, as a 4-value border-color shorthand
  // (top right bottom left), so that is what is used verbatim here.
  //
  // The LIGHT edge is ${T.bevelLight}, not ${T.borderHighlight}. Both name a bevel
  // in UI.md, but borderHighlight is also the link/accent colour — a saturated
  // gold, teal or violet sitting several steps above the text it frames. Put on
  // every panel, button, input, scrollbar and dialog edge at once, it stopped
  // reading as depth and started reading as decoration: reported on Antigravity as
  // the edges taking all the attention, and it is the same complaint Win95 itself
  // answers by making the light edge a LIGHTNESS step off the surface (white on
  // grey), never a hue. bevelLight is exactly that step -- one notch above
  // surfaceAlt, the lightest surface in the palette, so it still reads as lit from
  // the top-left against every background the theme paints, without competing with
  // the text. A light palette keeps its near-white edge, which is the same rule.
  const B_OUTER = `border: 2px solid !important; border-color: ${T.bevelLight} ${T.borderDark} ${T.borderDark} ${T.bevelLight} !important; box-shadow: none !important;`;
  const B_INNER = `border: 2px solid !important; border-color: ${T.borderDark} ${T.bevelLight} ${T.bevelLight} ${T.borderDark} !important; box-shadow: none !important;`;
  const B_SUNK = B_INNER;

  // ═══════════════════════════════════════════════════════════════════════════════
  // GLOBAL CSS — v29.0
  // ═══════════════════════════════════════════════════════════════════════════════
  const GLOBAL_CSS = `
:root {
  color-scheme: ${DARK ? 'dark' : 'light'} !important;
  /* UI.md token block, verbatim names — the single source of colour truth. */
  --background: ${T.background}; --backgroundSoft: ${T.backgroundSoft};
  --surface: ${T.surface}; --surfaceRaised: ${T.surfaceRaised}; --surfaceAlt: ${T.surfaceAlt};
  --borderDark: ${T.borderDark}; --borderHighlight: ${T.borderHighlight}; --bevelLight: ${T.bevelLight}; --borderMuted: ${T.borderMuted}; --link: ${T.link};
  --textPrimary: ${T.textPrimary}; --textSecondary: ${T.textSecondary}; --textMuted: ${T.textMuted};
  --accentTeal: ${T.accentTeal}; --accentTealDeep: ${T.accentTealDeep};
  --success: ${T.success}; --warning: ${T.warning}; --danger: ${T.danger}; --dangerText: ${T.dangerText};
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
  /* CRITICAL CPU GUARD: duration alone is not enough. An infinite animation at
     1ms still remains an infinite animation, and pseudo-element animations
     cannot be paused by process(el) because ::before/::after are not Elements.
     Clamp every animation to one iteration so spinners, shimmer skeletons and
     hidden pseudo-elements complete once instead of being evaluated forever. */
  animation-iteration-count: 1 !important;
  /* 🚨 SNAPBACK — this line is why reuters.com rendered a blank page 🚨
     The comment above used to argue snapback "only affects already-broken
     sites". That was wrong, and Reuters is the proof: header drawn, article
     body empty, full-height scrollbar. The pattern is completely ordinary —
     base state opacity:0, a reveal animation with no fill-mode, and the
     final visible state left to the animation. Slam the duration to 0.001s
     and the animation ends immediately, the effect stops applying, and the
     element falls back to its base opacity:0. Forever.
     'forwards' makes the last keyframe persist, which is exactly what such a
     site would have written itself. Not 'both': that would also apply the
     FROM state before the animation starts, a behaviour change this does not
     need since the delay is already 0s. Reveal animations now land visible;
     nothing else about the no-motion rule changes.
     (Backticks are banned in here -- this whole block is a JS template
     literal, so one backtick ends the stylesheet mid-file.) */
  animation-fill-mode: forwards !important;
}
html { scroll-behavior: auto !important; }

/* 🚨 NO 99999s HOVER TRANSITIONS 🚨
   The previous cross-origin fallback kept paint-property transitions alive for
   99,999 seconds on every hovered element and pseudo-element. On a deep React
   tree, :hover matches the whole ancestor chain; every small paint change could
   therefore leave another long-lived transition object behind. Readable hover
   rules are still stripped by stripHoverSheets(). Unreadable cross-origin hover
   paint is now tolerated rather than buying a permanent compositor tax. */

/* The page's own photo backdrop goes at the root too. The repainter handles the
   full-bleed DIVs sites use for this (see the page-sized backdrop rule there),
   but html/body are the classic carriers and need no measurement to judge: a
   background image on the document root is never an icon. */
html, body { background-image: none !important; }
html { background-color: ${T.background} !important; color: ${T.textPrimary} !important; }
body { background-color: ${T.backgroundSoft} !important; color: ${T.textPrimary} !important; margin: 0 !important; padding: 0 !important; }

/* 🚨 VERDANA 100% FORCED EVERYWHERE — inputs/textareas included 🚨
   Only true icon-font carriers are excluded (glyphs would turn into letters). */
*:not(svg):not(path):not(i):not([class*="icon" i]):not([class*="fa-" i]):not([class*="symbols" i]):not([class*="glyph" i]):not([class*="mdi" i]):not([class*="bi-" i]):not([class*="codicon" i]):not([class*="lucide" i]):not([class*="octicon" i]):not([class*="remixicon" i]):not([class*="phosphor" i]):not([class*="iconify" i]):not([class*="feather" i]):not([data-icon]):not([data-cds="Icon"]) {
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
*:not(svg):not(path):not(i):not(html):not(h1):not(h2):not(h3):not(h4):not(h5):not(h6):not(small):not(sub):not(sup):not(figcaption):not([class*="icon" i]):not([class*="fa-" i]):not([class*="symbols" i]):not([class*="glyph" i]):not([class*="mdi" i]):not([class*="bi-" i]):not([class*="codicon" i]):not([class*="lucide" i]):not([class*="octicon" i]):not([class*="remixicon" i]):not([class*="phosphor" i]):not([class*="iconify" i]):not([class*="feather" i]):not([data-icon]):not([data-cds="Icon"]) {
  font-size: 12px !important;
  line-height: 1.2 !important;
}
h1 { font-size: 16px !important; line-height: 1.2 !important; color: ${T.textPrimary} !important; }
h2, h3, h4, h5, h6 { font-size: 14px !important; line-height: 1.2 !important; color: ${T.textPrimary} !important; }
small, sub, sup, figcaption { font-size: 10px !important; line-height: 1.2 !important; color: ${T.textSecondary} !important; }

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
:root b, :root strong { color: ${T.textPrimary} !important; }
:root i, :root em, :root cite, :root var, :root address, :root dfn, :root q, :root blockquote { font-style: italic !important; }

/* UI.md law 5 + the accessibility floor, together. The old link colour #9DD9F9
   traced to no token at all — an iron-law-5 violation on the single most common
   coloured element on the web. --accentTeal is the palette's accent, but #008080
   on #1A0F05 measures 3.7:1, under the WCAG AA 4.5:1 that UI.md also requires,
   so it is NOT usable as link TEXT. --borderHighlight #C0A060 measures 7.8:1, is
   a real token, and stays clearly distinct from --textPrimary body text. Visited
   uses --textSecondary (6.2:1); --textMuted was rejected at 3.3:1 for the same
   AA reason. */
a, a:link { color: ${T.link} !important; text-decoration: none !important; background-color: transparent !important; }
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
body, main, section, article, aside, footer,
.container, [class*="container" i]:not([class*="button" i]):not([class*="btn" i]):not([class*="input" i]):not([class*="badge" i]):not([class*="card" i]):not([class*="item" i]):not([class*="popup" i]):not([class*="modal" i]):not([class*="dialog" i]):not([class*="menu" i]):not([class*="dropdown" i]):not([class*="tooltip" i]):not([class*="toast" i]):not([class*="alert" i]):not([class*="banner" i]),
.wrapper, [class*="wrapper" i]:not([class*="button" i]):not([class*="btn" i]):not([class*="input" i]):not([class*="badge" i]):not([class*="card" i]):not([class*="item" i]):not([class*="popup" i]):not([class*="modal" i]):not([class*="dialog" i]):not([class*="menu" i]):not([class*="dropdown" i]):not([class*="tooltip" i]):not([class*="toast" i]):not([class*="alert" i]):not([class*="banner" i]),
.main, #main, #wrapper { background-color: transparent !important; }

*::selection, ::selection { background-color: ${T.selection} !important; color: ${T.textPrimary} !important; }

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
header::before, header::after, nav::before, nav::after, footer::before, footer::after,
[role="navigation"]::before, [role="navigation"]::after,
[role="banner"]::before, [role="banner"]::after,
[role="contentinfo"]::before, [role="contentinfo"]::after,
[class*="header" i]::before, [class*="header" i]::after,
[class*="navbar" i]::before, [class*="navbar" i]::after,
[class*="nav-bar" i]::before, [class*="nav-bar" i]::after,
[class*="topbar" i]::before, [class*="topbar" i]::after,
[class*="top-bar" i]::before, [class*="top-bar" i]::after,
[class*="footer" i]::before, [class*="footer" i]::after,
[class*="toolbar" i]:not([class*="ytp" i])::before, [class*="toolbar" i]:not([class*="ytp" i])::after,
[id*="header" i]::before, [id*="header" i]::after,
[id*="navbar" i]::before, [id*="navbar" i]::after,
[id*="topbar" i]::before, [id*="topbar" i]::after,
[id*="footer" i]::before, [id*="footer" i]::after {
  background-color: transparent !important;
}
[class*="icon" i], [class*="glyph" i], [class*="symbol" i] {
  --fill: currentColor !important;
  --icon-color: currentColor !important;
  --svg-fill: currentColor !important;
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

/* 🚨 A STATUS INDICATOR IS NOT BUTTON DECORATION 🚨
   This rule's selector list began with a bare, UNGUARDED
   "button:not(.ytp-button) *," line for one release: when the exclusions below
   were added, the old selector was left above them with its trailing comma, so it
   stayed in the same list and kept matching everything the guards were written to
   spare. The dot was wiped by the very rule the guards were bolted onto, the
   guarded copies below never got a chance to not-match, and the CSS read as
   fixed. Verified on the live app while it was in that state: span.status-dot
   with data-kind="running", 6x6, background-color rgba(0, 0, 0, 0).
   A guard is only a guard if EVERY selector in the list carries it -- one
   unguarded sibling in a comma list defeats all of them, silently.
   tools/check-css.js now fails on exactly that shape.
   The wipe above exists so a button reads as ONE control instead of a pile of
   nested boxes, and it is right about wrappers. It is wrong about the small
   coloured dot a button uses to report state, whose entire meaning IS its
   background — done, running, waiting. Claude Code puts exactly such a dot inside
   a button and the wipe left an empty hole where the status had been. Confirmed
   from the engine rather than guessed: CSS.getMatchedStylesForNode on that dot
   lists .status-dot[data-kind="running"] with background hsl(var(--text-400))
   losing to this rule's background-color transparent.
   The exclusions are EXPRESSED AS :not() ON THE WIPE ITSELF, not as a re-colouring
   rule after it. Undoing it later cannot work: from user origin (which is how the
   Electron shim injects into Claude) revert rolls back to the USER-AGENT origin,
   not to the app's, so the dot would have come back transparent and looked fixed
   in the CSS while staying broken on screen. Not matching is the only thing that
   lets the app's own colour through — and it is also what keeps the OTHER states
   right without guessing what any of them are called. */
button:not(.ytp-button) *:not(i):not([class*="icon" i]):not([class*="fa-" i]):not([class*="symbols" i]):not([class*="glyph" i]):not([class*="mdi" i]):not([class*="bi-" i]):not([class*="status" i]):not([class*="indicator" i]):not([class*="badge" i]):not([class*="dot" i]):not([data-kind]):not([data-status]):not([role="status"]):not([role="progressbar"]):not([role="meter"]),
[class~="button" i] *:not(i):not([class*="icon" i]):not([class*="fa-" i]):not([class*="symbols" i]):not([class*="glyph" i]):not([class*="mdi" i]):not([class*="bi-" i]):not([class*="status" i]):not([class*="indicator" i]):not([class*="badge" i]):not([class*="dot" i]):not([data-kind]):not([data-status]):not([role="status"]):not([role="progressbar"]):not([role="meter"]),
[class~="btn" i] *:not(i):not([class*="icon" i]):not([class*="fa-" i]):not([class*="symbols" i]):not([class*="glyph" i]):not([class*="mdi" i]):not([class*="bi-" i]):not([class*="status" i]):not([class*="indicator" i]):not([class*="badge" i]):not([class*="dot" i]):not([data-kind]):not([data-status]):not([role="status"]):not([role="progressbar"]):not([role="meter"]),
span[role="button"] *:not(i):not([class*="icon" i]):not([class*="fa-" i]):not([class*="symbols" i]):not([class*="glyph" i]):not([class*="mdi" i]):not([class*="bi-" i]):not([class*="status" i]):not([class*="indicator" i]):not([class*="badge" i]):not([class*="dot" i]):not([data-kind]):not([data-status]):not([role="status"]):not([role="progressbar"]):not([role="meter"]),
a[role="button"] *:not(i):not([class*="icon" i]):not([class*="fa-" i]):not([class*="symbols" i]):not([class*="glyph" i]):not([class*="mdi" i]):not([class*="bi-" i]):not([class*="status" i]):not([class*="indicator" i]):not([class*="badge" i]):not([class*="dot" i]):not([data-kind]):not([data-status]):not([role="status"]):not([role="progressbar"]):not([role="meter"]),
.btn *:not(i):not([class*="icon" i]):not([class*="fa-" i]):not([class*="symbols" i]):not([class*="glyph" i]):not([class*="mdi" i]):not([class*="bi-" i]):not([class*="status" i]):not([class*="indicator" i]):not([class*="badge" i]):not([class*="dot" i]):not([data-kind]):not([data-status]):not([role="status"]):not([role="progressbar"]):not([role="meter"]) {
  background-color: transparent !important; background-image: none !important; box-shadow: none !important;
  border: none !important; text-shadow: none !important; color: inherit !important;
}



        /* Claude Code UI: icon buttons, sidebar items, and footer controls should not inherit solid Tailwind backgrounds
       or look like bulky Win95 buttons until hovered. */
    .cds-root a:not(:hover):not(:active),
    .cds-root button:not(:hover):not(:active),
    .cds-root [role="button"]:not(:hover):not(:active),
    .cds-root [class*="btn" i]:not(:hover):not(:active),
    .cds-root [class*="button" i]:not(:hover):not(:active),
    .cds-root [class*="hover:bg-" i]:not(:hover):not(:active) {
      background: transparent !important;
      border-color: transparent !important;
      box-shadow: none !important;
    }

    /* Claude Code: give .cds-root a solid surface and re-solidify floating panels.
       Only the ROOT gets a bg; descendants keep transparent unless they are a
       known floating surface pattern. This avoids the "inherit everything" crash. */
    .cds-root:not(:root):not(.w) {
      background-color: ${T.background} !important;
      color: ${T.textPrimary} !important;
    }
    .cds-root [data-radix-popper-content-wrapper] > *,
    .cds-root [data-radix-portal] > *,
    .cds-root [data-floating-ui-portal] > *,
    .cds-root [data-state="open"][role],
    .cds-root [class*="popover" i],
    .cds-root [class*="dropdown" i]:not(button),
    .cds-root [class*="modal" i],
    .cds-root [class*="overlay" i]:not([class*="backdrop"]),
    .cds-root [class*="drawer" i],
    .cds-root [class*="panel" i],
    .cds-root [class*="sidebar" i],
    .cds-root [class*="sheet" i] {
      background-color: ${T.backgroundSoft} !important;
      color: ${T.textPrimary} !important;
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
summary:focus-visible, [tabindex]:not([tabindex="-1"]):not(div):not(article):not(section):not(main):not(p):not(blockquote):not(h1):not(h2):not(h3):not(h4):not(h5):not(h6):focus-visible, [role="button"]:focus-visible, [contenteditable]:focus-visible {
  outline: 1px dotted ${T.textPrimary} !important; outline-offset: -4px !important;
}

/* ChatGPT, Claude, Tailwind prose and modern web apps surface & text variable overrides */
:root, html, body, [data-message-author-role], [class*="prose" i], .markdown {
  --main-surface-primary: ${T.background} !important;
  --main-surface-secondary: ${T.backgroundSoft} !important;
  --main-surface-tertiary: ${T.surface} !important;
  --surface-primary: ${T.background} !important;
  --surface-secondary: ${T.backgroundSoft} !important;
  --surface-tertiary: ${T.surface} !important;
  --bg-primary: ${T.background} !important;
  --bg-secondary: ${T.backgroundSoft} !important;
  --bg-tertiary: ${T.surface} !important;
  --text-primary: ${T.textPrimary} !important;
  --text-secondary: ${T.textSecondary} !important;
  --text-tertiary: ${T.textMuted} !important;
  --text-quaternary: ${T.textMuted} !important;
  --text-muted: ${T.textMuted} !important;
  --text-color: ${T.textPrimary} !important;
  --color-text-primary: ${T.textPrimary} !important;
  --color-text-secondary: ${T.textSecondary} !important;
  --token-text-primary: ${T.textPrimary} !important;
  --token-text-secondary: ${T.textSecondary} !important;
  --token-text-tertiary: ${T.textMuted} !important;
  --tw-prose-body: ${T.textPrimary} !important;
  --tw-prose-headings: ${T.textPrimary} !important;
  --tw-prose-lead: ${T.textSecondary} !important;
  --tw-prose-links: ${T.link} !important;
  --tw-prose-bold: ${T.textPrimary} !important;
  --tw-prose-counters: ${T.textSecondary} !important;
  --tw-prose-bullets: ${T.borderHighlight} !important;
  --tw-prose-quotes: ${T.textPrimary} !important;
  --tw-prose-captions: ${T.textMuted} !important;
  --tw-prose-code: ${T.textPrimary} !important;
  --tw-prose-invert-body: ${T.textPrimary} !important;
  --tw-prose-invert-headings: ${T.textPrimary} !important;
  --tw-prose-invert-lead: ${T.textSecondary} !important;
  --tw-prose-invert-links: ${T.link} !important;
  --tw-prose-invert-bold: ${T.textPrimary} !important;
  --tw-prose-invert-counters: ${T.textSecondary} !important;
  --tw-prose-invert-bullets: ${T.borderHighlight} !important;
  --tw-prose-invert-quotes: ${T.textPrimary} !important;
  --tw-prose-invert-captions: ${T.textMuted} !important;
  --tw-prose-invert-code: ${T.textPrimary} !important;
  --tw-prose-invert-pre-code: ${T.textPrimary} !important;
}

/* Inline code snippets (code:not(pre code), kbd, samp) */
p code, li code, blockquote code, td code, dd code, span code, code:not(pre code), kbd, samp {
  display: inline !important;
  box-decoration-break: clone !important;
  -webkit-box-decoration-break: clone !important;
  padding: 0px 4px !important;
  margin: 0 2px !important;
  border: 1px solid ${T.borderMuted} !important;
  background-color: ${T.backgroundSoft} !important;
  color: ${T.textPrimary} !important;
  font-family: ${FONT} !important;
  vertical-align: baseline !important;
  line-height: inherit !important;
}
p, li, dd, dt, blockquote {
  line-height: 1.4 !important;
  color: ${T.textPrimary} !important;
}

/* Force soft theme text on message bubbles, markdown, and white-utility classes */
[data-message-author-role], [data-message-author-role] p,
.markdown, .markdown p, [class*="prose" i], [class*="prose" i] p,
[class*="text-token-text" i], [class*="message" i] p,
[class*="text-gray-100" i], [class*="text-gray-200" i], [class*="text-gray-50" i],
[class*="text-white" i], [class*="dark:text-white" i],
[class*="dark:text-gray-100" i], [class*="dark:text-gray-200" i] {
  color: ${T.textPrimary} !important;
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

/* CodeNomad exposes real session state on this small indicator. Keep that
   semantic signal instead of letting the generic repainter flatten every dot
   to the normal foreground colour. */
.status-indicator.session-status.session-working > .status-dot { background-color: ${T.warning} !important; }
.status-indicator.session-status.session-idle > .status-dot { background-color: ${T.success} !important; }
.status-indicator.session-status.session-compacting > .status-dot { background-color: ${T.accentTeal} !important; }
.status-indicator.session-status.session-permission > .status-dot,
.status-indicator.session-status.session-retrying > .status-dot { background-color: ${T.danger} !important; }

/* Claude Code / Claude Desktop reports thinking on this dot. The wipe above
   spares it so the app's own colour survives; darken the running (thinking)
   state explicitly so it reads as work in progress instead of a bright pin.
   Same warning token CodeNomad's session-working uses, so "thinking" means
   the same colour across both apps. */
.status-dot[data-kind="running"] { background-color: ${T.warning} !important; }

/* Status colours (--success/--warning/--danger) are deliberately NOT applied by
   class-name substring here. '[class*="error" i]' matches 'error-boundary',
   '[class*="valid" i]' matches 'validation-container' — both are large wrappers,
   and painting one solid red or green is exactly the "might help some other site"
   over-reach that already broke two real sites in this file's history (see the
   transition-property note above). Semantic snapping happens in the JS repainter
   instead, gated on the site having ALREADY painted a saturated green/amber/red
   background — i.e. on evidence, not on a name. */

/* ZCode desktop "Usage remaining" popup: the "5 hours" column label. The popup
   has three quota columns (5 hours / Weekly / ZCode MCP) and CSS cannot match
   text, so the one column is picked by the only structural thing that separates
   it from its siblings: the progress bar the renderer paints INLINE with
   var(--color-usage-chart-1) — Weekly is chart-2 and MCP is chart-5, so the
   [style*=...] discriminator is exact. The closing paren in "usage-chart-1)"
   is deliberate: a bare "usage-chart-1" substring would also match
   usage-chart-10..19 if the app ever grows that many chart tokens. Everything
   else in the chain is just the column's own skeleton (label span sits in the
   first row of the column that owns that bar — the value row's "- Sep 18" span
   is in the SECOND row and stays dim), and the whole selector is inert outside
   this app because the class names are ZCode's own utility set. Weekly and MCP
   keep their app colours and stay dim on purpose: the point of this rule is
   that the 5-hour quota — the one that throttles everyday sessions — reads
   first; the repainter spares the chart-token bars so both the colour and this
   rule's anchor survive (see the --color-usage-chart- guard in process()).
   Light orange, mixed from the palette's warm edge and danger text so every
   theme derives its own version instead of one hardcoded literal (see the
   bare-hex gate in tools/check-css.js). Conscious WCAG exception: the mix is
   55% borderHighlight, a role check-css.js deliberately holds outside
   WCAG_ROLES ("never text"), so no gate measures this label's contrast; all
   16 current palettes are dark and compute ~8:1 against the popup surface,
   but a future light palette must re-check this rule by hand. */
div[class*="space-y-1.5"]:has(> div[class*="h-1.5"] > div[style*="usage-chart-1)"]) > div > div:first-child > span[class*="text-foreground-subtle"] {
  color: color-mix(in srgb, ${T.borderHighlight} 55%, ${T.dangerText} 45%) !important;
  font-weight: 700 !important;
}

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
 :root body a:hover { color: ${T.link} !important; text-decoration: underline !important; background-color: transparent !important; }


 html[data-w95-x="1"], html[data-w95-x="1"] body { background-color: ${T.background} !important; color: ${T.textPrimary} !important; }
 html[data-w95-x="1"] body > div, html[data-w95-x="1"] main, html[data-w95-x="1"] header[role="banner"],
 html[data-w95-x="1"] [data-testid="primaryColumn"], html[data-w95-x="1"] [data-testid="sidebarColumn"],
 html[data-w95-x="1"] [data-testid="DMDrawer"], html[data-w95-x="1"] [data-testid="tweetDetail"],
 html[data-w95-x="1"] [data-testid="sheetDialog"], html[data-w95-x="1"] [role="dialog"],
 html[data-w95-x="1"] [role="menu"], html[data-w95-x="1"] [role="listbox"],
 html[data-w95-x="1"] [role="region"], html[data-w95-x="1"] section[role="region"],
 html[data-w95-x="1"] [aria-label*="Settings" i], html[data-w95-x="1"] [aria-label*="Seaded" i] {
   background-color: ${T.backgroundSoft} !important; background-image: none !important; color: ${T.textPrimary} !important;
 }
 html[data-w95-x="1"] [data-testid="primaryColumn"], html[data-w95-x="1"] [data-testid="sidebarColumn"],
 html[data-w95-x="1"] [data-testid="tweetDetail"], html[data-w95-x="1"] [data-testid="sheetDialog"],
 html[data-w95-x="1"] [role="dialog"], html[data-w95-x="1"] [role="menu"], html[data-w95-x="1"] [role="listbox"] {
   background-color: ${T.surface} !important; ${B_OUTER}
 }
 html[data-w95-x="1"] [data-testid="tweet"], html[data-w95-x="1"] [data-testid="cellInnerDiv"] > div,
 html[data-w95-x="1"] [data-testid="cellInnerDiv"], html[data-w95-x="1"] [data-testid="UserCell"] {
   background-color: ${T.surface} !important; color: ${T.textPrimary} !important; border-color: ${T.borderMuted} !important;
 }
 html[data-w95-x="1"] [data-testid="tweetText"], html[data-w95-x="1"] [data-testid="User-Name"],
 html[data-w95-x="1"] [data-testid="UserDescription"] { color: ${T.textPrimary} !important; }
 html[data-w95-x="1"] [data-testid="SearchBox_Search_Input"], html[data-w95-x="1"] [contenteditable="true"],
 html[data-w95-x="1"] input, html[data-w95-x="1"] textarea, html[data-w95-x="1"] select {
   background-color: ${T.compareBack} !important; color: ${T.textPrimary} !important; ${B_SUNK}
 }
 html[data-w95-x="1"] a { color: ${T.link} !important; }
 html[data-w95-x="1"] svg { fill: currentColor !important; }

  html[data-w95-reddit="1"] {
    --color-neutral-content: ${T.textPrimary} !important;
    --color-neutral-content-strong: ${T.textPrimary} !important;
    --color-neutral-content-weak: ${T.textSecondary} !important;
    --color-neutral-content-muted: ${T.textMuted} !important;
    --color-neutral-background: ${T.backgroundSoft} !important;
    --color-neutral-background-weak: ${T.surface} !important;
    --color-neutral-background-strong: ${T.surfaceRaised} !important;
    --color-neutral-background-medium: ${T.surface} !important;
    --color-tone-1: ${T.textPrimary} !important;
    --color-tone-2: ${T.textSecondary} !important;
    --color-tone-3: ${T.textMuted} !important;
    --color-tone-4: ${T.textMuted} !important;
    --color-tone-5: ${T.borderMuted} !important;
    --color-tone-6: ${T.surfaceRaised} !important;
    --color-tone-7: ${T.backgroundSoft} !important;
    --color-primary: ${T.link} !important;
    --color-secondary: ${T.textSecondary} !important;
    --shreddit-content-background: ${T.backgroundSoft} !important;
    --shreddit-post-background: ${T.surface} !important;
  }
  html[data-w95-reddit="1"] shreddit-post, html[data-w95-reddit="1"] shreddit-comment-tree,
  html[data-w95-reddit="1"] shreddit-feed, html[data-w95-reddit="1"] faceplate-tracker,
  html[data-w95-reddit="1"] shreddit-post h1, html[data-w95-reddit="1"] shreddit-post h2,
  html[data-w95-reddit="1"] shreddit-post h3, html[data-w95-reddit="1"] shreddit-post p,
  html[data-w95-reddit="1"] [slot="title"], html[data-w95-reddit="1"] [slot="title"] a,
  html[data-w95-reddit="1"] a[slot="title"], html[data-w95-reddit="1"] a[id*="post-title"],
  html[data-w95-reddit="1"] [id*="post-title"], html[data-w95-reddit="1"] [slot="text-body"],
  html[data-w95-reddit="1"] [slot="text-body"] *, html[data-w95-reddit="1"] [data-testid="post-title"],
  html[data-w95-reddit="1"] [data-testid="post-container"] a, html[data-w95-reddit="1"] [data-testid="post-container"] p,
  html[data-w95-reddit="1"] [slot="comment"], html[data-w95-reddit="1"] .text-neutral-content-strong,
  html[data-w95-reddit="1"] .text-neutral-content {
    color: ${T.textPrimary} !important;
  }
  html[data-w95-reddit="1"] [slot="title"]:hover, html[data-w95-reddit="1"] [slot="title"] a:hover,
  html[data-w95-reddit="1"] a[slot="title"]:hover, html[data-w95-reddit="1"] a[id*="post-title"]:hover,
  html[data-w95-reddit="1"] shreddit-post h1:hover, html[data-w95-reddit="1"] shreddit-post h2:hover,
  html[data-w95-reddit="1"] shreddit-post h3:hover {
    color: ${T.link} !important;
    text-decoration: underline !important;
  }
  /* Reddit card overlays & stretched click-catchers must never be solidified */
  html[data-w95-reddit="1"] a.absolute,
  html[data-w95-reddit="1"] shreddit-post a[class*="absolute" i],
  html[data-w95-reddit="1"] [class*="inset-0" i],
  html[data-w95-reddit="1"] [class*="cover-link" i],
  html[data-w95-reddit="1"] [class*="stretched-link" i] {
    background-color: transparent !important;
    background-image: none !important;
    border: none !important;
    box-shadow: none !important;
  }
  /* Inactive / un-opened hovercards must stay transparent and unbordered */
  faceplate-hovercard:not([enter-done]):not([opened]):not([active]) {
    background-color: transparent !important;
    background-image: none !important;
    border: none !important;
  }
  /* Reddit carousel & community highlights bleed fix */
  html[data-w95-reddit="1"] shreddit-carousel > *,
  html[data-w95-reddit="1"] [class*="highlight" i] {
    background-color: ${T.surface} !important;
  }
  /* Reddit search header input tag alignment and ghost placeholder fix */
  html[data-w95-reddit="1"] reddit-header-large input,
  html[data-w95-reddit="1"] shreddit-app input[type="search"] {
    height: auto !important;
    min-height: 24px !important;
  }
  html[data-w95-reddit="1"] reddit-header-large [class*="placeholder" i],
  html[data-w95-reddit="1"] #header-search [class*="placeholder" i] {
    display: none !important;
  }

  /* Google Search & Material 3 / AI Overview surface tokens */
  html[data-w95-google="1"] {
    --color-surface: ${T.surface} !important;
    --color-surface-variant: ${T.surfaceRaised} !important;
    --color-surface-container: ${T.surface} !important;
    --color-surface-container-high: ${T.surfaceRaised} !important;
    --color-surface-container-highest: ${T.surfaceAlt} !important;
    --color-surface-container-low: ${T.backgroundSoft} !important;
    --color-surface-container-lowest: ${T.background} !important;
    --color-background: ${T.backgroundSoft} !important;
    --color-on-surface: ${T.textPrimary} !important;
    --color-on-surface-variant: ${T.textSecondary} !important;
    --color-on-background: ${T.textPrimary} !important;
    --color-primary: ${T.link} !important;
    --color-outline: ${T.borderMuted} !important;
    --color-outline-variant: ${T.bevelLight} !important;
    --m3c-surface: ${T.surface} !important;
    --m3c-surface-container: ${T.surface} !important;
    --m3c-surface-container-high: ${T.surfaceRaised} !important;
    --m3c-surface-container-highest: ${T.surfaceAlt} !important;
    --m3c-surface-container-low: ${T.backgroundSoft} !important;
    --m3c-surface-container-lowest: ${T.background} !important;
    --m3c-on-surface: ${T.textPrimary} !important;
    --m3c-on-surface-variant: ${T.textSecondary} !important;
    --m3c-outline: ${T.borderMuted} !important;
    --m3c-outline-variant: ${T.bevelLight} !important;
    --g-surface: ${T.surface} !important;
    --g-surface-variant: ${T.surfaceRaised} !important;
    --g-background: ${T.backgroundSoft} !important;
    --g-color-surface: ${T.surface} !important;
    --g-color-background: ${T.backgroundSoft} !important;
    --center-column-background: ${T.backgroundSoft} !important;
    --appbar-background: ${T.surface} !important;
    --header-background: ${T.surface} !important;
  }
  /* Google AI Overview and Follow-up / Ask anything bar */
  html[data-w95-google="1"] form:has([placeholder*="Ask" i]),
  html[data-w95-google="1"] div:has(> form [placeholder*="Ask" i]),
  html[data-w95-google="1"] div:has(> [placeholder*="Ask" i]),
  html[data-w95-google="1"] [aria-label*="Ask" i],
  html[data-w95-google="1"] [data-attrid*="overview" i],
  html[data-w95-google="1"] [class*="conversational" i],
  html[data-w95-google="1"] [class*="follow-up" i],
  html[data-w95-google="1"] [class*="followup" i],
  html[data-w95-google="1"] [jsname]:has([placeholder*="Ask" i]),
  html[data-w95-google="1"] [jscontroller]:has([placeholder*="Ask" i]) {
    background-color: ${T.surface} !important;
    background-image: none !important;
    color: ${T.textPrimary} !important;
    border-color: ${T.borderDark} !important;
    box-shadow: none !important;
  }

  yt-interaction, paper-ripple, .mdc-ripple-surface, .mdc-ripple-upgraded::before, .mdc-ripple-upgraded::after {
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
tp-yt-iron-dropdown, ytcp-menu, ytcp-paper-tooltip, ytcp-navigation-drawer,
[role="menu"], [role="listbox"], [role="tooltip"], [role="dialog"], [role="alertdialog"],
[data-radix-popper-content-wrapper] > *, [data-radix-portal] > *, [data-floating-ui-portal] > *,
.quick-input-widget, .context-view {
  /* Dialog bodies use --surfaceRaised and a RAISED bevel (UI.md windows and
     dialogs) — a floating panel is the most window-like thing on a web page, so
     it gets the full Win95 window edge instead of the old flat 1px outline. */
  background-color: ${T.surfaceRaised} !important; background-image: none !important;
  ${B_OUTER}
}
ytd-popup-container {
  background-color: transparent !important;
  background-image: none !important;
  border: none !important;
  box-shadow: none !important;
}
ytd-popup-container tp-yt-iron-dropdown,
ytd-popup-container ytd-multi-page-menu-renderer,
ytd-popup-container ytd-menu-popup-renderer,
ytd-popup-container ytd-simple-menu-header-renderer,
ytd-multi-page-menu-renderer, ytd-menu-popup-renderer {
  background-color: ${T.surfaceRaised} !important;
  background-image: none !important;
  ${B_OUTER}
}
ytcp-bar-chart, .ytcp-bar-chart, [class*="bar-chart" i], [class*="comparison-bar" i], ytcp-table-cell-compare-period {
  background-color: transparent !important;
}
ytcp-bar-chart .bar, .bar.ytcp-bar-chart, [class*="bar-chart" i] .bar,
[class*="comparison-bar" i] .bar, [class*="bar-container" i] .bar,
ytcp-bar-chart .primary-bar, ytcp-bar-chart .bar-fill,
rect.bar, rect.ytcp-bar-chart, .comparison-bar {
  background-color: ${T.link} !important;
  fill: ${T.link} !important;
  opacity: 1 !important;
  visibility: visible !important;
}
ytcp-bar-chart .previous, ytcp-bar-chart .secondary-bar,
.bar.ytcp-bar-chart.previous-period, [class*="bar-chart" i] .previous,
rect.bar.previous-period {
  background-color: ${T.textMuted} !important;
  fill: ${T.textMuted} !important;
  opacity: 0.7 !important;
  visibility: visible !important;
}
.card, [class~="card" i], [class*="card-" i], [class*="-card" i], [class*="__card" i],
.panel, [class~="panel" i], [class*="panel-" i], [class*="-panel" i], [class*="__panel" i],
[class*="content-box" i], [class*="content-block" i], [class*="info-box" i], [class*="detail-box" i], [class*="data-box" i],
[class*="profile-box" i], [class*="profile-content" i], [class*="user-profile" i],
[class*="subscription" i]:not(a):not(button) {
  background-color: ${T.surface} !important;
  color: ${T.textPrimary} !important;
}
[class*="menu" i]:not(a):not(button):not([class*="item" i]):not([class*="icon" i]),
[class*="dropdown" i]:not(a):not(button), [class*="popup" i], [class*="tooltip" i],
[class*="hovercard" i], [class*="hover-card" i], faceplate-hovercard {
  background-color: ${T.surfaceRaised} !important; background-image: none !important;
}

/* Scrollbars: the track's sunken look came from inset box-shadows, which the
   global zero-shadow rule removes — rebuilt out of 2px bevel borders so the
   depth language is identical to every other control.

   12px, not the Win95-authentic 16px, and that is a deliberate concession. The
   moment ::-webkit-scrollbar is styled at all, Chromium stops drawing OVERLAY
   scrollbars and draws classic ones, which occupy real layout width — so every
   container the app wrote as scrollable grows a permanent gutter it never
   budgeted for. On Antigravity that gutter was wide enough to eat the edge of the
   Settings button. 12px keeps the thumb comfortably grabbable and gives four
   pixels back to every scroll container in the application at once.

   The stepper arrows are GONE (display: none), not restyled. They are the one
   part of a Win95 scrollbar that is pure ornament on a machine with a wheel and a
   trackpad, they cost 32px of track per scrollbar, and — worse — they render on
   the JS-drawn shells below as two little bevelled squares even where there is
   nothing to scroll, which is precisely the "decoration, not a control" the
   report was about. */
::-webkit-scrollbar { width: 12px !important; height: 12px !important; }
::-webkit-scrollbar-track { background: ${T.backgroundSoft} !important; ${B_INNER} }
::-webkit-scrollbar-thumb { background: ${T.surfaceRaised} !important; ${B_OUTER} }
::-webkit-scrollbar-thumb:active { background: ${T.surface} !important; ${B_INNER} }
::-webkit-scrollbar-corner { background: ${T.backgroundSoft} !important; }
::-webkit-scrollbar-button { display: none !important; width: 0 !important; height: 0 !important; }

/* JS-DRAWN SCROLLBARS THAT ARE NOT SCROLLBARS YET.
   Monaco (VS Code, Antigravity, and every embedded editor on the web) does not use
   a native scrollbar: it renders its own shells and keeps them in the DOM at all
   times, hidden by opacity/visibility until there is something to scroll. Our
   surface + bevel rules paint those shells unconditionally, so they turn into
   permanent Win95 scrollbars that scroll nothing -- decoration, exactly as
   reported in Antigravity. Handing these back to the app is the only correct
   move: it already knows when they should be visible. */
.monaco-scrollable-element > .scrollbar,
.monaco-scrollable-element > .scrollbar > .slider,
.monaco-scrollable-element > .invisible {
  background: transparent !important;
  background-color: transparent !important;
  border: 0 !important;
  box-shadow: none !important;
}
.monaco-scrollable-element > .scrollbar.invisible { visibility: hidden !important; }
.monaco-scrollable-element > .scrollbar > .slider { background-color: ${T.surfaceRaised} !important; }

/* 🚨 SURFACE FLATTENING — LIGHT DOM 🚨
   This pair used to live only in SHADOW_CSS and reached these apps by being
   concatenated into the document sheet, which was a mistake for a different reason
   (see tools/build-desktop.js). The concatenation is gone; the rules are wanted, so
   they are stated HERE, where a document stylesheet is what they were always going
   to be, and with the guards a document needs and a shadow tree does not.
   Removing them wholesale was itself a regression: CodeNomad and Antigravity lost
   the flattening that makes an app read as one surface instead of a stack of
   vendor greys.
   Three guards, each paid for: :not(:root) keeps the document root out of it — an
   inherit handed to the root computes to black and drags the whole page down with
   it. The state-marker exclusions keep a status dot's background, which is the only
   thing carrying its meaning. And the floating surfaces are re-solidified straight
   after, or menus and tooltips render see-through with the text behind them showing
   through. */
div:not([class*="status" i]):not([class*="indicator" i]):not([class*="badge" i]):not([class*="dot" i]):not([data-kind]):not([data-status]):not([role="status"]):not([role="progressbar"]):not([role="meter"]),
span:not([class*="status" i]):not([class*="indicator" i]):not([class*="badge" i]):not([class*="dot" i]):not([data-kind]):not([data-status]):not([role="status"]):not([role="progressbar"]):not([role="meter"]),
section:not([class*="status" i]):not([class*="indicator" i]):not([class*="badge" i]):not([class*="dot" i]):not([data-kind]):not([data-status]):not([role="status"]):not([role="progressbar"]):not([role="meter"]),
article:not([class*="status" i]):not([class*="indicator" i]):not([class*="badge" i]):not([class*="dot" i]):not([data-kind]):not([data-status]):not([role="status"]):not([role="progressbar"]):not([role="meter"]),
aside:not([class*="status" i]):not([class*="indicator" i]):not([class*="badge" i]):not([class*="dot" i]):not([data-kind]):not([data-status]):not([role="status"]):not([role="progressbar"]):not([role="meter"]),
nav:not([class*="status" i]):not([class*="indicator" i]):not([class*="badge" i]):not([class*="dot" i]):not([data-kind]):not([data-status]):not([role="status"]):not([role="progressbar"]):not([role="meter"]),
header:not([class*="status" i]):not([class*="indicator" i]):not([class*="badge" i]):not([class*="dot" i]):not([data-kind]):not([data-status]):not([role="status"]):not([role="progressbar"]):not([role="meter"]),
footer:not([class*="status" i]):not([class*="indicator" i]):not([class*="badge" i]):not([class*="dot" i]):not([data-kind]):not([data-status]):not([role="status"]):not([role="progressbar"]):not([role="meter"]),
main:not([class*="status" i]):not([class*="indicator" i]):not([class*="badge" i]):not([class*="dot" i]):not([data-kind]):not([data-status]):not([role="status"]):not([role="progressbar"]):not([role="meter"]) {
  /* Blanket wipe retired (T-121). JS repainter handles backgrounds accurately now. */
}


`;

  // ─── SHADOW DOM MINIMAL CSS ──────────────────────────────────────────────────
  const SHADOW_CSS = `
    /* Height-only 1ms transition + near-zero animation (see GLOBAL_CSS motion
       note): transitionend/animationend keep firing for collapse + rc-motion
       state machines, without touching top/left/width/transform. */
    /* animation-fill-mode: forwards for the same snapback reason as the global
       layer -- a shadow tree reveals its content the same way a light one does. */
    * { border-radius: 0 !important; transition-property: height, max-height, min-height !important; transition-duration: 0.001s !important; transition-delay: 0s !important; animation-duration: 0.001s !important; animation-delay: 0s !important; animation-iteration-count: 1 !important; animation-fill-mode: forwards !important; }
    /* Zero shadow / zero blur, same as the global layer (UI.md law 2). Shadow
       roots are where modern component libraries keep their elevation, so
       skipping this here would leave every web-component card floating while the
       rest of the page is flat. */
    *, *::before, *::after { box-shadow: none !important; text-shadow: none !important; backdrop-filter: none !important; -webkit-backdrop-filter: none !important; }
    *:not(img):not(svg):not(video):not(canvas):not(picture):not(image), *::before, *::after { filter: none !important; }
    /* Type ladder, same five steps and the same disjoint-selector trick as the
       global layer (see the specificity note there — layering the exceptions on
       top instead silently flattens every heading to 12px). */
    *:not(svg):not(path):not(i):not(h1):not(h2):not(h3):not(h4):not(h5):not(h6):not(small):not(sub):not(sup):not(figcaption):not([class*="icon" i]):not([class*="fa-" i]):not([class*="symbols" i]):not([class*="glyph" i]):not([class*="mdi" i]):not([class*="bi-" i]):not([class*="codicon" i]):not([class*="lucide" i]):not([class*="octicon" i]):not([class*="remixicon" i]):not([class*="phosphor" i]):not([class*="iconify" i]):not([class*="feather" i]):not([data-icon]):not([data-cds="Icon"]) {
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
    :host b, :host strong, :host p, :host li, :host dd, :host dt, :host h1, :host h2, :host h3, :host h4, :host h5, :host h6 { color: ${T.textPrimary} !important; }
    :host i, :host em, :host cite, :host var, :host dfn, :host q, :host blockquote { font-style: italic !important; }
    /* No 99,999-second hover freeze here either. Shadow-tree pseudo-elements
       are exactly where shimmer loaders and decorative hover layers tend to live,
       so keeping permanent transitions here is especially expensive. */
    *:not(svg):not(path):not(i):not([class*="icon" i]):not([class*="fa-" i]):not([class*="symbols" i]):not([class*="glyph" i]):not([class*="mdi" i]):not([class*="bi-" i]):not([class*="codicon" i]):not([class*="lucide" i]):not([class*="octicon" i]):not([class*="remixicon" i]):not([class*="phosphor" i]):not([class*="iconify" i]):not([class*="feather" i]):not([data-icon]):not([data-cds="Icon"]) {
      font-family: ${FONT} !important; -webkit-font-smoothing: none !important; -moz-osx-font-smoothing: unset !important; font-smooth: never !important; text-rendering: optimizeSpeed !important;
    }
    input, textarea, select, option, button, code, pre, kbd, samp, tt, [class*="code" i], [class*="mono" i] { font-family: ${FONT} !important; }
     :host {
       --radius: 0px; --shreddit-border-radius: 0px; --md-sys-shape-corner-full: 0px;
       --color-neutral-content: ${T.textPrimary}; --color-neutral-content-strong: ${T.textPrimary};
       --color-neutral-content-weak: ${T.textSecondary}; --color-neutral-content-muted: ${T.textMuted};
       --color-tone-1: ${T.textPrimary}; --color-tone-2: ${T.textSecondary};
       --color-neutral-background: ${T.backgroundSoft}; --color-neutral-background-weak: ${T.surface};
       --shreddit-content-background: ${T.backgroundSoft}; --shreddit-post-background: ${T.surface};
       --m3c-surface: ${T.surface}; --m3c-surface-container: ${T.surface}; --color-surface: ${T.surface};
       background-color: transparent !important; background-image: none !important; color: ${T.textPrimary} !important;
     }
     [slot="title"], [slot="title"] a, a[slot="title"], a[id*="post-title"], [id*="post-title"] {
       color: ${T.textPrimary} !important;
     }
    /* Ad-iframe load-flash fix, scoped to known ad hosts only — see GLOBAL_CSS note (unconditional would break transparent widget overlays) */
    iframe[src*="doubleclick.net" i], iframe[src*="googlesyndication.com" i],
    iframe[src*="google.com/ads" i], iframe[id*="google_ads_iframe" i],
    iframe[id*="gpt_unit" i], iframe[src*="adservice.google" i],
    iframe[src*="amazon-adsystem.com" i], iframe[src*="taboola.com" i],
    iframe[src*="outbrain.com" i] {
      background-color: ${T.backgroundSoft} !important;
    }
    /* 🚨 :not(:root) IS LOAD-BEARING, DO NOT DROP IT 🚨
       Inside a shadow tree an attribute selector can never match the document root,
       so this guard costs nothing there — but this stylesheet does not only live in
       shadow trees. tools/build-desktop.js CONCATENATES GLOBAL_CSS + SHADOW_CSS into
       the single sheet the Electron shim injects into a whole document, and there
       [class] matches <html class="dark"> like any other element. The root then gets
       color: inherit with nothing above it to inherit from, so it computes to the
       INITIAL value — black — and every descendant inherits that same black through
       this very rule. background-color: transparent does the same to the root's
       background.
       That is what made Claude unreadable: black text on the themed brown, immune
       even to an inline important because the sheet is injected at user origin
       there. Proved live over CDP: removing the class attribute from <html> turned
       the whole transcript from rgb(0,0,0) to rgb(212,200,154) and restoring it put
       the black back. Apps whose <html> carries no class (the Electron shell,
       about:blank) were untouched, which is exactly why it read as a Claude-specific
       mystery for eight rounds. :root is never a thing to hand inherit to.
       (No backticks in this comment: it sits inside a template literal and one would
       end it. node --check caught that too, on the very same edit.) */
    div, span, section, article, aside, nav, header, footer, main {
      /* Blanket wipe retired (T-121) */
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
    /* Same exclusions as the light-DOM wipe retired in T-121 */

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
    *::selection, ::selection { background-color: ${T.selection} !important; color: ${T.textPrimary} !important; }

    /* Hover recolor stays zeroed out here too — only real clickable controls respond. */
    button:hover, shreddit-button:hover, .btn:hover { background-color: ${T.surfaceAlt} !important; ${B_OUTER} }
    a, a:link { color: ${T.link} !important; text-decoration: none !important; }
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

  // Late CSS from the site wins over ours at equal specificity purely by being
  // later in the document, so the theme has to end up last. It used to buy that
  // by appending a SECOND COMPLETE COPY of GLOBAL_CSS -- 44 KB of selectors
  // parsed, stored and matched twice against every element, for the whole life
  // of the page. Measured on a 3200-element harness, the theme roughly doubled
  // the cost of a style recalculation (22.9ms -> 47.8ms) and half of that was
  // paying for the same sheet twice. On a long chat the recalculation is far
  // bigger and it is charged on every hover, caret blink and DOM change --
  // reported as the CPU pinned at idle on chatgpt.com.
  //
  // Being last is a POSITION, not a copy. Moving the one sheet we already have
  // to the end of <head> buys the identical cascade order for nothing.
  function injectLate() {
    try {
      const existing = document.querySelector('style[data-w95="global"]');
      const target = document.head || document.documentElement;
      if (!target) return;
      if (existing) {
        // Already last? Then there is nothing to do and no reason to touch the DOM.
        if (target.lastElementChild !== existing) target.appendChild(existing);
        return;
      }
      // The early injection never happened (document-start raced a hostile page).
      injectStyle(document, 'global', GLOBAL_CSS);
      const s = document.querySelector('style[data-w95="global"]');
      if (s && target.lastElementChild !== s) target.appendChild(s);
    } catch (e) { }
  }
  // --- REPAINTER START ---

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

  const JS_SKIP_SELECTOR = '#movie_player, .html5-video-player, ytd-player, ytd-thumbnail, yt-img-shadow, ytd-avatar-shape, yt-avatar-shape, #avatar, #author-thumbnail, ytd-logo, yt-icon, yt-icon-shape, ytcp-bar-chart, .ytcp-bar-chart, [class*="bar-chart" i], [class*="comparison-bar" i], [class*="trend-cell" i], ytcp-table-cell-compare-period, [class*="screen-pause" i], [class*="player-screen" i], [class*="video-screen" i], [class*="vjs-text-track" i], [class*="inset-0" i], [class*="stretched-link" i], [class*="cover-link" i]';
  const SHADOW_SKIP_TAGS = new Set(['YTD-LOGO', 'YT-ICON', 'YT-ICON-SHAPE', 'YT-IMG-SHADOW', 'YTD-AVATAR-SHAPE', 'YT-AVATAR-SHAPE', 'VIDEO', 'AUDIO', 'CANVAS', 'IFRAME']);
  const TAG_SKIP = /^(IMG|VIDEO|CANVAS|PICTURE|IFRAME|SVG|PATH|CIRCLE|RECT|LINE|POLYGON|POLYLINE|ELLIPSE|DEFS|SYMBOL|USE|STYLE|SCRIPT|LINK|META|HEAD|HTML|BR|HR|WBR|TEMPLATE|NOSCRIPT|AUDIO|SOURCE|TRACK|OPTION|OPTGROUP)$/i;

  const piercedRoots = new Set();

  // PERF-004 (SRC-004): the observer options are declared ONCE, here, because
  // the registration has to be rebuilt later (see pruneShadowRegistry) and a
  // rebuild that does not match the original registration silently changes what
  // is observed. Declared beside piercedRoots rather than beside the observer so
  // pierceShadow -- which sits above the observer -- can read it without a TDZ
  // ReferenceError.
  const SHADOW_OBS_OPTS = {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ['class', 'bgcolor', 'background', 'style']
  };

  function pierceShadow(host) {
    const tag = (host.tagName || '').toUpperCase();
    if (SHADOW_SKIP_TAGS.has(tag)) return;
    if (!host.shadowRoot || piercedRoots.has(host.shadowRoot)) return;
    piercedRoots.add(host.shadowRoot);
    try {
      injectStyle(host.shadowRoot, 'shadow', SHADOW_CSS);
      if (!CSS_ONLY_MODE) {
        shadowObserver.observe(host.shadowRoot, SHADOW_OBS_OPTS);
        stylesDirty = true;
      }
    } catch (e) { noteSuppressed('shadowPierceThrows', e); }
  }


  // ─── :hover RULE SURGERY (v29.1) ────────────────────────────────────────────
  // Strips paint properties out of every readable :hover rule so sites cannot
  // flashbang-highlight on hover. Functional props (display, visibility,
  // opacity, transform) are left untouched so hover-opened menus keep working.
  // Cross-origin sheets that throw on cssRules access are covered by the CSS
  // freeze rule in GLOBAL_CSS/SHADOW_CSS instead.
  const HOVER_PAINT = /^(background|box-shadow|filter|backdrop-filter|color|border|outline|text-decoration|text-shadow|--)/;
  const sheetSeen = new WeakMap(); // sheet -> { gen, count } at last pass
  // PERF-010: same-count stylesheet replacement (CSSStyleSheet.replace /
  // replaceSync, or STYLE text replacement) is a normal mutation shape and
  // must invalidate the per-sheet hover-surgery cache. cssRules.length is
  // not a generation identifier: it can stay constant while every rule is
  // rewritten. We instrument the CSSStyleSheet prototype once at startup to
  // bump a per-sheet generation token whenever ANY rule-mutating API runs.
  // stripHoverSheets then re-walks the sheet whenever either length or
  // generation changes, instead of silently skipping same-count changes.
  if (typeof CSSStyleSheet !== 'undefined' && CSSStyleSheet.prototype && !CSSStyleSheet.prototype.__wintageInstrumented) {
    CSSStyleSheet.prototype.__wintageInstrumented = true;
    const bump = function (sheet) {
      try { sheet.__wintageGen = (sheet.__wintageGen || 0) + 1; } catch (e) { }
    };
    const proto = CSSStyleSheet.prototype;
    if (typeof proto.replace === 'function' && !proto.__wintagePatchedReplace) {
      const origReplace = proto.replace;
      proto.replace = function () { const r = origReplace.apply(this, arguments); bump(this); return r; };
      proto.__wintagePatchedReplace = true;
    }
    if (typeof proto.replaceSync === 'function' && !proto.__wintagePatchedReplaceSync) {
      const origReplaceSync = proto.replaceSync;
      proto.replaceSync = function () { const r = origReplaceSync.apply(this, arguments); bump(this); return r; };
      proto.__wintagePatchedReplaceSync = true;
    }
    if (typeof proto.insertRule === 'function' && !proto.__wintagePatchedInsert) {
      const origInsert = proto.insertRule;
      proto.insertRule = function () { const r = origInsert.apply(this, arguments); bump(this); return r; };
      proto.__wintagePatchedInsert = true;
    }
    if (typeof proto.deleteRule === 'function' && !proto.__wintagePatchedDelete) {
      const origDelete = proto.deleteRule;
      proto.deleteRule = function () { const r = origDelete.apply(this, arguments); bump(this); return r; };
      proto.__wintagePatchedDelete = true;
    }
  }
  // STYLE text replacements mutate the ownerNode's sheet under the hood; the
  // sibling instrumentations above already cover that case because the
  // browser dispatches a corresponding API call. We additionally bump the
  // sheet's generation when a <style> element's text is set, because some
  // engines bypass the prototype patch in that path.
  function bumpStyleElementSheets(root) {
    if (!root || !root.querySelectorAll) return;
    const els = root.querySelectorAll('style');
    for (let i = 0; i < els.length; i++) {
      const el = els[i];
      if (el.__wintageLastText !== el.textContent) {
        el.__wintageLastText = el.textContent;
        try { if (el.sheet) el.sheet.__wintageGen = (el.sheet.__wintageGen || 0) + 1; } catch (e) { noteSuppressed('sheetGenThrows', e); }
      }
    }
  }

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
      if (r.type === 7) continue; // CSSRule.KEYFRAMES_RULE has no :hover rules
      try {
        if (r.selectorText && r.selectorText.indexOf(':hover') !== -1) stripHoverRule(r);
        if (r.cssRules && r.cssRules.length) walkRules(r); // @media/@supports/@layer/nesting
      } catch (e) { noteSuppressed('hoverWalkThrows', e); }
    }
  }

  // Returns true when at least one sheet had changed since the last pass — the
  // caller treats that as "late CSS is still landing" and requests a force
  // re-verify (v1.3.0). On a settled page it returns false every time, which is
  // what lets the expensive pass go quiet.
  function stripHoverSheets(root) {
    let changed = false;
    bumpStyleElementSheets(root);
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
        const gen = sheet.__wintageGen || 0;
        const seen = sheetSeen.get(sheet);
        // PERF-010: a same-length sheet that was rewritten still invalidates
        // the cache (the old length-only check silently skipped it). The
        // generation token is bumped by the prototype-instrumented mutators
        // and by bumpStyleElementSheets; any of them invalidates this pass.
        if (seen && seen.gen === gen && seen.count === count) continue;
        sheetSeen.set(sheet, { gen, count });
        changed = true;
        if (!seen || seen.count > count || seen.gen !== gen) {
          walkRules(sheet); // first sight, rules removed, or same-count rewrite: full walk
        } else {
          // CSS-in-JS engines insertRule constantly; re-walking the whole sheet
          // every tick was a jank source. Walk the appended rules only.
          try {
            const rules = sheet.cssRules;
            for (let r = seen.count; r < count; r++) {
              const rule = rules[r];
              if (rule.selectorText && rule.selectorText.indexOf(':hover') !== -1) stripHoverRule(rule);
              if (rule.cssRules && rule.cssRules.length) walkRules(rule);
            }
          } catch (e) { noteSuppressed('hoverAppendThrows', e); }
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
          w.push(el, 'background-color', isIconish(el) ? T.textPrimary : T.surfaceRaised);
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
    // actually covering content it does not own. The same test is part of the
    // repainter block below, which build-desktop.js extracts (REPAINTER
    // START/END) and ships inside the Electron shim; there it is the whole
    // mechanism -- FLOAT_FIX was folded into the repainter and no longer exists
    // as a separate patch.
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
          let isOverMediaOrCanvas = false;
          for (let k = at + 1; at >= 0 && k < stack.length; k++) {
            const u = stack[k];
            if (u.tagName === 'VIDEO' || u.tagName === 'AUDIO' || u.tagName === 'CANVAS' ||
                u.tagName === 'IMG' || u.tagName === 'PICTURE' || u.tagName === 'SVG' ||
                (u.closest && u.closest('video, audio, canvas, img, picture, svg')) ||
                (u.querySelector && u.querySelector('video, audio, canvas, img, picture, svg'))) {
              isOverMediaOrCanvas = true;
              break;
            }
          }
          if (!isOverMediaOrCanvas) {
            for (let k = at + 1; at >= 0 && k < stack.length; k++) {
              const under = stack[k];
              if (under === document.body || under === document.documentElement) continue;
              if (under.contains(el)) continue;
              // Internal card/post layers (stretched links, click-catchers, card overlays)
              // share an ancestor card/post/article with under: solidifying them obscures the card text.
              const elComp = el.closest && el.closest('article, [class*="card" i], [class*="post" i], [class*="item" i], shreddit-post');
              const underComp = under.closest && under.closest('article, [class*="card" i], [class*="post" i], [class*="item" i], shreddit-post');
              if (elComp && underComp && elComp === underComp) continue;
              if (el.tagName === 'A' ||
                  (el.matches && el.matches('[class*="inset-0" i], [class*="stretched-link" i], [class*="cover-link" i]'))) {
                continue;
              }
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
      // ZCode's usage popup binds its quota-bar fills INLINE to the app's own
      // chart token: style="background-color: var(--color-usage-chart-1)".
      // Re-grading those would do two harms at once: overwrite the var()
      // reference in the style ATTRIBUTE with a resolved literal (destroying
      // the exact substring the GLOBAL_CSS "5 hours" label rule anchors on, so
      // the label would dim itself again after the next sweep and re-orange on
      // every React remount), and flatten the three quota bars into one
      // palette shade, killing the per-column distinction the popup exists
      // for. The token family is scoped, not a blanket var() exemption, so
      // nothing else on any other site changes behaviour.
      if (!(bg && el.style && /var\(--color-usage-chart-/i.test(el.style.backgroundColor || ''))) {
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
    if (el.namespaceURI === 'http://www.w3.org/2000/svg' && tag !== 'SVG') return true;
    if (tag === 'INPUT') {
      const t = (el.type || '').toLowerCase();
      // Natively-rendered controls: repainting them hides the checked state.
      // checkbox/radio are handled specially in process() (need computed
      // style to tell a real control from a hidden custom-switch proxy).
      if (t === 'range' || t === 'color' || t === 'file') return true;
    }
    if (el.closest && el.closest('button')) return true;
    if (el.closest && el.closest('video, audio')) return true;
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
  const MUTATION_RECORD_LIMIT = 10000;
  const MUTATION_WORK_LIMIT_MS = 600;
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
    // PERF-007 (SRC-002): suspension is permanent for the page. Without a
    // future runSweeper to prune, every still-tracked piercedRoots entry would
    // keep its shadow subtree and style objects alive forever. Drop the
    // registry now so detached DOM can be GC'd; the live roots keep whatever
    // was already injected into them.
    try { piercedRoots.clear(); } catch (e) { }
    try { forceRootCursors.clear(); } catch (e) { }
    // SRC-006:R010: the lap workset is the same class of retention (a live
    // array of roots nothing will ever drain once the lane is dead).
    forceLapWorkset = null;
    forceLapIndex = 0;
    forceLapRemaining = 0;
    // PERF-003 (SRC-004): the light registry is the same class of retention --
    // a Set of elements that nothing will ever drain once the lane is dead.
    try { lightDirty.clear(); } catch (e) { }
    forceLapActive = false;
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

  // PERF-004 (SRC-004): detached shadow roots had TWO retention owners and only
  // one of them was ever released. runSweeper pruned piercedRoots and
  // forceRootCursors, but MutationObserver has no per-target unobserve, so the
  // detached root stayed a registered target of the shared shadowObserver until
  // the whole observer was disconnected -- i.e. until suspendRepainter or the
  // page died. Worse, onMutations handled no removedNodes at all, so a quiet
  // removal scheduled no cleanup: a measured removal-only batch produced zero
  // force requests and zero light requests, and the registry only shrank when
  // some unrelated work happened to run a sweep.
  //
  // The repair is deliberately NOT a walk of every removed subtree (that costs
  // O(removed nodes) on exactly the batches that are already large). It scans
  // piercedRoots -- bounded by how many roots we pierced -- drops the
  // disconnected ones, and if any went away rebuilds the shared observer's
  // registration from the survivors. Pending records are taken before the
  // disconnect and handed straight back to onMutations, so a legitimate shadow
  // mutation delivered in the same tick is not dropped.
  let shadowPruneQueued = false;
  function pruneShadowRegistry() {
    shadowPruneQueued = false;
    if (repainterSuspended) return;
    let removedAny = false;
    piercedRoots.forEach(root => {
      try {
        if (!root.host || !root.host.isConnected) {
          piercedRoots.delete(root);
          forceRootCursors.delete(root);
          removedAny = true;
        }
      } catch (e) { }
    });
    if (!removedAny || CSS_ONLY_MODE) return;
    try {
      const pending = shadowObserver.takeRecords();
      shadowObserver.disconnect();
      piercedRoots.forEach(root => {
        try { shadowObserver.observe(root, SHADOW_OBS_OPTS); } catch (e) { }
      });
      if (pending && pending.length) onMutations(pending);
    } catch (e) { }
  }
  function requestShadowPrune() {
    if (shadowPruneQueued || repainterSuspended || !piercedRoots.size) return;
    shadowPruneQueued = true;
    // Bounded, one-shot, and never a poll: only a batch that actually carried
    // removals gets here.
    setTimeout(pruneShadowRegistry, 250);
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
      // PERF-003 (SRC-002): a single MutationRecord's addedNodes can be tens
      // of thousands of elements (framework bulk-insert / virtualised list
      // mount). The 500-node budget used to be enforced only during process()
      // after every element had already been pushed into the unbounded `added`
      // array AND a Set built from it. Bound the collection walk itself:
      // stop retaining node refs the moment ADDED_NODE_BUDGET is reached,
      // mark the batch truncated, and request a deferred force reverify.
      // A truncated batch with STYLE/LINK nodes (even beyond the cutoff) must
      // still mark stylesDirty so the deferred sweep re-checks.
      let collectionBudget = ADDED_NODE_BUDGET;
      let addedTruncatedDuringCollection = false;
      let addedCollected = 0;
      let removalSeen = false;
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
              // PERF-005 (SRC-002): the cooldown contract promised the next
              // light sweep would revisit. There was no such request. Now
              // there is: requestLightSweep coalesces and stays floor-limited.
              // PERF-003 (SRC-004): register the element explicitly so the
              // light pass does not have to rediscover it with a document-wide
              // negative selector.
              markLightDirty(t);
              requestLightSweep();
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
            if (target.hasAttribute && target.hasAttribute('data-w95')) continue;
            const tag = (target.tagName || '').toUpperCase();
            if (tag === 'STYLE' || (tag === 'LINK' && (target.rel || '').toLowerCase().includes('stylesheet'))) {
              styleishAdded = true;
            }
          }
          // PERF-004 (SRC-004): a batch that carried removals schedules ONE
          // bounded shadow-registry cleanup. Only the FACT of a removal is read
          // here -- never the removed nodes themselves, which is what keeps this
          // O(1) per record on exactly the batches that are already large.
          if (m.removedNodes && m.removedNodes.length) removalSeen = true;
        }
        for (let ni = 0; ni < m.addedNodes.length; ni++) {
          // PERF-002 (SRC-004): STOP at the budget. The previous loop kept
          // iterating every remaining entry after the 500th just to discover it
          // existed -- measured on one 20,000-node childList record:
          // iteratedAddedNodes = 20,000 for processCalls = 500. The tail is now
          // never touched, so intake cost stops scaling with the size of a
          // framework bulk insert. Nothing is lost: truncation requests a force
          // sweep below, and a force pass re-scans stylesheets unconditionally
          // (scanStyles = force || stylesDirty), which is what the old per-node
          // tail peek for STYLE/LINK was protecting.
          //
          // The record loop itself continues -- attribute records after this
          // point still need their process() call, and that walk is bounded by
          // MUTATION_RECORD_LIMIT rather than by node cardinality.
          if (addedCollected >= collectionBudget) { addedTruncatedDuringCollection = true; break; }
          const node = m.addedNodes[ni];
          if (node.nodeType !== 1) continue;
          if (node.hasAttribute && node.hasAttribute('data-w95')) continue;
          added.push(node);
          addedCollected++;
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
        if (styleishAdded || addedTruncated || addedTruncatedDuringCollection) {
          stylesDirty = stylesDirty || styleishAdded;
          requestForceSweep();
        }
      }
      flushWrites(w);
      if (removalSeen) requestShadowPrune();
      addWorkPressure(performance.now() - workStarted, 'mutation-work');
    }, 60);
  }
  const mainObserver = new MutationObserver(onMutations);
  const shadowObserver = new MutationObserver(onMutations);

  if (!CSS_ONLY_MODE) {
    const obsTarget = document.documentElement || document;
    mainObserver.observe(obsTarget, {
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
  // SRC-006:R010: element work is not the only per-slice cost. Root-LEVEL work
  // (disconnected-root pruning, hover-sheet processing, workset construction,
  // iteration from root zero, the completion scan) used to run over ALL
  // pierced roots on EVERY force continuation slice, so with many ShadowRoots
  // a tiny element budget still paid O(R) per slice. Root work gets its own
  // hard per-slice bound: at most FORCE_ROOT_BUDGET roots are served per
  // slice, and a lap keeps a persistent ordered workset + cursor so
  // continuation slices resume where the previous one stopped.
  const FORCE_ROOT_BUDGET = 64;
  const LIGHT_MAX_NODES = FORCE_BUDGET;
  const forceRootCursors = new Map();
  let forceLapActive = false;
  let forceLapWorkset = null;   // ordered roots of the CURRENT lap (document once, then a registry snapshot)
  let forceLapIndex = 0;        // cursor into forceLapWorkset; advances monotonically within a lap
  let forceLapRemaining = 0;    // roots not yet done/dropped in this lap; O(1) completion detection

  let forcePassesOwed = 0;
  let lightPending = false;
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

  function scheduleSweep(delay, kind) {
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

      // PERF-005 (SRC-002): force debt drains first. A pending light request
      // is only skipped when a force pass just ran and there is still debt,
      // because the force pass is a superset of the light work.
      const force = forcePassesOwed > 0;
      if (force) forcePassesOwed--;

      // PERF-003 (SRC-004): CONSUME the light token before the pass it caused.
      // It used to be read again after runSweeper returned, so the still-true
      // token scheduled a second identical pass -- measured: one isolated
      // requestLightSweep() produced 2 timer callbacks and 2 sweeps, the second
      // re-running the full dirty selector with nothing left to do. Re-arming
      // now happens only if a NEW request arrived DURING the pass.
      if (!force) lightPending = false;

      runSweeper(force);

      // Drainable scheduler (PERF-005): after a light pass, re-arm only when a
      // light request arrived while this pass was running (lightPending was
      // cleared above, so a true value can only come from during-pass work) or
      // bounded dirty work remains. After a force pass that exhausted its
      // budget, runSweeper already re-armed itself when incomplete.
      if (!force && (lightPending || lightDirty.size)) {
        lightPending = false;
        lastSweepEnd = Date.now();
        scheduleSweep(MIN_SWEEP_GAP, 'light');
        return;
      }
      lastSweepEnd = Date.now();

      // No automatic reschedule here. Fresh work comes from mutations,
      // stylesheet loads, visibility changes, or the explicit load-time passes.
    }, d);
  }

  // A request means "there is fresh work, revisit soon" — soon being the fast
  // lane, NEVER immediately. runSweeper itself calls this (via stripHoverSheets
  // spotting a changed sheet), so an immediate schedule here is a direct
  // sweep-calls-sweep loop.
  //
  function requestForceSweep() {
    if (repainterSuspended) return;
    if (forcePassesOwed < 1) forcePassesOwed = 1;
    forceLapActive = true;
    scheduleSweep(1500, 'force');
  }

  // PERF-005: attrCooldown relies on "the next light sweep" to revisit an
  // element whose attribute toggled during cooldown, but no such sweep was
  // ever scheduled. This is the missing bounded light-work request: mark
  // lightPending and re-arm. It coalesces (one timer), stays floor-limited,
  // and a light pass never turns into an endless force cycle.
  //
  // PERF-003 (SRC-004): the light lane now carries its OWN bounded dirty
  // registry instead of rediscovering work with a document-wide negative
  // selector. `root.querySelectorAll('*:not([data-w95-done])')` materialised
  // the COMPLETE matching NodeList before the 2500-node budget was consulted --
  // measured at 12,000 materialised matches for 2,500 process() calls -- and on
  // a settled page it still made the selector engine walk every root to return
  // nothing. Every caller that clears the done marker without immediately
  // re-processing registers the element here, so discovery is O(dirty), not
  // O(document). Past the cap the work is promoted ONCE to the force lane,
  // which is a strict superset and already incremental.
  const LIGHT_DIRTY_MAX = 2000;
  const lightDirty = new Set();
  function markLightDirty(el) {
    if (!el || el.nodeType !== 1) return;
    if (lightDirty.size >= LIGHT_DIRTY_MAX) { requestForceSweep(); return; }
    lightDirty.add(el);
  }
  function requestLightSweep() {
    if (repainterSuspended || document.hidden) return;
    if (lightPending) { if (!sweepTimer) scheduleSweep(MIN_SWEEP_GAP, 'light'); return; }
    lightPending = true;
    scheduleSweep(MIN_SWEEP_GAP, 'light');
  }

  function runSweeper(force) {
    if (repainterSuspended) return;
    const sweepStarted = performance.now();
    const scanStyles = force || stylesDirty;
    const w = [];
    if (!force) {
      if (stylesDirty) {
        stylesDirty = false;
        stripHoverSheets(document);
        piercedRoots.forEach(root => { try { stripHoverSheets(root); } catch (e) { } });
      }
      // PERF-003 (SRC-004): the light lane drains its OWN bounded registry and
      // never touches the root list. The old form ran
      // `root.querySelectorAll('*:not([data-w95-done])')` for EVERY search root,
      // which materialises the complete matching NodeList BEFORE the budget is
      // consulted -- measured at 12,000 materialised matches to do 2,500 units
      // of work -- and on a settled document it still made the selector engine
      // walk every root to return nothing. The registry holds exactly the
      // elements that lost their done marker without being re-processed,
      // wherever they live, so shadow roots are covered without a per-root
      // query. An overflow was already promoted to the force lane at
      // registration time.
      let remaining = LIGHT_MAX_NODES;
      let incomplete = false;
      for (const el of lightDirty) {
        if (remaining <= 0) { incomplete = true; break; }
        lightDirty.delete(el);
        if (!el.isConnected) continue;
        try { process(el, false, w); } catch (e) { }
        remaining--;
      }
      flushWrites(w);
      // Sweep-work accounting feeds the mutation-work suspension guard.
      addWorkPressure(performance.now() - sweepStarted, 'sweep-work');
      if (incomplete && !repainterSuspended && !document.hidden) {
        requestLightSweep();
      }
      return;
    }
    // ---- FORCE LANE (SRC-006:R010) ----
    // A lap owns an ordered workset built ONCE from the registry (document
    // first, represented exactly once). Continuation slices resume at
    // forceLapIndex instead of reconstructing `[document, ...piercedRoots]`
    // and walking from root zero; detached roots are dropped lazily AS
    // VISITED, never via a registry-wide scan per slice; hover-sheet work is
    // folded into first-serve per root; completion is the O(1) remaining
    // counter, not a full-rootCollection scan. Roots pierced DURING a lap
    // join the next lap's workset.
    if (!forceLapActive || !forceLapWorkset) {
      forceLapWorkset = [document, ...piercedRoots];
      forceLapIndex = 0;
      forceLapRemaining = forceLapWorkset.length;
      forceLapActive = true;
      stylesDirty = false;
      // Cursors from an earlier lap are garbage once the workset is rebuilt.
      forceRootCursors.clear();
    }
    let remaining = FORCE_BUDGET;
    let rootsServed = 0;
    while (forceLapIndex < forceLapWorkset.length && remaining > 0) {
      if (rootsServed >= FORCE_ROOT_BUDGET) break;
      const root = forceLapWorkset[forceLapIndex];
      if (root !== document) {
        let detached = false;
        try { detached = !root.host || !root.host.isConnected; } catch (e) { detached = true; }
        if (detached) {
          // SRC-006:R010: lazy prune-as-visited. Detached roots never leak in
          // forceRootCursors past this point (and a lap end clears the rest).
          try { piercedRoots.delete(root); forceRootCursors.delete(root); } catch (e) { }
          forceLapRemaining--;
          forceLapIndex++;
          continue;
        }
      }
      let state = forceRootCursors.get(root);
      if (!state) {
        // PERF-002: TreeWalker.NodeFilter.SHOW_ELEMENT only. No full
        // querySelectorAll materialisation. The walker advances one node at
        // a time and is GC'd when its root detaches; never retain a static
        // NodeList.
        const walker = (root.createTreeWalker ? root.createTreeWalker(root, 0x1 /* SHOW_ELEMENT */, null) : null);
        state = { walker, total: 0, done: false };
        forceRootCursors.set(root, state);
        // Hover-sheet work is incremental too: one strip per root per lap,
        // paid when the root is first SERVED -- not a registry-wide forEach
        // on every continuation slice.
        if (scanStyles) { try { stripHoverSheets(root); } catch (e) { } }
      }
      try {
        // Walk incrementally until the element budget is exhausted, then
        // resume on the next slice from this exact walker.
        while (remaining > 0) {
          const node = state.walker ? state.walker.nextNode() : null;
          if (!node) { state.done = true; break; }
          process(node, true, w);
          state.total++;
          remaining--;
        }
      } catch (e) { state.done = true; }
      if (state.done) {
        forceLapRemaining--;
        forceLapIndex++;
      } else {
        // Element budget exhausted mid-root: stay on this root so the next
        // slice resumes from the same walker (cursor never moves backwards).
        break;
      }
      rootsServed++;
    }
    flushWrites(w);
    // Sweep-work accounting feeds the mutation-work suspension guard; every
    // slice must report its own duration regardless of which lane ran.
    addWorkPressure(performance.now() - sweepStarted, 'sweep-work');
    const lapComplete = forceLapRemaining <= 0 && forceLapIndex >= forceLapWorkset.length;
    if (force && forceLapActive) {
      if (lapComplete) {
        // Lap done: drop ALL traversal state so neither cursors nor a dead
        // workset outlive the lap.
        forceRootCursors.clear();
        forceLapWorkset = null;
        forceLapIndex = 0;
        forceLapRemaining = 0;
        forceLapActive = false;
      } else if (!repainterSuspended && !document.hidden) {
        forcePassesOwed = Math.max(forcePassesOwed, 1);
        scheduleSweep(MIN_SWEEP_GAP);
      }
    }
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

  // --- REPAINTER END ---
})();
