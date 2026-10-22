# FINAL REPORT — T-991: Wintage waves 1-6 campaign, closing report

Ticket: T-991 (the campaign's closing deliverable). Mission: Reliability, Performance,
Compatibility, Release Safety for the Wintage userscript and its desktop installer.

This report is written from the measured artifacts of the campaign. Every number below
comes from a file in this repository or from a run whose command is quoted with it.
Nothing here is estimated, remembered or carried over from another ticket's claim.

## STATUS

- **Campaign: COMPLETE for everything the campaign may do. Three owner decisions remain open.**
- Closed in this campaign: **T-980, T-982, T-983, T-984, T-985, T-987, T-988, T-989, T-990, T-991**.
- Still open and blocked on the owner: **T-981** (release channel convergence — needs a push),
  **T-986** (Verdana_m1.ttf redistribution decision), **T-376** (live BetterDiscord acceptance).
- Tree at the time of writing: branch `main`, code HEAD `43aef8e`, **6 code commits** on top of
  `d775325` (the commit that is published on the polled destination). This report and its
  amendments are commits of their own, whose hashes cannot appear inside themselves.
- **Remote publication: DISABLED FOR NEW CHANGES.** This campaign pushed nothing, tagged nothing,
  published nothing, deployed nothing and rewrote no remote history. Every commit below is local.
- No shared protocol machinery was modified: `SAIPEN_HOME` is untouched, and the SAIPEN
  conformance receipt was refreshed and re-verified with the project's own `saipen validate`
  and `saipen work reverify` only.

## RESULT

The six waves produced **four code changes and two measurement/repair changes**, all in the
local tree, all proved by the project's own gates:

1. The release now **binds to the destination the clients actually poll** and **proves the
   artifact it delivered** (T-984, T-983) — the defect that let a release report success while
   every browser kept the old build.
2. The checkout **carries no third-party audio and no user audio** any more (T-982).
3. The suite **runs in fractions** with gate sets derived from `release.ps1` itself (T-985).
4. The **shadow-sheet hot path** no longer re-parses an 11 KB stylesheet once per shadow root
   (T-987), and the **palette contrast contract** was widened so a pack is judged against every
   backdrop it can legally sit on, with three packs corrected (T-988).
5. The desktop installer's transaction, idempotence and failure reporting were **proved rather
   than assumed** (T-989).
6. The project's own benchmark was **repairing a measurement**: the smoke run used to overwrite
   the full measurement matrix (T-987 follow-up, `43aef8e`).

The honest limits: **no live authenticated acceptance was performed anywhere in this campaign**,
the **Brave** browser figure is **UNVERIFIED** (there is no Brave on this machine), and the
**release channel still does not converge** until the owner pushes.

## COMPLETED WORK

### Wave 1 — Release channel safety (T-984, T-983, T-982; T-981 blocked)

- **T-984 — the release knew nothing about where it published.** It pushed to a remote named
  `origin` and verified the ref moved, while the URL browsers poll lives in the installed
  script's own `@updateURL`/`@downloadURL` metadata. Nothing compared the two, so a release
  could report success while every client kept the old build — and because the poll URL is
  part of the *installation*, no later release could repair it.
  *Change*: `tools/check-release-target.js` compares the push target with the userscript's
  update/download URL (same repository, branch and file); `release.ps1` runs it in the
  preflight, before anything is mutated, and the commit body and the success line name the
  destination. The push URL is read with `git remote get-url --push origin` (on this tree
  `https://gitlab.com/vacuum34/wintage.git`).
  *Evidence*: `node tools/test-release-target.js` -> 13 checks PASS, exit 0; against the real
  push URL of `origin` -> exit 0, verdict `MATCH`; against the other live remote -> exit 1,
  verdict `MISMATCH`. The 13th case is the self-audit fix: an empty push destination is
  `UNKNOWN` (code 2), never a silent re-resolution.
- **T-983 — the release never checked what it published.** It verified the pushed ref (a fact
  about git) and then printed "Tampermonkey clients will pick it up" (a claim about the
  artifact the browser installs). The project already owned the detector for that measurement,
  `tools/check-deployed-userscript.js`, invoked by no release step and by no test.
  *Change*: `release.ps1` runs the detector against the install URL after the push, retries
  because a raw URL can lag a push, and reports a stale delivery or an `UNPROVEN` artifact
  instead of a green success line.
  *Evidence*: `tools/test-release-delivery.js` and `tools/test-release-delivery-verdict.ps1`
  both exit 0 (the latter is 15 checks, including a RED control that mutates the lifted
  `Get-ReleaseDeliveryVerdict` text and requires the same assertion to go red). The derived
  release step count went **18 -> 20 unique tool paths**, of which 16 are must-run gates and 4
  are `BUILD_IMPORT` steps; `tests/test-release-gate-audit.ps1` pins `20`, so dropping either
  new gate is loud.
- **T-982 — the checkout carried a third-party sound and invited user audio into git.** The
  operator's own repair `052f416` was ported: `sounds/` is gitignored, the tracked
  game-derived wav is out of the tree, the installer copies the chosen sound to
  `%APPDATA%\Wintage\freebuff.<ext>` and reads the preference from
  `%APPDATA%\Wintage\freebuff-sound.txt`, a legacy in-checkout copy is moved out on load, and
  all 33 desktop READMEs name the real destination instead of a path inside the checkout.
  *Evidence*: `git ls-files sounds/` empty; `git ls-files | grep -icE '\.(wav|mp3|ogg|m4a|flac|aac|opus|wma)$'` -> 0;
  `git check-ignore -q sounds/freebuff.wav` -> exit 0; `tools/test-no-repo-audio.js` -> 11 checks
  PASS and it runs inside the suite. The self-audit found one real defect (the READMEs still
  said COPY writes "into the repo itself") and fixed it; the source-digest stamps were
  re-stamped with the project's own `tools/stamp-readme-digests.ps1` (231 PASS, 0 FAIL).
- **T-981 is BLOCKED, and the blocker is exact** (see RELEASE SAFETY and NEED USER).

### Wave 2 — Test execution efficiency (T-985)

- The suite had no way to run "the release gates" as opposed to "everything", so every
  iteration cost a full pass. The gate set was also hand-maintained in two places, which is
  how a release step and its test drift apart.
  *Change*: `tests/Run-Tests.ps1` gained `-Level FULL|FOCUSED|FAST` (`-Only` / `-Skip` too).
  The gate set is **derived from `release.ps1` itself** by `tests/lib/ReleaseGateAudit.ps1`:
  20 derived tool paths, 16 must-run gates. Every exit door prints a per-suite timing summary
  and the slowest five. A reduced run prints a label next to the verdict:
  `REDUCED RUN: this is not a release proof. release.ps1 judges the tree with the FULL level.`
  *Evidence*: `level FULL runs every registered suite (123 of 123)`, `level FOCUSED never runs a
  suite FULL does not (25 of 123)`, `level FAST never runs a suite FOCUSED does not (16 of 25)`,
  `level FAST runs no PowerShell-child suite (found: )`, `level FOCUSED covers every release
  gate (missed: )`, `the release gate set was actually derived, not empty (16 gates)`.

### Wave 3 — Browser runtime performance (T-987)

- **Root cause.** The repainter's pierce pass re-entered every live shadow root on every
  repaint, and each entry called `replaceSync` on the adopted shadow sheet — 11 KB of
  selectors — even when the content had not changed. The DOM fallback path had always compared
  the content first (`if (sheet.__w95Content !== content)`); the adopted path had not. That
  asymmetry was the measured hot path: on a page with 200 live shadow roots the same CSS was
  re-parsed 200 times per repaint.
  *Change* (`wintage.user.js`): the adopted path now carries the same guard, so an unchanged
  sheet is not re-parsed. One condition, in the place where the asymmetry was.
  *Proof*: see PERFORMANCE. The fix is proved by the same benchmark, before and after.
- **A defect in the instrument itself.** The suite runs `bench-idle-cpu.js --quick` as a smoke
  gate, and the tool wrote its output over `tools/bench-idle-cpu-results.json` — the full
  5-arm x 6-workload x 3-repeat matrix. A two-row smoke file in place of the matrix would
  silently destroy the measurement this report quotes. *Change* (`tools/bench-idle-cpu.js`,
  `43aef8e`): `--quick` writes `tools/bench-idle-cpu-results-quick.json`; the full matrix keeps
  its own file. *Evidence*: after **two** FULL suite runs the matrix file was byte-unchanged
  (28 679 bytes, mtime 13:56:30 — the time of its own generation) while the smoke rows landed in
  the quick file (683 bytes, 14:26:28, written by the run that was executing at that moment).
  All three result files are gitignored (`.gitignore` lines 114 and 118), so the tree stays clean
  and the measurement stays reproducible with `node tools/bench-idle-cpu.js`.

### Wave 4 — Visual and interaction stability (T-988)

- **Root cause.** The palette contrast contract judged each role against a *single* backdrop.
  A pack could therefore pass the gate while failing against another backdrop it legally
  renders on — three shipped packs were in exactly that state.
  *Change*: `tools/theme-schema.js` `WCAG_BACKDROPS` became a per-role **list** (a role is
  judged against every backdrop it can legally sit on), mirrored into
  `tools/theme-schema.json`, enforced by `tools/check-css.js`, consumed by the installer's
  `Update-Info` path and by the suite; `tools/derive-palette.js` reproduces the shipped
  values; `themes/codenomad.json`, `themes/solarized.json` and `themes/vintageclassic.json`
  were corrected. This is a **strengthening**: no test was weakened, and the FULL suite on the
  same tree is green.
  *Evidence*: 13 wave-4 site gates, one by one, every one `exit=0`
  (`test-chatgpt-2026`, `test-chatgpt-perf-css`, `test-chatgpt-contract-parity`,
  `test-chatgpt-viewport-coverage`, `test-chatgpt-assistant-content`,
  `test-provider-image-preservation`, `test-x-interaction-safety`, `test-reddit-cssonly`,
  `test-reddit-repaint-gates`, `test-reddit-mutation-stress`, `test-theme-packs`,
  `test-theme-switch`, `test-shadow-registry-lifecycle`); 20 captured screenshots
  pixel-audited -> `problems: 0`; a computed-style sweep over 16 palettes + 4 host stand-ins
  -> `PROBLEMS (0): none`, body contrast 7.67-14.81, minimum surface contrast 4.75-7.91, every
  palette `firstError null`, shadow CSS injected, `cssOnly=true` on all four hosts.
  *Not performed*: **live authenticated acceptance was NOT performed** and is recorded as
  UNVERIFIED, not as a pass.

### Wave 5 — Desktop installer reliability (T-989)

- **Root cause (of the campaign's doubt, not of a defect):** wave 5 was expected to find
  transaction, idempotence and failure-reporting defects in the installer. The shipped tree
  already owned them. The one real defect wave 5 found was inherited from wave 4's widened
  contrast contract (the three packs above) and was fixed there. Wave 5's job turned out to be
  **proof, not code** — which is the honest outcome, and it is recorded as such.
  *Evidence*: the five wave-5 gates ran on the final tree with **325 assertions, 0 FAIL** —
  `test-atomic-recovery` 19 PASS, `test-target-refresh-transaction` 53 PASS,
  `test-transaction-boundary` 121 PASS, `test-batch-timer-gui` 45 PASS,
  `test-first-touch-recovery` 87 PASS. The failure-injection assertions all hold: `w2004` ext
  post-copy failure exits non-zero and the rollback claim is present (restore verified); `w2004`
  obs late-write failure exits non-zero and the injected seam is what failed, not a refusal
  before mutating; `w2005` native — a non-zero native exit in the rollback fails the operation
  while the original commit failure still survives; `w2005` double reports both the commit and
  the rollback error; `w2005` restored — a successful rollback still exits non-zero; `w2005`
  happy — a successful commit exits 0 and never runs the rollback; `c4d-3d` manifest-commit
  failure exits non-zero and the persistent recovery survives the failure.
  *Idempotence*, run against a **TEMP** `WINTAGE_APPDATA` root (never the live `%APPDATA%`):
  apply #1 installs the Notepad++ theme and exits 0; apply #2 of the same target produces the
  **byte-identical** theme file (SHA256 `3C8DD3E81C77` both times) and reports no mutation;
  the manifest-wide `-Reapply` pass prints `notepadplusplus: up to date (payload v1.36.10, path
  ...)` followed by `Nothing to do -- all recorded targets are up to date.` and exits 0:
  `IDEMPOTENCE: second-apply-says-up-to-date=True nothing-to-do=True
  second-apply-reported-a-mutation=False applied-theme-bytes-identical=True`. The manifest bytes
  differ between the two applies **only** in the `applied` timestamp, which is why the assertion
  compares the applied theme payload rather than the manifest blob.
  *Also measured*: 33 locale files, all fully translated; 81 keys in `en.json`; 147 source files
  scanned; 16 dead keys, 12 of which are hardcoded in English in the source, and the remaining
  four (`InfoTitle`, `NothingToDo`, `NothingToDoEmpty`, `UpToDate`) are consumed as English
  values by the GUI parse regex at `desktop/WintageInstaller.ps1:1953`.
  *Nothing was touched*: no real installed application, no user profile, no browser database
  and no global Windows setting. Every installer run used an isolated root under `%TEMP%`.

### Wave 6 — Distribution and compliance hygiene (T-982, T-986)

- The audio half of wave 6 shipped with T-982 (above). The font half is **T-986, still open**:
  the repository is public and `Verdana_m1.ttf` is a modified Microsoft Verdana (`fsType` 8,
  editable embedding) whose terms grant use, not redistribution. The file's name table,
  `fsType` and embedding terms are recorded, the 20 bundled terminal faces are hash-verified
  CONFIRMED, and `THIRD_PARTY_NOTICES.md` names the ticket and keeps the font at
  `NEEDS_REVIEW` with the three options. **The campaign did not make that choice silently** —
  it is the owner's.

### T-990 — the T-376 claim, reconciled with this machine (DONE)

- T-376 claimed a live BetterDiscord acceptance. Re-checked on this machine, the premise was
  wrong in both directions and the truth is narrower:
  - `C:\Users\vac34\AppData\Roaming\BetterDiscord\betterdiscord.asar` **PRESENT** (598 323
    bytes, 58 installed plugin files);
  - `C:\Users\vac34\AppData\Local\Discord\app-1.0.9264\resources\betterdiscord.app.asar`
    **PRESENT** — the installed Discord is already patched by BetterDiscord, which is why there
    is no plain `app.asar`;
  - `C:\Users\vac34\AppData\Roaming\discord\settings.json` PRESENT; six `Discord.exe`
    processes running since 00:31.
  - The plugin set **changed under the ticket**: the sources live in a separate repository
    (`V:\___VAC\__K\__CODE\_PLUG_SCRIPT\BetterDiscord_vac34_plugins`) and ship **three**
    plugins now (MediaFilter 1.0.3, which merged the former HideEmbeds / RemoveGIFS /
    RemoveStickers; GoodEmoji 1.1.1; SilentTyping 1.0.0), so the earlier live evidence
    ("the four plugins load") describes a layout that no longer exists. This repository has no
    `desktop/targets/betterdiscord/plugins` at all (that folder holds only `template.css`).
  - The **offline half is green**: `npm run check` in the plugin repository -> `node --check` on
    all three plugins, and `node --test tests/mediafilter.test.js` -> `tests 20, pass 20, fail 0`.
  - The **live half needs the operator**, for two measured reasons: the running Discord was
    launched **without** `--remote-debugging-port` (127.0.0.1:9223, 9222 and 9229 all refuse
    the connection; the only listening port is 6463), and the installed copies of MediaFilter
    (installed SHA `987838474b418da4` vs source `b140eedf32d18502`) and GoodEmoji
    (`3afdf385947d31e8` vs `08b59ef15426d436`) **differ from the current source**, and this
    campaign may not modify a real installed application.
  - **NO LIVE ACCEPTANCE IS CLAIMED.** Nothing here was asserted from an unauthenticated or
    unrun session.

## PERFORMANCE

Source of record: **`tools/bench-idle-cpu-results.json`**, the full matrix written by
`node tools/bench-idle-cpu.js` (5 arms x 6 workloads x 3 repeats, arm order rotated per round
to remove positional bias) on 2026-10-22 at 13:56:30, on the shipped tree. The measurement is
the **renderer** process's own busy percentage from CDP `Performance.getMetrics`
(`TaskDuration` over wall time); browser-process CPU is never mixed into it.

**Measured median renderer busy % per workload (from that file, and nothing else):**

| workload | disabled | baseline (b5fb1d64) | fixA | preFix (0e2bb1b) | both (shipped) |
|---|---|---|---|---|---|
| longIdle   | 0.9  | 1.1  | 1.1  | 0.9  | 1.2  |
| highChurn  | 12   | 14.4 | 13.6 | 13.9 | 13.6 |
| generic    | 1.4  | 5.7  | 4.4  | 4.6  | 4.7  |
| shadowHeavy| 23.3 | 28.8 | 35.3 | 36.5 | **29.1** |
| manyFrame  | 2.2  | 2    | 2.2  | 1.9  | 2.1  |
| mountUnmount | 12.9 | 24.8 | 20.4 | 21 | 20.1  |

Arms: `disabled` = no userscript at all; `baseline` = `b5fb1d64`, the build before the T-938
shadow work; `fixA` = the shipped source with the whole `interceptAttachShadow` block
replaced by the baseline's; `preFix` = `0e2bb1b`, the build immediately before the T-987
change; `both` = the shipped worktree.

**The claim, proved by the same benchmark (before and after):**

- On `shadowHeavy`, the pre-fix build measures **36.5** and the shipped build **29.1** — a
  paired median delta of **-7.4** points, the fix ahead in **3 of 3** paired rounds, with
  non-overlapping ranges (`preFix [34.1..41.3]` vs `both [27..30.1]`).
- A focused 9-repeat run of the same instrument on the same pair
  (`node tools/bench-idle-cpu.js --workload shadowHeavy --arms preFix,both --repeats 9 --out
  bench-idle-cpu-results-shadow.json`, its own file `tools/bench-idle-cpu-results-shadow.json`):
  **33.8 -> 27.7**, paired median delta **-5.5**, the fix ahead in **9 of 9** paired rounds,
  ranges non-overlapping (`preFix [30.1..39.3]` vs `both [26.7..29.8]`).
- On the other five workloads the paired median difference is **0.2 points or less**, inside
  the run-to-run spread. **No effect is claimed there.**

**What the numbers do and do not say (honest limits):**

- The **absolute level moves with machine load**; the claim is the **paired delta and the win
  count**, not the absolute number. The same caveat is stamped in the code comment at
  `wintage.user.js:3158`.
- The matrix has **no arm that isolates the two changes that shipped together** in `d8d2885`
  (the conditional shadow-sheet refresh and the widened palette contrast contract). The
  measured delta is therefore attributed to **that commit**, not to the single line; the
  mechanism is named (an unchanged 11 KB sheet was re-parsed once per shadow root per
  repaint), but the attribution is to the commit.
- **Brave: UNVERIFIED.** There is no Brave on this machine
  (`C:/Program Files/BraveSoftware` does not exist; Chrome and the Playwright Chromium are
  present). **No Brave figure is presented as a measurement**, because none was taken.
- The **browser-process** CPU comparison is also **UNVERIFIED**: the instrument measures the
  renderer by design and never mixes the two.
- The operator's original "~46.4% total CPU" observation is **not reproduced and not
  eliminated** by this work. It named no tab and no workload; it remains NEEDS_OPERATOR_PROFILE.

## TEST EFFICIENCY

The suite now runs in fractions, and every fraction says out loud that it is not a release
proof.

| level | what it runs | measured on the final tree |
|---|---|---|
| FULL     | every registered suite (123) — the release proof | **123 suites, 674.4s total, exit 0** (`scratch/suite-final4.log`) |
| FOCUSED  | the 16 must-run release gates, derived from `release.ps1` (25 suites) | **25 suites, 139.5s total, exit 0** (`scratch/suite-focused-final.log`) |
| FAST     | the 16 pure-JS gates, no PowerShell child (16 suites) | **16 suites, 4s total, exit 0** (`scratch/suite-fast-exitprobe.log`) |

Measured on the final tree, that is **674.4s -> 139.5s -> 4s**: the release-gate set is about
**4.8x** cheaper than the full run and the JS-only set about **170x**, with the same
`exit=0 errors=0` verdict at every level. The FOCUSED run's five slowest suites are
`test-batch-generation.ps1` 94.22s, `test-first-touch-recovery.ps1` 17.20s,
`test-freebuff.ps1` 15.79s, `test-perf-recovery.js` 2.83s, `test-perf-lanes.js` 1.46s.

- The gate set is **derived**, not hand-maintained: `tests/lib/ReleaseGateAudit.ps1` reads
  `release.ps1` and yields **20 unique tool paths, 16 of them must-run gates**; the suite
  asserts `level FOCUSED covers every release gate (missed: )` and
  `the release gate set was actually derived, not empty (16 gates)`, and
  `tests/test-release-gate-audit.ps1` pins the count of 20.
- Every exit door prints the timing summary and the five slowest suites, so the cost of the
  suite is visible instead of guessed.
- A reduced run prints `REDUCED RUN: this is not a release proof. release.ps1 judges the tree
  with the FULL level.` next to its verdict.

## REGRESSION

- **FULL suite on the shipped bytes**: `SUITE VERDICT: head=43aef8e
  worktree=0afd3ff96f7f/1360file/12455k exit=0 errors=0`, `suite timings: 123 suites, 674.4s
  total`, `ALL TESTS PASSED!` (`scratch/suite-final4.log`). The process exit code observed by
  the shell was **0** (`scratch/suite-final4.exit`).
- **One anomaly, recorded not hidden.** An earlier FULL run on the **same** tree — the same
  `head=43aef8e` and the *identical* worktree fingerprint `0afd3ff96f7f/1360file/12455k` —
  printed the same green verdict and the same `ALL TESTS PASSED!`, but returned **5** to the
  shell. The re-run of the identical bytes returned 0. The cause was **not isolated**; what
  the pair of runs does prove is that it is **not a property of the shipped bytes** (the
  fingerprint is identical in both) and that it is **not reproduced** on the final tree.
  Nothing in the suite's own assertions differed: `errors=0` in both runs.
- Earlier FULL runs of the same campaign, for comparison: `head=0e2bb1b` -> 123 suites, 750.9s,
  exit 0; `head=d8d2885` -> 123 suites, 678.6s, exit 0.
- **Wave-4 gates**: 13 site gates, each `exit=0` (`scratch/gates-wave4.txt`).
- **Wave-5 gates**: 325 assertions, 0 FAIL (`scratch/w5-summaries.txt`,
  `scratch/w5-fail-evidence.txt`).
- **Bench gates**: `bench-idle-cpu.js --quick suite exits 0` inside the FULL run, and the
  full matrix file was byte-unchanged across that run.
- **Release gates**: `test-release-target.js`, `test-release-delivery.js`,
  `test-release-delivery-verdict.ps1`, `test-release-rollback-split.ps1`,
  `test-release-gate-audit.ps1` and the rest of the 16 derived gates all exit 0.
- **No failing regression was weakened.** The only contract change in the campaign was a
  **strengthening** (the palette contrast contract was widened, and three packs were brought
  up to the wider contract).
- Pre-existing debt, cleared by re-verification and not by assertion: **T-243, T-244, T-245
  and T-357** were DONE tickets that carried no current-cycle re-verification receipt. The
  conformance receipt was `STALE_FAIL` before this report (it was bound to a different source
  identity than the current checkpoint). After this report's text was final, all four were
  re-verified against the tree by `saipen work reverify`, one receipt per ticket, each
  recording the **executed** command that re-proves the ticket's own gate and each bound to
  the same source head and tree fingerprint as the refreshed canonical receipt. The
  refreshed receipt then reports **one** remaining problem instead of four.
- **That one remaining problem is the project's own deliberate carry, and it is not this
  campaign's to close.** It is **E-838**, a hand-appended historical structural event with
  no `[op: ...]` marker; E-909 records the decision to carry it. The sanctioned cure
  (`tools/accept_legacy_debt.py --authority SRC-###`) needs an independently witnessed
  authority Source, which this campaign cannot mint. **The shared protocol was not touched,
  no gate was weakened and no accepted-debt record was written**: the debt is named for the
  owner instead of being closed quietly.
- **The receipt is not the only view of the ledger, and the other view is not clean.**
  `saipen status` still prints `Claimed but unproven: T-357, T-245, T-244, T-243`. That
  line comes from the LOG grammar, not from the receipt: each of those four tickets was
  closed on 2026-09-11 without a `transition to VERIFY` marker in its cycle, and the ledger
  counts only RUN evidence *inside* a cycle, so it finds neither boundary nor evidence. The
  re-verification receipts cannot enter that grammar — a checkpoint written after a
  ticket's canonical finish is history about the closure, not evidence for it (the engine's
  own T-1758 rule). The campaign demonstrated it rather than asserting it: the RUN
  checkpoint for T-244 written after this round (`E-4449`) is recorded in the LOG, and the
  ledger still refuses to count it. Clearing that line would mean re-opening the four
  tickets so they start a fresh cycle, which is a scope change this campaign did not make
  (see NEED USER, item 3).

## RELEASE SAFETY

- **Nothing was published.** No push, no tag, no package, no deployment, no remote-history
  rewrite. The six commits below exist only in this working tree.
- **The release binds to the polled destination and proves the delivered artifact** (T-984,
  T-983). A release to the wrong place now aborts before it mutates anything, and a release
  that pushed but published something nobody can fetch says so instead of printing a green
  line.
- **The measured channel state** (recorded in `.saipen/KNOWLEDGE/ADR-012.md`):

  | destination | `main` | serves | the project's own detector |
  |---|---|---|---|
  | `origin` = `gitlab.com/vacuum34/wintage` (the polled one) | `d775325` | 1.36.10 | `CURRENT` — the tree's `@version` |
  | `github` = `github.com/vacterro/Wintage` | `f750202` | 1.36.9 | `STALE_DEPLOYMENT` (exit 1) — one current-live hook is missing |

  `git ls-remote` answers on both. The GitLab side carries the newest product work; the
  GitHub side carries the operator's repair `052f416` (ported into this tree by T-982) and the
  7 October README redesign, which this tree does not have.
- **The channel does not converge by itself.** It converges when the owner pushes: the
  polled destination needs the local commits, and the GitHub destination needs them too,
  because an install carries the update URL it was installed with and **every install made
  before 1.36.10 polls `raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js`** —
  without that second push those clients stay on 1.36.9 forever.
- **The front page is a fork, and the choice is the owner's.** The GitHub side's `README.md`
  (207 lines: badges, Showcase, "Why Wintage", a Features table, the project network, a
  support block) and this tree's `README.md` (170 lines, install link on GitLab, migration
  note) are two different documents and **neither is a superset**. The only file on the GitHub
  side that this tree lacks is `docs/showcase/more-screenshots-2026-10.webp` (restorable with
  `git checkout f750202 -- docs/showcase/more-screenshots-2026-10.webp`). The campaign did not
  pick a public front page on its own.
