# Owned-field revert regression suite (T-189, P1#14/#15).
#
# Revert must restore ONLY the fields Wintage owns, merged into the CURRENT
# config, so unrelated user edits made after Apply survive. These fixtures
# exercise OBS, Total Commander and Obsidian with real apply -> user-edit ->
# revert cycles; everything lives under temp dirs.
#
#   .\tools\test-ownership.ps1

[CmdletBinding()]
param([switch]$List)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$pass = 0; $fail = 0
$utf8 = New-Object System.Text.UTF8Encoding($false)

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

function Run-TestChild([string]$exe, [string[]]$argsList) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & $exe @argsList 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    [pscustomobject]@{ Out = @($out); Code = $code }
}

if ($List) {
    Write-Host "test-ownership.ps1:"
    Write-Host "  1. OBS unrelated post-Apply edit survives Revert"
    Write-Host "  2. TotalCmd unrelated post-Apply edit survives Revert"
    Write-Host "  3. Obsidian unrelated post-Apply edit survives Revert"
    Write-Host "  4. Obsidian second-vault failure does not advance/remove manifest"
    exit 0
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-ownership-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

# ---- Test 1: OBS ownership revert ----
$obsConfig = Join-Path $testRoot 'obs'
New-Item -ItemType Directory -Path $obsConfig -Force | Out-Null
$userIni = Join-Path $obsConfig 'user.ini'
$iniOrig = "[Appearance]`r`nTheme=System`r`nLanguage=en-US`r`n[Output]`r`nMode=Advanced`r`n"
[System.IO.File]::WriteAllText($userIni, $iniOrig, $utf8)
$obsTheme = Join-Path $root 'desktop\out\obs\goldendefault\Wintage.ovt'
$r = Run-TestChild node @((Join-Path $root 'tools\install-obs.js'), '--config', $obsConfig, '--theme', $obsTheme, '--palette', 'goldendefault')
check 'OBS apply exits 0' ($r.Code -eq 0)
$applied = [System.IO.File]::ReadAllText($userIni, $utf8)
check 'OBS apply sets the Theme key' ($applied -match 'Theme=com\.wintage\.OBS')
# User changes unrelated settings after Apply.
$current = [System.IO.File]::ReadAllText($userIni, $utf8)
$current = $current -replace 'Mode=Advanced', "Mode=Simple`r`n[Video]`r`nRenderer=direct3d11"
[System.IO.File]::WriteAllText($userIni, $current, $utf8)
$r = Run-TestChild node @((Join-Path $root 'tools\install-obs.js'), '--config', $obsConfig, '--revert')
check 'OBS ownership revert exits 0' ($r.Code -eq 0)
$after = [System.IO.File]::ReadAllText($userIni, $utf8)
check 'OBS revert restores the owned Theme key' ($after -match '(?m)^Theme=System\r?$')
check 'OBS revert PRESERVES the unrelated Mode edit' ($after -match '(?m)^Mode=Simple\r?$')
check 'OBS revert PRESERVES the unrelated Video section' ($after -match '(?m)^Renderer=direct3d11\r?$')
check 'OBS revert removes the Wintage theme file' (-not (Test-Path (Join-Path $obsConfig 'themes\Wintage.ovt')))
check 'OBS revert removes the marker' (-not (Test-Path (Join-Path $obsConfig '.wintage-obs-palette')))

# ---- Test 2: TotalCmd ownership revert ----
$tcRoot = Join-Path $testRoot 'totalcmd'
New-Item -ItemType Directory -Path $tcRoot -Force | Out-Null
$tcIni = Join-Path $tcRoot 'wincmd.ini'
$tcTheme = Join-Path $tcRoot 'Current.ini'
$tcEntry = "[Colors]`r`nRedirectSection=`"%COMMANDER_PATH%\Current.ini`"`r`n"
$tcOrig = @"
[ColorTheme]
EnableColorFilters=1
[ColorsDark]
ColorFilter1=>Age rule
ColorFilter1Color=8414720
ColorFilter2=>Keep custom
ColorFilter2Color=12632256
[Colors]
ColorFilter1=>Age rule
ColorFilter1Color=8414720
ColorFilter2=>Keep custom
ColorFilter2Color=12632256
[Searches]
Age rule_SearchFlags=0|000002000020|||2|0|||||0000|
Keep custom_SearchFlags=0|000002000020||||||||22220|0000|
"@
[System.IO.File]::WriteAllText($tcIni, $tcEntry, $utf8)
[System.IO.File]::WriteAllText($tcTheme, $tcOrig, $utf8)
$r = Run-TestChild powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'desktop\install.ps1'), '-Target', 'totalcmd', '-TotalCmdIni', $tcIni, '-Palette', 'goldendefault')
check 'TotalCmd apply exits 0' ($r.Code -eq 0)
# User edits unrelated things after Apply: a layout flag + a custom color key
# that Wintage never owned.
$current = [System.IO.File]::ReadAllText($tcTheme, $utf8)
$current = $current + "[Layout]`r`nShowToolbar=1`r`n[Colors]`r`nCustomColor=123456`r`n"
[System.IO.File]::WriteAllText($tcTheme, $current, $utf8)
$r = Run-TestChild powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'desktop\install.ps1'), '-Target', 'totalcmd', '-TotalCmdIni', $tcIni, '-Revert')
check 'TotalCmd ownership revert exits 0' ($r.Code -eq 0)
$after = [System.IO.File]::ReadAllText($tcTheme, $utf8)
check 'TotalCmd revert removes the owned BackColor (absent originally)' ($after -notmatch '(?m)^BackColor=')
check 'TotalCmd revert restores the recent-filter colour' ($after -match '(?m)^ColorFilter1Color=8414720\r?$')
check 'TotalCmd revert PRESERVES the unrelated ShowToolbar edit' ($after -match '(?m)^ShowToolbar=1\r?$')
check 'TotalCmd revert PRESERVES the unrelated CustomColor edit' ($after -match '(?m)^CustomColor=123456\r?$')

# ---- Tests 3+4: Obsidian ----
$fakeAppData = Join-Path $testRoot 'appdata'
$vault1 = Join-Path $testRoot 'vault1'
$vault2 = Join-Path $testRoot 'vault2'
New-Item -ItemType Directory -Path (Join-Path $fakeAppData 'obsidian'), (Join-Path $vault1 '.obsidian\themes'), (Join-Path $vault2 '.obsidian\themes'), (Join-Path $fakeAppData 'Wintage') -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $fakeAppData 'obsidian\obsidian.json'), (@{ vaults = @{ v1 = @{ path = $vault1 }; v2 = @{ path = $vault2 } } } | ConvertTo-Json -Depth 4), $utf8)
$app1 = Join-Path $vault1 '.obsidian\appearance.json'
$app2 = Join-Path $vault2 '.obsidian\appearance.json'
[System.IO.File]::WriteAllText($app1, '{"baseFontSize":16,"cssTheme":"Default"}', $utf8)
[System.IO.File]::WriteAllText($app2, '{"cssTheme":"Default"}', $utf8)

$prevApp = $env:APPDATA
$prevWin = $env:WINTAGE_APPDATA
$env:APPDATA = $fakeAppData
$env:WINTAGE_APPDATA = Join-Path $fakeAppData 'Wintage'
try {
    # Test 3: ownership revert.
    $r = Run-TestChild powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'desktop\install.ps1'), '-Target', 'obsidian', '-Palette', 'goldendefault')
    check 'Obsidian apply exits 0' ($r.Code -eq 0)
    $m = Get-Content (Join-Path $fakeAppData 'Wintage\installed.json') -Raw | ConvertFrom-Json
    check 'Obsidian apply advances the manifest' ([bool]$m.obsidian)
    # User edits appearance.json after Apply (unrelated key).
    $cur = (Get-Content $app1 -Raw | ConvertFrom-Json)
    $cur | Add-Member -NotePropertyName nativeMenus -NotePropertyValue $true -Force
    [System.IO.File]::WriteAllText($app1, ($cur | ConvertTo-Json -Depth 6), $utf8)
    $r = Run-TestChild powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'desktop\install.ps1'), '-Target', 'obsidian', '-Revert')
    check 'Obsidian revert exits 0' ($r.Code -eq 0)
    $after = Get-Content $app1 -Raw | ConvertFrom-Json
    check 'Obsidian revert restores the owned cssTheme' ($after.cssTheme -eq 'Default')
    check 'Obsidian revert PRESERVES the unrelated nativeMenus edit' ($after.nativeMenus -eq $true)
    check 'Obsidian revert removes the Wintage themes' (-not (Get-ChildItem (Join-Path $vault1 '.obsidian\themes') -Directory -Filter 'Wintage *' -ErrorAction SilentlyContinue))
    $mAfter = Get-Content (Join-Path $fakeAppData 'Wintage\installed.json') -Raw | ConvertFrom-Json
    check 'Obsidian revert removes the manifest entry' (-not $mAfter.obsidian)

    # Test 4: second-vault failure must not advance OR remove the manifest.
    # 4a: apply with a broken vault2 must not advance the manifest.
    Remove-Item (Join-Path $vault2 '.obsidian') -Recurse -Force
    [System.IO.File]::WriteAllText((Join-Path $vault2 '.obsidian'), 'not a directory', $utf8)
    $r = Run-TestChild powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'desktop\install.ps1'), '-Target', 'obsidian', '-Palette', 'goldendefault')
    check 'Obsidian vault-2 failure exits NONZERO' ($r.Code -ne 0)
    $mBroken = if (Test-Path (Join-Path $fakeAppData 'Wintage\installed.json')) { Get-Content (Join-Path $fakeAppData 'Wintage\installed.json') -Raw | ConvertFrom-Json } else { @{} }
    check 'Obsidian vault-2 failure does NOT advance the manifest' (-not $mBroken.obsidian)

    # 4b: revert with a broken vault2 must NOT remove the manifest for vault1.
    # Make vault2's appearance.json CORRUPT so its revert step throws after
    # vault1 has already reverted - the manifest must survive.
    Remove-Item (Join-Path $vault2 '.obsidian') -Force
    New-Item -ItemType Directory -Path (Join-Path $vault2 '.obsidian\themes') -Force | Out-Null
    [System.IO.File]::WriteAllText($app2, '{"cssTheme":"Default"}', $utf8)
    $r = Run-TestChild powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'desktop\install.ps1'), '-Target', 'obsidian', '-Palette', 'goldendefault')
    check 'Obsidian re-apply with healthy vaults exits 0' ($r.Code -eq 0)
    [System.IO.File]::WriteAllText($app2, '{ this is broken', $utf8)
    $r = Run-TestChild powershell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'desktop\install.ps1'), '-Target', 'obsidian', '-Revert')
    check 'Obsidian revert with a broken vault exits NONZERO' ($r.Code -ne 0)
    $mRevert = Get-Content (Join-Path $fakeAppData 'Wintage\installed.json') -Raw | ConvertFrom-Json
    check 'Obsidian revert with a broken vault KEEPS the manifest entry' ([bool]$mRevert.obsidian)
} finally {
    $env:APPDATA = $prevApp
    $env:WINTAGE_APPDATA = $prevWin
}

# ---- Summary ----
Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
Remove-Item $testRoot -Recurse -Force -ErrorAction SilentlyContinue
exit $fail
