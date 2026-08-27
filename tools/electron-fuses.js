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
// Fuse policy (CORE-007): a SUPPORTED, byte-verified fuse schema (version 1 with
// the known count) that has these two fuses enabled is repaired by backing the
// original executable up byte-exactly (once, at the install epoch) and disabling
// the fuse bytes, with revert restoring the backup. An app whose fuse wire cannot
// be READ OR VERIFIED — unknown schema version, malformed count, missing sentinel,
// or more than one candidate executable — is UNVERIFIABLE, and a mutating install
// must fail closed rather than modify an application whose launch constraints are
// unknown. "Unable to prove fuse safety" is never treated as "safe".
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
  'GrantFileProtocolExtraPrivileges',
  'WasmTrapHandlers'
];

const STATE = { 0x30: 'disabled', 0x31: 'enabled', 0x72: 'removed' };
const MAX_KNOWN_COUNT = NAMES.length + 8; // tolerated slack, still validated below

// Tri-state verdicts (CORE-007):
//   VERIFIED_SAFE  - read and schema-valid: the two blocking fuses are known off.
//   BLOCKED        - read and schema-valid: a blocking fuse is enabled.
//   UNVERIFIABLE   - the wire cannot be read, the schema is unknown/malformed, or
//                    the caller could not resolve exactly one executable.
const VERIFIED_SAFE = 'VERIFIED_SAFE';
const BLOCKED = 'BLOCKED';
const UNVERIFIABLE = 'UNVERIFIABLE';

function readFuses(exe) {
  let data;
  try { data = fs.readFileSync(exe); } catch (e) { return { error: 'cannot read ' + exe + ': ' + e.message }; }
  const i = data.indexOf(SENTINEL);
  if (i < 0) return { error: 'no fuse wire in ' + exe };
  const at = i + SENTINEL.length;
  const version = data[at];
  const count = data[at + 1];
  // Schema validation: version 1, count sane (at least the 6 core fuses through OnlyLoadAppFromAsar), AND every byte within the file.
  if (version !== 1 || !count || count < 6 || count > MAX_KNOWN_COUNT || (at + 2 + count) > data.length) {
    // Unknown or malformed schema: report it rather than mapping bytes onto names
    // that may have moved or reading past the end. A wrong ENABLED/disabled reading
    // here would either block a themeable app or wave through one that is about to
    // break — both are failures of the same kind.
    return { version, count, unknown: true, malformed: !(version === 1 && count > 0 && (at + 2 + count) <= data.length) };
  }
  const fuses = {};
  for (let k = 0; k < count; k++) {
    const raw = data[at + 2 + k];
    fuses[NAMES[k] || ('Fuse' + k)] = STATE[raw] || ('byte 0x' + raw.toString(16));
  }
  return { version, count, fuses };
}

// Blocking verdict with full detail. `unknown`/`error` are NEVER flattened into
// "no reasons" (CORE-007): callers must treat them as UNVERIFIABLE.
function fuseVerdict(exe) {
  const r = readFuses(exe);
  if (r.error || r.unknown) {
    return { status: UNVERIFIABLE, reasons: [], detail: r, reason: (r.error || ('unknown fuse schema: version ' + r.version + ', count ' + r.count)) };
  }
  const reasons = [];
  if (r.fuses.OnlyLoadAppFromAsar === 'enabled') {
    reasons.push('OnlyLoadAppFromAsar is enabled - Electron will load resources/app.asar and nothing else, so the shim in resources/app can never run');
  }
  if (r.fuses.EnableEmbeddedAsarIntegrityValidation === 'enabled') {
    reasons.push('EnableEmbeddedAsarIntegrityValidation is enabled - the archive is hash-checked against the binary, so repacking it is not an alternative');
  }
  return { status: reasons.length ? BLOCKED : VERIFIED_SAFE, reasons, detail: r };
}

// Backward-compatible shape for existing callers: `reasons.length` still
// means "blocked", but callers that need fail-closed behaviour must use
// fuseVerdict/defuseState instead.
function blockers(exe) {
  const v = fuseVerdict(exe);
  return { reasons: v.status === BLOCKED ? v.reasons : [], detail: v.detail || v.reason };
}

// defuse() itself validates the known schema/version/count and target offsets
// BEFORE any write, so callers cannot bypass the guard (CORE-007).
function defuse(exe) {
  let data;
  try { data = fs.readFileSync(exe); } catch (e) { return { error: e.message }; }
  const original = Buffer.from(data);
  const i = data.indexOf(SENTINEL);
  if (i < 0) return { error: 'no fuse wire' };
  const at = i + SENTINEL.length;
  const version = data[at];
  const count = data[at + 1];
  if (version !== 1 || !count || count < 6 || count > MAX_KNOWN_COUNT || (at + 2 + count) > data.length) {
    return { error: 'unknown/malformed fuse schema (version ' + version + ', count ' + count + ') - refusing to modify an unverifiable executable' };
  }
  let changed = false;
  if (data[at + 6] === 0x31) { data[at + 6] = 0x30; changed = true; } // EnableEmbeddedAsarIntegrityValidation
  if (data[at + 7] === 0x31) { data[at + 7] = 0x30; changed = true; } // OnlyLoadAppFromAsar
  if (changed) {
    const backup = exe + '.wintage-fuse.bak';
    // CORE-008: the backup is the INSTALL-EPOCH authority. If one already
    // exists (a repaint re-defusing a drifted exe), it must never be replaced
    // by the already-drifted bytes - Revert needs the original executable.
    if (!fs.existsSync(backup)) {
      try { fs.writeFileSync(backup, original); }
      catch (e) { return { error: 'could not back up ' + exe + ' to ' + backup + ': ' + e.message }; }
    }
    try { fs.writeFileSync(exe, data); }
    catch (e) { return { error: 'could not write ' + exe + ': ' + e.message + ' (is the app running?)' }; }
  }
  return { success: true, changed, backup: changed ? exe + '.wintage-fuse.bak' : null };
}

module.exports = { readFuses, blockers, defuse, fuseVerdict, VERIFIED_SAFE, BLOCKED, UNVERIFIABLE };

if (require.main === module) {
  const exe = process.argv[2];
  if (!exe) { console.error('usage: node tools/electron-fuses.js <path-to-exe>'); process.exit(1); }
  const v = fuseVerdict(exe);
  if (v.status === UNVERIFIABLE) { console.error(v.reason); process.exit(1); }
  for (const [k, val] of Object.entries(v.detail.fuses)) console.log((val === 'enabled' ? '  ON  ' : '  off ') + k);
  console.log(v.status === BLOCKED ? '\nNOT themeable by the shim:\n  ' + v.reasons.join('\n  ') : '\nThemeable by the shim.');
}