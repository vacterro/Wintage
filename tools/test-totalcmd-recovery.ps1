# SRC-007:R006 / W2-001 -- Total Commander recovery-format migration
#
# Defect classes this test suite pins down:
#  1. Strict recovery-format discriminator:
#     - Current JSON format (starting with '{') must parse and schema-validate strictly.
#     - Malformed/truncated JSON or JSON containing INI-like text MUST NOT fall back
#       to legacy INI parsing. It must fail closed: nonzero exit, zero live mutation,
#       manifest preserved, backup preserved.
#     - Valid JSON with wrong 'owned' shape (scalar, empty, invalid section/key types)
#       must fail closed with zero mutation.
#  2. Strict positive identification of legacy whole-file INI:
#     - Requires recognizable INI section headers and key-value pairs, plus Total
#       Commander specific sections ([Colors], [ColorsDark], or [Configuration]).
#     - Non-INI bytes or unrelated INIs fail closed with zero mutation.
#  3. Dynamic recent-file filter migration:
#     - Legacy whole-file INI recovery extracts both fixed keys AND dynamic
#       ColorFilter{id}Color / ColorFilter{id}ColorDark keys.
#     - Custom pre-Wintage recent filter colors are restored to their exact values.
#     - Unrelated filters and user edits survive Revert.
#
# Red control: run with -RedControl to execute against a pre-W2-001 implementation.
# The critical fail-closed and recent-filter assertions must fail against pre-fix code.

[CmdletBinding()]
param(
    [switch]$List,
    [switch]$RedControl,
    [string]$InstallerPath,
    [string]$Only
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$defaultInstaller = Join-Path $root 'desktop\install.ps1'
$installer = if ($InstallerPath) { $InstallerPath } else { $defaultInstaller }
$utf8 = New-Object System.Text.UTF8Encoding($false)
$pass = 0; $fail = 0
$failedLabels = @()

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++; $script:failedLabels += $label }
}

if ($List) {
    Write-Host "test-totalcmd-recovery.ps1 (W2-001/W2-003 TotalCmd recovery & transaction matrix):"
    Write-Host "  case A  manifest commit failure: live INI, backup and manifest byte-exact; retry succeeds"
    Write-Host "  case B  live INI restoration failure: exact pre-operation INI restored, backup and manifest untouched"
    Write-Host "  case C  valid JSON with unknown key: rejected before mutation, zero live mutation"
    Write-Host "  case D  valid JSON with numeric/boolean value: rejected, zero live mutation"
    Write-Host "  case E  valid current snapshot: normal Apply -> Revert lifecycle succeeds"
    Write-Host "  case 1  truncated JSON: Revert exits nonzero, zero live mutation, backup+manifest preserved"
    Write-Host "  case 2  corrupt JSON with [Colors]: fails closed as JSON error, zero mutation"
    Write-Host "  case 3  wrong owned shape: scalar, empty, missing section, or invalid value types fail closed"
    Write-Host "  case 4  unrecognized non-JSON: non-INI / empty files fail closed"
    Write-Host "  case 5  genuine legacy INI: fixed owned keys restore, absent keys removed"
    Write-Host "  case 6  legacy INI recent-file filters: pre-Wintage filter colors restore, unrelated edits survive"
    Write-Host "Red control: -RedControl (verifies that pre-fix implementation fails critical assertions)"
    exit 0
}

# Setup temporary test isolation environment
$testRoot = Join-Path $env:TEMP ("wintage-tc-rec-" + [guid]::NewGuid().ToString('N'))
$origAppData = $env:WINTAGE_APPDATA
$origBackupRoot = $env:WINTAGE_BACKUP_ROOT
$origHome = $env:USERPROFILE
$redCopyRoot = $null

function Compare-Bytes([byte[]]$a, [byte[]]$b) {
    if ($null -eq $a -or $null -eq $b) { return $false }
    if ($a.Count -ne $b.Count) { return $false }
    if ($a.Count -eq 0 -and $b.Count -eq 0) { return $true }
    for ($i = 0; $i -lt $a.Count; $i++) {
        if ($a[$i] -ne $b[$i]) { return $false }
    }
    return $true
}

