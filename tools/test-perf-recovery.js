#!/usr/bin/env node
// PERF-001 (SRC-004:R013): Electron recovery must not scale in MEMORY with the
// size of the application it is protecting.
//
// The pre-fix shape stacked whole-binary Buffers across both transaction layers:
//   * captureRevertPreState read the live archive, its .bak, the executable and
//     the fuse backup into RAM;
//   * captureAppDir then read the MOVED archive and the complete
//     app.asar.unpacked tree into more Buffers, so the same archive was resident
//     TWICE (pre.movedAsar and appPre['app.asar']);
//   * installInPlace held a full pre-patch Buffer (preAsar) IN ADDITION to the
//     on-disk .bak copy it had just written.
// The audit measured +192.1 MiB RSS for a 64 MiB archive plus a 64 MiB unpacked
// file, i.e. roughly one byte of RSS per recovery byte, precisely during
// Apply/Revert where memory pressure is least welcome.
//
// Recovery is now a durable on-disk vault plus in-memory IDENTITY (size +
// streamed SHA-256). This gate measures the property the audit named -- peak RSS
// stays approximately FIXED as the fixture grows -- and then proves the fix did
// not buy that with correctness: every existing failure seam still restores the
// large files byte-exactly, and an incomplete rollback still names its recovery
// locations.
//
// Usage: node tools/test-perf-recovery.js   (exit 0 = pass, 1 = fail)

const fs = require('fs');
const os = require('os');
const path = require('path');
const cp = require('child_process');
const crypto = require('crypto');

const TOOL = path.join(__dirname, 'install-electron.js');
const SRC = fs.readFileSync(TOOL, 'utf8');

let bad = 0;
const check = (label, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  console.log((ok ? 'PASS: ' : 'FAIL: ') + label
    + (ok ? '' : '  got=' + JSON.stringify(got) + ' want=' + JSON.stringify(want)));
  if (!ok) bad++;
};

// Same minimal-but-valid asar layout the state-machine suite builds, with a
// PAYLOAD tail so the archive can be made arbitrarily large without changing its
// header or its package.json entry.
function buildAsar(file, pkg, padBytes) {
  const data = Buffer.from(JSON.stringify(pkg, null, 2), 'utf8');
  const entry = { size: data.length, offset: '0' };
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
  const fd = fs.openSync(file, 'w');
  try {
    fs.writeSync(fd, Buffer.concat([head, json, pad, data]));
    if (padBytes > 0) {
      // Written in 4 MiB slices so the FIXTURE builder does not itself become the
      // memory hog this gate is measuring.
      const chunk = Buffer.alloc(4 * 1024 * 1024, 0x41);
      let left = padBytes;
      while (left > 0) {
        const n = Math.min(left, chunk.length);
        fs.writeSync(fd, chunk, 0, n);
        left -= n;
      }
    }
  } finally { fs.closeSync(fd); }
}

const FUSE_SENTINEL = Buffer.from('dL7pKGdnNz796PbbjQWNKmHXBZaB9tsX');
function buildFusedExe(padBytes) {
  const head = Buffer.alloc(2);
  head[0] = 1; head[1] = 8;
  const fuses = Buffer.alloc(8);
  fuses.fill(0x30);
  fuses[5] = 0x31;
  fuses[6] = 0x31;
  const core = Buffer.concat([Buffer.from('MZ fake exe '), FUSE_SENTINEL, head, fuses, Buffer.from(' padding')]);
  if (!padBytes) return core;
  return Buffer.concat([core, Buffer.alloc(padBytes, 0x42)]);
}

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'wintage-perfrec-'));
const PKG = (version) => ({ name: 'FakeApp', version, main: 'src/main/entry/index.js'.padEnd(40, '.') });

function mk(name, exePad) {
  const d = path.join(tmp, name, 'resources');
  fs.mkdirSync(d, { recursive: true });
  fs.writeFileSync(path.join(tmp, name, 'FakeApp.exe'), buildFusedExe(exePad));
  return d;
}

function writeBig(file, bytes, fill) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const fd = fs.openSync(file, 'w');
  try {
    const chunk = Buffer.alloc(4 * 1024 * 1024, fill);
    let left = bytes;
    while (left > 0) {
      const n = Math.min(left, chunk.length);
      fs.writeSync(fd, chunk, 0, n);
      left -= n;
    }
  } finally { fs.closeSync(fd); }
}

