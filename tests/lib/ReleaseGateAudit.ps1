# Release gate audit: derive the tools/* node steps a release script actually
# executes, from source TEXT, by parsing the PowerShell AST instead of matching
# a spelling. T-395 (SRC-063 CORE-002).
#
# The derivation takes text, never a live file, so a red control can prove the
# checker bites by handing it a mutated string in memory. That is the whole
# reason this exists as a callable: T-390 proved its guard by editing
# release.ps1 in place for the duration of a full suite run, and an external
# audit archived that mutant and reported it as a real missing release gate
# (T-394, SRC-063 CORE-001).

Set-StrictMode -Version Latest

# ponytail: this resolves nested Join-Path and simple assignment binding, not a
# tools path computed by a loop, a pipeline or a function call. Such a step is
# simply NOT derived, which is the safe direction -- it can make the guard
# blind, never falsely complete. Upgrade path if that ever matters: resolve
# InvokeExpressionResultAst too, or move release.ps1 onto the declarative
# step structure the audit's preferred design describes.

# The four release steps that GENERATE or IMPORT product bytes instead of
# asserting anything. A named list, not a file-name convention: a convention
# silently excused any future gate named verify-*.js or audit-*.js, which is
# what T-390 fixed. Each entry is still checked to be invoked, so dropping one
# from release.ps1 fails loudly rather than quietly ceasing to be excused.
$script:ReleaseNonGatePaths = @(
    'tools/apply-themes.js'
    'tools/build-desktop.js'
    'tools/derive-palette.js'
    'tools/import-fastprompter.js'
)

function Get-ReleaseNonGatePaths {
    return $script:ReleaseNonGatePaths
}

