// T-017 verification.
// A) golden render unchanged vs the shipped HEAD build
// B) the rewritten gate actually fails on the faults it claims to catch
const fs = require('fs'), cp = require('child_process'), path = require('path');
const repo = 'V:/___VAC/__K/__CODE/_TAMPERMONKEY/_WIN95THEME/Wintage';
const tmp = __dirname;

const now = fs.readFileSync(path.join(repo, 'wintage.user.js'), 'utf8');
const old = cp.execSync('git show HEAD:wintage.user.js', { cwd: repo, encoding: 'utf8', maxBuffer: 1 << 24 });

function cssBody(src, name) {
  const decl = 'const ' + name + ' = `';
  const i = src.indexOf(decl); if (i < 0) throw new Error('no ' + name);
  const start = i + decl.length;
  return src.slice(start, start + /\n[ \t]*`;/.exec(src.slice(start)).index);
}
function tokens(src) {
  // both shapes: `const T = {…}` (old) and the tokens block inside THEMES (new)
  const i = src.indexOf('tokens: {') >= 0 ? src.indexOf('tokens: {') : src.indexOf('const T = {');
  const body = src.slice(i, src.indexOf('};', i) >= 0 ? src.indexOf('}', i) : src.length);
  const out = {};
  for (const m of body.matchAll(/(\w+)\s*:\s*'(#[0-9A-Fa-f]{6})'/g)) out[m[1]] = m[2].toUpperCase();
  return out;
}

let bad = 0;
const eq = (label, a, b) => {
  const ok = a === b;
  console.log((ok ? 'PASS: ' : 'FAIL: ') + label + (ok ? '' : '\n  old=' + a + '\n  new=' + b));
  if (!ok) bad++;
};

for (const n of ['GLOBAL_CSS', 'SHADOW_CSS']) {
  eq(n + ' body byte-identical to HEAD', cssBody(old, n), cssBody(now, n));
}
const to = tokens(old), tn = tokens(now);
eq('token names identical', Object.keys(to).sort().join(','), Object.keys(tn).sort().join(','));
for (const k of Object.keys(to)) eq('token ' + k, to[k], tn[k]);

// The two emitters that actually changed: the pre-token paint. Old wrote literals,
// new writes T.background / T.textPrimary — they must resolve to the same colours.
const oldPaint = [...old.matchAll(/setProperty\('(background-color|color)', '(#[0-9A-Fa-f]{6})'/g)].map(m => m[2].toUpperCase());
eq('early paint background', oldPaint[0], tn.background);
eq('early paint text', oldPaint[1], tn.textPrimary);
eq('new file emits no literal in the early paint',
  'none', /setProperty\('(?:background-color|color)', '#/.test(now) ? 'literal still present' : 'none');

// B) guard validation — each fault must make the gate exit non-zero.
const faults = {
  'hardcoded hex in CSS': s => s.replace('html { background-color: ${T.background}', 'html { background-color: #1A0F05'),
  'missing token': s => s.replace(/\n\s*selection: '#362812', compareBack: '#0F0A04'/, "\n        compareBack: '#0F0A04'"),
  'unknown token': s => s.replace("compareBack: '#0F0A04'", "compareBack: '#0F0A04', bogusToken: '#123456'"),
  'malformed hex': s => s.replace("surface: '#2A1C0A'", "surface: 'rgb(42,28,10)'")
};
const sandbox = path.join(tmp, 'gate');
fs.rmSync(sandbox, { recursive: true, force: true });
fs.mkdirSync(path.join(sandbox, 'tools'), { recursive: true });
fs.copyFileSync(path.join(repo, 'tools/check-css.js'), path.join(sandbox, 'tools/check-css.js'));
for (const [label, mut] of Object.entries(faults)) {
  const mutated = mut(now);
  if (mutated === now) { console.log('FAIL: fault "' + label + '" did not apply'); bad++; continue; }
  fs.writeFileSync(path.join(sandbox, 'wintage.user.js'), mutated);
  let code = 0, out = '';
  try { out = cp.execSync('node tools/check-css.js', { cwd: sandbox, encoding: 'utf8', stdio: 'pipe' }); }
  catch (e) { code = e.status; out = (e.stdout || '') + (e.stderr || ''); }
  const first = (out.split('\n').find(l => l.startsWith('FAIL:')) || '').trim();
  console.log((code ? 'PASS: ' : 'FAIL: ') + 'gate rejects ' + label + (code ? ' -> ' + first : ' (exit 0, NOT caught)'));
  if (!code) bad++;
}

console.log(bad ? '\n' + bad + ' failure(s)' : '\nT-017 VERIFY GREEN');
process.exit(bad ? 1 : 0);
