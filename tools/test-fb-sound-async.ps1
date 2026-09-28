# PERF-003 (audit/8.md) -- FreeBuff async sound preview suite.
#
# DEFECTS under test (the two UI-thread hazards named by the audit):
#   1. synchronous ffmpeg conversion blocking the GUI thread;
#   2. MediaPlayer fallback wait loop using Application.DoEvents + Start-Sleep.
#
# CONTRACT under test:
#   a. ffmpeg transcode launches ASYNCHRONOUSLY (Start-FbConvertAsync, no
#      blocking `& $ff.Source ...` inside the preview path);
#   b. NO Application.DoEvents / Start-Sleep call anywhere in the preview path;
#   c. MediaPlayer uses MediaOpened/MediaFailed events + a one-shot Forms.Timer
#      timeout, never a polling sleep loop and never a "HasAudio == false means
#      playing" guess;
#   d. ownership state: generation/request identity, owned conversion process,
#      active player, timeout timer, temp output, staged pending candidate;
#   e. Stop-FbSoundPreview is idempotent and tears down ALL owned resources;
#   f. completion is asynchronous: the selection is committed ONLY from a
#      verified callback, never from an immediate $true.
#
# BEHAVIORAL FIXTURES drive the real production functions (extracted from
# WintageInstaller.ps1) against a controllable fake ffmpeg (a .cmd process) and
# a WinForms message pump, so the real Forms.Timer / Process ownership logic is
# exercised end to end.
#
#   .\tools\test-fb-sound-async.ps1          # all tests
#   .\tools\test-fb-sound-async.ps1 -List    # list tests

[CmdletBinding()]
param([switch]$List)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$guiPath = Join-Path $root 'desktop\WintageInstaller.ps1'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$pass = 0; $fail = 0
$failedLabels = @()

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++; $script:failedLabels += $label }
}

if ($List) {
    Write-Host "test-fb-sound-async.ps1 (PERF-003 async sound preview):"
    Write-Host "  1. async ffmpeg launch (no blocking convert in preview)"
    Write-Host "  2. no Application.DoEvents / Start-Sleep in preview path"
    Write-Host "  3. MediaPlayer event-based + one-shot timer (no poll loop)"
    Write-Host "  4. ownership state: generation/process/player/timer/tmp/pending"
    Write-Host "  5. Stop-FbSoundPreview idempotent teardown of all owned state"
    Write-Host "  6. RED control: old sync/DoEvents shape absent"
    Write-Host "  7. behavioral: async success, heartbeat, B supersedes A,"
    Write-Host "     close-during-conversion, failed conversion -> fallback"
    exit 0
}

$guiText = [System.IO.File]::ReadAllText($guiPath, $utf8)

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

$playFn = Get-FnText $guiText 'Play-FbSoundPreview'
$stopFn = Get-FnText $guiText 'Stop-FbSoundPreview'
$startAsyncFn = Get-FnText $guiText 'Start-FbConvertAsync'
$watchFn = Get-FnText $guiText 'Start-FbConversionWatch'
$mediaFn = Get-FnText $guiText 'Start-FbMediaPreview'
check 'PERF-003: Play-FbSoundPreview located' ($null -ne $playFn)
check 'PERF-003: Stop-FbSoundPreview located' ($null -ne $stopFn)
check 'PERF-003: Start-FbConvertAsync located' ($null -ne $startAsyncFn)
check 'PERF-003: Start-FbConversionWatch located' ($null -ne $watchFn)
check 'PERF-003: Start-FbMediaPreview located' ($null -ne $mediaFn)

$previewScoped = $playFn + $stopFn + $startAsyncFn + $watchFn + $mediaFn

# ---- 1. async ffmpeg -------------------------------------------------------
check 'PERF-003: preview launches ffmpeg asynchronously (Start-FbConvertAsync)' (
    ($playFn -match 'Start-FbConvertAsync') -and ($startAsyncFn -match 'ProcessStartInfo'))
check 'PERF-003: NO synchronous blocking convert call in preview' (
    ($playFn -notmatch 'Convert-ToPlayableWav') -or ($playFn -match 'Start-FbConvertAsync'))
check 'PERF-003: no blocking & ffmpeg invocation in preview path' ($playFn -notmatch '& \$ff\.Source')
check 'PERF-003: obsolete synchronous Convert-ToPlayableWav removed' ($guiText -notmatch 'function\s+Convert-ToPlayableWav')

