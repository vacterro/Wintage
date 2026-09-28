// saihunt S4 probe: does a FAILED prune in the exact patch-freebuff-ads.js:170-172
// shape stay invisible? (read-only toward the project: writes only in scratch)
const fs = require('fs'), path = require('path'), os = require('os');
const root = path.join(__dirname, 's4-tmp');
fs.rmSync(root, {recursive:true, force:true});
const lockedDir = path.join(root, '_orig-baseline-2026-09-16T00-00-00-000Z-1234');
fs.mkdirSync(lockedDir, {recursive:true});
fs.writeFileSync(path.join(lockedDir, 'owned.bin'), 'baseline payload');

let threw = null, printed = [];
const realLog = console.log;
console.log = (...a) => { printed.push(a.join(' ')); realLog('[captured console.log]', ...a); };
// exact shape of pruneBaselines() body (patch-freebuff-ads.js:170-172)
try { fs.rmSync(lockedDir, { recursive: true, force: true }); console.log('pruned stale baseline ' + path.basename(lockedDir)); }
catch (e) { }
console.log = realLog;
try { fs.rmSync(lockedDir, { recursive: true, force: true }); } catch (e) { threw = e.code || e.message; }
realLog('rmSync threw            :', threw || 'no (lock not held)');
realLog('diagnostic from the catch:', printed.length ? printed.join(' | ') : '(none)');
realLog('dir still on disk       :', fs.existsSync(lockedDir));
fs.rmSync(root, {recursive:true, force:true});