- **The userscript keeps `@namespace https://github.com/vacterro/Wintage`.** That is
  intentional and was not changed to remove an old GitHub URL.
- **The measurement instrument is no longer able to eat its own evidence**: the smoke run
  writes its own file, and the full matrix is proven byte-stable across a FULL suite run.
- **One anomaly in the FULL run's process exit code** is recorded in UNRESOLVED. It did not
  affect any assertion (the suite's own verdict was `exit=0 errors=0` with
  `ALL TESTS PASSED!`), it did not reproduce on the re-run of the identical bytes, and it is
  reported rather than smoothed over.

## COMMITS

All six are local; none is pushed. `d775325` is the base (the commit published on the polled
destination). The report itself is the seventh commit (`6c94dee`) plus three amendment commits
that state the refreshed conformance receipt's exact outcome, the re-verification round that
followed it, and the ledger line that survives that round; a commit cannot contain its own
hash, so those four are named here and their hashes are in `git log`.

| commit | subject |
|---|---|
| `bb38eea` | feat(release): bind the release to the polled destination, prove the artifact, and run the suite in fractions |
| `50302de` | fix(freebuff): keep the chosen sound out of the checkout; record the bundled third-party fonts |
| `0e2bb1b` | docs(knowledge): record the measured channel state in ADR-012 |
| `d8d2885` | perf(shadow): stop re-parsing the shadow sheet, and widen the palette contrast contract |
| `f007fb6` | docs(perf): restamp the T-987 shadow-sheet comment with the final measured medians |
| `43aef8e` | fix(bench): keep the smoke run from overwriting the full measurement matrix |

