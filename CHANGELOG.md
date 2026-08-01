# Changelog

## [1.24.0] - 2026-08-01

- Claude Desktop: buttons transparent by default; the foreground repair moved to targeted floating-surface selectors (the earlier inherit-all approach was reverted); re-solidify specificity bumped to beat the transparency wipe, with Radix UI selectors added; live CSS hot-reloading for Electron targets (tools/watch-claude.ps1).
- Docs: README translated to Russian (README.ru.md), Estonian (README.et.md) and the Дед voice (README.ded.md); an 8-page wiki mirror added under wiki/.
- Tests: shim payload validity and terminal font agreement are now release-gated (tools/test-shim-payloads.js, tools/test-terminal-font.js).

## [1.23.3] - 2026-08-01

- Replace proportional Verdana in Windows Terminal and classic conhost with Consolas 12 so glyphs fit the fixed terminal cell grid.

## [1.23.2] - 2026-08-01

- Restore readable palette foregrounds in Claude Desktop 1.24012.9 while leaving SVG and icon glyphs untouched.

## [1.23.1] - 2026-08-01

- Report clipboard failures with the usable browser-theme path instead of claiming it was copied.
- Surface installer path-preference write failures instead of silently forgetting them.

## [1.23.0] - 2026-08-01

- Added immediate Windows theme installation with muted active/inactive captions and the `___CURRENT___` cursor scheme.
- Added Verdana 12 and matching 16-colour palettes for Windows Terminal and classic conhost profiles.
- Added OBS Studio theme installation and immediate selection.
- Added installed and portable Chromium browser discovery, Tampermonkey detection, stable browser-theme staging, and browser-owned installation pages.
- Reorganized the installer into separate My Apps and Popular Apps groups and added a console-free launcher.
- Restored all sixteen userscript palettes, including the editable Custom palette.
- Restored themed recent-file colour indicators in Total Commander.
- Fixed dry-run isolation, generated token drift, Electron injection coverage, and several installer round-trip defects.