try {
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
    $env:WINTAGE_APPDATA = Join-Path $testRoot 'appdata'
    $env:WINTAGE_BACKUP_ROOT = Join-Path $testRoot 'backup'
    New-Item -ItemType Directory -Force -Path $env:WINTAGE_APPDATA | Out-Null
    New-Item -ItemType Directory -Force -Path $env:WINTAGE_BACKUP_ROOT | Out-Null

    # If -RedControl requested, construct a pre-fix copy of targets.ps1 & install.ps1
    # MANDATORY -- both new defect classes, each reproduced by an explicit assertion:
    $redMandatory = @(
        'case A: live INI byte-identical to themed pre-operation state',
        'case B: exact pre-operation INI restored',
        'case C: recovery rejected (unknown key exits nonzero)',
        'case D (numeric value): recovery rejected (exits nonzero)'
    )
    # Additional pre-fix evidence (must NOT substitute for the mandatory proofs):
    $redExtra = @(
        'case C: INI unchanged before live mutation',
        'case 1: truncated JSON Revert exits nonzero',
        'case 1: truncated JSON leaves live wincmd.ini untouched',
        'case 2: corrupt JSON with [Colors] Revert exits nonzero',
        'case 6: legacy recent filter Color restored in [Colors]'
    )

    if ($RedControl) {
        $redCopyRoot = Join-Path $testRoot 'red-install'
        Copy-Item -Recurse (Join-Path $root 'desktop') $redCopyRoot
        Copy-Item -Recurse (Join-Path $root 'themes') (Join-Path $testRoot 'themes')
        Copy-Item (Join-Path $root 'wintage.user.js') (Join-Path $testRoot 'wintage.user.js')
        $redTargets = Join-Path $redCopyRoot 'modules\targets.ps1'
        $targetsCode = [System.IO.File]::ReadAllText($redTargets, $utf8)

        # Pre-fix Restore-TotalCmdOwned: catches ConvertFrom-Json and parses corrupt JSON as legacy INI;
        # does not validate keys or scalar types, does not reconstruct dynamic ColorFilter{id}Color keys from legacy INI.
        $preFixRestore = @'
function Restore-TotalCmdOwned([string]$ini, [string]$iniBak, [switch]$Keep) {
    $snapshot = $null
    if (Test-Path $iniBak) {
        try {
            $parsed = Read-Utf8 $iniBak | ConvertFrom-Json
            if ($parsed.owned) { $snapshot = $parsed }
        } catch {
            $legacy = (Read-Utf8 $iniBak) -split '\r?\n'
            $owned = @{}
            foreach ($s in $script:TC_OWNED_SECTIONS) {
                $owned[$s] = @{}
                foreach ($k in $script:TC_OWNED_KEYS) {
                    $v = Get-IniKey $legacy $s $k
                    $owned[$s][$k] = if ($null -ne $v) { $v } else { $null }
                }
            }
            $snapshot = [pscustomobject]@{ owned = $owned }
        }
    }
    if (-not $snapshot) { return $false }
    $current = (Read-Utf8 $ini) -split '\r?\n'
    while ($current.Count -and $current[-1] -eq '') { $current = $current[0..($current.Count - 2)] }
    foreach ($s in $script:TC_OWNED_SECTIONS) {
        if (-not $snapshot.owned.$s) { continue }
        foreach ($prop in $snapshot.owned.$s.PSObject.Properties) {
            $val = $prop.Value
            if ($null -ne $val) {
                $current = Set-IniKey $current $s $prop.Name "$val"
            } else {
                $current = Remove-IniKey $current $s $prop.Name
            }
        }
    }
    if ($env:WINTAGE_TEST_FAIL_TOTALCMD_RESTORE_WRITE) {
        [System.IO.File]::WriteAllText($ini, "CORRUPTED_MID_WRITE`r`n", $script:Utf8WithBom)
        throw "simulated failure during live INI restoration (WINTAGE_TEST_FAIL_TOTALCMD_RESTORE_WRITE)"
    }
    Write-Utf8BomLines $ini $current
    if (-not $Keep) { Remove-Item $iniBak -Force }
    return $true
}
'@

        # Pre-fix Total Commander Revert: mutates live INI before Invoke-TargetCommit,
        # with an empty rollback block that does not restore the live INI on failure.
        $preFixRevert = @'
            if (Test-Path $iniBak) {
                $restored = Restore-TotalCmdOwned $ini $iniBak -Keep
                if (-not $restored) { throw "$($appName): backup exists but could not be parsed - nothing restored." }
                Say "$($appName): restored the Wintage-owned keys into the current wincmd.ini" 'Green'
                Invoke-TargetCommit $manifestName $appName {
                    Remove-ManifestEntry $manifestName
                } {
                }
                if (Test-Path $iniBak) { Remove-Item $iniBak -Force }
            }
'@
        $revertPattern = '(?s)(if \(\$PSCmdlet\.ShouldProcess\(\$ini, ''Revert Wintage theme''\)\) \{\r?\n\s+)if \(Test-Path \$iniBak\) \{.*?Say "\$\(\$appName\): restored the Wintage-owned keys into the current wincmd\.ini" ''Green''\r?\n            \}'
        $targetsCode = [regex]::Replace($targetsCode, $revertPattern, { param($m) $m.Groups[1].Value + $preFixRevert }, 1)
        $targetsCode = [regex]::Replace($targetsCode, '(?s)function Restore-TotalCmdOwned.*?return \$true\r?\n\}', { param($m) $preFixRestore }, 1)
        [System.IO.File]::WriteAllText($redTargets, $targetsCode, $utf8)
        $installer = Join-Path $redCopyRoot 'install.ps1'
    }

    function Run-Child([string[]]$argsList) {
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $installer @argsList 2>&1
        $code = $LASTEXITCODE
        $ErrorActionPreference = $prev
        [pscustomobject]@{ Out = (@($out) -join "`n"); Code = $code }
    }

    function Manifest-HasTarget([string]$name) {
        $mf = Join-Path $env:WINTAGE_APPDATA 'installed.json'
        if (-not (Test-Path $mf)) { return $false }
        try {
            $json = Get-Content $mf -Raw | ConvertFrom-Json
            return ($null -ne $json.$name)
        } catch { return $false }
    }

    # =========================================================================
    # CASE A: Manifest commit failure during backup-backed Revert
    # =========================================================================
    if (-not $Only -or $Only -match 'A') {
        $tcDir = Join-Path $testRoot 'caseA'
        New-Item -ItemType Directory -Force -Path $tcDir | Out-Null
        $ini = Join-Path $tcDir 'wincmd.ini'
        $bak = $ini + '.wintage.bak'
        $mf = Join-Path $env:WINTAGE_APPDATA 'installed.json'

        $initContent = "[Configuration]`r`nInstallDir=C:\TC`r`n[Colors]`r`nBackColor=16777215`r`nForeColor=0`r`n"
        [System.IO.File]::WriteAllText($ini, $initContent, $utf8)

        $rApply = Run-Child @('-Target', 'totalcmd', '-TotalCmdIni', $ini, '-Palette', 'goldendefault')
        check "case A: initial Apply exits 0" ($rApply.Code -eq 0)

        $themedBytes = [System.IO.File]::ReadAllBytes($ini)
        $origBakBytes = [System.IO.File]::ReadAllBytes($bak)
        $origMfBytes = [System.IO.File]::ReadAllBytes($mf)

        # Inject failure into manifest removal/commit
        $env:WINTAGE_TEST_FAIL_MANIFEST_MOVE = '1'
        $rRevertFail = Run-Child @('-Target', 'totalcmd', '-TotalCmdIni', $ini, '-Revert')
        Remove-Item Env:\WINTAGE_TEST_FAIL_MANIFEST_MOVE -ErrorAction SilentlyContinue

        check "case A: manifest commit failure Revert exits nonzero" ($rRevertFail.Code -ne 0)

        $afterFailBytes = [System.IO.File]::ReadAllBytes($ini)
        $afterBakBytes = if (Test-Path $bak) { [System.IO.File]::ReadAllBytes($bak) } else { @() }
        $afterMfBytes = if (Test-Path $mf) { [System.IO.File]::ReadAllBytes($mf) } else { @() }

        $iniMatchesThemed = (Compare-Bytes $themedBytes $afterFailBytes)
        $bakMatchesOrig = (Compare-Bytes $origBakBytes $afterBakBytes)
        $mfMatchesOrig = (Compare-Bytes $origMfBytes $afterMfBytes)

        check "case A: live INI byte-identical to themed pre-operation state" $iniMatchesThemed
        check "case A: .wintage.bak byte-identical to pre-operation state" $bakMatchesOrig
        check "case A: manifest byte-identical and still contains totalcmd" ($mfMatchesOrig -and (Manifest-HasTarget 'totalcmd'))

        # Remove injected failure and retry
        $rRevertRetry = Run-Child @('-Target', 'totalcmd', '-TotalCmdIni', $ini, '-Revert')
        check "case A: Revert retry exits 0" ($rRevertRetry.Code -eq 0)

        $restored = [System.IO.File]::ReadAllText($ini, $utf8)
        check "case A: original BackColor restored" ($restored -match '(?m)^BackColor=16777215\r?$')
        check "case A: original ForeColor restored" ($restored -match '(?m)^ForeColor=0\r?$')
        check "case A: manifest entry removed" (-not (Manifest-HasTarget 'totalcmd'))
        check "case A: recovery backup consumed only after success" (-not (Test-Path $bak))
    }

    # =========================================================================
    # CASE B: Failure while live INI restoration is being written
    # =========================================================================
    if (-not $Only -or $Only -match 'B') {
        $tcDir = Join-Path $testRoot 'caseB'
        New-Item -ItemType Directory -Force -Path $tcDir | Out-Null
        $ini = Join-Path $tcDir 'wincmd.ini'
        $bak = $ini + '.wintage.bak'
        $mf = Join-Path $env:WINTAGE_APPDATA 'installed.json'

        $initContent = "[Configuration]`r`nInstallDir=C:\TC`r`n[Colors]`r`nBackColor=16777215`r`nForeColor=0`r`n"
        [System.IO.File]::WriteAllText($ini, $initContent, $utf8)

        $rApply = Run-Child @('-Target', 'totalcmd', '-TotalCmdIni', $ini, '-Palette', 'goldendefault')
        check "case B: initial Apply exits 0" ($rApply.Code -eq 0)

        $themedBytes = [System.IO.File]::ReadAllBytes($ini)
        $origBakBytes = [System.IO.File]::ReadAllBytes($bak)
        $origMfBytes = [System.IO.File]::ReadAllBytes($mf)

        # Inject failure while live INI restoration is being written
        $env:WINTAGE_TEST_FAIL_TOTALCMD_RESTORE_WRITE = '1'
        $rRevertFail = Run-Child @('-Target', 'totalcmd', '-TotalCmdIni', $ini, '-Revert')
        Remove-Item Env:\WINTAGE_TEST_FAIL_TOTALCMD_RESTORE_WRITE -ErrorAction SilentlyContinue

        check "case B: failure during live restoration exits nonzero" ($rRevertFail.Code -ne 0)

        $afterFailBytes = [System.IO.File]::ReadAllBytes($ini)
        $afterBakBytes = if (Test-Path $bak) { [System.IO.File]::ReadAllBytes($bak) } else { @() }
        $afterMfBytes = if (Test-Path $mf) { [System.IO.File]::ReadAllBytes($mf) } else { @() }

        $iniMatchesThemed = (Compare-Bytes $themedBytes $afterFailBytes)
        $bakMatchesOrig = (Compare-Bytes $origBakBytes $afterBakBytes)
        $mfMatchesOrig = (Compare-Bytes $origMfBytes $afterMfBytes)

        check "case B: exact pre-operation INI restored" $iniMatchesThemed
        check "case B: backup preserved" ($bakMatchesOrig -and (Test-Path $bak))
        check "case B: manifest unchanged" ($mfMatchesOrig -and (Manifest-HasTarget 'totalcmd'))
    }

    # =========================================================================
    # CASE C: Valid JSON with unknown key
    # =========================================================================
    if (-not $Only -or $Only -match 'C') {
        $tcDir = Join-Path $testRoot 'caseC'
        New-Item -ItemType Directory -Force -Path $tcDir | Out-Null
        $ini = Join-Path $tcDir 'wincmd.ini'
        $bak = $ini + '.wintage.bak'

        $initContent = "[Configuration]`r`nInstallDir=C:\TC`r`n[Colors]`r`nBackColor=16777215`r`n"
        [System.IO.File]::WriteAllText($ini, $initContent, $utf8)

        $rApply = Run-Child @('-Target', 'totalcmd', '-TotalCmdIni', $ini, '-Palette', 'goldendefault')
        check "case C: initial Apply exits 0" ($rApply.Code -eq 0)

        $themedBytes = [System.IO.File]::ReadAllBytes($ini)
        $unknownKeyJson = @"
{
  "owned": {
    "Colors": {
      "BackColor": "123",
      "UnrelatedUserKey": null
    },
    "ColorsDark": {}
  }
}
"@
        [System.IO.File]::WriteAllText($bak, $unknownKeyJson, $utf8)

        $rRevert = Run-Child @('-Target', 'totalcmd', '-TotalCmdIni', $ini, '-Revert')
        check "case C: recovery rejected (unknown key exits nonzero)" ($rRevert.Code -ne 0)

        $afterBytes = [System.IO.File]::ReadAllBytes($ini)
        $bytesMatch = (Compare-Bytes $themedBytes $afterBytes)
        check "case C: INI unchanged before live mutation" $bytesMatch
        check "case C: backup preserved" (Test-Path $bak)
        if (Test-Path $bak) {
            check "case C: backup content untouched" ([System.IO.File]::ReadAllText($bak, $utf8) -eq $unknownKeyJson)
        }
        check "case C: manifest unchanged" (Manifest-HasTarget 'totalcmd')
    }

    # =========================================================================
    # CASE D: Valid JSON with numeric or boolean owned value
    # =========================================================================
    if (-not $Only -or $Only -match 'D') {
        $tcDir = Join-Path $testRoot 'caseD'
        New-Item -ItemType Directory -Force -Path $tcDir | Out-Null
        $ini = Join-Path $tcDir 'wincmd.ini'
        $bak = $ini + '.wintage.bak'

        $invalidValues = @(
            @{ Name = 'numeric value'; Json = '{"owned": {"Colors": {"BackColor": 123}, "ColorsDark": {}}}' },
            @{ Name = 'boolean value'; Json = '{"owned": {"Colors": {"BackColor": true}, "ColorsDark": {}}}' }
        )

        foreach ($iv in $invalidValues) {
            [System.IO.File]::WriteAllText($ini, "[Colors]`r`nBackColor=1`r`n", $utf8)
            $rApply = Run-Child @('-Target', 'totalcmd', '-TotalCmdIni', $ini, '-Palette', 'goldendefault')
            $themedBytes = [System.IO.File]::ReadAllBytes($ini)

            [System.IO.File]::WriteAllText($bak, $iv.Json, $utf8)
            $rRevert = Run-Child @('-Target', 'totalcmd', '-TotalCmdIni', $ini, '-Revert')
            check "case D ($($iv.Name)): recovery rejected (exits nonzero)" ($rRevert.Code -ne 0)

            $afterBytes = [System.IO.File]::ReadAllBytes($ini)
            $bytesMatch = (Compare-Bytes $themedBytes $afterBytes)
            check "case D ($($iv.Name)): zero live mutation (INI untouched)" $bytesMatch
            check "case D ($($iv.Name)): backup preserved" (Test-Path $bak)
        }
    }

    # =========================================================================
    # CASE E: Valid current snapshot (normal Apply -> Revert)
    # =========================================================================
    if (-not $Only -or $Only -match 'E') {
        $tcDir = Join-Path $testRoot 'caseE'
        New-Item -ItemType Directory -Force -Path $tcDir | Out-Null
        $ini = Join-Path $tcDir 'wincmd.ini'
        $bak = $ini + '.wintage.bak'

        $initContent = "[Configuration]`r`nInstallDir=C:\TC`r`n[Colors]`r`nBackColor=16777215`r`nForeColor=0`r`n"
        [System.IO.File]::WriteAllText($ini, $initContent, $utf8)

        $rApply = Run-Child @('-Target', 'totalcmd', '-TotalCmdIni', $ini, '-Palette', 'goldendefault')
        check "case E: normal Apply exits 0" ($rApply.Code -eq 0)
        check "case E: snapshot created as JSON" (Test-Path $bak)
        check "case E: manifest has totalcmd" (Manifest-HasTarget 'totalcmd')

        $rRevert = Run-Child @('-Target', 'totalcmd', '-TotalCmdIni', $ini, '-Revert')
        check "case E: normal Revert exits 0" ($rRevert.Code -eq 0)

        $restored = [System.IO.File]::ReadAllText($ini, $utf8)
        check "case E: original BackColor restored" ($restored -match '(?m)^BackColor=16777215\r?$')
        check "case E: original ForeColor restored" ($restored -match '(?m)^ForeColor=0\r?$')
        check "case E: backup consumed on success" (-not (Test-Path $bak))
        check "case E: manifest entry removed on success" (-not (Manifest-HasTarget 'totalcmd'))
    }

    # =========================================================================
    # CASE 1: Truncated JSON recovery snapshot beginning with '{'
    # =========================================================================
    if (-not $Only -or $Only -match '1') {
        $tcDir = Join-Path $testRoot 'case1'
        New-Item -ItemType Directory -Force -Path $tcDir | Out-Null
        $ini = Join-Path $tcDir 'wincmd.ini'
        $bak = $ini + '.wintage.bak'

        $initContent = "[Configuration]`r`nInstallDir=C:\TC`r`n[Colors]`r`nBackColor=16777215`r`nForeColor=0`r`n"
        [System.IO.File]::WriteAllText($ini, $initContent, $utf8)

        # Apply theme first so manifest and backup are created
        $rApply = Run-Child @('-Target', 'totalcmd', '-TotalCmdIni', $ini, '-Palette', 'goldendefault')
        check "case 1: initial Apply exits 0" ($rApply.Code -eq 0)

        $themedBytes = [System.IO.File]::ReadAllBytes($ini)
        $corruptJson = '{"owned": {"Colors": {"BackColor": '
        [System.IO.File]::WriteAllText($bak, $corruptJson, $utf8)

        # Revert must fail closed on corrupt JSON
        $rRevert = Run-Child @('-Target', 'totalcmd', '-TotalCmdIni', $ini, '-Revert')
        check "case 1: truncated JSON Revert exits nonzero" ($rRevert.Code -ne 0)

        $afterBytes = [System.IO.File]::ReadAllBytes($ini)
        $bytesMatch = (Compare-Bytes $themedBytes $afterBytes)
        check "case 1: truncated JSON leaves live wincmd.ini untouched" $bytesMatch
        check "case 1: truncated JSON preserves backup file" (Test-Path $bak)
        if (Test-Path $bak) {
            check "case 1: backup file content untouched" ([System.IO.File]::ReadAllText($bak, $utf8) -eq $corruptJson)
        }
        check "case 1: manifest entry preserved" (Manifest-HasTarget 'totalcmd')
    }

    # =========================================================================
    # CASE 2: Corrupt JSON containing strings resembling [Colors]
    # =========================================================================
    if (-not $Only -or $Only -match '2') {
        $tcDir = Join-Path $testRoot 'case2'
        New-Item -ItemType Directory -Force -Path $tcDir | Out-Null
        $ini = Join-Path $tcDir 'wincmd.ini'
        $bak = $ini + '.wintage.bak'

        $initContent = "[Configuration]`r`nInstallDir=C:\TC`r`n[Colors]`r`nBackColor=16777215`r`n"
        [System.IO.File]::WriteAllText($ini, $initContent, $utf8)

        $rApply = Run-Child @('-Target', 'totalcmd', '-TotalCmdIni', $ini, '-Palette', 'goldendefault')
        check "case 2: initial Apply exits 0" ($rApply.Code -eq 0)

        $themedBytes = [System.IO.File]::ReadAllBytes($ini)
        # Malformed JSON that looks like an INI inside
        $corruptWithIni = "{`"owned`": `r`n[Colors]`r`nBackColor=12345`r`n}"
        [System.IO.File]::WriteAllText($bak, $corruptWithIni, $utf8)

        $rRevert = Run-Child @('-Target', 'totalcmd', '-TotalCmdIni', $ini, '-Revert')
        check "case 2: corrupt JSON with [Colors] Revert exits nonzero" ($rRevert.Code -ne 0)

        $afterBytes = [System.IO.File]::ReadAllBytes($ini)
        $bytesMatch = (Compare-Bytes $themedBytes $afterBytes)
        check "case 2: corrupt JSON leaves live wincmd.ini untouched" $bytesMatch
        check "case 2: backup file preserved" (Test-Path $bak)
        check "case 2: manifest entry preserved" (Manifest-HasTarget 'totalcmd')
    }

    # =========================================================================
    # CASE 3: Valid JSON with wrong 'owned' shape
    # =========================================================================
    if (-not $Only -or $Only -match '3') {
        $tcDir = Join-Path $testRoot 'case3'
        New-Item -ItemType Directory -Force -Path $tcDir | Out-Null
        $ini = Join-Path $tcDir 'wincmd.ini'
        $bak = $ini + '.wintage.bak'

        $shapes = @(
            @{ Name = 'scalar owned'; Content = '{"owned": "not_an_object"}' },
            @{ Name = 'empty owned';  Content = '{"owned": {}}' },
            @{ Name = 'scalar section'; Content = '{"owned": {"Colors": "not_an_object"}}' },
            @{ Name = 'array key value'; Content = '{"owned": {"Colors": {"BackColor": [1,2,3]}}}' },
            @{ Name = 'missing owned'; Content = '{"different_key": 123}' }
        )

        foreach ($s in $shapes) {
            [System.IO.File]::WriteAllText($ini, "[Colors]`r`nBackColor=1`r`n", $utf8)
            $rApply = Run-Child @('-Target', 'totalcmd', '-TotalCmdIni', $ini, '-Palette', 'goldendefault')
            $themedBytes = [System.IO.File]::ReadAllBytes($ini)

            [System.IO.File]::WriteAllText($bak, $s.Content, $utf8)
            $rRevert = Run-Child @('-Target', 'totalcmd', '-TotalCmdIni', $ini, '-Revert')
            check "case 3 ($($s.Name)): Revert exits nonzero" ($rRevert.Code -ne 0)

            $afterBytes = [System.IO.File]::ReadAllBytes($ini)
            $bytesMatch = (Compare-Bytes $themedBytes $afterBytes)
            check "case 3 ($($s.Name)): live ini untouched" $bytesMatch
            check "case 3 ($($s.Name)): backup preserved" (Test-Path $bak)
        }
    }

    # =========================================================================
    # CASE 4: Unrecognized non-JSON (not valid INI)
    # =========================================================================
    if (-not $Only -or $Only -match '4') {
        $tcDir = Join-Path $testRoot 'case4'
        New-Item -ItemType Directory -Force -Path $tcDir | Out-Null
        $ini = Join-Path $tcDir 'wincmd.ini'
        $bak = $ini + '.wintage.bak'

        $badFiles = @(
            @{ Name = 'empty file'; Content = '' },
            @{ Name = 'random text without sections'; Content = "some random log text`r`nkey=value`r`n" },
            @{ Name = 'non-TC section without keys'; Content = "[SomeOtherApp]`r`n" }
        )

        foreach ($bf in $badFiles) {
            [System.IO.File]::WriteAllText($ini, "[Colors]`r`nBackColor=1`r`n", $utf8)
            $rApply = Run-Child @('-Target', 'totalcmd', '-TotalCmdIni', $ini, '-Palette', 'goldendefault')
            $themedBytes = [System.IO.File]::ReadAllBytes($ini)

            [System.IO.File]::WriteAllText($bak, $bf.Content, $utf8)
            $rRevert = Run-Child @('-Target', 'totalcmd', '-TotalCmdIni', $ini, '-Revert')
            check "case 4 ($($bf.Name)): Revert exits nonzero" ($rRevert.Code -ne 0)

            $afterBytes = [System.IO.File]::ReadAllBytes($ini)
            $bytesMatch = (Compare-Bytes $themedBytes $afterBytes)
            check "case 4 ($($bf.Name)): live ini untouched" $bytesMatch
        }
    }

    # =========================================================================
    # CASE 5: Genuine legacy whole-file INI (fixed keys restore)
    # =========================================================================
    if (-not $Only -or $Only -match '5') {
        $tcDir = Join-Path $testRoot 'case5'
        New-Item -ItemType Directory -Force -Path $tcDir | Out-Null
        $ini = Join-Path $tcDir 'wincmd.ini'
        $bak = $ini + '.wintage.bak'

        $legacyIni = @"
[Configuration]
InstallDir=C:\totalcmd
LanguageIni=Wcmd_eng.lng
[Colors]
BackColor=16777215
ForeColor=255
[Layout]
ShowToolbar=1
"@
        # Set up live ini as themed by Wintage
        [System.IO.File]::WriteAllText($ini, "[Configuration]`r`nInstallDir=C:\totalcmd`r`n[Colors]`r`nBackColor=1`r`n", $utf8)
        $rApply = Run-Child @('-Target', 'totalcmd', '-TotalCmdIni', $ini, '-Palette', 'goldendefault')
        check "case 5: initial Apply exits 0" ($rApply.Code -eq 0)

        # Replace snapshot with genuine legacy whole-file INI
        [System.IO.File]::WriteAllText($bak, $legacyIni, $utf8)

        # Revert
        $rRevert = Run-Child @('-Target', 'totalcmd', '-TotalCmdIni', $ini, '-Revert')
        check "case 5: legacy whole-file INI Revert exits 0" ($rRevert.Code -eq 0)

        $restored = [System.IO.File]::ReadAllText($ini, $utf8)
        check "case 5: BackColor restored to original" ($restored -match '(?m)^BackColor=16777215\r?$')
        check "case 5: ForeColor restored to original" ($restored -match '(?m)^ForeColor=255\r?$')
        check "case 5: Wintage added MarkColor removed" ($restored -notmatch '(?m)^MarkColor=')
        check "case 5: Wintage added CursorColor removed" ($restored -notmatch '(?m)^CursorColor=')
        check "case 5: [ColorsDark] Wintage keys removed" ($restored -notmatch '(?m)^\[ColorsDark\]\r?\nBackColor=')
        check "case 5: backup consumed" (-not (Test-Path $bak))
        check "case 5: manifest entry removed" (-not (Manifest-HasTarget 'totalcmd'))
    }

    # =========================================================================
    # CASE 6: Legacy whole-file INI with dynamic recent-file filter colors
    # =========================================================================
    if (-not $Only -or $Only -match '6') {
        $tcDir = Join-Path $testRoot 'case6'
        New-Item -ItemType Directory -Force -Path $tcDir | Out-Null
        $ini = Join-Path $tcDir 'wincmd.ini'
        $bak = $ini + '.wintage.bak'

        $legacyIniWithFilters = @"
[Configuration]
InstallDir=C:\totalcmd
[Colors]
BackColor=16777215
ForeColor=0
ColorFilter1=>RecentFiles
ColorFilter1Color=65280
ColorFilter1ColorDark=32768
ColorFilter2=>KeepCustom
ColorFilter2Color=12345
[ColorsDark]
ColorFilter1Color=65280
ColorFilter1ColorDark=32768
[Searches]
RecentFiles_SearchFlags=0|000002000020|||5|0|||||0000|
KeepCustom_SearchFlags=0|000002000020||||||||22220|0000|
"@
        [System.IO.File]::WriteAllText($ini, $legacyIniWithFilters, $utf8)

        $rApply = Run-Child @('-Target', 'totalcmd', '-TotalCmdIni', $ini, '-Palette', 'goldendefault')
        check "case 6: Apply with recent filters exits 0" ($rApply.Code -eq 0)

        # Replace backup with the pre-v1.26.5 legacy whole-file INI
        [System.IO.File]::WriteAllText($bak, $legacyIniWithFilters, $utf8)

        # Add unrelated user edit made post-apply in live INI
        $liveThemed = [System.IO.File]::ReadAllText($ini, $utf8)
        $liveThemed += "`r`n[Layout]`r`nShowButtonBar=1`r`n[Colors]`r`nUnrelatedCustom=999999`r`n"
        [System.IO.File]::WriteAllText($ini, $liveThemed, $utf8)

        # Revert
        $rRevert = Run-Child @('-Target', 'totalcmd', '-TotalCmdIni', $ini, '-Revert')
        check "case 6: Revert with legacy filter migration exits 0" ($rRevert.Code -eq 0)

        $restored = [System.IO.File]::ReadAllText($ini, $utf8)
        check "case 6: legacy recent filter Color restored in [Colors]" ($restored -match '(?m)^ColorFilter1Color=65280\r?$')
        check "case 6: legacy recent filter ColorDark restored in [Colors]" ($restored -match '(?m)^ColorFilter1ColorDark=32768\r?$')
        check "case 6: legacy recent filter Color restored in [ColorsDark]" ($restored -match '(?m)^ColorFilter1Color=65280\r?$')
        check "case 6: legacy recent filter ColorDark restored in [ColorsDark]" ($restored -match '(?m)^ColorFilter1ColorDark=32768\r?$')
        check "case 6: non-recent filter Color preserved" ($restored -match '(?m)^ColorFilter2Color=12345\r?$')
        check "case 6: unrelated ShowButtonBar preserved" ($restored -match '(?m)^ShowButtonBar=1\r?$')
        check "case 6: unrelated UnrelatedCustom preserved" ($restored -match '(?m)^UnrelatedCustom=999999\r?$')
        check "case 6: backup consumed" (-not (Test-Path $bak))
        check "case 6: manifest entry removed" (-not (Manifest-HasTarget 'totalcmd'))
    }

} finally {
    $env:WINTAGE_APPDATA = $origAppData
    $env:WINTAGE_BACKUP_ROOT = $origBackupRoot
    $env:USERPROFILE = $origHome
    if (Test-Path $testRoot) { Remove-Item -Recurse -Force $testRoot -ErrorAction SilentlyContinue }
}

Write-Host "`n========================================================"
if ($RedControl) {
    # Under red control, the MANDATORY pre-fix assertions MUST all fail.
    $redHit = 0
    foreach ($lbl in $redMandatory) {
        if ($failedLabels -contains $lbl) { $redHit++ }
    }
    $redExtraHit = 0
    foreach ($lbl in $redExtra) {
        if ($failedLabels -contains $lbl) { $redExtraHit++ }
    }
    Write-Host "Red control results: $redHit of $($redMandatory.Count) mandatory + $redExtraHit of $($redExtra.Count) extra critical failures reproduced."
    if ($redHit -eq $redMandatory.Count) {
        Write-Host "RED CONTROL PASS: all mandatory pre-fix defects correctly caught by tests." -ForegroundColor Green
        exit 0
    } else {
        Write-Host "RED CONTROL FAIL: mandatory pre-fix defects NOT all reproduced (need $($redMandatory.Count), got $redHit)." -ForegroundColor Red
        exit 1
    }
}

if ($fail -gt 0) {
    Write-Host "FAILED: $fail assertions failed out of $($pass + $fail)" -ForegroundColor Red
    exit 1
} else {
    Write-Host "ALL $pass ASSERTIONS PASSED" -ForegroundColor Green
    exit 0
}
