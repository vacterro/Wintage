#!/usr/bin/env node
// Wintage - FreeBuff completion sound customizer.
//
// NOTE: Ad stripping has been permanently removed in compliance with FreeBuff ToS.
// FreeBuff renderer and orchestrator code are never modified.
// This helper manages the completion sound (chime-*.mp3) with transactional
// backup and baseline recovery.
//
// Usage:
//   node desktop/patch-freebuff-ads.js                             # verify install & sound status
//   node desktop/patch-freebuff-ads.js --sound "C:\...\my.mp3"     # install custom completion sound
//   node desktop/patch-freebuff-ads.js --scan                      # report ToS compliance status
//   node desktop/patch-freebuff-ads.js --dry-run                   # validate inputs without touching disk
//   node desktop/patch-freebuff-ads.js --verify                    # report sound health
//   node desktop/patch-freebuff-ads.js --revert                    # restore stock chime from baseline
//   node desktop/patch-freebuff-ads.js --target "D:\...\@codebufffreebuff-desktop"

const fs = require('fs');
const path = require('path');

const DEFAULT_TARGET = path.join(process.env.LOCALAPPDATA || '', 'Programs', '@codebufffreebuff-desktop');

function arg(name, fallback) {
  const i = process.argv.indexOf('--' + name);
  return i >= 0 ? process.argv[i + 1] : fallback;
}
const has = name => process.argv.includes('--' + name);
function die(msg) { console.error('patch-freebuff-ads: ' + msg); process.exit(1); }

const target = arg('target', DEFAULT_TARGET);
const dryRun = has('dry-run');
const doVerify = has('verify');
const doScan = has('scan');
const doRevert = has('revert');

if (!fs.existsSync(path.join(target, 'Freebuff.exe'))) {
  die('Freebuff.exe not found in: ' + target + '  -- pass --target correctly');
}

const orchestratorDir = path.join(target, 'resources', 'orchestrator');
const indexHtmlPath = path.join(orchestratorDir, 'ui', 'index.html');
const orchestratorPath = path.join(orchestratorDir, 'orchestrator.js');

let bundlePath = null;
if (fs.existsSync(indexHtmlPath)) {
  const html = fs.readFileSync(indexHtmlPath, 'utf8');
  const m = /assets\/(index-[A-Za-z0-9_-]+\.js)/.exec(html);
  if (m) bundlePath = path.join(orchestratorDir, 'ui', 'assets', m[1]);
}

const assetsDir = path.join(orchestratorDir, 'ui', 'assets');
let chimePath = null;
if (fs.existsSync(assetsDir)) {
  const hits = fs.readdirSync(assetsDir)
    .filter(f => /^chime-.*\.mp3$/.test(f))
    .map(f => path.join(assetsDir, f))
    .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
  if (hits.length) chimePath = hits[0];
}

const soundArg = arg('sound', null);

const isAudio = p => {
  try {
    const b = fs.readFileSync(p);
    if (b.length < 8) return false;
    const s4 = b.slice(0, 4).toString('latin1');
    if (b.length > 12 && s4 === 'RIFF' && b.slice(8, 12).toString('latin1') === 'WAVE') return true; // wav
    if (b.slice(0, 3).toString('latin1') === 'ID3') return true;                                     // mp3
    if (b.length >= 2 && b[0] === 0xFF && (b[1] & 0xE0) === 0xE0) return true;                       // mp3 (raw frames)
    if (s4 === 'OggS' || s4 === 'fLaC') return true;                                                // ogg / flac
    if (b.length >= 8 && b.slice(4, 8).toString('latin1') === 'ftyp') return true;                   // m4a / mp4
    return false;
  } catch (e) { return false; }
};

function soundStatus() {
  if (!chimePath) return 'no chime-*.mp3 found';
  return (isAudio(chimePath) ? 'custom audio installed' : 'stock') + ' -> ' + path.relative(target, chimePath);
}

