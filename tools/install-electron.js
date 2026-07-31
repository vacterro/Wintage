#!/usr/bin/env node
// Installs (or removes) the Wintage stylesheet in an Electron application.
//
// The obvious approach does not work, and it fails silently, so it is worth writing
// down: dropping a `resources/app/` folder next to `app.asar` does NOTHING, because
// Electron searches `resources/app.asar` FIRST and only falls back to `resources/app`
// when the archive is absent. Tried it on Freebuff вЂ” the app started perfectly and
// the theme simply never ran, with no error anywhere.
//
// So the archive is MOVED instead: `resources/app.asar` becomes
// `resources/app/app.asar`, its `app.asar.unpacked` sibling moves with it (that
// pairing is by filename вЂ” separating them breaks every native module), and the
// shim takes the now-empty `resources/app` slot. The application's own bytes are
// never rewritten; only their location changes, and -Revert moves them back.
//
// After an app update the archive reappears at `resources/app.asar` and wins the
// search again, so the app runs unthemed rather than broken вЂ” a good failure mode,
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
const inPlace = has('in-place');

// в”Ђв”Ђв”Ђ Reading the original package.json out of the asar в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
// This matters more than it looks. Electron derives the app NAME from the entry
// package.json, and the name decides where userData lives вЂ” so a shim that
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
    // 8 + pickleSize вЂ” which is not the same number, because the pickle is padded
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
  if (inPlace) {
    const asarBak = asar + '.bak';
    if (!fs.existsSync(asarBak)) { console.log('install-electron: no backup found at ' + asarBak); process.exit(0); }
    if (dryRun) { console.log('install-electron: would restore ' + asarBak + ' -> ' + asar); process.exit(0); }
    fs.copyFileSync(asarBak, asar);
    fs.unlinkSync(asarBak);
    try { fs.unlinkSync(path.join(resources, 'wintage-shim.cjs')); } catch (e) {}
    try { fs.unlinkSync(path.join(resources, 'wintage.css')); } catch (e) {}
    try { fs.unlinkSync(path.join(resources, 'wintage-status.txt')); } catch (e) {}
    console.log('install-electron: restored original ' + path.basename(asar) + ' from backup');
    process.exit(0);
  } else {
    if (!fs.existsSync(appDir)) { console.log('install-electron: nothing installed at ' + appDir); process.exit(0); }
    const pkgPath = path.join(appDir, 'package.json');
    const ours = fs.existsSync(pkgPath) && (JSON.parse(fs.readFileSync(pkgPath, 'utf8').replace(/^\uFEFF/, '')).wintage === MARKER);
    if (!ours) die(appDir + ' exists but was not created by Wintage - refusing to touch it. Inspect it yourself.');
    if (dryRun) { console.log('install-electron: would restore ' + movedAsar + ' -> ' + asar + ' and remove ' + appDir); process.exit(0); }
    if (fs.existsSync(movedAsar)) {
      if (fs.existsSync(asar)) die('both ' + asar + ' and ' + movedAsar + ' exist - the app was probably updated. Delete ' + appDir + ' by hand.');
      fs.renameSync(movedAsar, asar);
      if (fs.existsSync(movedUnpacked)) fs.renameSync(movedUnpacked, unpacked);
    }
    fs.rmSync(appDir, { recursive: true, force: true });
    console.log('install-electron: restored ' + path.basename(asar) + ' and removed ' + appDir);
    process.exit(0);
  }
}

const palette = arg('palette', 'golden');
const built = path.join(ROOT, 'desktop', 'out', 'electron', palette);
if (!fs.existsSync(built)) die('no build for palette "' + palette + '" - run `node tools/build-desktop.js`');

// Already themed? Then the archive has ALREADY moved, and demanding app.asar at its
// original location fails the most ordinary request there is: "same app, different
// palette". Swap the payload in place instead -- no archive move, so it also works
// while the application is running, which the first install cannot do.
const asarBak = asar + '.bak';
let alreadyOurs = false;
if (inPlace) {
  alreadyOurs = fs.existsSync(asarBak) && fs.existsSync(path.join(resources, 'wintage-shim.cjs'));
} else {
  alreadyOurs = fs.existsSync(path.join(appDir, 'package.json')) &&
    JSON.parse(fs.readFileSync(path.join(appDir, 'package.json'), 'utf8').replace(/^\uFEFF/, '')).wintage === MARKER &&
    fs.existsSync(movedAsar);
}

