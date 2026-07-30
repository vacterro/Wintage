import re
with open('tools/install-electron.js', 'r', encoding='utf-8') as f:
    code = f.read()

revert_pattern = re.compile(r"if \(has\('revert'\)\) \{.*?process\.exit\(0\);\n\}", re.DOTALL)

revert_new = """if (has('revert')) {
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
}"""

match = revert_pattern.search(code)
if match:
    code = code[:match.start()] + revert_new + code[match.end():]
    with open('tools/install-electron.js', 'w', encoding='utf-8') as f:
        f.write(code)
    print("Patched successfully")
else:
    print("Match not found")