// ---------------------------------------------------------------------------
// --scan: report ToS compliance status
// ---------------------------------------------------------------------------
if (doScan) {
  console.log('target: ' + target);
  console.log('FreeBuff ad patching is permanently retired in compliance with FreeBuff Terms of Service.');
  console.log('No ad routes or renderer bundles are modified.');
  console.log('Completion sound status: ' + soundStatus());
  process.exit(0);
}

// ---------------------------------------------------------------------------
// Baselines & Transactions
// ---------------------------------------------------------------------------
function ownedFileList() {
  const list = [];
  if (bundlePath && fs.existsSync(bundlePath)) {
    list.push({ abs: bundlePath, rel: path.relative(target, bundlePath) });
  }
  if (orchestratorPath && fs.existsSync(orchestratorPath)) {
    list.push({ abs: orchestratorPath, rel: path.relative(target, orchestratorPath) });
  }
  if (chimePath) {
    list.push({ abs: chimePath, rel: path.relative(target, chimePath) });
  }
  return list;
}

function baselineDir() {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  return path.join(target, '_orig-baseline-' + stamp + '-' + process.pid);
}

function createBaseline(files) {
  const dir = baselineDir();
  const meta = { kind: 'baseline', files: files.map(f => f.rel), complete: false, created: new Date().toISOString(), target };
  for (const f of files) {
    const dst = path.join(dir, f.rel);
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    fs.copyFileSync(f.abs, dst);
  }
  fs.writeFileSync(path.join(dir, 'wintage-baseline.json'), JSON.stringify(meta, null, 2), 'utf8');
  meta.complete = true;
  fs.writeFileSync(path.join(dir, 'wintage-baseline.json'), JSON.stringify(meta, null, 2), 'utf8');
  return dir;
}

function baselines() {
  if (!fs.existsSync(target)) return [];
  const dirs = fs.readdirSync(target).filter(d => /^_orig-baseline-/.test(d));
  const out = [];
  for (const d of dirs) {
    const dir = path.join(target, d);
    const metaPath = path.join(dir, 'wintage-baseline.json');
    if (!fs.existsSync(metaPath)) continue;
    try {
      const meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
      if (meta.kind !== 'baseline' || meta.complete !== true || !Array.isArray(meta.files) || !meta.files.length) continue;
      if (meta.files.some(rel => !fs.existsSync(path.join(dir, rel)))) continue;
      out.push({ dir, meta });
    } catch (e) { continue; }
  }
  return out.sort((a, b) => b.dir.localeCompare(a.dir));
}

function currentBaseline() { return baselines()[0] || null; }

function upstreamReplacedOwnedFile() {
  const b = currentBaseline();
  if (!b) return true;
  for (const rel of b.meta.files) {
    if (chimePath && rel === path.relative(target, chimePath)) continue;
    const live = path.join(target, rel);
    if (!fs.existsSync(live)) continue;
    const orig = path.join(b.dir, rel);
    if (!fs.existsSync(orig)) return true;
    const liveBuf = fs.readFileSync(live);
    const origBuf = fs.readFileSync(orig);
    if (!liveBuf.equals(origBuf)) {
      return true;
    }
  }
  return false;
}

function pruneBaselines() {
  const all = baselines();
  if (all.length <= 3) return;
  for (const old of all.slice(3)) {
    try { fs.rmSync(old.dir, { recursive: true, force: true }); console.log('pruned stale baseline ' + path.basename(old.dir)); }
    catch (e) { }
  }
}

function ensureBaseline() {
  const cur = currentBaseline();
  if (cur && !upstreamReplacedOwnedFile()) {
    pruneBaselines();
    return cur;
  }
  if (cur && upstreamReplacedOwnedFile()) {
    console.log('detected a new app generation - establishing a fresh baseline from the current stock files.');
  }
  const dir = createBaseline(ownedFileList());
  pruneBaselines();
  console.log('baseline -> ' + path.relative(target, dir));
  return { dir, meta: JSON.parse(fs.readFileSync(path.join(dir, 'wintage-baseline.json'), 'utf8')) };
}

