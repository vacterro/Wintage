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
//   node desktop/patch-freebuff-ads.js                  # patch (asks nothing, backs up first)
//   node desktop/patch-freebuff-ads.js --sound "C:\...\my.mp3"   # also install a custom completion sound (wav/mp3/ogg/flac/m4a/aac)
//   node desktop/patch-freebuff-ads.js --scan           # list ad markers present in this install
//   node desktop/patch-freebuff-ads.js --dry-run        # say what would change, touch nothing
//   node desktop/patch-freebuff-ads.js --verify         # report patched / not / unknown
//   node desktop/patch-freebuff-ads.js --revert         # restore newest _orig-backup-*
//   node desktop/patch-freebuff-ads.js --target "D:\...\@codebufffreebuff-desktop"
//
// The completion sound is the file the renderer plays when a turn finishes
// (chime-<hash>.mp3 in the same assets dir). It is discovered the same way the
// bundle is - the name embeds the build hash, so a version-locked filename would
// die on the first update. --sound <path> copies the given audio file (wav,
// mp3, ogg, flac, m4a, aac) over it, keeping the stock file as
// chime-*.mp3.bak; --revert restores it.
//
// Any file overwritten is copied to _orig-backup-<timestamp>/ inside the install
// dir first. Run it again after every FreeBuff update - updates restore stock files.
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

function backup(filePath) {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const backupDir = path.join(target, '_orig-backup-' + stamp);
  fs.mkdirSync(backupDir, { recursive: true });
  const rel = path.relative(target, filePath);
  const dst = path.join(backupDir, rel);
  fs.mkdirSync(path.dirname(dst), { recursive: true });
  fs.copyFileSync(filePath, dst);
  return backupDir;
}

function newestBackup() {
  const dirs = fs.readdirSync(target).filter(d => /^_orig-backup-/.test(d)).sort();
  return dirs.length ? path.join(target, dirs[dirs.length - 1]) : null;
}

// ---------------------------------------------------------------------------
// --revert
// ---------------------------------------------------------------------------
if (doRevert) {
  const bk = newestBackup();
  if (!bk) die('no _orig-backup-* found in ' + target);
  for (const p of [bundlePath, orchestratorPath]) {
    const orig = path.join(bk, path.relative(target, p));
    if (fs.existsSync(orig)) { fs.copyFileSync(orig, p); console.log('restored ' + path.relative(target, p)); }
  }
  // The stock sound is kept as chime-*.mp3.bak, so it survives --revert too.
  if (chimePath && fs.existsSync(chimePath + '.bak')) {
    fs.copyFileSync(chimePath + '.bak', chimePath);
    console.log('restored sound ' + path.relative(target, chimePath));
  }
  console.log('reverted from ' + path.basename(bk));
  process.exit(0);
}

// ---------------------------------------------------------------------------
// --verify
// ---------------------------------------------------------------------------
if (doVerify) {
  let status = 'PATCHED';
  for (const [filePath, patches] of [[bundlePath, RENDERER_PATCHES], [orchestratorPath, ORCHESTRATOR_PATCHES]]) {
    const { allNew, anyOld } = isPatched(filePath, patches);
    const label = path.relative(target, filePath);
    if (!allNew && !anyOld) { console.log(label + ': STOCK (not patched, no patch markers)'); status = 'STOCK'; }
    else if (allNew && !anyOld) { console.log(label + ': patched OK'); }
    else if (anyOld) { console.log(label + ': PARTIAL (some old strings still present)'); status = 'PARTIAL'; }
    else { console.log(label + ': STALE (patch strings no longer match this build)'); status = 'STALE'; }
  }
  console.log('sound: ' + soundStatus());
  console.log('status: ' + status);
  process.exit(status === 'PATCHED' ? 0 : 1);
}

