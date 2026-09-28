# Wintage Scenario Presets -- T-257 / SRC-013 (audit/6.md)
#
# A preset is desired INSTALLER UI STATE (palette + checked target keys), never
# a second installation engine. Loading a preset stages intent in the GUI; the
# existing Apply/Revert buttons remain the only mutation paths.
#
# Storage lives OUTSIDE the repo under %APPDATA%\Wintage\presets\ (one JSON file
# per preset), the same discipline as paths.json / language.txt: the checkout is
# pulled, moved and re-cloned, and a per-machine preference has no business in
# it. Tests redirect the whole root through WINTAGE_APPDATA.
#
# This module owns ONLY the preset contract: schema validation and atomic,
# lock-serialized storage. It deliberately does NOT hardcode the theme token set
# -- the caller passes the canonical tokens read from tools/theme-schema.json, so
# a snapshot is validated against the ONE authoritative token list and cannot
# become a fourth copy that drifts (the T-187 class).

$script:PresetSchemaVersion = 1
$script:PresetIdPattern = '^[a-z0-9][a-z0-9-]{0,63}$'
# The canonical six-digit hex colour contract (tools/theme-schema.js owns the
# same rule for packs). A snapshot carrying a malformed value must be isolated
# HERE, before any GUI state is mutated.
$script:PresetTokenPattern = '^#[0-9A-Fa-f]{6}$'

# Field names of an object regardless of how it was decoded: ConvertFrom-Json
# yields a PSCustomObject, while callers may hand over a hashtable. ONE helper so
# every field check reads the same surface.
function Get-PresetFieldNames($obj) {
    if ($null -eq $obj) { return @() }
    if ($obj -is [System.Collections.IDictionary]) { return @($obj.Keys | ForEach-Object { [string]$_ }) }
    return @($obj.PSObject.Properties.Name)
}

function Get-PresetField($obj, [string]$name) {
    if ($null -eq $obj) { return $null }
    # Assign via an explicit statement: a single-element array returned from an
    # `if` EXPRESSION is unrolled before the comma-wrap can protect it, which
    # turned `targets: ["windows"]` into a scalar and failed the array check.
    $value = $null
    if ($obj -is [System.Collections.IDictionary]) { $value = $obj[$name] }
    else { $value = $obj.$name }
    if ($value -is [array]) { return ,$value }
    return $value
}

function Get-PresetRoot {
    if ($env:WINTAGE_APPDATA) { return (Join-Path $env:WINTAGE_APPDATA 'presets') }
    return (Join-Path $env:APPDATA 'Wintage\presets')
}

function Get-PresetLockPath {
    if ($env:WINTAGE_APPDATA) { return (Join-Path $env:WINTAGE_APPDATA 'presets.lock') }
    return (Join-Path $env:APPDATA 'Wintage\presets.lock')
}

# A safe, stable, filesystem-independent id derived from a human name. Lower
# cased, non-alphanumerics collapsed to single hyphens, trimmed. The result must
# satisfy the id pattern; anything that cannot is refused rather than mangled
# into a surprising filename.
function New-PresetId([string]$name) {
    if ([string]::IsNullOrWhiteSpace($name)) { return $null }
    $id = $name.ToLowerInvariant()
    $id = [regex]::Replace($id, '[^a-z0-9]+', '-')
    $id = $id.Trim('-')
    if ($id.Length -gt 64) { $id = $id.Substring(0, 64).Trim('-') }
    if (-not [regex]::IsMatch($id, $script:PresetIdPattern)) { return $null }
    return $id
}

# Which preset file a given id maps to. The id is validated FIRST, so a hostile
# or malformed id (`..\..\x`, absolute path, separators) can never escape the
# preset root: it fails validation and no path is produced at all.
function Get-PresetPath([string]$id) {
    if (-not [regex]::IsMatch([string]$id, $script:PresetIdPattern)) {
        throw "preset id '$id' is unsafe: must match $($script:PresetIdPattern)"
    }
    return (Join-Path (Get-PresetRoot) ("$id.json"))
}

