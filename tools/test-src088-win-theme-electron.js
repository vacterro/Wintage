#!/usr/bin/env node
// SRC-088 regression suite for W2-002 + W2-004 (audit/10.md).
//
// W2-004 (install-windows-theme.js): the Revert branch used to accept the mere
// physical existence of `Wintage.original.theme` as proof of a live install and
// ignored the retired-epoch marker. After Apply -> Revert -> Finalize the epoch
// is RETIRED, the snapshot file is deliberately KEPT (Windows may still hold it),
// and a second Revert therefore used to hand that stale snapshot back as an
// activation target — overriding a theme the user picked AFTER Revert. Revert is
// now epoch-aware: retired + no live install => a machine-readable no-op with
// NO activation target.
//
// W2-002 (install-electron.js): sidecar cleanup and rollback errors were
// swallowed, so a Revert with an EPERM on a sidecar unlink exited 0 with the
// orphan behind, and a failed repaint rollback claimed "restored the exact
// pre-operation state" while the visible palette still differed. Remove/restore
// now return structured per-file failures and every caller PROVES the result
// before claiming success.
//
// Source-based: drives the two REAL Node helpers as child processes against
// isolated temp fixtures, and verifies the on-disk state independently of exit
// code and log text. Each defect has a positive case (defect reproduced against
// the fix => honest failure) AND a negative control (the same operation WITHOUT
// the injected fault => the happy/exact-restore path still holds, proving a
// nonzero/INCOMPLETE verdict is caused by the fault and not by a broken tool).

const fs = require('fs');
const os = require('os');
const path = require('path');
const cp = require('child_process');

const WIN = path.join(__dirname, 'install-windows-theme.js');
const ELECTRON = path.join(__dirname, 'install-electron.js');

let bad = 0;
const check = (label, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  console.log((ok ? 'PASS: ' : 'FAIL: ') + label
    + (ok ? '' : '\n        got  = ' + JSON.stringify(got) + '\n        want = ' + JSON.stringify(want)));
  if (!ok) bad++;
};
const checkT = (label, got, predicate) => {
  const ok = !!predicate(got);
  console.log((ok ? 'PASS: ' : 'FAIL: ') + label
    + (ok ? '' : '\n        got  = ' + JSON.stringify(got)));
  if (!ok) bad++;
};

const temps = [];
function tempDir(tag) {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'wintage-src088-' + tag + '-'));
  temps.push(d);
  return d;
}

function run(tool, args, env) {
  try {
    const out = cp.execFileSync(process.execPath, [tool].concat(args),
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], env: Object.assign({}, process.env, env || {}) });
    return { code: 0, out };
  } catch (e) {
    return { code: e.status === undefined ? 1 : e.status, out: (e.stdout || '') + (e.stderr || '') };
  }
}
function jsonOut(r) { try { return JSON.parse((r.out || '').trim()); } catch (e) { return null; } }

// ═════════════════ W2-004: Windows theme Revert is epoch-aware ════════════════

const THEME_BODY = (tag) => [
  '; Wintage test theme ' + tag,
  '[Theme]',
  'DisplayName=' + tag,
  '',
  '[Control Panel\\Colors]',
  'Background=' + tag.length + ' 0 0',
  '',
  '[VisualStyles]',
  'Path=%SystemRoot%\\resources\\themes\\Aero\\Aero.msstyles',
  ''
].join('\r\n');

function winFixture(tag) {
  const dir = tempDir('win-' + tag);
  const themesDir = path.join(dir, 'Themes');
  fs.mkdirSync(themesDir, { recursive: true });
  const overlay = path.join(dir, 'overlay.theme');
  const current = path.join(themesDir, 'UserChoice.theme');
  fs.writeFileSync(overlay, THEME_BODY('OVERLAY'), 'utf8');
  fs.writeFileSync(current, THEME_BODY('USER-ONE'), 'utf8');
  return { dir, themesDir, overlay, current };
}
const winApply = (f, cur) => run(WIN, ['--themes-dir', f.themesDir, '--theme', f.overlay, '--current-theme', (cur || f.current), '--palette', 'goldendefault']);
const winRevert = (f) => run(WIN, ['--themes-dir', f.themesDir, '--revert']);
const winFinalize = (f) => run(WIN, ['--themes-dir', f.themesDir, '--finalize-revert']);