if (alreadyOurs) {
  if (inPlace) {
    if (dryRun) { console.log('install-electron: would repaint ' + asar + ' to "' + palette + '"'); process.exit(0); }
    let shimCode = fs.readFileSync(path.join(built, 'shim.cjs'), 'utf8');
    const original = asarPackageJson(asarBak);
    shimCode = shimCode.replace("require(ASAR);", "require(path.join(ASAR, '" + original.main + "'));");
    fs.writeFileSync(path.join(resources, 'wintage-shim.cjs'), shimCode);
    fs.copyFileSync(path.join(built, 'wintage.css'), path.join(resources, 'wintage.css'));
    try { fs.unlinkSync(path.join(resources, 'wintage-status.txt')); } catch (e) { }
    console.log('install-electron: repainted ' + asar + ' in-place to "' + palette + '"');
    console.log('  restart the app to see it');
    process.exit(0);
  }
  const pkgPath = path.join(appDir, 'package.json');
  const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8').replace(/^\uFEFF/, ''));
  const from = pkg.wintagePalette;
  if (dryRun) {
    console.log('install-electron: would repaint ' + appDir + ' from "' + from + '" to "' + palette + '"');
    process.exit(0);
  }
  pkg.wintagePalette = palette;
  fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + '\n');
  fs.copyFileSync(path.join(built, 'shim.cjs'), path.join(appDir, 'shim.cjs'));
  fs.copyFileSync(path.join(built, 'wintage.css'), path.join(appDir, 'wintage.css'));
  try { fs.unlinkSync(path.join(appDir, 'wintage-status.txt')); } catch (e) { }
  console.log('install-electron: repainted ' + (from === palette ? '' : '"' + from + '" -> ') + '"' + palette + '" in ' + appDir);
  console.log('  restart the app to see it');
  process.exit(0);
}

if (!fs.existsSync(asar)) die('no app.asar in ' + resources + ' - this does not look like a packed Electron app');

// в”Ђв”Ђв”Ђ Fuse check, BEFORE anything moves в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
// Two Electron fuses make the shim unrunnable, and they do not fail at install
// time -- they fail at LAUNCH, after the archive has already moved. That is how
// Claude's desktop app broke: installed cleanly, then would not start. Reading the
// fuses out of the binary turns a mystery into a refusal with a reason.
  const { blockers, defuse } = require('./electron-fuses.js');
  const exe = arg('exe') || (() => {
    const dir = path.dirname(resources);
    const skip = /^(uninstall|elevate|squirrel|update)/i;
    const exes = fs.readdirSync(dir).filter(n => n.endsWith('.exe') && !skip.test(n));
    if (exes.length !== 1) return null;
    return path.join(dir, exes[0]);
  })();
  if (exe) {
    const b = blockers(exe);
    if (b.reasons.length) {
      if (dryRun) {
        console.log('install-electron: would defuse ' + exe);
      } else {
        console.log('install-electron: app is fused shut, attempting to defuse ' + exe + '...');
        const d = defuse(exe);
        if (d.error) die('could not defuse the app: ' + d.error);
        if (d.changed) console.log('install-electron: successfully defused the app.');
      }
    }
  }

// An `app/` folder that is not ours is the application's own unpacked source.
// Overwriting it would replace the program with a shim that then tries to load an
// asar that may not exist. Refuse; there is no safe guess here.
if (fs.existsSync(appDir)) {
  const pkgPath = path.join(appDir, 'package.json');
  const existing = fs.existsSync(pkgPath) ? JSON.parse(fs.readFileSync(pkgPath, 'utf8').replace(/^\uFEFF/, '')) : {};
  if (existing.wintage !== MARKER) {
    die(appDir + ' already exists and was not created by Wintage. This app ships an unpacked app/ directory; ' +
      'installing here would shadow it. Refusing.');
  }
}

const original = asarPackageJson(asar);

