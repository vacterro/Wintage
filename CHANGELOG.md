# Changelog

## [1.26.4] - 2026-08-11

- Correctness pass over the installer's failure and rollback paths. `-Reapply` now exits nonzero when any target fails (a broken sibling no longer reads as a green run), payload versions are compared semantically (`1.9.0 < 1.26.3` instead of lexically), Electron apply/revert/`-WhatIf` helper failures abort the target instead of printing and continuing, the FreeBuff ad/sound patch runs before the manifest is written, and the GUI reports PASS/FAIL per target and only claims success when every requested operation succeeded. Saving or deleting the custom theme now aborts the Apply when the generators fail, so a stale build can never be installed.
- Rollback integrity: SMART VAC CLEANER keeps its first pre-Wintage backup across repaints (apply A -> apply B -> Revert restores the original byte-for-byte), the source anchors that smartvac/wildrift/saipenview patch must each match exactly once or the install fails without writing anything, MPC-HC refuses to mutate the registry when its backup export fails and refuses to claim a restore when the import fails, and a corrupt `installed.json` is a distinct fatal state that Status and Reapply report and that no mutation will overwrite. Manifest writes are atomic (temp write + readback + rename).
- The theme contract now has one owner. `tools/theme-schema.js` defines the canonical 21-token schema and the WCAG text roles (textPrimary/textSecondary/link), shared by apply-themes, check-css, build-desktop and the GUI; pack validation rejects duplicate slugs/labels and any pack whose filename does not match its slug; the GUI and the build gate warn about exactly the same contrast roles, so a decorative `borderHighlight` no longer produces a false FAIL on light palettes.
- Encoding: double-encoded UTF-8 mojibake removed from `build-desktop.js`, `install-electron.js` and `derive-palette.js`, generated outputs regenerated, and a gate now fails the build on known mojibake signatures.
- Tests: the reapply suite now runs fully isolated from the live `%APPDATA%` manifest and covers semantic versioning, moved-target rediscovery, child-failure aggregation, corrupt-manifest refusal, Electron helper failure propagation and byte-exact revert; the repository suite validates the shared schema, theme identity collisions, WCAG role parity and single-owner target dispatch.

## [1.26.3] - 2026-08-10

- BetterDiscord is now a dedicated target. The generic web stylesheet broke Discord's layout because it never fills Discord's own CSS variables; a dedicated theme maps every Wintage palette token onto Discord's variable surface (dark + light, brand, modifiers, scrollbars, bevels on buttons and inputs, Verdana, status colours) and installs under the BetterDiscord theme directory.
- The whole README/installer/browser-theme surface now ships in 29 languages. Twelve languages were added outright (Ukrainian, Portuguese, Dutch, Polish, Swedish, Danish, Finnish, Norwegian, Turkish, Czech, Slovak, Croatian) and the other seventeen were refreshed to the current palette table; the installer gained 12 new UI locales alongside its existing four.
- Fixed: `install.ps1` died on every launch when no CodeNomad path was configured -- `Join-Path` throws on an empty first argument during target-table construction, so listing and every target failed before this fix.
- The installer monolith was split into shared modules (`desktop/modules/common.ps1` and `desktop/modules/targets.ps1`); behaviour is unchanged, the listing, `-Reapply` and `-Status` flows were re-verified byte-identical.
- A new release gate pins that the repository `wiki/` mirror never drifts from the maintained wiki source.
- Docs corrected: the palette tables now name the real Golden Default tokens, the browser-theme README no longer claims to use the same palette as the userscript, and the Core-share ru/et/ded READMEs carry the same source-digest markers as the translated bundle.

## [1.26.2] - 2026-08-07

