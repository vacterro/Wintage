#!/usr/bin/env node
// Installs (or removes) the Wintage stylesheet in an Electron application.
//
// The obvious approach does not work, and it fails silently, so it is worth writing
// down: dropping a `resources/app/` folder next to `app.asar` does NOTHING, because
// Electron searches `resources/app.asar` FIRST and only falls back to `resources/app`
// when the archive is absent. Tried it on Freebuff — the app started perfectly and
// the theme simply never ran, with no error anywhere.
//
// So the archive is MOVED instead: `resources/app.asar` becomes
// `resources/app/app.asar`, its `app.asar.unpacked` sibling moves with it (that
// pairing is by filename — separating them breaks every native module), and the
// shim takes the now-empty `resources/app` slot. The application's own bytes are
// never rewritten; only their location changes, and --revert moves them back.
//
// After an app update the archive reappears at `resources/app.asar` and wins the
// search again. That is NOT a broken state — it is UPDATED_RELOCATED and is the
// ordinary reason -Reapply exists (T-189): the fresh stock archive becomes the new
// rollback source and the stale relocation is replaced, so Revert restores the NEW
// app version, never the old moved archive.
//
// Every operation classifies the filesystem state first (T-189) and every MUTATING
// operation is transactional (T-190): all inputs are pre-read and all changes
// calculated BEFORE the first mutation, the fuse flip belongs to the same
// transaction, and any failure restores the exact pre-operation state. ANY command
// containing --dry-run performs ZERO mutations.
//
// Usage:
//   node tools/install-electron.js --resources <dir> --palette golden
//   node tools/install-electron.js --resources <dir> --revert
//   node tools/install-electron.js --resources <dir> --palette golden --dry-run
//   node tools/install-electron.js --resources <dir> --status-json
//   node tools/install-electron.js --resources <dir> --version

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const MARKER = 'wintage-shim';

function arg(name, fallback) {
  const i = process.argv.indexOf('--' + name);
  return i >= 0 ? process.argv[i + 1] : fallback;
}
const has = name => process.argv.includes('--' + name);
function die(msg) { console.error('install-electron: ' + msg); process.exit(1); }

const resources = arg('resources');
if (!resources) die('--resources <dir> is required');
if (!fs.existsSync(resources)) die('resources directory not found: ' + resources);

const asar = path.join(resources, 'app.asar');
const appDir = path.join(resources, 'app');
const dryRun = has('dry-run');
const inPlace = has('in-place');

// ─── Reading the original package.json out of the asar ──────────────────────
// This matters more than it looks. Electron derives the app NAME from the entry
// package.json, and the name decides where userData lives — so a shim that
// declares its own name silently moves the app to an empty profile: no session,
// no settings, no history, and no error message either. The original values are
// copied verbatim and only `main` is changed.
function asarPackageJson(file) {
  const fd = fs.openSync(file, 'r');
  try {
    const head = Buffer.alloc(16);
    fs.readSync(fd, head, 0, 16, 0);
    // asar layout: [u32 = 4][u32 pickleSize][u32 jsonSize][u32 jsonLen][json][files]
    const pickleSize = head.readUInt32LE(4);
    const jsonLen = head.readUInt32LE(12);
    const header = Buffer.alloc(jsonLen);
    fs.readSync(fd, header, 0, jsonLen, 16);
    const index = JSON.parse(header.toString('utf8').replace(/\0+$/, ''));
    const entry = index.files['package.json'];
    if (!entry) throw new Error('no package.json inside the asar');
    const base = 8 + pickleSize;
    const buf = Buffer.alloc(entry.size);
    fs.readSync(fd, buf, 0, entry.size, base + Number(entry.offset));
    return JSON.parse(buf.toString('utf8'));
  } finally { fs.closeSync(fd); }
}

const movedAsar = path.join(appDir, 'app.asar');
const unpacked = asar + '.unpacked';
const movedUnpacked = movedAsar + '.unpacked';

function resolveExe() {
  return arg('exe') || (() => {
    const dir = path.dirname(resources);
    const skip = /^(uninstall|elevate|squirrel|update)/i;
    const exes = fs.readdirSync(dir).filter(n => n.endsWith('.exe') && !skip.test(n));
    if (exes.length !== 1) return null;
    return path.join(dir, exes[0]);
  })();
}

