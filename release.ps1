# Wintage release helper: bumps @version, commits everything, pushes to main.
# Usage:  .\release.ps1 -Message "fix reddit hovercards"
#         .\release.ps1 -Message "new palette" -Bump minor
param(
    [Parameter(Mandatory = $true)][string]$Message,
    [ValidateSet('patch', 'minor', 'major')][string]$Bump = 'patch'
)

$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'wintage.user.js'
# Read/write explicitly as UTF-8 (no BOM). PS 5.1's Get-Content defaults to the
# ANSI codepage and mojibakes every non-ASCII character in the file.
$utf8 = New-Object System.Text.UTF8Encoding($false)
$content = [System.IO.File]::ReadAllText($script, $utf8)

if ($content -notmatch '// @version\s+(\d+)\.(\d+)\.(\d+)') {
    throw "Could not find a semver @version line in wintage.user.js"
}
$maj = [int]$Matches[1]; $min = [int]$Matches[2]; $pat = [int]$Matches[3]
switch ($Bump) {
    'major' { $maj++; $min = 0; $pat = 0 }
    'minor' { $min++; $pat = 0 }
    'patch' { $pat++ }
}
$new = "$maj.$min.$pat"
$content = $content -replace '(// @version\s+)\d+\.\d+\.\d+', "`${1}$new"
[System.IO.File]::WriteAllText($script, $content, $utf8)

node --check $script
if ($LASTEXITCODE -ne 0) { throw "Syntax check failed - release aborted, version line already bumped, fix and rerun" }

# node --check cannot see inside the CSS template literals - to JavaScript they
# are just strings. A stray '*/', an unbalanced brace or an off-palette colour in
# there passes --check, loads fine, and then the browser's CSS parser silently
# discards rules while recovering. That exact failure shipped once and was only
# caught by measuring computed styles on a live page, so it gates releases now.
node (Join-Path $PSScriptRoot 'tools/check-css.js')
if ($LASTEXITCODE -ne 0) { throw "CSS check failed - release aborted, version line already bumped, fix and rerun" }

# The theme switch is resolved at document-start from GM storage, with fallbacks
# that only matter when something is wrong (no GM API, a slug whose pack was
# removed, a failed write). None of those paths is exercised by opening a page in
# a healthy browser, so they get a real test instead of an assumption.
node (Join-Path $PSScriptRoot 'tools/test-theme-switch.js')
if ($LASTEXITCODE -ne 0) { throw "Theme switch test failed - release aborted, version line already bumped, fix and rerun" }

git -C $PSScriptRoot add -A
git -C $PSScriptRoot commit -m "v${new}: $Message"
git -C $PSScriptRoot push origin main
Write-Host "Released Wintage v$new - Tampermonkey clients will pick it up on their next update check." -ForegroundColor Green
