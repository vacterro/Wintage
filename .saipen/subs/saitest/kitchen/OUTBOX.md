# OUTBOX — saitest reproductions from crew circuit sc (E-479 hunt)

## ST-002: REPRODUCED — node exit codes unchecked in WintageInstaller.ps1 Save-Custom/Delete-Custom

- **status:** ready
- **source_head:** 6ffc5cc
- **summary:** `desktop/WintageInstaller.ps1` lines 870-871 and 880-881 call `node tools/apply-themes.js` and `node tools/build-desktop.js`, pipe output to `Out-Null`, but never check `$LASTEXITCODE`. If node fails, theme packs are stale but Load-Packs runs on old data silently. Contrast with `install.ps1:1351-1352` which checks exit code correctly.
- **payload:** MEDIUM bug. Two call sites need `if ($LASTEXITCODE -ne 0) { Say-Log 'rebuild failed'; return }` guards.
- **coverage:** grep proves the `& node` calls at lines 870-871 and 880-881 are followed by no `$LASTEXITCODE` check.
- **verified:** REPRODUCED — unguarded node calls confirmed at exact lines.
- **instructions:** Add `$LASTEXITCODE` check after both node calls in Save-Custom and Delete-Custom functions.

## ST-003: REPRODUCED — write-Utf8Lines dead function in install.ps1

- **status:** ready
- **source_head:** 6ffc5cc
- **summary:** `desktop/install.ps1` line 62 defines `function Write-Utf8Lines` — a BOM-less line-array writer. Zero call sites exist in the project. Only its sibling `Write-Utf8BomLines` (line 64) is used (for TotalCmd wincmd.ini BOM requirement).
- **payload:** LOW cleanup. Remove the dead function or repurpose it (one existing write-Write-Utf8 to string path could use the line-array variant instead of joining).
- **coverage:** `rg "Write-Utf8Lines\b"` across all .ps1 files returns exactly 1 match — the definition.
- **verified:** REPRODUCED — grep confirms zero call sites.
- **instructions:** Remove the dead `Write-Utf8Lines` function from install.ps1:62.

## ST-004: REPRODUCED — stale kitchen file verify-t017-render-equivalence.js

- **status:** ready
- **source_head:** 6ffc5cc
- **summary:** `.saipen/kitchen/verify-t017-render-equivalence.js` belongs to T-017 which is DONE on BOARD.md. 72-line one-shot verification script, no longer exercisable. Per hunt.md's kitchen stale rule (owning ticket DONE and off BOARD.md).
- **payload:** LOW cleanup. Delete the file.
- **coverage:** T-017 is `[x]` in DONE section. File is 72 lines, last referenced in E-047 log event.
- **verified:** REPRODUCED — file exists, T-017 DONE, no references from active code.
- **instructions:** Delete `verify-t017-render-equivalence.js`. Recoverable via git (tracked at HEAD).

## ST-005: REPRODUCED — orphan convenience launcher tests/run.cmd

- **status:** ready
- **source_head:** 6ffc5cc
- **summary:** `tests/run.cmd` is a 3-line CMD launcher calling `tests/Run-Tests.ps1`. Zero references from any project file, doc, or config. Convenience wrapper with no documented purpose.
- **payload:** LOW cleanup. Delete or document.
- **coverage:** `rg "run\.cmd"` across all project files returns zero matches (only the self-reference when grepping the file itself).
- **verified:** REPRODUCED — zero references, exists on disk.
- **instructions:** Delete `tests/run.cmd`. Recoverable via git.

## ST-006: REPRODUCED — reg import/export exit codes unchecked in install.ps1 MPC-HC paths

- **status:** ready
- **source_head:** 6ffc5cc
- **summary:** `desktop/install.ps1` line 1098 calls `reg import $bak 2>&1 | Out-Null` without checking `$LASTEXITCODE`. Line 1108 calls `reg export $MPC_REG $bak /y 2>&1 | Out-Null` without checking `$LASTEXITCODE`. Failed import = silent no-op; failed backup = no restore available, user unaware.
- **payload:** LOW bug. Add `$LASTEXITCODE` guards or Write-Warning on failure.
- **coverage:** grep proves both reg calls are piped to Out-Null with no subsequent `$LASTEXITCODE` check.
- **verified:** REPRODUCED — unguarded reg calls confirmed at exact lines.
- **instructions:** Add `if ($LASTEXITCODE -ne 0) { Write-Warning ... }` after both reg calls in Invoke-MpcHc.

## ST-007: REPRODUCED — build-desktop.js exit code unchecked in watch-claude.ps1

