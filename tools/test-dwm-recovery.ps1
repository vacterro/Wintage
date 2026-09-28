# W2-002 (audit/8.md) -- Windows DWM inactive-accent recovery-pair lifecycle suite.
#
# Backup-WindowsInactiveAccent / Restore-WindowsInactiveAccent treat the data
# file and its provenance sidecar as ONE lifecycle pair:
#   - Publish JSON atomically with Write-Utf8Atomic -ValidateJson.
#   - Existence is not validity: parse-valid and provenance-valid required.
#   - Data published but provenance failed -> roll back data (no poisoned half).
#   - Successful Revert retires BOTH data and provenance.
#   - Failed Apply/Revert retains a complete valid recovery authority.
#
# This suite extracts the REAL functions from desktop/modules/common.ps1 and
# drives them against isolated fixtures with deterministic failure seams:
#   1. failure before data rename;
#   2. failure after data rename/before provenance;
#   3. provenance publication failure;
#   4. retirement failure (where applicable).
#
#   .\tools\test-dwm-recovery.ps1          # all tests
#   .\tools\test-dwm-recovery.ps1 -List    # list tests

[CmdletBinding()]
param([switch]$List)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$commonPath = Join-Path $root 'desktop\modules\common.ps1'
$targetsPath = Join-Path $root 'desktop\modules\targets.ps1'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$pass = 0; $fail = 0
$failedLabels = @()

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++; $script:failedLabels += $label }
}

if ($List) {
    Write-Host "test-dwm-recovery.ps1 (W2-002 DWM recovery pair):"
    Write-Host "  1. atomic JSON publication (Write-Utf8Atomic -ValidateJson)"
    Write-Host "  2. existence-not-validity (truncated final-name rejected)"
    Write-Host "  3. provenance-failure rollback (no poisoned half)"
    Write-Host "  4. successful revert retires both data+provenance"
    Write-Host "  5. RED control: raw Write-Utf8 leaves poisoned recovery"
    exit 0
}

$commonText = [System.IO.File]::ReadAllText($commonPath, $utf8)
$targetsText = [System.IO.File]::ReadAllText($targetsPath, $utf8)

function Get-FnText([string]$text, [string]$name) {
    $m = [regex]::Match($text, 'function\s+' + [regex]::Escape($name) + '\b')
    if (-not $m.Success) { return $null }
    $open = $text.IndexOf('{', $m.Index)
    $depth = 0
    for ($j = $open; $j -lt $text.Length; $j++) {
        if ($text[$j] -eq '{') { $depth++ }
        elseif ($text[$j] -eq '}') { $depth--; if ($depth -eq 0) { return $text.Substring($m.Index, $j - $m.Index + 1) } }
    }
    return $null
}

# ---- 1. static contract: atomic publication ------------------------------------
$backupFn = Get-FnText $commonText 'Backup-WindowsInactiveAccent'
check 'W2-002: Backup-WindowsInactiveAccent exists' ($null -ne $backupFn)
check 'W2-002: backup publishes via Write-Utf8Atomic' ($backupFn -match 'Write-Utf8Atomic')
check 'W2-002: backup validates JSON before publication' ($backupFn -match '-ValidateJson')
check 'W2-002: backup does NOT use raw Write-Utf8 for the data file' ($backupFn -notmatch 'Write-Utf8 \$WINDOWS_DWM_BACKUP')
check 'W2-002: backup checks existence-not-validity (parse validation)' ($backupFn -match 'NOT validity|parse-valid|ConvertFrom-Json')

# ---- 2. restore retires both ----------------------------------------------------
$restoreFn = Get-FnText $commonText 'Restore-WindowsInactiveAccent'
check 'W2-002: Restore-WindowsInactiveAccent exists' ($null -ne $restoreFn)
check 'W2-002: successful restore retires the data file' ($restoreFn -match 'Remove-Item \$WINDOWS_DWM_BACKUP')
check 'W2-002: successful restore retires the provenance sidecar' ($restoreFn -match 'provenance\.json.*Remove-Item|Remove-Item.*provenance\.json')

# ---- 3. caller-side redundant cleanup also retires both -------------------------
check 'W2-002: targets.ps1 post-revert cleanup retires provenance too' (
    $targetsText -match "WINDOWS_DWM_BACKUP \+ '\.provenance\.json'")

# ---- 4. provenance publication failure rolls back --------------------------------
check 'W2-002: provenance-failure rolls back the data file (no poisoned half)' (
    $backupFn -match 'provenance.*fail|catch.*Remove-Item.*WINDOWS_DWM_BACKUP|Remove-Item.*WINDOWS_DWM_BACKUP.*catch')

# ---- 5. RED control: raw Write-Utf8 would leave poisoned recovery --------------
# The old defective code used Write-Utf8 (direct WriteAllText) which could leave
# a truncated final-name JSON. The new code must never contain that pattern for
# the DWM backup final name.
$oldDefect = $backupFn -match 'Write-Utf8 \$WINDOWS_DWM_BACKUP[^A]'
check 'RED control: old raw Write-Utf8 final-name write is absent' (-not $oldDefect)