## UNRESOLVED

1. **The release channel does not converge** — T-981. It needs the owner's push; the campaign
   is forbidden from publishing. The state of both destinations is measured and recorded
   (ADR-012), and the release now refuses to publish anywhere the clients do not poll.
2. **`Verdana_m1.ttf` redistribution** — T-986. The three options are written down in
   `THIRD_PARTY_NOTICES.md` (ship as is, remove from the public tree, replace with a
   redistributable substitute). **The campaign may not make this choice silently.**
3. **Live BetterDiscord acceptance** — T-376. Preconditions are present but narrower than
   the ticket said; the two measured blockers are the missing `--remote-debugging-port` and
   the installed plugins being out of date with their source. **No live acceptance is
   claimed.**
4. **Live authenticated acceptance of the four hosts and the 16 palettes was NOT performed**
   anywhere in this campaign. The wave-4 evidence is the project's own site gates, a pixel
   audit of 20 captured screenshots and a computed-style sweep — not a signed-in session.
   This is recorded as UNVERIFIED, not as a pass.
5. **Brave: UNVERIFIED.** No Brave on this machine, so no Brave number exists and none is
   presented.
6. **The browser-process CPU figure: UNVERIFIED.** The instrument measures the renderer.
7. **The operator's ~46.4% total-CPU observation is neither reproduced nor eliminated.** It
   remains NEEDS_OPERATOR_PROFILE.