if (inPlace) {
  // In-place patch: Instead of patching package.json, we patch Claude's main process
  // directly. Node cannot resolve `../` out of an ASAR via package.json main.
  // We overwrite the sentry-dbid string in `.vite/build/index.pre.js` to require our shim.
  if (dryRun) {
    console.log('install-electron: would install palette "' + palette + '" IN-PLACE into ' + asar);
    console.log('  app name/version preserved: ' + original.name + ' ' + original.version);
    console.log('  injecting wintage-shim.cjs into index.pre.js');
    process.exit(0);
  }

  // Backup first
  const asarBak = asar + '.bak';
  try {
    fs.copyFileSync(asar, asarBak);
  } catch (e) {
    if (e.code === 'EBUSY' || e.code === 'EPERM') {
      die('the application is running - close it completely (check the tray) and run this again.\n  Nothing was changed.');
    }
    throw e;
  }
  
  // The shim keeps its handoff: it is the entry point now, so it must require the
  // real archive itself. (The previous version stripped that block because it
  // injected a require INTO index.pre.js instead -- see the note below.)
  fs.copyFileSync(path.join(built, 'shim.cjs'), path.join(resources, 'wintage-shim.cjs'));
  fs.copyFileSync(path.join(built, 'wintage.css'), path.join(resources, 'wintage.css'));

  // Patch `main` inside the archive's package.json, byte-length-identical.
  //
  // The earlier approach overwrote a "sentry-dbid-<uuid>" string literal inside
  // .vite/build/index.pre.js with a require() of the same length. Verified against
  // a COPY of the installed archive: that literal DOES NOT EXIST in this build, so
  // the install would have thrown "Could not find sentry-dbid in index.pre.js".
  // It was also fragile by construction -- it depended on an unrelated vendor
  // string keeping an exact length.
  //
  // Rewriting `main` is the stable equivalent: the value is shorter than the
  // original, so it is padded with spaces (JSON ignores whitespace between
  // tokens) and every offset in the header stays valid. Its reason for being
  // rejected before -- "Node cannot resolve ../ out of an ASAR via package.json
  // main" -- was tested and is not true: path.join(appPath, '../wintage-shim.cjs')
  // normalises the .asar component away entirely, and requiring the result works.
  const fd = fs.openSync(asar, 'r+');
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
      // Growing the string would shift every byte after it and invalidate every
      // offset in the archive. Refuse instead of corrupting it.
      throw new Error('replacement main does not fit (' + Buffer.byteLength(want) + ' > ' + budget +
        ') - this app needs the relocation mode instead');
    }
    const padded = want + ' '.repeat(budget - Buffer.byteLength(want));
    const newBuf = Buffer.from(text.slice(0, m.index) + padded + text.slice(m.index + m[0].length), 'utf8');
    if (newBuf.length !== buf.length) throw new Error('package.json changed size during the patch');
    fs.writeSync(fd, newBuf, 0, newBuf.length, base + Number(entry.offset));

    // The archive carries per-file integrity hashes. They are only ENFORCED while
    // the integrity fuse is on (it is off here, or the caller would have refused),
    // but leaving a stale hash behind is a landmine for anyone who re-enables it.
    if (entry.integrity && entry.integrity.hash) {
      const crypto = require('crypto');
      const newHash = crypto.createHash('sha256').update(newBuf).digest('hex');
      const newHeaderStr = header.toString('utf8').split(entry.integrity.hash).join(newHash);
      const newHeader = Buffer.from(newHeaderStr, 'utf8');
      if (newHeader.length !== header.length) throw new Error('header length changed during the hash update');
      fs.writeSync(fd, newHeader, 0, newHeader.length, 16);
    }
    console.log('install-electron: main "' + m[1] + '" -> "../wintage-shim.cjs" (padded to ' + budget + ' bytes)');
  } finally {
    fs.closeSync(fd);
  }

  console.log('install-electron: installed palette "' + palette + '" IN-PLACE into ' + asar);
  console.log('  ' + original.name + ' ' + original.version + ' - name and version preserved, so userData does not move');
  console.log('  restart the app to see it; `--revert` restores the original ASAR from backup');

} else {
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
  fs.writeFileSync(path.join(appDir, 'package.json'), JSON.stringify(pkg, null, 2) + '\n');
  fs.copyFileSync(path.join(built, 'shim.cjs'), path.join(appDir, 'shim.cjs'));
  fs.copyFileSync(path.join(built, 'wintage.css'), path.join(appDir, 'wintage.css'));
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
}

