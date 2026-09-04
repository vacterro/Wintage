# Get-InstallEpoch fail-closed regression suite (T-205 / CORE-008).
#
# The install epoch is the install identity that every persistent recovery
# file is stamped with. Auto-rotating it on a corrupt file (the pre-fix
# behaviour) would silently disconnect every provenance-stamped recovery
# from the install that wrote it, and the next Assert-RecoveryProvenance
# call would reject its own files as foreign -- locking the user out of
# every recovery. The contract is therefore fail-closed on corruption: the
# corrupt bytes are preserved exactly, no rotation, and the caller sees
# an error. A genuinely absent file is still created exactly once and
# remains stable across calls.
#
# Every fixture here lives under a unique temp app-data root injected
# through WINTAGE_APPDATA; the live %APPDATA%\Wintage\install-epoch.json
# is never read or written.
#
#   .\tools\test-epoch.ps1          # all tests
#   .\tools\test-epoch.ps1 -List    # list tests

[CmdletBinding()]
param([switch]$List)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$common = Join-Path $here '..\desktop\modules\common.ps1'
$pass = 0; $fail = 0
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:Utf8WithBom = New-Object System.Text.UTF8Encoding($true)

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

if ($List) {
    Write-Host "test-epoch.ps1 (10 tests):"
    Write-Host "  1. absent-epoch-creates-exactly-once-and-is-stable"
    Write-Host "  2. valid-epoch-is-returned-unmodified"
    Write-Host "  3. corrupt-json-throws-and-preserves-original-bytes"
    Write-Host "  4. empty-id-throws-and-preserves-original-bytes"
    Write-Host "  5. non-object-root-throws-and-preserves-original-bytes"
    Write-Host "  6. pre-existing-id-supplies-stamped-recovery-stays-verifiable"
    Write-Host "  7. corrupt-epoch-does-not-rotate-and-foreign-stamp-stays-foreign"
    Write-Host "  8. dot-source-of-common-ps1-is-the-only-loader"
    Write-Host "  9. concurrent-first-create-barrier-two-processes-one-identity"
    Write-Host " 10. concurrent-first-create-barrier-four-processes-one-identity"
    exit 0
}

# Dot-source the module under test once. Set the two script-scope UTF8
# encodings first so Read-Utf8/Write-Utf8 don't read $script:Utf8NoBom as
# $null. Define a top-level $WintageAppData so Get-InstallEpoch can resolve
# the install-epoch.json path.
. $common
$prevAppData = $env:WINTAGE_APPDATA

function Reset-AppData {
    param([string]$Label)
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-epoch-test-$Label-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $env:WINTAGE_APPDATA = $dir
    $script:WintageAppData = $dir
    return $dir
}

