# Changelog

## [1.26.8] - 2026-08-11

- The browser theme stage is now OWNED, not merely "in a safe location": a directory carrying the Wintage owner marker is the only one Apply replaces or Revert deletes. An unowned stage with user data is never touched - Apply and Revert refuse instead of recursively deleting it, and the stage is swapped atomically through a temp sibling.
- VS Code / Antigravity extension recovery moved to a persistent, non-pruned authority (`WINTAGE_APPDATA/recovery/<target>`): the first apply records whether the folder was created by Wintage or replaced a pre-existing one, a repaint never overwrites that pristine snapshot, and Revert restores the original directory byte-for-byte.
- SAIPENVIEW backup refreshes are now a REBASE, not a wholesale copy: the current CSS's Wintage-owned `--token` values always come from the old pristine, so a themed live file can never become the "pristine" authority and Revert restores stock colours, not Wintage's.
- The manifest is now schema-validated on every read and write: a syntax-valid but semantically broken file (top-level array, non-object entry, wrong-typed fields, non-array or duplicate-path `items`) is rejected like corrupt JSON and never overwritten, while unknown future target keys are preserved.
- Windows theme applies capture the exact owned pre-state (DWM inactive accent + Wintage theme artifacts) before mutating, and an activation failure restores it instead of leaving a half-applied theme. The DWM recovery backup survives until the manifest transition succeeds.
- Windows Terminal, Electron and Total Commander manifest commits are now part of their transactions: a failed commit rolls the target back (or keeps the recovery source for an idempotent retry), so a themed target can never be left with a manifest that does not describe it.
- The release helper now publishes the branch and the tag in ONE atomic push (`git push --atomic`): a rejected ref means neither lands, so a half-published version is impossible. The tag's availability is checked locally and on the remote before anything is pushed.
- The GUI custom theme Save/Delete are transactional: if a generator fails, the previous custom pack is restored and the generated outputs regenerated, so source and generated state never diverge.
- test-reapply now enumerates its full 34-test catalog and adds regressions for every fix above.

## [1.26.7] - 2026-08-11

- A target's mutation and its manifest commit are now ONE transaction: the manifest is validated before any real mutation (a corrupt `installed.json` aborts with zero target changes), and a failed manifest commit rolls every target back to its exact pre-operation state instead of leaving a mutated target with an old manifest. Each target also runs its whole DISCOVER..COMMIT under a named per-target mutex, so two concurrent applies of the same target serialize and can never tear each other's files.
- FreeBuff recovery is tighter: the transaction snapshot now includes the app EXE and its fuse backup (a failed second layer restores a half-defused executable too), and Revert refuses to restore an old-generation baseline over a new app build. A new app generation is detected by content (not just missing patch strings) and re-bases the baseline, which is pruned to the newest three generations.
- Electron repaint and revert are now transactions with their own failure seams: a failed repaint restores the previous palette, a failed revert restores the themed pre-state, and `--status-json` reports fuse health so Reapply can detect and repair a re-fused EXE.
- Reapply never reopens a browser: a browsers re-apply runs with launch suppressed (the theme already loads from a stable stage path), and a stub/empty browser executable is never "launched". This also stops the regression suite from yanking real Edge/Chrome windows open mid-session.
- Windows Terminal and Obsidian health now probe the EFFECTIVE owned state (markers and active-theme values) after the recorded item set passes, so a deleted or drifted marker triggers Reapply rather than being skipped.
- VS Code / Antigravity extension revert restores the apply-time backup instead of deleting the theme dir and leaving the user theme-less, and the browser stage root is snapshotted so a failed commit restores the exact pre-operation stage.
- The single release gate now runs every tool regression suite (reapply, freebuff, ownership, electron state machine) from `tests/Run-Tests.ps1`, and release publishing verifies the remote actually received the commit before tagging, so a half-published version is impossible.
- paths.json is schema-validated and saved atomically; remembered paths outside the known target set or with non-string values are dropped instead of later blowing up a `Join-Path`.

