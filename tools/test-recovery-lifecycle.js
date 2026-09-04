#!/usr/bin/env node
// W2-001 (SRC-004:R006) + W2-002 (SRC-004:R007): recovery-lifecycle contracts
// for the two Node helpers whose documented lifecycle and executable lifecycle
// had drifted apart.
//
// W2-001, install-windows-theme.js: a completed Revert hands back
// `Wintage.original.theme` as the file to ACTIVATE. `--finalize-revert` then
// deleted exactly that file -- leaving Windows with CurrentTheme pointing at
// something Wintage had just removed -- and deleted the retired-epoch marker
// that nothing has ever written, so the `firstApply` retirement branch was
// unreachable and a later Apply could not tell a completed lifecycle from a
// repaint inside a live epoch.
//
// W2-002, install-obs.js: the INI writers match section/key names
// case-insensitively and the readers did not, so OBS's own
// `[appearance] theme=System` was snapshotted as "absent" and Revert DELETED
// the user's selection. Separately, malformed or wrong-shape JSON recovery fell
// through to the legacy-INI branch and came back as a plausible
// `{existed:false,value:null}`, which the fail-closed preflight accepted.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const WIN = path.join(__dirname, 'install-windows-theme.js');
const OBS = path.join(__dirname, 'install-obs.js');

let bad = 0;
const check = (label, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  console.log((ok ? 'PASS: ' : 'FAIL: ') + label
    + (ok ? '' : '\n        got  = ' + JSON.stringify(got) + '\n        want = ' + JSON.stringify(want)));
  if (!ok) bad++;
};

function tempDir(tag) {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'wintage-recovery-' + tag + '-'));
}