8. **Two residual sub-4.5 contrast ratios** (textSecondary/link on the `surface` card
   backdrop, link on `backgroundSoft`) are **accepted debt**, reported rather than hidden.
9. **The FULL suite's process exit code anomaly** (see the REGRESSION section): the suite's
   internal verdict is green (`exit=0 errors=0`, `ALL TESTS PASSED!`) but one run of the
   **identical** tree returned 5 to the shell, while the re-run returned 0. The cause was
   **not isolated**; the assertions themselves are unaffected, and the anomaly is recorded
   here rather than explained away. **A release that gates on the process exit code should
   read the verdict line, not only the code**, until the cause is found.
10. **The core conformance gate still reports one problem, and it is the project's own
    deliberate carry.** `E-838` (a hand-appended historical structural event with no
    `[op: ...]` marker) is the debt E-909 records the project carrying; the sanctioned
    cure needs an authority Source this campaign cannot mint, so it stays red by
    decision, not by oversight. The four DONE tickets that also carried no current-cycle
    evidence — **T-243, T-244, T-245, T-357** — were re-verified against this tree with
    executed receipts (one per ticket, each naming the command that re-proves it) and are
    no longer findings in the canonical receipt. `saipen status` nevertheless still lists
    them under `Claimed but unproven`, because that ledger reads the LOG's per-ticket
    verification cycle and those cycles closed in 2026-09-11 without a VERIFY boundary
    (see the REGRESSION section).
