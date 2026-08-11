#!/usr/bin/env node
// Wintage - FreeBuff desktop ad removal patch.
//
// Cuts the ads OUT of the installed FreeBuff, not just hides them:
//
//   resources/orchestrator/orchestrator.js          - the three /api/ad/* routes
//                                                     stop calling the ad network,
//                                                     and the live-turn inline ad
//                                                     request is short-circuited.
//   resources/orchestrator/ui/assets/index-<hash>.js - the sponsored-ad component
//                                                     call sites are replaced with
//                                                     null and the ad API client is
//                                                     neutralised, so nothing renders
//                                                     and no /api/ad/* request ever
//                                                     leaves the renderer.
//
// Why byte-level replacement and not a full-file payload (the old
// _FREEBUFF_PATCH approach): the bundle filename embeds a build hash and changes
// every release, so a payload file is dead on arrival after the first update.
// Instead we discover the CURRENT bundle from index.html and swap exact strings
// inside it.
//
// FUTURE VERSIONS. Every target has TWO matchers: an exact byte string for the
// build it was written against, and a regular-expression fallback that survives
// what actually changes between builds:
//
//   * the orchestrator (orchestrator.js) is NOT minified - names like
//     `maybeRequestAd`, `app.ads.slotAd` and `exports_Effect` are readable and
//     stable, so its exact strings hold for a long time;
//   * the renderer bundle (index-*.js) IS minified, so one-letter identifiers
//     (b, s2, Ie, ...) can be renamed by the next build. The regex fallbacks are
//     anchored on what a minifier CANNOT rename: the string literals
//     "/api/ad/slot", "/api/ad/impression", "/api/ad/click", the protocol
//     discriminator `case"ad":`, the class `sponsored-ad`, and the placement
//     variants `variant:"banner"` / `variant:"card"`.
//
//   `--scan` reports which ad markers exist in the CURRENT install, so after a
//   FreeBuff update you can see at a glance what the new build still carries and
//   whether the patch strings need refreshing.
//
// Every replacement is verified - if both the exact string and the regex miss,
// the script says which target no longer matched instead of silently shipping a
// no-op patch.
//
// Usage:
//   node desktop/patch-freebuff-ads.js                  # patch (asks nothing, one transaction backup first)
//   node desktop/patch-freebuff-ads.js --sound "C:\...\my.mp3"   # also install a custom completion sound (wav/mp3/ogg/flac/m4a/aac)
//   node desktop/patch-freebuff-ads.js --scan           # list ad markers present in this install
//   node desktop/patch-freebuff-ads.js --dry-run        # validate everything, exit nonzero on any missing/incompatible input, touch nothing
//   node desktop/patch-freebuff-ads.js --verify         # report patched / not / unknown
//   node desktop/patch-freebuff-ads.js --revert         # restore the newest COMPLETE transaction
//   node desktop/patch-freebuff-ads.js --target "D:\...\@codebufffreebuff-desktop"
//
// The completion sound is the file the renderer plays when a turn finishes
// (chime-<hash>.mp3 in the same assets dir). It is discovered the same way the
// bundle is - the name embeds the build hash, so a version-locked filename would
// die on the first update. --sound <path> copies the given audio file (wav,
// mp3, ogg, flac, m4a, aac) over it.
//
// Apply is preflight-first (T-189): ALL files are read and ALL required matchers
// and inputs are validated BEFORE anything is written or backed up. Every owned
// file is then captured into ONE _orig-backup-<stamp>-<pid> transaction with a
// metadata file; --revert restores only a COMPLETE transaction and refuses
// partial/crashed dirs. Run it again after every FreeBuff update - updates
// restore stock files.
//
// NOTE on shim.cjs: this file is the byte-level layer. Wintage's shared
// Electron shim additionally blocks /api/ad/* fetches and hides .sponsored-ad
// in the page, so even a brand-new bundle whose strings this script has not
// learned yet cannot surface ads. Both layers are independent on purpose.

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

