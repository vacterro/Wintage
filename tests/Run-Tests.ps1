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
# The schema authority is tools/theme-schema.json (mirrored from
# theme-schema.js), NOT golden.json: golden is one pack, i.e. data, and a pack
# can never be the specification that judges the other packs (T-187).
$schemaFile = "$root\tools\theme-schema.json"
Assert-True (Test-Path $schemaFile) "canonical theme schema exists"
$schema = Get-Content $schemaFile -Raw | ConvertFrom-Json
$requiredKeys = @($schema.tokens)

foreach ($file in Get-ChildItem "$root\themes\*.json") {
    $theme = Get-Content $file.FullName -Raw | ConvertFrom-Json
    $themeKeys = $theme.tokens.PSObject.Properties.Name | Sort-Object
    
    $missing = $requiredKeys | Where-Object { $_ -notin $themeKeys }
    $extra = $themeKeys | Where-Object { $_ -notin $requiredKeys }
    
    Assert-True (@($missing).Count -eq 0) "$($file.Name) has all $($requiredKeys.Count) required token keys"
    if (@($missing).Count -gt 0) { Write-Host "       Missing: $($missing -join ', ')" -ForegroundColor Red }
    
    Assert-True (@($extra).Count -eq 0) "$($file.Name) has no undocumented extra keys"
    if (@($extra).Count -gt 0) { Write-Host "       Extra: $($extra -join ', ')" -ForegroundColor Red }

    Assert-True ($file.BaseName -eq $theme.slug) "$($file.Name) filename matches its pack.slug"
    Assert-True ([bool]$theme.label) "$($file.Name) has a label"
}

# Duplicate slug/label collision fixture: two packs sharing a slug or a label
# must be rejected by the generators' shared validator (tools/theme-schema.js).
$schemaSync = (& node "$root\tools\theme-schema.js" --json | Out-String).Trim()
Assert-True ($LASTEXITCODE -eq 0) "theme-schema.js --json runs clean"
$schemaExpected = ((Get-Content $schemaFile -Raw) -replace '\s', '')
$schemaActual = ($schemaSync -replace '\s', '')
Assert-True ($schemaExpected -eq $schemaActual) "theme-schema.json mirrors theme-schema.js (tokens + WCAG roles)"
if ($schemaExpected -ne $schemaActual) {
    Write-Host "       JS  : $schemaActual" -ForegroundColor Red
    Write-Host "       JSON: $schemaExpected" -ForegroundColor Red
}

$wcagRoles = @($schema.wcagRoles)
Assert-True ($wcagRoles.Count -eq 3 -and $wcagRoles -contains 'link') "WCAG role list is the shared text-role set (textPrimary/textSecondary/link)"

# Vintage Classic regression fixture (T-187): the shared roles are the text
# roles. borderHighlight on this LIGHT palette is a near-white decorative bevel
# and MUST NOT be in the role list -- gating it is how the old GUI produced a
# false FAIL for every light palette while the build gate accepted them.
function Get-RelLum([double]$v) { if ($v -le 0.03928) { $v / 12.92 } else { [Math]::Pow(($v + 0.055) / 1.055, 2.4) } }
function Get-Contrast([string]$hexA, [string]$hexB) {
    $toRgb = { param($h) @([Convert]::ToInt32($h.Substring(1,2),16), [Convert]::ToInt32($h.Substring(3,2),16), [Convert]::ToInt32($h.Substring(5,2),16)) }
    $ra = & $toRgb $hexA; $rb = & $toRgb $hexB
    $lumA = 0.2126 * (Get-RelLum ($ra[0]/255)) + 0.7152 * (Get-RelLum ($ra[1]/255)) + 0.0722 * (Get-RelLum ($ra[2]/255))
    $lumB = 0.2126 * (Get-RelLum ($rb[0]/255)) + 0.7152 * (Get-RelLum ($rb[1]/255)) + 0.0722 * (Get-RelLum ($rb[2]/255))
    ([Math]::Max($lumA,$lumB) + 0.05) / ([Math]::Min($lumA,$lumB) + 0.05)
}
$vc = Get-Content "$root\themes\vintageclassic.json" -Raw | ConvertFrom-Json
$vcBg = $vc.tokens.backgroundSoft
foreach ($role in $wcagRoles) {
    $ratio = Get-Contrast $vc.tokens.$role $vcBg
    Assert-True ($ratio -ge 4.5) "vintageclassic $role passes WCAG AA on backgroundSoft ($([Math]::Round($ratio,2)):1)"
}
$vcBevel = Get-Contrast $vc.tokens.borderHighlight $vcBg
Assert-True ($vcBevel -lt 4.5) "vintageclassic borderHighlight is decorative (<4.5:1) and therefore must NOT be a WCAG text role"