function sha(p) {
  const h = crypto.createHash('sha256');
  const fd = fs.openSync(p, 'r');
  try {
    const buf = Buffer.alloc(65536);
    for (;;) {
      const n = fs.readSync(fd, buf, 0, buf.length, null);
      if (!n) break;
      h.update(buf.subarray(0, n));
    }
  } finally { fs.closeSync(fd); }
  return h.digest('hex');
}

// Peak RSS is a property only the child can report (spawnSync gives no rusage on
// Windows), so the tool prints it under a test seam. Parsed off stderr.
function run(args, env) {
  const r = cp.spawnSync(process.execPath, [TOOL].concat(args), {
    encoding: 'utf8',
    env: Object.assign({}, process.env, { WINTAGE_TEST_REPORT_RSS: '1' }, env || {})
  });
  const err = r.stderr || '';
  const m = /wintage-rss: (\d+)/.exec(err);
  return {
    code: r.status === null ? 1 : r.status,
    out: ((r.stdout || '') + err).trim(),
    rssKiB: m ? Number(m[1]) : null
  };
}

// ══ 1. RSS stays approximately fixed as the recovery set grows ══════════════
// The audit's own two sizes. A relocation Revert is the worst pre-fix path: it
// held the moved archive twice plus the unpacked tree plus the exe.
const MiB = 1024 * 1024;
const measurements = [];
for (const sizeMiB of [16, 64, 256]) {
  const R = mk('rss-' + sizeMiB, 2 * MiB);
  buildAsar(path.join(R, 'app.asar'), PKG('1.0.0'), sizeMiB * MiB);
  writeBig(path.join(R, 'app.asar.unpacked', 'native', 'addon.node'), sizeMiB * MiB, 0x43);

  let r = run(['--resources', R, '--palette', 'goldendefault']);
  check('rss ' + sizeMiB + ' MiB: apply exits 0', r.code, 0);

  // The measured operation: a Revert whose rollback path is exercised, so every
  // capture helper runs. WINTAGE_TEST_FAIL_AFTER_REVERT forces the full rollback.
  r = run(['--resources', R, '--revert'], { WINTAGE_TEST_FAIL_AFTER_REVERT: '1' });
  check('rss ' + sizeMiB + ' MiB: forced-rollback revert exits NONZERO', r.code !== 0, true);
  check('rss ' + sizeMiB + ' MiB: the child reported its peak RSS', typeof r.rssKiB === 'number', true);
  measurements.push({ sizeMiB, rssKiB: r.rssKiB });
  fs.rmSync(path.join(tmp, 'rss-' + sizeMiB), { recursive: true, force: true });
}

console.log('        peak RSS by fixture size: '
  + measurements.map(m => m.sizeMiB + ' MiB -> ' + (m.rssKiB / 1024).toFixed(1) + ' MiB RSS').join(', '));

const smallest = measurements[0];
const largest = measurements[measurements.length - 1];
const growthKiB = largest.rssKiB - smallest.rssKiB;
const fixtureGrowthKiB = (largest.sizeMiB - smallest.sizeMiB) * 1024 * 2; // archive + unpacked
// Pre-fix this was ~1 byte of RSS per recovery byte, so a 240 MiB fixture growth
// meant ~480 MiB of RSS growth. The bar is deliberately generous (5% of the
// fixture growth): the point is that RSS is no longer PROPORTIONAL, not that it
// is bit-for-bit constant.
check('PERF-001: peak RSS does not scale with the recovery set (<5% of fixture growth)',
  growthKiB < fixtureGrowthKiB * 0.05, true);
check('PERF-001: and it stays under 256 MiB even for a 256 MiB archive + 256 MiB unpacked',
  largest.rssKiB < 256 * 1024, true);

