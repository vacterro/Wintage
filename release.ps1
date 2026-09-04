# Wintage release helper: bumps @version, commits everything, pushes to main.
# Usage:  .\release.ps1 -Message "fix reddit hovercards"
#         .\release.ps1 -Message "new palette" -Bump minor
param(
    [Parameter(Mandatory = $true)][string]$Message,
    [ValidateSet('patch', 'minor', 'major')][string]$Bump = 'patch'
)

$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'wintage.user.js'
# Read/write explicitly as UTF-8 (no BOM). PS 5.1's Get-Content defaults to the
# ANSI codepage and mojibakes every non-ASCII character in the file.
$utf8 = New-Object System.Text.UTF8Encoding($false)

# git writes "LF will be replaced by CRLF" to STDERR, and PowerShell 5.1 turns any
# native-command stderr line into a NativeCommandError -- which, even under
# ErrorActionPreference='Continue', still aborts the script the moment the whole
# release is invoked through a pipe (`.\release.ps1 ... | ...`). safecrlf did not
# silence it because the conversion itself is what warns. Two belts:
#   1. -c core.autocrlf=false stops the conversion, so there is no warning to emit.
#   2. Run each git call inside a helper that merges stderr into stdout and decides
#      success by $LASTEXITCODE alone, so a stray line can never be fatal.
function Git-Safe {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & git -c core.autocrlf=false -C $PSScriptRoot @args 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    $output | ForEach-Object { Write-Host $_ }
    return $code
}

# T-232: the same two belts, for the calls whose VALUE is needed.
#
# Git-Safe above was written for exactly this hazard and every fire-and-forget
# call uses it -- but the calls that read a value back (`stash create`, `rev-parse`,
# `ls-remote`, `tag -l`) were written as bare `& git ... 2>$null` instead, so they
# got NEITHER belt. `2>$null` does not save them: under
# $ErrorActionPreference='Stop' PowerShell 5.1 still promotes a native stderr
# line into a terminating NativeCommandError, and `git stash create` on this repo
# emits one warning per CRLF-converted file. The release therefore died at the
# snapshot step -- before the try block, so before any mutation -- with a "warning:
# LF will be replaced by CRLF" as the fatal error. Same defect class as the gates
# nobody ran: the fix already existed in this file and the risky call sites
# bypassed it.
#
# Returns stdout as a string array and leaves the exit code in $script:GitReadCode
# so a caller can still distinguish "empty because absent" from "empty because it
# failed" (`ls-remote --exit-code` depends on that).
function Git-Read {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & git -c core.autocrlf=false -C $PSScriptRoot @args 2>$null
    $script:GitReadCode = $LASTEXITCODE
    $ErrorActionPreference = $prev
    return @($output)
}

# ─── PREFLIGHT: every feasible NON-MUTATING gate runs before any file changes ──
# W2-007: the release publishes refs/heads/main + the version tag as ONE atomic
# unit, so the branch being committed on MUST be main and HEAD MUST equal the
# local main ref that will be pushed. A release run from a feature branch used to
# push the tag (feature commit) while remote main stayed behind - atomicity only
# proves both refs moved together, never that they name the same commit.
$currentBranch = ((Git-Read rev-parse --abbrev-ref HEAD) -join '').Trim()
if ($currentBranch -ne 'main') {
    throw "release must run on 'main' (current branch: '$currentBranch') - the release publishes refs/heads/main and the version tag as one unit; committing on any other branch would split them. NOTHING was changed."
}
$headCommit = ((Git-Read rev-parse HEAD) -join '').Trim()
$mainCommit = ((Git-Read rev-parse 'refs/heads/main') -join '').Trim()
if (-not $headCommit -or $mainCommit -ne $headCommit) {
    throw "HEAD ($headCommit) does not equal refs/heads/main ($mainCommit) - the release would publish a different commit than it pushes. NOTHING was changed."
}