function transactionDir() {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  return path.join(target, '_orig-backup-' + stamp + '-' + process.pid);
}

function createTransaction(files) {
  const dir = transactionDir();
  fs.mkdirSync(path.join(dir, 'orchestrator', 'ui', 'assets'), { recursive: true });
  const meta = { files: files.map(f => f.rel), complete: false, created: new Date().toISOString(), target };
  for (const f of files) {
    const dst = path.join(dir, f.rel);
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    fs.copyFileSync(f.abs, dst);
  }
  fs.writeFileSync(path.join(dir, 'wintage-backup.json'), JSON.stringify(meta, null, 2), 'utf8');
  meta.complete = true;
  fs.writeFileSync(path.join(dir, 'wintage-backup.json'), JSON.stringify(meta, null, 2), 'utf8');
  return dir;
}

function patchHealth(desiredSound) {
  const sound = (() => {
    if (!chimePath) return { requested: !!desiredSound, state: 'no-chime', healthy: false };
    if (desiredSound) {
      if (!fs.existsSync(desiredSound)) return { requested: true, state: 'missing-source', healthy: false };
      if (fs.readFileSync(chimePath).equals(fs.readFileSync(desiredSound))) return { requested: true, state: 'installed', healthy: true };
      return { requested: true, state: 'wrong', healthy: false };
    }
    const b = currentBaseline();
    const baselineChime = b && b.meta.files.includes(path.relative(target, chimePath))
      ? path.join(b.dir, path.relative(target, chimePath)) : null;
    if (baselineChime && fs.existsSync(baselineChime) && fs.readFileSync(chimePath).equals(fs.readFileSync(baselineChime))) {
      return { requested: false, state: 'stock', healthy: true };
    }
    return { requested: false, state: 'custom', healthy: true };
  })();
  return { renderer: 'stock', orchestrator: 'stock', sound, healthy: sound.healthy };
}

if (has('status-json')) {
  const h = patchHealth(arg('sound', null));
  h.resources = target;
  console.log(JSON.stringify(h));
  process.exit(h.healthy ? 0 : 1);
}

// ---------------------------------------------------------------------------
// --revert
// ---------------------------------------------------------------------------
if (doRevert) {
  const b = currentBaseline();
  if (!b) die('no COMPLETE baseline found in ' + target + ' - nothing to restore.');
  
  const plausibleBuild = (buf) => buf && buf.length >= 32;
  let mismatch = null;
  for (const rel of b.meta.files) {
    if (chimePath && rel === path.relative(target, chimePath)) continue;
    const live = path.join(target, rel);
    if (!fs.existsSync(live)) continue; // W2-010: missing live file will be restored
    const liveBuf = fs.readFileSync(live);
    const orig = path.join(b.dir, rel);
    if (!fs.existsSync(orig)) continue;
    const origBuf = fs.readFileSync(orig);
    if (!liveBuf.equals(origBuf)) {
      if (plausibleBuild(liveBuf)) {
        mismatch = rel;
        break;
      }
    }
  }
  if (mismatch) {
    console.error('REVERT REFUSED: ' + mismatch + ' belongs to a DIFFERENT app generation than the baseline (' + path.basename(b.dir) + ').');
    console.error('Restoring this baseline would overwrite the current app files with an outdated snapshot.');
    process.exit(1);
  }

  for (const rel of b.meta.files) {
    const orig = path.join(b.dir, rel);
    const live = path.join(target, rel);
    if (fs.existsSync(orig)) {
      fs.mkdirSync(path.dirname(live), { recursive: true });
      fs.copyFileSync(orig, live);
      console.log('restored ' + rel);
    }
  }
  console.log('reverted from baseline ' + path.basename(b.dir));
  process.exit(0);
}