// ══ 1b. The in-place lane has its own recovery set and its own budget ═══════
// installInPlace used to hold the whole pre-patch archive as `preAsar` IN
// ADDITION to the `.bak` copy it had just written to disk one line earlier.
// Measured separately because the relocation numbers above never touch it.
const inplaceMeasurements = [];
for (const sizeMiB of [16, 256]) {
  const R = mk('rss-ip-' + sizeMiB, 2 * MiB);
  buildAsar(path.join(R, 'app.asar'), PKG('1.0.0'), sizeMiB * MiB);
  // The seam fires AFTER the sidecars are written, so the rollback path runs too.
  const r = run(['--resources', R, '--in-place', '--palette', 'goldendefault'],
    { WINTAGE_TEST_FAIL_AFTER_ASAR_WRITE: '1' });
  check('rss in-place ' + sizeMiB + ' MiB: forced-rollback apply exits NONZERO', r.code !== 0, true);
  check('rss in-place ' + sizeMiB + ' MiB: the child reported its peak RSS', typeof r.rssKiB === 'number', true);
  inplaceMeasurements.push({ sizeMiB, rssKiB: r.rssKiB });
  fs.rmSync(path.join(tmp, 'rss-ip-' + sizeMiB), { recursive: true, force: true });
}
console.log('        peak RSS, in-place lane: '
  + inplaceMeasurements.map(m => m.sizeMiB + ' MiB -> ' + (m.rssKiB / 1024).toFixed(1) + ' MiB RSS').join(', '));
const ipGrowthKiB = inplaceMeasurements[1].rssKiB - inplaceMeasurements[0].rssKiB;
const ipFixtureGrowthKiB = (inplaceMeasurements[1].sizeMiB - inplaceMeasurements[0].sizeMiB) * 1024;
check('PERF-001: in-place peak RSS does not scale with the archive either',
  ipGrowthKiB < ipFixtureGrowthKiB * 0.05, true);

// ══ 2. No path keeps two in-memory copies of the same archive ═══════════════
check('PERF-001: the second full Buffer of the moved archive is gone (pre.movedAsar)',
  /pre\.movedAsar\s*=\s*fs\.readFileSync/.test(SRC), false);
check('PERF-001: only its PRESENCE is recorded now',
  /pre\.movedAsarExisted = fs\.existsSync\(movedAsar\)/.test(SRC), true);
check('PERF-001: the in-place pre-patch Buffer is gone (preAsar)',
  /const preAsar = fs\.readFileSync\(asar\)/.test(SRC), false);
check('PERF-001: snapshotPath stores a vault reference, not a Buffer',
  /kind: 'file', size: st\.size, sha: hashFile\(p\), vault: vaultStore\(p\)/.test(SRC), true);
check('PERF-001: comparison is size + digest, not Buffer.equals',
  /a\.size === b\.size && a\.sha === b\.sha/.test(SRC) && !/a\.buf\.equals\(b\.buf\)/.test(SRC), true);
check('PERF-001: the digest is streamed through a bounded window',
  /Buffer\.alloc\(65536\)/.test(SRC), true);
// STRUCTURAL, and said plainly rather than dressed up as behaviour: the in-place
// rollback authority moved from an in-memory Buffer to the on-disk `.bak`, so
// that copy must be proven to match the live archive BEFORE the first write.
// Triggering a silently-wrong copyFileSync would need a seam invented purely for
// this gate, so the pin is on the source. The controls below still prove the
// assertion can fail.
check('PERF-001: the on-disk rollback authority is digest-verified before patching',
  /does not match the live archive - refusing to patch without a verified rollback source/.test(SRC), true);

// ══ 3. Correctness was not traded away: every seam still restores exactly ═══
// Small fixtures, real byte comparison. If the vault indirection lost a byte
// anywhere, these are where it shows.
const RELO_SEAMS = [
  'WINTAGE_TEST_FAIL_AFTER_STAGING_MOVE',
  'WINTAGE_TEST_FAIL_AFTER_ASAR_MOVE',
  'WINTAGE_TEST_FAIL_UNPACKED_MOVE',
  'WINTAGE_TEST_FAIL_VERIFY'
];
for (const seam of RELO_SEAMS) {
  const R = mk('seam-' + seam, 0);
  buildAsar(path.join(R, 'app.asar'), PKG('1.0.0'), 3 * MiB);
  writeBig(path.join(R, 'app.asar.unpacked', 'native', 'addon.node'), 2 * MiB, 0x44);
  const asarSha = sha(path.join(R, 'app.asar'));
  const unpackedSha = sha(path.join(R, 'app.asar.unpacked', 'native', 'addon.node'));
  const r = run(['--resources', R, '--palette', 'goldendefault'], { [seam]: '1' });
  check('seam ' + seam + ': exits NONZERO', r.code !== 0, true);
  check('seam ' + seam + ': root archive restored byte-exactly',
    fs.existsSync(path.join(R, 'app.asar')) && sha(path.join(R, 'app.asar')) === asarSha, true);
  check('seam ' + seam + ': unpacked tree restored byte-exactly',
    fs.existsSync(path.join(R, 'app.asar.unpacked', 'native', 'addon.node'))
      && sha(path.join(R, 'app.asar.unpacked', 'native', 'addon.node')) === unpackedSha, true);
}