// ─── Fuse handling (T-190) ──────────────────────────────────────────────────
// The fuse flip is part of the install transaction: it happens ONLY after
// classify + preflight + calculation, and a later failure restores the EXE.
const { blockers, defuse } = require('./electron-fuses.js');

function ensureDefused(exe) {
  if (!exe) return;
  const b = blockers(exe);
  if (!b.reasons.length) return;
  console.log('install-electron: app is fused shut, attempting to defuse ' + exe + '...');
  const d = defuse(exe);
  if (d.error) die('could not defuse the app: ' + d.error);
  if (d.changed) console.log('install-electron: successfully defused the app.');
}

function restoreFuseIfDefused(exe) {
  if (!exe) return;
  const bak = exe + '.wintage-fuse.bak';
  if (!fs.existsSync(bak)) return;
  try { fs.copyFileSync(bak, exe); fs.unlinkSync(bak); } catch (e) { }
}

const hasRoot = () => fs.existsSync(asar);
const hasAppDir = () => fs.existsSync(appDir);
const pkgPath = () => path.join(appDir, 'package.json');

// Is the app/ folder OURS (created by Wintage relocation)?
function appDirIsOurs() {
  if (!hasAppDir()) return false;
  try {
    return JSON.parse(fs.readFileSync(pkgPath(), 'utf8').replace(/^\uFEFF/, '')).wintage === MARKER;
  } catch (e) { return false; }
}

// Is the CURRENT root app.asar already Wintage-patched (in-place mode)?
// Tri-state: true = patched, false = stock, null = unreadable (ambiguous).
function asarIsPatched() {
  if (!hasRoot()) return null;
  try {
    const pkg = asarPackageJson(asar);
    if (pkg && pkg.wintage === MARKER) return true;
    if (pkg && typeof pkg.main === 'string' && pkg.main.indexOf('wintage-shim') >= 0) return true;
    return false;
  } catch (e) { return null; }
}

// ─── State classification (T-189) ───────────────────────────────────────────
function classifyState() {
  const bak = asar + '.bak';
  const hasBak = fs.existsSync(bak);
  const hasShim = fs.existsSync(path.join(resources, 'wintage-shim.cjs'));
  if (inPlace) {
    const patched = asarIsPatched();
    if (patched === null) return { state: 'ambiguous', detail: 'current app.asar cannot be read' };
    if (patched && hasBak && hasShim) return { state: 'themed-inplace', detail: 'patched asar + fresh backup + shim' };
    if (!patched && hasRoot() && (hasBak || hasShim)) return { state: 'updated-inplace', detail: 'stock asar with stale Wintage sidecars' };
    if (!patched && hasRoot() && !hasBak && !hasShim) return { state: 'stock', detail: 'untouched app' };
    if (patched && !(hasBak && hasShim)) return { state: 'ambiguous', detail: 'patched asar but missing backup/shim' };
    return { state: 'ambiguous', detail: 'unexpected in-place layout' };
  }
  const ours = appDirIsOurs();
  const moved = fs.existsSync(movedAsar);
  if (hasRoot() && !hasAppDir()) return { state: 'stock', detail: 'untouched app' };
  if (!hasRoot() && ours && moved) return { state: 'themed-relocated', detail: 'archive moved into Wintage app/' };
  if (hasRoot() && ours && moved) return { state: 'updated-relocated', detail: 'new stock archive + stale Wintage relocation' };
  if (hasRoot() && !ours && hasAppDir()) return { state: 'ambiguous', detail: 'app/ exists but was not created by Wintage' };
  if (!hasRoot() && hasAppDir() && !ours) return { state: 'ambiguous', detail: 'app/ exists without the archive and is not ours' };
  if (ours && !moved) return { state: 'ambiguous', detail: 'Wintage app/ but the moved archive is missing' };
  if (!hasRoot() && !hasAppDir()) return { state: 'stock', detail: 'no archive and no app dir (absent app)' };
  return { state: 'ambiguous', detail: 'unexpected relocation layout' };
}

// Current version for status/health: the newest stock archive wins (root asar),
// else the moved archive in a themed-relocated app.
function currentVersion() {
  if (hasRoot()) {
    try { return asarPackageJson(asar).version || null; } catch (e) { return null; }
  }
  if (fs.existsSync(movedAsar)) {
    try { return asarPackageJson(movedAsar).version || null; } catch (e) { return null; }
  }
  return null;
}