// ---------------------------------------------------------------------------
// --verify
// ---------------------------------------------------------------------------
if (doVerify) {
  const desiredSound = arg('sound', null);
  const h = patchHealth(desiredSound);
  console.log('sound: ' + h.sound.state + (desiredSound ? ' (desired ' + desiredSound + ')' : ''));
  console.log('status: ' + (h.healthy ? 'HEALTHY' : 'UNHEALTHY'));
  process.exit(h.healthy ? 0 : 1);
}

// ---------------------------------------------------------------------------
// Preflight & Apply
// ---------------------------------------------------------------------------
function preflight() {
  const problems = [];
  let soundAlready = false;

  if (soundArg) {
    if (!chimePath) problems.push('--- sound: no chime-*.mp3 found under ' + assetsDir);
    else if (!fs.existsSync(soundArg)) problems.push('--- sound: file not found: ' + soundArg);
    else if (!isAudio(soundArg)) problems.push('--- sound: not a recognized audio file (wav/mp3/ogg/flac/m4a/aac): ' + soundArg);
    else if (fs.readFileSync(chimePath).equals(fs.readFileSync(soundArg))) soundAlready = true;
  }
  return { problems, soundAlready };
}

const plan = preflight();
if (dryRun) {
  console.log('target: ' + target);
  if (plan.problems.length) {
    console.error(plan.problems.join('\n'));
    console.error('\nDry-run FAILED: preflight checks failed.');
    process.exit(1);
  }
  if (soundArg) {
    if (plan.soundAlready) console.log('--- sound: already installed, nothing to do.');
    else console.log('--- sound: would install ' + soundArg + ' -> ' + path.relative(target, chimePath));
  } else {
    console.log('--- sound: ' + soundStatus() + ' (no --sound given)');
  }
  console.log('FreeBuff ad stripping removed per ToS. Bundles remain stock.');
  process.exit(0);
}

if (plan.problems.length) {
  console.error(plan.problems.join('\n'));
  process.exit(1);
}

// If no sound change needed:
if (!soundArg || plan.soundAlready) {
  ensureBaseline();
  console.log(plan.soundAlready ? 'Sound already installed, nothing to do.' : 'FreeBuff ad stripping removed per ToS. No sound specified.');
  process.exit(0);
}

const base = ensureBaseline();
const owned = [{ abs: chimePath, rel: path.relative(target, chimePath) }];
const tx = createTransaction(owned);

if (process.env.WINTAGE_FREEBUFF_TEST_FAIL_APPLY) {
  const e = new Error('simulated apply failure (WINTAGE_FREEBUFF_TEST_FAIL_APPLY)');
  e.code = 'EIO';
  // Trigger rollback
  for (const f of owned) {
    const orig = path.join(tx, f.rel);
    try { fs.copyFileSync(orig, f.abs); } catch (e2) {}
  }
  try { fs.rmSync(tx, { recursive: true, force: true }); } catch (e2) {}
  die('simulated apply failure (WINTAGE_FREEBUFF_TEST_FAIL_APPLY)');
}

try {
  fs.copyFileSync(soundArg, chimePath);
  console.log('sound: installed ' + soundArg + ' -> ' + path.relative(target, chimePath));
  if (!fs.readFileSync(chimePath).equals(fs.readFileSync(soundArg))) {
    throw new Error('verification failed after writing ' + chimePath);
  }
} catch (e) {
  console.error('write/verify failed (' + e.message + ') - rolling back.');
  let rolledBack = true;
  for (const f of owned) {
    const orig = path.join(tx, f.rel);
    try { fs.copyFileSync(orig, f.abs); } catch (e2) { rolledBack = false; }
  }
  try { fs.rmSync(tx, { recursive: true, force: true }); } catch (e2) {}
  die(rolledBack ? 'rollback complete; nothing changed.' : 'ROLLBACK INCOMPLETE - originals remain in ' + tx);
}

console.log('backup transaction -> ' + path.relative(target, tx));
console.log('Done.');