// In-place: the rollback now reads the verified on-disk .bak instead of a Buffer.
for (const seam of ['WINTAGE_TEST_FAIL_AFTER_SIDECARS', 'WINTAGE_TEST_FAIL_AFTER_ASAR_WRITE']) {
  const R = mk('inplace-' + seam, 0);
  buildAsar(path.join(R, 'app.asar'), PKG('1.0.0'), 3 * MiB);
  const asarSha = sha(path.join(R, 'app.asar'));
  const r = run(['--resources', R, '--in-place', '--palette', 'goldendefault'], { [seam]: '1' });
  check('inplace ' + seam + ': exits NONZERO', r.code !== 0, true);
  check('inplace ' + seam + ': archive restored byte-exactly from the on-disk backup',
    sha(path.join(R, 'app.asar')) === asarSha, true);
}

// ══ 4. A failed relocation Revert still keeps exactly one archive copy ══════
{
  const R = mk('revert-exact', 0);
  buildAsar(path.join(R, 'app.asar'), PKG('1.0.0'), 3 * MiB);
  writeBig(path.join(R, 'app.asar.unpacked', 'native', 'addon.node'), 1 * MiB, 0x45);
  const asarSha = sha(path.join(R, 'app.asar'));
  const unpackedSha = sha(path.join(R, 'app.asar.unpacked', 'native', 'addon.node'));
  let r = run(['--resources', R, '--palette', 'goldendefault']);
  check('revert-exact: apply exits 0', r.code, 0);
  r = run(['--resources', R, '--revert'], { WINTAGE_TEST_FAIL_AFTER_REVERT: '1' });
  check('revert-exact: forced-rollback revert exits NONZERO', r.code !== 0, true);
  check('revert-exact: the moved archive is back and byte-exact',
    fs.existsSync(path.join(R, 'app', 'app.asar')) && sha(path.join(R, 'app', 'app.asar')) === asarSha, true);
  check('revert-exact: no duplicate at root',
    fs.existsSync(path.join(R, 'app.asar')), false);
  check('revert-exact: exactly one unpacked copy, byte-exact',
    [fs.existsSync(path.join(R, 'app.asar.unpacked')),
     fs.existsSync(path.join(R, 'app', 'app.asar.unpacked', 'native', 'addon.node'))
       && sha(path.join(R, 'app', 'app.asar.unpacked', 'native', 'addon.node')) === unpackedSha],
    [false, true]);
  check('revert-exact: the rollback claim is honest',
    /rolled back to the exact pre-operation state/.test(r.out), true);
  check('revert-exact: a SUCCESSFUL rollback still drops its vault',
    fs.readdirSync(os.tmpdir()).filter(n => n.startsWith('wintage-vault-')).length, 0);
}

