# README source-digest stamping step (T-415; improve cycle imp-vacterro-wintage-20261005-4, RUN-1/IMP-002).
#
# Defect class this step pins down:
# the T-413 wave rewrote all 64 locale stamps by hand and escaped the path inside
# the marker -- '<!-- source-digest: README\\.md sha256:<hex> -->' -- while the
# consuming gate matches 'source-digest:\s*README\.md\s*sha256:' against the file
# text. Neither set matched, so 32 root and 32 desktop READMEs reported "carries a
# source-digest stamp" red, and only the live gate caught it. The stamping step had
# no way to fail: it wrote what it liked and reported success.
#
# This is the step, and it cannot finish on a stamp the gate cannot read: it
# rewrites the marker in the one canonical form (one literal per README set, so the
# path cannot drift from what the gate parses) and then runs
# tools/test-readme-target-parity.ps1, exiting with that gate's code. Re-stamping
# never touches anything but the digest inside an existing marker; a locale with no
# marker is REPORTED rather than given one in a guessed place. Byte handling keeps
# a BOM and the original line endings, so an already-canonical set is left
# byte-identical.
#
#   tools/stamp-readme-digests.ps1            # stamp both sets, then verify
#   tools/stamp-readme-digests.ps1 -Verify    # report only, write nothing
#   tools/stamp-readme-digests.ps1 -WhatIf    # report which files would change
#   tools/stamp-readme-digests.ps1 -RedControl  # scratch-tree proof (the checkout is untouched)
#
# Exit 0 = every stamp is canonical and the parity gate passes, 1 = it does not,
# 2 = usage error.

