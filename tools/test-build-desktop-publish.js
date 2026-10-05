#!/usr/bin/env node
// T-396 (audit/10.md SRC-063 W2-002): a generation is published as a whole
// directory or not at all.
//
// build-desktop.js used to be atomic per FILE. Every emit() renamed one file
// into the live desktop/out tree, and the lock was released by an unconditional
// `finally`. So a throw in the last target -- cinema4d validates a pack's colour
// file before writing it, which is exactly the kind of failure that arrives
// after eight targets are already on disk -- left electron/browser/windows at
// generation N+1 and cinema4d at N. The mixed tree was permanent: nothing but
// another full build repaired it, and the unconditional `finally` had already
// handed the lock to a batch that read exactly those halves and cached them.
//
// The repair renders into OUT.staging and swaps directories. This gate drives
// the real CLI as a child process against a throwaway tree (WINTAGE_BUILD_OUT,
// WINTAGE_APPDATA) and pins four things: a clean build publishes whole and
// leaves no debris; a late failure leaves the published tree byte-identical and
// releases the lock; --check writes nothing at all; and an interrupted swap is
// recovered. The last case is the red control the ticket asks for -- it rebuilds
// by hand the mixed tree the per-file write leaves behind and requires the
// per-target comparison to call it mixed, so "nothing moved" is a claim the gate
// can actually be wrong about.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const BUILDER = path.join(ROOT, 'tools', 'build-desktop.js');

let bad = 0;
const check = (label, ok, detail) => {
  console.log((ok ? 'PASS: ' : 'FAIL: ') + label + (ok ? '' : '  ' + (detail || '')));
  if (!ok) bad++;
};

function tmpTree(tag) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wintage-t396-' + tag + '-'));
  return { dir, out: path.join(dir, 'out'), appdata: path.join(dir, 'appdata') };
}

function build(tree, extraEnv) {
  const r = spawnSync(process.execPath, [BUILDER], {
    cwd: ROOT,
    encoding: 'utf8',
    env: Object.assign({}, process.env, {
      WINTAGE_BUILD_OUT: tree.out,
      WINTAGE_APPDATA: tree.appdata
    }, extraEnv || {})
  });
  return { code: r.status, stdout: r.stdout || '', stderr: r.stderr || '' };
}

// One digest per target directory, so a mixed generation is visible as a
// per-target disagreement instead of a single opaque tree hash. This is the
// comparison the red control has to be able to fail.
function targetDigests(root) {
  const out = {};
  if (!fs.existsSync(root)) return out;
  for (const name of fs.readdirSync(root).sort()) {
    const h = require('crypto').createHash('sha256');
    const dir = path.join(root, name);
    const walk = (d, rel) => {
      for (const e of fs.readdirSync(d, { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : 1))) {
        const p = path.join(d, e.name);
        if (e.isDirectory()) walk(p, rel ? rel + '/' + e.name : e.name);
        else { h.update(rel + '/' + e.name + '\0'); h.update(fs.readFileSync(p)); }
      }
    };
    walk(dir, name);
    out[name] = h.digest('hex');
  }
  return out;
}

const changedTargets = (before, after) => Object.keys(after)
  .filter(k => before[k] !== after[k])
  .concat(Object.keys(before).filter(k => !(k in after)));

const debris = (tree) => fs.readdirSync(tree.dir).filter(n => n !== 'out' && n !== 'appdata');

// ── 1. a clean build publishes a whole generation ────────────────────────────
const g = tmpTree('green');
const first = build(g);
check('a clean build succeeds', first.code === 0, first.stderr.slice(-400));
check('the published tree is not empty', Object.keys(targetDigests(g.out)).length > 0);
check('vscode package.json is published',
  fs.existsSync(path.join(g.out, 'vscode', 'wintage-themes', 'package.json')));
check('a successful publish leaves no staging, backup or journal debris',
  debris(g).length === 0, 'left: ' + JSON.stringify(debris(g)));

// ── 2. a LATE failure must not move a single target ──────────────────────────
const before = targetDigests(g.out);
const late = build(g, { WINTAGE_TEST_FAIL_TARGET: 'cinema4d' });
check('the forced late failure fails the run', late.code !== 0, 'exit=' + late.code);
check('the run says the tree was left at its previous whole generation',
  /left at its previous whole generation/.test(late.stderr), late.stderr.slice(-400));
const after = targetDigests(g.out);
check('no target was updated to the failed future generation',
  changedTargets(before, after).length === 0,
  'targets that moved: ' + JSON.stringify(changedTargets(before, after)));
check('the failed run left no staging or backup debris', debris(g).length === 0,
  'left: ' + JSON.stringify(debris(g)));
check('the failed run did not leak the publication lock',
  !fs.existsSync(path.join(g.appdata, 'build-generation.lock')));

// ── 3. --check stays read-only ───────────────────────────────────────────────
const c = tmpTree('check');
build(c);
const cBefore = fs.readdirSync(c.dir).sort();
const checkRun = spawnSync(process.execPath, [BUILDER, '--check'], {
  cwd: ROOT, encoding: 'utf8',
  env: Object.assign({}, process.env, { WINTAGE_BUILD_OUT: c.out, WINTAGE_APPDATA: c.appdata })
});
check('--check on a published tree exits 0', checkRun.status === 0,
  (checkRun.stderr || '').slice(-400));
check('--check created nothing at all',
  JSON.stringify(fs.readdirSync(c.dir).sort()) === JSON.stringify(cBefore),
  'left: ' + JSON.stringify(fs.readdirSync(c.dir)));