{
  const f = winFixture('retired');
  const original = path.join(f.themesDir, 'Wintage.original.theme');
  const retired = path.join(f.themesDir, '.wintage-epoch-retired');

  check('W2-004: apply exits 0', winApply(f).code, 0);
  const r1 = winRevert(f);
  const j1 = jsonOut(r1);
  check('W2-004: live revert exits 0', r1.code, 0);
  check('W2-004: live revert hands back the snapshot to activate', j1 && j1.activate, original);
  check('W2-004: live revert is NOT flagged a no-op', j1 && j1.noop, undefined);
  check('W2-004: finalize exits 0', winFinalize(f).code, 0);
  check('W2-004: epoch is retired after finalize', fs.existsSync(retired), true);
  check('W2-004: finalize KEEPS the retired snapshot (Windows may reference it)', fs.existsSync(original), true);

  // The defect: a second Revert after finalization must be a NO-OP, not hand the
  // stale snapshot back as an activation target.
  const r2 = winRevert(f);
  const j2 = jsonOut(r2);
  check('W2-004: second revert exits 0 (idempotent, not a hard failure)', r2.code, 0);
  check('W2-004: second revert is reported as a no-op', j2 && j2.noop, true);
  check('W2-004: second revert reports retired', j2 && j2.retired, true);
  check('W2-004: second revert hands back NO activation target', j2 && j2.activate, null);
  check('W2-004: a no-op result names no cleanup', j2 && j2.cleanup, []);
  check('W2-004: retired snapshot survives the no-op revert', fs.existsSync(original), true);
}

{
  // The user picks a DIFFERENT theme after the completed Revert; a further Revert
  // must leave that choice untouched and must not re-activate the old snapshot.
  const f = winFixture('userchoice');
  const original = path.join(f.themesDir, 'Wintage.original.theme');
  const userTwo = path.join(f.themesDir, 'UserTwo.theme');
  winApply(f);
  winRevert(f);
  winFinalize(f);
  fs.writeFileSync(userTwo, THEME_BODY('USER-TWO'), 'utf8');
  const userTwoBytes = fs.readFileSync(userTwo);

  const r2 = jsonOut(winRevert(f));
  check('W2-004: revert after user re-picked hands back NO activation target', r2 && r2.activate, null);
  check("W2-004: the user's post-revert theme file is left byte-for-byte", fs.readFileSync(userTwo).equals(userTwoBytes), true);

  // Apply after retirement must re-baseline from the NEW current theme.
  const a3 = jsonOut(winApply(f, userTwo));
  check('W2-004: apply after retirement is a first apply again', a3 && a3.firstApply, true);
  check('W2-004: the new baseline is the new current theme',
    fs.existsSync(original) && fs.readFileSync(original, 'utf8'), THEME_BODY('USER-TWO'));
}

// ═════════════════════ W2-002: Electron checked cleanup / rollback ═════════════

function buildAsar(file, pkg, withIntegrity) {
  const data = Buffer.from(JSON.stringify(pkg, null, 2), 'utf8');
  const entry = { size: data.length, offset: '0' };
  if (withIntegrity) entry.integrity = { hash: 'a'.repeat(64) };
  const json = Buffer.from(JSON.stringify({ files: { 'package.json': entry } }), 'utf8');
  const jsonLen = json.length;
  const pickleSize = 8 + jsonLen + (4 - ((8 + jsonLen) % 4 || 4));
  const base = 8 + pickleSize;
  const head = Buffer.alloc(16);
  head.writeUInt32LE(4, 0);
  head.writeUInt32LE(pickleSize, 4);
  head.writeUInt32LE(jsonLen, 8);
  head.writeUInt32LE(jsonLen, 12);
  const pad = Buffer.alloc(base - 16 - jsonLen);
  fs.writeFileSync(file, Buffer.concat([head, json, pad, data]));
}
const FUSE_SENTINEL = Buffer.from('dL7pKGdnNz796PbbjQWNKmHXBZaB9tsX');
function buildFusedExe() {
  const head = Buffer.alloc(2);
  head[0] = 1; head[1] = 8;
  const fuses = Buffer.alloc(8);
  fuses.fill(0x30);
  fuses[5] = 0x31;
  fuses[6] = 0x31;
  return Buffer.concat([Buffer.from('MZ fake exe '), FUSE_SENTINEL, head, fuses, Buffer.from(' padding')]);
}
const PKG = (version) => ({ name: 'FakeApp', version, main: 'src/main/entry/index.js'.padEnd(40, '.') });

function elFixture(tag) {
  const dir = tempDir('el-' + tag);
  const R = path.join(dir, 'resources');
  fs.mkdirSync(R, { recursive: true });
  fs.writeFileSync(path.join(dir, 'FakeApp.exe'), buildFusedExe());
  return { dir, R };
}
const elApply = (R) => run(ELECTRON, ['--resources', R, '--in-place', '--palette', 'goldendefault']);
const elRevert = (R, env) => run(ELECTRON, ['--resources', R, '--in-place', '--revert'], env);
const elRepaint = (R, pal, env) => run(ELECTRON, ['--resources', R, '--in-place', '--palette', pal], env);
const SIDECARS = ['wintage-shim.cjs', 'wintage.css', 'wintage-palette.txt', 'wintage-status.txt'];
const present = (R) => SIDECARS.filter(f => fs.existsSync(path.join(R, f)));

