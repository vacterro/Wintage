<#
.SYNOPSIS
  Deterministic maintainer tool: fetch, verify and (only on demand) install the
  bundled terminal fonts from fonts/terminal/sources.json.

.DESCRIPTION
  This is the ONLY place Wintage downloads a font. Runtime never calls it; the
  repo ships the verified files/ tree and works offline. Every artifact is pinned
  to an immutable reference (a google/fonts commit, or a release tag + asset URL)
  and every expected SHA-256 is recorded in sources.json. A mismatch is a hard
  refusal -- there is deliberately no "trust the server" path.

  Modes:
    -VerifyOnly (default)  validate what is already on disk against sources.json
                           and catalog.json. No network. Exit 1 on any drift.
    -Fetch                 download missing artifacts to a temp cache (never
                           into the repo tree), verify hashes, then -Write copies
                           the extracted file + license into fonts/terminal/.
    -Write                 write verified artifacts into the repo tree.
    -Offline               alias of -VerifyOnly (explicit intent).

  Safety: downloaded bytes are treated as untrusted binary assets. They are
  hashed and written -- never executed, never parsed as script. A hash mismatch
  refuses and leaves the existing file untouched.

.EXAMPLE
  ./tools/sync-terminal-fonts.ps1 -VerifyOnly
.EXAMPLE
  ./tools/sync-terminal-fonts.ps1 -Fetch -Write
