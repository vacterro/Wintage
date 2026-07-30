import re

with open('tools/install-electron.js', 'r', encoding='utf-8') as f:
    code = f.read()

already_ours_old = """const alreadyOurs = fs.existsSync(path.join(appDir, 'package.json')) &&
  JSON.parse(fs.readFileSync(path.join(appDir, 'package.json'), 'utf8').replace(/^\\uFEFF/, '')).wintage === MARKER &&
  fs.existsSync(movedAsar);

if (alreadyOurs) {"""

already_ours_new = """const asarBak = asar + '.bak';
let alreadyOurs = false;
if (inPlace) {
  alreadyOurs = fs.existsSync(asarBak) && fs.existsSync(path.join(resources, 'wintage-shim.cjs'));
} else {
  alreadyOurs = fs.existsSync(path.join(appDir, 'package.json')) &&
    JSON.parse(fs.readFileSync(path.join(appDir, 'package.json'), 'utf8').replace(/^\\uFEFF/, '')).wintage === MARKER &&
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
  }"""

code = code.replace(already_ours_old, already_ours_new)

with open('tools/install-electron.js', 'w', encoding='utf-8') as f:
    f.write(code)