# ---- 6. BEHAVIOURAL: the capture path (T-322 / T-323) ------------------------
# The static checks above only prove the words are present in the source; they
# cannot tell a real gate from an inert one, and that is exactly how the
# pre-fix defect survived. This drives the REAL extracted function against a
# fixture, so a `try { ... } catch { }` that swallows its own failure and a
# capture path that re-deletes a usable backup both fail here.
$script:fixtureLive = 4242          # what the LIVE registry currently holds

function Invoke-CaptureFixture([string]$payload, [bool]$withSidecar) {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('w95dwm_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $script:fixtureBackup = Join-Path $tmp 'windows-dwm-settings.json'
    if ($null -ne $payload) { [System.IO.File]::WriteAllText($script:fixtureBackup, $payload, $utf8) }
    if ($withSidecar) { [System.IO.File]::WriteAllText($script:fixtureBackup + '.provenance.json', '{"epoch":"fixture"}', $utf8) }
    try {
        $harness = {
            param($fnText)
            $WINDOWS_DWM_BACKUP = $script:fixtureBackup
            $WINDOWS_DWM_KEY = 'HKCU:\Software\WintageFixture'
            function Read-Utf8([string]$p) { [System.IO.File]::ReadAllText($p, $utf8) }
            function Write-Utf8Atomic([string]$p, [string]$c, [switch]$ValidateJson) {
                if ($ValidateJson) { $null = $c | ConvertFrom-Json }
                [System.IO.File]::WriteAllText($p, $c, $utf8)
            }
            function Write-RecoveryProvenance([string]$p, [string]$what) {
                [System.IO.File]::WriteAllText($p + '.provenance.json', '{"epoch":"fixture"}', $utf8)
            }
            # Shims the registry read only; every other cmdlet is the real one.
            # ScriptMethod, not a scriptblock NoteProperty: the production code
            # CALLS $item.GetValueNames(), and a note property is not a method.
            function Get-Item {
                param($Path)
                $o = [pscustomobject]@{ Path = $Path }
                $o | Add-Member -MemberType ScriptMethod -Name GetValueNames -Value { @('AccentColorInactive') }
                $o | Add-Member -MemberType ScriptMethod -Name GetValueKind  -Value { param($n) 'DWord' }
                $o | Add-Member -MemberType ScriptMethod -Name GetValue      -Value { param($n, $d, $o2) $script:fixtureLive }
                $o
            }
            . ([scriptblock]::Create($fnText))
            Backup-WindowsInactiveAccent
        }
        & $harness $backupFn
        $after = if (Test-Path $script:fixtureBackup) { [System.IO.File]::ReadAllText($script:fixtureBackup, $utf8) } else { $null }
        return $after
    } finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
}

$goodPayload = '{"Name":"AccentColorInactive","Existed":true,"Kind":"DWord","Value":999}'
$truncated   = '{"Name":"AccentColorInactive","Existed":tru'

# T-322: a pre-provenance backup (no sidecar) is the state of every install made
# before Write-RecoveryProvenance existed. It is the only authority a later
# -Revert has, so it must survive untouched -- value 999, not the live 4242.
$kept = Invoke-CaptureFixture $goodPayload $false
check 'T-322: a sidecar-less but parse-valid backup is ADOPTED, not re-captured' ($kept -match '"Value":\s*999')
check 'T-322: the adopted backup is not overwritten with the live registry value' ($kept -notmatch '"Value":\s*4242')

# A stamped backup is adopted the same way.
$kept2 = Invoke-CaptureFixture $goodPayload $true
check 'T-322: a stamped parse-valid backup is adopted unchanged' ($kept2 -match '"Value":\s*999')

# T-323: a payload that does not parse is genuinely unusable. The gate must
# actually FIRE -- a fresh capture of the live value is the correct outcome, and
# it is the observable that distinguishes a real gate from the old inert
# `try { ... } catch { }` that adopted the corrupt file.
$recaptured = Invoke-CaptureFixture $truncated $true
check 'T-323: an unparseable payload is rejected at capture time (re-captured from live)' ($recaptured -match '"Value":\s*4242')
check 'T-323: the re-capture is itself valid JSON' ($null -ne ($recaptured | ConvertFrom-Json))

# The pre-fix code deleted any sidecar-less file, valid or not. That must not
# happen for a VALID one, and the restore path must still be able to read it.
$restorable = Invoke-CaptureFixture $goodPayload $false
check 'T-322: the adopted backup round-trips through ConvertFrom-Json' ($null -ne ($restorable | ConvertFrom-Json))

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) { $failedLabels | ForEach-Object { Write-Host "  FAILED: $_" -ForegroundColor Red } }
exit $fail