Write-Host "
--- Theme Identity Validation ---" -ForegroundColor Cyan
# The generators must reject duplicate slug, duplicate label and
# filename/slug mismatch. Probed through the shared validator directly with a
# throwaway themes/ clone so the real pack dir is never at risk.
$identRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-identity-" + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $identRoot -Force | Out-Null
    function New-IdentityPack([string]$slug, [string]$label, [int]$order) {
        $tokens = @{}
        foreach ($k in $requiredKeys) { $tokens[$k] = '#112233' }
        @{ slug = $slug; label = $label; order = $order; tokens = $tokens }
    }
    $schemaJsPath = $root.Replace('\', '/') + '/tools/theme-schema.js'

    # duplicate slug is structurally impossible to reach directly: the
    # filename==slug invariant means two packs sharing a slug would need the same
    # filename, so the collision guard is exercised through a second file that
    # CLAIMS an already-used slug -- the validator must reject it hard, and the
    # filename guard is the mechanism that makes the collision impossible.
    $dupRoot = Join-Path $identRoot 'dupslug'
    New-Item -ItemType Directory -Path $dupRoot -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $dupRoot 'alpha.json'), ((New-IdentityPack 'alpha' 'Alpha' 1) | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $dupRoot 'alpha-copy.json'), ((New-IdentityPack 'alpha' 'Beta' 2) | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
    $dupOut = (& node -e "const {loadAndValidatePacks}=require('$schemaJsPath'); try{loadAndValidatePacks('$($dupRoot.Replace('\','/'))');console.log('NO-ERROR')}catch(e){console.log('REJECTED: '+e.message)}")
    Assert-True ($dupOut -match 'REJECTED:') "a second pack claiming an already-used slug is rejected"

    # duplicate label (same label, different slug -> the label collision must fire)
    $labRoot = Join-Path $identRoot 'duplabel'
    New-Item -ItemType Directory -Path $labRoot -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $labRoot 'alpha.json'), ((New-IdentityPack 'alpha' 'Alpha' 1) | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $labRoot 'beta.json'), ((New-IdentityPack 'beta' 'Alpha' 2) | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
    $labOut = (& node -e "const {loadAndValidatePacks}=require('$schemaJsPath'); try{loadAndValidatePacks('$($labRoot.Replace('\','/'))');console.log('NO-ERROR')}catch(e){console.log('REJECTED: '+e.message)}")
    Assert-True ($labOut -match 'REJECTED:.*duplicate label') "duplicate label is rejected"

    # filename/slug mismatch (gamma.json claims slug alpha)
    $misRoot = Join-Path $identRoot 'mismatch'
    New-Item -ItemType Directory -Path $misRoot -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $misRoot 'gamma.json'), ((New-IdentityPack 'alpha' 'Gamma' 1) | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
    $misOut = (& node -e "const {loadAndValidatePacks}=require('$schemaJsPath'); try{loadAndValidatePacks('$($misRoot.Replace('\','/'))');console.log('NO-ERROR')}catch(e){console.log('REJECTED: '+e.message)}")
    Assert-True ($misOut -match 'REJECTED:.*filename does not match') "filename/slug mismatch is rejected"
} finally {
    if (Test-Path $identRoot) { Remove-Item $identRoot -Recurse -Force }
}

Write-Host "
--- GUI Shares the Build Gate's WCAG Roles ---" -ForegroundColor Cyan
# The GUI must read its token list and WCAG roles from the shared schema, never
# carry a second hardcoded list (the borderHighlight drift that produced false
# FAILs in the editor). The read is the contract; a resurrected hardcoded copy
# is what this gate fails on.
$guiSource = [System.IO.File]::ReadAllText("$root\desktop\WintageInstaller.ps1")
Assert-True ($guiSource -match 'theme-schema\.json') 'GUI reads the canonical theme-schema.json'
Assert-True ($guiSource -notmatch "['""]textPrimary['""]\s*,\s*['""]textSecondary['""]\s*,\s*['""]borderHighlight['""]") 'GUI does not carry the stale hardcoded WCAG role list'
Assert-True ($guiSource -match '\$script:wcagRoles') 'GUI consumes wcagRoles from the schema'

