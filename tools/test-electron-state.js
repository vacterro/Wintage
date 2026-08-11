#!/usr/bin/env node
// Electron apply/revert state-machine regression suite (T-189).
//
// install-electron.js must classify the filesystem state (STOCK / THEMED_RELOCATED
// / UPDATED_RELOCATED / THEMED_INPLACE / UPDATED_INPLACE / AMBIGUOUS) from the
// actual layout and make Revert restore the CURRENT app version — never an old
// moved archive or a stale backup. Each scenario builds fake app.asar archives
// (minimal valid asar layout with a package.json) in a temp resources dir and
// drives the real tool as a child process.

const fs = require('fs');
const os = require('os');
const path = require('path');
const cp = require('child_process');

const ROOT = path.join(__dirname, '..');
const TOOL = path.join(__dirname, 'install-electron.js');
let bad = 0;

const check = (label, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  console.log((ok ? 'PASS: ' : 'FAIL: ') + label + (ok ? '' : '  got=' + JSON.stringify(got) + ' want=' + JSON.stringify(want)));
  if (!ok) bad++;
};

// Minimal valid asar: [u32=4][u32 pickleSize][u32 jsonSize][u32 jsonLen][json][pad][file]
function buildAsar(file, pkg) {
  const data = Buffer.from(JSON.stringify(pkg, null, 2), 'utf8');
  const json = Buffer.from(JSON.stringify({ files: { 'package.json': { size: data.length, offset: '0' } } }), 'utf8');
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

const PKG = (version) => ({ name: 'FakeApp', version, main: 'src/main/entry/index.js'.padEnd(40, '.') });

function run(args, env) {
  try {
    const out = cp.execSync('node "' + TOOL + '" ' + args, { encoding: 'utf8', stdio: 'pipe', env: Object.assign({}, process.env, env || {}) });
    return { code: 0, out: out.trim() };
  } catch (e) {
    return { code: e.status || 1, out: ((e.stdout || '') + (e.stderr || '')).trim() };
  }
}

function status(resources, inPlace) {
  const r = run('--resources "' + resources + '"' + (inPlace ? ' --in-place' : '') + ' --status-json');
  if (r.code !== 0) return null;
  return JSON.parse(r.out);
}

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'wintage-elstate-'));
const mk = (name) => { const d = path.join(tmp, name, 'resources'); fs.mkdirSync(d, { recursive: true }); return d; };

// ---- Relocation mode ----
{
  const R = mk('relo');
  buildAsar(path.join(R, 'app.asar'), PKG('1.0.0'));
  const s0 = status(R, false);
  check('stock state classified', s0.state, 'stock');
  check('stock version read', s0.version, '1.0.0');
  check('stock healthy=false', s0.healthy, false);

  // Apply v1 (relocation)
  let r = run('--resources "' + R + '" --palette goldendefault');
  check('relocation apply v1 exits 0', r.code, 0);
  const s1 = status(R, false);
  check('after apply: themed-relocated', s1.state, 'themed-relocated');
  check('after apply: version is v1 via moved asar', s1.version, '1.0.0');
  check('after apply: healthy=true', s1.healthy, true);
  check('after apply: palette recorded', s1.palette, 'goldendefault');
  // --version works after relocation (P0#7)
  const v1 = run('--resources "' + R + '" --version');
  check('--version after relocation reads moved asar', v1.out, '1.0.0');

  // App update: v2 stock archive lands at root while the old relocation remains.
  buildAsar(path.join(R, 'app.asar'), PKG('2.0.0'));
  const s2 = status(R, false);
  check('app update classified as updated-relocated', s2.state, 'updated-relocated');
  check('updated-relocated reports CURRENT root version', s2.version, '2.0.0');

  // Reapply must recover: retire stale relocation, install v2, v2 becomes rollback.
  r = run('--resources "' + R + '" --palette goldendefault');
  check('reapply onto updated-relocated exits 0', r.code, 0);
  const s3 = status(R, false);
  check('after reapply: themed-relocated again', s3.state, 'themed-relocated');
  check('after reapply: version is v2', s3.version, '2.0.0');

  // Revert must restore v2 stock, NEVER v1.
  r = run('--resources "' + R + '" --revert');
  check('revert exits 0', r.code, 0);
  const vAfter = status(R, false);
  check('after revert: state stock', vAfter.state, 'stock');
  check('after revert: root app.asar restored', fs.existsSync(path.join(R, 'app.asar')), true);
  check('after revert: Wintage app dir removed', fs.existsSync(path.join(R, 'app')), false);
  // Re-read version via tool to confirm v2, not v1.
  const vAfter2 = run('--resources "' + R + '" --version');
  check('revert restores v2, never v1', vAfter2.out, '2.0.0');
}

