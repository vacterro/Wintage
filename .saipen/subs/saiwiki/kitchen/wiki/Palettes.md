# Palettes

Wintage ships **sixteen palettes**. Six are UI.md's own structure rotated to another
hue family (Dark Golden, Claude Code, Antigravity, K-Lite, FreeBuff, NomadCode);
Custom can be edited and saved from the desktop installer; nine are imported from
FastPrompter (Default, Golden Vintage, Golden Default, Vintage Dark, Vintage Classic,
Dark 2 OLED, Dracula, Nord, Solarized Dark).

Every palette clears WCAG AA on the three tokens that carry text — the build gate
refuses a palette that does not.

## The Dark Golden token table

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

## Why palettes live outside the script

Palettes live in `themes/*.json`, outside the script, because Tampermonkey
re-downloads `wintage.user.js` on every update — a palette edited into it by hand
would vanish. Re-apply them onto a fresh build with:

```powershell
.\install-themes.ps1 -Latest
```

## Custom

The desktop installer's GUI shows all eighteen colour tokens as editable swatches.
Editing any swatch forks the palette into **Custom** rather than changing a shipped
theme under you.