# Acquire the shared presets lock, mirroring common.ps1 Save-PathPreference: a
# dedicated lock file held across read -> validate -> write-temp -> move so two
# concurrent writers cannot lost-update. Returns the open FileStream (caller
# disposes) or throws.
function Enter-PresetLock {
    $lockPath = Get-PresetLockPath
    $dir = Split-Path $lockPath -Parent
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    for ($attempt = 0; $attempt -lt 100; $attempt++) {
        try {
            return [System.IO.File]::Open($lockPath,
                [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None)
        } catch [System.IO.IOException] {
            Start-Sleep -Milliseconds (10 + (Get-Random -Maximum 40))
        }
    }
    throw "could not acquire presets lock at $lockPath after 100 attempts."
}

# Validate a decoded preset object against the contract. Returns an array of
# human-readable violations (empty = valid). Pure: never throws, never writes.
# `$canonicalTokens` is the authoritative token list; a snapshot must carry the
# EXACT set, because a preset that silently drops a token would install a
# truncated palette.
function Test-PresetObject($obj, [string[]]$canonicalTokens) {
    $errors = @()
    if ($null -eq $obj) { return @('preset is empty') }
    if ($obj -isnot [System.Management.Automation.PSCustomObject] -and $obj -isnot [System.Collections.IDictionary]) {
        return @('preset root must be a JSON object')
    }
    $names = Get-PresetFieldNames $obj

    # schemaVersion: unknown future versions fail with a useful message, never
    # silently load as if they were v1.
    if ($names -notcontains 'schemaVersion') { $errors += 'missing required field: schemaVersion' }
    else {
        $sv = Get-PresetField $obj 'schemaVersion'
        if ($sv -isnot [int] -and $sv -isnot [long]) { $errors += "schemaVersion must be an integer (got '$sv')" }
        elseif ([int]$sv -ne $script:PresetSchemaVersion) {
            $errors += "unsupported schemaVersion $sv (this installer supports $($script:PresetSchemaVersion)); it was written by a newer Wintage"
        }
    }

    # id: present, safe, and matching the filename identity contract.
    if ($names -notcontains 'id') { $errors += 'missing required field: id' }
    elseif (-not [regex]::IsMatch([string](Get-PresetField $obj 'id'), $script:PresetIdPattern)) {
        $errors += "id '$(Get-PresetField $obj 'id')' is unsafe: must match $($script:PresetIdPattern)"
    }

    # name: non-empty display label.
    if ($names -notcontains 'name') { $errors += 'missing required field: name' }
    elseif ([string]::IsNullOrWhiteSpace([string](Get-PresetField $obj 'name'))) { $errors += 'name must not be empty' }

    # palette: either a pack reference or a complete custom token snapshot.
    if ($names -notcontains 'palette') { $errors += 'missing required field: palette' }
    else {
        $p = Get-PresetField $obj 'palette'
        $pnames = Get-PresetFieldNames $p
        if ($null -eq $p) { $errors += 'palette must be an object' }
        elseif ($pnames -notcontains 'type') { $errors += 'palette.type is required' }
        else {
            $ptype = [string](Get-PresetField $p 'type')
            if ($ptype -eq 'pack') {
                if ($pnames -notcontains 'slug' -or [string]::IsNullOrWhiteSpace([string](Get-PresetField $p 'slug'))) {
                    $errors += 'palette.type=pack requires a non-empty palette.slug'
                }
            } elseif ($ptype -eq 'snapshot') {
                $tk = Get-PresetField $p 'tokens'
                if ($pnames -notcontains 'tokens' -or $null -eq $tk) {
                    $errors += 'palette.type=snapshot requires palette.tokens'
                } else {
                    $tnames = Get-PresetFieldNames $tk
                    $missing = @($canonicalTokens | Where-Object { $tnames -notcontains $_ })
                    $extra = @($tnames | Where-Object { $canonicalTokens -notcontains $_ })
                    if ($missing.Count) { $errors += "palette snapshot is missing token(s): $($missing -join ',')" }
                    if ($extra.Count) { $errors += "palette snapshot carries unknown token(s): $($extra -join ',')" }
                    # CORE-005 (audit/7.md): structural completeness is not a
                    # colour. Every snapshot VALUE must be a string matching the
                    # canonical six-digit hex contract; the reason names the
                    # token and the offending value, and the COMPLETE preset is
                    # rejected before any GUI state is touched.
                    $badValues = @()
                    foreach ($tn in $tnames) {
                        $tv = Get-PresetField $tk $tn
                        if ($tv -isnot [string] -or $tv -notmatch $script:PresetTokenPattern) {
                            $badValues += "$tn='$tv'"
                        }
                    }
                    if ($badValues.Count) {
                        $errors += "palette snapshot token value(s) must be a six-digit hex colour like #A1B2C3: $($badValues -join ', ')"
                    }
                }
            } else {
                $errors += "palette.type '$ptype' is not one of pack|snapshot"
            }
        }
    }

    # targets: canonical keys only, no duplicates after case normalization.
    if ($names -contains 'targets') {
        $tlist = Get-PresetField $obj 'targets'
        if ($tlist -isnot [array]) { $errors += 'targets must be an array' }
        else {
            $seen = @{}
            foreach ($t in $tlist) {
                if ([string]::IsNullOrWhiteSpace([string]$t)) { $errors += 'targets must not contain empty entries'; continue }
                $k = ([string]$t).Trim().ToLowerInvariant()
                if ($k -ne [string]$t) { $errors += "target '$t' must be a canonical lower-case key" }
                if ($seen.ContainsKey($k)) { $errors += "duplicate target '$t'" }
                else { $seen[$k] = $true }
            }
        }
    } else {
        $errors += 'missing required field: targets'
    }

    # options: reserved for typed future settings; must be an object when present.
    if ($names -contains 'options') {
        $opt = Get-PresetField $obj 'options'
        if ($null -ne $opt -and $opt -isnot [System.Management.Automation.PSCustomObject] -and $opt -isnot [System.Collections.IDictionary]) {
            $errors += 'options must be an object'
        }
    }

    return $errors
}

# Build the canonical JSON text for a preset (UTF-8, no BOM is the writer's job).
# Keys are emitted in a stable order so a saved preset diffs cleanly and is
# human-copyable between machines.
function ConvertTo-PresetJson($preset) {
    $ordered = [ordered]@{
        schemaVersion = $script:PresetSchemaVersion
        id            = [string]$preset.id
        name          = [string]$preset.name
        description   = [string]$preset.description
        palette       = $preset.palette
        targets       = @($preset.targets)
        options       = if ($null -ne $preset.options) { $preset.options } else { [ordered]@{} }
    }
    return (($ordered | ConvertTo-Json -Depth 8) + "`n")
}

# Read + validate one preset file. Returns the decoded object or $null when the
# file is unreadable/malformed -- a corrupt preset must NEVER prevent the
# installer from opening, and one corrupt preset must never hide healthy ones,
# so the caller collects nulls and reports them rather than aborting.
function Read-PresetFile([string]$path, [string[]]$canonicalTokens) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $text = [System.IO.File]::ReadAllText($path, (New-Object System.Text.UTF8Encoding($false)))
        $obj = $text | ConvertFrom-Json
    } catch { return $null }
    $errors = Test-PresetObject $obj $canonicalTokens
    if ($errors.Count) { return $null }
    return $obj
}

