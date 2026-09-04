// CORE-001 (SRC-004:R001): Windows Terminal ownership round-trip.
//
// The tool's whole contract is that Apply -> Revert returns the document to its
// pre-Apply state. Three separate representation losses made that false on the
// SUCCESS path, with exit code 0 on both halves, which is why no gate noticed:
//
//   1. `null` carried both "absent" and "the user configured null", so an
//      explicit null was deleted by Revert.
//   2. Apply rewrites a legacy top-level `profiles` ARRAY into
//      `{ defaults, list }`; the original container form was never recorded.
//   3. Apply drops every scheme named `Wintage` before inserting its own, so a
//      user who owned a scheme by that name lost it permanently.
//
// This suite drives the REAL tool as a child process against temp fixtures and
// compares the post-Revert document to the pre-Apply document, so it fails on
// any future representation change too, not only on these three.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const TOOL = path.join(__dirname, 'install-terminal.js');
const PALETTE = path.join(__dirname, '..', 'themes', 'golden.json');

let bad = 0;
const check = (label, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  console.log((ok ? 'PASS: ' : 'FAIL: ') + label
    + (ok ? '' : '\n        got  = ' + JSON.stringify(got) + '\n        want = ' + JSON.stringify(want)));
  if (!ok) bad++;
};
const truthy = (label, value) => check(label, !!value, true);

function tempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'wintage-terminal-core001-'));
}

