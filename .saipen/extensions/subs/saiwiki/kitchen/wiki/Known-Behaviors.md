# Known behaviors

- **Hover effects built in JavaScript** (class toggling rather than CSS `:hover`) may
  still show their own highlight — the script only strips readable `:hover` CSS rules.
- **Cross-origin stylesheets**: on rare sites whose CSS is cross-origin, clicking a
  non-focusable element can delay its visual state change until the mouse leaves it
  (the hover-freeze fallback at work). Real buttons and links are exempt.
- **Static by design**: no options panel, no per-site toggles. Fork it and edit the
  tokens at the top if you want a different flavor.
- **Safety guard**: the script disables itself on OAuth, captcha, banking and payment
  pages so critical flows are never restyled.

## What the script touches

- Dark golden palette — solid flat surfaces only: no gradients, no blur, no transparency.
- Classic 3D bevels — buttons raised, inputs sunken, pressed buttons push in (with
  the authentic 1px label shift). Scrollbars are full Win95-style.
- `border-radius: 0` enforced everywhere, including framework CSS variables.
- All transitions and animations zeroed; state changes are instant.
- Hover highlighting disabled completely — paint properties stripped from every
  readable `:hover` rule; functional properties (`display`/`visibility`/`opacity`)
  are kept so hover-opened menus still work.
- Verdana forced everywhere (inputs and textareas included, font smoothing
  disabled); icon fonts excluded so glyphs don't turn into letters. A custom font
  installed as `Verdana_m1` is used automatically.
- Adaptive repainter converts light surfaces and unthemed dark-mode grays into the
  vintage brown scale and fixes low-contrast text at WCAG-aware thresholds. Images,
  videos, canvases and players are never touched.
- Shadow DOM piercing themes web components too (YouTube, Reddit, and friends) via an
  `attachShadow` hook.
- Popups (menus, dialogs, tooltips, hovercards) are recolored only; the script never
  forces `opacity`/`z-index`/`visibility`, so hidden site UI stays hidden.