// ══ 5. The vault is transient on success, retained + named on failure ═══════
{
  const vaultsBefore = fs.readdirSync(os.tmpdir()).filter(n => n.startsWith('wintage-vault-')).length;
  const R = mk('vault-clean', 0);
  buildAsar(path.join(R, 'app.asar'), PKG('1.0.0'), 1 * MiB);
  let r = run(['--resources', R, '--palette', 'goldendefault']);
  check('vault: apply exits 0', r.code, 0);
  r = run(['--resources', R, '--revert']);
  check('vault: clean revert exits 0', r.code, 0);
  const vaultsAfter = fs.readdirSync(os.tmpdir()).filter(n => n.startsWith('wintage-vault-')).length;
  check('vault: a successful operation leaves NO vault behind', vaultsAfter, vaultsBefore);

  // The failure case: rollback cannot complete, so the vault is the last copy.
  const R2 = mk('vault-kept', 0);
  buildAsar(path.join(R2, 'app.asar'), PKG('1.0.0'), 1 * MiB);
  const preSha = sha(path.join(R2, 'app.asar'));
  r = run(['--resources', R2, '--palette', 'goldendefault'], { WINTAGE_TEST_FAIL_ROLLBACK_ASAR: '1' });
  check('vault-kept: exits NONZERO', r.code !== 0, true);
  check('vault-kept: reports rollback INCOMPLETE', /INCOMPLETE/.test(r.out), true);
  check('vault-kept: does NOT claim exact restoration',
    /rolled back to the exact pre-operation state/.test(r.out), false);
  check('vault-kept: names a recovery location', /Recovery locations preserved:/.test(r.out), true);
  // CORE-001 invariant, unchanged by PERF-001: the original bytes survive on disk.
  // Note there is deliberately NO vault here: a stock -> relocation apply only
  // RENAMES the archive, so nothing was ever copied and the recovery locations
  // are the in-tree `.wintage-*` directories. A vault that appeared for this path
  // would mean the fix had introduced a copy the old code did not make.
  const keptStock = fs.readdirSync(os.tmpdir()).filter(n => n.startsWith('wintage-vault-'));
  check('vault-kept: a rename-only apply creates no vault at all', keptStock.length, 0);
  const inTree = fs.existsSync(R2) ? fs.readdirSync(R2) : [];
  const candidates = [path.join(R2, 'app.asar')]
    .concat(inTree.filter(n => n.startsWith('.wintage-')).map(n => path.join(R2, n, 'app.asar')));
  const surviving = candidates.filter(p => fs.existsSync(p) && fs.statSync(p).isFile() && sha(p) === preSha);
  check('vault-kept: the original archive bytes survive somewhere on disk',
    surviving.length >= 1, true);
}

// ══ 6. When the vault DOES hold bytes, an incomplete rollback keeps it ══════
// updated-relocated is the path that copies: captureAppDir() vaults the old
// themed app dir (including the previously moved archive) before the swap. If the
// rollback cannot complete, that vault is the last copy of those bytes, so it
// must survive the process AND be named in the message. Retaining it always
// would leak; retaining it never would lose data -- both directions are
// controlled.
{
  const R = mk('vault-update', 0);
  buildAsar(path.join(R, 'app.asar'), PKG('1.0.0'), 1 * MiB);
  let r = run(['--resources', R, '--palette', 'goldendefault']);
  check('vault-update: first apply exits 0', r.code, 0);
  const oldMovedSha = sha(path.join(R, 'app', 'app.asar'));
  // An app update lands: a fresh stock archive reappears at root.
  buildAsar(path.join(R, 'app.asar'), PKG('2.0.0'), 1 * MiB);
  r = run(['--resources', R, '--palette', 'goldendefault'], { WINTAGE_TEST_FAIL_ROLLBACK_ASAR: '1' });
  check('vault-update: exits NONZERO', r.code !== 0, true);
  check('vault-update: reports rollback INCOMPLETE', /INCOMPLETE/.test(r.out), true);
  const kept = fs.readdirSync(os.tmpdir())
    .filter(n => n.startsWith('wintage-vault-'))
    .map(n => path.join(os.tmpdir(), n));
  check('vault-update: an incomplete rollback RETAINS its vault', kept.length >= 1, true);
  check('vault-update: and the message names that exact directory',
    kept.some(d => r.out.includes(d)), true);
  const vaulted = kept.flatMap(d => fs.readdirSync(d).map(f => path.join(d, f)))
    .filter(p => fs.statSync(p).isFile() && sha(p) === oldMovedSha);
  check('vault-update: the vault really holds the old archive bytes', vaulted.length >= 1, true);
  for (const d of kept) fs.rmSync(d, { recursive: true, force: true });
}

fs.rmSync(tmp, { recursive: true, force: true });
console.log('\n' + (bad === 0 ? 'perf recovery test PASS' : bad + ' FAILURE(S)'));
process.exit(bad === 0 ? 0 : 1);