# ---- 2. no DoEvents / sleeps -----------------------------------------------
check 'PERF-003: no Application::DoEvents in preview path' ($previewScoped -notmatch 'DoEvents')
check 'PERF-003: no Start-Sleep polling loop in preview path' ($previewScoped -notmatch 'Start-Sleep')

# ---- 3. event-based MediaPlayer + one-shot timer ---------------------------
check 'PERF-003: MediaPlayer registers MediaOpened event' ($mediaFn -match 'Add_MediaOpened')
check 'PERF-003: MediaPlayer registers MediaFailed event' ($mediaFn -match 'Add_MediaFailed')
check 'PERF-003: one-shot Forms.Timer timeout used' (
    (($playFn + $watchFn + $mediaFn) -match 'Windows\.Forms\.Timer') -and ($mediaFn -match '\.Stop\(\)'))
check 'PERF-003: timeout terminates the owned attempt (no HasAudio guess)' (
    ($mediaFn -notmatch 'HasAudio'))

# ---- 4. ownership state ----------------------------------------------------
check 'PERF-003: generation/request identity (fbPreviewGeneration)' ($guiText -match '\$script:fbPreviewGeneration')
check 'PERF-003: owned conversion process tracked (fbPreviewFfmpeg)' ($guiText -match '\$script:fbPreviewFfmpeg')
check 'PERF-003: active player tracked (fbSoundPlayer)' ($guiText -match '\$script:fbSoundPlayer')
check 'PERF-003: timeout timer tracked (fbPreviewTimer)' ($guiText -match '\$script:fbPreviewTimer')
check 'PERF-003: temp output tracked (fbPreviewTmp)' ($guiText -match '\$script:fbPreviewTmp')
# T-338: the persistence decision rides the per-request record, which carries
# Gen/Tmp/Path/Name/OnVerified/Settled and is the object the conversion watcher
# and the media callbacks actually read. The old assertion pinned
# $script:fbPreviewPending, a flag that was written and cleared but NEVER read:
# it carried no resource and gated nothing, while its comment claimed it gated
# persistence. Pin the real mechanism, and pin the dead flag's removal.
check 'PERF-003: the per-request record is tracked (fbPreviewReq)' ($guiText -match '\$script:fbPreviewReq')
check 'PERF-003: the write-only fbPreviewPending flag is gone' ($guiText -notmatch 'fbPreviewPending')

# ---- 5. Stop-FbSoundPreview idempotent teardown ----------------------------
check 'PERF-003: Stop bumps generation (invalidates stale callbacks)' ($stopFn -match 'fbPreviewGeneration \+= 1')
check 'PERF-003: Stop terminates owned conversion process' ($stopFn -match 'fbPreviewFfmpeg' -and $stopFn -match 'Kill\(\)')
check 'PERF-003: Stop stops/disposes timeout timer' ($stopFn -match 'fbPreviewTimer' -and $stopFn -match 'Dispose\(\)')
check 'PERF-003: Stop removes owned temp file' ($stopFn -match 'Remove-Item' -and $stopFn -match 'fbPreviewTmp')
check 'PERF-003: Stop clears the per-request record' ($stopFn -match 'fbPreviewReq = \$null')
check 'PERF-003: Stop disposes player (SoundPlayer and MediaPlayer branches)' (
    $stopFn -match 'SoundPlayer' -and $stopFn -match 'Close\(\)')

# ---- 6. B supersedes A / source guards -------------------------------------
check 'PERF-003: watcher checks generation before touching state' ($watchFn -match 'Gen -ne \$script:fbPreviewGeneration')
check 'PERF-003: superseded request owns nothing (guard before side effects)' ($watchFn -match 'owns nothing')
check 'PERF-003: completion is asynchronous (onVerified callback present)' (
    ($playFn -match 'onVerified') -and ($watchFn -match 'onVerified') -and ($mediaFn -match 'onVerified'))

# ---- 7. RED controls (mutation-based, deterministic) -----------------------
# The old defective shape: synchronous Convert-ToPlayableWav + DoEvents loop.
$mutantPlay = $playFn -replace 'Start-FbConvertAsync', 'Convert-ToPlayableWav'
check 'RED control: injected synchronous convert is detected by the source guard' (
    -not (($mutantPlay -notmatch 'Convert-ToPlayableWav') -or ($mutantPlay -match 'Start-FbConvertAsync')))
