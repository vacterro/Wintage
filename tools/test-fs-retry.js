#!/usr/bin/env node
// T-230: a Windows sharing violation is not proof that the app is running.
//
// install-electron.js used to map every EBUSY/EPERM onto "the application is
// running - close it completely (check the tray)". On Windows a file written
// milliseconds earlier is routinely still held by the AV scanner or the search
// indexer, and that handle is gone again within a few hundred ms. Measured on
// this repo's own fixtures, 60 isolated clean applies with no application
// anywhere: 1 failed with that message. Two costs -- the release gate went red
// on correct code about one run in twenty, and a real user was told to close an
// app that was not open.
//
// The fix retries the retriable codes with a short backoff and only claims the
// app is running when the operation is STILL blocked after that window. This
// gate pins the retry's behaviour (it must retry, it must give up, it must NOT
// swallow a non-retriable error) and pins that the transaction path actually
// routes through it.

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.join(__dirname, '..');
const SRC = path.join(ROOT, 'tools', 'install-electron.js');
const src = fs.readFileSync(SRC, 'utf8');

let bad = 0;
const check = (label, got, want) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  console.log((ok ? 'PASS: ' : 'FAIL: ') + label + (ok ? '' : '  got=' + JSON.stringify(got) + ' want=' + JSON.stringify(want)));
  if (!ok) bad++;
};

// ---- slice the retry helper out of the real source ----
const from = src.indexOf('const RETRIABLE_FS_CODES');
const marker = '\nfunction fsRetry(fn) {';
const fnAt = src.indexOf(marker);
if (from < 0 || fnAt < 0) { console.error('FAIL: could not locate the fs-retry helper'); process.exit(1); }
let depth = 0, end = -1;
for (let i = src.indexOf('{', fnAt + marker.length - 1); i < src.length; i++) {
  if (src[i] === '{') depth++;
  else if (src[i] === '}') { depth--; if (depth === 0) { end = i + 1; break; } }
}
if (end < 0) { console.error('FAIL: fsRetry closing brace not found'); process.exit(1); }
const slice = src.slice(from, end);

function load(env) {
  const ctx = { process: { env: env || {} }, Date, Atomics, Int32Array, SharedArrayBuffer, console };
  vm.createContext(ctx);
  vm.runInContext('(function(){\n' + slice + '\nthis.__fsRetry = fsRetry;\nthis.__codes = RETRIABLE_FS_CODES;\nthis.__delays = FS_RETRY_DELAYS_MS;\n}).call(this)', ctx);
  return ctx;
}

// ---- Test 1: the retriable set is exactly the Windows sharing-violation family ----
{
  const ctx = load();
  check('retriable codes are EBUSY/EPERM/EACCES', [...ctx.__codes].sort(), ['EACCES', 'EBUSY', 'EPERM']);
  check('the backoff is bounded and short', ctx.__delays.reduce((a, b) => a + b, 0) <= 1000, true);
  check('the backoff has at least 3 attempts', ctx.__delays.length >= 3, true);
}

// ---- Test 2: a transient failure SUCCEEDS after a retry ----
// This is the whole point: the flake disappears without the caller changing.
{
  const ctx = load();
  let calls = 0;
  const val = ctx.__fsRetry(() => {
    calls++;
    if (calls < 3) { const e = new Error('busy'); e.code = 'EBUSY'; throw e; }
    return 'ok';
  });
  check('a transient EBUSY is retried to success', val, 'ok');
  check('it took exactly the failing attempts plus one', calls, 3);
}

// ---- Test 3: a PERSISTENT failure still fails, with the original error ----
// A genuinely running app holds its archive for as long as it runs, so it must
// still reach the caller's "the application is running" branch with the code intact.
{
  const ctx = load();
  let calls = 0;
  let caught = null;
  try {
    ctx.__fsRetry(() => { calls++; const e = new Error('locked'); e.code = 'EBUSY'; throw e; });
  } catch (e) { caught = e; }
  check('a persistent EBUSY still throws', caught !== null, true);
  check('the thrown error keeps its code so the caller can classify it', caught && caught.code, 'EBUSY');
  check('it gave up after the bounded attempt count', calls, load().__delays.length + 1);
}

// ---- Test 4: a NON-retriable error is rethrown immediately, never retried ----
// Retrying ENOENT would turn a missing file into a slow missing file.
{
  const ctx = load();
  let calls = 0;
  let caught = null;
  try {
    ctx.__fsRetry(() => { calls++; const e = new Error('nope'); e.code = 'ENOENT'; throw e; });
  } catch (e) { caught = e; }
  check('ENOENT is not retried', calls, 1);
  check('ENOENT is rethrown unchanged', caught && caught.code, 'ENOENT');
}

// ---- Test 5: the test seam disables the retry (so a gate can measure the flake) ----
{
  const ctx = load({ WINTAGE_TEST_NO_FS_RETRY: '1' });
  let calls = 0;
  try { ctx.__fsRetry(() => { calls++; const e = new Error('busy'); e.code = 'EBUSY'; throw e; }); } catch (e) { }
  check('WINTAGE_TEST_NO_FS_RETRY makes it a single pass-through call', calls, 1);
}

// ---- Test 6: the transaction path actually USES it ----
// A helper nothing calls fixes nothing. Every mutating rename/copy in the
// apply and revert transactions must route through fsRetry.
{
  const mustRetry = [
    ['in-place backup copy', /fsRetry\(\(\) => fs\.copyFileSync\(asar, asarBak\)\)/],
    ['retire the old relocation', /fsRetry\(\(\) => fs\.renameSync\(appDir, oldReloc\)\)/],
    ['move staging into place', /fsRetry\(\(\) => fs\.renameSync\(staging, appDir\)\)/],
    ['move the archive', /fsRetry\(\(\) => fs\.renameSync\(asar, movedAsar\)\)/],
    ['move the unpacked sibling', /fsRetry\(\(\) => fs\.renameSync\(unpacked, movedUnpacked\)\)/],
    ['in-place revert restore', /fsRetry\(\(\) => fs\.copyFileSync\(bak, asar\)\)/],
    ['relocation revert restore', /fsRetry\(\(\) => fs\.renameSync\(movedAsar, asar\)\)/]
  ];
  for (const [what, re] of mustRetry) {
    check('transaction routes through fsRetry: ' + what, re.test(src), true);
  }
  // And the rollback steps too: a rollback that loses to an indexer is worse
  // than the original failure, because it leaves the app half-moved.
  check('rollback steps retry as well', /undo\.push\(\(\) => fsRetry\(/.test(src), true);
}

// ---- Test 7: the message is still reachable, and still says the right thing ----
{
  check('the app-is-running message survives for the persistent case',
    /the application is running - close it completely/.test(src), true);
  check('it is still gated on the retriable codes',
    /if \(e\.code === 'EBUSY' \|\| e\.code === 'EPERM'\)/.test(src), true);
}

console.log(bad ? '\n' + bad + ' failure(s)' : '\nfs-retry test PASS');
process.exit(bad ? 1 : 0);
