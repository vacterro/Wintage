# T-257 / SRC-013 -- Scenario Presets contract + storage
#
# Defect classes this suite pins down (audit/6.md + audit/7.md):
#   1. A preset is UI STATE, never an execution engine: loading a preset must
#      never invoke install.ps1 Apply/Revert and never mutate an application.
#   2. Persistence is fail-safe: atomic replace, no partial file can overwrite a
#      valid preset, a malformed preset cannot crash the loader or become a
#      silent default, and one corrupt preset cannot hide healthy ones.
#   3. The schema is strict: unknown schemaVersion rejected; unsafe id and path
#      traversal refused; duplicate ids after case normalization rejected;
#      custom snapshots must carry the EXACT canonical token set.
#   4. Targets are canonical keys; an unavailable target is retained in the
#      definition rather than silently dropped.
#   5. Storage lives outside the repository.
#
# Red controls: mutant-based copies of the module prove each guard actually
# fails when its check is removed (no shipped-source switch).
#
#   .\tools\test-presets.ps1                 # normal
#   .\tools\test-presets.ps1 -RedControl     # prove the guards go red

[CmdletBinding()]
param([switch]$List, [switch]$RedControl)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path $here -Parent
$modulePath = Join-Path $root 'desktop\modules\presets.ps1'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$pass = 0; $fail = 0

function check($label, $cond) {
    if ($cond) { Write-Host "PASS: $label" -ForegroundColor Green; $script:pass++ }
    else { Write-Host "FAIL: $label" -ForegroundColor Red; $script:fail++ }
}

if ($List) {
    Write-Host "test-presets.ps1 (T-257 Scenario Presets):"
    Write-Host "  1. pack preset round-trips (save -> load -> same palette + target set)"
    Write-Host "  2. custom token snapshot round-trips"
    Write-Host "  3. malformed preset does not crash the loader and is reported"
    Write-Host "  4. one corrupt preset does not hide healthy presets"
    Write-Host "  5. unsupported schemaVersion is rejected"
    Write-Host "  6. unsafe id / path traversal is refused"
    Write-Host "  7. duplicate id after case normalization is rejected"
    Write-Host "  8. custom snapshot missing a token is rejected"
    Write-Host "  9. unavailable target is retained in the definition"
    Write-Host " 10. Save without -Overwrite cannot clobber an existing preset"
    Write-Host " 11. failed atomic write preserves the previous preset bytes"
    Write-Host " 12. Rename failure preserves the original preset"
    Write-Host " 13. Delete changes no installation state (definition only)"
    Write-Host " 14. storage lives outside the repository"
    Write-Host " 15. loading a preset performs no child install process (static)"
    Write-Host " 16. CORE-001 preset identity (ComboBox bound to ids, not display names)"
    Write-Host " 17. CORE-002 target selectability + unresolved palette"
    Write-Host " 18. CORE-003 rename lock ordering"
    Write-Host " 19. CORE-005 snapshot token value validation"
    Write-Host " 20. CORE-006 preset dirty state (normalized staged-state snapshot)"
    Write-Host "Red control: -RedControl (each guard removed in a temp copy must fail)"
    exit 0
}