function run(settingsPath, extra) {
  return execFileSync(process.execPath,
    [TOOL, '--settings', settingsPath, '--palette', PALETTE].concat(extra || []),
    { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
}

// One full Apply -> Revert cycle against a document written verbatim.
// `mutate` (optional) edits the THEMED document between the halves, standing in
// for a user who changes unrelated settings while the theme is installed.
function roundTrip(before, mutate) {
  const dir = tempDir();
  const settings = path.join(dir, 'settings.json');
  fs.writeFileSync(settings, JSON.stringify(before, null, 4) + '\n', 'utf8');
  run(settings, []);
  const themed = JSON.parse(fs.readFileSync(settings, 'utf8'));
  if (mutate) {
    mutate(themed);
    fs.writeFileSync(settings, JSON.stringify(themed, null, 4) + '\n', 'utf8');
  }
  run(settings, ['--revert']);
  const after = JSON.parse(fs.readFileSync(settings, 'utf8'));
  return { dir, themed, after };
}

// ── 1. explicit null is a VALUE, not absence ────────────────────────────────
{
  const before = {
    profiles: { defaults: { colorScheme: null, font: null, antialiasingMode: null, historySize: null } },
    schemes: [],
    keep: { x: 1 }
  };
  const r = roundTrip(before);
  check('explicit nulls survive the round trip', r.after, before);
}

// ── 2. absent fields stay absent ────────────────────────────────────────────
{
  const before = { profiles: { defaults: {} }, schemes: [], keep: 1 };
  const r = roundTrip(before);
  check('absent owned fields stay absent', r.after, before);
}

// ── 3. historySize 0 is a real setting (the CORE-015 case, still pinned) ─────
{
  const before = { profiles: { defaults: { historySize: 0 } }, schemes: [] };
  const r = roundTrip(before);
  check('explicit historySize 0 is restored as 0', r.after, before);
  check('the themed document raised the scrollback floor', r.themed.profiles.defaults.historySize, 9000);
}

// ── 4. legacy top-level profiles ARRAY ──────────────────────────────────────
{
  const before = { profiles: [{ name: 'p1' }], schemes: [], keep: 1 };
  const r = roundTrip(before);
  check('legacy profiles array container is restored', r.after, before);
  truthy('Apply did normalise it to an object first',
    !Array.isArray(r.themed.profiles) && Array.isArray(r.themed.profiles.list));
}

// ── 5. a pre-existing USER scheme named Wintage is not ours to delete ───────
{
  const before = {
    profiles: { defaults: {} },
    schemes: [{ name: 'Wintage', custom: 'USER-SCHEME' }, { name: 'KeepMe', custom: 'KEEP' }]
  };
  const r = roundTrip(before);
  const names = (r.after.schemes || []).map((s) => s.name).sort();
  check('both schemes survive', names, ['KeepMe', 'Wintage']);
  check('the displaced user scheme is restored verbatim',
    (r.after.schemes || []).find((s) => s.name === 'Wintage'), { name: 'Wintage', custom: 'USER-SCHEME' });
  check('exactly one Wintage scheme remains',
    (r.after.schemes || []).filter((s) => s.name === 'Wintage').length, 1);
  truthy('the themed document carried a real palette scheme',
    r.themed.schemes.filter((s) => s.name === 'Wintage').length === 1
    && typeof r.themed.schemes.find((s) => s.name === 'Wintage').background === 'string');
}

// ── 6. absent `schemes` comes back absent; empty stays empty ────────────────
{
  const before = { profiles: { defaults: {} } };
  const r = roundTrip(before);
  check('absent schemes key stays absent', Object.prototype.hasOwnProperty.call(r.after, 'schemes'), false);
  check('absent profiles container is not invented', r.after, before);
}
{
  const before = { profiles: { defaults: {} }, schemes: [] };
  const r = roundTrip(before);
  check('empty schemes array stays an empty array', r.after.schemes, []);
}

// ── 7. `profiles` absent entirely ───────────────────────────────────────────
{
  const before = { keep: 'only' };
  const r = roundTrip(before);
  check('a document with no profiles key gets it removed again', r.after, before);
}

// ── 8. an existing font object keeps its non-owned keys ─────────────────────
{
  const before = {
    profiles: { defaults: { font: { face: 'Consolas', size: 14, weight: 'bold', cellWidth: '1.2' } } },
    schemes: []
  };
  const r = roundTrip(before);
  check('font object is restored exactly', r.after, before);
  check('Apply preserved the non-owned font key', r.themed.profiles.defaults.font.cellWidth, '1.2');
}

// ── 9. unrelated user edits made WHILE themed survive Revert ────────────────
{
  const before = { profiles: { defaults: {} }, schemes: [] };
  const r = roundTrip(before, (themed) => {
    themed.userAddedTopLevel = 'keep me';
    themed.profiles.defaults.cursorShape = 'filledBox';
    themed.schemes.push({ name: 'UserLater', custom: 'LATER' });
  });
  check('a top-level edit made while themed survives', r.after.userAddedTopLevel, 'keep me');
  check('a non-owned profiles.defaults edit survives', r.after.profiles.defaults.cursorShape, 'filledBox');
  check('a scheme added while themed survives',
    (r.after.schemes || []).map((s) => s.name), ['UserLater']);
  check('no Wintage scheme is left behind',
    (r.after.schemes || []).filter((s) => s.name === 'Wintage').length, 0);
}

// ── 10. the array container is NOT restored when that would lose a user edit ─
{
  const before = { profiles: [{ name: 'p1' }], schemes: [] };
  const r = roundTrip(before, (themed) => { themed.profiles.defaults.cursorShape = 'vintage'; });
  truthy('object form is kept when profiles.defaults carries a user edit',
    !Array.isArray(r.after.profiles));
  check('the user edit is the reason, and it survived', r.after.profiles.defaults.cursorShape, 'vintage');
  check('the profile list is intact', r.after.profiles.list, [{ name: 'p1' }]);
}

// ── 11. schema-1 snapshots are migrated deliberately, not reinterpreted ─────
{
  const dir = tempDir();
  const settings = path.join(dir, 'settings.json');
  // A themed document plus a v1 backup, exactly as an older Wintage left it.
  fs.writeFileSync(settings, JSON.stringify({
    profiles: { defaults: { colorScheme: 'Wintage', antialiasingMode: 'aliased', historySize: 9000 } },
    schemes: [{ name: 'Wintage', background: '#000000' }]
  }, null, 4) + '\n', 'utf8');
  fs.writeFileSync(settings + '.wintage.bak', JSON.stringify({
    __wintage_owned: true,
    colorScheme: 'Campbell',
    font: null,
    antialiasingMode: null,
    historySize: 4321
  }, null, 2) + '\n', 'utf8');
  fs.writeFileSync(settings + '.wintage-palette', 'golden\n', 'utf8');
  run(settings, ['--revert']);
  const after = JSON.parse(fs.readFileSync(settings, 'utf8'));
  check('v1 snapshot restores its recorded scalars', after.profiles.defaults.colorScheme, 'Campbell');
  check('v1 snapshot restores historySize', after.profiles.defaults.historySize, 4321);
  check('v1 null still means absent (its writer meant that)',
    Object.prototype.hasOwnProperty.call(after.profiles.defaults, 'antialiasingMode'), false);
  // v1 never recorded whether `schemes` existed, so deleting the key would be a
  // guess: the empty array is the honest result.
  check('v1 snapshot leaves an emptied schemes array rather than guessing', after.schemes, []);
}

// ── 12. a legacy WHOLE-FILE backup loses nothing (it is the document) ───────
{
  const dir = tempDir();
  const settings = path.join(dir, 'settings.json');
  const original = {
    profiles: [{ name: 'legacy' }],
    schemes: [{ name: 'Wintage', custom: 'USER' }],
    keep: true
  };
  fs.writeFileSync(settings, JSON.stringify({
    profiles: { defaults: { colorScheme: 'Wintage' }, list: [{ name: 'legacy' }] },
    schemes: [{ name: 'Wintage', background: '#000000' }],
    keep: true
  }, null, 4) + '\n', 'utf8');
  fs.writeFileSync(settings + '.wintage.bak', JSON.stringify(original, null, 2) + '\n', 'utf8');
  fs.writeFileSync(settings + '.wintage-palette', 'golden\n', 'utf8');
  run(settings, ['--revert']);
  const after = JSON.parse(fs.readFileSync(settings, 'utf8'));
  check('whole-file backup restores the legacy array container', Array.isArray(after.profiles), true);
  check('whole-file backup restores the displaced user scheme',
    after.schemes, [{ name: 'Wintage', custom: 'USER' }]);
}

// ── 13. the snapshot on disk records the new facts ──────────────────────────
{
  const dir = tempDir();
  const settings = path.join(dir, 'settings.json');
  fs.writeFileSync(settings, JSON.stringify({
    profiles: [{ name: 'p1' }],
    schemes: [{ name: 'Wintage', custom: 'USER' }]
  }, null, 4) + '\n', 'utf8');
  run(settings, []);
  const snap = JSON.parse(fs.readFileSync(settings + '.wintage.bak', 'utf8'));
  check('snapshot declares its schema', snap.schema, 2);
  check('snapshot records presence separately from value', snap.fields.colorScheme, { present: false });
  check('snapshot records the profiles container form', snap.profiles.kind, 'array');
  check('snapshot records the displaced schemes', snap.schemes.displaced, [{ name: 'Wintage', custom: 'USER' }]);
}

console.log(bad ? '\n' + bad + ' failure(s)' : '\nterminal ownership round-trip test PASS');
process.exit(bad ? 1 : 0);