// ---------------------------------------------------------------------------
// Locate the renderer bundle the way the app itself does: read index.html.
// ---------------------------------------------------------------------------
const orchestratorDir = path.join(target, 'resources', 'orchestrator');
const indexHtmlPath = path.join(orchestratorDir, 'ui', 'index.html');
const orchestratorPath = path.join(orchestratorDir, 'orchestrator.js');

let bundlePath = null;
if (fs.existsSync(indexHtmlPath)) {
  const html = fs.readFileSync(indexHtmlPath, 'utf8');
  const m = /assets\/(index-[A-Za-z0-9_-]+\.js)/.exec(html);
  if (m) bundlePath = path.join(orchestratorDir, 'ui', 'assets', m[1]);
}
if (!bundlePath || !fs.existsSync(bundlePath)) {
  die('could not locate the renderer bundle (index-*.js) under ' + orchestratorDir);
}

// ---------------------------------------------------------------------------
// Locate the completion sound (chime-<hash>.mp3) the same way: glob the assets
// dir, never a version-locked name. Its filename changes with every build.
// ---------------------------------------------------------------------------
const assetsDir = path.join(orchestratorDir, 'ui', 'assets');
let chimePath = null;
if (fs.existsSync(assetsDir)) {
  // Several builds can leave several chime-*.mp3 files behind (an update ships a
  // new hash and may not delete the old one). Newest mtime, not name: hash
  // prefixes sort arbitrarily.
  const hits = fs.readdirSync(assetsDir)
    .filter(f => /^chime-.*\.mp3$/.test(f))
    .map(f => path.join(assetsDir, f))
    .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);
  if (hits.length) chimePath = hits[0];
}