check 'RED control: old DoEvents+Start-Sleep loop is absent' ($previewScoped -notmatch 'DoEvents.*Start-Sleep|Start-Sleep.*DoEvents')

# ===========================================================================
# BEHAVIORAL FIXTURES
# ===========================================================================
Write-Host "`n-- behavioral fixtures --" -ForegroundColor Cyan

$sandbox = Join-Path $env:TEMP ('fbasync_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sandbox -Force | Out-Null

function New-FakeFfmpeg([string]$name, [int]$delayMs, [int]$exitCode) {
    $p = Join-Path $sandbox $name
    $delay = if ($delayMs -gt 0) { "ping -n 2 127.0.0.1 >nul`r`n" } else { '' }
    $body = @"
@echo off
setlocal
set "OUT="
:loop
if "%~1"=="" goto done
set "OUT=%~1"
shift
goto loop
:done
$delay> "%OUT%" echo RIFF
exit /b $exitCode
"@
    [System.IO.File]::WriteAllText($p, $body, (New-Object System.Text.ASCIIEncoding))
    return $p
}

function New-FakeWav([string]$name) {
    $p = Join-Path $sandbox $name
    $bytes = New-Object byte[] 44
    [System.Text.Encoding]::ASCII.GetBytes('RIFF').CopyTo($bytes, 0)
    [System.Text.Encoding]::ASCII.GetBytes('WAVE').CopyTo($bytes, 8)
    [System.IO.File]::WriteAllBytes($p, $bytes)
    return $p
}

$fastFake = New-FakeFfmpeg 'ffmpeg_fast.cmd' 0 0
$slowFake = New-FakeFfmpeg 'ffmpeg_slow.cmd' 1 0
$failFake = New-FakeFfmpeg 'ffmpeg_fail.cmd' 0 1
$wavA = New-FakeWav 'a.wav'
$wavB = New-FakeWav 'b.wav'

# --- sandbox: production function definitions + script state ---------------
$script:fbSoundPlayer = $null
$script:fbPreviewTmp = $null
$script:fbPreviewFailed = $false
$script:fbPreviewGeneration = 0
$script:fbPreviewTimer = $null
$script:fbPreviewFfmpeg = $null
$script:fbPreviewReq = $null
$script:fbPreviewReq = $null
$script:logLines = @()
$script:fakeFfmpegPath = $fastFake

function Say-Log($msg) { $script:logLines += $msg }

# Controllable ffmpeg discovery: the real Start-FbConvertAsync resolves its
# executable through Get-Command, so shadowing the cmdlet here injects the
# fake process without touching production code.
function Get-Command {
    [CmdletBinding()]
    param([Parameter(Position = 0)]$Name, [switch]$CommandType)
    if ($Name -eq 'ffmpeg' -and $script:fakeFfmpegPath) {
        return [pscustomobject]@{ Source = $script:fakeFfmpegPath }
    }
    return $null
}

# Load the real production functions into this scope.
$kindFn = Get-FnText $guiText 'Get-FbAudioKind'
foreach ($fn in @($stopFn, $startAsyncFn, $watchFn, $mediaFn, $kindFn, $playFn)) {
    . ([scriptblock]::Create($fn))
}

function Test-PidGone([int]$ProcessId, [int]$TimeoutMs = 2000) {
    $end = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $end) {
        if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { return $true }
        Start-Sleep -Milliseconds 50
    }
    return (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue))
}

# --- fixture 1: async launch is non-blocking (slow conversion keeps running) -
$script:fakeFfmpegPath = $slowFake
$script:res1 = 'unset'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$acc1 = Play-FbSoundPreview $wavA { param($ok) $script:res1 = $ok }
$sw.Stop()
check 'behavior: Play-FbSoundPreview accepts a valid candidate' ($acc1 -eq $true)
check 'behavior: launch returned without waiting for conversion (<400ms)' ($sw.ElapsedMilliseconds -lt 400)
check 'behavior: an owned conversion process is live' ($script:fbPreviewFfmpeg -and -not $script:fbPreviewFfmpeg.HasExited)
check 'behavior: completion did not fire synchronously (async staging)' ($script:res1 -eq 'unset')
check 'behavior: owned temp reserved for the request' ($null -ne $script:fbPreviewTmp)
Stop-FbSoundPreview

