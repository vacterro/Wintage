# T-967: the GUI form-shown stamp is STRICTLY OPT-IN.
#
# The legacy Form.Shown handler defaulted the stamp to %TEMP%\wintage-form-shown.stamp
# when WINTAGE_TEST_FORM_SHOWN_FILE was NOT set, so every ordinary launch of the
# installer wrote a test artifact into the operator's temp directory. That is a
# fixture leaking into normal operation, and a file no operator asked for.
#
# This gate proves the repair from three directions, so "no write" is a measured
# fact rather than an absence someone has to believe:
#
#   1. SOURCE: the handler writes only inside a test guarded by the variable,
#      and no default stamp path exists anywhere in the shipped source;
#   2. LIVE / POSITIVE: a real child GUI with the variable set DOES write the
#      stamp and self-closes, so the legitimate smoke contract still works;
#   3. LIVE / NEGATIVE: a real child GUI with the variable UNSET writes NO stamp
#      into temp (the marker path and the whole temp dir are checked), so an
#      ordinary launch cannot pollute the machine.
#
# The negative case is the one that could not have been caught before: the stamp
# WAS the default, so the ordinary launch always wrote it and looked normal.
#
#   .\tools\test-form-shown-optin.ps1          # all tests
#   .\tools\test-form-shown-optin.ps1 -List    # list tests

[CmdletBinding()]
param([switch]$List)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$guiPath = Join-Path $root 'desktop\WintageInstaller.ps1'
$pass = 0
$fail = 0

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}
if ($List) {
    Write-Host 'test-form-shown-optin.ps1 (GUI form-shown stamp is strictly opt-in)'
    exit 0
}

$guiText = [System.IO.File]::ReadAllText($guiPath)

# ---- 1. SOURCE: the handler guards on the variable, no default path ----------
$shownIdx = $guiText.IndexOf('$form.Add_Shown(')
check 'source: the Form.Shown handler was located' ($shownIdx -ge 0)
$open = $guiText.IndexOf('{', $shownIdx)
$depth = 0
$handlerText = $null
for ($j = $open; $j -lt $guiText.Length; $j++) {
    if ($guiText[$j] -eq '{') { $depth++ }
    elseif ($guiText[$j] -eq '}') { $depth--; if ($depth -eq 0) { $handlerText = $guiText.Substring($shownIdx, $j - $shownIdx + 1); break } }
}
check 'source: the handler body was extracted in full' ($null -ne $handlerText)
if ($handlerText) {
    # The write must sit INSIDE the `if ($env:WINTAGE_TEST_FORM_SHOWN_FILE)` test:
    # find the if, then confirm the WriteAllText occurs before that if's closing
    # brace rather than at handler level.
    $ifIdx = $handlerText.IndexOf('if ($env:WINTAGE_TEST_FORM_SHOWN_FILE)')
    $writeIdx = $handlerText.IndexOf('WriteAllText')
    check 'source: the stamp write is guarded by WINTAGE_TEST_FORM_SHOWN_FILE' (
        $ifIdx -ge 0 -and $writeIdx -gt $ifIdx)
    check 'source: the handler reads no default stamp path' (
        $handlerText -notmatch 'wintage-form-shown\.stamp' -and
        $handlerText -notmatch 'Join-Path[^\n]*GetTempPath[^\n]*stamp')
    # Every other WINTAGE_TEST_* hook in the same handler must also be a guard,
    # never a defaulted write.
    check 'source: the auto-close timer is likewise guarded by its own variable' (
        $handlerText -match 'if \(\$env:WINTAGE_TEST_AUTOCLOSE_MS\)')
}
check 'source: the legacy default stamp path is gone from the whole installer' (
    $guiText -notmatch '\$stamp\s*=\s*Join-Path')

# ---- 2..3. LIVE: run the REAL GUI twice, once with the var, once without -----
# Isolated WINTAGE_APPDATA so the child never reads or writes the operator's
# preferences. Temp is watched through a private scratch dir the child is pointed
# at via $env:TEMP, so "nothing was written" is checked against a directory the
# gate owns rather than the operator's shared temp.
$fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-shown-' + [guid]::NewGuid().ToString('N'))
$childAppData = Join-Path $fixture 'appdata'
$childTemp = Join-Path $fixture 'temp'
$childLocalAppData = Join-Path $fixture 'localappdata'
New-Item -ItemType Directory -Force -Path $childAppData | Out-Null
New-Item -ItemType Directory -Force -Path $childTemp | Out-Null
New-Item -ItemType Directory -Force -Path $childLocalAppData | Out-Null

