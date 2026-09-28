# Terminal Fonts subsystem -- private preview, catalog, capability and apply
# glue for WintageInstaller.ps1 (T-283 / SRC-026).
#
# Dot-sourced by the GUI AFTER i18n.ps1 and the palette loader, so it can use
# Get-ActiveTokens / C / T / Say-Log from the caller's scope (functions here run
# in the caller's scope, exactly like desktop/modules/targets.ps1).
#
# Design contract:
#   - The catalog is loaded ONCE from fonts/terminal/catalog.json and never
#     re-read per selection.
#   - Preview loads bundled TTFs into a PrivateFontCollection, so browsing a face
#     performs ZERO system font registration. Loaded families are cached for the
#     GUI lifetime and disposed on close.
#   - Capability is PROBED, never assumed: a bundled-but-uninstalled face is
#     previewable but not applicable; conhost additionally requires a resolved
#     fixed-pitch family.
#   - The canonical preference is read/written ONLY through
#     tools/terminal-font-preference.js -- no second schema.

$script:TfRoot = $root
$script:TfCatalog = $null
$script:TfCatalogBySlug = @{}
$script:TfPrivateCollections = @{}     # slug -> PrivateFontCollection (live)
$script:TfPrivateFamilies = @{}        # slug -> Drawing.FontFamily (live)
$script:TfInstalledNames = $null       # lazy probe cache
$script:TfPreviewFont = $null
$script:TfSelectedSlug = $null
$script:TfSize = 12
$script:TfRendering = 'aliased'

function Get-TfCatalogPath { Join-Path $script:TfRoot 'fonts\terminal\catalog.json' }

# Load the catalog once. A malformed/absent catalog is a hard error: the tab
# cannot honestly show font state without it.
function Initialize-TfCatalog {
    if ($script:TfCatalog) { return $script:TfCatalog }
    $path = Get-TfCatalogPath
    if (-not (Test-Path -LiteralPath $path)) { throw "terminal font catalog not found: $path" }
    $raw = [System.IO.File]::ReadAllText($path, (New-Object System.Text.UTF8Encoding($false))) -replace '^\uFEFF', ''
    $doc = $raw | ConvertFrom-Json
    if ([int]$doc.schema -ne 1 -or -not $doc.fonts) { throw "terminal font catalog: schema must be 1 and carry fonts[]" }
    $script:TfCatalog = $doc
    $script:TfCatalogBySlug = @{}
    foreach ($f in $doc.fonts) {
        if ($script:TfCatalogBySlug.ContainsKey($f.slug)) { throw "terminal font catalog: duplicate slug '$($f.slug)'" }
        $script:TfCatalogBySlug[$f.slug] = $f
    }
    return $doc
}

function Get-TfEntries { (Initialize-TfCatalog).fonts }
function Get-TfEntry([string]$slug) { if ($script:TfCatalogBySlug.ContainsKey($slug)) { $script:TfCatalogBySlug[$slug] } else { $null } }
function Get-TfPreviewSample { (Initialize-TfCatalog).previewSample }

# --- capability probes --------------------------------------------------------
# Family enumeration is the same question the themed apps ask, and sees HKLM,
# HKCU and per-user Fonts alike. Cached per GUI run.
function Get-TfInstalledNames {
    if ($null -ne $script:TfInstalledNames) { return $script:TfInstalledNames }
    $set = @{}
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        foreach ($fam in [System.Drawing.FontFamily]::Families) { $set[$fam.Name] = $true }
    } catch {
        foreach ($hive in @('HKCU:', 'HKLM:')) {
            $key = "$hive\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
            $props = Get-ItemProperty $key -ErrorAction SilentlyContinue
            if ($props) { foreach ($n in $props.PSObject.Properties.Name) { $set[$n] = $true } }
        }
    }
    $script:TfInstalledNames = $set
    return $set
}

function Test-TfFamilyInstalled([string]$family) {
    if (-not $family) { return $false }
    return (Get-TfInstalledNames).ContainsKey($family)
}

# Is the given vendored file fixed-pitch (monospace)? Reads the face's own
# metrics via GDI+ -- a proportional face must never reach conhost.
# PERF-001: fixed-pitch probe cache keyed by immutable bundled-file identity
# (path + size + mtime ticks). An unchanged file never re-probes within a GUI
# epoch. Re-probe after a Windows-owned installation via Clear-TfCapabilityCache.
$script:TfFixedPitchCache = @{}

function Get-TfFileIdentity([string]$path) {
    try {
        $item = Get-Item -LiteralPath $path -ErrorAction Stop
        return "$path|$($item.Length)|$($item.LastWriteTimeUtc.Ticks)"
    } catch { return $path }
}

function Clear-TfCapabilityCache {
    $script:TfFixedPitchCache = @{}
}

