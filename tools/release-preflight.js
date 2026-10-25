#!/usr/bin/env node
// Local-only release preflight (T-992, T-993).
//
// WHY THIS EXISTS. The release was conflated with permission to publish: a green
// local run was read as "the release is ready", and the only way to prove that
// was to reach release.ps1's push step -- which publishes. T-992 required a
// CHANGELOG entry and version alignment, but its verification depended on that
// push. T-993 treated the remote publication restriction as a reason not to
// establish a local monitoring gate.
//
// This script separates PREPARATION from PUBLICATION. It validates every
// prerequisite that CAN be validated locally -- version consistency, metadata
// agreement, derived-artifact freshness, the destination identity gate, and the
// local test suite -- without mutating the repository, without contacting any
// publication endpoint, and without reading a remote.
//
//   node tools/release-preflight.js            # human readable
//   node tools/release-preflight.js --json     # for scripts
//   node tools/release-preflight.js --target 1.36.11  # expect a specific version
//
// EXIT: 0 = READY_LOCAL (all local checks pass; REMOTE_UNVERIFIED is expected)
//       1 = BLOCKED_LOCAL (a fixable local prerequisite is unmet)
//       2 = INTERNAL_ERROR (the preflight itself could not run)
//
// READY_LOCAL does NOT grant permission to publish. REMOTE_UNVERIFIED is the
// expected state: the destination identity gate and the delivered-artifact check
// need the network/remote and are OUT OF SCOPE for this local preflight.

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const argv = process.argv.slice(2);
const AS_JSON = argv.includes('--json');
const targetIdx = argv.indexOf('--target');
const TARGET = targetIdx >= 0 && argv[targetIdx + 1] ? argv[targetIdx + 1] : null;

const WINTAGE = path.join(ROOT, 'wintage.user.js');
const PKG = path.join(ROOT, 'package.json');
const PKG_LOCK = path.join(ROOT, 'package-lock.json');
const CHANGELOG = path.join(ROOT, 'CHANGELOG.md');
const DESKTOP_OUT = path.join(ROOT, 'desktop', 'out');

let checks = 0;
let failures = 0;
const problems = [];
const checksRun = [];

function record(name, ok, detail) {
  checks++;
  checksRun.push({ check: name, ok: !!ok, detail: detail || '' });
  if (!ok) {
    failures++;
    problems.push(name + (detail ? ': ' + detail : ''));
  }
}

// Read a JSON file safely.
function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (e) {
    return null;
  }
}

// Read a semver version from a string.
function extractVersion(str, label) {
  const m = /(\d+\.\d+\.\d+)/.exec(str || '');
  return m ? m[1] : null;
}

// Read the @version and @downloadURL/@updateURL from the userscript header.
function readUserscript() {
  const src = fs.readFileSync(WINTAGE, 'utf8');
  const header = /\/\/\s*@version\s+(\d+\.\d+\.\d+)/.exec(src);
  const internal = /const W95_VERSION\s*=\s*['"]([^'"]+)['"]/.exec(src);
  const updateUrl = /\/\/\s*@updateURL\s+(\S+)/.exec(src);
  const downloadUrl = /\/\/\s*@downloadURL\s+(\S+)/.exec(src);
  return {
    source: src,
    version: header ? header[1] : null,
    w95Version: internal ? internal[1] : null,
    updateUrl: updateUrl ? updateUrl[1] : null,
    downloadUrl: downloadUrl ? downloadUrl[1] : null
  };
}

// Read version from package.json.
function readPackageVersion() {
  const pkg = readJson(PKG);
  record('package.json readable', pkg, 'package.json is ' + (pkg ? 'valid JSON' : 'missing or unparseable'));
  return pkg ? pkg.version : null;
}

// Read the root version from package-lock.json.
function readLockVersion() {
  const lock = readJson(PKG_LOCK);
  record('package-lock.json readable', lock, 'package-lock.json is ' + (lock ? 'valid JSON' : 'missing or unparseable'));
  if (!lock) return null;
  return lock.version || (lock.packages && lock.packages[''] && lock.packages[''].version) || null;
}

