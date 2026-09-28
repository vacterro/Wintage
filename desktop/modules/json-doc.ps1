# W2-005 (SRC-018:R011): ONE strict reader for the user-owned JSON documents
# that TWO writers read-modify-write (paths.json: the CLI Save-PathPreference and
# the GUI Save-CustomPaths). It exists because the two writers had DIVERGENT
# failure policy on the same file:
#
#   CLI  common.ps1 Save-PathPreference: `try { parse } catch { }` -> empty object
#   GUI  WintageInstaller.ps1 Save-CustomPaths: same, explicit "nothing worth
#        preserving", then writes only its own keys
#
# Both then atomically REPLACED the original. Atomic replacement prevents a
# torn write; it does not make it safe to overwrite a value that could not be
# read. A transient or hand-edited corruption therefore destroyed every
# remembered location and every unknown forward-compatible key on the next
# unrelated save -- the very evidence needed to diagnose the file.
#
# The distinction that fixes it is exactly three states:
#   absent                     -> Exists=$false, Ok=$true   initialize normally
#   present AND a JSON object  -> Exists=$true,  Ok=$true   merge, preserve keys
#   present but not that       -> Exists=$true,  Ok=$false  FAIL CLOSED
#
# "Not that" is deliberately strict. ConvertFrom-Json accepts a bare string, a
# number, a boolean, `null` and an array as valid JSON; none of them is a
# document this code may merge into and rewrite. Treating them as "empty" is how
# a scalar paths.json would still be silently replaced by a one-key object.
function Read-OwnedJsonDocument([string]$Path) {
    $invalid = {
        param($reason)
        [pscustomobject]@{ Exists = $true; Ok = $false; Value = $null; Reason = $reason }
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Exists = $false; Ok = $true; Value = $null; Reason = $null }
    }
    $raw = $null
    try {
        # Same read contract as every other hand-edited file in this project: an
        # explicit UTF-8 no-BOM read with any leftover mark stripped, because
        # ConvertFrom-Json throws on a BOM and a checkout/write elsewhere has put
        # one here before.
        $raw = [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding($false))) -replace '^\uFEFF', ''
    } catch {
        return (& $invalid "$Path is unreadable: $($_.Exception.Message)")
    }
    try {
        $value = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return (& $invalid "$Path is not valid JSON: $($_.Exception.Message)")
    }
    if ($null -eq $value) {
        return (& $invalid "$Path is valid JSON but not an object (got null; expected {}).")
    }
    if ($value -isnot [System.Management.Automation.PSCustomObject]) {
        return (& $invalid "$Path is valid JSON but not an object (got $($value.GetType().Name); expected {}).")
    }
    return [pscustomobject]@{ Exists = $true; Ok = $true; Value = $value; Reason = $null }
}

# The ONE refusal sentence both writers throw, so the operator sees the same
# contract and the same guarantee (bytes preserved) regardless of which surface
# tried to save.
function Format-OwnedJsonRefusal([string]$Label, $Document) {
    return "W2-005: $Label is present but could not be read; refusing to overwrite it. " +
        "The original bytes are preserved exactly. $($Document.Reason)"
}

# ─── Canonical terminal typography preference (T-283 / SRC-026) ──────────────
# ONE schema, TWO runtimes. The Node helper (tools/terminal-font-preference.js)
# owns the WRITE side and the tests/GUI use it; THIS reader is the shared
# PowerShell side that conhost, Windows Terminal, health, Reapply and the GUI
# all use, so the installer keeps working on a machine WITHOUT Node (routing the
# read through a `node` child would have added a hard runtime dependency).
# tools/test-terminal-fonts.js proves the two implementations agree over shared
# fixtures (the parity group), so the schema cannot drift between them.
#
# This file is dot-sourced by BOTH common.ps1 (CLI) and WintageInstaller.ps1
# (GUI), which is exactly why it lives here and not in common.ps1.
$script:TfPreferenceSchema = 1
$script:TfPreferenceSizeMin = 7
$script:TfPreferenceSizeMax = 24
$script:TfPreferenceModes = @('aliased', 'grayscale', 'cleartype')

function Get-TerminalFontPreferencePath {
    $appData = if ($env:WINTAGE_APPDATA) { $env:WINTAGE_APPDATA } else { Join-Path $env:APPDATA 'Wintage' }
    Join-Path $appData 'terminal-font.json'
}

function Get-TerminalFontPreference {
    $file = Get-TerminalFontPreferencePath
    $default = [pscustomobject]@{
        schema = $script:TfPreferenceSchema
        fontSlug = 'terminus-ttf'
        family = 'Terminus (TTF) for Windows'
        size = 12
        renderingMode = 'aliased'
        source = 'default'
        file = $file
    }
    if (-not (Test-Path -LiteralPath $file)) { return $default }

    $raw = $null
    try { $raw = ([System.IO.File]::ReadAllText($file, (New-Object System.Text.UTF8Encoding($false)))) -replace '^\uFEFF', '' } catch { $raw = $null }
    $doc = $null
    try { $doc = $raw | ConvertFrom-Json } catch { $doc = $null }

    $problems = @()
    if ($null -eq $doc) {
        $problems += 'document is not valid JSON'
    } else {
        if ([int]$doc.schema -ne $script:TfPreferenceSchema) { $problems += "schema must be $script:TfPreferenceSchema" }
        if ([string]::IsNullOrWhiteSpace([string]$doc.fontSlug)) { $problems += 'fontSlug must be a non-empty string' }
        if ([string]::IsNullOrWhiteSpace([string]$doc.family)) { $problems += 'family must be a non-empty string' }
        $sizeOk = $false
        $parsedSize = 0
        if ([int]::TryParse($doc.size, [ref]$parsedSize)) {
            $sizeOk = ($parsedSize -ge $script:TfPreferenceSizeMin -and $parsedSize -le $script:TfPreferenceSizeMax)
        }
        if (-not $sizeOk) { $problems += "size must be an integer in $script:TfPreferenceSizeMin..$script:TfPreferenceSizeMax" }
        if ($script:TfPreferenceModes -notcontains [string]$doc.renderingMode) { $problems += "renderingMode must be one of $($script:TfPreferenceModes -join ', ')" }
    }
    if ($problems.Count) {
        throw "terminal-font.json is invalid ($($problems -join '; ')) at $file; refusing to overwrite it with a default."
    }
    return [pscustomobject]@{
        schema = $script:TfPreferenceSchema
        fontSlug = [string]$doc.fontSlug
        family = [string]$doc.family
        size = [int]$doc.size
        renderingMode = [string]$doc.renderingMode
        source = 'file'
        file = $file
    }
}
