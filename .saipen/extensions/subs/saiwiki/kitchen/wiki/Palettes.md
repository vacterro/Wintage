# Palettes

Wintage ships **sixteen palettes**. Six are UI.md's own structure rotated to another
hue family (Dark Golden, Claude Code, Antigravity, K-Lite, FreeBuff, CodeNomad);
Custom can be edited and saved from the desktop installer; nine are imported from
FastPrompter (Default, Golden Vintage, Golden Default, Vintage Dark, Vintage Classic,
Dark 2 OLED, Dracula, Nord, Solarized Dark).

Every palette clears WCAG AA on the three tokens that carry text — the build gate
refuses a palette that does not.

## The Golden Default token table

| Token | Hex | Used for |
|---|---|---|
| background | `#1A1810` | outermost background |
| backgroundSoft | `#232018` | body / content backdrop |
| surface | `#332E22` | headers, nav, panels |
| surfaceRaised | `#3D372A` | buttons, popups, scrollbar thumb |
| surfaceAlt | `#453D30` | button hover |
| borderHighlight | `#F0D060` | bevel edges, links |
| borderDark | `#100E08` | sunken edges, borders |
| textPrimary | `#D4C89A` | primary golden text |
| textMuted | `#6E674E` | placeholders, disabled |
| link | `#F0D060` | links, focus |

## Why palettes live outside the script

Palettes live in `themes/*.json`, outside the script, because Tampermonkey
re-downloads `wintage.user.js` on every update — a palette edited into it by hand
would vanish. Re-apply them onto a fresh build with:

```powershell
.\install-themes.ps1 -Latest
```

## Custom

The desktop installer's GUI shows all twenty-one colour tokens as editable swatches.
Editing any swatch forks the palette into **Custom** rather than changing a shipped
theme under you.
