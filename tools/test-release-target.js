#!/usr/bin/env node
// Unit test for the release target identity gate (T-984).
//
// The gate under test: tools/check-release-target.js
//
// Every case is a fixture written to a temp directory and the REAL tool run
// against it as a child process, so the exit code the release reads is the one
// under test -- not a re-implementation of it. Nothing here touches the
// network, a real remote or the repository.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const TOOL = path.join(__dirname, 'check-release-target.js');
let failures = 0;
let checks = 0;

function assertTrue(cond, label) {
  checks++;
  if (cond) {
    console.log('[PASS] ' + label);
  } else {
    failures++;
    console.log('[FAIL] ' + label);
  }
}

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'wintage-release-target-'));

function fixture(name, updateUrl, downloadUrl) {
  // The gate compares the polled FILE NAME with the released file name, so
  // every fixture lives in its own directory under the real file name.
  const dir = path.join(tmp, name);
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, 'wintage.user.js');
  const lines = [
    '// ==UserScript==',
    '// @name         Wintage',
    '// @namespace    https://github.com/vacterro/Wintage',
    '// @version      1.0.0'
  ];
  if (updateUrl) lines.push('// @updateURL    ' + updateUrl);
  if (downloadUrl) lines.push('// @downloadURL  ' + downloadUrl);
  lines.push('// ==/UserScript==', 'const W95_VERSION = \'1.0.0\';', '');
  fs.writeFileSync(file, lines.join('\n'), 'utf8');
  return file;
}

function run(script, remoteUrl, extraArgs) {
  const args = ['--json', '--script', script, '--branch', 'main'];
  if (remoteUrl) args.push('--remote-url', remoteUrl);
  for (const a of (extraArgs || [])) args.push(a);
  const res = spawnSync(process.execPath, [TOOL].concat(args), { encoding: 'utf8' });
  let json = null;
  try { json = JSON.parse(res.stdout); } catch (e) { /* reported by the caller */ }
  return { code: res.status, stdout: res.stdout, stderr: res.stderr, json: json };
}

const GITLAB_RAW = 'https://gitlab.com/vacuum34/wintage/-/raw/main/wintage.user.js';
const GITLAB_REPO = 'https://gitlab.com/vacuum34/wintage.git';
const GITHUB_REPO = 'https://github.com/vacterro/Wintage.git';
const GITHUB_RAW = 'https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js';

// 1. The matching case: same repo, same branch, same file.
let script = fixture('match.js', GITLAB_RAW, GITLAB_RAW);
let r = run(script, GITLAB_REPO);
assertTrue(r.code === 0 && r.json && r.json.verdict === 'MATCH',
  'a destination that matches the polled URL is accepted (code ' + r.code + ', verdict ' + (r.json && r.json.verdict) + ')');

// 2. The defect this gate exists for: a release into the OTHER live remote.
r = run(script, GITHUB_REPO);
assertTrue(r.code === 1 && r.json && r.json.verdict === 'MISMATCH',
  'a destination that is not the polled repository is refused (code ' + r.code + ')');
assertTrue(r.json && /publishes to/.test(r.json.detail || ''),
  'the refusal names both sides (detail: ' + (r.json && r.json.detail) + ')');

// 3. The scp form of the same remote is the same repository.
r = run(script, 'git@gitlab.com:vacuum34/wintage.git');
assertTrue(r.code === 0 && r.json && r.json.verdict === 'MATCH',
  'the scp form of the same remote is accepted (code ' + r.code + ')');

// 4. The raw.githubusercontent.com host form resolves to the GitHub repository.
script = fixture('gh.js', GITHUB_RAW, GITHUB_RAW);
r = run(script, GITHUB_REPO);
assertTrue(r.code === 0 && r.json && r.json.verdict === 'MATCH',
  'the raw.githubusercontent.com form matches the GitHub remote (code ' + r.code + ')');
r = run(script, GITLAB_REPO);
assertTrue(r.code === 1, 'the raw.githubusercontent.com form does not match the GitLab remote (code ' + r.code + ')');

