agent: saipen-cli-01
role: core
model_or_runtime: unknown
project: vacterro-wintage
saipen_version: 8.1.0
protocol_fingerprint: sha256:8e8dbdcbb3b14381b858d306a9e75aee21a058203837605c50bc0b7c8aef132d
source_head: 66790d592398803eafd2deb900d86eab3c63d1df
source_tree_fingerprint: git-delta-v1:980fbe253cd26fe7fb3d0ba366b6d0cd18c241dadbe6c80ca011af5827a27607
discovery_model: git-delta-v1
context_scope: SAIPEN audit, phase DONE
context_available: partial
report_status: complete

## RUN 1

Scope: the SAIPEN surfaces this seat exercised while closing T-414, T-415 and T-416 and closing out the wave that produced commits 4ff154d, c234716, 73b4fcc and 66790d5 in vacterro/wintage on 2026-10-05: the phase lifecycle BUILD -> VERIFY -> REVIEW -> SHIP -> DONE, the suite the evidence rests on, the reporting the seat produced for those tickets, and the memory/commit boundary the closing writes crossed.

Method: every expected/actual pair below is a measurement taken on this checkout during this RUN (the gate commands, git plumbing, the retained suite transcripts under /tmp/rt-t414-*.txt and .saipen/logs/run-tests-last.txt), not a reading of the documentation. Where a hypothesis was not established the class says so.

IMP-001 [P2] [LOGIC_ERROR] [reproduced] [ticket] Two full suite runs on one committed tree printed the same identity and disagreed about the verdict.
  expected: for a fixed tree -- same HEAD, same worktree delta -- tests/Run-Tests.ps1 returns the same verdict, so a red verdict is a statement about the tree.
  actual: run D and run E on head 73b4fcc printed byte-identical identity lines 'head=73b4fcc worktree=69c6b861371b/520path/3367k'; D ended exit=1 errors=1 with the single failing check named as tools/test-browser-cache.ps1, E ended exit=0 errors=0 with 284 [PASS] and no failing assertion. That gate alone, run twice on the same tree, returned 'test-browser-cache.ps1: 75 PASS / 0 FAIL / 0 SKIP', so no property of the judged tree explains the red: the suite's verdict is load-dependent, and a red run cannot be read as evidence about the tree it names.
  evidence: /tmp/rt-t414-d.txt lines 318-321 ('failing checks (1): - test-browser-cache.ps1 suite exits 0' then the verdict line exit=1 errors=1) against /tmp/rt-t414-e.txt line 316 (the same verdict line at exit=0 errors=0); 284 [PASS] and no [FAIL] in E versus 283 [PASS] in D; 'powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-browser-cache.ps1' twice -> 75 PASS / 0 FAIL / 0 SKIP, exit 0 both times.

IMP-002 [P2] [LOGIC_ERROR] [reproduced] [ticket] The new worktree identity hashes the index as well as the worktree, so a foreign index prints as a tree change while an index-hidden text change prints as none.
  expected: the worktree= field distinguishes two trees whose judged content differs, and stays put when only the index moves.
  actual: the payload is the dirty path list plus the text of 'git diff HEAD', and that diff is index-influenced. This checkout carries a foreign pre-staged wave, so tools/stamp-readme-digests.ps1 has no index entry while its worktree bytes equal HEAD's blob, and the diff for it reports 160 deletions of a file that matches HEAD -- an index-only change that moves the fingerprint, and roughly 3367k of foreign delta hashed into every run. In the other direction, a tracked file whose only difference from HEAD is line-ending normalization has an empty text delta, so an edit git normalizes away leaves worktree= unchanged; .saipen/kitchen/digest.md is such a file and git says so on every add.
  evidence: 'git ls-files -s -- tools/stamp-readme-digests.ps1' empty, 'git cat-file -e HEAD:tools/stamp-readme-digests.ps1' succeeds, 'git status --porcelain -uall' prints both 'D  tools/stamp-readme-digests.ps1' and '?? tools/stamp-readme-digests.ps1', and 'git diff HEAD --stat -- tools/stamp-readme-digests.ps1' -> '1 file changed, 160 deletions(-)'; 'warning: in the working copy of .saipen/kitchen/digest.md, LF will be replaced by CRLF the next time Git touches it'.

IMP-003 [P3] [LOGIC_ERROR] [reproduced] [ticket] The commit-scope gate defaults to the live staged index, so in any checkout that keeps another session's staged wave it fails every ticket.
  expected: 'tools/test-commit-scope.ps1 -Ticket T-414' judges the commit the caller is about to make.
  actual: invoked with the default target it judged the live index and returned 'RESULT: 1 PASS, 1 FAIL' with '[FAIL] unattributed paths in a T-414 commit: 260 -- .saipen/KNOWLEDGE/ADR-008.md, .saipen/KNOWLEDGE/ADR-009.md, ...', while the commit actually staged held four standard memory paths; the same command under GIT_INDEX_FILE pointing at the private index returned '2 PASS, 0 FAIL ... every path is attributable: 0 product, 4 standard memory'. The gate is usable only when the caller hides the live index itself, and neither its output nor the ticket that introduced it says so, so its green result is easy to obtain on the wrong target and its red result is noise on the right one.
  evidence: the two outputs above, produced minutes apart in this session on one tree, from tools/test-commit-scope.ps1 (T-418).

IMP-004 [P3] [PROTOCOL_VIOLATION] [reproduced] [ticket] A ticket-named commit carried three earlier waves' ignore rules and the scope gate admitted them.
  expected: the commit whose message names T-414 contains that ticket's delta plus the memory writes T-414 produced -- the rule T-418's own gate exists to enforce.
  actual: 73b4fcc 'T-414: the suite says which tree it judged and what failed' adds four separate .gitignore groups in one commit: this ticket's .saipen/logs/ line, the desktop/out.staging/ rule whose comment names T-396, the _AUDAPACK_MANIFEST.json rule whose comment names T-348, and the .audapack/ group whose comment names T-350. Those three predate this wave and were uncommitted in the worktree; the gate passed them because attribution is per path (declared with -Path) and only LOG.md gets line-level ownership, so one declared path admits unrelated lines inside it.
  evidence: 'git diff-tree -p -r 73b4fcc -- .gitignore' shows all four groups; the T-414 scope-gate run over that same staged set reported '2 PASS, 0 FAIL'.

IMP-005 [P3] [OTHER] [reproduced] [note] The evidence a red run leaves behind cannot ship, and every verdict line addresses it by a path only this machine can open.
  expected: the artifact that explains a red verdict is reachable from the delivered result.
  actual: the retained transcript lives in a directory the repository ignores on purpose (.gitignore line 51: .saipen/logs/), and each verdict line prints an absolute machine-local path in its log= field, so a reader of the archive cannot open the run whose name they are shown, and the T-417 delivery-claim resolver refuses a claim naming that file as unshippable -- the ship digest had to name the directory instead of the transcript.
  evidence: '.gitignore:51 .saipen/logs/'; the verdict line's 'log=<abs>\.saipen\logs\run-tests-last.txt' field in both retained transcripts; the resolver run over the digest printing '[ok] tests/Run-Tests.ps1', '[ok] tools/test-browser-cache.ps1' and 'RESULT: 2 claim(s): 2 resolved in the artifact' only after the ignored transcript path was removed from the digest text.

No finding in this RUN contradicts the three tickets: their delivered behaviour is what the tickets claim, and each of the five observations above is a property of the surrounding machinery (the suite's determinism, the identity's inputs, the gate's default target, the commit boundary, the evidence's portability) rather than a retraction of a delivered clause.
