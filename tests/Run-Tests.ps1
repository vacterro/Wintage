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
foreach ($script in @("$root\desktop\install.ps1", "$root\desktop\WintageInstaller.ps1")) {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$null, [ref]$parseErrors)
    Assert-True ($parseErrors.Count -eq 0) "$($script | Split-Path -Leaf) parses with zero syntax errors"
    if ($parseErrors.Count -gt 0) {
        foreach ($e in $parseErrors) { Write-Host "       Line $($e.Extent.StartLineNumber): $($e.Message)" -ForegroundColor Red }
    }
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