function Test-TfFileFixedPitch([string]$path, [string]$slug) {
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    try {
        $pfc = Get-TfPrivateCollection $slug $path
        if (-not $pfc -or $pfc.Families.Count -eq 0) { return $false }
        $fam = $pfc.Families[0]
        # A cell-grid font has advance widths equal for 'i' and 'W'.
        $bmp = New-Object System.Drawing.Bitmap 64, 32
        try {
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $f = New-Object System.Drawing.Font($fam, 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
                try {
                    $wi = $g.MeasureString('i', $f).Width
                    $wW = $g.MeasureString('W', $f).Width
                    $wM = $g.MeasureString('M', $f).Width
                    $max = [Math]::Max($wi, [Math]::Max($wW, $wM))
                    $min = [Math]::Min($wi, [Math]::Min($wW, $wM))
                    return (($max - $min) -le 0.6)
                } finally { $f.Dispose() }
            } finally { $g.Dispose() }
        } finally { $bmp.Dispose() }
    } catch { return $false }
}

# PERF-001: memoize the probe outcome per immutable file identity.
function Test-TfFileFixedPitchCached([string]$path, [string]$slug) {
    $identity = Get-TfFileIdentity $path
    if ($script:TfFixedPitchCache.ContainsKey($identity)) { return $script:TfFixedPitchCache[$identity] }
    $result = Test-TfFileFixedPitch $path $slug
    $script:TfFixedPitchCache[$identity] = $result
    return $result
}

# Is a RESOLVED family fixed-pitch (monospace) on this machine? Measures the
# living family the way conhost resolves it -- several glyphs, not one pair --
# so a proportional installed face can never reach HKCU\Console. The bundled-file
# variant (Test-TfFileFixedPitch) only checks the vendored TTF; this also covers
# system-only families (Terminus, Consolas) through GDI+ enumeration of the
# resolved family.
function Test-TfFamilyFixedPitch([string]$family) {
    if (-not $family) { return $false }
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $fam = $null
        foreach ($f in [System.Drawing.FontFamily]::Families) { if ($f.Name -eq $family) { $fam = $f; break } }
        if (-not $fam) { return $false }
        $bmp = New-Object System.Drawing.Bitmap 64, 32
        try {
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $font = New-Object System.Drawing.Font($fam, 12, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
                try {
                    $wid = @('i','W','M','0','1',' ')
                    $widths = @($wid | ForEach-Object { $g.MeasureString($_, $font).Width })
                    $max = ($widths | Measure-Object -Maximum).Maximum
                    $min = ($widths | Measure-Object -Minimum).Minimum
                    return (($max - $min) -le 0.6)
                } finally { $font.Dispose() }
            } finally { $g.Dispose() }
        } finally { $bmp.Dispose() }
    } catch { return $false }
}