- **status:** ready
- **source_head:** 6ffc5cc
- **summary:** `tools/watch-claude.ps1` line 18 runs `node tools/build-desktop.js` after `check-css.js` passes, but never checks `$LASTEXITCODE`. If check-css passes but build-desktop fails, hot-reload copies a stale/broken CSS file into the Claude app.
- **payload:** MEDIUM bug. Add `if ($LASTEXITCODE -ne 0) { Write-Host 'build failed'; return }` guard.
- **coverage:** grep proves line 18 is the node call, and there is no `$LASTEXITCODE` check following it.
- **verified:** REPRODUCED — unguarded build call confirmed.
- **instructions:** Add `$LASTEXITCODE` guard after `node tools/build-desktop.js` in watch-claude.ps1.

## ST-101: REPRODUCED — Core-share README ru/et/ded carry no source-digest marker (Damaged state)

- **status:** reviewed
- **source_head:** c3925a4
- **summary:** `README.ru.md`, `README.et.md`, `README.ded.md` (repo root AND `.saipen/saitranslate/kitchen/`) have no `<!-- source-digest: README.md sha256:... -->` line, while all 29 bundle translations DO. translate.md §3 requires every locale README to carry the source digest of the English source it was translated from; the three Core-share locales are the only ones missing it. A locale without its digest is a half-written record — nothing signals when it has gone stale.
- **payload:** LOW defect. Add the current digest line (`sha256:ee7c6a2a1626faed`) to all three files, root + kitchen copies.
- **coverage:** script scan of all 32 root README.*.md found exactly 3 without a digest marker (ru/et/ded); kitchen copies confirmed identical state.
- **verified:** REPRODUCED — `Select-String "source-digest"` returns no match for ru/et/ded in root and kitchen; 29 bundle files all carry it.
- **instructions:** Append `<!-- source-digest: README.md sha256:ee7c6a2a1626faed -->` to README.ru.md, README.et.md, README.ded.md (root + kitchen copies stay byte-identical).

## ST-102: REPRODUCED — Core-share translations absent on desktop/README and browser-theme surfaces (Boundary)

- **status:** reviewed
- **source_head:** c3925a4
- **summary:** `desktop/README.<lang>.md` and `browser-theme/README.<lang>.txt` exist for all 29 bundle languages, but NO `desktop/README.ru.md`/`et.md`/`ded.md` and NO `browser-theme/README.ru.txt`/`et.txt`/`ded.txt` exist (checked repo root and saitranslate kitchen). The root README has Core-share ru/et/ded; the two other surfaces are 29/29 with zero Core-share coverage. Asymmetry: a Russian/Polish... (RU/ET/Дед) user gets translated install docs on one surface and English-only on the others. Boundary family: 0 Core-share + 29 bundle = the set is not complete.
- **payload:** LOW gap. Either translate desktop/README + browser-theme README into ru/et/ded (Core share), or document the intentional omission.
- **coverage:** directory listing of desktop/ and browser-theme/ shows ru/et/ded absent; kitchen mirrors confirm.
- **verified:** REPRODUCED — `Test-Path` for all six (desktop ru/et/ded, browser-theme ru/et/ded) returns False in root and kitchen; all 29 bundle files present.
- **instructions:** Core decides: translate the two surfaces into ru/et/ded, or record the omission as intentional.

## ST-103: NOT_REPRODUCED — bundle translations and BetterDiscord theme are structurally clean

- **status:** reviewed
- **source_head:** c3925a4
- **summary:** Adversarial sweep of the two newest changes found no breakage:
  - ST-002-part: all 29 root README.<lang>.md have `[EN](README.md)` switcher bar, correct digest (`ee7c6a2a1626faed`), zero stale legacy hexes, valid UTF-8.
  - ST-003-part: all 33 `desktop/locales/*.json` parse (ConvertFrom-Json) and carry exactly the en.json 49-key set (0 missing, 0 extra).
  - ST-004-part: all 16 `desktop/out/betterdiscord/<slug>/wintage.theme.css` have balanced braces, BD `@name`/`@author` header, the required Discord variables (`--background-primary`, `--text-normal`, `--interactive-normal`, `--brand-experiment`, `--channeltextarea-background`, `--scrollbar-auto-thumb`), and zero unresolved `${` placeholders.
- **payload:** none — no fix needed.
- **coverage:** programmatic scan (python) of 32 READMEs, 33 locales, 16 BetterDiscord CSS files.
- **verified:** NOT_REPRODUCED — all checks green; the only findings in the run are ST-101 and ST-102 above.
- **instructions:** none; the negative result is the deliverable (nobody retries these blind).
