# Desktop README documentation-contract regression suite (T-211 / CORE-012).
#
# The audit caught three user-facing contract drifts between desktop/README.md
# and the live code:
#   1. Terminal font: README said "Consolas 12" while install.ps1 and
#      install-terminal.js apply Terminus (TTF) for Windows.
#   2. Terminal Revert model: README said "kept byte-for-byte" while the
#      helper performs an owned-field merge so comments and unrelated settings
#      survive.
#   3. Electron executable bytes: README said "No application byte is
#      rewritten" while install-electron.js supports fuse defusing for
#      supported BLOCKED states, backed by a byte-exact <exe>.wintage-fuse.bak.
#
# This test enforces the live contracts are described in the canonical README.
# A future change that flips any of the three contracts must flip the
# matching wording too -- the test fails closed.
#
#   .\tools\test-readme-contract.ps1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$readme = Join-Path $here '..\desktop\README.md'
$installer = Join-Path $here '..\desktop\install.ps1'
$terminal = Join-Path $here '..\tools\install-terminal.js'
$electronFuses = Join-Path $here '..\tools\electron-fuses.js'
$installElectron = Join-Path $here '..\tools\install-electron.js'
$pass = 0; $fail = 0

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

$md = Get-Content $readme -Raw

# ---- Test 1: Terminal font contract ----
# Live code applies Terminus (TTF); README must say Terminus, not Consolas.
$inst = Get-Content $installer -Raw
$term = Get-Content $terminal -Raw
$liveFontTerminal = ($inst -match 'CONSOLE_FONT\s*=\s*[''"]?Terminus') -or ($term -match "FaceName\s*[:=]\s*['""]?Terminus")
check 'live: install.ps1 / install-terminal.js actually apply Terminus (TTF)' $liveFontTerminal
check 'readme: Terminal row mentions Terminus (TTF)' ($md -match 'terminal.*Terminus \(TTF\)')
$readmeConsolasTerminal = ($md | Select-String -Pattern 'Consolas 12' -SimpleMatch) | Where-Object { $_.LineNumber -ge 50 -and $_.LineNumber -le 80 }
check 'readme: Terminal row no longer says "Consolas 12"' (-not $readmeConsolasTerminal)

# ---- Test 2: Terminal Revert contract ----
# Live code merges owned fields into the current document so comments /
# unrelated settings survive; README must say "merge" or "owned-field",
# not "byte-for-byte beside it".
$liveRevertMerge = $term -match "mergeOwnedIntoCurrent|owned|hasOwned"
check 'live: install-terminal.js does an owned-field merge (not whole-file byte-exact)' $liveRevertMerge
$hasMerge = $md -match 'owned(-| )field|fields Wintage owns|merge|merge(.*)owned|surgical'
check 'readme: Terminal Revert section mentions owned-field / merge' $hasMerge
$hasByteForByte = ($md | Select-String -Pattern 'byte-for-byte beside it' -SimpleMatch) | Where-Object { $_.LineNumber -ge 155 -and $_.LineNumber -le 175 }
check 'readme: Terminal section no longer says "kept byte-for-byte beside it"' (-not $hasByteForByte)

# ---- Test 3: Electron executable fuse defuse contract ----
# Live code supports fuse defusing for supported BLOCKED states and keeps a
# byte-exact <exe>.wintage-fuse.bak; README must describe the contract.
$liveDefuse = (Get-Content $electronFuses -Raw) -match 'function defuse|defuse\('
$liveBackup  = (Get-Content $installElectron -Raw) -match 'wintage-fuse\.bak|defuse\(|ensureDefused'
check 'live: electron-fuses.js exports a defuse() function' $liveDefuse
check 'live: install-electron.js wires defuse + <exe>.wintage-fuse.bak' $liveBackup
$hasDefuse = $md -match 'defuse|wintage-fuse\.bak'
check 'readme: Electron section mentions defuse / <exe>.wintage-fuse.bak' $hasDefuse
$hasNoBytes = ($md | Select-String -Pattern 'No application byte is rewritten' -SimpleMatch) | Where-Object { $_.LineNumber -ge 220 -and $_.LineNumber -le 240 }
check 'readme: Electron section no longer claims "No application byte is rewritten"' (-not $hasNoBytes)

# ---- Test 4: terminal-font gate hook ----
# The audit's verify clause says: existing test-terminal-font.js must no longer
# be able to pass while README still advertises Consolas. The live gate is in
# tests/Run-Tests.ps1 (font assert). Confirm the font assert references
# Terminus, not Consolas.
$runTests = Get-Content (Join-Path $here '..\tests\Run-Tests.ps1') -Raw
$runTestsAssertsTerminus = $runTests -match 'Terminus' -and ($runTests -notmatch 'Consolas')
check 'gate: tests/Run-Tests.ps1 font assert references Terminus (not Consolas)' $runTestsAssertsTerminus

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail
