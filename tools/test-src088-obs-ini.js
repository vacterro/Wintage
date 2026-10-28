'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const CR = String.fromCharCode(13);
const LF = String.fromCharCode(10);
const CRLF = CR + LF;
const OBS = path.join(__dirname, 'install-obs.js');
const THEME_ID = 'com.wintage.OBS';

let bad = 0;
const check = (label, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  console.log((ok ? 'PASS: ' : 'FAIL: ') + label + (ok ? '' : ' | got ' + JSON.stringify(got) + ' want ' + JSON.stringify(want)));
  if (!ok) bad += 1;
};

function values(text) {
  const out = [];
  let cur = null;
  for (const raw of text.split(LF)) {
    const l = raw.endsWith(CR) ? raw.slice(0, -1) : raw;
    const t = l.trim();
    if (t.startsWith('[') && t.endsWith(']')) { cur = t.slice(1, -1).toLowerCase(); continue; }
    if (cur === 'appearance') {
      const eq = l.indexOf('=');
      if (eq < 0) continue;
      if (l.slice(0, eq).trim().toLowerCase() === 'theme') out.push(l.slice(eq + 1));
    }
  }
  return out;
}

function dir() {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'wintage-ini-'));
  fs.mkdirSync(path.join(d, 'themes'), { recursive: true });
  return d;
}

function run(tool, args) {
  try {
    const out = execFileSync(process.execPath, [tool].concat(args), { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    return { code: 0, out };
  } catch (e) {
    return { code: e.status === undefined ? 1 : e.status, out: (e.stdout || '') + (e.stderr || '') };
  }
}

const THEME_SRC = (() => {
  const p = path.join(__dirname, '..', 'desktop', 'out', 'obs', 'goldendefault', 'Wintage.ovt');
  return fs.existsSync(p) ? p : null;
})();

if (!THEME_SRC) {
  console.log('SKIP: desktop/out/obs/goldendefault/Wintage.ovt is absent - run node tools/build-desktop.js');
  process.exit(1);
}

const apply = (d) => run(OBS, ['--config', d, '--theme', THEME_SRC, '--palette', 'goldendefault']);
const revert = (d) => run(OBS, ['--config', d, '--revert']);

// 1) duplicates with different values
{
  const live = '[Appearance]' + CRLF + '; keep me' + CRLF + 'Theme=First' + CRLF + 'Other=keep' + CRLF + 'Theme=Last' + CRLF + 'Other2=keep2' + CRLF;
  const d = dir();
  fs.writeFileSync(path.join(d, 'user.ini'), live, 'utf8');
  const a = apply(d);
  check('dup diff: apply exits 0', a.code, 0);
  check('dup diff: apply leaves one unambiguous value', values(fs.readFileSync(path.join(d, 'user.ini'), 'utf8')), [THEME_ID, THEME_ID]);
  const snap = JSON.parse(fs.readFileSync(path.join(d, 'user.ini.wintage.bak'), 'utf8'));
  check('dup diff: snapshot value is last', snap.value, 'Last');
  check('dup diff: occurrences preserve order', snap.occurrences.map((o) => o.value), ['First', 'Last']);
  const r = revert(d);
  check('dup diff: revert exits 0', r.code, 0);
  check('dup diff: revert restores both values and structure', values(fs.readFileSync(path.join(d, 'user.ini'), 'utf8')), ['First', 'Last']);
  const after = fs.readFileSync(path.join(d, 'user.ini'), 'utf8');
  check('dup diff: comment survives', after.indexOf('; keep me') >= 0, true);
  check('dup diff: unrelated keys survive', after.indexOf('Other=keep') >= 0 && after.indexOf('Other2=keep2') >= 0, true);
}

// 2) duplicates with identical values
{
  const live = '[Appearance]' + CRLF + 'Theme=Same' + CRLF + 'Theme=Same' + CRLF;
  const d = dir();
  fs.writeFileSync(path.join(d, 'user.ini'), live, 'utf8');
  apply(d);
  check('dup same: apply leaves unambiguous value', values(fs.readFileSync(path.join(d, 'user.ini'), 'utf8')), [THEME_ID, THEME_ID]);
  revert(d);
  check('dup same: revert restores', values(fs.readFileSync(path.join(d, 'user.ini'), 'utf8')), ['Same', 'Same']);
}

// 3) multiple Appearance sections
{
  const live = '[Appearance]' + CRLF + 'Theme=One' + CRLF + '[Other]' + CRLF + 'X=1' + CRLF + '[Appearance]' + CRLF + 'Theme=Two' + CRLF;
  const d = dir();
  fs.writeFileSync(path.join(d, 'user.ini'), live, 'utf8');
  apply(d);
  const snap = JSON.parse(fs.readFileSync(path.join(d, 'user.ini.wintage.bak'), 'utf8'));
  check('multi-section: both occurrences recorded', snap.occurrences.map((o) => o.value), ['One', 'Two']);
  check('multi-section: both occurrences rewritten unambiguously', values(fs.readFileSync(path.join(d, 'user.ini'), 'utf8')), [THEME_ID, THEME_ID]);
  revert(d);
  check('multi-section: revert restores both', values(fs.readFileSync(path.join(d, 'user.ini'), 'utf8')), ['One', 'Two']);
}

// 4) repeated section names with different casing
{
  const live = '[appearance]' + CRLF + 'theme=Lower' + CRLF + '[Appearance]' + CRLF + 'Theme=Upper' + CRLF;
  const d = dir();
  fs.writeFileSync(path.join(d, 'user.ini'), live, 'utf8');
  apply(d);
  const snap = JSON.parse(fs.readFileSync(path.join(d, 'user.ini.wintage.bak'), 'utf8'));
  check('casing: occurrences keep file spelling', snap.occurrences.map((o) => o.section + '/' + o.key + '=' + o.value), ['appearance/theme=Lower', 'Appearance/Theme=Upper']);
  check('casing: apply leaves unambiguous value', values(fs.readFileSync(path.join(d, 'user.ini'), 'utf8')), [THEME_ID, THEME_ID]);
  revert(d);
  check('casing: revert restores both spellings', values(fs.readFileSync(path.join(d, 'user.ini'), 'utf8')), ['Lower', 'Upper']);
}

// 5) negative control: occurrence count changed after Apply -> fail closed
{
  const live = '[Appearance]' + CRLF + 'Theme=First' + CRLF + 'Theme=Last' + CRLF;
  const d = dir();
  fs.writeFileSync(path.join(d, 'user.ini'), live, 'utf8');
  apply(d);
  const iniPath = path.join(d, 'user.ini');
  fs.writeFileSync(iniPath, '[Appearance]' + CRLF + 'Theme=' + THEME_ID + CRLF + 'Theme=UserAdded' + CRLF + 'Theme=' + THEME_ID + CRLF, 'utf8');
  const before = fs.readFileSync(iniPath, 'utf8');
  const r = revert(d);
  check('mismatch: revert exits nonzero', r.code !== 0, true);
  check('mismatch: refusal names the recovery evidence', r.out.indexOf('--revert refused') >= 0, true);
  check('mismatch: user.ini untouched', fs.readFileSync(iniPath, 'utf8'), before);
}

console.log(bad ? bad + ' failure(s)' : 'obs ini duplicate-key test PASS');
process.exit(bad ? 1 : 0);