## [1.26.6] - 2026-08-11

- FreeBuff recovery is now a persistent per-generation BASELINE: every Wintage-owned file (renderer bundle, orchestrator, completion sound) is snapshotted as pristine stock, and Revert restores the current generation consistently — a later sound-only or subset Apply can never shadow the earlier recovery source, and an upstream app update starts a fresh generation baseline. The FreeBuff target is also atomic as a whole: both the Electron layer and the ad/sound patch are preflighted before any mutation, and a second-layer failure restores the exact pre-operation Electron state (a repaint rolls back to the old palette, never an uninstall). A configured-but-missing completion sound now fails closed in both `-WhatIf` and Apply, and the Reapply health probe checks the patch layer (renderer/orchestrator/sound) directly instead of assuming it.
- Electron installs are now fully transactional: `--dry-run` performs zero mutations (the fuse restore is never touched on a dry-run), the fuse flip happens only after state classification and preflight and is rolled back on any later failure, and both the relocation and in-place apply paths stage their changes and restore the exact pre-operation state on any injected failure.
- Revert now restores ONLY the fields Wintage owns, merged into the current config, for Obsidian and Windows Terminal too, and multi-item targets record their exact owned SET (`items`) in the manifest so health compares canonical path sets and revert walks the recorded items even when some vanish from today's discovery.
- Source-tree rollback provenance is safer: when the upstream source changes, the rollback base is re-based from the live non-owned content plus the old pristine's owned token values — a themed file can never become the "pristine" backup.
- Health probes now verify owned VALUES (marker == recorded palette, source-tree tokens == palette, generated CSS carries the palette), not just marker existence, so a tampered marker/token/CSS is detected and repaired by `-Reapply`.
- Concurrency hardening: the manifest write cleans up its temp on failure, an abandoned mutex is treated as acquisition (not a timeout), and the duplicate-function static gate is enforced across all installer modules.
- `-Target all` without Node no longer aborts globally: native/source-tree targets still run, absent generated-build targets skip, and present generated-build consumers fail with an aggregated result.

## [1.26.5] - 2026-08-11

- `-Reapply` now decides by TARGET HEALTH, not just the Wintage payload version: an application update or a moved install (same payload, new app version / new path / lost theme) triggers a re-apply, and an unhealthy recorded target is reported instead of skipped. `-Reapply -WhatIf` runs each child's real preflight so a broken helper surfaces as a nonzero exit, and an explicit or manifest-recorded target that cannot be resolved is a hard failure (bulk `-Target all` keeps treating genuine absence as a skip).
- Electron installs are now a real state machine: `stock / themed-relocated / updated-relocated / themed-inplace / updated-inplace / ambiguous` are classified from the actual layout, an app update leaves the NEW archive as the rollback source (Revert restores the current version, never the old one), the relocation move is a rollback-protected transaction, and a machine-readable `--status-json` plus a working `--version` after relocation feed the health probe.
- FreeBuff is one transaction: top-level Revert undoes the shim AND the ad/sound patch, the missing patch helper is a hard failure, `-WhatIf` validates both layers, and the patch is preflight-first with a single complete-transaction backup that Revert refuses to split.
- Revert now restores ONLY the fields Wintage owns, merged into the current config: Windows Terminal, OBS, Obsidian and Total Commander no longer restore whole old files, so unrelated edits made after Apply survive a revert. Obsidian advances/removes its manifest entry only after every vault succeeds.
- Source-tree targets (SMART VAC CLEANER, WildRift) re-base their rollback backup when the upstream source changes, so an update survives repaint and revert never restores an obsolete version.
- Manifest writes are serialized across processes (named lock + unique temp), so a GUI, CLI and logon task can no longer overwrite each other's entries.
- GUI polish: the status line visibly resets its failure colour on a later success, a failed target listing is preserved instead of dropped, and malformed app version directories no longer crash discovery.

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