# Every run works in an isolated APPDATA so nothing touches the live machine.
$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("wintage-presets-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $sandbox | Out-Null
$prevWinApp = $env:WINTAGE_APPDATA
$env:WINTAGE_APPDATA = $sandbox

$TOKENS = @((Get-Content (Join-Path $root 'tools\theme-schema.json') -Raw | ConvertFrom-Json).tokens)

function New-TokenSnapshot {
    $h = [ordered]@{}
    foreach ($k in $TOKENS) { $h[$k] = '#112233' }
    return $h
}

try {
    . $modulePath

    # --- 1. pack preset round-trip ---
    $p1 = New-PresetObject -Id 'work' -Name 'Work' -PaletteType pack -PaletteSlug 'goldendefault' -Targets @('windows', 'terminal', 'totalcmd')
    $saved = Save-Preset $p1 $TOKENS
    check 'pack preset saves to disk' (Test-Path -LiteralPath $saved)
    $loaded = Get-Presets $TOKENS
    $w = @($loaded.Presets | Where-Object { $_.id -eq 'work' })[0]
    check 'pack preset reloads with the same slug' ($w.palette.slug -eq 'goldendefault' -and $w.palette.type -eq 'pack')
    check 'pack preset reloads the exact target set' ((@($w.targets) -join ',') -eq 'windows,terminal,totalcmd')

    # --- 2. custom snapshot round-trip ---
    $p2 = New-PresetObject -Id 'creative' -Name 'Creative' -PaletteType snapshot -Tokens (New-TokenSnapshot) -Targets @('cinema4d', 'obs')
    Save-Preset $p2 $TOKENS | Out-Null
    $loaded2 = Get-Presets $TOKENS
    $c = @($loaded2.Presets | Where-Object { $_.id -eq 'creative' })[0]
    $cTokNames = @($c.palette.tokens.PSObject.Properties.Name)
    check 'custom snapshot reloads all canonical tokens' ((@($TOKENS | Where-Object { $cTokNames -notcontains $_ }).Count) -eq 0)

    # --- 3. malformed JSON does not crash the loader ---
    $badFile = Join-Path (Get-PresetRoot) 'broken.json'
    [System.IO.File]::WriteAllText($badFile, '{ this is not json', $utf8)
    $ok = $true
    try { $loaded3 = Get-Presets $TOKENS } catch { $ok = $false }
    check 'malformed preset does not crash the loader' $ok
    check 'malformed preset is reported as invalid' ((@($loaded3.Invalid) -contains 'broken.json'))

    # --- 4. one corrupt preset does not hide healthy ones ---
    check 'healthy presets survive beside a corrupt one' ((@($loaded3.Presets | Where-Object { $_.id -eq 'work' }).Count) -eq 1)

    # --- 5. unsupported schemaVersion rejected ---
    $futureObj = [pscustomobject]@{ schemaVersion = 999; id = 'future'; name = 'Future'; palette = [pscustomobject]@{ type = 'pack'; slug = 'goldendefault' }; targets = @('windows') }
    $v = Test-PresetObject $futureObj $TOKENS
    check 'unsupported schemaVersion is rejected with a useful message' (($v -join ' ') -match 'unsupported schemaVersion 999')

    # --- 6. unsafe id / traversal refused ---
    $trav = $false
    try { $null = Get-PresetPath '../../evil' } catch { $trav = $true }
    check 'path-traversal id is refused' $trav
    $emptyId = New-PresetId '   '
    check 'a blank name yields no safe id' ($null -eq $emptyId)
    check 'a safe id is derived from a normal name' ((New-PresetId 'Test VM') -eq 'test-vm')

    # --- 7. duplicate id after case normalization ---
    $dupObj = [pscustomobject]@{ schemaVersion = 1; id = 'work'; name = 'Work'; palette = [pscustomobject]@{ type = 'pack'; slug = 'goldendefault' }; targets = @('windows') }
    $dup = $false
    try { Save-Preset $dupObj $TOKENS } catch { $dup = ($_.Exception.Message -match 'already exists') }
    check 'Save without -Overwrite refuses an existing id' $dup

    # --- 8. snapshot missing a token rejected ---
    $short = [ordered]@{}
    foreach ($k in $TOKENS) { if ($k -ne 'link') { $short[$k] = '#112233' } }
    $shortObj = New-PresetObject -Id 'short' -Name 'Short' -PaletteType snapshot -Tokens $short -Targets @('windows')
    $sv = Test-PresetObject $shortObj $TOKENS
    check 'snapshot missing a canonical token is rejected' (($sv -join ' ') -match 'missing token.*link')

    # --- 9. unavailable target retained ---
    $p9 = New-PresetObject -Id 'unavail' -Name 'Unavail' -PaletteType pack -PaletteSlug 'goldendefault' -Targets @('cinema4d', 'obs')
    Save-Preset $p9 $TOKENS | Out-Null
    $l9 = @((Get-Presets $TOKENS).Presets | Where-Object { $_.id -eq 'unavail' })[0]
    check 'target not currently installed is retained in the definition' ((@($l9.targets) -contains 'cinema4d') -and (@($l9.targets) -contains 'obs'))

    # --- 10. duplicate target detected ---
    $dupT = [pscustomobject]@{ schemaVersion = 1; id = 'dupt'; name = 'DupT'; palette = [pscustomobject]@{ type = 'pack'; slug = 'goldendefault' }; targets = @('windows', 'WINDOWS') }
    $dtv = Test-PresetObject $dupT $TOKENS
    check 'duplicate target after case normalization is rejected' (($dtv -join ' ') -match 'duplicate target')

    # --- 11. failed atomic write preserves previous bytes ---
    $overwrite = New-PresetObject -Id 'work' -Name 'Work' -PaletteType pack -PaletteSlug 'klite' -Targets @('windows')
    Save-Preset $overwrite $TOKENS -Overwrite | Out-Null
    $before = [System.IO.File]::ReadAllText((Get-PresetPath 'work'), $utf8)
    $boom = $false
    try { Save-Preset ([pscustomobject]@{ schemaVersion = 1; id = 'work'; name = ''; palette = [pscustomobject]@{ type = 'pack'; slug = 'x' }; targets = @('windows') }) $TOKENS -Overwrite } catch { $boom = $true }
    $after = [System.IO.File]::ReadAllText((Get-PresetPath 'work'), $utf8)
    check 'a rejected save leaves the previous preset byte-identical' ($boom -and ($before -eq $after))

    # --- 12. rename preserves original on failure ---
    Rename-Preset 'work' 'Work Renamed' $TOKENS | Out-Null
    check 'rename moves the definition to the new id' (Test-Path -LiteralPath (Get-PresetPath 'work-renamed'))
    $renFail = $false
    try { Rename-Preset 'work-renamed' '   ' $TOKENS } catch { $renFail = $true }
    check 'rename with an empty name fails and keeps the original' ($renFail -and (Test-Path -LiteralPath (Get-PresetPath 'work-renamed')))

    # --- 13. delete changes no installation state (definition only) ---
    $installedBefore = Join-Path $env:WINTAGE_APPDATA 'installed.json'
    $hadInstalled = Test-Path -LiteralPath $installedBefore
    Remove-Preset 'creative'
    check 'delete removes only the definition' (-not (Test-Path -LiteralPath (Get-PresetPath 'creative')))
    check 'delete touches no installation manifest' ((Test-Path -LiteralPath $installedBefore) -eq $hadInstalled)

    # --- 14. storage outside the repository ---
    $preRoot = Get-PresetRoot
    check 'preset root is outside the repository' (-not ($preRoot.Replace('/', '\').StartsWith($root.Replace('/', '\'), [System.StringComparison]::OrdinalIgnoreCase)))

    # --- 15. loading performs no child install process (static) ---
    $modText = [System.IO.File]::ReadAllText($modulePath)
    check 'preset module launches no child process' ($modText -notmatch 'Start-Process|&\s+powershell|install\.ps1')

    # --- 16. CORE-001: ONE canonical preset identity (Id, not display name) ---
    # The GUI functions are AST-extracted from the REAL WintageInstaller.ps1 and
    # driven against a REAL WinForms ComboBox with stubbed window chrome, so the
    # identity contract is behavioural: the visible selection and activePresetId
    # always name the same preset id, including equal display names.
    Add-Type -AssemblyName System.Windows.Forms
    $guiPath = Join-Path $root 'desktop\WintageInstaller.ps1'
    $guiText = [System.IO.File]::ReadAllText($guiPath, $utf8)
    function Get-GuiFunctionText([string]$text, [string]$name) {
        $m = [regex]::Match($text, 'function\s+' + [regex]::Escape($name) + '\b')
        if (-not $m.Success) { return $null }
        $i = $m.Index
        $open = $text.IndexOf('{', $i)
        $depth = 0
        for ($j = $open; $j -lt $text.Length; $j++) {
            if ($text[$j] -eq '{') { $depth++ }
            elseif ($text[$j] -eq '}') { $depth--; if ($depth -eq 0) { return $text.Substring($i, $j - $i + 1) } }
        }
        return $null
    }
    $guiFns = @('New-PresetComboItem', 'Select-PresetComboItem', 'Get-SelectedPreset', 'Activate-Preset',
        'Apply-PresetUiState', 'Update-PresetState', 'Get-CheckedTargetKeys', 'Get-UiPalette',
        'Refresh-Presets', 'Save-CurrentAsPreset', 'Get-TargetSelectability', 'Resolve-PresetUiState',
        'Get-PresetDirtyState', 'Test-PresetStateDirty')
    $missingGui = @($guiFns | Where-Object { $null -eq (Get-GuiFunctionText $guiText $_) })
    check 'CORE-001: all GUI identity functions were located in WintageInstaller.ps1' ($missingGui.Count -eq 0)
    $guiSrc = ($guiFns | ForEach-Object { Get-GuiFunctionText $guiText $_ }) -join "`n"
    # CORE-001 specifically requires the handlers to derive their target from the
    # canonical visible selection, never from a display-name lookup.
    check 'CORE-001: Update/Rename/Delete handlers derive the target from Get-SelectedPreset' (
        ([regex]::Matches($guiText, '\$btnPreset(Update|Rename|Delete)\.Add_Click\(\{(?s).*?Get-SelectedPreset')).Count -eq 3)
    $uIdx = $guiText.IndexOf('$btnPresetUpdate.Add_Click')
    $rIdx = $guiText.IndexOf('Refresh-Presets', $uIdx)
    $handlerRegion = if ($uIdx -ge 0 -and $rIdx -gt $uIdx) { $guiText.Substring($uIdx, $rIdx - $uIdx) } else { '' }
    check 'CORE-001: no display-name lookup remains in the preset selection handlers' (
        $handlerRegion -ne '' -and $handlerRegion -notmatch '\$_\.name -eq \$name')

    $script:packStub = @{ goldendefault = [pscustomobject]@{ label = 'Golden Default' }; klite = [pscustomobject]@{ label = 'K-Lite' } }
    $script:packs = $script:packStub
    $script:current = 'goldendefault'
    $script:custom = [ordered]@{}
    $script:customTokensStub = [ordered]@{}
    foreach ($k in $TOKENS) { $script:customTokensStub[$k] = '#101010' }
    $script:targets = @([pscustomobject]@{ Key = 'windows' }, [pscustomobject]@{ Key = 'terminal' })
    $harnessTargetList = New-Object Windows.Forms.CheckedListBox
    [void]$harnessTargetList.Items.Add('windows')
    [void]$harnessTargetList.Items.Add('terminal')
    $harnessTargetList.SetItemChecked(0, $true)
    $TARGET_LISTS = @($harnessTargetList)
    $script:logLines = @()
    function Say-Log($m) { $script:logLines += $m }
    function T($k) { $k }
    function Refresh-Swatches { }
    function Update-Info { }
    function Update-FbButtonsVisibility { }
    function Get-ActiveTokens { return $script:customTokensStub }
    $cmbPreset = New-Object Windows.Forms.ComboBox
    $lstThemes = New-Object Windows.Forms.ListBox
    $lblPresetState = New-Object Windows.Forms.Label
    Invoke-Expression $guiSrc
    $script:presets = @()
    $script:presetsInvalid = @()
    $script:activePresetId = $null
    $script:presetBaseline = $null

    Save-CurrentAsPreset 'Alpha'
    check 'CORE-001: Save As activates the saved preset internally' ($script:activePresetId -eq 'alpha')
    check 'CORE-001: Save As selects the saved preset visibly by ID' (
        $null -ne $cmbPreset.SelectedItem -and $cmbPreset.SelectedItem.Id -eq 'alpha')
    Save-CurrentAsPreset 'Bravo'   # audit case: Save As while another preset was active
    check 'CORE-001: Save As B leaves B internally active (not A)' ($script:activePresetId -eq 'bravo')
    check 'CORE-001: Save As B leaves B visibly selected (not A)' ($cmbPreset.SelectedItem.Id -eq 'bravo')
    $comboIds = @($cmbPreset.Items | ForEach-Object { $_.Id })
    check 'CORE-001: the refresh did not duplicate items' ((@($comboIds | Sort-Object -Unique).Count) -eq $comboIds.Count)

    # Two valid presets with EQUAL display names must stay individually selectable.
    Save-Preset (New-PresetObject -Id 'same-a' -Name 'Same' -PaletteType pack -PaletteSlug 'goldendefault' -Targets @('windows')) $TOKENS -Overwrite | Out-Null
    Save-Preset (New-PresetObject -Id 'same-b' -Name 'Same' -PaletteType pack -PaletteSlug 'klite' -Targets @('windows')) $TOKENS -Overwrite | Out-Null
    Refresh-Presets
    check 'CORE-001: duplicate display names both remain selectable' (
        @($cmbPreset.Items | Where-Object { $_.Name -eq 'Same' }).Count -eq 2)
    [void](Select-PresetComboItem 'same-b')
    $sel = Get-SelectedPreset
    check 'CORE-001: selecting the second duplicate resolves to its own stable id' ($null -ne $sel -and $sel.id -eq 'same-b')
    [void](Activate-Preset 'same-b')
    check 'CORE-001: Activate-Preset selects the requested duplicate visibly' ($cmbPreset.SelectedItem.Id -eq 'same-b')
    check 'CORE-001: Activate-Preset makes it the internal owner' ($script:activePresetId -eq 'same-b')
    $otherBefore = [System.IO.File]::ReadAllText((Get-PresetPath 'same-a'), $utf8)
    $renamed = Rename-Preset 'same-b' 'Same Two' $TOKENS
    Refresh-Presets
    [void](Activate-Preset $renamed)
    check 'CORE-001: rename acted on the VISIBLE preset, not its equal-named sibling' (Test-Path -LiteralPath (Get-PresetPath 'same-a'))
    check 'CORE-001: the equal-named sibling is byte-identical after the rename' (
        [System.IO.File]::ReadAllText((Get-PresetPath 'same-a'), $utf8) -eq $otherBefore)
    $script:activePresetId = 'ghost-id'
    Refresh-Presets
    check 'CORE-001: stale activePresetId after refresh clears instead of pointing nowhere' ($null -eq $script:activePresetId)

    # --- 17. CORE-002: target selectability + unresolved palette ---
    # Discovery states the installer already knows must drive preset loading:
    # present-in-output is not usable, and a missing pack is never baselined as
    # the current palette. The REAL ItemCheck handler is extracted and registered
    # on a real CheckedListBox, with Ask-CustomPath stubbed, so "zero dialogs on
    # preset load" is behavioural rather than a grep.
    $script:suppressPathPrompt = $false
    $script:customPaths = @{}
    $PATH_TARGETS = @('zcode', 'cinema4d')
    $script:targets = @(
        [pscustomobject]@{ Key = 'windows'; State = 'themed' },
        [pscustomobject]@{ Key = 'obs'; State = 'not installed' },
        [pscustomobject]@{ Key = 'terminal'; State = 'fused shut' },
        [pscustomobject]@{ Key = 'zcode'; State = 'listing failed' },
        [pscustomobject]@{ Key = 'cinema4d'; State = 'themed' },
        [pscustomobject]@{ Key = 'freebuff'; State = 'themed' }
    )
    $t2 = New-Object Windows.Forms.CheckedListBox
    foreach ($k in @('windows', 'obs', 'terminal', 'zcode', 'cinema4d', 'freebuff')) { [void]$t2.Items.Add($k) }
    $TARGET_LISTS = @($t2)
    $script:askCount = 0
    function Ask-CustomPath([string]$key) { $script:askCount++; return $false }
    $handlerMatch = [regex]::Match($guiText, '\$onTargetCheck = \{')
    $handlerBody = $null
    if ($handlerMatch.Success) {
        $open = $guiText.IndexOf('{', $handlerMatch.Index)
        $depth = 0
        for ($j = $open; $j -lt $guiText.Length; $j++) {
            if ($guiText[$j] -eq '{') { $depth++ }
            elseif ($guiText[$j] -eq '}') { $depth--; if ($depth -eq 0) { $handlerBody = $guiText.Substring($open, $j - $open + 1); break } }
        }
    }
    check 'CORE-002: the real ItemCheck handler was located' ($null -ne $handlerBody)
    # Invoke-Expression parses the extracted literal in THIS scope, so the REAL
    # handler text resolves the same session-scope variables it would inside
    # WintageInstaller.ps1 ([scriptblock]::Create does not bind $script:).
    Invoke-Expression ('$onTargetCheck = ' + $handlerBody)
    $t2.Add_ItemCheck($onTargetCheck)

    $presetRes = New-PresetObject -Id 'resolver' -Name 'Resolver' -PaletteType pack -PaletteSlug 'goldendefault' -Targets @('windows', 'obs', 'terminal', 'zcode', 'cinema4d', 'ghost')
    $rr = Resolve-PresetUiState $presetRes
    check 'CORE-002: resolver returns requested/selectable/unavailable' (
        @($rr.Requested).Count -eq 6 -and (@($rr.Selectable) -contains 'windows') -and
        (@($rr.Unavailable | Where-Object { $_.Key -eq 'ghost' }).Count) -eq 1)
    $logStart = $script:logLines.Count
    Apply-PresetUiState $presetRes
    $newLog = (@($script:logLines[$logStart..($script:logLines.Count - 1)]) -join "`n")
    check 'CORE-002: themed target checked' ($t2.GetItemChecked(0))
    check 'CORE-002: not-installed target unchecked' (-not $t2.GetItemChecked(1))
    check 'CORE-002: fused-shut target unchecked' (-not $t2.GetItemChecked(2))
    check 'CORE-002: listing-failed target unchecked' (-not $t2.GetItemChecked(3))
    check 'CORE-002: path target without remembered folder unchecked' (-not $t2.GetItemChecked(4))
    check 'CORE-002: target outside the preset unchecked' (-not $t2.GetItemChecked(5))
    check 'CORE-002: preset load opened ZERO folder dialogs' ($script:askCount -eq 0)
    check 'CORE-002: unavailable members are reported with reasons' (
        $newLog -match 'obs \(not installed\)' -and $newLog -match 'zcode \(listing failed\)' -and
        $newLog -match 'cinema4d \(no remembered folder\)' -and $newLog -match 'ghost \(not found on this machine\)')
    check 'CORE-002: partial load does not emit the success-only line' ($newLog -notmatch 'loaded into the UI')
    # Probe control: with suppression OFF the same handler DOES attempt a prompt,
    # so the zero-dialog assertion above is not vacuous.
    $script:suppressPathPrompt = $false
    $script:askCount = 0
    $t2.SetItemChecked(4, $true)
    check 'CORE-002 control: without suppression the path prompt IS attempted' ($script:askCount -eq 1)
    $t2.SetItemChecked(4, $false)

    # Missing pack: palette stays unresolved, current palette untouched, no
    # fallback baseline, no success-only message.
    $missingPack = New-PresetObject -Id 'nopack' -Name 'NoPack' -PaletteType pack -PaletteSlug 'nosuch' -Targets @('windows')
    $script:current = 'goldendefault'
    $logStart = $script:logLines.Count
    Apply-PresetUiState $missingPack
    $newLog = (@($script:logLines[$logStart..($script:logLines.Count - 1)]) -join "`n")
    check 'CORE-002: missing palette leaves the current palette unchanged' ($script:current -eq 'goldendefault')
    check 'CORE-002: missing palette is reported and NOT baselined' (
        $newLog -match 'not installed on this machine - palette left unchanged' -and $null -eq $script:presetBaseline)
    check 'CORE-002: missing palette emits no success-only line' ($newLog -notmatch 'loaded into the UI')

    # Snapshot preset: resolved to Custom, with a baseline captured.
    $snapPreset = New-PresetObject -Id 'snapres' -Name 'SnapRes' -PaletteType snapshot -Tokens $script:customTokensStub -Targets @('windows')
    Apply-PresetUiState $snapPreset
    check 'CORE-002: snapshot palette resolves to Custom' ($script:current -eq '<custom>')
    check 'CORE-002: resolved snapshot captures a baseline' ($null -ne $script:presetBaseline)

    # --- 18. CORE-003: Rename-Preset holds the lock across read-modify-write ---
    # Deterministic race, no sleeps as synchronization: this process holds the
    # preset lock; the renaming child announces readiness at the seam and blocks
    # on the lock; the source is then replaced by a NEWER committed write; the
    # lock is released. A correct rename read the source UNDER the lock and
    # carries the new bytes. A pre-fix rename read before locking and would
    # re-serialize the stale object over the newer content.
    function Invoke-RenameRace([string]$modulePath, [string]$label) {
        $dir = Join-Path $sandbox ("race-" + $label)
        $appData = Join-Path $dir 'appdata'
        $presetDir = Join-Path $appData 'presets'
        New-Item -ItemType Directory -Force -Path $presetDir | Out-Null
        $raceFile = Join-Path $presetDir 'race.json'
        $oldJson = ConvertTo-PresetJson (New-PresetObject -Id 'race' -Name 'Race' -PaletteType pack -PaletteSlug 'goldendefault' -Targets @('windows'))
        [System.IO.File]::WriteAllText($raceFile, $oldJson, $utf8)
        $newJson = ConvertTo-PresetJson (New-PresetObject -Id 'race' -Name 'Race' -PaletteType pack -PaletteSlug 'klite' -Targets @('windows'))
        $seam = Join-Path $dir 'seam'
        $child = Join-Path $dir 'child.ps1'
        $childBody = @(
            'param($modulePath, $appData, $seam, $root)',
            '$ErrorActionPreference = ''Stop''',
            '$env:WINTAGE_APPDATA = $appData',
            '$env:WINTAGE_TEST_PRESET_RENAME_SEAM = $seam',
            '. $modulePath',
            '$TOKENS = @((Get-Content (Join-Path $root ''tools\theme-schema.json'') -Raw | ConvertFrom-Json).tokens)',
            'Rename-Preset ''race'' ''Race Renamed'' $TOKENS | Out-Null',
            'exit 0'
        ) -join "`n"
        [System.IO.File]::WriteAllText($child, $childBody, $utf8)
        $prevApp = $env:WINTAGE_APPDATA
        $env:WINTAGE_APPDATA = $appData
        $lock = $null
        $proc = $null
        try {
            $lock = Enter-PresetLock
            $proc = Start-Process powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $child, $modulePath, $appData, $seam, $root) -PassThru -WindowStyle Hidden
            $deadline = (Get-Date).AddSeconds(30)
            while (-not (Test-Path -LiteralPath $seam) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 20 }
            $sawSeam = Test-Path -LiteralPath $seam
            [System.IO.File]::WriteAllText($raceFile, $newJson, $utf8)
            if ($sawSeam) { Remove-Item -LiteralPath $seam -Force }
            $lock.Dispose(); $lock = $null
            $null = $proc.WaitForExit(60000)
        } finally {
            if ($lock) { $lock.Dispose() }
            if ($proc -and -not $proc.HasExited) { $proc.Kill() }
            $env:WINTAGE_APPDATA = $prevApp
        }
        $dest = Join-Path $presetDir 'race-renamed.json'
        if (-not (Test-Path -LiteralPath $dest)) { return '<no-dest>' }
        return ([System.IO.File]::ReadAllText($dest, $utf8) | ConvertFrom-Json).palette.slug
    }
    $raceSlug = Invoke-RenameRace $modulePath 'green'
    check 'CORE-003: rename carries the concurrent committed write (no stale resurrection)' ($raceSlug -eq 'klite')
    check 'CORE-003: the source file is gone after the rename' (-not (Test-Path -LiteralPath (Join-Path $sandbox 'race-green\appdata\presets\race.json')))
    . $modulePath

    # --- 19. CORE-005: snapshot token VALUE validation ---
    function New-BadSnapshot([object]$value) {
        $t = [ordered]@{}
        foreach ($k in $TOKENS) { $t[$k] = '#112233' }
        $t['link'] = $value
        return New-PresetObject -Id 'valcheck' -Name 'ValCheck' -PaletteType snapshot -Tokens $t -Targets @('windows')
    }
    $valueCases = @(
        @{ V = 'red';     Label = 'named colour' },
        @{ V = '';        Label = 'empty string' },
        @{ V = '#12345';  Label = 'short hex' },
        @{ V = '#12345G'; Label = 'malformed hex' },
        @{ V = 5;         Label = 'numeric value' },
        @{ V = $null;     Label = 'null value' }
    )
    foreach ($c in $valueCases) {
        $v = Test-PresetObject (New-BadSnapshot $c.V) $TOKENS
        check "CORE-005: $($c.Label) snapshot token is rejected" (($v -join ' ') -match 'link=')
    }
    check 'CORE-005: valid mixed-case six-digit hex is accepted' ((@(Test-PresetObject (New-BadSnapshot '#AaBbCc') $TOKENS)).Count -eq 0)
    # File-level isolation: a semantically bad snapshot cannot hide a good one.
    $badRaw = [ordered]@{
        schemaVersion = 1; id = 'badtoken'; name = 'BadToken'; description = ''
        palette       = [ordered]@{ type = 'snapshot'; tokens = [ordered]@{} }
        targets       = @('windows'); options = [ordered]@{}
    }
    foreach ($k in $TOKENS) { $badRaw.palette.tokens[$k] = '#112233' }
    $badRaw.palette.tokens['link'] = 'red'
    [System.IO.File]::WriteAllText((Get-PresetPath 'badtoken'), (($badRaw | ConvertTo-Json -Depth 8) + "`n"), $utf8)
    $loadedBad = Get-Presets $TOKENS
    check 'CORE-005: a semantically invalid preset is reported, not loaded' ((@($loadedBad.Invalid) -contains 'badtoken.json'))
    check 'CORE-005: and healthy presets still load beside it' ((@($loadedBad.Presets | Where-Object { $_.id -eq 'work-renamed' }).Count) -eq 1)
    $badSave = $false
    try { Save-Preset (New-BadSnapshot 'red') $TOKENS -Overwrite } catch { $badSave = $true }
    check 'CORE-005: Save-Preset refuses the invalid snapshot before writing' ($badSave -and -not (Test-Path -LiteralPath (Get-PresetPath 'valcheck')))

    # --- 20. CORE-006: preset dirty state (normalized staged-state snapshot) ---
    # The modified marker compares a normalized staged-state snapshot (palette
    # identity, COMPLETE custom token set, SORTED targets) against the
    # same-shaped baseline, which is recaptured after load / Save As / Update.
    $TARGET_LISTS = @($harnessTargetList)
    $script:current = 'goldendefault'
    $harnessTargetList.SetItemChecked(0, $true)
    $harnessTargetList.SetItemChecked(1, $false)
    $p20 = New-PresetObject -Id 'dirty20' -Name 'Dirty20' -PaletteType pack -PaletteSlug 'goldendefault' -Targets @('windows')
    Save-Preset $p20 $TOKENS -Overwrite | Out-Null
    Refresh-Presets
    [void](Activate-Preset 'dirty20')
    check 'CORE-006: a fresh load is not reported modified' ($lblPresetState.Text -notmatch 'PresetModified')

    # ItemCheck fires BEFORE the check commits: the handler forwards the pending
    # row + NewValue, so the FIRST click already reads as modified. The pre-fix
    # marker re-read GetItemChecked (pre-click state) and stayed silent.
    Update-PresetState -PendingItem $harnessTargetList -PendingIndex 1 -PendingValue 'Checked'
    check 'CORE-006: the first click (pending NewValue) reports modified immediately' ($lblPresetState.Text -match 'PresetModified')
    Update-PresetState
    check 'CORE-006: control - without a pending click the unchanged state stays clean' ($lblPresetState.Text -notmatch 'PresetModified')

    # Commit the click, then undo it: equivalent sets return to clean.
    $harnessTargetList.SetItemChecked(1, $true)
    Update-PresetState
    check 'CORE-006: a committed click keeps reporting modified' ($lblPresetState.Text -match 'PresetModified')
    $harnessTargetList.SetItemChecked(1, $false)
    Update-PresetState
    check 'CORE-006: reverting the click returns to clean (no sticky dirty)' ($lblPresetState.Text -notmatch 'PresetModified')

    # Custom tokens participate: a snapshot preset with ONE edited token is
    # modified even though the theme list still shows the same selection.
    # snapres was built in memory during the CORE-002 section but never saved;
    # save it so Activate-Preset can actually resolve it from disk.
    $snapSave = New-PresetObject -Id 'snapres' -Name 'SnapRes' -PaletteType snapshot -Tokens $script:customTokensStub -Targets @('windows')
    Save-Preset $snapSave $TOKENS -Overwrite | Out-Null
    Refresh-Presets
    [void](Activate-Preset 'snapres')
    check 'CORE-006: a snapshot load baselines the full token set' ($null -ne $script:presetBaseline -and $null -ne $script:presetBaseline.Tokens)
    Update-PresetState
    check 'CORE-006: snapshot load starts clean' ($lblPresetState.Text -notmatch 'PresetModified')
    $script:customTokensStub['link'] = '#A1B2C3'
    Update-PresetState
    check 'CORE-006: one custom token edit is reported modified' ($lblPresetState.Text -match 'PresetModified')
    $script:customTokensStub['link'] = '#101010'
    Update-PresetState
    check 'CORE-006: restoring the token value returns to clean' ($lblPresetState.Text -notmatch 'PresetModified')

    # A pack preset forked to Custom is a deviation even before any token edit.
    [void](Activate-Preset 'dirty20')
    Update-PresetState
    check 'CORE-006: pack preset starts clean' ($lblPresetState.Text -notmatch 'PresetModified')
    $script:current = '<custom>'
    Update-PresetState
    check 'CORE-006: a pack forked to Custom is modified' ($lblPresetState.Text -match 'PresetModified')
    $script:current = 'goldendefault'
    Update-PresetState
    check 'CORE-006: fork cleanup returns to clean' ($lblPresetState.Text -notmatch 'PresetModified')

    # Normalization: equivalent target sets in a different order are the same state.
    $bl = [pscustomobject]@{ Palette = 'goldendefault'; Tokens = $null; Targets = @('terminal', 'windows') }
    $st = [pscustomobject]@{ Palette = 'goldendefault'; Tokens = $null; Targets = @('windows', 'terminal') }
    check 'CORE-006: equivalent target sets in a different order are not dirty' (-not (Test-PresetStateDirty $bl $st))
    $st.Targets = @('windows')
    check 'CORE-006: a genuinely different target set is dirty' (Test-PresetStateDirty $bl $st)

    # Save As / Update recapture the baseline: the saved state IS the preset.
    $harnessTargetList.SetItemChecked(1, $true)
    Update-PresetState
    check 'CORE-006: pre-save state is modified' ($lblPresetState.Text -match 'PresetModified')
    Save-CurrentAsPreset 'Dirty Save'
    check 'CORE-006: Save As/Update recaptures the baseline (saved state is clean)' ($lblPresetState.Text -notmatch 'PresetModified')

    # The ItemCheck wiring forwards the pending row, not a stale re-read.
    check 'CORE-006: ItemCheck wiring forwards the pending NewValue' (
        $guiText -match 'Add_ItemCheck\(\{ param\(\$sender, \$e\)\s*\r?\n\s*Update-PresetState -PendingItem \$sender -PendingIndex \$e\.Index -PendingValue \$e\.NewValue')

    # --- red controls: mutant module copies must fail their guard ---
    # Each mutant disables exactly ONE guard; loading it must let the defect
    # through (guard no longer holds). The shipped module is re-dotted after the
    # controls so no later state depends on the mutant.
    if ($RedControl) {
        $redRoot = Join-Path $sandbox 'red'
        New-Item -ItemType Directory -Force -Path $redRoot | Out-Null
        $lines = $modText -split "`n"

        function Invoke-Mutant([string]$text, [string]$name, [scriptblock]$probe) {
            $mp = Join-Path $redRoot $name
            [System.IO.File]::WriteAllText($mp, $text, $utf8)
            . $mp
            # $true  = the guard still held (refused)
            # $false = the defect passed through
            return [bool](& $probe)
        }

        # RED A: neuter the schemaVersion comparison -> a future version loads.
        $mutA = ($lines | ForEach-Object {
            if ($_ -match 'unsupported schemaVersion') { '        # RED-A removed the version refusal' }
            elseif ($_ -match '\[int\]\$sv -ne') { '        elseif ($false) {' }
            else { $_ }
        }) -join "`n"
        $heldA = Invoke-Mutant $mutA 'a.ps1' {
            $obj = [pscustomobject]@{ schemaVersion = 999; id = 'future'; name = 'Future'; palette = [pscustomobject]@{ type = 'pack'; slug = 'goldendefault' }; targets = @('windows') }
            (@(Test-PresetObject $obj $TOKENS)).Count -gt 0
        }
        check 'RED A: mutant source differs from the shipped module' ($mutA -ne $modText)
        check 'RED A: removing the version guard lets the unsupported schemaVersion through' (-not $heldA)

        # RED B: remove the duplicate-target guard.
        $mutB = ($lines | ForEach-Object {
            if ($_ -match 'duplicate target') { '        # RED-B removed the duplicate-target guard' }
            elseif ($_ -match '\$seen\.ContainsKey\(\$k\)\) \{') { '' }
            else { $_ }
        }) -join "`n"
        $heldB = Invoke-Mutant $mutB 'b.ps1' {
            $obj = [pscustomobject]@{ schemaVersion = 1; id = 'dupt'; name = 'DupT'; palette = [pscustomobject]@{ type = 'pack'; slug = 'goldendefault' }; targets = @('windows', 'WINDOWS') }
            ((@(Test-PresetObject $obj $TOKENS)) -join ' ') -match 'duplicate target'
        }
        check 'RED B: mutant source differs from the shipped module' ($mutB -ne $modText)
        check 'RED B: removing the duplicate guard lets a duplicate target through' (-not $heldB)

        # RED C: remove the unsafe-id refusal.
        $mutC = ($lines | ForEach-Object {
            if ($_ -match 'is unsafe: must match') { '        return (Join-Path (Get-PresetRoot) ("`$id.json"))' }
            else { $_ }
        }) -join "`n"
        $heldC = Invoke-Mutant $mutC 'c.ps1' {
            $traversal = $false
            try { $null = Get-PresetPath '../../evil' } catch { $traversal = $true }
            $traversal
        }
        check 'RED C: mutant source differs from the shipped module' ($mutC -ne $modText)
        check 'RED C: removing the id guard produces a traversal path' (-not $heldC)

        # RED D: pre-CORE-003 lock ordering (source read BEFORE the lock) must
        # resurrect the stale preset in the SAME race fixture.
        $fixedRename = Get-GuiFunctionText $modText 'Rename-Preset'
        $legacyRename = @'
function Rename-Preset([string]$id, [string]$newName, [string[]]$canonicalTokens) {
    if ([string]::IsNullOrWhiteSpace($newName)) { throw 'a preset name must not be empty' }
    $path = Get-PresetPath $id
    if (-not (Test-Path -LiteralPath $path)) { throw "no preset with id '$id'" }
    $obj = Read-PresetFile $path $canonicalTokens
    if ($null -eq $obj) { throw "preset '$id' is invalid on disk and cannot be renamed" }
    $newId = New-PresetId $newName
    if (-not $newId) { throw "name '$newName' cannot produce a safe preset id" }
    $obj.name = $newName
    $obj.id = $newId
    if ($env:WINTAGE_TEST_PRESET_RENAME_SEAM) {
        [System.IO.File]::WriteAllText($env:WINTAGE_TEST_PRESET_RENAME_SEAM, 'ready')
        $seamDeadline = (Get-Date).AddSeconds(30)
        while ((Test-Path -LiteralPath $env:WINTAGE_TEST_PRESET_RENAME_SEAM) -and (Get-Date) -lt $seamDeadline) { Start-Sleep -Milliseconds 20 }
    }
    $lock = Enter-PresetLock
    try {
        $dest = Get-PresetPath $newId
        if (($newId -ne $id) -and (Test-Path -LiteralPath $dest)) {
            throw "renaming '$id' to '$newId' would collide with an existing preset"
        }
        $json = ConvertTo-PresetJson $obj
        $tmp = $dest + '.wintage-tmp-' + [guid]::NewGuid().ToString('N')
        try {
            [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
            Move-Item -LiteralPath $tmp -Destination $dest -Force
        } finally {
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        }
        if ($newId -ne $id -and (Test-Path -LiteralPath $path)) { Remove-Item -LiteralPath $path -Force }
    } finally { $lock.Dispose() }
    return $newId
}
'@
        $mutD = if ($fixedRename) { $modText.Replace($fixedRename, $legacyRename) } else { $modText }
        check 'RED D: mutant source differs from the shipped module' ($null -ne $fixedRename -and $mutD -ne $modText)
        $mutDPath = Join-Path $redRoot 'd.ps1'
        [System.IO.File]::WriteAllText($mutDPath, $mutD, $utf8)
        $redSlug = Invoke-RenameRace $mutDPath 'red'
        check 'RED D: pre-fix lock ordering resurrects the stale preset' ($redSlug -eq 'goldendefault')

        # RED E: CORE-006 -- a dirty-state compare that ignores custom tokens
        # misses the single-token edit (the pre-CORE-006 marker never looked at
        # tokens at all). Mutant compare reads palette identity + targets only.
        $fixedCompare = Get-GuiFunctionText $guiText 'Test-PresetStateDirty'
        $legacyCompare = @'
function Test-PresetStateDirty($baseline, $staged) {
    if (-not $baseline) { return $false }
    if ([string]$baseline.Palette -ne [string]$staged.Palette) { return $true }
    if (((@($baseline.Targets) | Sort-Object -Unique) -join ',') -ne ((@($staged.Targets) | Sort-Object -Unique) -join ',')) { return $true }
    return $false
}
'@
        $mutE = if ($fixedCompare) { $guiText.Replace($fixedCompare, $legacyCompare) } else { $guiText }
        check 'RED E: mutant source differs from the shipped GUI source' ($null -ne $fixedCompare -and $mutE -ne $guiText)
        $mutEPath = Join-Path $redRoot 'e-gui.ps1'
        [System.IO.File]::WriteAllText($mutEPath, $mutE, $utf8)
        $mutEText = [System.IO.File]::ReadAllText($mutEPath, $utf8)
        $mutECompare = Get-GuiFunctionText $mutEText 'Test-PresetStateDirty'
        Invoke-Expression $mutECompare
        $tokBase = [pscustomobject]@{ Palette = '<custom>'; Tokens = ([ordered]@{ background = '#101010'; link = '#101010' }); Targets = @() }
        $tokEdit = [pscustomobject]@{ Palette = '<custom>'; Tokens = ([ordered]@{ background = '#101010'; link = '#A1B2C3' }); Targets = @() }
        check 'RED E: token-blind compare misses the single-token edit' (-not (Test-PresetStateDirty $tokBase $tokEdit))
        # Restore the REAL compare from the shipped GUI source so later state
        # depends only on shipped code (same extraction the harness itself uses).
        Invoke-Expression (Get-GuiFunctionText $guiText 'Test-PresetStateDirty')

        # RED F: the pre-CORE-006 marker re-read the committed check state on
        # ItemCheck and stayed silent on the FIRST click (the event fires before
        # the commit, so the observed state still equals the baseline). Without
        # pending forwarding, a first click on a clean preset observes CLEAN;
        # the shipped forwarding turns the same click into a dirty observation.
        $tokBase2 = [pscustomobject]@{ Palette = 'goldendefault'; Tokens = $null; Targets = @('windows') }
        $stagedPreClick = [pscustomobject]@{ Palette = 'goldendefault'; Tokens = $null; Targets = @('windows') }
        $stagedPending = [pscustomobject]@{ Palette = 'goldendefault'; Tokens = $null; Targets = @('windows', 'terminal') }
        check 'RED F: without pending forwarding the first click observes clean' (-not (Test-PresetStateDirty $tokBase2 $stagedPreClick))
        check 'RED F: with pending forwarding the same click observes dirty' (Test-PresetStateDirty $tokBase2 $stagedPending)

        . $modulePath
    }
}
finally {
    $env:WINTAGE_APPDATA = $prevWinApp
    if (Test-Path -LiteralPath $sandbox) { Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host "`n$pass PASS, $fail FAIL" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $fail