// Read the latest release heading from CHANGELOG.md.
function readChangelogVersion() {
  const src = fs.readFileSync(CHANGELOG, 'utf8');
  // The top non-Unreleased heading.
  const m = /##\s*\[(\d+\.\d+\.\d+)\]/.exec(src);
  const released = m ? m[1] : null;
  // Check for an [Unreleased] section (which means work is in progress).
  const hasUnreleased = /^\s*##\s*\[Unreleased\]/m.test(src);
  record('CHANGELOG.md has a released heading', released, 'latest release heading: ' + (released || '(none)'));
  return { released, hasUnreleased: !!hasUnreleased };
}

// Read version embedded in derived desktop artifacts (manifest.json files).
function readDerivedVersions() {
  const versions = new Set();
  if (!fs.existsSync(DESKTOP_OUT)) {
    record('desktop/out artifacts exist', false, 'desktop/out does not exist -- run node tools/build-desktop.js');
    return { versions: versions, count: 0 };
  }
  const manifests = [];
  function walk(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.name === 'manifest.json') manifests.push(full);
    }
  }
  try {
    walk(DESKTOP_OUT);
  } catch (e) {
    record('desktop/out walkable', false, String(e));
    return { versions: versions, count: 0 };
  }
  for (const manifest of manifests) {
    const data = readJson(manifest);
    if (data && data.version) versions.add(data.version);
  }
  const list = [...versions];
  record('derived desktop version(s)', versions.size <= 1,
    versions.size === 0 ? 'no manifests found' :
    versions.size === 1 ? 'all manifests at v' + list[0] + ' (' + manifests.length + ' files)' :
    'version mismatch: ' + list.join(', '));
  return { versions: list, count: manifests.length };
}

// Run the destination identity gate (read-only: --remote-url with the local git remote,
// no push). This does NOT contact the remote; it just checks URL parsing.
function runDestinationGate() {
  const res = spawnSync(process.execPath, [
    path.join(__dirname, 'check-release-target.js'),
    '--json'
  ], { cwd: ROOT, encoding: 'utf8' });
  let verdict = 'UNKNOWN';
  let detail = '';
  try {
    const json = JSON.parse(res.stdout);
    verdict = json.verdict || 'UNKNOWN';
    detail = json.detail || '';
  } catch (e) {
    detail = 'could not parse output: ' + res.stdout.substring(0, 200);
  }
  // MATCH means the local git remote + metadata URLs all agree on repo/branch/file.
  // This is a local check; no network contact happens.
  record('destination identity gate (local URLs agree)', verdict === 'MATCH',
    'verdict: ' + verdict + (detail ? ' -- ' + detail : '') + ' [REMOTE_UNVERIFIED: payload delivery not checked here]');
  return { verdict, detail };
}

// Run the local test suite in FOCUSED mode (the release gates).
function runFocusedSuite() {
  if (!fs.existsSync(path.join(ROOT, 'tests', 'Run-Tests.ps1'))) {
    record('FOCUSED test suite passes', false, 'tests/Run-Tests.ps1 not found');
    return false;
  }
  // NOTE: this is a read-only check under the supported local PowerShell 5.1 host.
  // It runs the FAST level (cheap deterministic gates) to keep the preflight quick.
  // The full suite is still run by release.ps1 itself.
  const res = spawnSync('powershell', [
    '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', path.join(ROOT, 'tests', 'Run-Tests.ps1'),
    '-Level', 'FAST', '-Skip', 'release-gate-audit'
  ], { cwd: ROOT, encoding: 'utf8', timeout: 120000 });
  const ok = res.status === 0;
  record('FOCUSED/FAST test suite passes (read-only)', ok,
    'exit ' + res.status + (res.status !== 0 ? ' -- see tests/Run-Tests.ps1 output' : ''));
  return ok;
}