- Portable browser root is no longer hardcoded to a personal-machine path. `tools/install-browsers.ps1` defaults to an empty `-PortableRoot` and only scans it when one is supplied (the installer passes the remembered `portable` entry from `paths.json`); the same hardcoded path was removed from prose in `desktop/README.md` and from the FastPrompter importer's default source.
- Corrupt config is no longer silent. `Read-PathsJson` and `Read-Manifest` now warn when `paths.json` or `installed.json` fails to parse, instead of returning an empty table that looks identical to "nothing configured".
- The browsers target now records itself in the install manifest, so `-Reapply` can rediscover it like every other target; the fuse-deflip in `tools/electron-fuses.js` backs up the original EXE before mutating it and `--revert` restores those bytes.
- Installer housekeeping: a stale comment about the removed `FLOAT_FIX` patch was corrected, the GUI's mojibaked section dividers were cleaned, config reads switched to the UTF-8-safe `Read-Utf8`, backup folders are pruned to the eight newest, palette-token reads were consolidated into one helper, and generated `desktop/out/` output is no longer tracked in git (rebuilt with `node tools/build-desktop.js`).

## [1.26.1] - 2026-08-06

- Fixed: Antigravity and FreeBuff would not start at all after 1.26.0. Retiring the old floating-surface payload cut its tail and left its head behind, so the next declaration closed that unterminated string instead of opening its own and the shim died on load with `SyntaxError: Invalid or unexpected token`. The error is thrown in Electron's main process, before any window exists, which is why it presented as the application refusing to launch rather than as a theme problem.
- The repainter is now carried into the shim as an encoded string instead of pasted into a template literal. Pasted, every backslash in its regular expressions was read as an escape -- `\d` became `d`, `\s` became `s` -- so the code still parsed and silently stopped recognising the colours it exists to correct.
- Shadow roots are themed in the desktop apps again. `insertCSS` produces a document stylesheet, which cannot cross a shadow boundary, so those rules travel inside the repainter payload and are injected root by root.
- Three new release gates, because every existing one was green while the above shipped: the build parses each generated shim, refuses an unresolved placeholder, and fails when the repainter starts reading a helper the shim does not provide; the payload suite parses each generated shim and the payload it builds.
- Removed a stale VS Code colour theme left behind when a palette was renamed -- nothing generated or read it.
- Fixed: the installer treated an unreadable FreeBuff sound preference as "no sound set" and said nothing about it.

## [1.26.0] - 2026-08-03

- Floating surfaces are decided by measurement rather than a list of component names. The deciding test is a hit test at the panel's own centre: if what lies under it is only its own ancestors it is an adornment, and anything foreign under it means it covers content it does not own. An earlier "must carry an explicit z-index" rule was wrong on the first application it met -- Claude's Settings dialog is `position: fixed` with `z-index: auto`.
- A viewport-covering backdrop that takes pointer events is dimmed instead of skipped. Erasing its background left an invisible modal that ate every click, which is how CodeNomad's tabs stopped responding.
- Panels are re-measured twice, bounded, after being refused for a reason time can change. A dialog animates in and is not its final size at the instant it is mounted, which is why they were see-through only sometimes.
- Status colours are alive again application-wide. The button-descendant wipe's selector list still opened with an unguarded `button:not(.ytp-button) *,` above the exclusions written for it, in the same comma list, and one unguarded sibling defeats every guarded one. The same shape is now guarded in `SHADOW_CSS`, and `tools/check-css.js` fails on it.
- Idle CPU: `injectLate()` was appending a second complete copy of `GLOBAL_CSS` -- 44 KB parsed and matched twice on every page. Being last in the cascade is a position, not a copy, so the existing sheet is moved instead. Style recalculation on a 3200-element harness dropped from 48ms to 20ms. The floating-surface pass also stopped marking small out-of-flow elements permanently dirty, which had cost a forced layout each, forever.
- Scrolling up means scrolling up: a programmatic scroll aimed at the bottom is dropped when the reader has deliberately scrolled away and no user gesture is behind the call. It fails open -- anything unmeasurable is allowed through.
- Withdrawn after measuring what it hit: the gauge painter marked 234 elements by shape and 111 by inline width, repainting ordinary controls as solid blocks. The problem stays open; nothing paints again until a real gauge is read live.
- New: `tools/inspect-electron.js` reads a live themed Electron app over CDP (targets / rules / eval) -- the tool behind every diagnosis above.

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