function currentPalette() {
  try {
    if (inPlace) {
      const pf = path.join(resources, 'wintage-palette.txt');
      return fs.existsSync(pf) ? fs.readFileSync(pf, 'utf8').trim() : null;
    }
    if (appDirIsOurs()) {
      return JSON.parse(fs.readFileSync(pkgPath(), 'utf8').replace(/^\uFEFF/, '')).wintagePalette || null;
    }
    return null;
  } catch (e) { return null; }
}

function health() {
  const c = classifyState();
  const healthyStates = inPlace ? ['themed-inplace'] : ['themed-relocated'];
  const st = c.state;
  return {
    mode: inPlace ? 'in-place' : 'relocation',
    state: st,
    version: currentVersion(),
    palette: currentPalette(),
    healthy: healthyStates.indexOf(st) >= 0,
    detail: c.detail
  };
}

if (has('status-json')) {
  const h = health();
  h.resources = resources;
  console.log(JSON.stringify(h));
  process.exit(0);
}

if (has('version')) {
  const v = currentVersion();
  if (v === null) { console.log('n/a'); process.exit(0); }
  console.log(v);
  process.exit(0);
}

// ─── Revert ─────────────────────────────────────────────────────────────────
// State-aware: restores the CURRENT app version, never an old moved archive or a
// stale backup. --revert --dry-run performs ZERO mutations (T-190): the fuse
// restore is only ever called on the real mutating path.
if (has('revert')) {
  const c = classifyState();
  if (inPlace) {
    const bak = asar + '.bak';
    if (c.state === 'themed-inplace') {
      if (dryRun) { console.log('install-electron: would restore ' + bak + ' -> ' + asar + ' and remove Wintage sidecars'); process.exit(0); }
      restoreFuseBackupForRevert(resolveExe());
      fs.copyFileSync(bak, asar);
      fs.unlinkSync(bak);
      for (const f of ['wintage-shim.cjs', 'wintage.css', 'wintage-status.txt', 'wintage-palette.txt']) {
        try { fs.unlinkSync(path.join(resources, f)); } catch (e) { }
      }
      console.log('install-electron: restored original ' + path.basename(asar) + ' from backup');
      process.exit(0);
    }
    if (c.state === 'updated-inplace' || c.state === 'stock') {
      // Nothing Wintage owns is live in the current asar: the backup is stale by
      // definition, so the ONLY safe reversion is dropping the sidecars and
      // leaving the current stock asar alone. (Covers both the stock-no-sidecars
      // case, which is trivially a no-op, and the stale-sidecar case.)
      if (dryRun) { console.log('install-electron: would remove stale Wintage sidecars (current asar is stock, nothing to restore)'); process.exit(0); }
      restoreFuseBackupForRevert(resolveExe());
      for (const f of ['wintage-shim.cjs', 'wintage.css', 'wintage-status.txt', 'wintage-palette.txt']) {
        try { fs.unlinkSync(path.join(resources, f)); } catch (e) { }
      }
      if (fs.existsSync(bak)) { try { fs.unlinkSync(bak); } catch (e) { } }
      console.log('install-electron: current app.asar is stock — removed stale Wintage sidecars, nothing restored');
      process.exit(0);
    }
    die('revert refused: ' + c.detail);
  } else {
    if (c.state === 'themed-relocated') {
      if (dryRun) { console.log('install-electron: would restore ' + movedAsar + ' -> ' + asar + ' and remove ' + appDir); process.exit(0); }
      restoreFuseBackupForRevert(resolveExe());
      if (fs.existsSync(movedAsar)) {
        if (fs.existsSync(asar)) die('both ' + asar + ' and ' + movedAsar + ' exist and the archive is ours — delete ' + appDir + ' by hand');
        fs.renameSync(movedAsar, asar);
        if (fs.existsSync(movedUnpacked)) fs.renameSync(movedUnpacked, unpacked);
      }
      fs.rmSync(appDir, { recursive: true, force: true });
      console.log('install-electron: restored ' + path.basename(asar) + ' and removed ' + appDir);
      process.exit(0);
    }
    if (c.state === 'updated-relocated' || c.state === 'stock') {
      // A fresh stock archive is live at root; our relocation is a stale shim.
      // Removing it leaves the current version stock — never restore the old move.
      if (!appDirIsOurs() && c.state === 'updated-relocated') die('app/ is not ours — refusing to remove it');
      if (dryRun) { console.log('install-electron: would remove stale Wintage relocation (fresh stock ' + path.basename(asar) + ' stays live)'); process.exit(0); }
      restoreFuseBackupForRevert(resolveExe());
      fs.rmSync(appDir, { recursive: true, force: true });
      console.log('install-electron: removed stale Wintage relocation; fresh stock ' + path.basename(asar) + ' is now live');
      process.exit(0);
    }
    die('revert refused: ' + c.detail);
  }
}