// ---------------------------------------------------------------------------
// Apply
// ---------------------------------------------------------------------------
if (dryRun) {
  console.log('target: ' + target);
  for (const [filePath, patches, label] of [[bundlePath, RENDERER_PATCHES, 'renderer bundle'], [orchestratorPath, ORCHESTRATOR_PATCHES, 'orchestrator']]) {
    const { allNew } = isPatched(filePath, patches);
    if (allNew) { console.log('--- ' + label + ': already patched, nothing to do.'); continue; }
    const r = applyPatches(filePath, patches, label);
    console.log('--- ' + label + ': ' + path.relative(target, filePath));
    for (const a of r.applied) console.log('  would apply: ' + a);
    for (const m of r.missing) console.log('  WARNING not found (build changed?): ' + m);
  }
  if (soundArg) {
    if (!chimePath) console.log('--- sound: ' + soundStatus() + ' - cannot install custom sound');
    else if (!fs.existsSync(soundArg)) console.log('--- sound: WARNING file not found: ' + soundArg);
    else if (!isAudio(soundArg)) console.log('--- sound: WARNING not a recognized audio file: ' + soundArg);
    else if (fs.readFileSync(chimePath).equals(fs.readFileSync(soundArg))) console.log('--- sound: already installed, nothing to do.');
    else console.log('--- sound: would install ' + soundArg + ' -> ' + path.relative(target, chimePath) + ' (stock kept as .bak)');
  } else {
    console.log('--- sound: ' + soundStatus() + ' (no --sound given)');
  }
  process.exit(0);
}

let ok = true;
for (const [filePath, patches, label] of [[bundlePath, RENDERER_PATCHES, 'renderer bundle'], [orchestratorPath, ORCHESTRATOR_PATCHES, 'orchestrator']]) {
  const { allNew } = isPatched(filePath, patches);
  if (allNew) { console.log(label + ': already patched, nothing to do.'); continue; }
  const r = applyPatches(filePath, patches, label);
  if (r.missing.length) {
    console.error('--- ' + label + ': ' + r.missing.length + ' target(s) not found in ' + path.relative(target, filePath) + ':');
    for (const m of r.missing) console.error('    ' + m);
    ok = false;
    continue;
  }
  const bk = backup(filePath);
  writeText(filePath, r.text);
  console.log('--- ' + label + ': ' + path.relative(target, filePath));
  for (const a of r.applied) console.log('  ' + a);
  console.log('  backup -> ' + path.relative(target, bk));
}

// The sound is independent of the ad strings, so it applies even if the bundle
// changed shape - a renamed build has a renamed chime-*.mp3, which the glob finds.
if (soundArg) {
  if (!chimePath) {
    console.error('sound: ' + soundStatus() + ' - cannot install custom sound');
  } else if (!fs.existsSync(soundArg)) {
    console.error('sound: file not found: ' + soundArg);
  } else if (!isAudio(soundArg)) {
    console.error('sound: not a recognized audio file (wav/mp3/ogg/flac/m4a/aac): ' + soundArg + ' - leaving the sound alone');
  } else if (fs.readFileSync(chimePath).equals(fs.readFileSync(soundArg))) {
    console.log('sound: already installed, nothing to do.');
  } else {
    // A previous custom audio may already be in place - the .bak guard keeps
    // the ORIGINAL stock file, so swapping one custom sound for another is safe.
    const bak = chimePath + '.bak';
    if (!fs.existsSync(bak)) fs.copyFileSync(chimePath, bak);
    fs.copyFileSync(soundArg, chimePath);
    console.log('sound: installed ' + soundArg + ' -> ' + path.relative(target, chimePath) + ' (stock kept at ' + path.basename(bak) + ')');
  }
}

if (!ok) {
  console.error('\nNothing was changed. The bundle changed shape - run --scan and update the patch strings.');
  process.exit(1);
}

console.log('\nDone. Restart FreeBuff for the changes to load.');
console.log('Re-run after every FreeBuff update. --scan shows what the new build still carries. --revert restores the last backup.');