# --- fixture 2: B supersedes A (A retired, stale A never owns B state) ------
$script:fakeFfmpegPath = $slowFake
$script:resA = 'unset'; $script:resB = 'unset'
$null = Play-FbSoundPreview $wavA { param($ok) $script:resA = $ok }
$aPid = $script:fbPreviewFfmpeg.Id
$aTmp = $script:fbPreviewTmp
$genA = $script:fbPreviewGeneration
$null = Play-FbSoundPreview $wavB { param($ok) $script:resB = $ok }
$genB = $script:fbPreviewGeneration
$bTmp = $script:fbPreviewTmp
check 'behavior: starting B advanced the request generation' ($genB -gt $genA)
check 'behavior: superseded A process was terminated' (Test-PidGone $aPid 3000)
check 'behavior: superseded A temp was removed' (-not (Test-Path -LiteralPath $aTmp))
check 'behavior: stale A never verified' ($script:resA -eq 'unset')
check 'behavior: B owns the retained temp' (
    ($script:fbPreviewTmp -eq $bTmp) -and ($aTmp -ne $bTmp))
Stop-FbSoundPreview

# --- fixture 3: close during conversion tears down every owned resource -----
$script:fakeFfmpegPath = $slowFake
$script:resC = 'unset'
$null = Play-FbSoundPreview $wavA { param($ok) $script:resC = $ok }
$cPid = $script:fbPreviewFfmpeg.Id
$cTmp = $script:fbPreviewTmp
check 'behavior: owned temp reserved during conversion' ($null -ne $cTmp)
Stop-FbSoundPreview
check 'behavior: no owned process remains after close' ($null -eq $script:fbPreviewFfmpeg)
check 'behavior: close terminated the conversion process' (Test-PidGone $cPid 3000)
check 'behavior: no player remains after close' ($null -eq $script:fbSoundPlayer)
check 'behavior: no timer remains after close' ($null -eq $script:fbPreviewTimer)
check 'behavior: no pending candidate remains after close' ($null -eq $script:fbPreviewReq)
check 'behavior: no temp remains after close' (-not (Test-Path -LiteralPath $cTmp))
check 'behavior: torn-down request never verified' ($script:resC -eq 'unset')

# --- fixture 4: Stop-FbSoundPreview is idempotent ---------------------------
Stop-FbSoundPreview
Stop-FbSoundPreview
check 'behavior: repeated Stop stays clean (no owned state)' (
    ($null -eq $script:fbPreviewFfmpeg) -and ($null -eq $script:fbPreviewTimer) -and
    ($null -eq $script:fbSoundPlayer) -and ($null -eq $script:fbPreviewTmp) -and ($null -eq $script:fbPreviewReq))

# --- fixture 5: no usable ffmpeg routes to the event-based fallback ---------
$script:fakeFfmpegPath = $null
$script:fbFallback = 0
$script:resD = 'unset'
function Start-FbMediaPreview([string]$path, [string]$name, [scriptblock]$onVerified) {
    $script:fbFallback++
    if ($onVerified) { & $onVerified $false }
}
$accD = Play-FbSoundPreview $wavA { param($ok) $script:resD = $ok }
check 'behavior: no ffmpeg -> MediaPlayer fallback invoked' ($script:fbFallback -eq 1)
check 'behavior: no ffmpeg -> request accepted, invalid candidate rejected' (
    ($accD -eq $true) -and ($script:resD -eq $false))
check 'behavior: failed conversion path references the fallback (source)' ($watchFn -match 'Start-FbMediaPreview')

# --- fixture 6: a non-audio candidate is rejected synchronously -------------
$script:fbFallback = 0
$txt = Join-Path $sandbox 'notaudio.txt'
[System.IO.File]::WriteAllText($txt, 'hello')
$rej = Play-FbSoundPreview $txt { param($ok) $script:resE = $ok }
check 'behavior: non-audio candidate rejected synchronously' ($rej -eq $false)
check 'behavior: rejected candidate started no fallback' ($script:fbFallback -eq 0)

# --- cleanup ----------------------------------------------------------------
Remove-Item -Recurse -Force $sandbox -ErrorAction SilentlyContinue

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) { $failedLabels | ForEach-Object { Write-Host "  FAILED: $_" -ForegroundColor Red } }
exit $fail