Write-Host "
--- Mojibake Gate ---" -ForegroundColor Cyan
# Double-encoded UTF-8 punctuation (em-dashes/box-drawing read as cp1251 and
# re-saved) is impossible in this codebase's ASCII source files and is caught
# here by the Cyrillic codepoints it leaves behind (T-187).
$mojibakeFiles = @(
    "$root\tools\build-desktop.js", "$root\tools\install-electron.js",
    "$root\tools\derive-palette.js", "$root\tools\apply-themes.js",
    "$root\tools\check-css.js", "$root\tools\theme-schema.js",
    "$root\desktop\install.ps1", "$root\desktop\WintageInstaller.ps1",
    "$root\desktop\modules\common.ps1", "$root\desktop\modules\targets.ps1",
    "$root\desktop\i18n.ps1", "$root\tests\Run-Tests.ps1",
    "$root\tools\test-reapply.ps1", "$root\release.ps1"
)
foreach ($f in $mojibakeFiles) {
    $text = [System.IO.File]::ReadAllText($f)
    $bad = @()
    foreach ($ch in $text.ToCharArray()) {
        $cp = [int]$ch
        if (($cp -ge 0x0400 -and $cp -le 0x04FF) -or ($cp -ge 0x2018 -and $cp -le 0x201F)) { $bad += ("U+{0:X4}" -f $cp) }
    }
    Assert-True ($bad.Count -eq 0) "$($f | Split-Path -Leaf) carries no mojibake signatures ($($bad -join ' '))"
}
$vscodePkg = "$root\desktop\out\vscode\wintage-themes\package.json"
if (Test-Path $vscodePkg) {
    Assert-True (([System.IO.File]::ReadAllText($vscodePkg)) -notmatch '[\u0400-\u04FF]') 'generated VS Code package.json carries no mojibake'
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
    # CRLF-tolerant, and written on ONE line on purpose. The previous form
    # embedded a LITERAL newline in the pattern, so it matched only while the
    # working copy used LF -- the moment install.ps1 was checked out with CRLF the
    # ELECTRON keys stopped being found and this gate went red on code it had no
    # complaint about. Same failure the Save-CustomPaths check had: a gate that
    # goes red for reasons unrelated to what it tests gets ignored, then trusted.
    $targetsMatches = [regex]::Matches($installCode, "(?:'|"")?([a-z0-9\-]+)(?:'|"")?\s*=\s*@\{\s*
?
\s+(Dir|Name)")
    $hashTargets = @()
    foreach ($m in $targetsMatches) { $hashTargets += $m.Groups[1].Value }
    # $TARGETS keys ONLY (the generic pattern above also swallows $ELECTRON keys,
    # which the ownership gate needs separated).
    $tBlock = [regex]::Match($installCode, '(?s)\$TARGETS\s*=\s*@\{(.*?)\n\s*\}').Groups[1].Value
    $targetsKeys = @([regex]::Matches($tBlock, "(?:'|"")?([a-z0-9\-]+)(?:'|"")?\s*=\s*@\{") | ForEach-Object { $_.Groups[1].Value })
    
    # Extract $ELECTRON keys
    $regex = '(?s)\$ELECTRON\s*=\s*@\{(.*?)\n\s*\}'
    $electronMatches = [regex]::Matches($installCode, $regex)
    $electronKeys = @()
    if ($electronMatches.Count -gt 0) {
        $eBlock = $electronMatches[0].Groups[1].Value
        $eKeysMatches = [regex]::Matches($eBlock, "(?:'|"")?([a-z0-9\-]+)(?:'|"")?\s*=\s*@{")
        foreach ($m in $eKeysMatches) { $hashTargets += $m.Groups[1].Value; $electronKeys += $m.Groups[1].Value }
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

    # Every non-all target must live in exactly ONE dispatch collection. A name
    # in two collections would be attempted twice under -Target all (the $known
    # concatenation) and shadowed by whichever branch matches first (T-187).
    $simpleDecl = [regex]::Match($installCode, '\$SIMPLE\s*=\s*@\((.*?)\)', 'Singleline').Groups[1].Value
    $simpleList = if ($simpleDecl) { @([regex]::Matches($simpleDecl, "'([a-z0-9\-]+)'") | ForEach-Object { $_.Groups[1].Value }) } else { @() }
    $ownerCount = @{}
    foreach ($t in @($targetsKeys + $electronKeys + $simpleList)) { $ownerCount[$t] = ($ownerCount[$t] + 1) }
    $dupeOwner = @($ownerCount.Keys | Where-Object { $ownerCount[$_] -gt 1 })
    Assert-True ($dupeOwner.Count -eq 0) "no target belongs to more than one dispatch collection ($($dupeOwner -join ', '))"
}

Write-Host "
--- Testing Script Syntax ---" -ForegroundColor Cyan
$parseErrors = $null
foreach ($script in @("$root\desktop\install.ps1", "$root\desktop\WintageInstaller.ps1", "$root\tools\install-browsers.ps1", "$root\desktop\modules\common.ps1", "$root\desktop\modules\targets.ps1")) {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$null, [ref]$parseErrors)
    Assert-True ($parseErrors.Count -eq 0) "$($script | Split-Path -Leaf) parses with zero syntax errors"
    if ($parseErrors.Count -gt 0) {
        foreach ($e in $parseErrors) { Write-Host "       Line $($e.Extent.StartLineNumber): $($e.Message)" -ForegroundColor Red }
    }
}

Write-Host "
--- Testing Function Definition Uniqueness ---" -ForegroundColor Cyan
# No module may define the same function twice in one scope (T-190/P1#9):
# "last definition wins" is how two supposedly identical copies become different
# six months later. install.ps1 dot-sources common.ps1 THEN i18n.ps1, so a
# duplicate across those two is a real collision in one process.
$moduleFiles = @(
    "$root\desktop\modules\common.ps1",
    "$root\desktop\modules\targets.ps1",
    "$root\desktop\i18n.ps1",
    "$root\desktop\install.ps1",
    "$root\desktop\WintageInstaller.ps1"
)
foreach ($script in $moduleFiles) {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$null, [ref]$null)
    $names = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
    $dups = @($names | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    Assert-True ($dups.Count -eq 0) "$($script | Split-Path -Leaf) has no duplicate function definitions"
    if ($dups.Count -gt 0) { Write-Host "       Duplicates: $($dups -join ', ')" -ForegroundColor Red }
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
--- Testing Terminal Font, Round Trip and Ownership Revert ---" -ForegroundColor Cyan
$terminalRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-terminal-" + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $terminalRoot -Force | Out-Null
    $terminalSettings = Join-Path $terminalRoot 'settings.json'
    # Canonical JSON in the tool's own output shape (JSON.stringify null,4) so
    # the owned-field round-trip is byte-exact when no unrelated edit happened
    # (T-189): byte-exact is valid ONLY then.
    $terminalOriginal = "{
    `"profiles`": {
        `"defaults`": {
            `"font`": {
                `"face`": `"Verdana`",
                `"size`": 11
            }
        }
    },
    `"startOnUserLogin`": false
}
"
    [System.IO.File]::WriteAllText($terminalSettings, $terminalOriginal, (New-Object System.Text.UTF8Encoding($false)))
    $terminalBefore = [System.IO.File]::ReadAllBytes($terminalSettings)

    & node "$root\tools\install-terminal.js" --settings $terminalSettings --palette "$root\themes\goldendefault.json" 2>&1 | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'terminal fixture apply exits successfully'
    $terminalApplied = Get-Content $terminalSettings -Raw | ConvertFrom-Json
    Assert-True ($terminalApplied.profiles.defaults.font.face -eq 'Consolas') 'terminal uses a fixed-width console-safe font'
    Assert-True ($terminalApplied.profiles.defaults.font.size -eq 12) 'terminal keeps the Vintage 12px font size'
    Assert-True ($terminalApplied.profiles.defaults.antialiasingMode -eq 'aliased') 'terminal keeps aliased rendering'
    Assert-True (Test-Path ($terminalSettings + '.wintage.bak')) 'terminal fixture creates one exact backup'

    # Case A: no unrelated edit -> owned-field revert restores the file byte-exact.
    & node "$root\tools\install-terminal.js" --settings $terminalSettings --revert 2>&1 | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'terminal fixture revert exits successfully'
    $terminalAfter = [System.IO.File]::ReadAllBytes($terminalSettings)
    Assert-True (-not (Compare-Object $terminalBefore $terminalAfter)) 'terminal revert restores settings byte-for-byte when no unrelated edit occurred'
    Assert-True (-not (Test-Path ($terminalSettings + '.wintage.bak'))) 'terminal revert consumes its backup'

    # Case B: the USER changes an unrelated setting after Apply (T-189). Revert
    # must merge the owned fields back into the CURRENT file and preserve the
    # user edit - never restore the whole old file.
    [System.IO.File]::WriteAllText($terminalSettings, $terminalOriginal, (New-Object System.Text.UTF8Encoding($false)))
    & node "$root\tools\install-terminal.js" --settings $terminalSettings --palette "$root\themes\goldendefault.json" 2>&1 | Out-Null
    $current = Get-Content $terminalSettings -Raw | ConvertFrom-Json
    $current.startOnUserLogin = $true
    $current.profiles | Add-Member -NotePropertyName list -NotePropertyValue @(@{ name = 'User-added profile'; commandline = 'cmd.exe' }) -Force
    $current | Add-Member -NotePropertyName actions -NotePropertyValue @(@{ action = 'close' }) -Force
    [System.IO.File]::WriteAllText($terminalSettings, ($current | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))
    & node "$root\tools\install-terminal.js" --settings $terminalSettings --revert 2>&1 | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'terminal ownership revert exits successfully'
    $afterOwn = Get-Content $terminalSettings -Raw | ConvertFrom-Json
    Assert-True ($afterOwn.profiles.defaults.font.face -eq 'Verdana') 'terminal ownership revert restores the owned font face'
    Assert-True ($afterOwn.profiles.defaults.font.size -eq 11) 'terminal ownership revert restores the owned font size'
    $csProp = $afterOwn.profiles.defaults.PSObject.Properties['colorScheme']
    Assert-True (-not $csProp -or $csProp.Value -ne 'Wintage') 'terminal ownership revert removes the Wintage colorScheme'
    Assert-True ($afterOwn.startOnUserLogin -eq $true) 'terminal ownership revert PRESERVES the unrelated user edit (startOnUserLogin)'
    Assert-True (@($afterOwn.profiles.list | Where-Object { $_.name -eq 'User-added profile' }).Count -eq 1) 'terminal ownership revert PRESERVES a user-added profile'
    Assert-True (@($afterOwn.actions).Count -eq 1) 'terminal ownership revert PRESERVES a user-added actions block'
    Assert-True (-not (Test-Path ($terminalSettings + '.wintage.bak'))) 'terminal ownership revert consumes its backup'

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
    # Total Commander is written with a UTF-8 BOM and CRLF on purpose (T-075:
    # Win32 INI parsers fall back to ANSI without the BOM), so the byte-exact
    # fixture must match the tool's output shape exactly.
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($tcIni, $tcEntryText, $utf8NoBom)
    $tcOriginalCrlf = ($tcOriginal -replace "`r?`n", "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText($tcTheme, $tcOriginalCrlf, $utf8Bom)

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
    Assert-True ([System.IO.File]::ReadAllText($tcTheme) -eq $tcOriginalCrlf) 'Total Commander revert restores the original theme byte-for-byte'
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
    # Out-String wraps captured warnings at the console width, so a 120-column
    # host splits the sentence across a newline AND re-prefixes the continuation
    # with "WARNING: " mid-phrase ('path could\nWARNING:  not be copied'). Strip
    # the prefixes and flatten whitespace before matching: the gate tests WHAT
    # the tool reports, not line layout, and it still fails if the tool stops
    # reporting the failure at all.
    $clipboardOutputFlat = ($clipboardOutput -replace '(?m)^WARNING:\s*', '') -replace '\s+', ' '
    Assert-True ($LASTEXITCODE -eq 0) 'browser clipboard-failure fixture exits successfully'
    Assert-True ($clipboardOutputFlat -match 'path could not be copied') 'browser reports clipboard failure'
    Assert-True ($clipboardOutputFlat -match [regex]::Escape($clipboardStage)) 'browser prints the usable stage path after clipboard failure'
    Assert-True ($clipboardOutputFlat -notmatch 'copied to clipboard') 'browser does not claim clipboard success after failure'
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
# Bounded to the function's OWN body. The previous form was
#   'function Save-CustomPaths[\s\S]*?catch\s*\{\s*\}'
# which is non-greedy and therefore reaches the first empty catch ANYWHERE below
# the declaration -- so an unrelated `catch { }` on a media player's Stop/Dispose
# call, added much later in the file, failed a test about paths.json. A gate that
# goes red for code it does not cover teaches people to ignore it.
$saveStart = $guiSource.IndexOf('function Save-CustomPaths')
Assert-True ($saveStart -ge 0) 'GUI still defines Save-CustomPaths'
$saveEnd = $guiSource.IndexOf("`n}", $saveStart)
$saveBody = if ($saveStart -ge 0 -and $saveEnd -gt $saveStart) { $guiSource.Substring($saveStart, $saveEnd - $saveStart) } else { '' }
Assert-True ($saveBody -notmatch 'catch\s*\{\s*\}') 'GUI custom-path save no longer swallows errors'

Write-Host "
======================="
if ($script:errors -gt 0) {
    Write-Host "TESTS FAILED ($script:errors errors)" -ForegroundColor Red
    exit 1
} else {
    Write-Host "ALL TESTS PASSED!" -ForegroundColor Green
    exit 0
}