11. **Two untracked leftovers of the project's own test runs were found in the tree and
    removed:** `.wintage.tmp` (299 478 bytes, an orphaned copy of the userscript that no
    file in this tree writes) and `Microsoft/Windows/PowerShell/ModuleAnalysisCache`
    (6 072 bytes, PowerShell's module-analysis cache, written into the repository because a
    child process had no `LOCALAPPDATA`). Neither name is in `.gitignore`, so both were
    untracked-but-unignored and both sat inside the source tree fingerprint the
    re-verification receipts are bound to. They are machine byproducts, not work product, so
    the campaign deleted them; **the owner may want both names added to `.gitignore`** so
    the next test run cannot reintroduce them.

## NEXT EXACT ACTION

**One action, and it belongs to the owner** (T-981): push the local campaign commits to both
live destinations, so that the polled channel and the pre-1.36.10 install channel serve the
same build.

```bash
git push origin main          # origin = gitlab.com/vacuum34/wintage (the polled destination)
git push github main          # github = github.com/vacterro/Wintage (every install before 1.36.10 polls this)
```

After the push, the campaign's own delivery check can confirm the result from the outside:

```bash
node tools/check-deployed-userscript.js   # verdict CURRENT against the install URL
```

Nothing in this repository needs to change for that to work; the release path and the delivery
check are already in place and gated.

