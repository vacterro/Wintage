#!/usr/bin/env node
// Reads an Electron application's FUSES straight out of its executable.
//
// Why this exists: the shim works by moving app.asar and letting Electron load
// `resources/app` instead. Two fuses make that impossible, and an app with them set
// does not fail loudly at install time — it fails at LAUNCH, after the archive has
// already moved, which is the worst possible moment to discover it. Claude's desktop
// app has both, and that is exactly how it was found: the app stopped starting.
//
//   OnlyLoadAppFromAsar                    - Electron loads resources/app.asar and
//                                            NOTHING else. `resources/app` is never
//                                            consulted, so the shim can never run.
//   EnableEmbeddedAsarIntegrityValidation  - the archive's header hash is checked
//                                            against a value baked into the binary,
//                                            so repacking the asar instead is not a
//                                            way around the first fuse either.
//
// Both are deliberate security controls. An app that sets them has decided its code
// is not to be modified, and the correct response is to say so and stop — not to
// find a cleverer way in.
//
// Format: a fixed sentinel string, then one byte of wire version, one byte of fuse
// count, then one ASCII byte per fuse: '0' disabled, '1' enabled, 'r' removed.
//
// Usage: node tools/electron-fuses.js <path-to-exe>

const fs = require('fs');

const SENTINEL = Buffer.from('dL7pKGdnNz796PbbjQWNKmHXBZaB9tsX');

// Order is the wire order for fuse schema version 1.
const NAMES = [
  'RunAsNode',
  'EnableCookieEncryption',
  'EnableNodeOptionsEnvironmentVariable',
  'EnableNodeCliInspectArguments',
  'EnableEmbeddedAsarIntegrityValidation',
  'OnlyLoadAppFromAsar',
  'LoadBrowserProcessSpecificV8Snapshot',
  'GrantFileProtocolExtraPrivileges'
];

const STATE = { 0x30: 'disabled', 0x31: 'enabled', 0x72: 'removed' };

function readFuses(exe) {
  let data;
  try { data = fs.readFileSync(exe); } catch (e) { return { error: 'cannot read ' + exe + ': ' + e.message }; }
  const i = data.indexOf(SENTINEL);
  if (i < 0) return { error: 'no fuse wire in ' + exe };
  const at = i + SENTINEL.length;
  const version = data[at];
  const count = data[at + 1];
  if (version !== 1 || !count || count > NAMES.length + 8) {
    // Unknown schema: report it rather than mapping bytes onto names that may have
    // moved. A wrong ENABLED/disabled reading here would either block a themeable
    // app or wave through one that is about to break.
    return { version, count, unknown: true };
  }
  const fuses = {};
  for (let k = 0; k < count && k < NAMES.length; k++) {
    fuses[NAMES[k]] = STATE[data[at + 2 + k]] || ('byte ' + data[at + 2 + k]);
  }
  return { version, count, fuses };
}

// The two that decide whether the shim can work at all.
function blockers(exe) {
  const r = readFuses(exe);
  if (r.error || r.unknown) return { reasons: [], detail: r };
  const reasons = [];
  if (r.fuses.OnlyLoadAppFromAsar === 'enabled') {
    reasons.push('OnlyLoadAppFromAsar is enabled - Electron will load resources/app.asar and nothing else, so the shim in resources/app can never run');
  }
  if (r.fuses.EnableEmbeddedAsarIntegrityValidation === 'enabled') {
    reasons.push('EnableEmbeddedAsarIntegrityValidation is enabled - the archive is hash-checked against the binary, so repacking it is not an alternative');
  }
  return { reasons, detail: r };
}

module.exports = { readFuses, blockers };

if (require.main === module) {
  const exe = process.argv[2];
  if (!exe) { console.error('usage: node tools/electron-fuses.js <path-to-exe>'); process.exit(1); }
  const r = readFuses(exe);
  if (r.error) { console.error(r.error); process.exit(1); }
  if (r.unknown) { console.log('unknown fuse schema: version ' + r.version + ', ' + r.count + ' fuses'); process.exit(0); }
  for (const [k, v] of Object.entries(r.fuses)) console.log((v === 'enabled' ? '  ON  ' : '  off ') + k);
  const b = blockers(exe);
  console.log(b.reasons.length ? '\nNOT themeable by the shim:\n  ' + b.reasons.join('\n  ') : '\nThemeable by the shim.');
}