# -WhatIf is declared here rather than taken from CmdletBinding's
# SupportsShouldProcess, because Get-FileHash honors the preference and returns
# nothing under it -- the step would die reading .Hash of a null digest and could
# never report which files it would touch.
[CmdletBinding()]
param(
    [string]$Root,
    [switch]$Verify,
    [switch]$WhatIf,
    [switch]$NoGate,
    [switch]$RedControl
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$script:root = if ($Root) { $Root } else { Split-Path $here -Parent }

# One literal per README set: the marker text and the source whose bytes it stamps.
# The pattern accepts both the canonical and the escaped path spelling, because the
# escaped one is what a hand stamp produces and this step has to repair it.
function Get-Sets([string]$root) {
    @(
        [pscustomobject]@{
            Label   = 'root'
            Dir     = Join-Path $root 'locales'
            Source  = Join-Path $root 'README.md'
            Text    = 'README.md'
            Pattern = '<!--\s*source-digest:\s*README\\?\.md\s*sha256:[0-9a-f]{16}\s*-->'
        }
        [pscustomobject]@{
            Label   = 'desktop'
            Dir     = Join-Path $root 'desktop'
            Source  = Join-Path $root 'desktop\README.md'
            Text    = 'desktop/README.md'
            Pattern = '<!--\s*source-digest:\s*desktop/README\\?\.md\s*sha256:[0-9a-f]{16}\s*-->'
        }
    )
}

function Invoke-StampSet($set, [switch]$verify, [switch]$whatIf) {
    if (-not (Test-Path $set.Source)) { Write-Host "no source README at $($set.Source)" -ForegroundColor Red; return $null }
    $digest = (Get-FileHash -Path $set.Source -Algorithm SHA256).Hash.ToLower().Substring(0, 16)
    $canonical = "<!-- source-digest: $($set.Text) sha256:$digest -->"
    Write-Host "$($set.Label) set -- source digest $digest"

    $files = @(Get-ChildItem -Path $set.Dir -Filter 'README.*.md' -File | Sort-Object Name)
    if ($files.Count -eq 0) { Write-Host "  no locale READMEs in $($set.Dir)" -ForegroundColor Red; return $null }
    $written = 0; $canonicalAlready = 0; $unmarked = @()
    foreach ($f in $files) {
        $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
        $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        if ($bom) { $text = $text.Substring(1) }
        if ($text -notmatch $set.Pattern) { $unmarked += "$($set.Label)/$($f.Name)"; continue }
        $new = [regex]::Replace($text, $set.Pattern, $canonical.Replace('$', '$$'))
        if ($new -eq $text) { $canonicalAlready++; continue }
        if ($verify -or $whatIf) { Write-Host "  would re-stamp $($f.Name)" -ForegroundColor Yellow; $written++; continue }
        $enc = New-Object System.Text.UTF8Encoding($false)
        $out = $enc.GetBytes($new)
        if ($bom) { $out = @(0xEF, 0xBB, 0xBF) + $out }
        [System.IO.File]::WriteAllBytes($f.FullName, $out)
        Write-Host "  stamped $($f.Name)"
        $written++
    }
    Write-Host "  stamps: $written written, $canonicalAlready already canonical, $($unmarked.Count) locale(s) with no marker"
    if ($unmarked.Count) {
        Write-Host "  no marker to update; add one where that set carries it: $(($unmarked | Select-Object -First 8) -join ', ')" -ForegroundColor Yellow
    }
    [pscustomobject]@{ Set = $set.Label; Written = $written; Canonical = $canonicalAlready; Unmarked = $unmarked.Count; Digest = $digest }
}

if ($RedControl) {
    # Proven in a scratch tree: this checkout is never mutated.
    $pass = 0; $fail = 0
    function check($label, $cond) {
        if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
        else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
    }
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-stamp-" + [Guid]::NewGuid().ToString('N').Substring(0, 12))
    New-Item -ItemType Directory -Path (Join-Path $tmp 'locales') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp 'desktop') -Force | Out-Null
    try {
        Set-Content -Path (Join-Path $tmp 'README.md') -Value 'root source'
        Set-Content -Path (Join-Path $tmp 'desktop/README.md') -Value 'desktop source'
        # The escaped spelling the T-413 wave produced, with a stale digest.
        $escapedRoot = '<!-- source-digest: README\.md sha256:0000000000000000 -->'
        $escapedDesktop = '<!-- source-digest: desktop/README\.md sha256:0000000000000000 -->'
        Set-Content -Path (Join-Path $tmp 'locales/README.et.md') -Value "title`n$escapedRoot"
        Set-Content -Path (Join-Path $tmp 'desktop/README.et.md') -Value "title`n$escapedDesktop"

        & powershell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Root $tmp -NoGate | Out-Null
        $code = $LASTEXITCODE
        check 'scratch: the step exits 0 on a repairable set' ($code -eq 0)

        $rootDigest = (Get-FileHash -Path (Join-Path $tmp 'README.md') -Algorithm SHA256).Hash.ToLower().Substring(0, 16)
        $desktopDigest = (Get-FileHash -Path (Join-Path $tmp 'desktop/README.md') -Algorithm SHA256).Hash.ToLower().Substring(0, 16)
        $rootText = [System.IO.File]::ReadAllText((Join-Path $tmp 'locales/README.et.md'))
        $desktopText = [System.IO.File]::ReadAllText((Join-Path $tmp 'desktop/README.et.md'))
        check 'scratch: the escaped path spelling is repaired to the canonical one' `
            ($rootText -notmatch 'README\\\.md' -and $desktopText -notmatch 'desktop/README\\\.md')
        check 'scratch: the root marker now carries the live source digest' `
            ($rootText -match "source-digest: README\.md sha256:$rootDigest")
        check 'scratch: the desktop marker now carries the live source digest' `
            ($desktopText -match "source-digest: desktop/README\.md sha256:$desktopDigest")
        check 'scratch: the stale digest is gone' `
            ($rootText -notmatch '0000000000000000' -and $desktopText -notmatch '0000000000000000')
        check 'scratch: the reparsed line still resolves through the gate regex' `
            (([regex]::Match($rootText, 'source-digest:\s*README\.md\s*sha256:([0-9a-f]{16})')).Groups[1].Value -eq $rootDigest)

        $second = & powershell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Root $tmp -NoGate 2>&1 | Out-String
        check 'scratch: a second run is idempotent (nothing left to write)' `
            ($second -match 'stamps: 0 written, 1 already canonical')
    }
    finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
    Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
    exit $fail
}

$results = @(foreach ($set in (Get-Sets $script:root)) { Invoke-StampSet $set -verify:$Verify -whatIf:$WhatIf })
if ($results -contains $null) { exit 2 }
$unmarked = ($results | Measure-Object -Property Unmarked -Sum).Sum
if ($unmarked -gt 0) { exit 1 }

# The step is not finished until the gate that consumes these stamps has read them.
if ($NoGate) { exit 0 }
Write-Host "`n--- tools/test-readme-target-parity.ps1 on the stamped result ---"
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'test-readme-target-parity.ps1')
$gate = $LASTEXITCODE
$ErrorActionPreference = $prevEap
if ($gate -ne 0) { Write-Host "the parity gate refuses the stamped result (exit $gate)" -ForegroundColor Red }
exit $gate