# Load every valid preset from disk. Returns an object with the surviving
# presets (sorted by name) and the list of files that failed validation, so the
# GUI can report them without hiding the rest.
function Get-Presets([string[]]$canonicalTokens) {
    $root = Get-PresetRoot
    $good = @()
    $bad = @()
    if (Test-Path -LiteralPath $root) {
        foreach ($f in (Get-ChildItem -LiteralPath $root -Filter '*.json' | Sort-Object Name)) {
            $obj = Read-PresetFile $f.FullName $canonicalTokens
            if ($null -eq $obj) { $bad += $f.Name }
            else {
                # The filename is the identity; a file whose id disagrees with
                # its own name is drift and is reported, not silently trusted.
                if ($obj.id -ne [System.IO.Path]::GetFileNameWithoutExtension($f.Name)) { $bad += $f.Name; continue }
                $good += $obj
            }
        }
    }
    return [pscustomobject]@{
        Presets = @($good | Sort-Object name)
        Invalid = @($bad)
        Root    = $root
    }
}

# Persist a preset atomically under the shared lock. `Overwrite` is required to
# replace an existing id; without it a same-id save is refused so Save As cannot
# silently clobber another preset. The previous file is only replaced once the
# complete new bytes are validated and on disk (temp sibling + Move-Item).
function Save-Preset($preset, [string[]]$canonicalTokens, [switch]$Overwrite) {
    $errors = Test-PresetObject $preset $canonicalTokens
    if ($errors.Count) { throw "refusing to save an invalid preset: $($errors -join '; ')" }
    $path = Get-PresetPath $preset.id
    $root = Split-Path $path -Parent
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    $lock = Enter-PresetLock
    try {
        if ((Test-Path -LiteralPath $path) -and -not $Overwrite) {
            throw "a preset with id '$($preset.id)' already exists; pass -Overwrite to replace it"
        }
        $json = ConvertTo-PresetJson $preset
        $tmp = $path + '.wintage-tmp-' + [guid]::NewGuid().ToString('N')
        try {
            [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
            $null = [System.IO.File]::ReadAllText($tmp, (New-Object System.Text.UTF8Encoding($false))) | ConvertFrom-Json
            Move-Item -LiteralPath $tmp -Destination $path -Force
        } finally {
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        }
    } finally { $lock.Dispose() }
    return $path
}

# Remove a preset definition. Deletes ONLY the definition -- no installed
# application state, manifest entry, or repository file is touched.
function Remove-Preset([string]$id) {
    $path = Get-PresetPath $id
    $lock = Enter-PresetLock
    try {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    } finally { $lock.Dispose() }
}

# Rename a preset's display name (and, when the id changes, its backing file)
# without ever losing the original: the new file is fully written and validated
# before the old one is removed, and a failed write leaves the original in place.
# CORE-003 (audit/7.md): the shared lock covers the COMPLETE read-modify-write.
# Only pure input data (name validation, new id) is computed before locking; the
# source is read INSIDE the lock, so a concurrent writer that commits first is
# renamed with its committed content instead of being resurrected stale.
function Rename-Preset([string]$id, [string]$newName, [string[]]$canonicalTokens) {
    if ([string]::IsNullOrWhiteSpace($newName)) { throw 'a preset name must not be empty' }
    if (-not [regex]::IsMatch([string]$id, $script:PresetIdPattern)) { throw "preset id '$id' is unsafe: must match $($script:PresetIdPattern)" }
    $newId = New-PresetId $newName
    if (-not $newId) { throw "name '$newName' cannot produce a safe preset id" }
    # Deterministic synchronization seam (tests only): announce readiness, then
    # hold until the caller consumes the signal. Never set outside tests.
    if ($env:WINTAGE_TEST_PRESET_RENAME_SEAM) {
        [System.IO.File]::WriteAllText($env:WINTAGE_TEST_PRESET_RENAME_SEAM, 'ready')
        $seamDeadline = (Get-Date).AddSeconds(30)
        while ((Test-Path -LiteralPath $env:WINTAGE_TEST_PRESET_RENAME_SEAM) -and (Get-Date) -lt $seamDeadline) {
            Start-Sleep -Milliseconds 20
        }
    }
    $lock = Enter-PresetLock
    try {
        $path = Get-PresetPath $id
        if (-not (Test-Path -LiteralPath $path)) { throw "no preset with id '$id'" }
        $obj = Read-PresetFile $path $canonicalTokens
        if ($null -eq $obj) { throw "preset '$id' is invalid on disk and cannot be renamed" }
        $obj.name = $newName
        $obj.id = $newId
        $dest = Get-PresetPath $newId
        if (($newId -ne $id) -and (Test-Path -LiteralPath $dest)) {
            throw "renaming '$id' to '$newId' would collide with an existing preset"
        }
        $json = ConvertTo-PresetJson $obj
        $tmp = $dest + '.wintage-tmp-' + [guid]::NewGuid().ToString('N')
        try {
            [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
            Move-Item -LiteralPath $tmp -Destination $dest -Force
        } finally {
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        }
        if ($newId -ne $id -and (Test-Path -LiteralPath $path)) { Remove-Item -LiteralPath $path -Force }
    } finally { $lock.Dispose() }
    return $newId
}

# Build a preset object from live GUI state (palette slug or custom snapshot +
# checked target keys). Pure: reads no GUI globals, so it is unit-testable.
function New-PresetObject {
    param(
        [string]$Id,
        [string]$Name,
        [string]$Description = '',
        [ValidateSet('pack', 'snapshot')][string]$PaletteType,
        [string]$PaletteSlug = '',
        $Tokens = $null,
        [string[]]$Targets,
        $Options = $null
    )
    $palette = if ($PaletteType -eq 'pack') {
        [ordered]@{ type = 'pack'; slug = $PaletteSlug }
    } else {
        [ordered]@{ type = 'snapshot'; tokens = $Tokens }
    }
    return [pscustomobject]@{
        schemaVersion = $script:PresetSchemaVersion
        id            = $Id
        name          = $Name
        description   = $Description
        palette       = $palette
        targets       = @($Targets | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Select-Object -Unique)
        options       = if ($null -ne $Options) { $Options } else { [ordered]@{} }
    }
}