function run(tool, args) {
  try {
    const out = execFileSync(process.execPath, [tool].concat(args),
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    return { code: 0, out };
  } catch (e) {
    return { code: e.status === undefined ? 1 : e.status, out: (e.stdout || '') + (e.stderr || '') };
  }
}

// ══ W2-001: Windows theme epoch lifecycle ═══════════════════════════════════

const THEME_BODY = (tag) => [
  '; Wintage test theme ' + tag,
  '[Theme]',
  'DisplayName=' + tag,
  '',
  '[Control Panel\\Colors]',
  'Background=' + tag.length + ' 0 0',
  '',
  '[VisualStyles]',
  'Path=%SystemRoot%\\resources\\themes\\Aero\\Aero.msstyles',
  ''
].join('\r\n');

function winFixture(tag) {
  const dir = tempDir('win-' + tag);
  const themesDir = path.join(dir, 'Themes');
  fs.mkdirSync(themesDir, { recursive: true });
  const overlay = path.join(dir, 'overlay.theme');
  const current = path.join(themesDir, 'UserChoice.theme');
  fs.writeFileSync(overlay, THEME_BODY('OVERLAY'), 'utf8');
  fs.writeFileSync(current, THEME_BODY('USER-ONE'), 'utf8');
  return { dir, themesDir, overlay, current };
}

const winApply = (f, currentTheme) => JSON.parse(run(WIN, [
  '--themes-dir', f.themesDir, '--theme', f.overlay,
  '--current-theme', currentTheme || f.current, '--palette', 'goldendefault'
]).out);
const winRevert = (f) => JSON.parse(run(WIN, ['--themes-dir', f.themesDir, '--revert']).out);
const winFinalize = (f) => JSON.parse(run(WIN, ['--themes-dir', f.themesDir, '--finalize-revert']).out);

{
  const f = winFixture('lifecycle');
  const original = path.join(f.themesDir, 'Wintage.original.theme');
  const retired = path.join(f.themesDir, '.wintage-epoch-retired');

  const a1 = winApply(f);
  check('win: first apply is a first apply', a1.firstApply, true);
  check('win: snapshot exists after apply', fs.existsSync(original), true);
  check('win: snapshot equals the then-current theme',
    fs.readFileSync(original, 'utf8'), THEME_BODY('USER-ONE'));

  // Repaint inside the SAME epoch must not move the baseline.
  fs.writeFileSync(f.current, THEME_BODY('CHANGED-MID-EPOCH'), 'utf8');
  const a2 = winApply(f);
  check('win: repaint inside a live epoch is not a first apply', a2.firstApply, false);
  check('win: repaint preserved the epoch baseline byte-for-byte',
    fs.readFileSync(original, 'utf8'), THEME_BODY('USER-ONE'));

  const r = winRevert(f);
  check('win: revert hands back the snapshot to activate', r.activate, original);
  check('win: the file it hands back exists', fs.existsSync(r.activate), true);
  check('win: revert does not retire on its own', fs.existsSync(retired), false);

  const fin = winFinalize(f);
  check('win: finalize reports success', fin.finalized, true);
  check('win: finalize retires the epoch', fs.existsSync(retired), true);
  // The whole point: the file Revert told Windows to activate must SURVIVE.
  check('win: finalize KEEPS the activated snapshot', fs.existsSync(original), true);
  check('win: finalize keeps its original-path evidence',
    fs.existsSync(path.join(f.themesDir, '.wintage-original-theme-path')), true);
  check('win: finalize drops the live-install markers', [
    fs.existsSync(path.join(f.themesDir, '.wintage-windows-palette')),
    fs.existsSync(path.join(f.themesDir, '.wintage-active-theme-path'))
  ], [false, false]);

  // A user picks a different theme after the completed Revert; the next Apply
  // must re-baseline from THAT, not from the retired epoch's snapshot.
  const userTwo = path.join(f.themesDir, 'UserTwo.theme');
  fs.writeFileSync(userTwo, THEME_BODY('USER-TWO'), 'utf8');
  const a3 = winApply(f, userTwo);
  check('win: apply after a retired epoch is a first apply again', a3.firstApply, true);
  check('win: the new baseline is the new current theme',
    fs.readFileSync(original, 'utf8'), THEME_BODY('USER-TWO'));
  check('win: the retired marker is cleared once the fresh snapshot is committed',
    fs.existsSync(retired), false);
}

{
  // Two full cycles must not accumulate managed themes nor delete the theme the
  // previous cycle is still referencing. The helper does not delete managed
  // themes itself: it RETURNS a `cleanup` list and the PowerShell caller acts on
  // it, so the caller is simulated here rather than asserted around.
  const f = winFixture('cycles');
  const original = path.join(f.themesDir, 'Wintage.original.theme');
  const applyCleanup = (result) => {
    for (const p of result.cleanup || []) {
      check('win: cleanup never names the activation target', p !== result.activate, true);
      if (fs.existsSync(p)) fs.rmSync(p, { force: true });
    }
  };
  for (let i = 1; i <= 2; i++) {
    const cur = path.join(f.themesDir, 'Cycle' + i + '.theme');
    fs.writeFileSync(cur, THEME_BODY('CYCLE-' + i), 'utf8');
    applyCleanup(winApply(f, cur));
    const r = winRevert(f);
    check('win cycle ' + i + ': activation target present', fs.existsSync(r.activate), true);
    applyCleanup(r);
    check('win cycle ' + i + ': activation target survives its own cleanup', fs.existsSync(r.activate), true);
    winFinalize(f);
    check('win cycle ' + i + ': snapshot survives finalize', fs.existsSync(original), true);
  }
  const managed = fs.readdirSync(f.themesDir).filter((n) => /^Wintage-[0-9a-f]+\.theme$/.test(n));
  check('win: no stale managed themes accumulate', managed.length, 0);
}

// ══ W2-002: OBS recovery parsing and INI case semantics ═════════════════════

function obsFixture(tag, iniText) {
  const dir = tempDir('obs-' + tag);
  fs.mkdirSync(path.join(dir, 'themes'), { recursive: true });
  if (iniText !== null) fs.writeFileSync(path.join(dir, 'user.ini'), iniText, 'utf8');
  return dir;
}
const OBS_THEME_SRC = (() => {
  const p = path.join(__dirname, '..', 'desktop', 'out', 'obs', 'goldendefault', 'Wintage.ovt');
  return fs.existsSync(p) ? p : null;
})();
const obsApply = (dir) => run(OBS, ['--config', dir, '--theme', OBS_THEME_SRC, '--palette', 'goldendefault']);
const obsRevert = (dir) => run(OBS, ['--config', dir, '--revert']);

if (!OBS_THEME_SRC) {
  console.log('SKIP: desktop/out/obs/goldendefault/Wintage.ovt is absent - run node tools/build-desktop.js');
  bad++;
} else {
  // Malformed / wrong-shape recovery must be TERMINAL, before any live change.
  const corrupt = [
    ['empty object', '{}'],
    ['truncated json', '{"existed": tru'],
    ['existed not boolean', '{"existed":"yes","value":"X"}'],
    ['existed true without a string value', '{"existed":true,"value":null}'],
    ['existed false with a value', '{"existed":false,"value":"X"}'],
    ['json array', '[]']
  ];
  for (const [label, payload] of corrupt) {
    const live = '[Appearance]\r\nTheme=CurrentTheme\r\nOther=keep\r\n';
    const dir = obsFixture('corrupt', live);
    fs.writeFileSync(path.join(dir, 'user.ini.wintage.bak'), payload, 'utf8');
    // The OTHER half of the required recovery set must be VALID, or the
    // preflight refuses for that reason instead and the assertion below would
    // pass without the payload ever being judged.
    fs.writeFileSync(path.join(dir, 'themes', 'Wintage.ovt.wintage-created'), '', 'utf8');
    fs.writeFileSync(path.join(dir, '.wintage-obs-palette'), 'goldendefault\n', 'utf8');
    const r = obsRevert(dir);
    const after = fs.readFileSync(path.join(dir, 'user.ini'), 'utf8');
    check('obs corrupt recovery (' + label + '): revert exits NONZERO', r.code !== 0, true);
    check('obs corrupt recovery (' + label + '): the refusal names the recovery file',
      /recovery file is corrupt/.test(r.out), true);
    check('obs corrupt recovery (' + label + '): user.ini untouched', after, live);
  }

  // OBS's own lowercase spelling must round-trip.
  for (const [label, live, wantValue] of [
    ['lowercase section and key', '[appearance]\r\ntheme=System\r\nOther=keep\r\n', 'System'],
    ['mixed case', '[AppEarance]\r\nThEmE=Dark\r\nOther=keep\r\n', 'Dark'],
    ['canonical', '[Appearance]\r\nTheme=Yami\r\nOther=keep\r\n', 'Yami']
  ]) {
    const dir = obsFixture('case', live);
    const a = obsApply(dir);
    check('obs ' + label + ': apply exits 0', a.code, 0);
    const snap = JSON.parse(fs.readFileSync(path.join(dir, 'user.ini.wintage.bak'), 'utf8'));
    check('obs ' + label + ': snapshot recorded the real value', snap, { existed: true, value: wantValue });
    const rv = obsRevert(dir);
    check('obs ' + label + ': revert exits 0', rv.code, 0);
    const after = fs.readFileSync(path.join(dir, 'user.ini'), 'utf8');
    check('obs ' + label + ': the theme value is back', /(?:^|\r?\n)\s*[Tt][Hh][Ee][Mm][Ee]\s*=\s*(.+)/.exec(after)[1].trim(), wantValue);
    check('obs ' + label + ': unrelated lines survived', /Other=keep/.test(after), true);
  }

  // A genuinely absent Theme key stays absent, and a legacy whole-file INI
  // recovery still works -- including in lowercase.
  {
    const dir = obsFixture('absent', '[Appearance]\r\nOther=keep\r\n');
    obsApply(dir);
    const snap = JSON.parse(fs.readFileSync(path.join(dir, 'user.ini.wintage.bak'), 'utf8'));
    check('obs absent key: snapshot says absent', snap, { existed: false, value: null });
    obsRevert(dir);
    const after = fs.readFileSync(path.join(dir, 'user.ini'), 'utf8');
    check('obs absent key: no Theme key invented', /Theme\s*=/i.test(after), false);
    check('obs absent key: unrelated lines survived', /Other=keep/.test(after), true);
  }
  {
    const dir = obsFixture('legacy', '[Appearance]\r\nTheme=Wintage\r\nOther=keep\r\n');
    // A pre-T-189 whole-file backup, in OBS's own lowercase spelling.
    fs.writeFileSync(path.join(dir, 'user.ini.wintage.bak'), '[appearance]\r\ntheme=LegacyPick\r\n', 'utf8');
    fs.writeFileSync(path.join(dir, 'themes', 'Wintage.ovt.wintage-created'), '', 'utf8');
    fs.writeFileSync(path.join(dir, '.wintage-obs-palette'), 'goldendefault\n', 'utf8');
    const rv = obsRevert(dir);
    check('obs legacy INI recovery: revert exits 0', rv.code, 0);
    const after = fs.readFileSync(path.join(dir, 'user.ini'), 'utf8');
    check('obs legacy INI recovery: lowercase value restored',
      /(?:^|\r?\n)\s*[Tt][Hh][Ee][Mm][Ee]\s*=\s*(.+)/.exec(after)[1].trim(), 'LegacyPick');
  }
}

console.log(bad ? '\n' + bad + ' failure(s)' : '\nrecovery lifecycle test PASS');
process.exit(bad ? 1 : 0);
