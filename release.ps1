# Wintage release helper: bumps @version, commits everything, pushes to main.
# Usage:  .\release.ps1 -Message "fix reddit hovercards"
#         .\release.ps1 -Message "new palette" -Bump minor
param(
    [Parameter(Mandatory = $true)][string]$Message,
    [ValidateSet('patch', 'minor', 'major')][string]$Bump = 'patch'
)

$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'wintage.user.js'
$content = Get-Content $script -Raw

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
[System.IO.File]::WriteAllText($script, $content)

node --check $script
if ($LASTEXITCODE -ne 0) { throw "Syntax check failed - release aborted, version line already bumped, fix and rerun" }

git -C $PSScriptRoot add -A
git -C $PSScriptRoot commit -m "v${new}: $Message"
git -C $PSScriptRoot push origin main
Write-Host "Released Wintage v$new - Tampermonkey clients will pick it up on their next update check." -ForegroundColor Green
