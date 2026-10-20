# T-967 item 7: MEASURE the real Windows cold-start cost of portable discovery.
#
# The live smoke in tools/test-browser-cache.ps1 arms an ARTIFICIAL 6-second
# walker to make the defect visible. That proves the walk CAN be on the startup
# path, but it does not say what the walk actually costs on a real machine. This
# script measures the real thing: the SAME child GUI, twice, once with a warm
# cache and once with a cold cache over a portable root of realistic size, with
# NO artificial delay. The difference is the walk's real contribution to
# time-to-usable-window.
#
# It is a MEASUREMENT tool, not a gate: it prints numbers and always exits 0
# unless the GUI could not be run at all. A number is not a verdict.
#
#   .\tools\measure-cold-start.ps1
#   .\tools\measure-cold-start.ps1 -NoiseFiles 400 -Runs 3

[CmdletBinding()]
param(
    [int]$NoiseFiles = 200,
    [int]$Runs = 3,
    [int]$AutoCloseMs = 600,
    [int]$WaitBudgetMs = 60000
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$gui = Join-Path $root 'desktop\WintageInstaller.ps1'
$helper = Join-Path $here 'browser-discovery.ps1'
if (-not (Test-Path $helper)) {
    Write-Host "SKIP: $helper not found (portable discovery cache module)" -ForegroundColor Yellow
    exit 0
}

# A throwaway portable root with a realistic amount of unrelated content, so the
# recursive walk has something to walk.
$fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('wintage-cold-' + [guid]::NewGuid().ToString('N'))
$portableRoot = Join-Path $fixture 'portable'
$deep = Join-Path $portableRoot 'unrelated\deep'
$appData = Join-Path $fixture 'appdata'
New-Item -ItemType Directory -Force -Path $deep | Out-Null
New-Item -ItemType Directory -Force -Path $appData | Out-Null
foreach ($n in 1..$NoiseFiles) { [System.IO.File]::WriteAllText((Join-Path $deep "f$n.bin"), 'noise') }
[System.IO.File]::WriteAllText((Join-Path $appData 'paths.json'), ('{"portable":"' + $portableRoot.Replace('\', '\\') + '"}'))

. $helper
$null = Get-PortableCandidates -PortableRoot $portableRoot -CacheRoot $appData
$cacheFile = Get-BrowserCachePath $appData

$marker = Join-Path $fixture 'shown.stamp'
$walkFile = Join-Path $fixture 'walkcount.txt'

function Measure-Startup([bool]$Cold) {
    if ($Cold -and (Test-Path $cacheFile)) { Remove-Item -LiteralPath $cacheFile -Force }
    if (-not $Cold) { $null = Get-PortableCandidates -PortableRoot $portableRoot -CacheRoot $appData }
    Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $walkFile -Force -ErrorAction SilentlyContinue
    $prev = @{
        'WINTAGE_APPDATA' = $env:WINTAGE_APPDATA
        'WINTAGE_TEST_FORM_SHOWN_FILE' = $env:WINTAGE_TEST_FORM_SHOWN_FILE
        'WINTAGE_TEST_WALK_COUNT_FILE' = $env:WINTAGE_TEST_WALK_COUNT_FILE
    }
    $had = @{}
    foreach ($n in $prev.Keys) { $had[$n] = ($null -ne $prev[$n]) }
    $proc = $null
    $t0 = [datetime]::UtcNow
    $shownMs = -1
    $walks = 0
    try {
        $env:WINTAGE_APPDATA = $appData
        $env:WINTAGE_TEST_FORM_SHOWN_FILE = $marker
        $env:WINTAGE_TEST_WALK_COUNT_FILE = $walkFile
        $proc = Start-Process -FilePath 'powershell' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $gui) -PassThru -WindowStyle Hidden
        for ($i = 0; $i -lt ($WaitBudgetMs / 25); $i++) {
            if (Test-Path -LiteralPath $marker) { break }
            if ($proc.HasExited) { break }
            Start-Sleep -Milliseconds 25
        }
        if (Test-Path -LiteralPath $marker) { $shownMs = [int]([datetime]::UtcNow - $t0).TotalMilliseconds }
        if (Test-Path -LiteralPath $walkFile) { $walks = [int]((Get-Content -LiteralPath $walkFile -Raw).Trim()) }
        # BOUNDED child execution: never leave a GUI process running.
        if (-not $proc.WaitForExit($AutoCloseMs + 20000)) {
            try { $proc.Kill() } catch { }
        }
    } finally {
        # Restore PRESENCE as well as value: a variable that was absent must go
        # back to being absent, not empty.
        foreach ($n in $prev.Keys) {
            if ($had[$n]) { Set-Item -Path ("Env:" + $n) -Value $prev[$n] }
            else { Remove-Item -Path ("Env:" + $n) -Force -ErrorAction SilentlyContinue }
        }
        if ($proc) {
            try { $proc.Dispose() } catch { }
        }
    }
    return [pscustomobject]@{ ShownMs = $shownMs; Walks = $walks; AutoCloseMs = $AutoCloseMs }
}

# Median, not mean: the first powershell spawn of the session pays one-time
# JIT / AV / cold-page costs that have nothing to do with the walk, and with
# Runs=3 a single such outlier moves the mean more than the walk does. The
# discard run below absorbs that cost before anything is recorded.
function Get-Median([int[]]$xs) {
    $s = @($xs | Sort-Object)
    if ($s.Count -eq 0) { return -1 }
    return $s[[int][math]::Floor(($s.Count - 1) / 2)]
}

try {
    # Direct cost of the walk ITSELF, isolated from powershell/WinForms spawn.
    # This is the number that decides item 7: if the walk over a realistic
    # portable root is milliseconds, deferring it off the startup path cannot
    # buy a user-visible improvement and no deferred-discovery mechanism is
    # justified. Repeat 5x on a cold cache so a single page-cache miss is not
    # mistaken for the walk's cost.
    $walkSamples = @()
    foreach ($i in 1..5) {
        if (Test-Path $cacheFile) { Remove-Item -LiteralPath $cacheFile -Force }
        $tw = [System.Diagnostics.Stopwatch]::StartNew()
        $null = Get-PortableCandidates -PortableRoot $portableRoot -CacheRoot $appData
        $tw.Stop()
        $walkSamples += [int]$tw.ElapsedMilliseconds
    }
    Write-Host ("direct walk cost over {0} files: {1} ms (samples: {2})" -f $NoiseFiles, (Get-Median $walkSamples), ($walkSamples -join '/'))

    $warm = @(); $cold = @()
    Write-Host 'discard warmup run (host JIT/AV, not measured)...'
    $null = Measure-Startup -Cold $false
    foreach ($i in 1..$Runs) {
        $w = Measure-Startup -Cold $false
        $warm += $w
        Write-Host ("warm run {0}: ShownMs={1} Walks={2}" -f $i, $w.ShownMs, $w.Walks)
    }
    foreach ($i in 1..$Runs) {
        $c = Measure-Startup -Cold $true
        $cold += $c
        Write-Host ("cold run {0}: ShownMs={1} Walks={2}" -f $i, $c.ShownMs, $c.Walks)
    }
    $warmAvg = Get-Median @($warm | ForEach-Object { $_.ShownMs })
    $coldAvg = Get-Median @($cold | ForEach-Object { $_.ShownMs })
    Write-Host ''
    Write-Host ("MEASUREMENT: warm median ShownMs={0} (walks {1}); cold median ShownMs={2} (walks {3}); walk contribution ~{4}ms" -f `
        $warmAvg, (($warm | ForEach-Object { $_.Walks }) -join '/'), $coldAvg, (($cold | ForEach-Object { $_.Walks }) -join '/'), ($coldAvg - $warmAvg))
    Write-Host ("portable root: {0} noise files under {1}" -f $NoiseFiles, $deep)
    Write-Host ("autoclose budget per run: {0}ms (child killed after)" -f ($AutoCloseMs + 20000))
} finally {
    Remove-Item -Recurse -Force -LiteralPath $fixture -ErrorAction SilentlyContinue
}
exit 0
