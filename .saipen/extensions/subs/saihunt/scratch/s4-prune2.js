// saihunt S4 probe (v2): the harness owns setup; this only exercises the shape.
const fs = require('fs'), path = require('path');
const lockedDir = path.join(__dirname, 's4-tmp2', '_orig-baseline-2026-09-16T00-00-00-000Z-1234');
if (!fs.existsSync(lockedDir)) { console.log('SETUP MISSING: harness did not create the locked tree'); process.exit(2); }
let printed = [];
const realLog = console.log;
console.log = (...a) => { printed.push(a.join(' ')); };
// ---- exact production shape: desktop/patch-freebuff-ads.js:170-172 ----
for (const old of [{ dir: lockedDir }]) {
  try { fs.rmSync(old.dir, { recursive: true, force: true }); console.log('pruned stale baseline ' + path.basename(old.dir)); }
  catch (e) { }
}
// ----------------------------------------------------------------------
console.log = realLog;
let code = null;
try { fs.rmSync(lockedDir, { recursive: true, force: true }); } catch (e) { code = e.code || e.message; }
realLog('prune attempted          : yes (production shape, real fs.rmSync)');
realLog('underlying failure        :', code || 'none (no lock)');
realLog('diagnostic emitted        :', printed.length ? printed.join(' | ') : '(NONE - failure silent)');
realLog('stale baseline remains    :', fs.existsSync(lockedDir));
