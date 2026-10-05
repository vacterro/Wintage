# Manifest forward-compatibility gate (W2-004, SRC-063).
#
# The defect: an OLDER Vintage reads a manifest fine -- Test-ManifestSchema
# reports unknown keys rather than dropping them -- but then REBUILT each entry
# from nothing on write. So re-applying a target through an older build silently
# deleted every field it did not recognise, and the loss only became visible
# when the operator later ran the newer build that had written them.
#
# Everything runs against a UNIQUE temp app-data root through WINTAGE_APPDATA.
# The live %APPDATA%\Wintage\installed.json is never read or written.
#
#   .\tools\test-manifest-forward-compat.ps1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$common = Join-Path $root 'desktop\modules\common.ps1'
$pass = 0; $fail = 0

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function New-ScratchRoot([string]$name) {
    $dir = Join-Path ([IO.Path]::GetTempPath()) ("wintage-fwdcompat-$name-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    return $dir
}

# Point the module's own app-data paths at a scratch root. The module resolves
# $WintageAppData/$ManifestPath at CALL time, so re-pointing them per scenario is
# enough -- nothing has to be re-dot-sourced, and the live manifest is never in
# the picture.
function Use-Scratch([string]$appData) {
    $script:WintageAppData = $appData
    $script:ManifestPath = Join-Path $appData 'installed.json'
    $script:Utf8NoBom = $utf8NoBom
}

function Write-ManifestFile([string]$appData, $manifest) {
    [System.IO.File]::WriteAllText((Join-Path $appData 'installed.json'), (($manifest | ConvertTo-Json -Depth 6) + "`n"), $utf8NoBom)
}

# Dot-sourced ONCE at script scope: a dot-source inside a function would bind the
# module's functions to that function's scope, where they are not visible to the
# checks that follow.
$scratchProbe = New-ScratchRoot 'probe'
Use-Scratch $scratchProbe
. $common
Remove-Item -Recurse -Force $scratchProbe -ErrorAction SilentlyContinue

Write-Host '--- W2-004: an unknown field on a KNOWN target survives a rewrite ---'

& {
    # Green: the shipped writer.
    $appData = New-ScratchRoot 'green'
    try {
        # A manifest as a NEWER Vintage would have written it: the five fields
        # this build knows, plus two it has never heard of -- a scalar and a
        # nested object, so a scalar-only carry-forward cannot pass by accident.
        Write-ManifestFile $appData ([pscustomobject]@{
            ZCode = [pscustomobject]@{
                palette        = 'golden'
                path           = 'C:\apps\ZCode\Resources\app'
                appVersion     = '9.9.9'
                payloadVersion = '9.9.9'
                applied        = '2026-01-01T00:00:00Z'
                rollbackPath   = 'C:\backups\ZCode'
                futureBlock    = [pscustomobject]@{ mode = 'strict'; retries = 3 }
            }
        })
        Use-Scratch $appData
        Set-ManifestEntry 'ZCode' 'klite' 'C:\apps\ZCode\Resources\app' '1.2.3' '4.5.6'
        $e = (Read-Manifest)['ZCode']
        check 'the unknown scalar field survived the rewrite' ($e.rollbackPath -eq 'C:\backups\ZCode')
        check 'the unknown nested object survived the rewrite' ($e.futureBlock.mode -eq 'strict' -and $e.futureBlock.retries -eq 3)
        check 'the owned fields were actually updated' ($e.palette -eq 'klite' -and $e.appVersion -eq '1.2.3' -and $e.payloadVersion -eq '4.5.6')
        check 'applied was refreshed by this write' ($e.applied -ne '2026-01-01T00:00:00Z')
        check 'the rewritten manifest still passes the schema gate' (@(Test-ManifestSchema (Read-Manifest)).Count -eq 0)
        check 'the on-disk JSON carries the field too' ((Get-Content -Raw (Join-Path $appData 'installed.json')) -match 'rollbackPath')
    } finally { Remove-Item -Recurse -Force $appData -ErrorAction SilentlyContinue }
}

& {
    # Green: a scalar must not come back as a 1-element array. Get-ManifestField
    # wraps its return on purpose; storing that wrapper back would turn every
    # carried scalar into an array on the way to disk.
    $appData = New-ScratchRoot 'shape'
    try {
        Write-ManifestFile $appData ([pscustomobject]@{
            Notepad = [pscustomobject]@{
                palette = 'golden'; path = 'C:\np'; appVersion = '1'; payloadVersion = '1'
                applied = '2026-01-01T00:00:00Z'; weight = 7
            }
        })
        Use-Scratch $appData
        Set-ManifestEntry 'Notepad' 'golden' 'C:\np' '1' '1'
        $json = Get-Content -Raw (Join-Path $appData 'installed.json')
        # ConvertTo-Json pads the colon with its own whitespace, so the match
        # is on the value's shape, not on a fixed number of spaces.
        check 'a carried scalar stays a scalar, not a 1-element array' ($json -match '"weight":\s+7(\s|,||
|})' -and $json -notmatch '"weight":\s*\[')
    } finally { Remove-Item -Recurse -Force $appData -ErrorAction SilentlyContinue }
}

& {
    # Green: a field this build DOES own must still be authoritative. Carrying
    # forward must not turn into "never overwrite" -- contentDigest is owned, so a
    # custom publish that can no longer compute one must not keep the stale value.
    $appData = New-ScratchRoot 'owned'
    try {
        Write-ManifestFile $appData ([pscustomobject]@{
            Zed = [pscustomobject]@{
                palette = 'custom'; path = 'C:\z'; appVersion = '1'; payloadVersion = '1'
                applied = '2026-01-01T00:00:00Z'; contentDigest = 'stale-digest'
            }
        })
        Use-Scratch $appData
        Set-ManifestEntry 'Zed' 'golden' 'C:\z' '1' '1'
        $e = (Read-Manifest)['Zed']
        check 'an owned field is overwritten, not carried (palette moved off custom)' ($e.palette -eq 'golden')
        check 'an owned field with no new value is removed, not carried (stale digest)' ($null -eq $e.contentDigest)
    } finally { Remove-Item -Recurse -Force $appData -ErrorAction SilentlyContinue }
}

& {
    # Green: the same rule one level down, on multi-item targets.
    $appData = New-ScratchRoot 'multi'
    try {
        Write-ManifestFile $appData ([pscustomobject]@{
            Terminal = [pscustomobject]@{
                palette = 'golden'; path = 'C:\t\settings.json'; appVersion = '1'; payloadVersion = '1'
                applied = '2026-01-01T00:00:00Z'
                scope   = 'per-user'
                items   = @([pscustomobject]@{ path = 'C:\t\settings.json'; backupKind = 'timestamped' })
            }
        })
        Use-Scratch $appData
        Set-ManifestEntryMulti 'Terminal' 'golden' @('C:\t\settings.json') '1' '1'
        $e = (Read-Manifest)['Terminal']
        check 'multi-item: the unknown ENTRY field survived' ($e.scope -eq 'per-user')
        check 'multi-item: the unknown ITEM field survived' ($e.items[0].backupKind -eq 'timestamped')
        check 'multi-item: the owned path set was still rebuilt' ($e.items.Count -eq 1 -and $e.items[0].path -eq 'C:\t\settings.json')
    } finally { Remove-Item -Recurse -Force $appData -ErrorAction SilentlyContinue }
}

# RED control: revert the writer to its verbatim pre-repair body in an in-memory
# copy of common.ps1 and require the same assertion to fail. The product file is
# never touched, and the pre-repair source is re-read from disk afterwards to
# prove it.
Write-Host "`n--- W2-004 RED: the pre-repair write path drops what it does not own ---"

& {
    $src = [System.IO.File]::ReadAllText($common)

    $oldSet = @'
function Set-ManifestEntry($target, $palette, $resolvedPath, $appVersion, $payloadVersion) {
    $lock = Enter-ManifestLock
    try {
        $m = Read-Manifest
        $entry = @{
            palette       = $palette
            path          = $resolvedPath
            appVersion    = $appVersion
            payloadVersion = $payloadVersion
            applied       = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
        $digest = Get-CustomContentDigest -Palette $palette
        if ($digest) { $entry.contentDigest = $digest }
        $m[$target] = $entry
        Write-Manifest $m
    } finally { Exit-ManifestLock $lock }
}
'@

    $startMarker = 'function Set-ManifestEntry($target, $palette, $resolvedPath, $appVersion, $payloadVersion) {'
    $i = $src.IndexOf($startMarker)
    check 'RED: located the shipped Set-ManifestEntry to revert' ($i -ge 0)
    # The shipped body runs to the start of the next top-level `function `.
    $j = $src.IndexOf("`nfunction ", $i + 10)
    $reverted = $src.Substring(0, $i) + $oldSet + $src.Substring($j)

    $appData = New-ScratchRoot 'red'
    # The mutant must sit BESIDE copies of common.ps1's siblings: dot-sourcing it
    # on its own fails on generation-lock.ps1, which proves nothing about W2-004.
    # So the whole module directory is copied out and only common.ps1 is replaced.
    $mutantDir = Join-Path $appData 'modules'
    Copy-Item -Recurse (Split-Path $common) $mutantDir
    $mutant = Join-Path $mutantDir 'common.ps1'
    try {
        [System.IO.File]::WriteAllText($mutant, $reverted, $utf8NoBom)
        Write-ManifestFile $appData ([pscustomobject]@{
            ZCode = [pscustomobject]@{
                palette = 'golden'; path = 'C:\apps\ZCode\Resources\app'
                appVersion = '9.9.9'; payloadVersion = '9.9.9'
                applied = '2026-01-01T00:00:00Z'; rollbackPath = 'C:\backups\ZCode'
            }
        })
        Use-Scratch $appData
        # Dot-sourcing the MUTANT over the shipped module inside this block's
        # scope rebinds Set-ManifestEntry to the pre-repair body for these calls
        # only. Disk is untouched.
        . $mutant
        Set-ManifestEntry 'ZCode' 'klite' 'C:\apps\ZCode\Resources\app' '1.2.3' '4.5.6'
        $e = (Read-Manifest)['ZCode']
        check 'RED: the pre-repair writer SILENTLY DROPS the unknown field' ($null -eq $e.rollbackPath)
        check 'RED: ...while still reporting success and writing the owned fields' ($e.palette -eq 'klite' -and $e.appVersion -eq '1.2.3')
        check 'RED: the product file still carries the carry-forward helper' (
            [System.IO.File]::ReadAllText($common).Contains('Add-ManifestUnknownFields'))
    } finally { Remove-Item -Recurse -Force $appData -ErrorAction SilentlyContinue }
}

Write-Host ''
Write-Host ("manifest forward-compat: $pass passed, $fail failed")
if ($fail -gt 0) { exit 1 }
exit 0