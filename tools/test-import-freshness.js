// CORE-004 (SRC-005:R004): the imported-theme freshness gate must be a REAL
// comparison under the exact release invocation. The pre-fix `--check` printed
// "freshness check skipped" and exited 0 when no FastPrompter checkout was
// available, so a hand-edited imported pack passed the gate that advertises it
// cannot. The repair verifies every imported pack against the committed
// sha256 fingerprint set (tools/fastprompter-fingerprints.json):
//
//   1. the exact release invocation performs a real comparison, never a skip;
//   2. mutating one imported token makes --check exit NONZERO;
//   3. restoring the pack makes --check exit 0 again;
//   4. release.ps1's regen-contract wiring still aborts on a nonzero exit;
//   5. the fingerprint file is NOT inside themes/ (theme-schema.js loads every
//      .json there as a pack; a non-pack file breaks every consumer).
//
//   node tools/test-import-freshness.js          # run
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const TOOL = path.join(__dirname, 'import-fastprompter.js');
const FP_FILE = path.join(__dirname, 'fastprompter-fingerprints.json');
const THEME_DIR = path.join(ROOT, 'themes');

let pass = 0, fail = 0;
const check = (label, cond) => {
  if (cond) { console.log('PASS: ' + label); pass++; }
  else { console.log('FAIL: ' + label); fail++; }
};

const run = (args) => {
  try {
    const out = execFileSync(process.execPath, [TOOL, ...args], { encoding: 'utf8', stdio: 'pipe' });
    return { code: 0, out };
  } catch (e) {
    return { code: e.status == null ? 1 : e.status, out: (e.stdout || '') + (e.stderr || '') };
  }
};

// ── 5. fingerprint file placement ────────────────────────────────────────────
check('r004: the fingerprint file lives beside the tool, not in themes/',
  fs.existsSync(FP_FILE) && !fs.existsSync(path.join(THEME_DIR, 'fastprompter-fingerprints.json')));

// ── 1. the exact release invocation ──────────────────────────────────────────
const clean = run(['--check']);
check('r004: the exact release invocation (--check, no source) exits 0', clean.code === 0);
check('r004: the exact release invocation performs a REAL comparison (no skip message)',
  /match their FastPrompter fingerprints/.test(clean.out) && !/skipped/i.test(clean.out));

// ── 2. a hand-edit must FAIL the gate ────────────────────────────────────────
const pack = path.join(THEME_DIR, 'fpdefault.json');
const original = fs.readFileSync(pack, 'utf8');
if (!/"background": "#[0-9A-F]{6}"/.test(original)) {
  check('r004: fixture could not locate the background token in fpdefault.json', false);
} else {
  fs.writeFileSync(pack, original.replace(/"background": "#[0-9A-F]{6}"/, '"background": "#123456"'));
  const red = run(['--check']);
  check('r004: a hand-edited imported pack makes --check exit NONZERO', red.code !== 0);
  check('r004: the drift is named (pack + expected/got digests)',
    /DRIFT fpdefault\.json/.test(red.out) && /no longer matches the FastPrompter import/.test(red.out));
  check('r004: the failure message says the only legitimate path is the import',
    /only be changed by re-running the import/.test(red.out));

  // ── 3. restoring the pack is green again ───────────────────────────────────
  fs.writeFileSync(pack, original);
  const green = run(['--check']);
  check('r004: restoring the pack makes --check exit 0 again', green.code === 0);
}

// ── 4. release.ps1 aborts on the failing check ───────────────────────────────
const releaseSrc = fs.readFileSync(path.join(ROOT, 'release.ps1'), 'utf8');
check('r004: release.ps1 runs import-fastprompter --check in the regen contracts',
  /import-fastprompter\.js['"]?\)\s+--check/.test(releaseSrc));
const abortLine = releaseSrc.match(/import-fastprompter\.js['"]?\)\s+--check\s*\r?\n\s*if \(\$LASTEXITCODE -ne 0\) \{ throw/);
check('r004: release.ps1 throws on the failing freshness check', abortLine !== null);

// ── 6. missing fingerprint file fails closed (never a skip) ──────────────────
const fpBackup = fs.readFileSync(FP_FILE, 'utf8');
fs.unlinkSync(FP_FILE);
const missing = run(['--check']);
fs.writeFileSync(FP_FILE, fpBackup);
check('r004: a MISSING fingerprint file FAILS the check (fail closed, never skip)', missing.code !== 0);
check('r004: the missing-fingerprint message names the recovery command',
  /--write-fingerprints/.test(missing.out));

console.log('\n' + pass + ' PASS, ' + fail + ' FAIL');
process.exit(fail);
