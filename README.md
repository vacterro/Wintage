# Wintage

**Win95 Dark Golden Vintage theme for the whole web.** A Tampermonkey userscript that restyles every site into a dark golden-brown Windows 95 application: pixel-sharp 3D bevels, zero rounded corners, zero animations, no hover flashbangs, Verdana everywhere.
<img width="876" height="618" alt="2026-08-01_230413" src="https://github.com/user-attachments/assets/5c1839ac-b977-46a0-9003-d6bffa9299a8" />
[🤍 Support Developer](https://buymeacoffee.com/vacuum34)

[EN](README.md) | [RU](README.ru.md) | [ET](README.et.md) | [Дед](README.ded.md)

_The modern web optimizes for aesthetics at the expense of usability. Rounded corners replace visual hierarchy, animations replace feedback, shadows replace structure, and minimalism often removes the very cues our brains rely on to understand an interface._

_Users shouldn't have to guess whether something is a button, a label, a card, or plain text. Wintage brings back explicit visual language: raised buttons, sunken inputs, sharp boundaries, consistent typography, zero distractions, and immediate state changes._

_Every element communicates its purpose at a glance, reducing cognitive load and making the web feel like a precise instrument again instead of a collection of decorative bubbles._

[Changelog](CHANGELOG.md)

## Install

1. Install [Tampermonkey](https://www.tampermonkey.net/) (Chrome, Edge, Firefox, Opera, Safari).
2. Click **[Install Wintage](https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js)** — Tampermonkey opens its install page automatically.
3. Done. Every site you visit is now running Windows 95, Dark Golden edition.

## Updating

- **Automatic:** the script carries `@updateURL`/`@downloadURL` pointing at this repo, so Tampermonkey picks up new versions on its regular update checks.
- **Manual refresh:** Tampermonkey → **Utilities → Check for userscript updates**, or just click the install link again — it replaces the old version in place, no uninstall needed.
- **Missing theme rows means an old script:** the menu is generated from the
  embedded theme registry and the release test requires exactly one menu row for
  every embedded palette. If the menu is shorter than the palette list below,
  click **Install Wintage** again and confirm **Update** in Tampermonkey.

## Sixteen palettes, and a switch

Wintage is no longer one palette. Six are UI.md's own structure rotated to another
hue family (Dark Golden, Claude Code, Antigravity, K-Lite, FreeBuff, CodeNomad),
Custom can be edited and saved from the desktop installer, and nine are imported
from [FastPrompter](https://github.com/vacterro) (Default, Golden
Vintage, Golden Default, Vintage Dark, Vintage Classic, Dark 2 OLED, Dracula, Nord,
Solarized Dark). Every one of them clears WCAG AA on the three tokens that carry
text -- the build gate refuses a palette that does not.

Pick one from the **Tampermonkey menu** on any page; the choice is stored per user,
not per site, so it holds across every domain.

Palettes live in `themes/*.json`, outside the script, for one reason: Tampermonkey
re-downloads `wintage.user.js` on every update, so a palette edited into it by hand
would vanish. Re-apply them onto a fresh build with:

```powershell
.\install-themes.ps1 -Latest
```

## Beyond the browser

The same palettes install into desktop applications -- VS Code and Antigravity as
colour themes, Electron apps (Freebuff, the Antigravity agent app) through a shim
that injects the very stylesheet this userscript uses. There is a small GUI for it:

Double-click **`Wintage Installer.vbs`** in the repo root. It opens the GUI without
a console window. The legacy `.cmd` launcher forwards to the same hidden host;
`desktop\WintageInstaller.ps1` can still be run directly for diagnostics.

What each target can and cannot reach -- including the two apps that are fused shut
or have their colours compiled in -- is written down in
**[desktop/README.md](desktop/README.md)**.

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

## Matching browser theme

The desktop installer's `browsers` target detects installed and portable Chromium
profiles, reports Tampermonkey coverage, stages the selected browser theme, and
opens the correct install/update pages for every profile. Chromium requires one
**Developer mode → Load unpacked** confirmation per profile; the installer copies
the stable theme path to the clipboard. Later palette changes reuse that path.

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

<img width="1440" height="860" alt="2026-07-29_180529" src="https://github.com/user-attachments/assets/7888e96f-f854-4b68-bd82-58f76b85f630" />
<img width="641" height="1080" alt="2026-08-01_230328" src="https://github.com/user-attachments/assets/2a33c723-eaee-4f49-b4e7-2d24e6bc599e" />
<img width="874" height="903" alt="2026-07-29_180545" src="https://github.com/user-attachments/assets/0fc63c83-b314-4c95-96ab-ac5cdd7c3d53" />
<img width="640" height="1080" alt="2026-08-01_230203" src="https://github.com/user-attachments/assets/db03a09c-dd8b-4423-b927-e8d87e7d0b4e" />
<img width="746" height="1080" alt="2026-07-29_180639" src="https://github.com/user-attachments/assets/840ef269-6259-4c84-a1b6-8fd44f390aad" />
<img width="900" height="663" alt="2026-07-29_180652" src="https://github.com/user-attachments/assets/4f38b63a-860c-468a-843f-6982c5287a7b" />


## License

[MIT](LICENSE)
