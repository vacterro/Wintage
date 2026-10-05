# T-418: a ticket-scoped commit must not sweep in unrelated memory directories.
#
# The 2026-10-05 T-413 commit (c528ef3) carried 372 files: 102 were the ticket's
# product delta and 256 were per-event journals under .saipen/recovery/log-detail
# for events E-2335..E-3237 that earlier waves had left uncommitted. SHIP already
# forbids widening adds (phases/ship.md 6b.4) and asks the shipper to "prove the
# index equals the intended scope" (6b.5), but that proof had no mechanical form,
# so the backlog went into the commit as a unit.
#
# This gate supplies the mechanical form. A commit belongs to exactly one ticket,
# and every path it contains must be one of:
#   * a product path (outside .saipen/), or a path the caller named with -Path;
#   * a standard per-operation memory surface (BOARD/STATE/LOG/MANIFEST/IDENTITY);
#   * a per-event journal whose event this commit's OWN added LOG.md lines
#     carry under this ticket's own owner tag.
# It also refuses an added LOG.md line that carries another ticket's owner tag:
# that is the uncommitted backlog itself, not a shadow of it. One deliberate,
# declared case is legal -- -AlsoOwns names the sibling tickets a single
# operation created (one `improve complete` writes the ticket-add lines for
# every follow-up it files), so their lines and journals may ride along, named
# rather than silent. Declaring ninety-two tickets is not a plausible accident.
#
#   tools/test-commit-scope.ps1                       # inspect the staged index
#   tools/test-commit-scope.ps1 -Ticket T-413 -Commit c528ef3
#   tools/test-commit-scope.ps1 -Commit HEAD -Path README.md,.saipen/KNOWLEDGE/ADR-009.md
#   tools/test-commit-scope.ps1 -List
#   tools/test-commit-scope.ps1 -RedControl           # scratch-repo red/green proof
#   tools/test-commit-scope.ps1 -Ticket T-413 -Commit c528ef3 -ExpectReject
#
# Exit 0 = PASS, 1 = FAIL (every offending path is named), 2 = usage error.
# -ExpectReject inverts the exit code: it is the regression form -- "this shipped
# commit was a scope violation and must stay caught" -- so the suite can assert
# the gate still catches the very commit that motivated it.