// 5. A polled branch that is not the published branch.
script = fixture('branch.js', 'https://gitlab.com/vacuum34/wintage/-/raw/dev/wintage.user.js', 'https://gitlab.com/vacuum34/wintage/-/raw/dev/wintage.user.js');
r = run(script, GITLAB_REPO);
assertTrue(r.code === 1 && r.json && /branch/.test(r.json.detail || ''),
  'a polled branch other than the published one is refused (code ' + r.code + ')');

// 6. A polled file that is not the released file.
script = fixture('file.js', 'https://gitlab.com/vacuum34/wintage/-/raw/main/other.user.js', 'https://gitlab.com/vacuum34/wintage/-/raw/main/other.user.js');
r = run(script, GITLAB_REPO);
assertTrue(r.code === 1 && r.json && /wintage\.user\.js/.test(r.json.detail || ''),
  'a polled file other than the released one is refused (code ' + r.code + ')');

// 7. @updateURL and @downloadURL pointing at different repositories.
script = fixture('split.js', GITLAB_RAW, GITHUB_RAW);
r = run(script, GITLAB_REPO);
assertTrue(r.code === 1 && r.json && /@downloadURL/.test(r.json.detail || ''),
  'an @updateURL and @downloadURL that disagree are refused (code ' + r.code + ')');

// 8. A script with no @updateURL cannot be verified -- UNKNOWN, not a verdict.
script = fixture('nourl.js', null, null);
r = run(script, GITLAB_REPO);
assertTrue(r.code === 2 && r.json && r.json.verdict === 'UNKNOWN',
  'a script with no @updateURL is UNKNOWN, not a false MATCH (code ' + r.code + ')');

// 9. An unreadable script is UNKNOWN too.
r = run(path.join(tmp, 'does-not-exist.js'), GITLAB_REPO);
assertTrue(r.code === 2 && r.json && r.json.verdict === 'UNKNOWN',
  'an unreadable script is UNKNOWN (code ' + r.code + ')');

// 10. A destination that is not a repository URL at all.
r = run(fixture('ok.js', GITLAB_RAW, GITLAB_RAW), 'not a url');
assertTrue(r.code === 2, 'a destination that is not a repository URL is UNKNOWN (code ' + r.code + ')');

// 11. A caller that could not read its push URL passes an EMPTY value. The
// gate used to drop it and re-resolve the remote itself, so the answer came
// from a different source of truth than the caller's: a release that failed
// to read its destination was told it was fine.
r = run(fixture('empty.js', GITLAB_RAW, GITLAB_RAW), null, ['--remote-url', '']);
assertTrue(r.code === 2 && r.json && r.json.verdict === 'UNKNOWN',
  'an empty push destination is UNKNOWN, not a silent re-resolution (code ' + r.code + ')');

// 12. Different download branch: @updateURL=main, @downloadURL=legacy.
const legacyBranchRaw = 'https://gitlab.com/vacuum34/wintage/-/raw/legacy/wintage.user.js';
script = fixture('dl-branch.js', GITLAB_RAW, legacyBranchRaw);
r = run(script, GITLAB_REPO);
assertTrue(r.code === 1 && r.json && (r.json.verdict === 'MISMATCH' || r.json.verdict === 'UNKNOWN'),
  'different download branch is not MATCH (code ' + r.code + ', verdict ' + (r.json && r.json.verdict) + ')');
assertTrue(r.json && /branch|disagree/.test(r.json.detail || ''),
  'different download branch names the disagreement (detail: ' + (r.json && r.json.detail) + ')');

// 13. Different download filename: @downloadURL points at legacy.user.js.
const legacyFileRaw = 'https://gitlab.com/vacuum34/wintage/-/raw/main/legacy.user.js';
script = fixture('dl-file.js', GITLAB_RAW, legacyFileRaw);
r = run(script, GITLAB_REPO);
assertTrue(r.code === 1 && r.json && (r.json.verdict === 'MISMATCH' || r.json.verdict === 'UNKNOWN'),
  'different download filename is not MATCH (code ' + r.code + ', verdict ' + (r.json && r.json.verdict) + ')');
assertTrue(r.json && /file|disagree/.test(r.json.detail || ''),
  'different download filename names the disagreement (detail: ' + (r.json && r.json.detail) + ')');

