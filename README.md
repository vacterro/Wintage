# Wintage

**Win95 Dark Golden Vintage theme for the whole web.** A Tampermonkey userscript that restyles every site into a dark golden-brown Windows 95 application: pixel-sharp 3D bevels, zero rounded corners, zero animations, no hover flashbangs, Verdana everywhere.

## Install

1. Install [Tampermonkey](https://www.tampermonkey.net/) (Chrome, Edge, Firefox, Opera, Safari).
2. Click **[Install Wintage](https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js)** — Tampermonkey opens its install page automatically.
3. Done. Every site you visit is now running Windows 95, Dark Golden edition.

## Updating

- **Automatic:** the script carries `@updateURL`/`@downloadURL` pointing at this repo, so Tampermonkey picks up new versions on its regular update checks.
- **Manual refresh:** Tampermonkey → **Utilities → Check for userscript updates**, or just click the install link again — it replaces the old version in place, no uninstall needed.

## Features

- **Dark golden palette** — deep brown-black canvas `#1A0F05`, golden text `#D4B87A`, golden bevel highlights `#C0A060`. Solid flat surfaces only: no gradients, no blur, no transparency effects.
- **Classic 3D bevels** — buttons raised, inputs sunken, pressed buttons push in (with the authentic 1px label shift). Scrollbars are full 16px Win95-style, beveled thumb and buttons included.
- **Radius killer** — `border-radius: 0` enforced everywhere, including framework CSS variables (Bootstrap, Material, YouTube, Reddit).
- **Motion is forbidden** — all transitions and animations are zeroed out. State changes are instant, like a real 1995 UI.
- **Hover-highlighting disabled completely** — no white flashbang rows, no gray tint blocks:
  - paint properties are surgically stripped from every readable `:hover` CSS rule (functional properties like `display`/`visibility`/`opacity` are kept, so hover-opened menus still work);
  - unreadable cross-origin stylesheets are neutralized by a transition-freeze fallback.
  Only real controls (buttons, links, inputs) keep an instant, themed bevel response.
- **Verdana forced 100% everywhere** — including inputs and textareas, with font smoothing disabled. Icon fonts are excluded so glyphs don't turn into letters. If you have a custom font installed under the name `Verdana_m1` (e.g. a de-antialiased Verdana patch), it is used automatically; otherwise regular Verdana.
- **Adaptive repainter** — a lightweight JS sweeper converts light "flashbang" surfaces and unthemed dark-mode grays into the vintage brown scale, and fixes low-contrast (dark-on-dark) text to golden, at WCAG-aware thresholds. Images, videos, canvases, and players are never touched.
- **Shadow DOM piercing** — themes web components too (YouTube, Reddit, and friends) via an `attachShadow` hook.
- **Popups behave** — menus, dialogs, tooltips, and hovercards are recolored only; the script never forces `opacity`/`z-index`/`visibility`, so hidden site UI stays hidden.
- **Safety guard** — the script disables itself on OAuth, captcha, banking, and payment pages so critical flows are never restyled.

## Palette

| Token | Hex | Used for |
|---|---|---|
| Canvas | `#1A0F05` | outermost background |
| Soft | `#1E1408` | body / content backdrop |
| Surface | `#2A1C0A` | headers, nav, panels |
| Raised | `#362812` | buttons, popups, scrollbar thumb |
| Alt | `#3A2A15` | button hover |
| Bevel highlight | `#C0A060` | top-left 3D edges |
| Bevel shadow | `#0E0803` | bottom-right 3D edges |
| Text | `#D4B87A` | primary golden text |
| Muted | `#7A6838` | placeholders, disabled |
| Accent | `#9DD9F9` | links, focus |

## Known behaviors

- Sites that build hover effects in JavaScript (class toggling) rather than CSS `:hover` may still show their own highlight.
- On rare sites whose CSS is cross-origin, clicking a non-focusable element can delay its visual state change until the mouse leaves it (the hover-freeze fallback at work). Real buttons and links are exempt.
- The script is static by design: no options panel, no per-site toggles. Fork it and edit the tokens at the top if you want a different flavor.

## Releasing a new version (maintainers)

Edit `wintage.user.js`, then run:

```powershell
.\release.ps1 -Message "what changed"
```

It bumps the `@version` patch number, commits, and pushes — Tampermonkey clients pick the update up automatically. Pass `-Bump minor` or `-Bump major` for bigger releases.

## License

[MIT](LICENSE)
