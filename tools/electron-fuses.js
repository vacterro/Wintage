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
// PERF-008: bounded chunk scanner. The previous implementation loaded the entire
// executable into a Buffer just to locate a 32-byte sentinel. A 200 MiB Electron
// binary therefore cost 200 MiB of peak memory on every install-listing probe
// (which is the read path the GUI hits once per target per refresh). Scanning in
// fixed-size chunks keeps the high-water mark near CHUNK_SIZE, and the trailing
// overlap across chunk boundaries guarantees a sentinel split between two reads
// is still found.
const CHUNK_SIZE = 1 << 20;   // 1 MiB
const OVERLAP = SENTINEL.length - 1;

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

// PERF-008: scan an open fd for the fuse sentinel, returning the read so far
// (capped at SENTINEL.length + 2 + MAX_KNOWN_COUNT bytes) once it is found.
// The returned buffer is a slice of the cumulative read window so callers can
// validate the wire bytes without ever materialising the rest of the executable.
function findFuseWireChunked(fd, fileSize) {
  const readCap = SENTINEL.length + 2 + MAX_KNOWN_COUNT;
  let carry = Buffer.alloc(0);
  let offset = 0;
  const buf = Buffer.alloc(CHUNK_SIZE);
  while (offset < fileSize) {
    const bytesRead = fs.readSync(fd, buf, 0, Math.min(CHUNK_SIZE, fileSize - offset), offset);
    if (bytesRead <= 0) break;
    // Combine the trailing overlap from the previous chunk with the new bytes.
    const window = carry.length === 0 ? buf.subarray(0, bytesRead) : Buffer.concat([carry, buf.subarray(0, bytesRead)], carry.length + bytesRead);
    const hit = window.indexOf(SENTINEL);
    if (hit >= 0) {
      // Found the sentinel. The full read window already covers the wire; cap
      // it at readCap so we never return more than the maximum bytes any
      // valid schema can occupy.
      return window.subarray(hit, Math.min(window.length, hit + readCap));
    }
    // Keep only the last OVERLAP bytes for cross-chunk sentinel matching.
    if (bytesRead >= OVERLAP) {
      carry = buf.subarray(bytesRead - OVERLAP, bytesRead);
    } else {
      carry = Buffer.concat([carry, buf.subarray(0, bytesRead)], carry.length + bytesRead).subarray(Math.max(0, carry.length + bytesRead - OVERLAP));
    }
    offset += bytesRead;
  }
  return null;
}

function readFuses(exe) {
  let fd;
  try { fd = fs.openSync(exe, 'r'); }
  catch (e) { return { error: 'cannot read ' + exe + ': ' + e.message }; }
  try {
    const stat = fs.fstatSync(fd);
    const wire = findFuseWireChunked(fd, stat.size);
    if (!wire) return { error: 'no fuse wire in ' + exe };
    const at = SENTINEL.length;
    const version = wire[at];
    const count = wire[at + 1];
    // Schema validation: version 1, count sane (at least the 6 core fuses through OnlyLoadAppFromAsar), AND every byte within the file.
    if (version !== 1 || !count || count < 6 || count > MAX_KNOWN_COUNT || (at + 2 + count) > wire.length) {
      // Unknown or malformed schema: report it rather than mapping bytes onto names
      // that may have moved or reading past the end. A wrong ENABLED/disabled reading
      // here would either block a themeable app or wave through one that is about to
      // break — both are failures of the same kind.
      return { version, count, unknown: true, malformed: !(version === 1 && count > 0 && (at + 2 + count) <= wire.length) };
    }
    const fuses = {};
    for (let k = 0; k < count; k++) {
      const raw = wire[at + 2 + k];
      fuses[NAMES[k] || ('Fuse' + k)] = STATE[raw] || ('byte 0x' + raw.toString(16));
    }
    return { version, count, fuses };
  } finally { try { fs.closeSync(fd); } catch (e) { } }
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
// PERF-008: scan the executable in fixed-size chunks to locate the wire, then
// patch only the two known fuse bytes through a file handle. The full
// executable is NEVER materialised in memory; the original-bytes backup is
// created by streaming the file to disk, not by retaining a second Buffer.
function defuse(exe) {
  let fd;
  try { fd = fs.openSync(exe, 'r'); }
  catch (e) { return { error: e.message }; }
  let wire, wireOffset;
  try {
    const stat = fs.fstatSync(fd);
    wireOffset = -1;
    let carry = Buffer.alloc(0);
    let offset = 0;
    const buf = Buffer.alloc(CHUNK_SIZE);
    while (offset < stat.size) {
      const bytesRead = fs.readSync(fd, buf, 0, Math.min(CHUNK_SIZE, stat.size - offset), offset);
      if (bytesRead <= 0) break;
      const window = carry.length === 0 ? buf.subarray(0, bytesRead) : Buffer.concat([carry, buf.subarray(0, bytesRead)], carry.length + bytesRead);
      const hit = window.indexOf(SENTINEL);
      if (hit >= 0) { wireOffset = offset - carry.length + hit; wire = window.subarray(hit); break; }
      if (bytesRead >= OVERLAP) carry = buf.subarray(bytesRead - OVERLAP, bytesRead);
      else carry = Buffer.concat([carry, buf.subarray(0, bytesRead)], carry.length + bytesRead).subarray(Math.max(0, carry.length + bytesRead - OVERLAP));
      offset += bytesRead;
    }
  } finally { try { fs.closeSync(fd); } catch (e) { } }
  if (!wire) return { error: 'no fuse wire' };
  const at = SENTINEL.length;
  const version = wire[at];
  const count = wire[at + 1];
  if (version !== 1 || !count || count < 6 || count > MAX_KNOWN_COUNT || (at + 2 + count) > wire.length) {
    return { error: 'unknown/malformed fuse schema (version ' + version + ', count ' + count + ') - refusing to modify an unverifiable executable' };
  }
  let changed = false;
  if (wire[at + 6] === 0x31) { wire[at + 6] = 0x30; changed = true; } // EnableEmbeddedAsarIntegrityValidation
  if (wire[at + 7] === 0x31) { wire[at + 7] = 0x30; changed = true; } // OnlyLoadAppFromAsar
  if (!changed) return { success: true, changed: false, backup: null };
  const backup = exe + '.wintage-fuse.bak';
  // CORE-008: the backup is the INSTALL-EPOCH authority. If one already
  // exists (a repaint re-defusing a drifted exe), it must never be replaced
  // by the already-drifted bytes - Revert needs the original executable.
  // PERF-008: stream-copy the file rather than loading it into a Buffer, so
  // peak memory stays bounded regardless of exe size.
  if (!fs.existsSync(backup)) {
    try {
      fs.copyFileSync(exe, backup);
    } catch (e) { return { error: 'could not back up ' + exe + ' to ' + backup + ': ' + e.message }; }
  }
  // Patch the two fuse bytes in place through a writable fd. CORE-007/W2
  // guard rollback: the original bytes are now safely on disk as the backup.
  let wfd;
  try { wfd = fs.openSync(exe, 'r+'); }
  catch (e) { return { error: 'could not open ' + exe + ' for writing: ' + e.message + ' (is the app running?)' }; }
  try {
    // Only the two changed fuse bytes are written, at their validated offsets
    // (fuse indices 6 and 7 after the sentinel + version + count).
    fs.writeSync(wfd, wire, SENTINEL.length + 6, 1, wireOffset + SENTINEL.length + 6);
    fs.writeSync(wfd, wire, SENTINEL.length + 7, 1, wireOffset + SENTINEL.length + 7);
  } catch (e) {
    return { error: 'could not write fuse bytes into ' + exe + ': ' + e.message + ' (is the app running?)' };
  } finally { try { fs.closeSync(wfd); } catch (e) { } }
  return { success: true, changed: true, backup };
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