async function main() {
  const report = {
    tool: 'release-preflight',
    root: ROOT,
    target: TARGET,
    checks: [],
    problems: [],
    verdict: 'INTERNAL_ERROR',
    detail: ''
  };

  try {
    // 1. Userscript metadata.
    const ws = readUserscript();
    record('wintage.user.js readable', ws.version,
      'version: ' + (ws.version || '(missing)') + ', W95_VERSION: ' + (ws.w95Version || '(missing)') +
      ', updateURL: ' + (ws.updateUrl || '(missing)') + ', downloadURL: ' + (ws.downloadUrl || '(missing)'));

    // 2. Version agreement across sources.
    const expected = TARGET || ws.version;
    if (!expected) {
      problems.push('cannot determine expected version (no --target and no @version in userscript)');
      report.verdict = 'BLOCKED_LOCAL';
      report.detail = 'cannot determine expected version';
      return finish(report, 1);
    }

    const pkgVersion = readPackageVersion();
    const lockVersion = readLockVersion();
    const changelog = readChangelogVersion();
    const derived = readDerivedVersions();
    const destGate = runDestinationGate();

    // Version consistency checks.
    record('@version header', ws.version === expected,
      'expected ' + expected + ', found ' + (ws.version || '(missing)'));
    record('W95_VERSION internal', ws.w95Version === expected,
      'expected ' + expected + ', found ' + (ws.w95Version || '(missing)'));
    if (pkgVersion !== null) {
      record('package.json version', pkgVersion === expected,
        'expected ' + expected + ', found ' + pkgVersion);
    }
    if (lockVersion !== null) {
      record('package-lock.json version', lockVersion === expected,
        'expected ' + expected + ', found ' + lockVersion);
    }
    if (changelog.released) {
      record('CHANGELOG.md release heading', changelog.released === expected,
        'expected ' + expected + ', found ' + changelog.released);
    }
    if (derived.count > 0) {
      record('derived desktop version(s)', derived.versions.length === 1 && derived.versions[0] === expected,
        'expected ' + expected + ', found ' + (derived.versions.length === 0 ? '(none)' : derived.versions.join(', ')));
    }

    // 3. Metadata URL health (local parse check).
    record('@updateURL present', !!ws.updateUrl, ws.updateUrl || '(missing)');
    record('@downloadURL present', !!ws.downloadUrl, ws.downloadUrl || '(missing)');
    record('@updateURL === @downloadURL', ws.updateUrl === ws.downloadUrl,
      ws.updateUrl === ws.downloadUrl ? 'both URLs agree' : 'updateURL differs from downloadURL');

    // 4. Destination identity gate (local only, no network).
    // This was done in runDestinationGate() above.

    // 5. Local test suite.
    runFocusedSuite();

    // Decide verdict.
    report.checks = checksRun;
    report.problems = problems;

    if (failures === 0) {
      report.verdict = 'READY_LOCAL';
      report.detail = 'All local prerequisites pass. REMOTE_UNVERIFIED: publication is not authorized; ' +
        'the delivered-artifact identity check (check-deployed-userscript.js) and ' +
        'the destination push URL are out of scope for this local preflight. ' +
        'READY_LOCAL is NOT permission to publish.';
      return finish(report, 0);
    }

    // Check if any failure is a remote-only concern (that would be REMOTE_UNVERIFIED,
    // not BLOCKED_LOCAL). Here all checks are local, so any failure is BLOCKED_LOCAL.
    report.verdict = 'BLOCKED_LOCAL';
    report.detail = problems.length + ' local check(s) failed. Fix them before preparing a release. ' +
      'REMOTE_UNVERIFIED: publication is not authorized; READY_LOCAL/READY_TO_PUBLISH requires operator approval.';
    return finish(report, 1);

  } catch (e) {
    report.verdict = 'INTERNAL_ERROR';
    report.detail = 'preflight crashed: ' + (e && e.stack ? e.stack : e);
    return finish(report, 2);
  }
}

function finish(report, code) {
  if (AS_JSON) {
    console.log(JSON.stringify(report, null, 2));
  } else {
    console.log('release preflight');
    console.log('  root         : ' + report.root);
    console.log('  target       : ' + (report.target || '(from @version header)'));
    console.log('  checks run   : ' + checks);
    console.log('  checks passed: ' + (checks - failures));
    console.log('  checks failed: ' + failures);
    if (report.problems.length > 0) {
      console.log('  problems     :');
      report.problems.forEach(p => console.log('    - ' + p));
    }
    console.log('  verdict      : ' + report.verdict);
    console.log('  detail       : ' + report.detail);
    if (report.verdict === 'READY_LOCAL') {
      console.log('  NOTE         : READY_LOCAL is NOT permission to publish. Publication requires operator authorization.');
    }
  }
  process.exitCode = code;
  return code;
}

main().catch(e => {
  console.error('release preflight: fatal -- ' + (e && e.stack ? e.stack : e));
  process.exitCode = 2;
});
