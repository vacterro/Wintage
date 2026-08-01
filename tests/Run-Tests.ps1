$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path $PSScriptRoot -Parent
$script:errors = 0

function Assert-True($condition, $message) {
    if (-not $condition) {
        Write-Host "[FAIL] $message" -ForegroundColor Red
        $script:errors++
    } else {
        Write-Host "[PASS] $message" -ForegroundColor Green
    }
}

Write-Host "
--- Testing Palette Consistency ---" -ForegroundColor Cyan
$golden = Get-Content "$root\themes\golden.json" -Raw | ConvertFrom-Json
$goldenKeys = $golden.tokens.PSObject.Properties.Name | Sort-Object

foreach ($file in Get-ChildItem "$root\themes\*.json") {
    $theme = Get-Content $file.FullName -Raw | ConvertFrom-Json
    $themeKeys = $theme.tokens.PSObject.Properties.Name | Sort-Object
    
    $missing = $goldenKeys | Where-Object { $_ -notin $themeKeys }
    $extra = $themeKeys | Where-Object { $_ -notin $goldenKeys }
    
    Assert-True (@($missing).Count -eq 0) "$($file.Name) has all required token keys"
    if (@($missing).Count -gt 0) { Write-Host "       Missing: $($missing -join ', ')" -ForegroundColor Red }
    
    Assert-True (@($extra).Count -eq 0) "$($file.Name) has no undocumented extra keys"
    if (@($extra).Count -gt 0) { Write-Host "       Extra: $($extra -join ', ')" -ForegroundColor Red }
}

Write-Host "
--- Testing CLI Targets Consistency ---" -ForegroundColor Cyan
$installCode = Get-Content "$root\desktop\install.ps1" -Raw

# Extract ValidateSet
$validateSetMatch = [regex]::Match($installCode, '\[ValidateSet\((.*?)\)\]')
if (-not $validateSetMatch.Success) {
    Assert-True $false "Could not parse ValidateSet in install.ps1"
} else {
    $validateTokens = $validateSetMatch.Groups[1].Value -replace "'", "" -replace " ", ""
    $validateTargets = $validateTokens -split "," | Where-Object { $_ -ne 'all' } | Sort-Object
    
    # Extract $TARGETS keys (handles quoted or unquoted keys)
    $targetsMatches = [regex]::Matches($installCode, "(?:'|"")?([a-z0-9\-]+)(?:'|"")?\s*=\s*@{?
\s+(Dir|Name)")
    $hashTargets = @()
    foreach ($m in $targetsMatches) { $hashTargets += $m.Groups[1].Value }
    
    # Extract $ELECTRON keys
    $regex = '(?s)\$ELECTRON\s*=\s*@\{(.*?)\n\s*\}'
    $electronMatches = [regex]::Matches($installCode, $regex)
    if ($electronMatches.Count -gt 0) {
        $eBlock = $electronMatches[0].Groups[1].Value
        $eKeysMatches = [regex]::Matches($eBlock, "(?:'|"")?([a-z0-9\-]+)(?:'|"")?\s*=\s*@{")
        foreach ($m in $eKeysMatches) { $hashTargets += $m.Groups[1].Value }
    }

    # Add hardcoded custom handlers
    $hardcodedMatches = [regex]::Matches($installCode, 'if \(\$name -eq ''([a-z0-9\-]+)''\)')
    $hardcoded = @()
    foreach ($m in $hardcodedMatches) { $hardcoded += $m.Groups[1].Value }
    
    $implementedTargets = @($hashTargets + $hardcoded) | Sort-Object -Unique

    $missingImpl = $validateTargets | Where-Object { $_ -notin $implementedTargets }
    $missingVal = $implementedTargets | Where-Object { $_ -notin $validateTargets }

    Assert-True (@($missingImpl).Count -eq 0) "All ValidateSet targets have implementation logic"
    if (@($missingImpl).Count -gt 0) { Write-Host "       Missing impl for: $($missingImpl -join ', ')" -ForegroundColor Red }

    Assert-True (@($missingVal).Count -eq 0) "All implemented targets are exposed in ValidateSet"
    if (@($missingVal).Count -gt 0) { Write-Host "       Missing from ValidateSet: $($missingVal -join ', ')" -ForegroundColor Red }
}

Write-Host "
--- Testing Script Syntax ---" -ForegroundColor Cyan
$parseErrors = $null
foreach ($script in @("$root\desktop\install.ps1", "$root\desktop\WintageInstaller.ps1", "$root\tools\install-browsers.ps1")) {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$null, [ref]$parseErrors)
    Assert-True ($parseErrors.Count -eq 0) "$($script | Split-Path -Leaf) parses with zero syntax errors"
    if ($parseErrors.Count -gt 0) {
        foreach ($e in $parseErrors) { Write-Host "       Line $($e.Extent.StartLineNumber): $($e.Message)" -ForegroundColor Red }
    }
}

