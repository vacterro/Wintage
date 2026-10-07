'use strict';
// The CURRENT-LIVE ChatGPT contract, in one place.
//
// WHY THIS FILE EXISTS. The repo carried the same fact in three shapes and they
// drifted apart: tools/inspect-web.js measured the live shell on 2026-10-04 and
// recorded that it exposes NO data-testid, no #thread and no aria-label on
// <main>, with a div.thread-scroll-container owning the viewport and a
// role=textbox contenteditable editor; CHATGPT_FAST_CSS kept binding the
// previous generation's data-testid; and the static gates called that stale
// hook "the October contract". So every gate stayed green while the signed-in
// page rendered stock black -- the failure mode a theme cannot notice about
// itself, because all four of its assertions were about ancestors of the
// element that paints.
//
// This module is the single list both sides read, so the next rollout moves the
// contract here and both the inspector and the gates follow, instead of one of
// them silently keeping the old shape.
//
// `css`       the exact selector part CHATGPT_FAST_CSS must carry.
// `inspector` the alternative that must appear in some tools/inspect-web.js
//             SURFACES selector, so production cannot claim a contract the
//             inspector does not measure (or the reverse).
//
// A contract belongs here only when a live measurement named it, never because
// a selector happened to match. Generated x* classes are build output and are
// excluded by construction -- see test-chatgpt-2026.js, which forbids them.

const STAMP = 'html[data-w95-chatgpt="1"]';

const CURRENT_LIVE_HOOKS = [
  {
    label: 'current-live root app container',
    css: STAMP + ' #web-mobile-root',
    inspector: '#web-mobile-root',
    surface: 'root-app'
  },
  {
    label: 'current-live viewport owner (thread scroll container)',
    css: STAMP + ' div.thread-scroll-container',
    inspector: 'div.thread-scroll-container',
    surface: 'app-scroll-container'
  },
  {
    label: 'current-live plain main viewport',
    css: STAMP + ' main',
    inspector: 'main',
    surface: 'app-scroll-container'
  },
  {
    label: 'current-live sidebar landmark',
    css: STAMP + ' [role="complementary"][aria-label="Sidebar"]',
    inspector: '[role="complementary"][aria-label="Sidebar"]',
    surface: 'sidebar'
  },
  {
    label: 'current-live prompt editor (role=textbox contenteditable)',
    css: STAMP + ' [role="textbox"][contenteditable="true"]',
    inspector: '[role="textbox"][contenteditable="true"]',
    surface: 'prompt-editor'
  }
];

// Split a CHATGPT_FAST_CSS-shaped sheet into selector parts, so a lookup is an
// exact rule-part match rather than a substring sweep. A substring answer is
// what let a stale selector satisfy a gate named after a different one.
function selectorParts(css) {
  const out = [];
  const text = css.replace(/\/\*[\s\S]*?\*\//g, '');
  let depth = 0, from = 0;
  for (let i = 0; i < text.length; i++) {
    if (text[i] === '{') {
      if (depth === 0) {
        for (const sel of text.slice(from, i).split(',')) {
          const s = sel.trim();
          if (s) out.push(s);
        }
      }
      depth++;
    } else if (text[i] === '}') {
      depth--;
      if (depth === 0) from = i + 1;
    }
  }
  return out;
}

module.exports = { STAMP, CURRENT_LIVE_HOOKS, selectorParts };
