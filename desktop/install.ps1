# Installs the Wintage look into desktop applications.
#
# Design constraint that shapes everything here: applications update themselves, and
# an update must not take the theme with it. So every target is installed into the
# USER's own profile where the app looks for extensions/config, never into the app's
# program directory -- and where a target has no such profile location (MPC-HC,
# Electron apps), the installer is written to be re-run after an update rather than
# pretending it survived one.
#
#   .\install.ps1                       # list targets and what each one can reach
#   .\install.ps1 -Target antigravity   # install one
#   .\install.ps1 -Target all
#   .\install.ps1 -Target all -WhatIf   # say what would change, touch nothing
#   .\install.ps1 -Target antigravity -Revert
#
# Anything overwritten is copied to desktop/backup/<timestamp>/ first.

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('antigravity', 'vscode', 'all')]
    [string]$Target,
    [switch]$Revert,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$out = Join-Path $here 'out'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $here "backup/$stamp"

function Say($msg, $colour = 'Gray') { Write-Host $msg -ForegroundColor $colour }

# Where each target keeps its extensions. Both are VS Code-family and read the
# identical format, which is why one built extension serves them both.
$TARGETS = @{
    antigravity = @{
        Name  = 'Antigravity IDE'
        Kind  = 'vscode-extension'
        Dir   = Join-Path $HOME '.antigravity/extensions'
        Built = Join-Path $out 'vscode/wintage-themes'
        Note  = 'Six colour themes. Lives in your profile, so an IDE update cannot remove it.'
    }
    vscode      = @{
        Name  = 'Visual Studio Code'
        Kind  = 'vscode-extension'
        Dir   = Join-Path $HOME '.vscode/extensions'
        Built = Join-Path $out 'vscode/wintage-themes'
        Note  = 'Same extension as Antigravity -- VS Code family, identical format.'
    }
}

if (-not $Target) {
    Say "Wintage desktop targets:" 'Cyan'
    foreach ($k in $TARGETS.Keys | Sort-Object) {
        $t = $TARGETS[$k]
        $present = if (Test-Path $t.Dir) { 'found' } else { 'NOT found on this machine' }
        Say ("  {0,-12} {1,-22} {2}" -f $k, $t.Name, $present)
        Say ("               {0}" -f $t.Note) 'DarkGray'
    }
    Say ""
    Say "Run:  .\install.ps1 -Target <name>   (or -Target all)" 'Cyan'
    return
}

# The built output is generated, not committed by hand -- refuse to install a stale
# or missing build rather than silently shipping last week's colours.
$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) {
    & node (Join-Path $root 'tools/build-desktop.js') --check | Out-Null
    if ($LASTEXITCODE -ne 0) {
        if (-not $Force) { throw "desktop/out is out of date with themes/*.json. Run 'node tools/build-desktop.js' first, or pass -Force to install what is already built." }
        Say "WARNING: installing a build that is out of date with themes/*.json (-Force)." 'Yellow'
    }
}
elseif (-not $Force) {
    Say "node not found - cannot verify the build is current. Installing what is in desktop/out as-is." 'Yellow'
}

$names = if ($Target -eq 'all') { $TARGETS.Keys } else { @($Target) }

foreach ($name in $names) {
    $t = $TARGETS[$name]

    if (-not (Test-Path $t.Dir)) {
        Say "$($t.Name): extensions directory not found ($($t.Dir)) - skipped." 'DarkYellow'
        continue
    }

    $dest = Join-Path $t.Dir 'wintage-themes'

    if ($Revert) {
        if (Test-Path $dest) {
            if ($PSCmdlet.ShouldProcess($dest, 'Remove installed Wintage themes')) {
                Remove-Item $dest -Recurse -Force
                Say "$($t.Name): removed $dest" 'Green'
            }
        }
        else { Say "$($t.Name): nothing installed, nothing to revert." }
        continue
    }

    if (-not (Test-Path $t.Built)) { throw "Built output missing: $($t.Built). Run 'node tools/build-desktop.js'." }

    # Replacing a directory wholesale is how a stale theme file from a previous
    # version survives forever, so the old one is removed - but only after it has
    # been copied out, because "the installer ate my hand-edited theme" is exactly
    # the failure a backup exists for.
    if (Test-Path $dest) {
        if ($PSCmdlet.ShouldProcess($dest, "Back up to $backupRoot and replace")) {
            $bak = Join-Path $backupRoot $name
            New-Item -ItemType Directory -Force -Path $bak | Out-Null
            Copy-Item $dest -Destination $bak -Recurse -Force
            Remove-Item $dest -Recurse -Force
            Say "$($t.Name): previous install backed up to $bak" 'DarkGray'
        }
    }

    if ($PSCmdlet.ShouldProcess($dest, 'Install Wintage themes')) {
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Copy-Item (Join-Path $t.Built '*') -Destination $dest -Recurse -Force
        $count = (Get-ChildItem (Join-Path $dest 'themes') -Filter '*.json').Count
        Say "$($t.Name): installed $count themes -> $dest" 'Green'
        Say "  Pick one: Ctrl+K Ctrl+T, look for 'Wintage ...'. Restart the app if it does not appear." 'DarkGray'
    }
}