// 14. Different download repository: @downloadURL points at a different repo.
const diffRepoRaw = 'https://gitlab.com/other-user/wintage/-/raw/main/wintage.user.js';
script = fixture('dl-repo.js', GITLAB_RAW, diffRepoRaw);
r = run(script, GITLAB_REPO);
assertTrue(r.code === 1 && r.json && (r.json.verdict === 'MISMATCH' || r.json.verdict === 'UNKNOWN'),
  'different download repository is not MATCH (code ' + r.code + ', verdict ' + (r.json && r.json.verdict) + ')');
assertTrue(r.json && /repository|disagree/.test(r.json.detail || ''),
  'different download repository names the disagreement (detail: ' + (r.json && r.json.detail) + ')');

// 15. HTTP @updateURL: scheme must be HTTPS.
const httpUpdateUrl = 'http://gitlab.com/vacuum34/wintage/-/raw/main/wintage.user.js';
script = fixture('http-update.js', httpUpdateUrl, GITLAB_RAW);
r = run(script, GITLAB_REPO);
assertTrue(r.code !== 0, 'HTTP update URL is not MATCH (code ' + r.code + ')');
assertTrue(r.json && /HTTPS|https/.test(r.json.detail || ''),
  'HTTP update URL is rejected with a transport message (detail: ' + (r.json && r.json.detail) + ')');

// 16. HTTP @downloadURL: scheme must be HTTPS.
const httpDownloadUrl = 'http://gitlab.com/vacuum34/wintage/-/raw/main/wintage.user.js';
script = fixture('http-download.js', GITLAB_RAW, httpDownloadUrl);
r = run(script, GITLAB_REPO);
assertTrue(r.code !== 0, 'HTTP download URL is not MATCH (code ' + r.code + ')');
assertTrue(r.json && /HTTPS|https/.test(r.json.detail || ''),
  'HTTP download URL is rejected with a transport message (detail: ' + (r.json && r.json.detail) + ')');

// 17. Missing @updateURL and @downloadURL: UNKNOWN.
script = fixture('missing-urls.js', null, null);
r = run(script, GITLAB_REPO);
assertTrue(r.code === 2 && r.json && r.json.verdict === 'UNKNOWN',
  'a script with no @updateURL and no @downloadURL is UNKNOWN (code ' + r.code + ', verdict ' + (r.json && r.json.verdict) + ')');

// 18. Malformed @updateURL: UNKNOWN (not a false MATCH).
script = fixture('malformed.js', 'not-a-valid-url', GITLAB_RAW);
r = run(script, GITLAB_REPO);
assertTrue(r.code === 2, 'a malformed @updateURL is UNKNOWN, not MATCH (code ' + r.code + ')');

// 19. Negative control: a non-matching repo in download URL must be caught by the
//   three-way repo check, not silently pass.
script = fixture('neg-ctrl.js', GITHUB_RAW, 'https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js');
r = run(script, GITLAB_REPO);
assertTrue(r.code === 1, 'GitLab push target vs GitHub update/download URLs is MISMATCH (code ' + r.code + ')');

// 20. Negative control: branch mismatch in updateURL must be caught.
script = fixture('neg-branch.js', 'https://gitlab.com/vacuum34/wintage/-/raw/dev/wintage.user.js', 'https://gitlab.com/vacuum34/wintage/-/raw/dev/wintage.user.js');
r = run(script, GITLAB_REPO);
assertTrue(r.code === 1, 'dev branch in update/download URLs vs main push target is MISMATCH (code ' + r.code + ')');

// 21. Negative control: filename mismatch in updateURL must be caught.
script = fixture('neg-file.js', 'https://gitlab.com/vacuum34/wintage/-/raw/main/other.user.js', 'https://gitlab.com/vacuum34/wintage/-/raw/main/other.user.js');
r = run(script, GITLAB_REPO);
assertTrue(r.code === 1, 'other.user.js in update/download URLs vs wintage.user.js push target is MISMATCH (code ' + r.code + ')');

fs.rmSync(tmp, { recursive: true, force: true });

console.log('');
if (failures > 0) {
  console.log('TESTS FAILED (' + failures + ' of ' + checks + ' checks)');
  process.exitCode = 1;
} else {
  console.log('ALL TESTS PASSED (' + checks + ' checks)');
  process.exitCode = 0;
}