Write-Host "
--- Testing -WhatIf Isolation ---" -ForegroundColor Cyan
$whatIfRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-whatif-" + [guid]::NewGuid().ToString('N'))
$smartVac = Join-Path $whatIfRoot 'smartvac'
$wildRift = Join-Path $whatIfRoot 'wildrift'
try {
    New-Item -ItemType Directory -Path $smartVac, $wildRift -Force | Out-Null
    $smartFile = Join-Path $smartVac '_SMART_VAC_CLEANER.py'
    $wildFile = Join-Path $wildRift 'theme.py'
    $smartOriginal = "WIN95_BG = '#010203'`n"
    $wildOriginal = "TOKENS = {`n    `"keep`": `"#010203`",`n}`n"
    [System.IO.File]::WriteAllText($smartFile, $smartOriginal, (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText($wildFile, $wildOriginal, (New-Object System.Text.UTF8Encoding($false)))

    & powershell -NoProfile -ExecutionPolicy Bypass -File "$root\desktop\install.ps1" -Target smartvac -SmartVacPath $smartVac -WhatIf *> $null
    $smartExit = $LASTEXITCODE
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$root\desktop\install.ps1" -Target wildrift -WildRiftPath $wildRift -WhatIf *> $null
    $wildExit = $LASTEXITCODE

    Assert-True ($smartExit -eq 0 -and $wildExit -eq 0) '-WhatIf fixture commands exit successfully'
    Assert-True ([System.IO.File]::ReadAllText($smartFile) -eq $smartOriginal) 'SMART VAC CLEANER -WhatIf leaves source byte-exact'
    Assert-True (-not (Test-Path "$smartFile.bak")) 'SMART VAC CLEANER -WhatIf creates no backup'
    Assert-True ([System.IO.File]::ReadAllText($wildFile) -eq $wildOriginal) 'WildRiftAssistant -WhatIf leaves source byte-exact'
    Assert-True (-not (Test-Path "$wildFile.bak")) 'WildRiftAssistant -WhatIf creates no backup'
} finally {
    if (Test-Path $whatIfRoot) { Remove-Item $whatIfRoot -Recurse -Force }
}

Write-Host "
--- Testing Terminal Font and Round Trip ---" -ForegroundColor Cyan
$terminalRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-terminal-" + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $terminalRoot -Force | Out-Null
    $terminalSettings = Join-Path $terminalRoot 'settings.json'
    $terminalOriginal = "{`r`n  // preserve this comment on revert`r`n  `"profiles`": { `"defaults`": { `"font`": { `"face`": `"Verdana`", `"size`": 11 } } },`r`n}`r`n"
    [System.IO.File]::WriteAllText($terminalSettings, $terminalOriginal, (New-Object System.Text.UTF8Encoding($false)))
    $terminalBefore = [System.IO.File]::ReadAllBytes($terminalSettings)

    & node "$root\tools\install-terminal.js" --settings $terminalSettings --palette "$root\themes\goldendefault.json" 2>&1 | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'terminal fixture apply exits successfully'
    $terminalApplied = Get-Content $terminalSettings -Raw | ConvertFrom-Json
    Assert-True ($terminalApplied.profiles.defaults.font.face -eq 'Consolas') 'terminal uses a fixed-width console-safe font'
    Assert-True ($terminalApplied.profiles.defaults.font.size -eq 12) 'terminal keeps the Vintage 12px font size'
    Assert-True ($terminalApplied.profiles.defaults.antialiasingMode -eq 'aliased') 'terminal keeps aliased rendering'
    Assert-True (Test-Path ($terminalSettings + '.wintage.bak')) 'terminal fixture creates one exact backup'

    & node "$root\tools\install-terminal.js" --settings $terminalSettings --revert 2>&1 | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'terminal fixture revert exits successfully'
    $terminalAfter = [System.IO.File]::ReadAllBytes($terminalSettings)
    Assert-True (-not (Compare-Object $terminalBefore $terminalAfter)) 'terminal revert restores settings byte-for-byte'
    Assert-True (-not (Test-Path ($terminalSettings + '.wintage.bak'))) 'terminal revert consumes its backup'

    Assert-True ($installCode -match '\$CONSOLE_FONT\s*=\s*''Consolas''') 'conhost uses the same fixed-width console-safe font'
    Assert-True ($installCode -notmatch '\$CONSOLE_FONT\s*=\s*''Verdana''') 'conhost no longer forces proportional Verdana'
} finally {
    if (Test-Path $terminalRoot) { Remove-Item $terminalRoot -Recurse -Force }
}

Write-Host "
--- Testing Total Commander Recent-File Indicator ---" -ForegroundColor Cyan
$tcRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-totalcmd-" + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $tcRoot -Force | Out-Null
    $tcIni = Join-Path $tcRoot 'wincmd.ini'
    $tcTheme = Join-Path $tcRoot 'Current.ini'
    $tcEntryText = "[Colors]`r`nRedirectSection=`"%COMMANDER_PATH%\Current.ini`"`r`n"
    $tcOriginal = @"
[ColorTheme]
EnableColorFilters=1
[ColorsDark]
ColorFilter1=>Age rule
ColorFilter1Color=8414720
ColorFilter2=>Keep custom
ColorFilter2Color=12632256
ColorFilter3=>Invalid relative date
ColorFilter3Color=424242
[Colors]
ColorFilter1=>Age rule
ColorFilter1Color=8414720
ColorFilter1ColorDark=8414720,8414720
ColorFilter2=>Keep custom
ColorFilter2Color=12632256
ColorFilter3=>Invalid relative date
ColorFilter3Color=424242
[Searches]
Age rule_SearchFlags=0|000002000020|||2|0|||||0000|
Keep custom_SearchFlags=0|000002000020||||||||22220|0000|
Invalid relative date_SearchFlags=0|000002000020|||-1|-1|||||0000|
"@
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tcIni, $tcEntryText, $utf8NoBom)
    [System.IO.File]::WriteAllText($tcTheme, $tcOriginal, $utf8NoBom)

    & powershell -NoProfile -ExecutionPolicy Bypass -File "$root\desktop\install.ps1" -Target totalcmd -TotalCmdIni $tcIni -Palette goldendefault *> $null
    $applyExit = $LASTEXITCODE
    $after = [System.IO.File]::ReadAllText($tcTheme)
    $pack = Get-Content "$root\themes\goldendefault.json" -Raw | ConvertFrom-Json
    $hex = $pack.tokens.link.TrimStart('#')
    $expectedRecent = ([Convert]::ToInt32($hex.Substring(4, 2), 16) -shl 16) -bor
        ([Convert]::ToInt32($hex.Substring(2, 2), 16) -shl 8) -bor
        [Convert]::ToInt32($hex.Substring(0, 2), 16)

    Assert-True ($applyExit -eq 0) 'Total Commander fixture apply exits successfully'
    Assert-True (([regex]::Matches($after, "(?m)^ColorFilter1Color=$expectedRecent`r?`$")).Count -eq 2) 'recent-file filter uses the palette link colour in light and dark sections'
    Assert-True ($after.Contains("ColorFilter1ColorDark=$expectedRecent,$expectedRecent")) 'explicit dark-mode colour keeps Total Commander normal/dark mirror values aligned'
    Assert-True (([regex]::Matches($after, '(?m)^ColorFilter2Color=12632256\r?$')).Count -eq 2) 'non-age filter keeps its user colour'
    Assert-True (([regex]::Matches($after, '(?m)^ColorFilter3Color=424242\r?$')).Count -eq 2) 'invalid relative-date filter is not mistaken for a recent file'
    Assert-True ($after.Contains('ColorFilter1=>Age rule')) 'recent-file filter expression is preserved'
    Assert-True (Test-Path "$tcTheme.wintage.bak") 'Total Commander fixture creates one exact backup'

    & powershell -NoProfile -ExecutionPolicy Bypass -File "$root\desktop\install.ps1" -Target totalcmd -TotalCmdIni $tcIni -Revert *> $null
    $revertExit = $LASTEXITCODE
    Assert-True ($revertExit -eq 0) 'Total Commander fixture revert exits successfully'
    Assert-True ([System.IO.File]::ReadAllText($tcTheme) -eq $tcOriginal) 'Total Commander revert restores the original theme byte-for-byte'
    Assert-True (-not (Test-Path "$tcTheme.wintage.bak")) 'Total Commander revert consumes its backup'
} finally {
    if (Test-Path $tcRoot) { Remove-Item $tcRoot -Recurse -Force }
}

Write-Host "
--- Testing Browser and Tampermonkey Target ---" -ForegroundColor Cyan
$browserRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-browsers-" + [guid]::NewGuid().ToString('N'))
try {
    $fakeBrowser = Join-Path $browserRoot 'Portable Browser'
    $fakeExe = Join-Path $fakeBrowser 'chrome.exe'
    $fakeData = Join-Path $fakeBrowser 'User Data'
    $fakeProfile = Join-Path $fakeData 'Default'
    $tmDir = Join-Path $fakeProfile 'Extensions\dhdgffkkebhmkfjojejmpbldmpobfkfo\5.5.0_0'
    $stage = Join-Path $browserRoot 'stage'
    $whatIfStage = Join-Path $browserRoot 'whatif-stage'
    New-Item -ItemType Directory -Path $tmDir -Force | Out-Null
    [System.IO.File]::WriteAllBytes($fakeExe, [byte[]]@())
    [System.IO.File]::WriteAllText((Join-Path $fakeProfile 'Preferences'), '{}', (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $fakeData 'Local State'), '{}', (New-Object System.Text.UTF8Encoding($false)))
    $catalog = Join-Path $browserRoot 'catalog.json'
    @([ordered]@{ Name = 'Fixture Chromium'; Exe = $fakeExe; UserData = $fakeData }) |
        ConvertTo-Json | ForEach-Object { [System.IO.File]::WriteAllText($catalog, $_, (New-Object System.Text.UTF8Encoding($false))) }

    $browserTool = "$root\tools\install-browsers.ps1"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $browserTool -Palette goldendefault -Catalog $catalog -StageRoot $stage -NoLaunch *> $null
    $browserApplyExit = $LASTEXITCODE
    Assert-True ($browserApplyExit -eq 0) 'browser fixture apply exits successfully'
    Assert-True (Test-Path (Join-Path $stage 'manifest.json')) 'selected browser theme is staged at a stable path'
    Assert-True (([System.IO.File]::ReadAllText((Join-Path $stage '.wintage-palette'))).Trim() -eq 'goldendefault') 'browser stage records the active palette'

    $escapedStage = $stage.Replace('\', '\\')
    [System.IO.File]::WriteAllText((Join-Path $fakeProfile 'Preferences'), ('{"extensions":{"settings":{"fixture":{"path":"' + $escapedStage + '"}}}}'), (New-Object System.Text.UTF8Encoding($false)))
    $summary = (& powershell -NoProfile -ExecutionPolicy Bypass -File $browserTool -ListJson -Catalog $catalog -StageRoot $stage | ConvertFrom-Json)
    Assert-True ($summary.ProfileCount -eq 1) 'browser discovery reports the fixture profile'
    Assert-True ($summary.TampermonkeyCount -eq 1) 'browser discovery detects Tampermonkey per profile'
    Assert-True ($summary.ThemeLoadedCount -eq 1) 'browser discovery recognises its stable unpacked-theme path'
    Assert-True ($summary.Palette -eq 'goldendefault') 'browser listing reports the staged palette'

    $clipboardStage = Join-Path $browserRoot 'clipboard-stage'
    $clipboardCommand = "& '$browserTool' -Palette goldendefault -Catalog '$catalog' -StageRoot '$clipboardStage' -ClipboardWriter { param(`$Value) throw 'clipboard denied' } 3>&1 2>&1"
    $clipboardOutput = (& powershell -NoProfile -ExecutionPolicy Bypass -Command $clipboardCommand | Out-String)
    Assert-True ($LASTEXITCODE -eq 0) 'browser clipboard-failure fixture exits successfully'
    Assert-True ($clipboardOutput -match 'path could not be copied') 'browser reports clipboard failure'
    Assert-True ($clipboardOutput -match [regex]::Escape($clipboardStage)) 'browser prints the usable stage path after clipboard failure'
    Assert-True ($clipboardOutput -notmatch 'copied to clipboard') 'browser does not claim clipboard success after failure'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $browserTool -Catalog $catalog -StageRoot $clipboardStage -NoLaunch -Revert *> $null

    & powershell -NoProfile -ExecutionPolicy Bypass -File $browserTool -Palette goldendefault -Catalog $catalog -StageRoot $whatIfStage -NoLaunch -WhatIf *> $null
    Assert-True ($LASTEXITCODE -eq 0) 'browser fixture -WhatIf exits successfully'
    Assert-True (-not (Test-Path $whatIfStage)) 'browser -WhatIf stages nothing'

    & powershell -NoProfile -ExecutionPolicy Bypass -File $browserTool -Catalog $catalog -StageRoot $stage -NoLaunch -Revert *> $null
    Assert-True ($LASTEXITCODE -eq 0) 'browser fixture revert exits successfully'
    Assert-True (-not (Test-Path $stage)) 'browser revert removes only the Wintage staging folder'
    Assert-True (Test-Path (Join-Path $fakeProfile 'Preferences')) 'browser target never rewrites browser Preferences'
} finally {
    if (Test-Path $browserRoot) { Remove-Item $browserRoot -Recurse -Force }
}

$guiSource = [System.IO.File]::ReadAllText("$root\desktop\WintageInstaller.ps1")
Assert-True ($guiSource -match 'could not save paths\.json') 'GUI reports custom-path persistence failures'
Assert-True ($guiSource -notmatch 'function Save-CustomPaths[\s\S]*?catch\s*\{\s*\}') 'GUI custom-path save no longer swallows errors'

Write-Host "
======================="
if ($script:errors -gt 0) {
    Write-Host "TESTS FAILED ($script:errors errors)" -ForegroundColor Red
    exit 1
} else {
    Write-Host "ALL TESTS PASSED!" -ForegroundColor Green
    exit 0
}