# Resolve one AST node to a string, or $null when it is not statically known.
# $ScriptRoot stands in for $PSScriptRoot so a caller can assert on the literal
# text it fed in; $Vars holds assignments already seen, in source order, which
# is what makes a variable-bound tools directory resolvable.
function Resolve-StaticValue {
    param(
        [Parameter(Mandatory = $true)] $Node,
        [Parameter(Mandatory = $true)] [hashtable] $Vars,
        [string] $ScriptRoot = '<root>'
    )

    if ($null -eq $Node) { return $null }

    # A bare word or single/double-quoted string with nothing to expand.
    if ($Node -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $Node.Value
    }

    # "…$PSScriptRoot\tools\x.js" — rebuild the template, then swap the one
    # variable we always know. The AST keeps the literal text in .Value.
    if ($Node -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
        $text = $Node.Value
        foreach ($name in $Vars.Keys) { $text = $text -replace ('\$\{0}(?![A-Za-z0-9_])' -f $name), $Vars[$name] }
        $text = $text -replace '\$\$PSScriptRoot(?![A-Za-z0-9_])', $ScriptRoot
        return $text
    }

    if ($Node -is [System.Management.Automation.Language.VariableExpressionAst]) {
        $name = $Node.VariablePath.UserPath
        if ($Vars.ContainsKey($name)) { return $Vars[$name] }
        if ($name -eq 'PSScriptRoot') { return $ScriptRoot }
        return $null
    }

    # node (Join-Path …) — the parenthesis only groups.
    if ($Node -is [System.Management.Automation.Language.ParenExpressionAst]) {
        $inner = $Node.Pipeline
        while ($inner -is [System.Management.Automation.Language.PipelineAst] -and $inner.PipelineElements.Count -eq 1) {
            $inner = $inner.PipelineElements[0]
        }
        return Resolve-StaticValue -Node $inner -Vars $Vars -ScriptRoot $ScriptRoot
    }

    if ($Node -is [System.Management.Automation.Language.PipelineAst]) {
        if ($Node.PipelineElements.Count -ne 1) { return $null }
        return Resolve-StaticValue -Node $Node.PipelineElements[0] -Vars $Vars -ScriptRoot $ScriptRoot
    }

    # A nested command, in practice Join-Path.
    if ($Node -is [System.Management.Automation.Language.CommandAst]) {
        $name = $Node.GetCommandName()
        if (-not $name -or $name -ne 'Join-Path') { return $null }
        $elements = @($Node.CommandElements | Select-Object -Skip 1)
        if ($elements.Count -lt 2) { return $null }
        $parts = @()
        foreach ($e in $elements) {
            $v = Resolve-StaticValue -Node $e -Vars $Vars -ScriptRoot $ScriptRoot
            if ($null -eq $v) { return $null }
            $parts += $v
        }
        # Join-Path concatenates with a separator and lets a rooted child win,
        # which is what PowerShell itself does; more parts keep folding left.
        $acc = $parts[0]
        for ($i = 1; $i -lt $parts.Count; $i++) {
            if ([System.IO.Path]::IsPathRooted($parts[$i])) { $acc = $parts[$i] }
            else { $acc = ($acc.TrimEnd('/', '\') + '/' + $parts[$i]) }
        }
        return $acc
    }

    return $null
}

function ConvertTo-NormalizedToolPath {
    param([string] $Value)

    if (-not $Value) { return $null }
    $flat = $Value -replace '\\', '/'
    if ($flat -match '(?i)(?:^|.*/)(tools/[A-Za-z0-9._-]+\.(?:js|cjs|mjs|ps1))$') { return $Matches[1] }
    return $null
}

function Get-ReleaseToolInvocations {
    <#
      .SYNOPSIS
        Every tools/* script a PowerShell release source hands to node.
      .DESCRIPTION
        Parses the AST, propagates simple assignments so a variable-bound tools
        directory still resolves, and returns one record per resolved step.
        Returns an empty array rather than throwing when the text parses to no
        node calls — an empty result is the signal the caller must not ignore.
    #>
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] [string] $Source,
        [string] $ScriptRoot = '<root>'
    )

    $errors = $null
    $tokens = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Source, [ref] $tokens, [ref] $errors)
    if ($errors -and $errors.Count -gt 0) {
        throw "release source does not parse: $($errors[0].Message)"
    }

    $vars = @{}
    # Assignments first, in source order: a tools directory bound above the call
    # site must be visible to it. Later reassignment wins, which is the safe
    # direction — an unresolved-after-reassignment path simply stops counting.
    foreach ($assign in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
        $left = $assign.Left
        if ($left -is [System.Management.Automation.Language.VariableExpressionAst]) {
            $value = Resolve-StaticValue -Node $assign.Right -Vars $vars -ScriptRoot $ScriptRoot
            if ($null -ne $value) { $vars[$left.VariablePath.UserPath] = $value }
        }
    }

    $found = @()
    foreach ($cmd in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        $name = $cmd.GetCommandName()
        if ($name -ne 'node') { continue }
        $elements = @($cmd.CommandElements | Select-Object -Skip 1)
        $args = @()
        foreach ($e in $elements) {
            $v = Resolve-StaticValue -Node $e -Vars $vars -ScriptRoot $ScriptRoot
            $args += $(if ($null -eq $v) { '<unresolved>' } else { $v })
        }
        $script = if ($args.Count -gt 0) { $args[0] } else { $null }
        $tool = ConvertTo-NormalizedToolPath -Value $script
        if (-not $tool) { continue }
        $found += [pscustomobject]@{
            Path   = $tool
            Args   = @($args | Select-Object -Skip 1)
            Line   = $cmd.Extent.StartLineNumber
            Source = $script
        }
    }
    return $found
}

function Get-ReleaseGateCoverage {
    <#
      .SYNOPSIS
        Which derived release gates exist on disk, and which the suite runs.
      .DESCRIPTION
        Returns the four lists the suite asserts on. Takes source TEXT, so every
        red control is a string, never an edited file.
    #>
    param(
        [Parameter(Mandatory = $true)] [string] $Source,
        [Parameter(Mandatory = $true)] [string] $Root,
        [string[]] $Executed = @()
    )

    $invocations = @(Get-ReleaseToolInvocations -Source $Source)
    $paths = @($invocations | ForEach-Object { $_.Path } | Sort-Object -Unique)
    $nonGates = Get-ReleaseNonGatePaths

    $missing = @($paths | Where-Object { -not (Test-Path (Join-Path $Root ($_ -replace '/', '\'))) })
    $droppedNonGates = @($nonGates | Where-Object { $paths -notcontains $_ })
    $mustRun = @($paths | Where-Object { $nonGates -notcontains $_ })
    $unrun = @($mustRun | Where-Object { $Executed -notcontains (Split-Path $_ -Leaf) })

    return [pscustomobject]@{
        Paths           = $paths
        Invocations     = $invocations
        NonGates        = $nonGates
        Missing         = $missing
        DroppedNonGates = $droppedNonGates
        MustRun         = $mustRun
        Unrun           = $unrun
    }
}