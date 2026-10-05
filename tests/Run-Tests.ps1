$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path $PSScriptRoot -Parent
$script:errors = 0

# T-414: the verdict of this file was not reproducible and a red run lost the
# name of what failed. One tree, two runs, two verdicts -- the browser-cache live
# smoke failed under full-suite load and passed twice standalone -- and the
# second run could not be compared with the first because nothing recorded which
# tree each had judged. The tail of a red run said 'TESTS FAILED (1 errors)' and
# the failing assertion's name existed only in the part of the output the reader
# had already let scroll away.
#
# So: identify the tree before judging it, keep the transcript, and re-print
# every failing check at the exit. The identity is the head commit plus a
# fingerprint of the worktree delta -- the dirty path list AND the diff text,
# because a name list cannot tell an edited file from an untouched one -- with
# ignored files excluded, so two runs can be compared without trusting that the
# tree was untouched. It is computed BEFORE the run and never after: the run
# itself writes (this transcript, .saipen/locks), and a fingerprint taken at the
# end would report those writes as if the tree had moved.
$script:failures = @()
$script:runHead = 'no-git'
$script:runFingerprint = 'no-git'
$script:transcript = $null
try {
    $prevEapId = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $headOut = @(& git -C $root rev-parse --short HEAD 2>$null)
    $headCode = $LASTEXITCODE
    $porcelain = @(& git -C $root status --porcelain=v1 -uall 2>$null)
    $statusCode = $LASTEXITCODE
    # Paths are not enough: git status names which files are dirty and never
    # what changed inside them, so an edit to an already-dirty file would leave
    # the identity untouched and two different trees would compare equal. The
    # diff text is the content half of the fingerprint. Measured on this tree:
    # 3.4 MB in 0.8s, which is why it is the whole-diff form and not a per-file
    # hash of five hundred files.
    $diffText = (& git -C $root diff HEAD 2>$null | Out-String)
    $diffCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEapId
    if ($headCode -eq 0 -and $statusCode -eq 0 -and $diffCode -eq 0 -and $headOut.Count -gt 0) {
        $script:runHead = "$headOut".Trim()
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $payload = ($porcelain -join "`n") + "`n--diff--`n" + $diffText
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
        $hex = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
        $script:runFingerprint = "$($hex.Substring(0, 12))/$($porcelain.Count)path/$([int]($diffText.Length / 1024))k"
    }
} catch {
    # A checkout without git still runs; it just cannot claim an identity.
}
$logDir = Join-Path $root '.saipen\logs'
$logPath = Join-Path $logDir 'run-tests-last.txt'
if ($env:WINTAGE_TEST_NO_TRANSCRIPT -ne '1') {
    # Never fatal: a locked or unwritable log must not decide the verdict.
    try {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        Start-Transcript -Path $logPath -Force | Out-Null
        $script:transcript = $logPath
    } catch { }
}

function Assert-True($condition, $message) {
    if (-not $condition) {
        Write-Host "[FAIL] $message" -ForegroundColor Red
        $script:errors++
        $script:failures += $message
    } else {
        Write-Host "[PASS] $message" -ForegroundColor Green
    }
}

# One exit for every way this file can end, so the identity, the transcript and
# the list of failing checks are the same shape whichever door the run leaves
# by. The two verdict strings are load-bearing and stay literal.
function Exit-Suite([int]$code) {
    if ($script:errors -gt 0) {
        Write-Host "failing checks ($($script:failures.Count)):" -ForegroundColor Red
        foreach ($f in $script:failures) { Write-Host "  - $f" -ForegroundColor Red }
    }
    Write-Host "SUITE VERDICT: head=$($script:runHead) worktree=$($script:runFingerprint) exit=$code errors=$($script:errors) log=$($script:transcript)"
    if ($script:errors -gt 0) {
        Write-Host "TESTS FAILED ($script:errors errors)" -ForegroundColor Red
    } else {
        Write-Host "ALL TESTS PASSED!" -ForegroundColor Green
    }
    if ($script:transcript) { try { Stop-Transcript | Out-Null } catch { } }
    exit $code
}

