<div align="center">

# Wintage

**Windows 95 visual language for the modern web.**

A Tampermonkey userscript and desktop theme toolkit that turns modern interfaces into sharp, quiet, dark-vintage UI: square geometry, explicit 3D bevels, instant state changes, warm palettes, and readable Verdana typography.

[![Tampermonkey](https://img.shields.io/badge/Tampermonkey-userscript-00485B?style=flat-square&logo=tampermonkey&logoColor=white)](https://www.tampermonkey.net/)
[![Platform](https://img.shields.io/badge/platform-Web%20%2B%20Windows-0078D4?style=flat-square)](#beyond-the-browser)
[![Palettes](https://img.shields.io/badge/palettes-16-D4B86A?style=flat-square)](#palettes)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)

[**Install Wintage**](https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js) · [Changelog](CHANGELOG.md) · [Desktop themes](desktop/README.md) · [Issues](https://github.com/vacterro/Wintage/issues)

<img width="876" height="618" alt="Wintage dark vintage theme applied to a modern web interface" src="https://github.com/user-attachments/assets/5c1839ac-b977-46a0-9003-d6bffa9299a8" />

</div>

---

## Why Wintage

Modern interfaces often trade visible structure for decoration: rounded cards blur boundaries, animations delay feedback, hover effects flash across content, and controls increasingly resemble plain text.

Wintage goes the other way. It restores an explicit visual language where controls look clickable, inputs look editable, panels have boundaries, and state changes happen immediately.

The result is intentionally old-school in appearance and modern in implementation:

- **square geometry** instead of pervasive rounded corners;
- **raised controls and sunken inputs** instead of ambiguous flat surfaces;
- **instant state changes** instead of transitions and decorative motion;
- **warm dark palettes** instead of gray-on-gray minimalism;
- **Verdana-first typography** with icon-font protection;
- **adaptive repainting** for sites that do not expose clean theme variables;
- **Shadow DOM coverage** for modern component-heavy applications;
- **safety exclusions** for OAuth, CAPTCHA, banking, and payment flows.

## Install

1. Install [Tampermonkey](https://www.tampermonkey.net/) for Chrome, Edge, Firefox, Opera, or Safari.
2. Click **[Install Wintage](https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js)**.
3. Confirm the userscript installation.

That is it. Wintage applies automatically to ordinary web pages.

### Updating

Wintage ships `@updateURL` and `@downloadURL` metadata, so Tampermonkey can update it automatically.

For a manual refresh, use **Tampermonkey → Utilities → Check for userscript updates**, or click **Install Wintage** again and confirm the update.

If the Tampermonkey menu shows fewer theme entries than the palette list below, the installed script is stale. Reinstalling from the link above refreshes it in place.

## Features

| Area | What Wintage does |
|---|---|
| **Structure** | Pixel-sharp 3D bevels, square corners, visible panel boundaries, Win95-style controls and scrollbars |
| **Motion** | Disables decorative transitions and animations so state changes are immediate |
| **Hover behavior** | Removes paint-only hover flash while preserving functional hover menus and real control feedback |
| **Typography** | Forces Verdana-compatible text while protecting icon fonts; automatically prefers `Verdana_m1` when installed |
| **Adaptive repainting** | Converts light flashbang surfaces and generic dark grays into the active palette while preserving media |
| **Shadow DOM** | Themes web components by intercepting `attachShadow` in page context |
| **Popups** | Recolors menus, dialogs, tooltips, and hovercards without forcing visibility or z-index |
| **Safety** | Disables itself on OAuth, CAPTCHA, banking, and payment pages |

### Golden Default

The canonical Golden Default palette uses warm brown-black surfaces with gold text and bevel highlights.

| Token | Hex | Purpose |
|---|---:|---|
| `background` | `#1A1810` | outer background |
| `backgroundSoft` | `#232018` | body/content backdrop |
| `surface` | `#332E22` | headers, navigation, panels |
| `surfaceRaised` | `#3D372A` | buttons, popups, scrollbar thumb |
| `surfaceAlt` | `#453D30` | alternate raised state |
| `borderHighlight` | `#F0D060` | bevel highlights and links |
| `borderDark` | `#100E08` | sunken edges and borders |
| `textPrimary` | `#D4C89A` | primary text |
| `textMuted` | `#6E674E` | secondary and disabled text |
| `link` | `#F0D060` | links and focus |

Every shipped palette defines the complete 21-token contract, including bevel structure, semantic colors, selection, and target-specific values.

## Palettes

Wintage ships **16 palettes**. Pick one from the Tampermonkey menu on any page; the selection is stored per user and applies across domains.

The set includes Wintage/SAIPEN-oriented palettes such as Dark Golden, Claude Code, Antigravity, K-Lite, FreeBuff, and CodeNomad, plus Custom and nine palettes shared with FastPrompter including Golden Vintage, Golden Default, Vintage Dark, Vintage Classic, Dark 2 OLED, Dracula, Nord, and Solarized Dark.

The build gate checks text-carrying palette tokens against WCAG AA requirements.

Palette definitions live in `themes/*.json` rather than being hand-edited inside the userscript. To apply them to a fresh build:

```powershell
.\install-themes.ps1 -Latest
```

## Beyond the browser

Wintage also installs matching themes into selected desktop applications.

Double-click **`Wintage Installer.vbs`** for the GUI installer without a console window. The legacy `.cmd` launcher forwards to the same hidden host, while `desktop\WintageInstaller.ps1` remains available for diagnostics.

Desktop coverage includes:

- VS Code-style color themes;
- Antigravity-compatible themes;
- Electron application shims where safe injection is possible;
- Chromium browser-theme staging for installed and portable profiles.

Target-specific capabilities and limitations are documented in **[desktop/README.md](desktop/README.md)**.

BetterDiscord extensions are maintained separately in [BetterDiscord vac34 plugins](https://github.com/vacterro/BetterDiscord_vac34_plugins).

### Matching Chromium theme

The desktop installer can detect installed and portable Chromium profiles, report Tampermonkey coverage, stage the selected browser theme, and open the correct installation/update pages.

Chromium still requires one **Developer mode → Load unpacked** confirmation per profile. Later palette changes reuse the same stable theme path.

## Screenshots

<details>
<summary><b>Open screenshot gallery</b></summary>

<br>

<table>
<tr>
<td width="50%"><img alt="Wintage themed interface example 1" src="https://github.com/user-attachments/assets/7888e96f-f854-4b68-bd82-58f76b85f630" /></td>
<td width="50%"><img alt="Wintage themed interface example 2" src="https://github.com/user-attachments/assets/0fc63c83-b314-4c95-96ab-ac5cdd7c3d53" /></td>
</tr>
<tr>
<td width="50%"><img alt="Wintage themed interface example 3" src="https://github.com/user-attachments/assets/2a33c723-eaee-4f49-b4e7-2d24e6bc599e" /></td>
<td width="50%"><img alt="Wintage themed interface example 4" src="https://github.com/user-attachments/assets/db03a09c-dd8b-4423-b927-e8d87e7d0b4e" /></td>
</tr>
<tr>
<td width="50%"><img alt="Wintage themed interface example 5" src="https://github.com/user-attachments/assets/840ef269-6259-4c84-a1b6-8fd44f390aad" /></td>
<td width="50%"><img alt="Wintage themed interface example 6" src="https://github.com/user-attachments/assets/4f38b63a-860c-468a-843f-6982c5287a7b" /></td>
</tr>
</table>

</details>

## Known behaviors

- Sites that create hover effects through JavaScript class changes instead of CSS `:hover` may retain their own highlight.
- Rare cross-origin stylesheets can trigger the transition-freeze fallback, which may delay a non-focusable element's visual update until the pointer leaves it. Real buttons and links are exempt.
- Wintage intentionally avoids pretending every target can be themed safely. Targets with inaccessible or compiled-in styling remain documented limitations rather than being patched recklessly.

## Maintainer workflow

Add the new `## [x.y.z] - date` entry to [CHANGELOG.md](CHANGELOG.md) before releasing. The release script refuses to continue without it.

```powershell
.\release.ps1 -Message "what changed"
```

The release flow updates userscript version stamps together, rebuilds generated desktop themes, runs the release gates, then commits, tags, and pushes. Use `-Bump minor` or `-Bump major` when required.

## Languages

**English** · [Русский](locales/README.ru.md) · [Eesti](locales/README.et.md) · [日本語](locales/README.ja.md) · [Дед](locales/README.ded.md)

<details>
<summary><b>All translated READMEs</b></summary>

| Language | README | Language | README |
|:---|:---|:---|:---|
| العربية | [AR](locales/README.ar.md) | Български | [BG](locales/README.bg.md) |
| Čeština | [CS](locales/README.cs.md) | Dansk | [DA](locales/README.da.md) |
| Deutsch | [DE](locales/README.de.md) | Ελληνικά | [EL](locales/README.el.md) |
| Español | [ES](locales/README.es.md) | Eesti | [ET](locales/README.et.md) |
| Suomi | [FI](locales/README.fi.md) | Français | [FR](locales/README.fr.md) |
| עברית | [HE](locales/README.he.md) | हिन्दी | [HI](locales/README.hi.md) |
| Hrvatski | [HR](locales/README.hr.md) | Magyar | [HU](locales/README.hu.md) |
| Bahasa Indonesia | [ID](locales/README.id.md) | Italiano | [IT](locales/README.it.md) |
| 日本語 | [JA](locales/README.ja.md) | 한국어 | [KO](locales/README.ko.md) |
| Nederlands | [NL](locales/README.nl.md) | Norsk | [NO](locales/README.no.md) |
| Polski | [PL](locales/README.pl.md) | Português | [PT](locales/README.pt.md) |
| Română | [RO](locales/README.ro.md) | Русский | [RU](locales/README.ru.md) |
| Slovenčina | [SK](locales/README.sk.md) | Svenska | [SV](locales/README.sv.md) |
| ไทย | [TH](locales/README.th.md) | Türkçe | [TR](locales/README.tr.md) |
| Українська | [UK](locales/README.uk.md) | Tiếng Việt | [VI](locales/README.vi.md) |
| 中文 | [ZH](locales/README.zh.md) | Дед | [DED](locales/README.ded.md) |

</details>

## Project network

Wintage is part of the broader **SAIPEN / vacterro** project ecosystem.

[**Author hub**](https://github.com/vacterro) · [**SAIPEN HQ**](https://github.com/saipenhq) · [**SAIPEN Core**](https://github.com/vacterro/saipen) · [**ZAICODE**](https://github.com/vacterro/zaicode) · [**FastPrompter**](https://github.com/vacterro/FastPrompter) · [**SAIPEN Community**](https://discord.gg/SEYaYkuVgN)

For reproducible bugs and durable feature requests, use [GitHub Issues](https://github.com/vacterro/Wintage/issues).

## License

[MIT](LICENSE)

<!-- VACTERRO_SUPPORT:BEGIN -->
---
<sub>If Wintage is useful to you, optional support: [Buy Me a Coffee](https://buymeacoffee.com/vacuum34) · [Boosty](https://boosty.to/vacuum34/donate) · [PayPal](https://paypal.me/AlexNelin) · [other ways](https://github.com/vacterro/vacterro/blob/main/SUPPORT.md)</sub>
<!-- VACTERRO_SUPPORT:END -->
