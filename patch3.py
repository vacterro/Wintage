import re

with open('tools/install-electron.js', 'r', encoding='utf-8') as f:
    code = f.read()

install_old = """const original = asarPackageJson(asar);
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
fs.writeFileSync(path.join(appDir, 'package.json'), JSON.stringify(pkg, null, 2) + '\\n');
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
    die('the application is running - close it completely (check the tray) and run this again.\\n' +
      '  Nothing was changed: ' + path.basename(asar) + ' is still where it was.');
  }
  throw e;
}
if (fs.existsSync(unpacked)) fs.renameSync(unpacked, movedUnpacked);

console.log('install-electron: installed palette "' + palette + '" into ' + appDir);
console.log('  ' + original.name + ' ' + original.version + ' - name and version preserved, so userData does not move');
console.log('  restart the app to see it; `--revert` removes the folder and restores it exactly');"""

install_new = """const original = asarPackageJson(asar);

if (inPlace) {
  let newMain = '../wintage-shim.cjs';
  if (newMain.length > original.main.length) {
    die('Cannot install in-place: original main "' + original.main + '" is too short to replace with "' + newMain + '" without resizing the ASAR header.');
  }
  newMain = newMain.padEnd(original.main.length, ' ');
  
  if (dryRun) {
    console.log('install-electron: would install palette "' + palette + '" IN-PLACE into ' + asar);
    console.log('  app name/version preserved: ' + original.name + ' ' + original.version);
    console.log('  original main: ' + original.main + ' -> ' + newMain.trim());
    process.exit(0);
  }

  // Backup first
  const asarBak = asar + '.bak';
  try {
    fs.copyFileSync(asar, asarBak);
  } catch (e) {
    if (e.code === 'EBUSY' || e.code === 'EPERM') {
      die('the application is running - close it completely (check the tray) and run this again.\\n  Nothing was changed.');
    }
    throw e;
  }
  
  // Create wintage-shim.cjs
  let shimCode = fs.readFileSync(path.join(built, 'shim.cjs'), 'utf8');
  shimCode = shimCode.replace("require(ASAR);", "require(path.join(ASAR, '" + original.main + "'));");
  fs.writeFileSync(path.join(resources, 'wintage-shim.cjs'), shimCode);
  fs.copyFileSync(path.join(built, 'wintage.css'), path.join(resources, 'wintage.css'));

  // Patch ASAR in-place
  const fd = fs.openSync(asar, 'r+');
  try {
    const head = Buffer.alloc(16);
    fs.readSync(fd, head, 0, 16, 0);
    const pickleSize = head.readUInt32LE(4);
    const jsonLen = head.readUInt32LE(12);
    const header = Buffer.alloc(jsonLen);
    fs.readSync(fd, header, 0, jsonLen, 16);
    const index = JSON.parse(header.toString('utf8').replace(/^\\uFEFF|\\0+$/g, ''));
    const entry = index.files['package.json'];
    const base = 8 + pickleSize;
    const buf = Buffer.alloc(entry.size);
    fs.readSync(fd, buf, 0, entry.size, base + Number(entry.offset));
    
    const pkgStr = buf.toString('utf8');
    const newPkgStr = pkgStr.replace(/"main"(\\s*:\\s*)"([^"]+)"/, (match, colon, oldMain) => {
      if (oldMain !== original.main) throw new Error("regex found different main than json parser");
      return '"main"' + colon + '"' + newMain + '"';
    });
    
    if (pkgStr.length !== newPkgStr.length) throw new Error("length mismatch during in-place patch");
    
    const newBuf = Buffer.from(newPkgStr, 'utf8');
    fs.writeSync(fd, newBuf, 0, newBuf.length, base + Number(entry.offset));
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
  fs.writeFileSync(path.join(appDir, 'package.json'), JSON.stringify(pkg, null, 2) + '\\n');
  fs.copyFileSync(path.join(built, 'shim.cjs'), path.join(appDir, 'shim.cjs'));
  fs.copyFileSync(path.join(built, 'wintage.css'), path.join(appDir, 'wintage.css'));
  try {
    fs.renameSync(asar, movedAsar);
  } catch (e) {
    fs.rmSync(appDir, { recursive: true, force: true });
    if (e.code === 'EBUSY' || e.code === 'EPERM') {
      die('the application is running - close it completely (check the tray) and run this again.\\n' +
        '  Nothing was changed: ' + path.basename(asar) + ' is still where it was.');
    }
    throw e;
  }
  if (fs.existsSync(unpacked)) fs.renameSync(unpacked, movedUnpacked);

  console.log('install-electron: installed palette "' + palette + '" into ' + appDir);
  console.log('  ' + original.name + ' ' + original.version + ' - name and version preserved, so userData does not move');
  console.log('  restart the app to see it; `--revert` removes the folder and restores it exactly');
}"""

code = code.replace(install_old, install_new)

with open('tools/install-electron.js', 'w', encoding='utf-8') as f:
    f.write(code)