// The fuse backup is restored only on a REAL revert (never a dry-run).
function restoreFuseBackupForRevert(exe) {
  if (!exe) return;
  const bak = exe + '.wintage-fuse.bak';
  if (!fs.existsSync(bak)) return;
  fs.copyFileSync(bak, exe);
  fs.unlinkSync(bak);
  console.log('install-electron: restored original fuse bytes in ' + exe + ' from backup');
}

const palette = arg('palette', 'golden');
const built = path.join(ROOT, 'desktop', 'out', 'electron', palette);
if (!fs.existsSync(built)) die('no build for palette "' + palette + '" - run `node tools/build-desktop.js`');

const c = classifyState();
if (c.state === 'ambiguous') die('refusing to touch an ambiguous state: ' + c.detail);

// ─── In-place patch calculation (pure; no mutation) ─────────────────────────
function calculateInPlacePatch(asarPath) {
  const fd = fs.openSync(asarPath, 'r');
  try {
    const head = Buffer.alloc(16);
    fs.readSync(fd, head, 0, 16, 0);
    const pickleSize = head.readUInt32LE(4);
    const jsonLen = head.readUInt32LE(12);
    const header = Buffer.alloc(jsonLen);
    fs.readSync(fd, header, 0, jsonLen, 16);
    const index = JSON.parse(header.toString('utf8').replace(/^\uFEFF| +$/g, ''));
    const entry = index.files['package.json'];
    if (!entry) throw new Error('no package.json inside the archive');
    const base = 8 + pickleSize;
    const buf = Buffer.alloc(entry.size);
    fs.readSync(fd, buf, 0, entry.size, base + Number(entry.offset));
    const text = buf.toString('utf8');
    const m = /"main"\s*:\s*"([^"]*)"/.exec(text);
    if (!m) throw new Error('no "main" field in the archive package.json');
    const want = '"main":"../wintage-shim.cjs"';
    const budget = Buffer.byteLength(m[0]);
    if (Buffer.byteLength(want) > budget) {
      throw new Error('replacement main does not fit (' + Buffer.byteLength(want) + ' > ' + budget +
        ') - this app needs the relocation mode instead');
    }
    const padded = want + ' '.repeat(budget - Buffer.byteLength(want));
    const newBuf = Buffer.from(text.slice(0, m.index) + padded + text.slice(m.index + m[0].length), 'utf8');
    if (newBuf.length !== buf.length) throw new Error('package.json changed size during the patch');
    let newHeader = null;
    if (entry.integrity && entry.integrity.hash) {
      const crypto = require('crypto');
      const newHash = crypto.createHash('sha256').update(newBuf).digest('hex');
      const newHeaderStr = header.toString('utf8').split(entry.integrity.hash).join(newHash);
      newHeader = Buffer.from(newHeaderStr, 'utf8');
      if (newHeader.length !== header.length) throw new Error('header length changed during the hash update');
    }
    return { newBuf, newHeader, entry, base, budget, main: m[1] };
  } finally { fs.closeSync(fd); }
}

const SIDECAR_FILES = ['wintage-shim.cjs', 'wintage.css', 'wintage-palette.txt', 'wintage-status.txt'];

function snapshotSidecars() {
  const snap = {};
  for (const f of SIDECAR_FILES) {
    const p = path.join(resources, f);
    snap[f] = fs.existsSync(p) ? { existed: true, buf: fs.readFileSync(p) } : { existed: false };
  }
  return snap;
}

