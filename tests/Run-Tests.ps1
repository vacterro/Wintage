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
    # CRLF-tolerant, and written as ONE escaped pattern on purpose. An earlier form
    # embedded a LITERAL newline in the pattern, so it matched only while the
    # working copy used LF -- the moment install.ps1 was checked out with CRLF the
    # ELECTRON keys stopped being found and this gate went red on code it had no
    # complaint about. Same failure the Save-CustomPaths check had: a gate that
    # goes red for reasons unrelated to what it tests gets ignored, then trusted.
    $targetsMatches = [regex]::Matches($installCode, "(?:'|"")?([a-z0-9\-]+)(?:'|"")?\s*=\s*@\{[ \t]*\r?\n\s+(Dir|Name)")
    $hashTargets = @()
    foreach ($m in $targetsMatches) { $hashTargets += $m.Groups[1].Value }
    # $TARGETS keys ONLY (the generic pattern above also swallows $ELECTRON keys,
    # which the ownership gate needs separated).
    # Both block patterns close on a brace in COLUMN 0, the only place a top-level
    # hashtable literal can end. `(.*?)\n\s*\}` closed on the first NESTED entry's
    # brace instead, so each block yielded only its first key or two and every
    # later target was reported as having no implementation -- workbuddy,
    # antigravity-app and codenomad were all "missing" while fully wired (T-198).
    $tBlock = [regex]::Match($installCode, '(?s)\$TARGETS\s*=\s*@\{(.*?)\r?\n\}').Groups[1].Value
    $targetsKeys = @([regex]::Matches($tBlock, "(?m)^\s{4}(?:'|"")?([a-z0-9\-]+)(?:'|"")?\s*=\s*@\{") | ForEach-Object { $_.Groups[1].Value })

    # Extract $ELECTRON keys
    $regex = '(?s)\$ELECTRON\s*=\s*@\{(.*?)\r?\n\}'
    $electronMatches = [regex]::Matches($installCode, $regex)
    $electronKeys = @()
    if ($electronMatches.Count -gt 0) {
        $eBlock = $electronMatches[0].Groups[1].Value
        $eKeysMatches = [regex]::Matches($eBlock, "(?m)^\s{4}(?:'|"")?([a-z0-9\-]+)(?:'|"")?\s*=\s*@\{")
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
$nppDir = Join-Path $whatIfRoot 'npp'
$c4dDir = Join-Path $whatIfRoot 'c4d'
try {
    New-Item -ItemType Directory -Path $nppDir -Force | Out-Null
    $c4dSchemes = Join-Path $c4dDir 'resource\modules\c4d_base\schemes'
    New-Item -ItemType Directory -Path $c4dSchemes -Force | Out-Null

    & powershell -NoProfile -ExecutionPolicy Bypass -File "$root\desktop\install.ps1" -Target notepadplusplus -NotepadPlusPlusPath $nppDir -WhatIf *> $null
    $nppExit = $LASTEXITCODE
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$root\desktop\install.ps1" -Target cinema4d -Cinema4DPath $c4dDir -WhatIf *> $null
    $c4dExit = $LASTEXITCODE

    Assert-True ($nppExit -eq 0 -and $c4dExit -eq 0) '-WhatIf fixture commands exit successfully'
    Assert-True (-not (Test-Path (Join-Path $nppDir 'themes\Wintage.xml'))) 'Notepad++ -WhatIf creates no files'
    Assert-True (-not (Test-Path (Join-Path $c4dSchemes 'Wintage'))) 'Cinema 4D -WhatIf creates no files'
} finally {
    if (Test-Path $whatIfRoot) { Remove-Item $whatIfRoot -Recurse -Force }
}

Write-Host "
--- Testing Terminal Font, Round Trip and Ownership Revert ---" -ForegroundColor Cyan
$terminalRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-terminal-" + [guid]::NewGuid().ToString('N'))
# T-283: the terminal helper reads the canonical typography preference
# (tools/terminal-font-preference.js -> %APPDATA%\Wintage\terminal-font.json, or
# WINTAGE_APPDATA when set). This fixture asserts the SHIPPED DEFAULT, so it must
# pin WINTAGE_APPDATA to an isolated dir with no preference file; otherwise a
# developer's real selected font would leak into the fixture and "fail" the
# default assertions. Restored in the finally below.
$savedWintageAppData = $env:WINTAGE_APPDATA
$env:WINTAGE_APPDATA = Join-Path $terminalRoot 'Wintage'
try {
    New-Item -ItemType Directory -Path $terminalRoot -Force | Out-Null
    $terminalSettings = Join-Path $terminalRoot 'settings.json'
    # Canonical JSON in the tool's own output shape (JSON.stringify null,4) so
    # the owned-field round-trip is byte-exact when no unrelated edit happened
    # (T-189): byte-exact is valid ONLY then.
    # The LF normalisation below is load-bearing: this file is checked out CRLF,
    # so the here-string carries CRLF while install-terminal.js writes LF. Without
    # it the byte-exact assertion compares line endings the tool never claimed to
    # preserve and fails on correct code (T-198).
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
    $terminalOriginal = $terminalOriginal -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($terminalSettings, $terminalOriginal, (New-Object System.Text.UTF8Encoding($false)))
    $terminalBefore = [System.IO.File]::ReadAllBytes($terminalSettings)

    & node "$root\tools\install-terminal.js" --settings $terminalSettings --palette "$root\themes\goldendefault.json" 2>&1 | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'terminal fixture apply exits successfully'
    $terminalApplied = Get-Content $terminalSettings -Raw | ConvertFrom-Json
    Assert-True ($terminalApplied.profiles.defaults.font.face -eq 'Terminus (TTF) for Windows') 'terminal uses the fixed-width console-safe font'
    Assert-True ($terminalApplied.profiles.defaults.font.size -eq 12) 'terminal keeps the Vintage 12px font size'
    Assert-True ($terminalApplied.profiles.defaults.antialiasingMode -eq 'aliased') 'terminal keeps aliased rendering'
    Assert-True ($terminalApplied.profiles.defaults.historySize -eq 9000) 'terminal guarantees 9000-line scrollback (historySize floor)'
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
    $hsProp = $afterOwn.profiles.defaults.PSObject.Properties['historySize']
    Assert-True (-not $hsProp) 'terminal ownership revert restores the original historySize'
    Assert-True ($afterOwn.startOnUserLogin -eq $true) 'terminal ownership revert PRESERVES the unrelated user edit (startOnUserLogin)'
    Assert-True (@($afterOwn.profiles.list | Where-Object { $_.name -eq 'User-added profile' }).Count -eq 1) 'terminal ownership revert PRESERVES a user-added profile'
    Assert-True (@($afterOwn.actions).Count -eq 1) 'terminal ownership revert PRESERVES a user-added actions block'
    Assert-True (-not (Test-Path ($terminalSettings + '.wintage.bak'))) 'terminal ownership revert consumes its backup'

    Assert-True ($installCode -match '\$CONSOLE_FONT\s*=\s*''Terminus') 'conhost uses the same fixed-width console-safe font'
    Assert-True ($installCode -notmatch '\$CONSOLE_FONT\s*=\s*''Verdana''') 'conhost no longer forces proportional Verdana'
} finally {
    if (Test-Path $terminalRoot) { Remove-Item $terminalRoot -Recurse -Force }
    if ($null -eq $savedWintageAppData) { Remove-Item Env:\WINTAGE_APPDATA -ErrorAction SilentlyContinue }
    else { $env:WINTAGE_APPDATA = $savedWintageAppData }
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

# paths.json has two writers (GUI + install.ps1) and one canonical key set. The GUI
# rebuilding the file from its own $PATH_TARGETS deleted every CLI-owned key on an
# unrelated folder pick, so a remembered portable-browser root or WorkBuddy install
# vanished without anyone touching it (T-196). Behavioural, not textual: the real
# function is lifted out of the GUI and run against a temp preferences file, because
# a regex asserting "it looks like it merges" is what let the wipe ship.
Assert-True ($guiSource -match "\`$MY_APP_KEYS = @\('codenomad', 'workbuddy'") 'GUI groups WorkBuddy with the portable/source apps'
$pathsFixture = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-paths-" + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $pathsFixture -Force | Out-Null
    $pathsFixtureFile = Join-Path $pathsFixture 'paths.json'
    $pathsFixtureCustom = Join-Path $pathsFixture 'custom-checkout'
    New-Item -ItemType Directory -Path $pathsFixtureCustom -Force | Out-Null
    $seedJson = '{"codenomad":"C:\\cn","workbuddy":"C:\\wb","portable":"C:\\pb","customapp":"C:\\stale","goneapp":"C:\\gone"}'
    [System.IO.File]::WriteAllText($pathsFixtureFile, $seedJson, (New-Object System.Text.UTF8Encoding($false)))

    $fnEnd2 = $guiSource.IndexOf("`n}", $saveStart)
    $fnText = if ($saveStart -ge 0 -and $fnEnd2 -gt $saveStart) { $guiSource.Substring($saveStart, $fnEnd2 - $saveStart + 2) } else { '' }
    $harnessLines = @(
        "`$PATH_TARGETS = @('customapp', 'goneapp')",
        ". '$root\desktop\modules\json-doc.ps1'",
        "`$script:pathsFile = '$pathsFixtureFile'",
        "`$script:customPaths = @{ 'customapp' = '$pathsFixtureCustom' }",
        $fnText,
        'if (-not (Save-CustomPaths)) { exit 3 }'
    )
    $harnessFile = Join-Path $pathsFixture 'save-paths-harness.ps1'
    [System.IO.File]::WriteAllText($harnessFile, ($harnessLines -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
    $prevEap2 = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $harnessFile 2>&1 | Out-Null
    $harnessCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEap2
    Assert-True ($harnessCode -eq 0) 'GUI custom-path save reports success on a writable preferences file'
    $savedPaths = [System.IO.File]::ReadAllText($pathsFixtureFile) | ConvertFrom-Json
    Assert-True ($savedPaths.codenomad -eq 'C:\cn') 'GUI save preserves the CLI-owned codenomad path'
    Assert-True ($savedPaths.workbuddy -eq 'C:\wb') 'GUI save preserves the CLI-owned workbuddy path'
    Assert-True ($savedPaths.portable -eq 'C:\pb') 'GUI save preserves the CLI-owned portable-browser root'
    Assert-True ($savedPaths.customapp -eq $pathsFixtureCustom) 'GUI save writes its own key from live state'
    Assert-True ($savedPaths.PSObject.Properties.Name -notcontains 'goneapp') 'GUI save still drops one of its own keys whose folder is gone'
} finally {
    if (Test-Path $pathsFixture) { Remove-Item $pathsFixture -Recurse -Force }
}

Write-Host "
--- Manifest Field Typing Across Hosts (T-199) ---" -ForegroundColor Cyan
# PowerShell 6+ retypes any timestamp-looking JSON string into [datetime], so the
# manifest's own `applied` field came back as an object there and the schema gate
# rejected it: on pwsh 7 EVERY target failed with "applied: not a string" before
# doing any work. Asserted at the type level rather than by host, so the gate holds
# whichever interpreter runs this file.
. "$root\desktop\modules\common.ps1"
$typedManifest = [pscustomobject]@{
    terminal = [pscustomobject]@{
        palette        = 'goldendefault'
        path           = 'C:\dummy\settings.json'
        appVersion     = '1.27.0'
        payloadVersion = '1.27.0'
        applied        = [datetime]::SpecifyKind([datetime]'2026-08-19T12:00:00', 'Utc')
        items          = @([pscustomobject]@{ path = 'C:\dummy\settings.json'; applied = [datetime]::SpecifyKind([datetime]'2026-08-19T12:00:00', 'Utc') })
    }
}
Assert-True (@(Test-ManifestSchema $typedManifest).Count -gt 0) 'schema still rejects a date-typed applied field before normalisation'
$normalised = ConvertTo-ManifestJsonStrings $typedManifest
Assert-True ($normalised.terminal.applied -is [string]) 'manifest read normalises a date-typed applied field to a string'
Assert-True ($normalised.terminal.applied -eq '2026-08-19T12:00:00Z') 'normalised applied keeps the ISO-8601 UTC shape the writer uses'
Assert-True ($normalised.terminal.items[0].applied -is [string]) 'multi-item entries are normalised too'
Assert-True (@(Test-ManifestSchema $normalised).Count -eq 0) 'a normalised manifest passes the schema gate'
if (Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue) {
    $prevEap3 = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $pwshList = (& pwsh -NoProfile -ExecutionPolicy Bypass -File "$root\desktop\install.ps1" 2>&1 | Out-String)
    $pwshCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEap3
    Assert-True ($pwshCode -eq 0 -and $pwshList -notmatch 'manifest schema invalid') 'install.ps1 lists targets under PowerShell 7 without a schema failure'
}

Write-Host "
--- Tool Regression Suites (T-191 P1#14 single entrypoint) ---"
# This file is the CANONICAL gate: release.ps1 runs only this, so every tool
# suite must be reachable from here or a release can ship a broken transaction
# path while the theme gates stay green.
$toolSuites = @(
    @{ Name = 'test-reapply.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-reapply.ps1"' },
    @{ Name = 'test-freebuff.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-freebuff.ps1"' },
    @{ Name = 'test-ownership.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-ownership.ps1"' },
    @{ Name = 'test-electron-state.js'; Cmd = 'node "{0}\tools\test-electron-state.js"' },
    # T-231: these five existed and passed but were reachable from NOTHING -- not
    # from here and not from release.ps1 -- so the contracts they pin (the
    # dir-prestate snapshot shape, Terminal's recorded-set health + the
    # keep/finalize recovery ordering, recovery consumption ordering, the install
    # epoch, portable-Electron path precedence) could regress through a release
    # with every wired gate green. A suite nobody runs is documentation.
    @{ Name = 'test-dir-prestate.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-dir-prestate.ps1"' },
    @{ Name = 'test-terminal-recorded-set.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-terminal-recorded-set.ps1"' },
    @{ Name = 'test-recovery-consumption.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-recovery-consumption.ps1"' },
    @{ Name = 'test-epoch.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-epoch.ps1"' },
    @{ Name = 'test-resolve-portable.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-resolve-portable.ps1"' },
    # CORE-001 (SRC-004): Apply -> Revert must return the Windows Terminal
    # document to its pre-Apply state. Three representation losses made that
    # false on the SUCCESS path (exit 0 both halves), so nothing red ever
    # appeared: an explicit null was deleted, a legacy top-level profiles ARRAY
    # came back as an object, and a user's own scheme named Wintage was removed.
    @{ Name = 'test-terminal-ownership.js'; Cmd = 'node "{0}\tools\test-terminal-ownership.js"' },
    # W2-001/W2-002 (SRC-004): recovery-lifecycle contracts for the windows-theme
    # and OBS helpers. One deleted the file it had just told Windows to activate;
    # the other's recovery parser reinterpreted malformed JSON as legacy INI and
    # its case-sensitive reads snapshotted OBS's own lowercase theme key as
    # absent, so Revert deleted a real user selection.
    @{ Name = 'test-recovery-lifecycle.js'; Cmd = 'node "{0}\tools\test-recovery-lifecycle.js"' },
    # CORE-005 + W2-004/005/006/007 (SRC-004): the transaction boundary and the
    # honesty of what a rollback claims. Every one of these was invisible on the
    # happy path -- a present-empty INI key deleted on Revert, a mutation that
    # happened OUTSIDE the transaction its snapshot was taken for, a rollback
    # whose native command could fail unnoticed under an "exact pre-operation
    # state" message, a -WhatIf that wrote persistent recovery, and two
    # paths.json writers that could each lose the other's key while both
    # reported success.
    @{ Name = 'test-transaction-boundary.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-transaction-boundary.ps1"' },
    # SRC-005:R009 (W2-005 windows half): Restore-WindowsPreState is a verified
    # rollback primitive. The pre-fix helper suppressed every owned registry/file
    # failure and accepted a successful ShellExecute as proof CurrentTheme came
    # back, so its caller claimed exact restoration over an unchecked rollback.
    # This gate drives the primitive against a scratch HKCU key and a temp
    # themes dir with the activation dispatch stubbed: deletion/registry/
    # false-activation failures must end INCOMPLETE with the resource named,
    # and only a fully verified restore may claim exact restoration.
    @{ Name = 'test-windows-prestate.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-windows-prestate.ps1"' },
    # SRC-005:R008 (W2-004): recovery artifacts and their provenance are part of
    # the rollback authority, so a crash mid-write must never leave a partial
    # authoritative file on its final name. The gate drives Write-Utf8Atomic /
    # Copy-FileAtomic / Write-RecoveryProvenance / Sync-SourceBackup directly:
    # rejected or interrupted writes keep the prior authoritative content, no
    # orphan .wintage-tmp-* survives, invalid sidecars fail closed, and a rebase
    # takes non-owned content from the live source while keeping the OLD pristine
    # owned tokens.
    @{ Name = 'test-atomic-recovery.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-atomic-recovery.ps1"' },
    # CORE-004 (SRC-005:R004): the imported-theme freshness gate must be a REAL
    # comparison under the exact release invocation. The pre-fix --check printed
    # "freshness check skipped" and exited 0 with no FastPrompter checkout, so a
    # hand-edited imported pack passed the gate that advertises it cannot. The
    # gate now verifies each imported pack against the committed sha256
    # fingerprint set; a hand-edit, a missing pack, or a missing fingerprint
    # file FAILS - never a skip.
    @{ Name = 'test-import-freshness.js'; Cmd = 'node "{0}\tools\test-import-freshness.js"' },
    # PERF-002/003/004/006/007 (SRC-004): the repaint and injection lanes must be
    # bounded by the budgets they advertise. Every finding here was invisible from
    # outside -- the theme looked right and the machine just cost more -- so the
    # gate counts primitive calls (getComputedStyle, querySelectorAll, insertCSS,
    # requestAnimationFrame) against the real source rather than asserting shape.
    @{ Name = 'test-perf-lanes.js'; Cmd = 'node "{0}\tools\test-perf-lanes.js"' },
    # PERF-001 (SRC-004): Electron recovery must not scale in MEMORY with the size
    # of the application it protects. The pre-fix code stacked whole-binary
    # Buffers across both transaction layers (+192 MiB RSS for a 64 MiB archive);
    # recovery is now a durable on-disk vault plus size+digest identity. Builds
    # 16/64/256 MiB fixtures and measures the child's own peak RSS, then proves
    # every failure seam still restores those large files byte-exactly.
    @{ Name = 'test-perf-recovery.js'; Cmd = 'node "{0}\tools\test-perf-recovery.js"' },
    # SRC-006:R004: the generic VS Code-family recovery epoch must fail closed on
    # corrupt/incomplete authority and, in replaced mode, restore the pre-Wintage
    # tree BYTE-EXACTLY from the retired tombstone (the retirement rename moves
    # pristine with the epoch). Also pins: two-cycle baselines stay independent,
    # a failed manifest transition after retirement restores BOTH the destination
    # and the epoch (retry stays possible), and an empty pristine is a legitimate
    # user state that restores to an empty directory.
    @{ Name = 'test-vscode-recovery.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-vscode-recovery.ps1"' },
    # SRC-006:R005: the Reapply child must re-validate the manifest intent its
    # parent planned from UNDER the target lock, and skip with ZERO mutation
    # when a concurrent Revert or palette change won the plan->lock race. The
    # race fixture parks the child on a held target lock (deterministic seam,
    # no sleeps) and completes the Revert while it waits.
    @{ Name = 'test-reapply-intent.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-reapply-intent.ps1"' },
    # SRC-006:R006: the GUI logon-task checkbox must not mutate the scheduled
    # task as a side effect of opening the installer, and a failed task command
    # must never dispatch the INVERSE command. The gate AST-extracts the real
    # handler and toggle from WintageInstaller.ps1 and drives them through a
    # real WinForms.CheckBox (authentic event wiring, no desktop automation).
    @{ Name = 'test-logon-task-gui.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-logon-task-gui.ps1"' },
    # Batch-timer crash-dialog gate: the Add_Tick delegate is re-bound against
    # the SCRIPT scope when the pump invokes it, so a tick written against
    # Start-BatchJob's function locals reads them as null and dies with
    # "You cannot call a method on a null-valued expression" on every 250ms
    # tick (the user-visible JIT dialog). The gate AST-extracts the REAL
    # Start-BatchJob, drives it through a real Forms.Timer on a real message
    # pump with ThreadException hooked, and proves null output lines and a
    # throwing completion handler are contained.
    @{ Name = 'test-batch-timer-gui.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\\tools\\test-batch-timer-gui.ps1"' },
    # R010 (SRC-007:W2-005) DETERMINISTIC red control. Builds TEMPORARY mutants
    # of the CURRENT fixed GUI (never the shipped source, never tied to git
    # HEAD -- a HEAD oracle goes blind once the fix is committed) that each
    # reintroduce one R010 lifecycle defect: A active-close refusal removed,
    # B exactly-once Consumed ownership guard removed, C close-safe Cleared
    # transition removed. The behavioural harness must reproduce every defect;
    # the matrix fails if the R010 assertions ever stay green on defective
    # source.
    @{ Name = 'test-batch-timer-gui.ps1 -RedControl'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-batch-timer-gui.ps1" -RedControl' },
    @{ Name = 'test-batch-streaming-gui.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\\tools\\test-batch-streaming-gui.ps1"' },
    @{ Name = 'test-batch-streaming-gui.ps1 -RedControl'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\\tools\\test-batch-streaming-gui.ps1" -RedControl' },
    # SRC-006:R007: a palette repaint of an already-themed Electron app must not
    # pay archive-sized I/O at either transaction layer. The gate instruments the
    # real tool through a NODE_OPTIONS preload that logs every byte read and
    # proves ZERO full-archive reads on healthy relocated repaints (<64KiB in
    # in-place mode, where a bounded .bak header read is legitimate), plus
    # sidecar-exact rollback on injected failure and an intact moved archive
    # after a parent manifest-commit failure.
    @{ Name = 'test-electron-repaint.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-electron-repaint.ps1"' },
    # SRC-006:R010: force-sweep continuation slices must bound ROOT-level work
    # (registry pruning, hover-sheet strips, workset construction, iteration,
    # completion detection) as well as element work. The gate slices the REAL
    # runSweeper into a sandbox with 2000 instrumented fake roots and tiny
    # budgets: no slice may serve more roots than the root budget, the cursor
    # must advance monotonically, every root must eventually be served,
    # detached roots must vanish, and the lap must end with all traversal
    # state dropped.
    @{ Name = 'test-force-root-budget.js'; Cmd = 'node "{0}\tools\test-force-root-budget.js"' },
    # CORE-010: a force request must continue through the whole persistent root
    # lap, not stop after the first budgeted window. The oracle drives the real
    # scheduler slice and checks document plus two 6,000-element shadow roots.
    @{ Name = 'test-force-sweep-continuation.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-force-sweep-continuation.ps1"' },
    # PERF-002 (SRC-007:R013): the repainter's style/root/CSSOM work must be
    # budgeted exactly like its DOM element work. The gate extracts the REAL
    # repainter out of wintage.user.js (no stubbed style/CSSOM primitives) and
    # drives it with a lazy indexed 250,000-rule cssRules collection, 25,000
    # instrumented roots, a nested @media/@supports/@layer/keyframes CSSOM, a
    # throwing cssRules getter, a mid-lap ShadowRoot insertion, a same-count
    # stylesheet replacement, a 50,000-rule append and a STYLE text rewrite.
    # It also holds static guards against forceLapWorkset = [document,
    # ...piercedRoots], querySelectorAll('style'), a recursive walkRules, an
    # unbudgeted appended-rule loop and a premature sheetSeen.set, and proves
    # both historical defects reproduce on TEMPORARY in-memory source mutants
    # (RED A full root snapshot, RED B recursive unbounded rule walk) while
    # asserting each mutation actually applied.
    @{ Name = 'test-repainter-budget.js'; Cmd = 'node "{0}\tools\test-repainter-budget.js"' },
    # PERF-001 (audit/7.md, SRC-018:R013): direct CSSOM mutations need not
    # create a DOM MutationObserver record, so insertRule/deleteRule/replaceSync
    # used to advance a per-sheet generation token while setting NO scheduler
    # debt, and async replace() stamped the new generation onto the OLD rules on
    # Promise creation. This gate drives the REAL wrappers and requires that
    # every successful mutation sets stylesDirty and arms ONE coalesced
    # continuation, that replace() invalidates only on fulfillment, returns the
    # ORIGINAL Promise, treats rejection as a no-op, and preserves native return
    # values/exceptions; 1000 synchronous mutations must not storm the timer.
    @{ Name = 'test-perf-cssom.js'; Cmd = 'node "{0}\tools\test-perf-cssom.js"' },
    # PERF-003 (audit/7.md, SRC-018:R015): suspendRepainter is a COMPLETE
    # permanent scheduler-state disposal boundary. A page that tripped the
    # breaker used to keep forceLapDeferredRoots / styleLapDeferredRoots /
    # activeStyleTask / styleCursorRoot / styleCursorRootIterator alive forever
    # (no future pass to drain them). This gate drives the REAL suspendRepainter
    # body, asserts every strong owner is emptied/null and a partial
    # activeStyleTask cannot continue, and structurally requires a future strong
    # scheduler Set to be disposed or fail.
    @{ Name = 'test-perf-suspend.js'; Cmd = 'node "{0}\tools\test-perf-suspend.js"' },
    # PERF-004 (audit/7.md, SRC-018:R016): GoodEmoji start() installed an
    # unconditional 2,000 ms body-wide sweep beside a MutationObserver that
    # already covered the same subtree. This gate proves no fixed interval
    # exists, 60s idle causes zero global scans, observer intake still covers
    # added emoji / attribute changes / characterData, a route change coalesces
    # to ONE bounded scan, and stop()/restart leaves one observer and no orphan
    # timer. A setInterval trap makes any reintroduced heartbeat throw.
    @{ Name = 'test-goodemoji.js'; Cmd = 'node "{0}\tools\test-goodemoji.js"' },
    # Audit wave imp-vacterro-wintage-20260927-2 (Core seat antigravity-01, RUN 1).
    # These two were previously release-gate-EXISTENCE checks only, so the
    # regressions they cover shipped inside a green Run-Tests run. They are
    # registered as executed suites now: test-spa-exclude.js carries the
    # high-churn-host classification gate (T-325) and the body transparency
    # check (T-336); test-perf-bounded.js carries the floating-surface media
    # gate (T-326) and the button-descendant-wipe gate (T-331).
    @{ Name = 'test-spa-exclude.js'; Cmd = 'node "{0}\tools\test-spa-exclude.js"' },
    @{ Name = 'test-perf-bounded.js'; Cmd = 'node "{0}\tools\test-perf-bounded.js"' },
    # PERF-005 (audit/7.md, SRC-018:R017): GoodEmoji matchSrc fell back to
    # Object.entries(codeToItem) and up to three String.includes per code for
    # EVERY unmatched image (2,880,000 includes for 1,000 URLs, plus a fresh
    # ~960-entry array per call). This gate proves matching is now proportional
    # to URL length, independent of the mapping-table size (with a ~10x mutant
    # table), preserves every mapped base/tone/variation/gender and legacy
    # delimiter shape, and adds no substring-prefix false positive.
    @{ Name = 'test-goodemoji-matchsrc.js'; Cmd = 'node "{0}\tools\test-goodemoji-matchsrc.js"' },
    # R015 / PERF-004 (SRC-007, T-246): portable browser discovery cache and
    # bounded preference scanning. It pins that a warm cache answers a status
    # refresh with ZERO recursive enumeration over the remembered PortableRoot
    # and the identical candidate set; that a walk happens only on a cold or
    # corrupt cache, a changed root, an invalidated cached candidate or an
    # explicit -Rescan; that a vanished browser is dropped rather than invented;
    # that preference matching is a chunked bounded search still exact for both
    # the escaped and slash forms; and that an unchanged fingerprint serves the
    # profile answer without opening the file. Two TEMPORARY source mutants
    # reproduce the old defects (RED A walk-on-every-refresh, RED B re-read on
    # every refresh) and assert each mutation actually applied.
    @{ Name = 'test-browser-cache.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-browser-cache.ps1"' },
    # W2-001 (SRC-007:R006): Total Commander recovery-format discriminator.
    # Corrupt/truncated current-format recovery JSON must fail closed with zero
    # live mutation, manifest preserved, backup preserved; genuine legacy whole-file
    # INI is positively identified and dynamic recent-file filter colors are migrated.
    @{ Name = 'test-totalcmd-recovery.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-totalcmd-recovery.ps1"' },
    # W2-001 (SRC-014): Notepad++ and Cinema 4D first-touch ownership/recovery.
    # Both targets used an ephemeral rollback snapshot as if it were persistent
    # ownership evidence: Notepad++ restored only Wintage.xml and wildcard-deleted
    # every Wintage-*.xml on Revert (user files included), Cinema 4D recursively
    # deleted whatever occupied schemes\Wintage, and both wrote recovery.json only
    # after the manifest commit. The gate drives the real installer through
    # Apply -> repaint -> Revert with byte-exact fixtures and deterministic seams
    # (alias-write failure, recovery-promotion failure, live-mutation failure,
    # manifest-commit failure, crash-after-commit) and asserts restoration of the
    # complete pre-operation set plus persistent recoverability.
    @{ Name = 'test-first-touch-recovery.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-first-touch-recovery.ps1"' },
    # CORE-003 (SRC-007:R003): Windows theme mutation rollback boundary.
    # Encapsulates helper file creation, AccentColorInactive write, activation,
    # polling/retry, and manifest update inside a unified transaction.
    # Rollback restores registry and theme files on mid-write, accent write failure,
    # activation dispatch throw, activation timeout, or manifest commit failure.
    @{ Name = 'test-windows-theme-boundary.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-windows-theme-boundary.ps1"' },
    # W2-004 (SRC-007:R009): Custom batch generation race.
    # The batch must own check+dispatch as one window and every custom publish
    # must own the same mutex; emitted files must be staged so no reader sees
    # a half-published tree.
    @{ Name = 'test-batch-generation.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-batch-generation.ps1"' },
    # W2-004 (SRC-007:R009) red-control suite. A regression matrix that cannot
    # prove its own gates still fail defective source is documentation, not a
    # gate: this suite reintroduces each historical release defect onto a
    # TEMPORARY mutated copy (never the shipped module) and must reproduce all
    # of them - RED A node token-less release leak, RED B MetadataWritten
    # malformed-release deletion, RED C age-only stealing of a live holder.
    # It exits 0 only when every defect is reproduced; if the real gates ever
    # go green on defective source, this suite goes red and the matrix fails.
    @{ Name = 'test-genlock-redcontrol.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-genlock-redcontrol.ps1"' },
    # W2-006 (SRC-007:R011): path-preference PREREQUISITE ordering. A validated
    # explicit portable path must be persisted BEFORE any application/stage
    # mutation; a forced persistence failure (paths.lock contention) must exit
    # nonzero with an accurate error while application bytes, manifest and
    # recovery lifecycle stay byte-identical; the retry records preference and
    # manifest; a later resolution without the flag finds the remembered path.
    @{ Name = 'test-path-preference-ordering.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-path-preference-ordering.ps1"' },
    # T-250 (HUNT-001): every locale must carry the SAME key set as en.json. The
    # GUI's T() loader overlays a locale on the English base and silently falls
    # back to English for any missing key, so a lagging locale renders English
    # with no crash and no warning -- invisible at runtime. 33 files, 68 keys.
    @{ Name = 'test-locale-parity.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-locale-parity.ps1"' },
    @{ Name = 'test-locale-parity.ps1 -RedControl'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-locale-parity.ps1" -RedControl' },
    # T-311: translated desktop READMEs must mirror the English source's
    # target/section coverage. Uses language-invariant code-literal anchors
    # (processexplorer/notepadplusplus/cinema4d/terminal-font.json) so a
    # translated file that lags a new target is caught. Core owns et/ru/ded
    # (enforced); the 29 producer locales are reported, not failed.
    @{ Name = 'test-readme-target-parity.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-readme-target-parity.ps1"' },
    @{ Name = 'test-readme-target-parity.ps1 -RedControl'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-readme-target-parity.ps1" -RedControl' },
    # T-312: accepted-debt record bytes were mutable through the generic journal
    # CAS, so a record's evidence can drift under it and a rebind can be booked
    # under an operation name the engine never implemented. The live pass drives
    # the protocol install's OWN accepted_debt.load_record (schema, integrity
    # digest, lineage, rule binding) and then re-derives the settled journal
    # chain -- contiguous before/after links, terminal hash == live bytes, every
    # writer a real engine operation. Evidence-line drift and unregistered
    # writers are REPORTED, not fatal: the integrity digest already proves the
    # record untampered, so drift is LOG rotation, not corruption. The self-test
    # is the red control -- it tampers with one thing at a time and proves each
    # check fires.
    @{ Name = 'accepted-debt-provenance.py'; Cmd = 'python "{0}\tools\accepted-debt-provenance.py" --project-root "{0}"' },
    @{ Name = 'accepted-debt-provenance.py --self-test'; Cmd = 'python "{0}\tools\accepted-debt-provenance.py" --self-test' },
    # T-310: key parity says nothing about VALUES. This suite pins two Core-locale
    # value defects the parity gate cannot see: double-escaped multiline strings
    # (parsed "\r\n" rendered as literal backslash text) and terminal-font keys
    # copied verbatim from English. Core owns et/ru/ded; producer locales unchecked.
    @{ Name = 'test-locale-semantic.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-locale-semantic.ps1"' },
    @{ Name = 'test-locale-semantic.ps1 -RedControl'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-locale-semantic.ps1" -RedControl' },
    # T-257 (SRC-013): scenario presets are UI state, never a second execution
    # engine. The suite pins the preset contract in tools/test-presets.ps1:
    # pack + custom-snapshot round-trip, strict schema (unknown schemaVersion,
    # unsafe id/path traversal, duplicate ids, incomplete token snapshot), the
    # unavailable-target-is-retained rule, fail-safe atomic storage (a rejected
    # save leaves the previous bytes, a failed rename keeps the original), and
    # the static proof that the preset module launches no child install process.
    # Its -RedControl is a separate entry: three mutant module copies each
    # disabled guard and prove the defect passes through.
    @{ Name = 'test-presets.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-presets.ps1"' },
    @{ Name = 'test-presets.ps1 -RedControl'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-presets.ps1" -RedControl' },
    # CORE-004 (SRC-018): the GUI-owned remembered-path set was zeroed out while
    # discovery, selection, persistence and batch forwarding still assumed it was
    # non-empty, so zcode/notepadplusplus/cinema4d could not be pointed at a
    # custom folder from the GUI. The gate evaluates the REAL declaration block
    # and drives the REAL Load/Save/Get-BatchArgs functions against isolated
    # paths.json fixtures: empty state unresolved, chosen folders survive a
    # reload, CLI-owned and unknown keys survive byte-for-value, vanished
    # folders drop on load, and each GUI-owned path forwards under its canonical
    # install.ps1 parameter.
    @{ Name = 'test-gui-paths.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-gui-paths.ps1"' },
    # T-309: MPC-HC OSD face resolved by ONE rule across surfaces. -List used to
    # hardcode the literal 'Verdana' while apply and health went through
    # Get-WintageFontFace, so a Verdana_m1 machine read "found, not themed" on
    # list yet "themed" on apply+health. The gate proves all three surfaces route
    # through Get-WintageFontFace and agree the verdict in both font worlds; the
    # RED control reintroduces the literal and confirms the list assertions fail.
    @{ Name = 'test-mpchc-font-parity.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-mpchc-font-parity.ps1"' },
    @{ Name = 'test-mpchc-font-parity.ps1 -RedControl'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-mpchc-font-parity.ps1" -RedControl' },
    # T-307: every T('Key') the GUI uses must exist in en.json. T() falls back to
    # the raw key name (i18n.ps1:41), so a code-used key with no table entry
    # renders its own name on screen -- exactly how the nine preset-control keys
    # shipped unlocalised past the parity gate (which only compares locales to
    # each other). The RED control reintroduces a used-but-absent key.
    @{ Name = 'test-locale-keys.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-locale-keys.ps1"' },
    @{ Name = 'test-locale-keys.ps1 -RedControl'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-locale-keys.ps1" -RedControl' },
    @{ Name = 'test-dwm-recovery.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-dwm-recovery.ps1"' },
    # Audit wave imp-vacterro-wintage-20260927-2 (Core seat antigravity-01, RUN 1):
    # T-321/T-327/T-328/T-330/T-332/T-333/T-334/T-337/T-338. Registered here
    # because every defect it guards was invisible to a green Run-Tests run.
    @{ Name = 'test-audit-20260927-fixes.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-audit-20260927-fixes.ps1"' },
    @{ Name = 'test-wintage-appdata-root.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-wintage-appdata-root.ps1"' },
    @{ Name = 'test-tf-lazy-init.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-tf-lazy-init.ps1"' },
    @{ Name = 'test-tf-async-apply.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-tf-async-apply.ps1"' },
    @{ Name = 'test-fb-sound-async.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-fb-sound-async.ps1"' },
    @{ Name = 'test-log-append-bound.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-log-append-bound.ps1"' },
    # SRC-023 (Process Explorer): the target's owned-value contract must be one
    # canonical set; its 12-name base list beside a 24-name write map left the
    # *Dark values unowned, so Revert could never restore them. The suite proves
    # map == PE_COLOR_VALUES, first-touch recovery captures every owned value,
    # repaint keeps it, mid-apply failure restores every touched value, Revert
    # restores pre-existing/absent/unrelated state exactly, health detects drift,
    # running refusal and -WhatIf are mutation-free, the remembered folder is a
    # canonical paths.json key, and -Target all includes the target.
    @{ Name = 'test-processexplorer.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-processexplorer.ps1"' },
    # T-283 (SRC-026): the TERMINAL FONTS subsystem. One focused suite covers the
    # catalog (20 bundled families, unique slugs/paths, every file+license exists,
    # every sha256 matches, one pinned source per family), the preference schema
    # (missing -> backward-compatible default, round-trip, malformed fails closed
    # leaving the file untouched, atomic write, range validation), private preview
    # (a bundled UNINSTALLED face resolves via PrivateFontCollection with ZERO
    # system registration and measures fixed-pitch), the Windows Terminal helper
    # (writes the selected family/size/rendering, preserves unrelated settings,
    # Revert restores the exact owned values, a malformed preference is refused
    # with zero mutation), the conhost guard (face comes from the preference and
    # an unusable face is refused before mutation), and the GUI tab (data-driven
    # three-tab strip, exactly one panel visible, private fonts disposed on
    # close). -RedControl mutates the catalog hash, the conhost preference
    # resolution and the single-visible-tab rule and requires each to go red.
    @{ Name = 'test-terminal-fonts.js'; Cmd = 'node "{0}\tools\test-terminal-fonts.js"' },
    @{ Name = 'test-terminal-fonts.js --red-control'; Cmd = 'node "{0}\tools\test-terminal-fonts.js" --red-control' },
    # The tab BEHAVIOUR (not just its presence): AST-extracts the REAL
    # Update-TabButtons / Set-ActiveTab and the REAL tab table, binds them to
    # genuine WinForms Controls, and proves three reachable tabs, exactly one
    # visible panel, a distinct active style, refusal of an unknown key, and a
    # table that survives switching (no lost selection state).
    @{ Name = 'test-terminal-fonts-gui.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-terminal-fonts-gui.ps1"' }
    @{ Name = 'test-tf-apply-results.js'; Cmd = 'node "{0}\tools\test-tf-apply-results.js"' },
    @{ Name = 'test-tf-apply-results.js --red-control'; Cmd = 'node "{0}\tools\test-tf-apply-results.js" --red-control' }
)
foreach ($s in $toolSuites) {
    $invokeLine = ($s.Cmd -f $root)
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $suiteOut = (& cmd /c $invokeLine 2>&1 | Out-String)
    $suiteCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    if ($suiteCode -eq 0) {
        Assert-True $true "$($s.Name) suite exits 0"
    } else {
        Assert-True $false "$($s.Name) suite exits 0"
        $tails = @($suiteOut -split "`r?`n" | Where-Object { $_ -match 'FAIL|failure|Error' } | Select-Object -Last 4)
        foreach ($line in $tails) { Write-Host "       $line" -ForegroundColor Red }
    }
}
# Do the JS gates exist? Every gate release.ps1 runs must be reachable as a file,
# so a renamed/removed gate fails this check instead of being silently skipped.
$releaseCode = [System.IO.File]::ReadAllText("$root\release.ps1")
Assert-True ($releaseCode -notmatch 'git\s+-C\s+[$]PSScriptRoot\s+checkout\s+--\s+\.') 'release rollback does not discard worktree from mutable HEAD'
Assert-True ($releaseCode -match 'stash create') 'release snapshots the pre-release tracked state'
Assert-True ($releaseCode -match 'restore "--source=[$]snapshotWorktree" --worktree') 'release rollback restores worktree from immutable snapshot'
Assert-True ($releaseCode -match 'restore "--source=[$]snapshotIndex" --staged') 'release rollback restores index from immutable snapshot'
$gateRefs = [regex]::Matches($releaseCode, "Join-Path [$]PSScriptRoot '([^']+\.js)'") |
    ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
foreach ($g in $gateRefs) {
    Assert-True (Test-Path "$root\$g") "release gate exists: $g"
}

Write-Host "
======================="
if ($script:errors -gt 0) {
    Write-Host "TESTS FAILED ($script:errors errors)" -ForegroundColor Red
    exit 1
} else {
    Write-Host "ALL TESTS PASSED!" -ForegroundColor Green
    exit 0
}