check('--check left the publication lock untouched',
  !fs.existsSync(path.join(c.appdata, 'build-generation.lock')));

// A stale tree must be REPORTED, not repaired: --check is a gate, not a fixer.
fs.writeFileSync(path.join(g.out, 'vscode', 'wintage-themes', 'package.json'), '{"stale":true}\n');
const staleRun = spawnSync(process.execPath, [BUILDER, '--check'], {
  cwd: ROOT, encoding: 'utf8',
  env: Object.assign({}, process.env, { WINTAGE_BUILD_OUT: g.out, WINTAGE_APPDATA: g.appdata })
});
check('--check reports a stale output and exits 1', staleRun.status === 1,
  'exit=' + staleRun.status);
check('--check repaired nothing',
  fs.readFileSync(path.join(g.out, 'vscode', 'wintage-themes', 'package.json'), 'utf8') === '{"stale":true}\n');

// ── 4. RED CONTROL: the mixed tree the per-file write leaves behind ──────────
// The pre-fix builder is not runnable as a mutant here -- it has neither the
// WINTAGE_BUILD_OUT redirect nor the failure seam -- so the red control
// reconstructs its OUTCOME instead: take the published generation and change
// exactly one early target, which is what "electron written, then cinema4d
// threw" leaves on disk. If the comparison in case 2 could not see that, case 2
// would be vacuously green.
const mixed = tmpTree('mixed');
build(mixed);
const genN = targetDigests(mixed.out);
const victim = path.join(mixed.out, 'electron');
// electron is laid out per palette, so the first entry is a slug directory.
const slug = fs.readdirSync(victim).find(n => fs.statSync(path.join(victim, n)).isDirectory());
const firstFile = fs.readdirSync(path.join(victim, slug))[0];
fs.appendFileSync(path.join(victim, slug, firstFile), '\n// generation N+1 leaked in\n');
const genNPlus1 = targetDigests(mixed.out);
check('RED CONTROL: a hand-built mixed generation is detected as mixed',
  changedTargets(genN, genNPlus1).length > 0,
  'the comparison saw no movement at all, so case 2 proves nothing');
check('RED CONTROL: only the touched target moves, not the whole tree',
  changedTargets(genN, genNPlus1).join(',') === 'electron',
  'moved: ' + JSON.stringify(changedTargets(genN, genNPlus1)));
check('RED CONTROL: a tree that never moved is still reported as whole',
  changedTargets(genNPlus1, targetDigests(mixed.out)).length === 0,
  'an unchanged tree was reported as moving: ' +
    JSON.stringify(changedTargets(genNPlus1, targetDigests(mixed.out))));

// ── 5. an interrupted install is finished, not inherited ─────────────────────
// A crash in the middle of installing the stage leaves a half-installed tree and
// a journal saying so. A tree that is merely partial would pass every case
// above, so the recovery path is pinned directly: stage the generation by hand,
// wipe half of the live tree, journal it, and let the next build converge.
const r = tmpTree('recover');
build(r);
const wholeGen = targetDigests(r.out);
// Stage the same generation, then damage the live tree the way an interrupted
// install would: a whole target gone.
fs.cpSync(r.out, r.out + '.staging', { recursive: true });
fs.rmSync(path.join(r.out, 'cinema4d'), { recursive: true, force: true });
fs.mkdirSync(r.appdata, { recursive: true });
fs.writeFileSync(path.join(r.appdata, 'build-publish.json'), JSON.stringify({
  out: r.out, stage: r.out + '.staging', phase: 'installing', pid: 1
}));
const recovered = build(r);
check('the next build recovers an interrupted install', recovered.code === 0,
  recovered.stderr.slice(-400));
check('recovery converges the live tree back to one whole generation',
  JSON.stringify(targetDigests(r.out)) === JSON.stringify(wholeGen),
  'recovered tree differs from the generation it was interrupted installing');
check('recovery clears the stage and the journal',
  !fs.existsSync(r.out + '.staging') && !fs.existsSync(path.join(r.appdata, 'build-publish.json')));
check('recovery reports what it did',
  /recovered an interrupted publish/.test(recovered.stdout), recovered.stdout.slice(-300));

// ── 6. the transaction is in the source, not just in behaviour ──────────────
const src = fs.readFileSync(BUILDER, 'utf8');
check('the builder no longer renames into the live tree directly',
  !/fs\.renameSync\(tmp, file\)/.test(src));
check('the builder installs a staged generation instead of building into the live tree',
  /function installStagedGeneration\(\)/.test(src) && /function publishGeneration\(\)/.test(src));
check('the builder recovers an interrupted install from a journal',
  /function recoverInterruptedPublish\(\)/.test(src) && /build-publish\.json/.test(src));
check('the builder refuses to install an empty stage',
  /refusing to install/.test(src));
check('--check takes no lock and owns no staging tree',
  /if \(!checkOnly\) seedStage\(\);/.test(src) && /if \(!checkOnly\) publishGeneration\(\);/.test(src));

fs.rmSync(g.dir, { recursive: true, force: true });
fs.rmSync(c.dir, { recursive: true, force: true });
fs.rmSync(mixed.dir, { recursive: true, force: true });
fs.rmSync(r.dir, { recursive: true, force: true });

console.log(bad === 0 ? '\nAll generation-publication checks passed.' : '\n' + bad + ' check(s) FAILED.');
process.exit(bad === 0 ? 0 : 1);