function Cleanup-AppData {
    if ($env:WINTAGE_APPDATA -and (Test-Path $env:WINTAGE_APPDATA)) {
        Remove-Item $env:WINTAGE_APPDATA -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$epochPath = { Join-Path $env:WINTAGE_APPDATA 'install-epoch.json' }

# ---- Test 1: absent epoch -> creates exactly once, stable across calls ----
try {
    Reset-AppData 'absent' | Out-Null
    $p = & $epochPath
    check 'absent: epoch file does not exist before first call' (-not (Test-Path $p))
    $id1 = Get-InstallEpoch
    check 'absent: epoch file exists after first call' (Test-Path $p)
    check 'absent: id looks like a 32-char hex GUID' ($id1 -match '^[0-9a-f]{32}$')
    $id2 = Get-InstallEpoch
    check 'absent: second call returns the SAME id (no rotation)' ($id1 -eq $id2)
    $bytes = [System.IO.File]::ReadAllText($p, $script:Utf8NoBom)
    $j = $bytes | ConvertFrom-Json
    check 'absent: persisted id matches returned id' ($j.id -eq $id1)
    check 'absent: firstSeen is present and parseable' ($null -ne $j.firstSeen -and ($j.firstSeen -as [datetime]) -ne $null)
    Cleanup-AppData
} finally { }

# ---- Test 2: valid epoch -> returned as-is, never overwritten ----
try {
    $dir = Reset-AppData 'valid'
    $p = & $epochPath
    $seed = 'aabbccddeeff00112233445566778899'
    [System.IO.File]::WriteAllText($p, (@{ id = $seed; firstSeen = '2026-01-01T00:00:00Z' } | ConvertTo-Json), $script:Utf8NoBom)
    $got = Get-InstallEpoch
    check 'valid: returned id equals the seeded id' ($got -eq $seed)
    $after = [System.IO.File]::ReadAllText($p, $script:Utf8NoBom)
    check 'valid: file bytes are byte-identical (no rotation)' ($after -eq (@{ id = $seed; firstSeen = '2026-01-01T00:00:00Z' } | ConvertTo-Json))
    # Calling again must still be a no-op.
    $got2 = Get-InstallEpoch
    check 'valid: second call returns the seeded id (still no rotation)' ($got2 -eq $seed)
    Cleanup-AppData
} finally { }

# ---- Test 3: corrupt JSON -> throws, original bytes preserved ----
try {
    Reset-AppData 'corrupt' | Out-Null
    $p = & $epochPath
    $bad = '{ this is not json'
    [System.IO.File]::WriteAllText($p, $bad, $script:Utf8NoBom)
    $threw = $false
    try { Get-InstallEpoch | Out-Null } catch { $threw = $true }
    check 'corrupt: Get-InstallEpoch THREW' $threw
    $after = [System.IO.File]::ReadAllText($p, $script:Utf8NoBom)
    check 'corrupt: original bytes preserved EXACTLY' ($after -eq $bad)
    Cleanup-AppData
} finally { }

# ---- Test 4: empty / whitespace id -> throws, original bytes preserved ----
try {
    Reset-AppData 'emptyid' | Out-Null
    $p = & $epochPath
    $bad = '{"id":"   ","firstSeen":"2026-01-01T00:00:00Z"}'
    [System.IO.File]::WriteAllText($p, $bad, $script:Utf8NoBom)
    $threw = $false
    try { Get-InstallEpoch | Out-Null } catch { $threw = $true }
    check 'emptyid: Get-InstallEpoch THREW on whitespace id' $threw
    $after = [System.IO.File]::ReadAllText($p, $script:Utf8NoBom)
    check 'emptyid: original bytes preserved EXACTLY' ($after -eq $bad)
    # A second corrupt-style failure must not have rotated.
    $threw2 = $false
    try { Get-InstallEpoch | Out-Null } catch { $threw2 = $true }
    check 'emptyid: second call ALSO THREW (still no rotation)' $threw2
    $after2 = [System.IO.File]::ReadAllText($p, $script:Utf8NoBom)
    check 'emptyid: bytes still preserved EXACTLY after retry' ($after2 -eq $bad)
    Cleanup-AppData
} finally { }

# ---- Test 5: non-object root (top-level array) -> throws, bytes preserved ----
try {
    Reset-AppData 'array' | Out-Null
    $p = & $epochPath
    $bad = '[1,2,3]'
    [System.IO.File]::WriteAllText($p, $bad, $script:Utf8NoBom)
    $threw = $false
    try { Get-InstallEpoch | Out-Null } catch { $threw = $true }
    check 'array: Get-InstallEpoch THREW on top-level array' $threw
    $after = [System.IO.File]::ReadAllText($p, $script:Utf8NoBom)
    check 'array: original bytes preserved EXACTLY' ($after -eq $bad)
    Cleanup-AppData
} finally { }

# ---- Test 6: stamped recovery from the existing identity is still accepted ----
# (CORE-008 verify bar: "preserve recovery A".)
try {
    $dir = Reset-AppData 'stamped'
    $p = & $epochPath
    $seed = '112233445566778899aabbccddeeff00'
    [System.IO.File]::WriteAllText($p, (@{ id = $seed; firstSeen = '2026-01-01T00:00:00Z' } | ConvertTo-Json), $script:Utf8NoBom)
    # A recovery file stamped with this epoch must still verify.
    $recovery = Join-Path $dir 'recovery-test.bin'
    [System.IO.File]::WriteAllBytes($recovery, [byte[]]@(0,1,2,3))
    Write-RecoveryProvenance $recovery 'test-target'
    check 'stamped: provenance file written next to the recovery' (Test-Path ($recovery + '.provenance.json'))
    $accepted = $false
    try {
        Assert-RecoveryProvenance $recovery 'test-target' 'test-target' | Out-Null
        $accepted = $true
    } catch { $accepted = $false }
    check 'stamped: same-epoch provenance is accepted' $accepted
    Cleanup-AppData
} finally { }

# ---- Test 7: foreign provenance + valid epoch is still REJECTED (unchanged) ----
# (Sanity check: the fail-closed contract for cross-install recovery files is
# preserved by the fix -- only the producer's rotation was the bug.)
try {
    $dir = Reset-AppData 'foreign'
    $p = & $epochPath
    $seed = 'cafebabecafebabecafebabecafebabe'
    [System.IO.File]::WriteAllText($p, (@{ id = $seed; firstSeen = '2026-01-01T00:00:00Z' } | ConvertTo-Json), $script:Utf8NoBom)
    $recovery = Join-Path $dir 'foreign.bin'
    [System.IO.File]::WriteAllBytes($recovery, [byte[]]@(9,8,7))
    # Manually stamp with a different epoch.
    [System.IO.File]::WriteAllText(($recovery + '.provenance.json'),
        (@{ owner = 'wintage'; target = 'foreign'; epoch = '00000000000000000000000000000000'; created = '2026-01-01T00:00:00Z' } | ConvertTo-Json),
        $script:Utf8NoBom)
    $threw = $false
    try { Assert-RecoveryProvenance $recovery 'foreign' 'foreign' | Out-Null } catch { $threw = $true }
    check 'foreign: cross-epoch provenance STILL throws' $threw
    Cleanup-AppData
} finally { }

# ---- Test 8: dot-source path is the only loader (no other $WintageAppData paths) ----
# This is a static contract: Get-InstallEpoch must ONLY resolve its path through
# $WintageAppData, never an env var or hard-coded fallback. Confirms the fix
# cannot accidentally introduce a second resolver.
try {
    Reset-AppData 'static' | Out-Null
    $src = Get-Content $common -Raw
    # Single RESOLVER: the epoch path may only ever be derived once, through
    # $WintageAppData. (The W2-003 cleanup filter names the creation-temp
    # pattern, which is a different string and does not resolve anything.)
    $count = ([regex]::Matches($src, [regex]::Escape("Join-Path `$WintageAppData 'install-epoch.json'"))).Count
    check 'static: install-epoch.json resolved exactly once in common.ps1 (single resolver)' ($count -eq 1)
    $lockCount = ([regex]::Matches($src, [regex]::Escape("Join-Path `$WintageAppData 'install-epoch.lock'"))).Count
    check 'static: the epoch lock path also has exactly one resolver' ($lockCount -eq 1)
    Cleanup-AppData
} finally { }

# ---- Tests 9+10: W2-003 -- concurrent first creation yields ONE identity ----
# Barrier-synchronised children all observe "epoch absent" at the same moment.
# The old absent-check + private GUID + forced rename let every child return
# its OWN id; the loser's recovery provenance was then stamped with an identity
# the persisted file never carried, and Assert-RecoveryProvenance later rejected
# Wintage's own backup as foreign. The lock must make every child return the
# persisted winner, and provenance written by EVERY child must verify.
function Invoke-ConcurrentFirstCreate {
    param([int]$Children)
    $dir = Reset-AppData ("race$Children")
    $goFile = Join-Path $dir 'go'
    $childFile = Join-Path $dir 'epoch-child.ps1'
    Write-Utf8 $childFile @'
param($appData, $common, $goFile, $i)
$ErrorActionPreference = 'Stop'
$env:WINTAGE_APPDATA = $appData
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:Utf8WithBom = New-Object System.Text.UTF8Encoding($true)
. $common
$script:WintageAppData = $appData
Set-Content -LiteralPath (Join-Path $appData "ready-$i") -Value 'r'
$deadline = (Get-Date).AddSeconds(30)
while (-not (Test-Path $goFile) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 20 }
if (-not (Test-Path $goFile)) { Set-Content (Join-Path $appData "result-$i") 'TIMEOUT|False'; exit 0 }
$id = Get-InstallEpoch
$recovery = Join-Path $appData "recovery-$i.bin"
[System.IO.File]::WriteAllBytes($recovery, [byte[]]@(1, 2, 3))
Write-RecoveryProvenance $recovery 'race-target'
$verified = $false
try { Assert-RecoveryProvenance $recovery 'race-target' 'race-target' | Out-Null; $verified = $true } catch { }
Set-Content -LiteralPath (Join-Path $appData "result-$i") -Value "$id|$verified"
exit 0
'@
    $jobs = @()
    for ($i = 1; $i -le $Children; $i++) {
        $jobs += Start-Process powershell -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
            $childFile, $dir, $common, $goFile, "$i"
        ) -PassThru -WindowStyle Hidden
    }
    # Barrier: wait until every child is parked on the go-file, then release.
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-ChildItem $dir -Filter 'ready-*' -ErrorAction SilentlyContinue).Count -lt $Children -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 20
    }
    Set-Content -LiteralPath $goFile -Value 'go'
    $jobs | ForEach-Object { $_.WaitForExit(60000) | Out-Null }
    $p = & $epochPath
    $ids = @()
    $allVerified = $true
    for ($i = 1; $i -le $Children; $i++) {
        $resultFile = Join-Path $dir "result-$i"
        if (-not (Test-Path $resultFile)) { $allVerified = $false; continue }
        $parts = (Get-Content $resultFile -Raw).Trim() -split '\|'
        $ids += $parts[0]
        if ($parts[1] -ne 'True') { $allVerified = $false }
    }
    $persisted = $null
    if (Test-Path $p) { $persisted = ([System.IO.File]::ReadAllText($p, $script:Utf8NoBom) | ConvertFrom-Json).id }
    $races = @{
        Ids = $ids
        AllReturnedPersisted = ($ids.Count -eq $Children) -and (($ids | Where-Object { $_ -ne $persisted }).Count -eq 0)
        Persisted = $persisted
        AllVerified = $allVerified
    }
    Cleanup-AppData
    return $races
}

foreach ($n in 2, 4) {
    $r = Invoke-ConcurrentFirstCreate -Children $n
    check "race-$n`: every child returned an id" ($r.Ids.Count -eq $n)
    check "race-$n`: all children returned the PERSISTED winner" $r.AllReturnedPersisted
    check "race-$n`: persisted id looks like a 32-char hex GUID" ($r.Persisted -match '^[0-9a-f]{32}$')
    check "race-$n`: recovery written by every child self-verifies" $r.AllVerified
}

$env:WINTAGE_APPDATA = $prevAppData

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail
