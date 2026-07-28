#!/usr/bin/env node
// Tests the theme-pack generator against the cases that actually break it.
//
// The one that matters most is "a version of the script this tool has never seen":
// the whole reason the packs exist is that Tampermonkey re-downloads the userscript
// on every upgrade, so the generator's real job is to patch a FUTURE file. That is
// exercised here by running it against the last released commit, which predates the
// generated markers entirely.
const fs = require('fs'), os = require('os'), path = require('path'), cp = require('child_process');

const ROOT = path.join(__dirname, '..');
const GEN = path.join(__dirname, 'apply-themes.js');
let bad = 0;

const check = (label, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  console.log((ok ? 'PASS: ' : 'FAIL: ') + label + (ok ? '' : '  got=' + JSON.stringify(got) + ' want=' + JSON.stringify(want)));
  if (!ok) bad++;
};

function run(args, cwd) {
  try {
    return { code: 0, out: cp.execSync('node "' + GEN + '" ' + args, { cwd: cwd || ROOT, encoding: 'utf8', stdio: 'pipe' }) };
  } catch (e) {
    return { code: e.status || 1, out: (e.stdout || '') + (e.stderr || '') };
  }
}

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'wintage-packs-'));

// 1. The repo copy must already be up to date — otherwise someone edited the
//    generated block by hand, which is the failure mode the markers exist to catch.
check('repo script is up to date with themes/', run('--check').code, 0);

// 2. A file with no markers at all (the last released commit) must be upgradable.
const legacy = path.join(tmp, 'legacy.user.js');
let released;
try {
  released = cp.execSync('git show HEAD:wintage.user.js', { cwd: ROOT, encoding: 'utf8', maxBuffer: 1 << 24 });
} catch (e) { released = null; }
if (!released) {
  console.log('SKIP: no git history available for the marker-less upgrade test');
} else {
  fs.writeFileSync(legacy, released);
  check('released file starts without markers', /THEME PACKS/.test(released), false);
  const r1 = run('"' + legacy + '"');
  check('generator patches a marker-less file', r1.code, 0);
  const after1 = fs.readFileSync(legacy, 'utf8');
  check('markers added on first run', /THEME PACKS/.test(after1) && /END THEME PACKS/.test(after1), true);
  check('patched file still parses', (() => {
    try { cp.execSync('node --check "' + legacy + '"', { stdio: 'pipe' }); return true; } catch (e) { return false; }
  })(), true);
  // 3. Idempotence: a second run must change nothing at all.
  run('"' + legacy + '"');
  check('second run is byte-identical', fs.readFileSync(legacy, 'utf8'), after1);
}

// 4. A target that is not a Wintage script must be refused, not mangled.
const junk = path.join(tmp, 'junk.js');
fs.writeFileSync(junk, 'console.log("not a userscript");\n');
const r2 = run('"' + junk + '"');
check('non-Wintage target rejected', r2.code, 1);
check('  ...with a reason naming what it looked for', /const THEMES/.test(r2.out), true);
check('junk file left untouched', fs.readFileSync(junk, 'utf8'), 'console.log("not a userscript");\n');

// 5. A half-marked file (opening marker, no closing one) must refuse to guess.
const half = path.join(tmp, 'half.user.js');
fs.writeFileSync(half, fs.readFileSync(path.join(ROOT, 'wintage.user.js'), 'utf8').replace(/  \/\/ ─── END THEME PACKS.*\n/, ''));
const r3 = run('"' + half + '"');
check('half-marked file rejected', r3.code, 1);
check('  ...without guessing where the block ends', /refusing to guess/.test(r3.out), true);

// 6. Malformed packs must fail loudly, one reason each. Each mutation is applied to
//    a throwaway themes/ dir so the repo's own packs are never touched.
const packSandbox = path.join(tmp, 'sandbox');
fs.mkdirSync(path.join(packSandbox, 'themes'), { recursive: true });
fs.mkdirSync(path.join(packSandbox, 'tools'), { recursive: true });
fs.copyFileSync(GEN, path.join(packSandbox, 'tools', 'apply-themes.js'));
fs.copyFileSync(path.join(ROOT, 'wintage.user.js'), path.join(packSandbox, 'wintage.user.js'));
const goodPack = JSON.parse(fs.readFileSync(path.join(ROOT, 'themes', 'golden.json'), 'utf8'));

const mutations = {
  'missing token': p => { delete p.tokens.selection; return p; },
  'non-hex token': p => { p.tokens.surface = 'rgb(1,2,3)'; return p; },
  'unknown token': p => { p.tokens.bogus = '#123456'; return p; },
  'slug that is not an identifier': p => { p.slug = '2-cool'; return p; },
  'label with an apostrophe': p => { p.label = "Dev's theme"; return p; },
  'invalid JSON': p => 'BROKEN'
};
for (const [label, mutate] of Object.entries(mutations)) {
  const pack = mutate(JSON.parse(JSON.stringify(goodPack)));
  fs.writeFileSync(path.join(packSandbox, 'themes', 'golden.json'),
    typeof pack === 'string' ? pack : JSON.stringify(pack, null, 2));
  let code = 0, out = '';
  try { out = cp.execSync('node tools/apply-themes.js', { cwd: packSandbox, encoding: 'utf8', stdio: 'pipe' }); }
  catch (e) { code = e.status || 1; out = (e.stdout || '') + (e.stderr || ''); }
  const reason = (out.split('\n').find(l => l.startsWith('apply-themes:')) || '').trim();
  check('pack with a ' + label + ' is rejected' + (code ? ' -> ' + reason.slice(0, 90) : ''), code, 1);
}

// 7. Menu order comes from the pack, not from the filesystem's sort order.
fs.writeFileSync(path.join(packSandbox, 'themes', 'golden.json'), JSON.stringify(goodPack, null, 2));
fs.writeFileSync(path.join(packSandbox, 'themes', 'aaa.json'), JSON.stringify({
  slug: 'zeta', label: 'Zeta', order: 5, tokens: goodPack.tokens
}, null, 2));
fs.writeFileSync(path.join(packSandbox, 'themes', 'zzz.json'), JSON.stringify({
  slug: 'alpha', label: 'Alpha', order: 2, tokens: goodPack.tokens
}, null, 2));
cp.execSync('node tools/apply-themes.js', { cwd: packSandbox, stdio: 'pipe' });
const emitted = fs.readFileSync(path.join(packSandbox, 'wintage.user.js'), 'utf8');
const order = [...emitted.matchAll(/^    (\w+): \{$/gm)].map(m => m[1]);
check('emitted in pack order, not filename order', order, ['golden', 'alpha', 'zeta']);

fs.rmSync(tmp, { recursive: true, force: true });
console.log(bad ? '\n' + bad + ' failure(s)' : '\ntheme-pack test PASS');
process.exit(bad ? 1 : 0);