// ---- W2-002 REPRODUCTION A: incomplete Revert cleanup must fail honestly -----
{
  const { R } = elFixture('revert-ep');
  buildAsar(path.join(R, 'app.asar'), PKG('1.0.0'), true);
  const stock = fs.readFileSync(path.join(R, 'app.asar'));
  check('A: apply (themed-inplace) exits 0', elApply(R).code, 0);
  // A successful in-place apply transiently removes wintage-status.txt, so the
  // live owned sidecars are shim/css/palette.
  check('A: pre-revert owns the live sidecars', present(R), ['wintage-shim.cjs', 'wintage.css', 'wintage-palette.txt']);

  // POSITIVE: EPERM specifically on removing wintage.css during --revert.
  const r = elRevert(R, { WINTAGE_TEST_FAIL_UNLINK: 'wintage.css' });
  checkT('A: revert exits NONZERO when a required sidecar cannot be removed', r.code, c => c !== 0);
  check('A: wintage.css is really still on disk (the orphan)', fs.existsSync(path.join(R, 'wintage.css')), true);
  check('A: the other owned sidecars were still removed (partial cleanup)', present(R), ['wintage.css']);
  checkT('A: report names the undeleted sidecar', r.out, o => /wintage\.css/.test(o));
  checkT('A: report says the revert is incomplete', r.out, o => /incomplete/i.test(o));
  checkT('A: report does NOT print the clean-revert success line', r.out, o => !/restored original app\.asar from backup/.test(o));

  // NEGATIVE CONTROL: identical fixture, no injected fault => clean success,
  // proving the nonzero verdict above is caused by the seam, not a broken tool.
  const { R: R2 } = elFixture('revert-ok');
  buildAsar(path.join(R2, 'app.asar'), PKG('1.0.0'), true);
  const ok = elApply(R2);
  check('A-control: apply exits 0', ok.code, 0);
  const rr = elRevert(R2);
  check('A-control: clean revert exits 0', rr.code, 0);
  check('A-control: clean revert removes every owned sidecar', present(R2), []);
  checkT('A-control: clean revert reports the restored original', rr.out, o => /restored original app\.asar from backup/.test(o));
  check('A-control: the archive is restored byte-exact to stock', fs.readFileSync(path.join(R2, 'app.asar')).equals(stock), true);
}

// ---- W2-002 REPRODUCTION B: false exact-rollback claim on failed repaint -----
{
  const { R } = elFixture('repaint-bad');
  buildAsar(path.join(R, 'app.asar'), PKG('1.0.0'), true);
  check('B: apply (themed-inplace) exits 0', elApply(R).code, 0);
  const prePalette = fs.readFileSync(path.join(R, 'wintage-palette.txt'), 'utf8').trim();
  const preShim = fs.readFileSync(path.join(R, 'wintage-shim.cjs'));
  checkT('B: pre-repaint palette is goldendefault', prePalette, p => p === 'goldendefault');

  // POSITIVE: the repaint itself fails (existing seam) AND the rollback cannot
  // write the old palette marker back (per-file write EPERM). The tool must not
  // claim it restored the exact pre-state while the palette still shows `nord`.
  const r = elRepaint(R, 'nord', { WINTAGE_TEST_FAIL_AFTER_REPAINT: '1', WINTAGE_TEST_FAIL_WRITE: 'wintage-palette.txt' });
  checkT('B: failing repaint exits NONZERO', r.code, c => c !== 0);
  const nowPalette = fs.readFileSync(path.join(R, 'wintage-palette.txt'), 'utf8').trim();
  checkT('B: the palette on disk is NOT the pre-state', nowPalette, p => p !== prePalette);
  check('B: the visible palette is the NEW one (nord) that rollback failed to undo', nowPalette, 'nord');
  check('B: the UNaffected sidecar (shim) was still rolled back', fs.readFileSync(path.join(R, 'wintage-shim.cjs')).equals(preShim), true);
  checkT('B: report says the rollback is INCOMPLETE', r.out, o => /INCOMPLETE/.test(o));
  checkT('B: report does NOT claim an exact pre-operation restore', r.out, o => !/restored the exact pre-operation state/.test(o));

  // NEGATIVE CONTROL: same failing repaint, but the rollback write is NOT
  // blocked => rollback truly completes => the exact-restore claim is honest.
  const { R: R2 } = elFixture('repaint-ok');
  buildAsar(path.join(R2, 'app.asar'), PKG('1.0.0'), true);
  elApply(R2);
  const r2Pre = fs.readFileSync(path.join(R2, 'wintage-palette.txt'), 'utf8').trim();
  const rc = elRepaint(R2, 'nord', { WINTAGE_TEST_FAIL_AFTER_REPAINT: '1' });
  checkT('B-control: failing repaint exits NONZERO', rc.code, c => c !== 0);
  check('B-control: palette rolled back to the exact pre-state', fs.readFileSync(path.join(R2, 'wintage-palette.txt'), 'utf8').trim(), r2Pre);
  checkT('B-control: with a proven rollback the exact-restore claim is still made', rc.out, o => /restored the exact pre-operation state/.test(o));
}

for (const d of temps) { try { fs.rmSync(d, { recursive: true, force: true }); } catch (e) { } }
console.log(bad ? '\n' + bad + ' failure(s)' : '\nSRC-088 W2-002/W2-004 regression PASS');
process.exit(bad ? 1 : 0);