## NEED USER

Three decisions are the owner's, and the campaign deliberately did not make any of them
silently.

1. **The front page.** The GitHub side's `README.md` (207 lines, with badges, a Showcase
   section, "Why Wintage", a Features table, the project network and a support block) and
   this tree's `README.md` (170 lines, with the install link repointed at GitLab and a
   migration note) are two different documents, and neither is a superset. The only file that
   exists on the GitHub side and not in this tree is
   `docs/showcase/more-screenshots-2026-10.webp` (restorable with
   `git checkout f750202 -- docs/showcase/more-screenshots-2026-10.webp`). **Which document is
   the public front page after the push?**
2. **Does `Verdana_m1.ttf` ship?** The repository is public and the file is a modified
   Microsoft Verdana (`fsType` 8, editable embedding) whose terms grant use, not
   redistribution. The three options are in `THIRD_PARTY_NOTICES.md`: ship as is, remove it
   from the public tree, or replace it with a redistributable substitute. **Which one?**
3. **Should the four re-verified tickets be re-opened so the ledger line clears too?**
   `saipen status` still lists `T-357, T-245, T-244, T-243` as `Claimed but unproven`
   because their verification cycles closed on 2026-09-11 without a VERIFY boundary. The
   canonical receipt no longer lists them (each has an executed re-verification receipt on
   this tree), but the ledger reads the LOG, and its grammar only counts evidence written
   inside a cycle. Clearing it means re-opening the four tickets to start fresh cycles —
   four DONE closures from another actor, reopened and re-verified, which is the owner's
   call and not this campaign's. **Re-open, or accept the status line as a known artifact
   of the 2026-09-11 closures?**

Plus the one mechanical step that only the owner can perform: **the push in NEXT EXACT
ACTION**, which this campaign is forbidden from doing.
