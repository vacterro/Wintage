# test-bd-architecture.ps1 -- T-413 architecture gate.
#
# Wintage ships the BetterDiscord THEME target only. Standalone BetterDiscord
# plugins live in https://github.com/vacterro/BetterDiscord_vac34_plugins and
# must never be copied, installed or state-recorded by this repository.
#
# Red conditions:
#   1. any *.plugin.js payload under desktop\targets\betterdiscord
#   2. a duplicate plugin distribution directory at the repo root
#   3. an active source reference to the removed plugin manager
#      (variables, functions, or installer writes into BetterDiscord\plugins /
#      BetterDiscord\data\stable\plugins.json)
#   4. the canonical repository URL missing from the installer page or READMEs
#   5. the BetterDiscord THEME target (template.css) missing
#
# Active scope only: desktop\, tools\, tests\, README.md, desktop\README.md,
# package.json. Historical records (.saipen\, CHANGELOG.md, docs archives) are
# out of scope by design.
#
#   .\tools\test-bd-architecture.ps1             # all checks
#   .\tools\test-bd-architecture.ps1 -List       # list checks
#   .\tools\test-bd-architecture.ps1 -RedControl # prove the gate can fail

param(
    [switch]$List,
    [switch]$RedControl
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$utf8 = New-Object System.Text.UTF8Encoding($false)
$pass = 0; $fail = 0
$failedLabels = @()
$self = $PSCommandPath

# Forbidden tokens are assembled at runtime so this gate's own source never
# matches its own scan.
$bs = [char]92
$forbidden = @(
    ('bdPlugins' + 'SourceDir'),
    ('bdPlugins' + 'InstallDir'),
    ('bdPlugins' + 'JsonPath'),
    ('Get-BdPlugins' + 'JsonPaths'),
    ('Get-BdSource' + 'PluginNames'),
    ('Get-BdPlugin' + 'Description'),
    ('Load-Bd' + 'Plugins'),
    ('Say-Bd' + 'Log'),
    ('updated_' + 'discord_plugins'),
    ('BetterDiscord' + $bs + 'plugins'),
    ('BetterDiscord' + $bs + 'data' + $bs + 'stable' + $bs + 'plugins.json')
)

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++; $script:failedLabels += $label }
}

if ($List) {
    Write-Host "test-bd-architecture.ps1 (T-413 BetterDiscord delegation gate):"
    Write-Host "  1. no *.plugin.js payload under desktop\targets\betterdiscord"
    Write-Host "  2. no duplicate plugin distribution directory at the repo root"
    Write-Host "  3. no active source reference to the removed plugin manager"
    Write-Host "  4. canonical repository URL present in installer page and READMEs"
    Write-Host "  5. BetterDiscord THEME target template.css still present"
    Write-Host "  RED control: a reintroduced payload turns check 1 red"
    exit 0
}

function Get-PluginPayloads {
    $bdRoot = Join-Path $root ('desktop' + $bs + 'targets' + $bs + 'betterdiscord')
    if (-not (Test-Path $bdRoot)) { return @() }
    @(Get-ChildItem -Path $bdRoot -Recurse -File -Filter '*.plugin.js' -ErrorAction Stop)
}

function Get-ForbiddenHits {
    $targets = @()
    foreach ($rel in @('desktop', 'tools', 'tests')) {
        $p = Join-Path $root $rel
        if (Test-Path $p) { $targets += Get-ChildItem -Path $p -Recurse -File -ErrorAction Stop }
    }
    foreach ($rel in @('README.md', ('desktop' + $bs + 'README.md'), 'package.json')) {
        $p = Join-Path $root $rel
        if (Test-Path $p) { $targets += Get-Item $p }
    }
    $hits = @()
    foreach ($f in $targets) {
        if ($f.FullName -eq $self) { continue }
        if ($f.Extension -notin @('.ps1', '.js', '.json', '.md', '.css', '.txt')) { continue }
        $text = [System.IO.File]::ReadAllText($f.FullName)
        foreach ($token in $forbidden) {
            if ($text.Contains($token)) {
                $hits += ('{0} :: {1}' -f $f.FullName.Substring($root.Length + 1), $token)
            }
        }
    }
    return $hits
}

# ---- 1: no standalone plugin payload inside the active tree -----------------
check '1. no *.plugin.js payload under desktop\targets\betterdiscord' ((Get-PluginPayloads).Count -eq 0)

# ---- 2: no duplicate distribution directory ---------------------------------
$dupDir = Join-Path $root ('updated_' + 'discord_plugins')
check '2. no duplicate plugin distribution directory at the repo root' (-not (Test-Path $dupDir))

# ---- 3: no active reference to the removed plugin manager -------------------
$hits = Get-ForbiddenHits
check '3. no active source reference to the removed plugin manager' ($hits.Count -eq 0)
if ($hits.Count -gt 0) { $hits | ForEach-Object { Write-Host "  HIT: $_" -ForegroundColor Red } }

# ---- 4: canonical URL delegation present ------------------------------------
$canonical = 'https://github.com/vacterro/BetterDiscord_vac34_plugins'
$installerPath = Join-Path $root ('desktop' + $bs + 'WintageInstaller.ps1')
$installerText = [System.IO.File]::ReadAllText($installerPath)
check '4a. installer BD tab links the canonical plugin repository' ($installerText.Contains($canonical))
foreach ($rel in @('README.md', ('desktop' + $bs + 'README.md'))) {
    $text = [System.IO.File]::ReadAllText((Join-Path $root $rel))
    check ("4b. {0} names the canonical plugin repository" -f $rel) ($text.Contains($canonical))
}

# ---- 5: the THEME target that must keep working ------------------------------
$template = Join-Path $root ('desktop' + $bs + 'targets' + $bs + 'betterdiscord' + $bs + 'template.css')
check '5. BetterDiscord THEME target template.css still present' (Test-Path $template)

if ($RedControl) {
    # The red control re-introduces one payload file, proves check 1 goes red,
    # then removes it again. Nothing else in the tree moves.
    $dir = Join-Path $root ('desktop' + $bs + 'targets' + $bs + 'betterdiscord' + $bs + 'plugins')
    $probe = Join-Path $dir 'RedControl.probe.plugin.js'
    $createdDir = $false
    try {
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null; $createdDir = $true }
        [System.IO.File]::WriteAllText($probe, '// red control probe', $utf8)
        $red = (Get-PluginPayloads).Count -gt 0
        check 'RED control: a reintroduced payload turns check 1 red' $red
    } finally {
        if (Test-Path $probe) { Remove-Item $probe -Force }
        if ($createdDir -and (Test-Path $dir) -and -not (Get-ChildItem $dir -Force)) { Remove-Item $dir -Force }
    }
    # Re-run check 1 after cleanup: the tree must be green again.
    check 'RED control cleanup: payload gate is green again' ((Get-PluginPayloads).Count -eq 0)
}

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) { $failedLabels | ForEach-Object { Write-Host "  FAILED: $_" -ForegroundColor Red } }
if ($fail -gt 0) { exit 1 }
exit 0