# T-201: `git add -A` publishes EVERY untracked file sitting in the tree. Refuse
# BEFORE anything is mutated (W2-009) so a refused release leaves the tree
# byte-identical and the next run retries at the same version.
$untracked = @(Git-Read ls-files --others --exclude-standard)
if ($untracked.Count -gt 0) {
    Write-Host "release aborted: $($untracked.Count) untracked file(s) would ride along in 'git add -A':"
    $untracked | ForEach-Object { Write-Host "  $_" }
    throw "git add -A would publish untracked file(s) - commit, delete or gitignore them, then rerun. NOTHING was changed."
}

$content = [System.IO.File]::ReadAllText($script, $utf8)

if ($content -notmatch '// @version\s+(\d+)\.(\d+)\.(\d+)') {
    throw "Could not find a semver @version line in wintage.user.js"
}
$maj = [int]$Matches[1]; $min = [int]$Matches[2]; $pat = [int]$Matches[3]
switch ($Bump) {
    'major' { $maj++; $min = 0; $pat = 0 }
    'minor' { $min++; $pat = 0 }
    'patch' { $pat++ }
}
$new = "$maj.$min.$pat"
$tagRef = "refs/tags/v$new"
$branchRef = 'refs/heads/main'

# ─── PREPARED-VERSION TRACKING (W2-009) ───────────────────────────────────
# A failed release is restartable: $prepared stays $false until the release
# COMMIT exists. Any failure before that restores the exact pre-release worktree
# and index, so a rerun recomputes the SAME version without losing user edits.
$prepared = $false
$snapshotCommit = ((Git-Read stash create 'wintage release pre-state') -join '').Trim()
if ($LASTEXITCODE -ne 0) { throw 'could not snapshot the pre-release tracked worktree and index' }
$snapshotIndex = if ($snapshotCommit) { "$snapshotCommit^2" } else { $headCommit }
$snapshotWorktree = if ($snapshotCommit) { $snapshotCommit } else { $headCommit }
if ($snapshotWorktree -notmatch '^[0-9a-f]{40}$') { throw 'could not snapshot the pre-release tracked worktree and index' }
try {
    # The changelog entry for the TARGET version must exist BEFORE the bump (a
    # rerun after a failed release retries the same version, so the entry is
    # already there - this check is then idempotent).
    $changelog = Join-Path $PSScriptRoot 'CHANGELOG.md'
    if (-not (Test-Path -LiteralPath $changelog) -or
        [System.IO.File]::ReadAllText($changelog, $utf8) -notmatch "(?m)^## \[$([regex]::Escape($new))\]") {
        throw "CHANGELOG.md needs a ## [$new] entry before release - NOTHING was changed."
    }
    # Tag availability is checked BEFORE any mutation too: a tag collision must
    # abort with the tree untouched, not after the version was bumped and committed.
    $tagExists = ((Git-Read tag -l "v$new") -join '').Trim()
    if ($tagExists) { throw "local tag v$new already exists - release aborted BEFORE publishing anything. NOTHING was changed." }
    if ((Git-Safe ls-remote --exit-code origin $tagRef) -eq 0) { throw "remote already has $tagRef - release aborted BEFORE publishing anything. NOTHING was changed." }

    # Bump: the file carries the version TWICE - the @version header Tampermonkey
    # reads, and const W95_VERSION, which is stamped onto every injected <style>
    # so a console can say which build is live. Bumping only the header made that
    # stamp lie -- it read 1.4.7 on a 1.5.0 build, and a version stamp that lies is
    # worse than none, because the one question it exists to answer ("am I looking
    # at a stale install?") gets a confident wrong answer. Both move together now,
    # and check-css.js fails if they ever disagree again.
    $content = $content -replace '(// @version\s+)\d+\.\d+\.\d+', "`${1}$new"
    $content = $content -replace "(const W95_VERSION = ')\d+\.\d+\.\d+(')", "`${1}$new`${2}"
    [System.IO.File]::WriteAllText($script, $content, $utf8)

    node --check $script
    if ($LASTEXITCODE -ne 0) { throw "Syntax check failed - release aborted" }

    # node --check cannot see inside the CSS template literals - to JavaScript they
    # are just strings. A stray '*/', an unbalanced brace or an off-palette colour in
    # there passes --check, loads fine, and then the browser's CSS parser silently
    # discards rules while recovering. That exact failure shipped once and was only
    # caught by measuring computed styles on a live page, so it gates releases now.
    node (Join-Path $PSScriptRoot 'tools/check-css.js')
    if ($LASTEXITCODE -ne 0) { throw "CSS check failed - release aborted" }

    # The theme switch is resolved at document-start from GM storage, with fallbacks
    # that only matter when something is wrong (no GM API, a slug whose pack was
    # removed, a failed write, a refused reload). None of those paths is exercised by
    # opening a page in a healthy browser, so they get a real test instead of an
    # assumption.
    node (Join-Path $PSScriptRoot 'tools/test-theme-switch.js')
    if ($LASTEXITCODE -ne 0) { throw "Theme switch test failed - release aborted" }

    # CORE-003: a same-document SPA navigation into an excluded URL (oauth, captcha,
    # paypal, stripe, bank) must re-evaluate the safety guard, and CORE-013: that
    # guard must install exactly once per document. A second install used to wrap the
    # first wrapper, invisibly, on every re-inject.
    node (Join-Path $PSScriptRoot 'tools/test-spa-exclude.js')
    if ($LASTEXITCODE -ne 0) { throw "SPA exclude safety test failed - release aborted" }

    # CORE-015: the hover surgery and the shadow pierce swallow throws by design (a
    # cross-origin sheet, an unresolved @import, a detached root). The swallow must
    # stay COUNTED: a silent one looks exactly like "hover highlighting is broken"
    # and leaves nothing to diagnose from.
    node (Join-Path $PSScriptRoot 'tools/test-diag-counters.js')
    if ($LASTEXITCODE -ne 0) { throw "Diagnostic counters test failed - release aborted" }

    # PERF-008/009/010: the fuse scanner must stay chunked (it ran on every GUI
    # listing refresh against a hundreds-of-MiB exe), the GUI must dispose its
    # per-draw GDI handles deterministically, and stripHoverSheets must invalidate
    # its per-sheet cache on a SAME-COUNT stylesheet rewrite. All three are
    # invisible when broken: the theme still looks right and the machine just costs
    # more. T-229 also repaired this gate's own ColorDialog assertion, which had
    # been stuck red on correct code.
    node (Join-Path $PSScriptRoot 'tools/test-perf-bounded.js')
    if ($LASTEXITCODE -ne 0) { throw "Performance bounding test failed - release aborted" }

    # PERF-002/003/004/006/007 (SRC-004): the repaint and injection lanes have to
    # stay bounded by the budgets they advertise. The pre-fix code iterated 20,000
    # addedNodes to do 500 units of work, walked the same subtree once per queued
    # root (501,500 getComputedStyle calls for 1,000 nested roots), materialised a
    # 12,000-entry NodeList before consulting a 2,500-node budget, kept detached
    # shadow roots registered with the shared observer forever, queued one full
    # layout scan per resize EVENT, and treated same-document SPA navigation as a
    # new document so stylesheets stacked. None of it is visible from outside:
    # the theme still looks right and the machine just costs more.
    node (Join-Path $PSScriptRoot 'tools/test-perf-lanes.js')
    if ($LASTEXITCODE -ne 0) { throw "Performance lane test failed - release aborted" }

    # PERF-001 (SRC-004): the Electron transaction used to hold whole-binary
    # recovery Buffers in BOTH the parent PowerShell and the child Node layer --
    # the same moved archive resident twice, measured at +192 MiB RSS for a 64 MiB
    # app, precisely during Apply/Revert. Recovery is now a durable on-disk vault
    # plus size+digest identity; this gate builds 16/64/256 MiB fixtures, reads the
    # child's own peak RSS, and re-proves that every failure seam still restores
    # those large files byte-exactly.
    node (Join-Path $PSScriptRoot 'tools/test-perf-recovery.js')
    if ($LASTEXITCODE -ne 0) { throw "Recovery memory test failed - release aborted" }

    # T-230: on Windows a file written milliseconds earlier is routinely still held
    # by the AV scanner or the search indexer. install-electron used to report every
    # such sharing violation as "the application is running - close it completely",
    # which made this very gate red on correct code about one run in twenty and told
    # real users to close an app that was not open. The retry must stay bounded, must
    # still fail for a genuinely locked archive, and must never retry ENOENT.
    node (Join-Path $PSScriptRoot 'tools/test-fs-retry.js')
    if ($LASTEXITCODE -ne 0) { throw "Filesystem retry test failed - release aborted" }

    # Every luminance threshold in the repainter was written against one dark palette.
    # This pins that the polarity layer is a no-op on golden and actually inverts on a
    # light one -- a "generalisation" that silently re-grades the shipped theme is a
    # regression wearing a feature's clothes.
    node (Join-Path $PSScriptRoot 'tools/test-repainter-polarity.js')
    if ($LASTEXITCODE -ne 0) { throw "Repainter polarity test failed - release aborted" }

    # Electron targets share one shim, but Claude alone carries a foreground repair
    # for its nested Epitaxy view. Pin both halves: Claude receives it, every other
    # Electron app keeps the common stylesheet byte-for-byte.
    node (Join-Path $PSScriptRoot 'tools/test-electron-shim.js')
    if ($LASTEXITCODE -ne 0) { throw "Electron shim regression test failed - release aborted" }

    # The palettes live in themes/*.json and are generated INTO the script, so a
    # release must never ship a script whose block drifted from the packs. --check
    # only reports; regenerating is a deliberate act, not something a release does
    # behind the author's back.
    node (Join-Path $PSScriptRoot 'tools/test-theme-packs.js')
    if ($LASTEXITCODE -ne 0) { throw "Theme pack test failed - release aborted" }

    # The desktop themes are generated from the same packs, and the extension's
    # version is read from the header line this script just bumped -- so a --check
    # would fail on EVERY release by construction. Build instead: the version bump
    # is the reason it is stale, and the fix is deterministic.
    node (Join-Path $PSScriptRoot 'tools/build-desktop.js')
    if ($LASTEXITCODE -ne 0) { throw "Building the desktop themes failed - release aborted" }

    # Regeneration contracts: a hand-edited derived/imported/theme block drifts
    # from its source and is only ever fixed deliberately.
    node (Join-Path $PSScriptRoot 'tools/import-fastprompter.js') --check
    if ($LASTEXITCODE -ne 0) { throw "An imported FastPrompter pack is out of date - run 'node tools/import-fastprompter.js', review the diff, then rerun" }
    node (Join-Path $PSScriptRoot 'tools/derive-palette.js') --check
    if ($LASTEXITCODE -ne 0) { throw "A derived palette is out of date - run 'node tools/derive-palette.js', review the diff, then rerun" }
    node (Join-Path $PSScriptRoot 'tools/apply-themes.js') --check
    if ($LASTEXITCODE -ne 0) { throw "Theme block is out of date with themes/*.json - run 'node tools/apply-themes.js', review the diff, then rerun" }

    # The repo wiki/ mirror is copied from the saiwiki kitchen and only ever differs
    # by .md link adaptation. A hand edit on one side drifts silently until someone
    # reads both. This pins that the two stay in lockstep.
    node (Join-Path $PSScriptRoot 'tools/check-wiki-mirror.js')
    if ($LASTEXITCODE -ne 0) { throw "Wiki mirror drifted from the saiwiki kitchen - re-run prepare saiwiki (qq) and collect before release" }

    # Every string the shim hands to executeJavaScript must be valid JavaScript, and
    # node --check cannot see inside template literals -- the same blind spot
    # check-css.js exists for, on the CSS side. Pin that the shipped payloads parse.
    node (Join-Path $PSScriptRoot 'tools/test-shim-payloads.js')
    if ($LASTEXITCODE -ne 0) { throw "Shim payload test failed - release aborted" }

    # The console font is named in TWO places (conhost registry vs Windows Terminal
    # settings.json). A machine with both installed must not render its two terminals
    # in different faces. Pin that they agree and are not proportional Verdana.
    node (Join-Path $PSScriptRoot 'tools/test-terminal-font.js')
    if ($LASTEXITCODE -ne 0) { throw "Terminal font test failed - release aborted" }

    # Desktop target dispatch, PowerShell parsing and -WhatIf isolation live in the
    # repository suite. A release that skips it can still mutate an app during a dry
    # run -- exactly the regression this gate now pins.
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'tests/Run-Tests.ps1')
    if ($LASTEXITCODE -ne 0) { throw "Repository tests failed - release aborted" }

    if ((Git-Safe add -A) -ne 0) { throw "git add failed" }
    if ((Git-Safe commit -m "v${new}: $Message") -ne 0) { throw "git commit failed (nothing to commit, or a hook rejected it)" }
    $prepared = $true

    # T-192 P1#25: a release is published WHOLE or NOT AT ALL. The branch and the tag
    # are pushed in ONE `git push --atomic` refspec: if either ref is rejected the
    # remote receives NEITHER, so no half-published version can ever exist. The tag
    # is created locally first.
    if ((Git-Safe tag -a "v$new" -m "Wintage v$new") -ne 0) { throw "git tag failed - release aborted BEFORE publishing anything." }

    # W2-007: prove the annotated tag dereferences to the EXACT branch commit being
    # published - a tag on a different commit is a branch/tag split even when the
    # push is atomic.
    $tagOid = ((Git-Read rev-parse "${tagRef}^{commit}") -join '').Trim()
    $mainOid = ((Git-Read rev-parse 'refs/heads/main^{commit}') -join '').Trim()
    if (-not $tagOid -or $tagOid -ne $mainOid) {
        throw "tag v$new dereferences to $tagOid but the published branch is $mainOid - branch/tag split detected; nothing was pushed."
    }
    if ((Git-Safe push --atomic origin "${branchRef}:${branchRef}" "${tagRef}:${tagRef}") -ne 0) {
        throw "atomic push FAILED - the remote received NEITHER the branch NOR the tag (git push --atomic). The local commit and annotated tag are ready; fix the remote and re-run: git push --atomic origin refs/heads/main refs/tags/v$new"
    }
    # Post-push invariant: origin/main must now BE the release commit.
    $remoteMain = ((Git-Read ls-remote origin $branchRef) -join '').Trim() -split '\s+' | Select-Object -First 1
    if ($remoteMain -ne $mainOid) {
        throw "post-push verification failed: origin/main is $remoteMain, expected $mainOid - the remote may need manual repair."
    }
    Write-Host "Released Wintage v$new - Tampermonkey clients will pick it up on their next update check." -ForegroundColor Green
} catch {
    if (-not $prepared) {
        # W2-009: restore every tracked file the preparation mutated so a rerun
        # retries the SAME version (untracked files were refused at preflight, so
        # restoring tracked files returns the tree to its exact pre-release state).
        if ((Git-Safe restore "--source=$snapshotWorktree" --worktree -- .) -ne 0 -or
            (Git-Safe restore "--source=$snapshotIndex" --staged -- .) -ne 0) {
            throw 'release rollback failed: pre-release tracked worktree and index could not be restored'
        }
        Write-Host "release aborted before the release commit: the versioned files were restored to their pre-release state - fix the cause and rerun (it will bump the SAME version)." -ForegroundColor Yellow
    }
    throw
}