#>
[CmdletBinding()]
param(
    [switch]$VerifyOnly,
    [switch]$Fetch,
    [switch]$Write,
    [switch]$Offline,
    [string]$CacheDir = (Join-Path ([System.IO.Path]::GetTempPath()) 'wintage-terminal-fonts')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path $PSScriptRoot -Parent
$fontRoot = Join-Path $root 'fonts\terminal'
$sourcesPath = Join-Path $fontRoot 'sources.json'
$catalogPath = Join-Path $fontRoot 'catalog.json'

if (-not (Test-Path -LiteralPath $sourcesPath)) { throw "sources.json not found at $sourcesPath" }
if (-not (Test-Path -LiteralPath $catalogPath)) { throw "catalog.json not found at $catalogPath" }

$sources = Get-Content -LiteralPath $sourcesPath -Raw | ConvertFrom-Json
$catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json

$script:errors = 0
function Fail([string]$msg) { Write-Host "[FAIL] $msg" -ForegroundColor Red; $script:errors++ }
function Ok([string]$msg) { Write-Host "[ OK ] $msg" -ForegroundColor Green }

function Get-Sha256([string]$path) {
    (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-FileHash([string]$path, [string]$expected, [string]$label) {
    if (-not (Test-Path -LiteralPath $path)) { Fail "$label missing: $path"; return $false }
    $actual = Get-Sha256 $path
    if ($actual -ne $expected.ToLowerInvariant()) {
        Fail "$label SHA-256 mismatch: expected $expected, got $actual ($path)"
        return $false
    }
    return $true
}

function Expand-ZipEntry([string]$zip, [string]$entry, [string]$dest) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $item = $archive.GetEntry($entry)
        if (-not $item) { throw "archive member '$entry' not found in $zip" }
        $reader = New-Object System.IO.StreamReader($item.Open())
        try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $bytes = [byte[]]@()
        # Re-read as binary for .ttf (StreamReader would mangle bytes); text path
        # is only used for license entries. Detect by extension.
        if ([System.IO.Path]::GetExtension($dest) -match '^\.(ttf|otf|ttc)$') {
            $stream = $item.Open()
            try {
                $ms = New-Object System.IO.MemoryStream
                $stream.CopyTo($ms)
                $bytes = $ms.ToArray()
                $ms.Dispose()
            } finally { $stream.Dispose() }
            [System.IO.File]::WriteAllBytes($dest, $bytes)
        } else {
            [System.IO.File]::WriteAllText($dest, $text, (New-Object System.Text.UTF8Encoding($false)))
        }
    } finally { $archive.Dispose() }
}

function Get-Raw([string]$url, [string]$dest) {
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 300
}

$verifyOnly = $VerifyOnly -or $Offline -or (-not $Fetch -and -not $Write)
if ($Offline) { $Fetch = $false; $Write = $false }

# The expected hash of the FILE that lands in fonts/terminal/files. A `raw`
# artifact IS the file, so it has only sha256_file; a `zip` artifact extracts a
# named member and records its own sha256_out.
function Get-ExpectedOutHash($entry) {
    if ($entry.PSObject.Properties.Name -contains 'sha256_out') { return $entry.sha256_out }
    return $entry.sha256_file
}

# ---- 1. Verify the on-disk tree against sources.json -------------------------
Write-Host "== verifying vendored terminal fonts against the pin manifest ==" -ForegroundColor Cyan
foreach ($entry in $sources.fonts) {
    $outPath = Join-Path $fontRoot ($entry.out -replace '/', '\')
    $licPath = Join-Path $fontRoot ($entry.license_out -replace '/', '\')
    if (Test-FileHash $outPath (Get-ExpectedOutHash $entry) $entry.slug) { Ok "$($entry.slug): file hash verified" }
    if (Test-FileHash $licPath $entry.license_sha256 "$($entry.slug) license") { Ok "$($entry.slug): license hash verified" }
}

# ---- 2. Catalog <-> sources consistency --------------------------------------
Write-Host "== catalog <-> manifest consistency ==" -ForegroundColor Cyan
$bundledCatalog = @($catalog.fonts | Where-Object { $_.bundled })
if ($bundledCatalog.Count -ne 20) { Fail "catalog must list exactly 20 bundled families, found $($bundledCatalog.Count)" } else { Ok "catalog lists 20 bundled families" }
foreach ($entry in $sources.fonts) {
    $cat = $bundledCatalog | Where-Object { $_.slug -eq $entry.slug }
    if (-not $cat) { Fail "sources.json entry '$($entry.slug)' has no bundled catalog row"; continue }
    if ($cat.sha256 -ne (Get-ExpectedOutHash $entry)) { Fail "$($entry.slug): catalog sha256 != manifest file hash" }
    if (($cat.file -replace '\\', '/') -ne $entry.out) { Fail "$($entry.slug): catalog file '$($cat.file)' != manifest out '$($entry.out)'" }
}

# ---- 3. Optional fetch/write -------------------------------------------------
if ($Fetch) {
    if (-not (Test-Path -LiteralPath $CacheDir)) { New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null }
    Write-Host "== fetching pinned artifacts into $CacheDir ==" -ForegroundColor Cyan
    foreach ($entry in $sources.fonts) {
        $cacheName = ($entry.slug + [System.IO.Path]::GetExtension($entry.url))
        $cached = Join-Path $CacheDir $cacheName
        if (Test-Path -LiteralPath $cached) {
            $have = Get-Sha256 $cached
            if ($have -eq $entry.sha256_file.ToLowerInvariant()) { Ok "$($entry.slug): cache hit, archive hash ok"; continue }
        }
        Write-Host "  downloading $($entry.url)"
        Get-Raw $entry.url $cached
        if ((Get-Sha256 $cached) -ne $entry.sha256_file.ToLowerInvariant()) {
            Remove-Item -LiteralPath $cached -Force
            Fail "$($entry.slug): downloaded archive SHA-256 mismatch -- removed, refusing to use it"
        } else { Ok "$($entry.slug): archive hash verified" }
    }

    if ($Write) {
        Write-Host "== writing verified artifacts into the repo tree ==" -ForegroundColor Cyan
        $filesDir = Join-Path $fontRoot 'files'
        $licDir = Join-Path $fontRoot 'licenses'
        New-Item -ItemType Directory -Force -Path $filesDir, $licDir | Out-Null
        $tmp = Join-Path $CacheDir 'extract.tmp'
        foreach ($entry in $sources.fonts) {
            $cacheName = ($entry.slug + [System.IO.Path]::GetExtension($entry.url))
            $cached = Join-Path $CacheDir $cacheName
            $outPath = Join-Path $fontRoot ($entry.out -replace '/', '\')
            $licPath = Join-Path $fontRoot ($entry.license_out -replace '/', '\')

            if ($entry.kind -eq 'raw') {
                if ((Get-Sha256 $cached) -ne (Get-ExpectedOutHash $entry)) { Fail "$($entry.slug): raw hash != expected file hash"; continue }
                Copy-Item -LiteralPath $cached -Destination $outPath -Force
            } else {
                Expand-ZipEntry $cached $entry.entry $tmp
                if ((Get-Sha256 $tmp) -ne (Get-ExpectedOutHash $entry)) { Fail "$($entry.slug): extracted member hash mismatch"; Remove-Item $tmp -Force; continue }
                Move-Item -LiteralPath $tmp -Destination $outPath -Force
            }
            if ($entry.license_entry) { Expand-ZipEntry $cached $entry.license_entry $licPath }
            elseif ($entry.license_url) { Get-Raw $entry.license_url $licPath }
            Ok "$($entry.slug): wrote file + license"
        }
    }
}

Write-Host ""
if ($script:errors) { Write-Host "$($script:errors) terminal-font check(s) FAILED" -ForegroundColor Red; exit 1 }
Write-Host "terminal font sync: ALL CHECKS PASSED" -ForegroundColor Green
exit 0