# Composed capability for one entry:
#   Preview   -- bundled file present (or system family installed)
#   Terminal  -- family resolvable by the machine (WT will honour the face)
#   Conhost   -- family resolvable AND fixed-pitch
#   Installed -- family already resolvable now
function Get-TfCapability($entry) {
    $cap = [ordered]@{
        Slug = $entry.slug; Installed = $false; Preview = $false
        Terminal = $false; Conhost = $false; FixedPitch = $false
    }
    $cap.Installed = Test-TfFamilyInstalled $entry.family
    if ($entry.bundled) {
        $path = Join-Path $script:TfRoot ('fonts\terminal\' + ($entry.file -replace '/', '\'))
        $cap.Preview = (Test-Path -LiteralPath $path)
        # PERF-001: an uninstalled bundled face is automatically Conhost=false
        # (see below: Conhost requires Installed). Do not fixed-pitch probe
        # merely to draw a row — the expensive GDI+ measurement runs only when
        # the face is installed (positive Conhost proof) or explicitly selected
        # for preview. Cached per immutable file identity for the GUI epoch.
        if ($cap.Preview -and $cap.Installed) { $cap.FixedPitch = Test-TfFileFixedPitchCached $path $entry.slug }
    } else {
        $cap.Preview = $cap.Installed
        # System-only families (Terminus, Consolas): measure the resolved face itself.
        if ($cap.Installed) { $cap.FixedPitch = Test-TfFamilyFixedPitch $entry.family }
    }
    $cap.Terminal = $cap.Installed
    # conhost only accepts a face the machine resolves AND that is fixed-pitch.
    $cap.Conhost = ($cap.Installed -and $cap.FixedPitch)
    return $cap
}

# --- private preview ----------------------------------------------------------
# Load (and cache) a bundled face process-locally. Never registers system-wide.
function Get-TfPrivateCollection([string]$slug, [string]$path) {
    if ($script:TfPrivateCollections.ContainsKey($slug)) { return $script:TfPrivateCollections[$slug] }
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $pfc = New-Object System.Drawing.Text.PrivateFontCollection
    try { $pfc.AddFontFile($path) } catch { $pfc.Dispose(); return $null }
    $script:TfPrivateCollections[$slug] = $pfc
    if ($pfc.Families.Count -gt 0) { $script:TfPrivateFamilies[$slug] = $pfc.Families[0] }
    return $pfc
}

function Get-TfPreviewFamily($entry) {
    if ($script:TfPrivateFamilies.ContainsKey($entry.slug)) { return $script:TfPrivateFamilies[$entry.slug] }
    if ($entry.bundled) {
        $path = Join-Path $script:TfRoot ('fonts\terminal\' + ($entry.file -replace '/', '\'))
        [void](Get-TfPrivateCollection $entry.slug $path)
        if ($script:TfPrivateFamilies.ContainsKey($entry.slug)) { return $script:TfPrivateFamilies[$entry.slug] }
    }
    # System family: resolve the installed face directly.
    try { return New-Object System.Drawing.FontFamily($entry.family) } catch { return $null }
}

function Get-TfRenderingHint([string]$mode) {
    switch ($mode) {
        'grayscale' { return [System.Drawing.Text.TextRenderingHint]::AntiAlias }
        'cleartype' { return [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit }
        default     { return [System.Drawing.Text.TextRenderingHint]::SingleBitPerPixelGridFit }
    }
}

# Approximate metrics for the selected face at the selected size. These describe
# the GDI+ rendering, not DirectWrite; the UI states that honestly.
# PERF-001: $knownCap reuses an already-computed row capability instead of
# redundantly running Get-TfCapability again.
function Get-TfMetrics($entry, [int]$size, $knownCap) {
    $cap = if ($null -ne $knownCap) { $knownCap } else { Get-TfCapability $entry }
    $m = [ordered]@{ Family = $entry.family; Size = $size; CellWidth = 0; LineHeight = 0; Monospace = 'SUSPECT'; Capability = $cap }
    $fam = Get-TfPreviewFamily $entry
    if (-not $fam) { return $m }
    try {
        $f = New-Object System.Drawing.Font($fam, $size, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
        try {
            $bmp = New-Object System.Drawing.Bitmap 8, 8
            try {
                $g = [System.Drawing.Graphics]::FromImage($bmp)
                try {
                    $wi = $g.MeasureString('i', $f).Width
                    $wW = $g.MeasureString('W', $f).Width
                    $m.CellWidth = [Math]::Round([Math]::Max($wi, $wW), 2)
                    $th = $g.MeasureString('Ag', $f)
                    $m.LineHeight = [Math]::Round($th.Height, 2)
                    $m.Monospace = if ([Math]::Abs($wi - $wW) -le 0.6) { 'PASS' } else { 'SUSPECT' }
                } finally { $g.Dispose() }
            } finally { $bmp.Dispose() }
        } finally { $f.Dispose() }
    } catch { }
    return $m
}

# Deterministic disposal on GUI close.
function Clear-TfPreviewResources {
    foreach ($slug in @($script:TfPrivateCollections.Keys)) {
        try { $script:TfPrivateCollections[$slug].Dispose() } catch { }
    }
    $script:TfPrivateCollections = @{}
    $script:TfPrivateFamilies = @{}
    if ($script:TfPreviewFont) { try { $script:TfPreviewFont.Dispose() } catch { }; $script:TfPreviewFont = $null }
}

# --- canonical preference -----------------------------------------------------
# READ goes through the shared PowerShell reader in common.ps1 (works without
# Node, exactly like the CLI targets). WRITE goes through the ONE node schema
# owner so the document is validated by the same code that owns the format;
# both runtimes are proven to agree by the parity fixtures in
# tools/test-terminal-fonts.js.
function Invoke-TfPreferenceCli([string[]]$cliArgs) {
    $helper = Join-Path $script:TfRoot 'tools\terminal-font-preference.js'
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & node $helper @cliArgs 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    [pscustomobject]@{ Output = ($out -join "`n").Trim(); ExitCode = $code }
}

function Get-TfPreference {
    # The shared reader (common.ps1). It throws PREFERENCE_MALFORMED-equivalent
    # on a bad document; callers already catch and log.
    return Get-TerminalFontPreference
}

function Set-TfPreference([string]$slug, [string]$family, [int]$size, [string]$mode) {
    $r = Invoke-TfPreferenceCli @('write', '--slug', $slug, '--family', $family, '--size', "$size", '--mode', $mode)
    if ($r.ExitCode -ne 0) { throw "terminal-font preference write failed: $($r.Output)" }
    return ($r.Output | ConvertFrom-Json)
}
