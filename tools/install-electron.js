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
// never rewritten; only their location changes, and -Revert moves them back.
//
// After an app update the archive reappears at `resources/app.asar` and wins the
// search again, so the app runs unthemed rather than broken — a good failure mode,
// and the reason the installer is meant to be re-run rather than trusted to persist.
//
// Usage:
//   node tools/install-electron.js --resources <dir> --palette golden
//   node tools/install-electron.js --resources <dir> --revert
//   node tools/install-electron.js --resources <dir> --palette golden --dry-run

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
    // The JSON is read using the length at offset 12, but the FILE DATA starts at
    // 8 + pickleSize — which is not the same number, because the pickle is padded
    // to a 4-byte boundary. Using the JSON length for both worked on one app and
    // produced a truncated package.json on the next; the padding is the difference.
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

if (has('revert')) {
  if (!fs.existsSync(appDir)) { console.log('install-electron: nothing installed at ' + appDir); process.exit(0); }
  const pkgPath = path.join(appDir, 'package.json');
  const ours = fs.existsSync(pkgPath) && (JSON.parse(fs.readFileSync(pkgPath, 'utf8')).wintage === MARKER);
  if (!ours) die(appDir + ' exists but was not created by Wintage - refusing to touch it. Inspect it yourself.');
  if (dryRun) { console.log('install-electron: would restore ' + movedAsar + ' -> ' + asar + ' and remove ' + appDir); process.exit(0); }
  // Archive first, folder second. A crash between the two leaves a working app
  // with a stray folder Electron ignores; the other order leaves no app at all.
  if (fs.existsSync(movedAsar)) {
    if (fs.existsSync(asar)) die('both ' + asar + ' and ' + movedAsar + ' exist - the app was probably updated. Delete ' + appDir + ' by hand.');
    fs.renameSync(movedAsar, asar);
    if (fs.existsSync(movedUnpacked)) fs.renameSync(movedUnpacked, unpacked);
  }
  fs.rmSync(appDir, { recursive: true, force: true });
  console.log('install-electron: restored ' + path.basename(asar) + ' and removed ' + appDir);
  process.exit(0);
}

const palette = arg('palette', 'golden');
const built = path.join(ROOT, 'desktop', 'out', 'electron', palette);
if (!fs.existsSync(built)) die('no build for palette "' + palette + '" - run `node tools/build-desktop.js`');
if (!fs.existsSync(asar)) die('no app.asar in ' + resources + ' - this does not look like a packed Electron app');

// An `app/` folder that is not ours is the application's own unpacked source.
// Overwriting it would replace the program with a shim that then tries to load an
// asar that may not exist. Refuse; there is no safe guess here.
if (fs.existsSync(appDir)) {
  const pkgPath = path.join(appDir, 'package.json');
  const existing = fs.existsSync(pkgPath) ? JSON.parse(fs.readFileSync(pkgPath, 'utf8')) : {};
  if (existing.wintage !== MARKER) {
    die(appDir + ' already exists and was not created by Wintage. This app ships an unpacked app/ directory; ' +
      'installing here would shadow it. Refusing.');
  }
}

const original = asarPackageJson(asar);
const pkg = Object.assign({}, original, {
  main: 'shim.cjs',
  wintage: MARKER,
  wintagePalette: palette,
  wintageOriginalMain: original.main
});

if (dryRun) {
  console.log('install-electron: would install palette "' + palette + '" into ' + appDir);
  console.log('  app name/version preserved: ' + original.name + ' ' + original.version);
  console.log('  original main: ' + original.main + ' -> shim.cjs');
  process.exit(0);
}

fs.mkdirSync(appDir, { recursive: true });
// Payload first, archive move last: until the archive moves, Electron still finds
// app.asar and the app runs exactly as before, so an interruption anywhere in here
// leaves a working application rather than a headless folder.
fs.writeFileSync(path.join(appDir, 'package.json'), JSON.stringify(pkg, null, 2) + '\n');
fs.copyFileSync(path.join(built, 'shim.cjs'), path.join(appDir, 'shim.cjs'));
fs.copyFileSync(path.join(built, 'wintage.css'), path.join(appDir, 'wintage.css'));
// A RUNNING app holds app.asar open, and Windows refuses the rename with EBUSY.
// That is not an error to dump a stack trace for -- it is the single most likely
// thing to happen, and the fix is one sentence. The half-written payload folder is
// removed on the way out so the next attempt starts clean; the app itself was never
// touched, because the move is the last step for exactly this reason.
try {
  fs.renameSync(asar, movedAsar);
} catch (e) {
  fs.rmSync(appDir, { recursive: true, force: true });
  if (e.code === 'EBUSY' || e.code === 'EPERM') {
    die('the application is running - close it completely (check the tray) and run this again.\n' +
      '  Nothing was changed: ' + path.basename(asar) + ' is still where it was.');
  }
  throw e;
}
if (fs.existsSync(unpacked)) fs.renameSync(unpacked, movedUnpacked);

console.log('install-electron: installed palette "' + palette + '" into ' + appDir);
console.log('  ' + original.name + ' ' + original.version + ' - name and version preserved, so userData does not move');
console.log('  restart the app to see it; `--revert` removes the folder and restores it exactly');
