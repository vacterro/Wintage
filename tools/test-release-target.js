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

fs.rmSync(tmp, { recursive: true, force: true });

console.log('');
if (failures > 0) {
  console.log('TESTS FAILED (' + failures + ' of ' + checks + ' checks)');
  process.exitCode = 1;
} else {
  console.log('ALL TESTS PASSED (' + checks + ' checks)');
  process.exitCode = 0;
}
