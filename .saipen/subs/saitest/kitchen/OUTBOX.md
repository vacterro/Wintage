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