function restoreSidecars(snap) {
  for (const f of SIDECAR_FILES) {
    const p = path.join(resources, f);
    try {
      if (snap[f].existed) fs.writeFileSync(p, snap[f].buf);
      else if (fs.existsSync(p)) fs.unlinkSync(p);
    } catch (e) { }
  }
}

// ─── Apply: in-place mode (transactional, T-190) ────────────────────────────
function installInPlace() {
  if (fs.existsSync(appDir) && !appDirIsOurs()) {
    die(appDir + ' already exists and was not created by Wintage. This app ships an unpacked app/ directory; ' +
      'installing here would shadow it. Refusing.');
  }
  const original = asarPackageJson(asar);   // current (v-now) stock archive
  // CALCULATE the complete patch BEFORE any mutation.
  const patch = calculateInPlacePatch(asar);
  const shimCode = fs.readFileSync(path.join(built, 'shim.cjs'), 'utf8')
    .replace("require(ASAR);", "require(path.join(ASAR, '" + original.main + "'));");
  if (dryRun) {
    console.log('install-electron: would install palette "' + palette + '" IN-PLACE into ' + asar);
    console.log('  app name/version preserved: ' + original.name + ' ' + original.version);
    console.log('  injecting wintage-shim.cjs into index.pre.js');
    process.exit(0);
  }

  const preAsar = fs.readFileSync(asar);
  const preSidecars = snapshotSidecars();
  const asarBak = asar + '.bak';

  // Establish a pristine backup of the CURRENT archive BEFORE patching. In
  // UPDATED_INPLACE the existing .bak is the OLD version and must not stay the
  // rollback authority — overwriting it with the current stock archive is what
  // makes Revert restore v-now instead of v-old.
  try {
    fs.copyFileSync(asar, asarBak);
  } catch (e) {
    if (e.code === 'EBUSY' || e.code === 'EPERM') {
      die('the application is running - close it completely (check the tray) and run this again.\n  Nothing was changed.');
    }
    throw e;
  }

  // The fuse flip belongs to this transaction (T-190).
  ensureDefused(resolveExe());

  let fd = null;
  try {
    fs.writeFileSync(path.join(resources, 'wintage-shim.cjs'), shimCode);
    fs.copyFileSync(path.join(built, 'wintage.css'), path.join(resources, 'wintage.css'));
    fs.writeFileSync(path.join(resources, 'wintage-palette.txt'), palette + '\n');
    if (process.env.WINTAGE_TEST_FAIL_AFTER_SIDECARS) throw new Error('simulated post-sidecar failure (WINTAGE_TEST_FAIL_AFTER_SIDECARS)');

    fd = fs.openSync(asar, 'r+');
    fs.writeSync(fd, patch.newBuf, 0, patch.newBuf.length, patch.base + Number(patch.entry.offset));
    if (process.env.WINTAGE_TEST_FAIL_AFTER_ASAR_WRITE) throw new Error('simulated post-asar-write failure (WINTAGE_TEST_FAIL_AFTER_ASAR_WRITE)');
    if (patch.newHeader) {
      if (process.env.WINTAGE_TEST_FAIL_BEFORE_INTEGRITY) throw new Error('simulated pre-integrity failure (WINTAGE_TEST_FAIL_BEFORE_INTEGRITY)');
      fs.writeSync(fd, patch.newHeader, 0, patch.newHeader.length, 16);
    }
    if (asarIsPatched() !== true) throw new Error('verification failed: archive not patched after write');
  } catch (e) {
    if (fd) { try { fs.closeSync(fd); } catch (e2) { } }
    // Restore the EXACT pre-operation state: asar byte-exact, sidecars as-were.
    try { fs.writeFileSync(asar, preAsar); } catch (e2) { }
    restoreSidecars(preSidecars);
    restoreFuseIfDefused(resolveExe());
    if (e.code === 'EBUSY' || e.code === 'EPERM') {
      die('the application is running - close it completely (check the tray) and run this again.\n  Nothing was changed.');
    }
    die('in-place apply failed (' + e.message + ') - restored the exact pre-operation state.');
  }
  if (fd) { try { fs.closeSync(fd); } catch (e2) { } }
  try { fs.unlinkSync(path.join(resources, 'wintage-status.txt')); } catch (e) { }

  console.log('install-electron: installed palette "' + palette + '" IN-PLACE into ' + asar);
  console.log('  ' + original.name + ' ' + original.version + ' - name and version preserved, so userData does not move');
  console.log('  restart the app to see it; `--revert` restores the original ASAR from backup');
  process.exit(0);
}

