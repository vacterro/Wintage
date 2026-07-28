# Re-applies the palettes in themes/*.json to a Wintage script.
#
# The problem this solves: Tampermonkey re-downloads wintage.user.js on every
# update, so a palette edited into the installed copy by hand disappears the next
# time upstream ships. The packs live outside the script for exactly that reason —
# after an upgrade you re-run this and your themes are back, on the NEW version.
#
#   .\install-themes.ps1                     # patch the copy in this repo
#   .\install-themes.ps1 -Path C:\tmp\w.js   # patch some other copy
#   .\install-themes.ps1 -Latest             # fetch the current upstream release,
#                                            # apply the packs, write it next door
#   .\install-themes.ps1 -Check              # report drift, change nothing
#
# With -Latest the result is written to wintage.themed.user.js and NOT installed
# anywhere: installing means pasting it into the Tampermonkey editor, which is a
# thing only you can do. Overwriting your live script from a shell would also
# silently lose any other local edits you had made to it.

param(
    [string]$Path,
    [switch]$Latest,
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$utf8 = New-Object System.Text.UTF8Encoding($false)

$node = (Get-Command node -ErrorAction SilentlyContinue)
if (-not $node) {
    throw "node was not found on PATH. The generator is a Node script (tools/apply-themes.js); install Node.js, or run that file with any JS runtime you do have."
}

$upstream = 'https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js'

if ($Latest) {
    if ($Path) { throw "-Latest and -Path are mutually exclusive: one fetches the upstream script, the other patches a file you name." }
    $Path = Join-Path $here 'wintage.themed.user.js'
    Write-Host "Fetching $upstream ..." -ForegroundColor Cyan
    $resp = Invoke-WebRequest -Uri $upstream -UseBasicParsing
    [System.IO.File]::WriteAllText($Path, $resp.Content, $utf8)
    $ver = if ($resp.Content -match '// @version\s+(\d+\.\d+\.\d+)') { $Matches[1] } else { 'unknown' }
    Write-Host "Fetched upstream v$ver -> $(Split-Path $Path -Leaf)" -ForegroundColor Cyan
}
elseif (-not $Path) {
    $Path = Join-Path $here 'wintage.user.js'
}

if (-not (Test-Path $Path)) { throw "Target not found: $Path" }

$generator = Join-Path $here 'tools/apply-themes.js'
if (-not (Test-Path $generator)) { throw "Generator missing: $generator" }

if ($Check) {
    node $generator $Path --check
    if ($LASTEXITCODE -ne 0) { exit 1 }
    exit 0
}

node $generator $Path
if ($LASTEXITCODE -ne 0) { throw "Applying the theme packs failed - target left untouched." }

# A palette that produces a file the browser cannot parse is worse than no palette,
# so the result is syntax-checked before it is called done.
node --check $Path
if ($LASTEXITCODE -ne 0) { throw "The patched file does not parse - do not install it. This is a bug in a theme pack or in the generator." }

if ($Latest) {
    Write-Host ""
    Write-Host "Done. Open the Tampermonkey dashboard, edit the Wintage script, and paste in:" -ForegroundColor Green
    Write-Host "  $Path" -ForegroundColor Green
    Write-Host "Then pick a theme from the Tampermonkey menu on any page." -ForegroundColor Green
}
else {
    Write-Host "Done: themes applied to $(Split-Path $Path -Leaf)." -ForegroundColor Green
}