// ---- Relocation partial-move rollback (P0#8) ----
{
  const R = mk('rollback');
  buildAsar(path.join(R, 'app.asar'), PKG('1.0.0'));
  const asarBytes = fs.readFileSync(path.join(R, 'app.asar'));
  const r = run('--resources "' + R + '" --palette goldendefault', { WINTAGE_TEST_FAIL_UNPACKED_MOVE: '1' });
  check('partial-move failure exits NONZERO', r.code !== 0, true);
  check('rollback: root app.asar restored byte-identical', fs.readFileSync(path.join(R, 'app.asar')).equals(asarBytes), true);
  check('rollback: incomplete app dir removed', fs.existsSync(path.join(R, 'app')), false);
}

// ---- In-place mode ----
{
  const R = mk('inplace');
  buildAsar(path.join(R, 'app.asar'), PKG('1.0.0'));
  let r = run('--resources "' + R + '" --in-place --palette goldendefault');
  check('in-place apply v1 exits 0', r.code, 0);
  const s1 = status(R, true);
  check('in-place apply: themed-inplace', s1.state, 'themed-inplace');
  check('in-place apply: version v1', s1.version, '1.0.0');
  check('in-place apply: palette', s1.palette, 'goldendefault');

  // App update: v2 stock asar lands, stale v1 backup + shim remain.
  const v1Bak = fs.readFileSync(path.join(R, 'app.asar.bak'));
  buildAsar(path.join(R, 'app.asar'), PKG('2.0.0'));
  const s2 = status(R, true);
  check('in-place update classified as updated-inplace', s2.state, 'updated-inplace');
  check('updated-inplace reports CURRENT root version', s2.version, '2.0.0');

  // Reapply: current stock v2 becomes the new pristine backup, then patched.
  r = run('--resources "' + R + '" --in-place --palette goldendefault');
  check('reapply onto updated-inplace exits 0', r.code, 0);
  const s3 = status(R, true);
  check('after reapply: themed-inplace', s3.state, 'themed-inplace');
  check('after reapply: version v2', s3.version, '2.0.0');
  const newBak = fs.readFileSync(path.join(R, 'app.asar.bak'));
  check('stale v1 backup no longer the rollback authority', !newBak.equals(v1Bak), true);

  // Revert must restore v2 stock byte-exact, never v1.
  r = run('--resources "' + R + '" --in-place --revert');
  check('in-place revert exits 0', r.code, 0);
  const vAfter = run('--resources "' + R + '" --in-place --version');
  check('in-place revert restores v2, never v1', vAfter.out, '2.0.0');
  const sAfter = status(R, true);
  check('after revert: stock state', sAfter.state, 'stock');
}

// ---- Revert on a fresh stock (nothing owned) stays a no-op, not a failure ----
{
  const R = mk('stockrevert');
  buildAsar(path.join(R, 'app.asar'), PKG('1.0.0'));
  const r = run('--resources "' + R + '" --revert');
  check('revert on untouched stock exits 0 (nothing owned)', r.code, 0);
  check('revert on untouched stock leaves app.asar', fs.existsSync(path.join(R, 'app.asar')), true);
}

// ---- Ambiguous refusal ----
{
  const R = mk('ambiguous');
  // app/ exists but not ours, no root asar
  fs.mkdirSync(path.join(R, 'app'), { recursive: true });
  fs.writeFileSync(path.join(R, 'app', 'foreign.txt'), 'not ours');
  const r = run('--resources "' + R + '" --palette goldendefault');
  check('ambiguous app/ is refused', r.code !== 0, true);
  check('ambiguous refusal leaves everything in place', fs.existsSync(path.join(R, 'app', 'foreign.txt')), true);
}

fs.rmSync(tmp, { recursive: true, force: true });
console.log(bad ? '\n' + bad + ' failure(s)' : '\nelectron state-machine test PASS');
process.exit(bad ? 1 : 0);