// ─── Apply: relocation mode (fully transactional, T-190) ────────────────────
function installRelocation() {
  const isUpdate = (c.state === 'updated-relocated');
  let original;
  try { original = asarPackageJson(asar); }
  catch (e) { die('cannot read the current app.asar (' + e.message + ') — refusing to install against an unreadable archive'); }

  if (fs.existsSync(appDir) && !appDirIsOurs() && c.state === 'stock') {
    die(appDir + ' already exists and was not created by Wintage. This app ships an unpacked app/ directory; ' +
      'installing here would shadow it. Refusing.');
  }

  // PRE-READ all inputs before any mutation.
  const pkg = Object.assign({}, original, {
    main: 'shim.cjs',
    wintage: MARKER,
    wintagePalette: palette,
    wintageOriginalMain: original.main
  });
  const shimContent = fs.readFileSync(path.join(built, 'shim.cjs'), 'utf8');
  const cssContent = fs.readFileSync(path.join(built, 'wintage.css'), 'utf8');

  if (dryRun) {
    console.log('install-electron: would install palette "' + palette + '" into ' + appDir + (isUpdate ? ' (replacing the stale relocation; current version ' + (original.version || '?') + ' becomes the rollback source)' : ''));
    console.log('  app name/version preserved: ' + original.name + ' ' + original.version);
    console.log('  original main: ' + original.main + ' -> shim.cjs');
    process.exit(0);
  }

  // The fuse flip belongs to this transaction (T-190).
  ensureDefused(resolveExe());

  // Stage the new app dir in a temp sibling; nothing live is touched until the
  // swap below, and the OLD relocation is preserved until commit.
  const staging = path.join(resources, '.wintage-stage-' + process.pid);
  const oldReloc = path.join(resources, '.wintage-old-' + process.pid);
  fs.rmSync(staging, { recursive: true, force: true });
  fs.rmSync(oldReloc, { recursive: true, force: true });
  fs.mkdirSync(staging, { recursive: true });
  try {
    fs.writeFileSync(path.join(staging, 'package.json'), JSON.stringify(pkg, null, 2) + '\n');
    fs.writeFileSync(path.join(staging, 'shim.cjs'), shimContent);
    fs.writeFileSync(path.join(staging, 'wintage.css'), cssContent);
  } catch (e) {
    fs.rmSync(staging, { recursive: true, force: true });
    restoreFuseIfDefused(resolveExe());
    die('relocation staging failed (' + e.message + ') - nothing was changed.');
  }
  if (process.env.WINTAGE_TEST_FAIL_AFTER_STAGE) {
    fs.rmSync(staging, { recursive: true, force: true });
    restoreFuseIfDefused(resolveExe());
    die('simulated staging failure (WINTAGE_TEST_FAIL_AFTER_STAGE) - nothing was changed.');
  }

  // The swap: retire old relocation, move staging in, move archive + unpacked,
  // verify. ANY failure rolls back every mutation in reverse.
  const undo = [];
  try {
    if (isUpdate && fs.existsSync(appDir)) {
      fs.renameSync(appDir, oldReloc);
      undo.push(() => fs.renameSync(oldReloc, appDir));
    }
    if (process.env.WINTAGE_TEST_FAIL_AFTER_OLD_RETIRE) throw new Error('simulated post-retire failure (WINTAGE_TEST_FAIL_AFTER_OLD_RETIRE)');

    fs.renameSync(staging, appDir);
    undo.push(() => fs.renameSync(appDir, staging));
    if (process.env.WINTAGE_TEST_FAIL_AFTER_STAGING_MOVE) throw new Error('simulated post-staging-move failure (WINTAGE_TEST_FAIL_AFTER_STAGING_MOVE)');

    if (fs.existsSync(asar)) {
      fs.renameSync(asar, movedAsar);
      undo.push(() => fs.renameSync(movedAsar, asar));
    }
    if (process.env.WINTAGE_TEST_FAIL_AFTER_ASAR_MOVE) throw new Error('simulated post-asar-move failure (WINTAGE_TEST_FAIL_AFTER_ASAR_MOVE)');

    if (process.env.WINTAGE_TEST_FAIL_UNPACKED_MOVE) throw new Error('simulated unpacked-move failure (WINTAGE_TEST_FAIL_UNPACKED_MOVE)');
    if (fs.existsSync(unpacked)) {
      fs.renameSync(unpacked, movedUnpacked);
      undo.push(() => fs.renameSync(movedUnpacked, unpacked));
    }

    if (process.env.WINTAGE_TEST_FAIL_VERIFY) throw new Error('simulated verification failure (WINTAGE_TEST_FAIL_VERIFY)');
    if (!fs.existsSync(movedAsar)) throw new Error('verification failed: moved archive missing');

    // Commit: obsolete relocation state is dropped only after everything is in place.
    if (fs.existsSync(oldReloc)) fs.rmSync(oldReloc, { recursive: true, force: true });
  } catch (e) {
    while (undo.length) { try { undo.pop()(); } catch (e2) { } }
    fs.rmSync(staging, { recursive: true, force: true });
    fs.rmSync(oldReloc, { recursive: true, force: true });
    restoreFuseIfDefused(resolveExe());
    if (e.code === 'EBUSY' || e.code === 'EPERM') {
      die('the application is running - close it completely (check the tray) and run this again.\n' +
        '  Nothing was changed.');
    }
    die('relocation failed (' + e.message + ') - rolled back to the exact pre-operation state.');
  }

  console.log('install-electron: installed palette "' + palette + '" into ' + appDir + (isUpdate ? ' (replaced stale relocation; current version preserved as rollback source)' : ''));
  console.log('  ' + original.name + ' ' + original.version + ' - name and version preserved, so userData does not move');
  console.log('  restart the app to see it; `--revert` restores the current version exactly');
  process.exit(0);
}