const soundArg = arg('sound', null);
// Sniffs the leading bytes the same way the GUI does (Get-FbAudioKind), so the
// two layers agree on what counts as a playable audio file. Only the container
// is checked - the renderer (Chromium) decodes by content, not by extension.
const isAudio = p => {
  try {
    const b = fs.readFileSync(p);
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
// Patches. Each entry has:
//   name   - human label
//   exact  - byte-exact string for the build this was written against (may be
//            the only matcher when a regex cannot be written safely)
//   regex  - version-tolerant fallback, anchored on unminifiable literals
//   to     - the replacement
// `exact` is tried first (precise, counts occurrences), `regex` second.
// All literals are ASCII and files are written in binary-safe utf8 mode so LF
// never turns into CRLF.
// ---------------------------------------------------------------------------
function P(name, exact, regex, to) { return { name, exact, regex, to }; }

// --- renderer bundle (minified) ---
const RENDERER_PATCHES = [
  P(
    'ad API client -> no-op',
    'adSlot:e=>Ie("/api/ad/slot",{threadId:e}),adImpression:e=>Ie("/api/ad/impression",{impUrl:e}),adClick:e=>Ie("/api/ad/click",{impUrl:e})',
    /adSlot:\s*[A-Za-z0-9_$]+\s*=>\s*[A-Za-z0-9_$]+\("[^"]*\/api\/ad\/slot"[^)]*\),\s*adImpression:\s*[A-Za-z0-9_$]+\s*=>\s*[A-Za-z0-9_$]+\("[^"]*\/api\/ad\/impression"[^)]*\),\s*adClick:\s*[A-Za-z0-9_$]+\s*=>\s*[A-Za-z0-9_$]+\("[^"]*\/api\/ad\/click"[^)]*\)/,
    'adSlot:()=>Promise.resolve(null),adImpression:()=>Promise.resolve(null),adClick:()=>Promise.resolve(null)'
  ),
  P(
    'message-part ad card -> null',
    'case"ad":return b.jsx(s2,{ad:m.ad,variant:"card"})',
    /case"ad":return [A-Za-z0-9_$]*\.jsx\([A-Za-z0-9_$]*,\{ad:[A-Za-z0-9_$]*\.[A-Za-z0-9_$]*,variant:"card"\}\)/,
    'case"ad":return null'
  ),
  P(
    'thread banner ad -> null',
    '!i||!r?null:b.jsx(s2,{ad:r,variant:"banner"})',
    /:[A-Za-z0-9_$]*\.jsx\([A-Za-z0-9_$]*,\{ad:[A-Za-z0-9_$]*,variant:"banner"\}\)/,
    ':null'
  ),
];

// --- orchestrator (NOT minified - readable, version-stable) ---
const ORCHESTRATOR_PATCHES = [
  P(
    '/api/ad/slot returns null (no auction call)',
    'const ad2 = yield* exports_Effect.promise(() => app.ads.slotAd(threadId));',
    /const ad2 = yield\* exports_Effect\.promise\(\(\) => app\.ads\.slotAd\([A-Za-z0-9_$]*\)\);/,
    'const ad2 = null;'
  ),
  P(
    '/api/ad/impression is a no-op',
    'const ok2 = yield* exports_Effect.promise(() => app.ads.impression(impUrl));',
    /const ok2 = yield\* exports_Effect\.promise\(\(\) => app\.ads\.impression\([A-Za-z0-9_$]*\)\);/,
    'const ok2 = false;'
  ),
  P(
    '/api/ad/click is a no-op',
    'const ok2 = yield* exports_Effect.promise(() => app.ads.click(impUrl));',
    /const ok2 = yield\* exports_Effect\.promise\(\(\) => app\.ads\.click\([A-Za-z0-9_$]*\)\);/,
    'const ok2 = false;'
  ),
  P(
    'live-turn inline ad request disabled',
    'if (harnessId !== "codebuff")',
    /if \(harnessId !== "codebuff"\)/,
    'if (true)'
  ),
];

// ---------------------------------------------------------------------------
// --scan: report which ad markers exist in the CURRENT install. Run this after
// a FreeBuff update to learn what the new build still carries.
// ---------------------------------------------------------------------------
if (doScan) {
  console.log('target: ' + target);
  const report = (label, filePath, markers) => {
    console.log('\n--- ' + label + ': ' + path.relative(target, filePath));
    const text = fs.readFileSync(filePath, 'utf8');
    for (const [desc, needle] of markers) {
      const found = typeof needle === 'string' ? text.includes(needle) : needle.test(text);
      console.log((found ? '  FOUND    ' : '  absent   ') + desc);
    }
  };
  // "live" markers match the UNPATCHED forms only, so a freshly patched install
  // scans clean: dead component definitions, route registrations that return
  // null, and the no-op client keys are expected remnants, not ad code.
  report('renderer bundle', bundlePath, [
    ['path literal "/api/ad/slot"', '"/api/ad/slot"'],
    ['path literal "/api/ad/impression"', '"/api/ad/impression"'],
    ['path literal "/api/ad/click"', '"/api/ad/click"'],
    ['ad client calling the network (adSlot:e=>Ie(...))', /adSlot:\s*[A-Za-z0-9_$]+\s*=>/],
    ['message-part ad card RENDER call', /case"ad":return [A-Za-z0-9_$]*\.jsx\(/],
    ['thread banner RENDER call', /variant:"banner"/],
    ['sponsored-ad class (component def; harmless if call sites are null)', 'sponsored-ad'],
  ]);
  report('orchestrator', orchestratorPath, [
    ['route "/api/ad/slot" registered (returns null after patch)', '/api/ad/slot'],
    ['route "/api/ad/impression" registered (returns false after patch)', '/api/ad/impression'],
    ['route "/api/ad/click" registered (returns false after patch)', '/api/ad/click'],
    ['ad auction CALL app.ads.slotAd(...)', /app\.ads\.slotAd\(/],
    ['ad impression CALL app.ads.impression(...)', /app\.ads\.impression\(/],
    ['ad click CALL app.ads.click(...)', /app\.ads\.click\(/],
    ['inline ad request reachable (maybeRequestAd not short-circuited)', /if \(harnessId !== "codebuff"\)/],
    ['remote ad network /api/v1/ads endpoint defined (dead code if auction call sites are nulled)', /this\.post\("\/api\/v1\/ads"/],
  ]);
  console.log('\nFOUND = live ad code this patch must neutralise. After patching, only benign remnants should remain (component definitions, null-returning routes).');
  process.exit(0);
}

// ---------------------------------------------------------------------------
// Match helpers
// ---------------------------------------------------------------------------
const readText = p => fs.readFileSync(p, 'utf8');
const writeText = (p, text) => fs.writeFileSync(p, text, 'utf8');

function applyPatches(filePath, patches, label) {
  const text = readText(filePath);
  let result = text;
  const applied = [];
  const missing = [];
  for (const p of patches) {
    if (p.exact && result.includes(p.exact)) {
      const count = result.split(p.exact).length - 1;
      result = result.split(p.exact).join(p.to);
      applied.push(p.name + ' (exact x' + count + ')');
    } else if (p.regex && p.regex.test(result)) {
      const count = (result.match(new RegExp(p.regex.source, 'g')) || []).length;
      result = result.replace(new RegExp(p.regex.source, 'g'), p.to);
      applied.push(p.name + ' (regex x' + count + ')');
    } else {
      missing.push(p.name);
    }
  }
  return { text: result, applied, missing };
}

function isPatched(filePath, patches) {
  const text = readText(filePath);
  const allNew = patches.every(p => text.includes(p.to));
  const anyOld = patches.some(p =>
    (p.exact && text.includes(p.exact)) || (p.regex && p.regex.test(text))
  );
  return { allNew, anyOld };
}

// ---------------------------------------------------------------------------
// Persistent pristine BASELINE (T-190): the stock snapshot of EVERY Wintage-owned
// file for the current app generation. Revert restores from this baseline, never
// from a per-apply transaction -- so a later sound-only or subset Apply can never
// shadow the earlier recovery source. A new generation (upstream replaced an
// owned bundle with fresh stock) establishes a NEW baseline from the current
// files; a same-generation repaint keeps the existing one.
// ---------------------------------------------------------------------------
function ownedFileList() {
  const list = [
    { abs: bundlePath, rel: path.relative(target, bundlePath) },
    { abs: orchestratorPath, rel: path.relative(target, orchestratorPath) },
  ];
  if (chimePath) list.push({ abs: chimePath, rel: path.relative(target, chimePath) });
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
  return out.sort((a, b) => b.dir.localeCompare(a.dir)); // newest generation first
}

function currentBaseline() { return baselines()[0] || null; }

// A new generation means the CURRENT owned files are no longer the baseline's
// stock. Detected by content, not by string presence: a patched file is still
// this generation; a live file that is not patched AND differs from the
// baseline's own stock snapshot is a new generation whether or not it happens to
// still carry the old matcher strings (T-191). The old heuristic only caught
// matcher-less restructures, which the patch cannot apply to at all - so a real
// app update that kept the ad strings kept the stale baseline too.
function upstreamReplacedOwnedFile() {
  const b = currentBaseline();
  if (!b) return true;
  for (const rel of b.meta.files) {
    const t = TARGET_FILES.find(f => f.rel === rel);
    if (!t) continue; // generation-neutral files (chime) are skipped
    const live = path.join(target, rel);
    if (!fs.existsSync(live)) continue;
    const { allNew } = isPatched(live, t.patches);
    if (allNew) continue; // still carries this generation's Wintage patch
    const orig = path.join(b.dir, rel);
    if (!fs.existsSync(orig)) return true;
    if (!fs.readFileSync(live).equals(fs.readFileSync(orig))) return true;
  }
  return false;
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

// T-191 P1#16: baselines accumulate one per app generation forever. Each holds a
// full copy of every owned file, so keep only the newest few generations as
// recovery sources and drop the rest. Old generations are unreachable through
// currentBaseline() anyway - they can never be the revert target.
function pruneBaselines() {
  const all = baselines();
  if (all.length <= 3) return;
  for (const old of all.slice(3)) {
    try { fs.rmSync(old.dir, { recursive: true, force: true }); console.log('pruned stale baseline ' + path.basename(old.dir)); }
    catch (e) { }
  }
}

// One transaction backup (T-189): ALL files THIS OPERATION writes go into a
// SINGLE _orig-backup-<stamp>-<pid> dir used ONLY for rollback of the current
// apply's writes. Revert sources come from the baseline, never from here.
function transactionDir() {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  return path.join(target, '_orig-backup-' + stamp + '-' + process.pid);
}

function createTransaction(files, extraText) {
  // files: [{ abs, rel }]
  const dir = transactionDir();
  fs.mkdirSync(path.join(dir, 'orchestrator', 'ui', 'assets'), { recursive: true });
  const meta = { files: files.map(f => f.rel), complete: false, created: new Date().toISOString(), target };
  for (const f of files) {
    const dst = path.join(dir, f.rel);
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    fs.copyFileSync(f.abs, dst);
  }
  if (extraText) fs.writeFileSync(path.join(dir, extraText.rel), extraText.text, 'utf8');
  meta.files = meta.files.concat(extraText ? [extraText.rel] : []);
  fs.writeFileSync(path.join(dir, 'wintage-backup.json'), JSON.stringify(meta, null, 2), 'utf8');
  meta.complete = true;
  fs.writeFileSync(path.join(dir, 'wintage-backup.json'), JSON.stringify(meta, null, 2), 'utf8');
  return dir;
}

function completeTransactions() {
  const dirs = fs.readdirSync(target).filter(d => /^_orig-backup-/.test(d));
  const complete = [];
  for (const d of dirs) {
    const dir = path.join(target, d);
    const metaPath = path.join(dir, 'wintage-backup.json');
    if (!fs.existsSync(metaPath)) continue;                 // partial/crash -> never selectable
    try {
      const meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
      if (meta.complete !== true || !Array.isArray(meta.files) || !meta.files.length) continue;
      if (meta.files.some(rel => !fs.existsSync(path.join(dir, rel)))) continue;  // listed file missing -> partial
      complete.push({ dir, meta });
    } catch (e) { continue; }
  }
  return complete.sort((a, b) => b.dir.localeCompare(a.dir)); // newest stamp first
}

// Per-file patch state classifier.
function patchState(filePath, patches) {
  const { allNew, anyOld } = isPatched(filePath, patches);
  if (allNew && !anyOld) return 'patched';
  if (!allNew && !anyOld) return 'stock';
  if (anyOld) return 'partial';
  return 'stale';
}

// Machine-readable health (T-190): used by install.ps1 for the FreeBuff health
// probe and by --verify with a desired sound. PowerShell never re-parses bundles.
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
  const renderer = patchState(bundlePath, RENDERER_PATCHES);
  const orchestrator = patchState(orchestratorPath, ORCHESTRATOR_PATCHES);
  const healthy = renderer === 'patched' && orchestrator === 'patched' && sound.healthy;
  return { renderer, orchestrator, sound, healthy };
}

// ---------------------------------------------------------------------------
// --status-json  (machine-readable patch health, optionally against a desired sound)
// ---------------------------------------------------------------------------
if (has('status-json')) {
  const h = patchHealth(arg('sound', null));
  h.resources = target;
  console.log(JSON.stringify(h));
  process.exit(h.healthy ? 0 : 1);
}

// ---------------------------------------------------------------------------
// --revert  (restores ONLY the current-generation baseline; partial dirs refused)
// ---------------------------------------------------------------------------
const TARGET_FILES = [
  { abs: bundlePath, rel: path.relative(target, bundlePath), patches: RENDERER_PATCHES, label: 'renderer bundle' },
  { abs: orchestratorPath, rel: path.relative(target, orchestratorPath), patches: ORCHESTRATOR_PATCHES, label: 'orchestrator' },
];
if (doRevert) {
  const b = currentBaseline();
  if (!b) die('no COMPLETE baseline found in ' + target + ' - nothing to restore. A baseline is only ever captured from stock files, so its absence means no verified pristine state exists.');
  // T-191 P0#4: generation reconciliation. Never restore an OLD baseline over a
  // NEW generation's files: a live owned file that is fresh stock (no patch
  // markers AND no old strings) and does NOT match the baseline's own stock
  // snapshot means upstream shipped a new generation whose pristine state this
  // baseline does not hold. Restoring it would silently replace the new app
  // files with an outdated snapshot. A live file that is NOT a plausible build
  // (torn/truncated/garbage) is damage within the current generation, not a new
  // one - the baseline restore is exactly the repair it needs.
  const plausibleBuild = (buf) => buf && buf.length >= 64 && !buf.includes(0);
  let mismatch = null;
  for (const rel of b.meta.files) {
    const t = TARGET_FILES.find(f => f.rel === rel);
    if (!t) continue; // generation-neutral files (e.g. the chime) are skipped
    const live = path.join(target, rel);
    if (!fs.existsSync(live)) { mismatch = rel; break; }
    const liveBuf = fs.readFileSync(live);
    const { allNew, anyOld } = isPatched(live, t.patches);
    if (allNew || anyOld) continue; // still carries this generation's Wintage state
    if (!plausibleBuild(liveBuf)) continue; // damage, not a new generation
    const orig = path.join(b.dir, rel);
    if (!fs.existsSync(orig) || !liveBuf.equals(fs.readFileSync(orig))) { mismatch = rel; break; }
  }
  if (mismatch) {
    console.error('REVERT REFUSED: ' + mismatch + ' belongs to a DIFFERENT app generation than the baseline (' + path.basename(b.dir) + ').');
    console.error('Restoring this baseline would overwrite the current app files with an outdated snapshot.');
    console.error('Run Apply once on the current generation (it establishes a matching baseline), or accept the loss and delete the stale _orig-baseline-* directories manually.');
    process.exit(1);
  }
  for (const rel of b.meta.files) {
    const orig = path.join(b.dir, rel);
    const live = path.join(target, rel);
    if (fs.existsSync(orig)) { if (fs.existsSync(live)) fs.copyFileSync(orig, live); console.log('restored ' + rel); }
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
  console.log('renderer bundle: ' + h.renderer);
  console.log('orchestrator: ' + h.orchestrator);
  console.log('sound: ' + h.sound.state + (desiredSound ? ' (desired ' + desiredSound + ')' : ''));
  console.log('status: ' + (h.healthy ? 'PATCHED' : 'UNHEALTHY'));
  process.exit(h.healthy ? 0 : 1);
}

// ---------------------------------------------------------------------------
// Preflight: classify EVERY file and validate EVERY input BEFORE anything is
// written or backed up (T-189). A missing matcher in any file, a missing sound
// file, or an incompatible build exits 1 with ZERO mutations.
// ---------------------------------------------------------------------------

function preflight() {
  const files = [];
  const problems = [];
  let soundAlready = false;
  for (const f of TARGET_FILES) {
    const { allNew } = isPatched(f.abs, f.patches);
    if (allNew) { files.push({ ...f, state: 'already' }); continue; }
    const r = applyPatches(f.abs, f.patches, f.label);
    if (r.missing.length) {
      problems.push('--- ' + f.label + ': ' + r.missing.length + ' required matcher(s) not found in ' + f.rel + ':' +
        r.missing.map(m => '\n    ' + m).join(''));
      continue;
    }
    files.push({ ...f, state: 'apply', result: r });
  }
  if (soundArg) {
    if (!chimePath) problems.push('--- sound: no chime-*.mp3 found - cannot install a custom sound');
    else if (!fs.existsSync(soundArg)) problems.push('--- sound: file not found: ' + soundArg);
    else if (!isAudio(soundArg)) problems.push('--- sound: not a recognized audio file (wav/mp3/ogg/flac/m4a/aac): ' + soundArg);
    else if (fs.readFileSync(chimePath).equals(fs.readFileSync(soundArg))) soundAlready = true;
  }
  return { files, problems, soundAlready: !!soundAlready };
}

const plan = preflight();
if (dryRun) {
  console.log('target: ' + target);
  if (plan.problems.length) {
    console.error(plan.problems.join('\n'));
    console.error('\nDry-run FAILED: the patch cannot be applied to this build without mutation. Nothing was changed.');
    process.exit(1);
  }
  for (const f of plan.files) {
    if (f.state === 'already') { console.log('--- ' + f.label + ': already patched, nothing to do.'); continue; }
    console.log('--- ' + f.label + ': ' + f.rel);
    for (const a of f.result.applied) console.log('  would apply: ' + a);
  }
  if (soundArg) {
    if (fs.readFileSync(chimePath).equals(fs.readFileSync(soundArg))) console.log('--- sound: already installed, nothing to do.');
    else console.log('--- sound: would install ' + soundArg + ' -> ' + path.relative(target, chimePath) + ' (stock kept in the transaction)');
  } else {
    console.log('--- sound: ' + soundStatus() + ' (no --sound given)');
  }
  process.exit(0);
}

if (plan.problems.length) {
  console.error(plan.problems.join('\n'));
  console.error('\nNothing was changed. The build changed shape or a required input is missing - run --scan and update the patch strings.');
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Apply: ONE transaction, then write, then verify, with rollback on failure.
// ---------------------------------------------------------------------------
const toWrite = plan.files.filter(f => f.state === 'apply');
if (!toWrite.length && !(soundArg && !plan.soundAlready)) {
  console.log('Already patched, nothing to do.');
  process.exit(0);
}

// Establish the current-generation baseline BEFORE any mutation, so Revert can
// restore every owned file consistently (T-190).
const base = ensureBaseline();

const owned = [];
for (const f of toWrite) owned.push({ abs: f.abs, rel: f.rel });
if (soundArg && chimePath && !plan.soundAlready) owned.push({ abs: chimePath, rel: path.relative(target, chimePath) });
const tx = createTransaction(owned);

// Test seam: deterministically exercise the apply-phase failure path (the caller
// restores its own pre-state when this exits nonzero).
if (process.env.WINTAGE_FREEBUFF_TEST_FAIL_APPLY) {
  const e = new Error('simulated apply failure (WINTAGE_FREEBUFF_TEST_FAIL_APPLY)');
  e.code = 'EIO';
  throw e;
}

try {
  for (const f of toWrite) {
    writeText(f.abs, f.result.text);
    console.log('--- ' + f.label + ': ' + f.rel);
    for (const a of f.result.applied) console.log('  ' + a);
  }
  if (soundArg && chimePath && !plan.soundAlready) {
    fs.copyFileSync(soundArg, chimePath);
    console.log('sound: installed ' + soundArg + ' -> ' + path.relative(target, chimePath));
  }
  // Verify every output before reporting success.
  for (const f of toWrite) {
    const { allNew } = isPatched(f.abs, f.patches);
    if (!allNew) throw new Error('verification failed after writing ' + f.rel + ' - patched strings not present');
  }
} catch (e) {
  // Rollback: restore every owned original from the transaction, then drop it.
  console.error('write/verify failed (' + e.message + ') - rolling back.');
  let rolledBack = true;
  for (const f of owned) {
    const orig = path.join(tx, f.rel);
    try { fs.copyFileSync(orig, f.abs); } catch (e2) { rolledBack = false; }
  }
  try { fs.rmSync(tx, { recursive: true, force: true }); } catch (e2) { }
  die(rolledBack ? 'rollback complete; nothing changed.' : 'ROLLBACK INCOMPLETE - originals remain in ' + tx);
}

console.log('backup transaction -> ' + path.relative(target, tx));
console.log('\nDone. Restart FreeBuff for the changes to load.');
console.log('Re-run after every FreeBuff update. --scan shows what the new build still carries. --revert restores the complete transaction.');