param(
    [string]$Ticket,
    [string[]]$Path = @(),
    [string]$Commit,
    [string[]]$AlsoOwns = @(),
    [switch]$List,
    [switch]$RedControl,
    [switch]$ExpectReject
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

# The memory files any single journaled operation is entitled to write.
$script:StandardMemory = @(
    '.saipen/BOARD.md', '.saipen/STATE.md', '.saipen/LOG.md',
    '.saipen/MANIFEST.json', '.saipen/IDENTITY.md'
)

function Invoke-Git([string[]]$argv) {
    $out = @(& git @argv 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "git $($argv -join ' ') failed: $($out -join ' ')" }
    return $out
}

function Get-JournalEvent([string]$p) {
    $m = [regex]::Match($p, '^\.saipen/recovery/log-detail/E-(\d+)-')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Get-AddedLogLines([string]$rev) {
    $lines = if ($rev) { Invoke-Git @('show', $rev, '--', '.saipen/LOG.md') }
             else      { Invoke-Git @('diff', '--cached', '--', '.saipen/LOG.md') }
    @($lines | Where-Object { $_ -like '+*' -and $_ -notlike '+++*' } | ForEach-Object { $_.Substring(1) })
}

function Get-CommitPaths([string]$rev) {
    $paths = if ($rev) { Invoke-Git @('diff-tree', '--no-commit-id', '--name-only', '--root', '-r', $rev) }
             else      { Invoke-Git @('diff', '--cached', '--name-only') }
    @($paths | Where-Object { $_ -ne '' } | ForEach-Object { $_ -replace '\\', '/' })
}

function Resolve-Ticket([string]$rev, [string]$explicit) {
    if ($explicit) { return $explicit }
    if (-not $rev) { return $null }
    $subject = @(Invoke-Git @('log', '-1', '--format=%s', $rev))[0]
    if ($subject -match '(?<!\w)(T-\d+)') { return $Matches[1] }
    return $null
}

# One evaluation, no printing: the single implementation both the CLI report and
# the scratch control read.
function Get-ScopeReport([string]$rev, [string]$ticket, [string[]]$declaredPath, [string[]]$alsoOwned = @()) {
    $also = New-Object System.Collections.Generic.HashSet[string]
    foreach ($a in ($alsoOwned -split ',')) { $t = $a.Trim(); if ($t) { [void]$also.Add($t) } }
    $paths = Get-CommitPaths $rev
    $logLines = Get-AddedLogLines $rev
    $ownedEvents = New-Object System.Collections.Generic.HashSet[string]
    foreach ($line in $logLines) {
        $owner = if ($line -match '\[(T-\d+)\]') { $Matches[1] } else { $null }
        if ($owner -and $owner -ne $ticket -and -not $also.Contains($owner)) { continue }
        if ($ticket -and -not $owner -and $line -notmatch [regex]::Escape("[$ticket]")) { continue }
        foreach ($m in [regex]::Matches($line, 'E-(\d+)')) { [void]$ownedEvents.Add($m.Groups[1].Value) }
    }
    $declared = New-Object System.Collections.Generic.HashSet[string]
    foreach ($p in ($declaredPath -split ',')) {
        $t = ($p -replace '\\', '/').Trim()
        if ($t) { [void]$declared.Add($t) }
    }

    $offenders = New-Object System.Collections.ArrayList
    $product = 0; $memory = 0; $journals = 0
    foreach ($p in $paths) {
        if ($p -notlike '.saipen/*') { $product++; continue }
        if ($script:StandardMemory -contains $p -or $declared.Contains($p)) { $memory++; continue }
        $ev = Get-JournalEvent $p
        if ($ev -and $ownedEvents.Contains($ev)) { $journals++; continue }
        [void]$offenders.Add($p)
    }
    $foreign = New-Object System.Collections.ArrayList
    $declaredLines = 0
    foreach ($line in $logLines) {
        if ($line -match '\[(T-\d+)\]' -and $Matches[1] -ne $ticket) {
            if ($also.Contains($Matches[1])) { $declaredLines++ }
            else { [void]$foreign.Add("$($Matches[1]) | " + $line.Substring(0, [Math]::Min(96, $line.Length))) }
        }
    }
    [pscustomobject]@{
        Paths = $paths; LogLines = $logLines; OwnedEvents = @($ownedEvents)
        Offenders = @($offenders); ForeignLines = @($foreign); DeclaredLines = $declaredLines
        Product = $product; Memory = $memory; Journals = $journals
    }
}

$script:passes = 0
$script:fails = New-Object System.Collections.ArrayList
function Ok([string]$m)  { $script:passes++; Write-Host "  [PASS] $m" }
function Bad([string]$m) { [void]$script:fails.Add($m); Write-Host "  [FAIL] $m" }

function Show-ScopeReport([string]$rev, [string]$ticket, [string[]]$declaredPath) {
    Write-Host "T-418 commit-scope gate -- ticket $(if ($ticket) { $ticket } else { '<unresolved>' }), target $(if ($rev) { "commit $rev" } else { 'staged index' })"
    if (-not $ticket) {
        Bad 'a ticket-scoped commit must name exactly one ticket: pass -Ticket T-### or put T-### in the subject'
        return
    }
    $r = Get-ScopeReport $rev $ticket $declaredPath $AlsoOwns
    if ($r.Paths.Count -eq 0) { Write-Host '  (nothing to inspect)'; return }
    if ($r.ForeignLines.Count -eq 0) {
        Ok "every added LOG.md line belongs to $ticket ($($r.LogLines.Count) added$(if ($r.DeclaredLines) { ", of which $($r.DeclaredLines) belong to declared sibling ticket(s)" }))"
    }
    else {
        Bad "added LOG.md lines name another ticket: $($r.ForeignLines.Count) line(s), first: $($r.ForeignLines[0])"
        foreach ($f in ($r.ForeignLines | Select-Object -Skip 1 -First 4)) { Write-Host "         $f" }
    }
    if ($r.Offenders.Count -eq 0) {
        Ok "every path is attributable: $($r.Product) product, $($r.Memory) standard memory, $($r.Journals) journal(s) of $ticket's own events"
    }
    else {
        Bad "unattributed paths in a $ticket commit: $($r.Offenders.Count) -- $(($r.Offenders | Select-Object -First 10) -join ', ')"
        Write-Host "         evidence ids $ticket's own LOG lines carry: $(if ($r.OwnedEvents.Count) { ($r.OwnedEvents | Sort-Object) -join ',' } else { 'none' })"
        Write-Host '         each one is either a product path (name it with -Path) or a write this ticket did not produce'
    }
}

function Test-ScratchRepo {
    # Proven in a scratch repository: this repo is never mutated.
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-commit-scope-" + [Guid]::NewGuid().ToString('N').Substring(0, 12))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        Push-Location $tmp
        Invoke-Git @('init', '-q', '.') | Out-Null
        Invoke-Git @('config', 'user.email', 'probe@localhost') | Out-Null
        Invoke-Git @('config', 'user.name', 'probe') | Out-Null
        New-Item -ItemType Directory -Path '.saipen/recovery/log-detail' -Force | Out-Null
        Set-Content -Path '.saipen/LOG.md' -Value @(
            '# LOG', '', '- 05.10.26 [E-9001] [T-900] [agent: probe] RUN: SCOUT -- own line',
            '- 05.10.26 [E-9002] [T-900] [agent: probe] RUN: BUILD -- own line')
        Set-Content -Path '.saipen/recovery/log-detail/E-9001-aaaaaaaaaaaaaaaaaaaaaaaa.json' -Value '{}'
        Set-Content -Path '.saipen/recovery/log-detail/E-9002-bbbbbbbbbbbbbbbbbbbbbbbb.json' -Value '{}'
        Invoke-Git @('add', '-A') | Out-Null
        Invoke-Git @('commit', '-q', '-m', 'T-900: own scope') | Out-Null
        $r = Get-ScopeReport 'HEAD' 'T-900' @()
        if ($r.Offenders.Count -eq 0 -and $r.ForeignLines.Count -eq 0 -and $r.Journals -eq 2) {
            Ok 'scratch green: an own-scope commit with its own two journals PASSes'
        } else {
            Bad "scratch green: own-scope commit must PASS, got offenders=$($r.Offenders -join ',') foreign=$($r.ForeignLines.Count) journals=$($r.Journals)"
        }

        Set-Content -Path '.saipen/recovery/log-detail/E-7777-cccccccccccccccccccccccc.json' -Value '{}'
        Invoke-Git @('add', '-A') | Out-Null
        Invoke-Git @('commit', '-q', '-m', 'T-900: swept journal') | Out-Null
        $r = Get-ScopeReport 'HEAD' 'T-900' @()
        if ($r.Offenders.Count -eq 1 -and $r.Offenders[0] -like '*E-7777*') {
            Ok 'scratch red: a foreign event journal FAILs and is named (E-7777)'
        } else {
            Bad "scratch red: foreign journal must be the one offender, got $($r.Offenders -join ',')"
        }

        Add-Content -Path '.saipen/LOG.md' -Value '- 05.10.26 [E-9100] [T-901] [agent: probe] RUN: SCOUT -- foreign line'
        Invoke-Git @('add', '-A') | Out-Null
        Invoke-Git @('commit', '-q', '-m', 'T-900: swept log') | Out-Null
        $r = Get-ScopeReport 'HEAD' 'T-900' @()
        if ($r.ForeignLines.Count -eq 1 -and $r.ForeignLines[0] -like 'T-901*') {
            Ok "scratch red: another ticket's LOG line FAILs and is named (T-901)"
        } else {
            Bad "scratch red: foreign LOG line must be named, got $($r.ForeignLines -join ' ; ')"
        }

        $r = Get-ScopeReport 'HEAD' 'T-900' @('.saipen/recovery/log-detail/E-7777-cccccccccccccccccccccccc.json')
        if ($r.Offenders.Count -eq 0) { Ok 'scratch green: a -Path declaration attributes the swept journal' }
        else { Bad "scratch green: -Path must attribute the journal, got $($r.Offenders -join ',')" }

        $r = Get-ScopeReport 'HEAD' 'T-900' @('.saipen/recovery/log-detail/E-7777-cccccccccccccccccccccccc.json') @('T-901')
        if ($r.ForeignLines.Count -eq 0 -and $r.DeclaredLines -eq 1) {
            Ok 'scratch green: -AlsoOwns T-901 names the sibling line instead of failing on it'
        } else {
            Bad "scratch green: -AlsoOwns must attribute the sibling LOG line, got foreign=$($r.ForeignLines -join ' ; ') declared=$($r.DeclaredLines)"
        }
    }
    finally {
        Pop-Location
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
}

if ($RedControl) {
    Write-Host 'T-418 commit-scope gate -- --RedControl (scratch repository; this checkout is not mutated)'
    Test-ScratchRepo
    Write-Host ''
    Write-Host "RESULT: $script:passes PASS, $($script:fails.Count) FAIL"
    if ($script:fails.Count) { foreach ($f in $script:fails) { Write-Host "  FAIL: $f" }; exit 1 }
    Write-Host 'ALL RED CONTROLS PASSED'
    exit 0
}

$resolved = Resolve-Ticket $Commit $Ticket
if ($List) {
    $paths = Get-CommitPaths $Commit
    $owned = New-Object System.Collections.Generic.HashSet[string]
    $also = New-Object System.Collections.Generic.HashSet[string]
    foreach ($a in ($AlsoOwns -split ',')) { $t = $a.Trim(); if ($t) { [void]$also.Add($t) } }
    foreach ($line in (Get-AddedLogLines $Commit)) {
        $owner = if ($line -match '\[(T-\d+)\]') { $Matches[1] } else { $null }
        if ($resolved -and $owner -and $owner -ne $resolved -and -not $also.Contains($owner)) { continue }
        foreach ($m in [regex]::Matches($line, 'E-(\d+)')) { [void]$owned.Add($m.Groups[1].Value) }
    }
    Write-Host "ticket: $resolved"
    Write-Host "target: $(if ($Commit) { "commit $Commit" } else { 'staged index' })"
    Write-Host "paths: $($paths.Count)"
    Write-Host "evidence ids from this ticket's own LOG lines: $(($owned | Sort-Object) -join ',')"
    exit 0
}

Show-ScopeReport $Commit $resolved $Path
Write-Host ''
Write-Host "RESULT: $script:passes PASS, $($script:fails.Count) FAIL"
if ($script:fails.Count) { foreach ($f in $script:fails) { Write-Host "  FAIL: $f" } }
if ($ExpectReject) {
    if ($script:fails.Count) { Write-Host 'REJECT CONFIRMED: the gate still refuses this commit'; exit 0 }
    Write-Host 'REJECT EXPECTED BUT NOT PRODUCED: the gate passed a commit it must refuse'
    exit 1
}
if ($script:fails.Count) { exit 1 }
Write-Host 'ALL COMMIT-SCOPE CHECKS PASSED'
exit 0