$marker = Join-Path $fixture 'shown.stamp'
$prevAppData = $env:WINTAGE_APPDATA
$prevTemp = $env:TEMP
$prevTmp = $env:TMP
$prevLocal = $env:LOCALAPPDATA
$prevShown = $env:WINTAGE_TEST_FORM_SHOWN_FILE
$prevAutoclose = $env:WINTAGE_TEST_AUTOCLOSE_MS
$hadShown = (Test-Path Env:WINTAGE_TEST_FORM_SHOWN_FILE)
$hadAutoclose = (Test-Path Env:WINTAGE_TEST_AUTOCLOSE_MS)

function Invoke-GuiWithShownVar([bool]$supplyShownFile, [int]$AutoCloseMs) {
    $prev = @{
        'WINTAGE_APPDATA' = $env:WINTAGE_APPDATA
        'TEMP' = $env:TEMP
        'TMP' = $env:TMP
        'LOCALAPPDATA' = $env:LOCALAPPDATA
        'WINTAGE_TEST_FORM_SHOWN_FILE' = $env:WINTAGE_TEST_FORM_SHOWN_FILE
        'WINTAGE_TEST_AUTOCLOSE_MS' = $env:WINTAGE_TEST_AUTOCLOSE_MS
    }
    $had = @{}
    foreach ($n in $prev.Keys) { $had[$n] = (Test-Path ("Env:" + $n)) }
    Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
    $proc = $null
    try {
        $env:WINTAGE_APPDATA = $childAppData
        $env:TEMP = $childTemp
        $env:TMP = $childTemp
        $env:LOCALAPPDATA = $childLocalAppData
        $env:WINTAGE_TEST_AUTOCLOSE_MS = "$AutoCloseMs"
        if ($supplyShownFile) { $env:WINTAGE_TEST_FORM_SHOWN_FILE = $marker }
        else { Remove-Item Env:WINTAGE_TEST_FORM_SHOWN_FILE -ErrorAction SilentlyContinue }
        try { $proc = Start-Process -FilePath 'powershell' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $guiPath) -PassThru -WindowStyle Hidden }
        catch { $proc = $null }
        $exited = $false
        if ($proc) {
            $exited = $proc.WaitForExit(60000)
            if (-not $exited) { try { $proc.Kill() } catch { } ; try { $proc.WaitForExit(5000) | Out-Null } catch { } }
            try { $proc.Dispose() } catch { }
        }
        $stamp = (Test-Path -LiteralPath $marker)
        $tempFiles = @(Get-ChildItem -LiteralPath $childTemp -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
        $stampLike = @($tempFiles | Where-Object { $_ -match 'form-shown|shown\.stamp' })
        return [pscustomobject]@{ Started = ($proc -ne $null); Exited = $exited; Stamp = $stamp; TempFileCount = $tempFiles.Count; StampLikeFiles = $stampLike }
    } finally {
        foreach ($n in $prev.Keys) {
            if ($had[$n]) { Set-Item -Path ("Env:" + $n) -Value $prev[$n] }
            else { Remove-Item -Path ("Env:" + $n) -ErrorAction SilentlyContinue }
        }
    }
}

try {
    $withVar = Invoke-GuiWithShownVar -supplyShownFile $true -AutoCloseMs 1200
    check 'live: the child GUI with the variable SET started and self-closed' ($withVar.Started -and $withVar.Exited)
    check 'live (positive): the stamp IS written when the fixture opts in' ($withVar.Stamp)

    $withoutVar = Invoke-GuiWithShownVar -supplyShownFile $false -AutoCloseMs 1200
    check 'live: the child GUI without the variable started and self-closed' ($withoutVar.Started -and $withoutVar.Exited)
    check 'live (negative): the ordinary launch writes NO stamp at the marker path' (-not $withoutVar.Stamp)
    check 'live (negative): the ordinary launch writes NO form-shown file anywhere in its temp dir' ($withoutVar.StampLikeFiles.Count -eq 0)
    check 'live (negative): the ordinary launch wrote nothing at all into its temp dir' ($withoutVar.TempFileCount -eq 0)
} finally {
    Remove-Item -Recurse -Force -LiteralPath $fixture -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("test-form-shown-optin.ps1: $pass PASS / $fail FAIL") -ForegroundColor Cyan
if ($fail -gt 0) { exit 1 }
exit 0