// ─── Repaint (already themed) ───────────────────────────────────────────────
function repaintInPlace() {
  if (dryRun) { console.log('install-electron: would repaint ' + asar + ' to "' + palette + '"'); process.exit(0); }
  let shimCode = fs.readFileSync(path.join(built, 'shim.cjs'), 'utf8');
  const original = asarPackageJson(asar + '.bak');
  shimCode = shimCode.replace("require(ASAR);", "require(path.join(ASAR, '" + original.main + "'));");
  fs.writeFileSync(path.join(resources, 'wintage-shim.cjs'), shimCode);
  fs.copyFileSync(path.join(built, 'wintage.css'), path.join(resources, 'wintage.css'));
  fs.writeFileSync(path.join(resources, 'wintage-palette.txt'), palette + '\n');
  try { fs.unlinkSync(path.join(resources, 'wintage-status.txt')); } catch (e) { }
  console.log('install-electron: repainted ' + asar + ' in-place to "' + palette + '"');
  console.log('  restart the app to see it');
  process.exit(0);
}

function repaintRelocation() {
  const pkg = JSON.parse(fs.readFileSync(pkgPath(), 'utf8').replace(/^\uFEFF/, ''));
  const from = pkg.wintagePalette;
  if (dryRun) {
    console.log('install-electron: would repaint ' + appDir + ' from "' + from + '" to "' + palette + '"');
    process.exit(0);
  }
  pkg.wintagePalette = palette;
  fs.writeFileSync(pkgPath(), JSON.stringify(pkg, null, 2) + '\n');
  fs.copyFileSync(path.join(built, 'shim.cjs'), path.join(appDir, 'shim.cjs'));
  fs.copyFileSync(path.join(built, 'wintage.css'), path.join(appDir, 'wintage.css'));
  try { fs.unlinkSync(path.join(appDir, 'wintage-status.txt')); } catch (e) { }
  console.log('install-electron: repainted ' + (from === palette ? '' : '"' + from + '" -> ') + '"' + palette + '" in ' + appDir);
  console.log('  restart the app to see it');
  process.exit(0);
}

if (inPlace) {
  if (c.state === 'themed-inplace') repaintInPlace();
  if (c.state === 'updated-inplace') installInPlace();   // current stock becomes the new pristine backup
  if (c.state === 'stock') installInPlace();
  die('apply refused: ' + c.detail);
} else {
  if (c.state === 'themed-relocated') repaintRelocation();
  if (c.state === 'updated-relocated') installRelocation();
  if (c.state === 'stock') installRelocation();
  die('apply refused: ' + c.detail);
}