Write-Host "
--- Testing Generated Build Freshness (T-344) ---" -ForegroundColor Cyan
# The whole node gate layer (the $toolSuites loop, ~40 suites including
# test-chatgpt-2026.js) lives at the BOTTOM of this file. The -WhatIf isolation
# test at :273 needs a fresh desktop/out, so a large wintage.user.js change used
# to make this file die 500 lines short with "desktop/out is out of date" -- a
# message that never mentions a single skipped suite. The run then read as
# "mostly green with one unrelated failure", and a gate that had never executed
# looked like a gate that had passed (TEST-105 S5).
# So check it FIRST, and say what is being skipped when it is stale.
$prevEapFresh = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$freshOut = (& node "$root\tools\build-desktop.js" --check 2>&1 | Out-String)
$freshCode = $LASTEXITCODE
$ErrorActionPreference = $prevEapFresh
Assert-True ($freshCode -eq 0) 'generated desktop/out is fresh (node tools/build-desktop.js --check)'
if ($freshCode -ne 0) {
    Write-Host "       SKIPPING EVERY TOOL SUITE below -- they all read desktop/out and would report on stale output:" -ForegroundColor Red
    foreach ($line in @($freshOut -split "`r?`n" | Where-Object { $_ -match 'STALE|out of date' } | Select-Object -First 5)) {
        Write-Host "       $line" -ForegroundColor Red
    }
    Write-Host "       Fix: node tools/build-desktop.js   (then re-run this file)" -ForegroundColor Red
    Write-Host "
======================="
    Exit-Suite 1
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
    # T-394/T-395 (SRC-063 CORE-001/CORE-002): the red controls for the
    # release-gate derivation itself. Every case is a source STRING, so this
    # gate can be proven to bite without ever editing release.ps1.
    @{ Name = 'test-release-gate-audit.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tests\test-release-gate-audit.ps1"' },
    # T-398 (SRC-063 W2-003): a release that died between the desktop generation
    # and the commit rolled back only the TRACKED store, leaving the ignored
    # desktop/out tree holding the failed run's N+1 payload. This gate builds a
    # throwaway git repo, walks it into the failed-release state, and runs the
    # SHIPPED rollback text (lifted out of release.ps1 with the AST) against it.
    # The RED control re-runs the identical scenario against the verbatim
    # pre-repair rollback and requires the same self-consistency check to fail.
    @{ Name = 'test-release-rollback-split.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-release-rollback-split.ps1"' },
    # T-396 (SRC-063 W2-002): desktop/out is published by swapping a staged
    # generation, so a late target failure cannot leave the tree mixed. This gate
    # builds the real CLI into a throwaway tree twice -- once clean, once with a
    # forced late failure -- and requires that not one target moves. It builds
    # nothing inside the repository.
    @{ Name = 'test-build-desktop-publish.js'; Cmd = 'node "{0}\tools\test-build-desktop-publish.js"' },
    @{ Name = 'test-reapply.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-reapply.ps1"' },
    # W2-004 (SRC-063): the read side preserved unknown manifest keys but the
    # write path rebuilt each entry from nothing, so an older build silently
    # deleted fields a newer one had written. Carries a RED control that splices
    # the verbatim pre-repair Set-ManifestEntry into a COPY of the module
    # directory -- beside its siblings, so the revert is a real one -- and
    # requires the same assertion to fail with the field gone.
    @{ Name = 'test-manifest-forward-compat.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-manifest-forward-compat.ps1"' },
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
        # Audit wave imp-vacterro-wintage-20260927-2 (Core seat antigravity-01, RUN 1).
    # These two were previously release-gate-EXISTENCE checks only, so the
    # regressions they cover shipped inside a green Run-Tests run. They are
    # registered as executed suites now: test-spa-exclude.js carries the
    # high-churn-host classification gate (T-325) and the body transparency
    # check (T-336); test-perf-bounded.js carries the floating-surface media
    # gate (T-326) and the button-descendant-wipe gate (T-331).
    @{ Name = 'test-spa-exclude.js'; Cmd = 'node "{0}\tools\test-spa-exclude.js"' },
    # T-397: a generation loaded over an older one must own the page. Pairs with
    # test-spa-exclude.js, which proves the guard installs ONCE per document;
    # this proves the surviving wrapper then belongs to the NEWEST generation
    # rather than to whichever one installed it.
    @{ Name = 'test-generation-handover.js'; Cmd = 'node "{0}\tools\test-generation-handover.js"' },
    # ChatGPT Web September 2026 shell contract: semantic tokens and stable
    # data hooks replace the retired broad composer / sticky-bottom selectors.
    @{ Name = 'test-chatgpt-2026.js'; Cmd = 'node "{0}\tools\test-chatgpt-2026.js"' },
    @{ Name = 'test-chatgpt-perf-css.js'; Cmd = 'node "{0}\tools\test-chatgpt-perf-css.js"' },
    # T-373 viewport-owner coverage. The two gates above read RULES: they prove
    # the October contracts are present in the sheet ChatGPT actually receives.
    # They cannot see the defect this one exists for, because the defect is not a
    # missing selector -- it is PARENT THEMED / CHILD VIEWPORT OWNER OPAQUE
    # STOCK, where every ancestor contract is present and matching and the page
    # is still stock charcoal. So this one drives real Chromium, injects the
    # resolved sheet AFTER a stock sheet that reproduces the shell, and asks what
    # colour a user actually sees in the centre of the viewport. Four red
    # controls, each cutting one anchored rule out of the shipped sheet and
    # requiring these same assertions to go red. It proves the TOOL and the CSS;
    # acceptance against a signed-in chatgpt.com tab is still a human step.
    @{ Name = 'test-chatgpt-viewport-coverage.js'; Cmd = 'node "{0}\tools\test-chatgpt-viewport-coverage.js"' },
    @{ Name = 'test-inspect-web.js'; Cmd = 'node "{0}\tools\test-inspect-web.js"' },
    @{ Name = 'test-inspect-web-mutations.js'; Cmd = 'node "{0}\tools\test-inspect-web-mutations.js"' },
    # T-359: the injector that puts the product's own CHATGPT_FAST_CSS on a live
    # ChatGPT tab without Tampermonkey, plus the two live defects it exists to make
    # reachable -- <html> held to the token paintRoot actually writes inline, and the
    # composer root judged together with its sibling. All three were found on a live
    # page and none of them is visible in the shipped source, so all three need bite
    # controls or a future edit can undo them silently.
    @{ Name = 'test-inject-wintage-web.js'; Cmd = 'node "{0}\tools\test-inject-wintage-web.js"' },
    # The shared CDP transport is the one place a diagnostic can hang forever,
    # and no offline suite ever notices: an unbounded Promise only misbehaves
    # when the browser dies mid-command, which is exactly when the operator is
    # not watching.
    @{ Name = 'test-cdp-client.js'; Cmd = 'node "{0}\tools\test-cdp-client.js"' },
    # ...and the transport is unproven against a REAL browser, which is exactly
    # what test-cdp-client.js cannot show: it stubs the socket, so a wrong
    # /json/list shape or a Runtime.evaluate that never returns passes it and
    # only fails an operator, mid-session, with no account to hand. This one
    # launches a headless Chrome on a throwaway profile with no cookies and
    # drives the real inspect-web CLI over real CDP against a local fixture.
    # It proves the TOOL, never the product: T-359's acceptance pass against a
    # signed-in chatgpt.com tab is still a human step.
    @{ Name = 'test-inspect-web-cdp-live.js'; Cmd = 'node "{0}\tools\test-inspect-web-cdp-live.js"' },
    # T-065: every chart family the theme names must carry a visibility
    # guard. The Studio report was unauthenticated-only for months while the
    # bar family sat guarded and its siblings did not, so the failure class was
    # still open for everything the bar guard did not name -- and that is
    # visible from the source, with no Studio session required.
    @{ Name = 'test-chart-guard-coverage.js'; Cmd = 'node "{0}\tools\test-chart-guard-coverage.js"' },
    @{ Name = 'test-perf-bounded.js'; Cmd = 'node "{0}\tools\test-perf-bounded.js"' },
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
    # -RedControl proves the pre-fix implementation is still caught. It was never
    # invoked by any suite entry, so the control existed only as a mode someone
    # could type by hand.
    @{ Name = 'test-totalcmd-recovery.ps1 -RedControl'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-totalcmd-recovery.ps1" -RedControl' },
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
    # Its red control adds one check (33 by default, 34 here): the pre-fix code
    # must leave orphaned files on an accent write failure.
    @{ Name = 'test-windows-theme-boundary.ps1 -RedControl'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-windows-theme-boundary.ps1" -RedControl' },
    # W2-004 (SRC-007:R009): Custom batch generation race.
    # The batch must own check+dispatch as one window and every custom publish
    # must own the same mutex; emitted files must be staged so no reader sees
    # a half-published tree.
    @{ Name = 'test-batch-generation.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-batch-generation.ps1"' },
    # Its -RedControl entry is new because the control only started working when
    # T-378 staged json-doc.ps1 beside the red common.ps1. Before that, both red
    # probes died on CommandNotFoundException and the gate exited 1 claiming a
    # gate had stayed green on defective source -- a claim about probes that had
    # never executed. It exits 0 only when all three reproduce their defects.
    @{ Name = 'test-batch-generation.ps1 -RedControl'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-batch-generation.ps1" -RedControl' },
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
    # T-366: the sibling doc gate was orphaned. test-readme-contract.ps1 enforces
    # the three contracts T-211/CORE-012 caught drifting -- terminal font, the
    # terminal Revert merge model, and electron fuse defusing -- and it reads the
    # LIVE code, not just the prose, so it catches a code change that leaves the
    # README asserting the old behaviour. It was referenced by nothing:
    # release.ps1 only calls this file, and this file never called it, so a
    # fourth drift would have shipped silently. Parity above checks that every
    # target is DOCUMENTED; this one checks the documentation is TRUE.
    @{ Name = 'test-readme-contract.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-readme-contract.ps1"' },
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
    # Its red control runs the retention gate against the unbounded appender and
    # expects assertions 1/2/4 to go red, exiting 0 only when they do.
    @{ Name = 'test-log-append-bound.ps1 -RedControl'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-log-append-bound.ps1" -RedControl' },
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
    @{ Name = 'test-terminal-fonts-gui.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-terminal-fonts-gui.ps1"' },
    @{ Name = 'test-tf-apply-results.js'; Cmd = 'node "{0}\tools\test-tf-apply-results.js"' },
    @{ Name = 'test-tf-apply-results.js --red-control'; Cmd = 'node "{0}\tools\test-tf-apply-results.js" --red-control' },
    # T-413: the architecture gate. Wintage owns the BetterDiscord THEME and a
    # link to the canonical plugin repository -- never standalone plugin
    # payloads, never a plugin manager in the installer. It fails if a
    # *.plugin.js payload, the removed manager symbols or a BetterDiscord
    # plugin-install write reappears anywhere in the ACTIVE tree, and it
    # requires the canonical repository URL. Its -RedControl plants each
    # violation in a scratch tree and requires the gate to catch it, so a green
    # run cannot be vacuous.
    @{ Name = 'test-bd-architecture.ps1'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-bd-architecture.ps1"' },
    @{ Name = 'test-bd-architecture.ps1 -RedControl'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-bd-architecture.ps1" -RedControl' },
    # T-418: the 2026-10-05 T-413 commit c528ef3 carried 372 paths, 256 of them
    # per-event journals for E-2335..E-3237 left over from earlier waves, because a
    # directory-scoped add takes a backlog as a unit and SHIP's 6b.5 'prove the index
    # equals the intended scope' had no mechanical form. This gate supplies it: a
    # ticket commit may carry product paths, the standard memory surfaces, and only
    # journals for events its own LOG.md lines attribute to it. The first entry is the
    # regression clause -- the real violator must stay caught -- and the second is the
    # scratch-repo control that proves a green run cannot be vacuous.
    @{ Name = 'test-commit-scope.ps1 -ExpectReject c528ef3'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-commit-scope.ps1" -Ticket T-413 -Commit c528ef3 -ExpectReject' },
    @{ Name = 'test-commit-scope.ps1 -RedControl'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\test-commit-scope.ps1" -RedControl' },
    # T-417: the T-413 delivery report listed an npm test/test:bd script repair in
    # `package.json`, a file .gitignore:60 excludes and no release archive carries,
    # so the recipient could not open the claim and read it as stale narration.
    # check-delivery-claims.ps1 resolves every path-shaped token of the delivery
    # text against the artifact (index or HEAD) and names the ones that resolve
    # nowhere. The scratch control proves both directions: an ignored file the
    # report claims is caught with the rule that excluded it, while the tracked
    # file in the same sentence still resolves.
    @{ Name = 'check-delivery-claims.ps1 -RedControl'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\check-delivery-claims.ps1" -RedControl' },
    # T-415: the T-413 wave rewrote all 64 locale stamps by hand and escaped the
    # path inside the marker ('README\.md') while test-readme-target-parity.ps1
    # matches 'source-digest:\s*README\.md\s*sha256:'. Neither set matched, so 32
    # root and 32 desktop READMEs reported the stamp red and only the live gate
    # caught it -- the stamping step had no way to fail. stamp-readme-digests.ps1
    # is that step: it writes the marker in the one canonical form and finishes by
    # running the consuming gate, exiting with its code. The scratch control takes
    # the real T-413 spelling, proves the repair, and proves a second run writes
    # nothing; the default run leaves an already-canonical set byte-identical.
    @{ Name = 'stamp-readme-digests.ps1 -RedControl'; Cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}\tools\stamp-readme-digests.ps1" -RedControl' },
    # T-387: these nine ran at RELEASE and nowhere else. The block below proved
    # every gate release.ps1 invokes exists as a file, and then executed nine
    # fewer of them than it had just proved present -- so 'Run-Tests.ps1 exits 0'
    # covered 287 entries while nine release gates were not among them. Measured
    # combined cost of closing that gap: 1.9s.
    @{ Name = 'test-diag-counters.js'; Cmd = 'node "{0}\tools\test-diag-counters.js"' },
    @{ Name = 'test-electron-shim.js'; Cmd = 'node "{0}\tools\test-electron-shim.js"' },
    @{ Name = 'test-fs-retry.js'; Cmd = 'node "{0}\tools\test-fs-retry.js"' },
    @{ Name = 'test-repainter-polarity.js'; Cmd = 'node "{0}\tools\test-repainter-polarity.js"' },
    @{ Name = 'test-shim-payloads.js'; Cmd = 'node "{0}\tools\test-shim-payloads.js"' },
    @{ Name = 'test-terminal-font.js'; Cmd = 'node "{0}\tools\test-terminal-font.js"' },
    @{ Name = 'test-theme-packs.js'; Cmd = 'node "{0}\tools\test-theme-packs.js"' },
    @{ Name = 'test-theme-switch.js'; Cmd = 'node "{0}\tools\test-theme-switch.js"' },
    # The gate convention here is test-* OR check-*, and the second half matters:
    # check-wiki-mirror.js is a gate -- its own header says 'exit 0 = pass, 1 =
    # fail' and it aborts with a named page and a diff -- but a test-* filter
    # would have classified it as a tool and let it keep running only at release.
    @{ Name = 'check-wiki-mirror.js'; Cmd = 'node "{0}\tools\check-wiki-mirror.js"' }
    # test-electron-repaint-probe.cjs is the eleventh release gate the suite used
    # to skip; it needs no entry of its own because test-electron-repaint.ps1
    # (already wired above) invokes it. The completeness assertion after the loop
    # derives that transitive edge from the file's own source rather than trusting
    # this comment, so deleting the invocation is caught.
)
# T-414 red control: one suite that cannot pass, added from the environment, so
# the exit reporting of failing check names can be proved on demand without
# breaking a real gate. Off in every ordinary run -- it exists only when the
# caller sets WINTAGE_TEST_INJECT_RED=<a name>, which is how the red half of
# this ticket was verified. The name carries no tool extension on purpose: a
# suite leaf would also be demanded of git by the structural check below, and
# this entry deliberately is not a file.
if ($env:WINTAGE_TEST_INJECT_RED) {
    $toolSuites = @($toolSuites) + @{ Name = $env:WINTAGE_TEST_INJECT_RED; Cmd = "cmd /c echo $($env:WINTAGE_TEST_INJECT_RED) injected red control & exit 7" }
}
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
# T-398 factored the rollback into Restore-PreReleaseState(worktreeRef, indexRef,
# generated) so the GENERATED store could be re-derived too. The immutability
# property is unchanged -- the call site still hands it the snapshot refs and
# never HEAD -- so these pin the handoff and the restore, not the identifiers.
Assert-True ($releaseCode -match 'Restore-PreReleaseState [$]snapshotWorktree [$]snapshotIndex') 'release rollback restores worktree from immutable snapshot'
Assert-True ($releaseCode -match 'restore "--source=[$]worktreeRef" --worktree' -and $releaseCode -match 'restore "--source=[$]indexRef" --staged') 'release rollback restores index from immutable snapshot'
# Every tools/ path release.ps1 actually hands to node, derived from the AST
# rather than from a spelling. T-390 widened a regex to cover two more spellings
# and the external audit was right that this is still convention inference: a
# nested Join-Path or a variable-bound tools directory derived nothing at all
# (SRC-063 CORE-002). The checker parses, resolves and takes SOURCE TEXT, which
# is also what lets every red control for it be a string rather than an edit to
# the live release entrypoint (SRC-063 CORE-001, T-394).
. (Join-Path $root 'tests\lib\ReleaseGateAudit.ps1')
$coverage = Get-ReleaseGateCoverage -Source $releaseCode -Root $root -Executed @()
$gateRefs = $coverage.Paths
foreach ($g in $coverage.Missing) {
    Assert-True $false "release gate exists: $g"
}
Assert-True ($coverage.Missing.Count -eq 0) "every release gate exists on disk (missing: $($coverage.Missing -join ', '))"

# Do the SUITE run them? Existence is the weaker half of the same question. The
# block above knows every gate release.ps1 invokes, and before T-387 the suite
# executed nine fewer of them than it had just proved present: a green
# Run-Tests.ps1 said nothing about the theme-switch, terminal-font, shim-payload
# and four other release gates. Nine entries close today's gap; this assertion is
# what stops the tenth gate from repeating it, and it is falsifiable on demand --
# add a reference to a gate release.ps1 does not run and this goes red.
#
# The executed set is derived, not listed: every tool file named by an entry in
# $toolSuites, plus the tool files those files themselves invoke (one level).
# That second hop is why test-electron-repaint-probe.cjs needs no entry of its
# own -- it is reached through test-electron-repaint.ps1, and the edge is read
# from that file's source rather than trusted from a comment.
$executed = New-Object 'System.Collections.Generic.HashSet[string]'
# One separator or more: the Cmd strings live in single-quoted PowerShell, so an
# entry written as "{0}\\tools\\x.ps1" carries a DOUBLE backslash that a
# single-separator pattern silently skipped -- one release gate's executed
# attribution was being dropped for a typo nobody could see.
foreach ($s in $toolSuites) {
    foreach ($m in [regex]::Matches($s.Cmd, 'tools[\\]+([A-Za-z0-9._-]+)')) {
        $null = $executed.Add($m.Groups[1].Value)
    }
}
# The Name field is the suite's display label, not a claim about what runs, and
# it used to be seeded into $executed before Cmd was read. A record whose Name
# said gate A while Cmd ran gate B therefore satisfied completeness for A
# without ever executing it (SRC-063 CORE-002). It is now proven decorative
# instead of trusted: every Name leaf must already be covered by Cmd.
$unbackedNames = @()
foreach ($s in $toolSuites) {
    $leaf = ($s.Name -split ' ')[0]
    if ($s.Cmd -notlike "*$leaf*") { $unbackedNames += $leaf }
}
Assert-True ($unbackedNames.Count -eq 0) "every suite Name is backed by its own Cmd, not standing in for it (unbacked: $($unbackedNames -join ', '))"
# T-416: strings in this file are not the deliverable -- the FILES are. The T-413
# wave ran ten test files that had zero commits: they existed only in that working
# tree, so a fresh clone ran a suite whose structural check above (Name backed by
# Cmd) was satisfied by strings while the files it named were absent from the
# repository, and the same dependency lived in an ignored manifest. Every tool
# file the suite runs must therefore be carried by git -- in HEAD, or in the index
# for the commit being written -- which also covers absence from disk, since
# neither is shipped. Both halves are needed: this wave commits through a private
# index so the checkout's own large pre-staged set is never disturbed, and a
# HEAD-only check would then report files this repository HAS already shipped.
# Falsifiable on demand -- `git rm --cached tools/<one of them>` turns this red
# with the file named, proved against a private index -- and the predicate is
# proved non-vacuous in the second assertion against a file that exists in this
# working copy but is in neither (package.json, .gitignore:60; if that file is
# ever tracked, move the probe, not the check).
function Get-UntrackedToolFile([string[]]$names) {
    $out = @()
    foreach ($n in $names) {
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & git -C $root ls-files --error-unmatch -- "tools/$n" 2>$null | Out-Null
        $onIndex = $LASTEXITCODE -eq 0
        if (-not $onIndex) {
            & git -C $root cat-file -e "HEAD:tools/$n" 2>$null | Out-Null
            $onIndex = $LASTEXITCODE -eq 0
        }
        $ErrorActionPreference = $prevEap
        if (-not $onIndex) { $out += $n }
    }
    , $out
}
$suiteToolLeaves = @($executed | Where-Object { $_ -match '\.(?:js|cjs|mjs|ps1|py)$' } | Sort-Object)
$untrackedTool = Get-UntrackedToolFile $suiteToolLeaves
Assert-True ($untrackedTool.Count -eq 0) "every tool file the suite runs is carried by git ($($suiteToolLeaves.Count) files; not tracked: $($untrackedTool -join ', '))"
$probeUntracked = Get-UntrackedToolFile @('package.json')
Assert-True ($probeUntracked.Count -eq 1 -and $probeUntracked[0] -eq 'package.json') "the tracked-file check names a file that exists here but is in neither HEAD nor the index (probe: $($probeUntracked -join ', '))"
foreach ($e in @($executed)) {
    $src = "$root\tools\$e"
    if (-not (Test-Path $src)) { continue }
    foreach ($m in [regex]::Matches([System.IO.File]::ReadAllText($src), 'tools[\\/]([A-Za-z0-9._-]+\.(?:js|cjs|mjs|ps1))')) {
        $null = $executed.Add($m.Groups[1].Value)
    }
}
# The steps release.ps1 runs that GENERATE or IMPORT product bytes instead of
# asserting anything. They were previously excused by a file-name prefix
# (test-/check-), which also silently excused any future gate named verify-*.js
# or audit-*.js -- an existence check that reads as coverage but proves nothing
# is executed (T-390). Naming the four steps is a smaller, falsifiable list
# than a naming convention, and each entry is checked below to still be invoked.
$releaseNonGates = Get-ReleaseNonGatePaths
foreach ($n in $coverage.DroppedNonGates) {
    Assert-True $false "release non-gate is still invoked by release.ps1: $n"
}
Assert-True ($coverage.DroppedNonGates.Count -eq 0) "every BUILD_IMPORT step is still invoked by release.ps1 (dropped: $($coverage.DroppedNonGates -join ', '))"
$releaseTestGates = @($coverage.MustRun | ForEach-Object { Split-Path $_ -Leaf })
$unrun = @($releaseTestGates | Where-Object { -not $executed.Contains($_) })
Assert-True ($unrun.Count -eq 0) "every test gate release.ps1 runs is executed by this suite (not run here: $($unrun -join ', '))"
Assert-True ($releaseTestGates.Count -ge 10) "the release gate set was actually derived, not empty ($($releaseTestGates.Count) gates)"

Write-Host "
======================="
if ($script:errors -gt 0) { Exit-Suite 1 } else { Exit-Suite 0 }
