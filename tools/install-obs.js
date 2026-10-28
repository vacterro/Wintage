#!/usr/bin/env node
'use strict';

// Installs (or removes) the Wintage OBS theme.
//
// Ownership model (CORE-001/CORE-010): OBS artifacts are divided into three
// classes, and every one gets persistent, verifiable recovery recorded BEFORE
// the first mutation:
//   - user.ini        Wintage owns EXACTLY ONE key: [Appearance] Theme (T-189).
//                     The pre-Wintage existence/value of that key is snapshotted
//                     once (JSON recovery); a user.ini that did not exist is
//                     marked .wintage-created. Revert merges only the owned key
//                     back into the CURRENT user.ini (unrelated post-Apply user
//                     edits survive) or removes a Wintage-created file ONLY when
//                     nothing but that one key is left in it.
//   - themes/Wintage.ovt  created-or-replaced provenance plus exact replaced
//                     bytes (byte-for-byte restore). First generation is never
//                     overwritten by a repaint.
//   - .wintage-obs-palette  the Wintage palette marker; created/removed with us.
//
// The parent (targets.ps1 Invoke-Obs) owns the manifest transition; this helper
// must therefore NEVER consume its persistent recovery while a manifest commit
// could still fail. --revert therefore restores the target but keeps every
// recovery artifact; the parent consumes them (Remove-ObsRecovery, exported
// below) only AFTER the manifest transition succeeds. A standalone --revert
// with no manifest coordination (direct CLI use) consumes them normally.
//
// Revert preflights the COMPLETE required recovery set before touching anything
// and fails NONZERO with zero mutation when an installed target lacks required
// recovery - lost recovery is an unverifiable state, never permission to
// perform a destructive revert by guessing.
//
// Usage:
//   node tools/install-obs.js --config DIR (--theme FILE --palette SLUG | --revert) [--dry-run]
//   node tools/install-obs.js --config DIR --revert --keep-recovery   (parent-coordinated revert)
//   node tools/install-obs.js --config DIR --finalize-revert          (consume recovery after commit)
//   node tools/install-obs.js --config DIR --finalize-revert --manifest-committed (commit proven)

const fs = require('fs');
const path = require('path');
const { writeAtomic } = require('./write-atomic');

function arg(name) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : null;
}

const configDir = arg('--config');
const sourceTheme = arg('--theme');
const palette = arg('--palette');
const revert = process.argv.includes('--revert');
const keepRecovery = process.argv.includes('--keep-recovery');
const finalizeRevert = process.argv.includes('--finalize-revert');
// W2-003: the caller's proof that the MANIFEST transition committed. Without it
// the marker must be absent, because a marker still present means Revert did not
// finish and its recovery may still be needed.
const manifestCommitted = process.argv.includes('--manifest-committed');
const dryRun = process.argv.includes('--dry-run');

if (!configDir || (!revert && !finalizeRevert && (!sourceTheme || !palette))) {
  console.error('Usage: install-obs.js --config DIR (--theme FILE --palette SLUG | --revert [--keep-recovery] | --finalize-revert [--manifest-committed]) [--dry-run]');
  process.exit(2);
}

const THEME_ID = 'com.wintage.OBS';
const userIni = path.join(configDir, 'user.ini');
const themesDir = path.join(configDir, 'themes');
const themeFile = path.join(themesDir, 'Wintage.ovt');
const markerFile = path.join(configDir, '.wintage-obs-palette');

// Wintage owns exactly ONE key in user.ini: [Appearance] Theme (T-189).
const THEME_KEY = 'Theme';
const THEME_SECTION = 'Appearance';

// ─── Persistent recovery (CORE-001) ─────────────────────────────────────────
// Three independent artifacts, written atomically BEFORE the first mutation:
//   user.ini.wintage.bak   JSON { existed, value } of the owned Theme key.
//   user.ini.wintage-created   empty marker = user.ini did not exist pre-Wintage.
//   Wintage.ovt.wintage.bak    JSON { existed, value? } - byte-exact replaced
//                          theme if a same-named user theme pre-existed.
//   Wintage.ovt.wintage-created empty marker = the .ovt did not exist.
const themeKeyBackup = `${userIni}.wintage.bak`;
const userIniCreated = `${userIni}.wintage-created`;
const ovtBackup = `${themeFile}.wintage.bak`;
const ovtCreated = `${themeFile}.wintage-created`;

function exists(p) { return fs.existsSync(p); }
function remove(p) { if (exists(p)) fs.unlinkSync(p); }

// CORE-002: a file that parses is not a recovery record. `{}`, `[]`, a bare
// number, `{"existed":"yes"}` and `{"existed":false,"junk":1}` all used to
// arrive here as truthy objects: the preflight accepted them, Revert then saw
// "no usable bytes to restore" and DELETED the live theme, and the recovery was
// consumed as a success. The value contract is the schema, not a detail --
// `existed` must be a boolean, a true record must carry a string value, and a
// false record must not carry one.
function ReadRecoveryJson(file) {
  if (!exists(file)) return null;
  let parsed;
  try { parsed = JSON.parse(fs.readFileSync(file, 'utf8')); } catch (e) { return null; }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return null;
  if (typeof parsed.existed !== 'boolean') return null;
  if (parsed.existed) {
    if (typeof parsed.value !== 'string') return null;
    return { existed: true, value: parsed.value };
  }
  if (parsed.value !== null && parsed.value !== undefined) return null;
  return { existed: false, value: null };
}

// parseIni -> { sections: {name: {key: value}}, order preserved via arrays }
function parseIni(source) {
  const bom = source.startsWith('\uFEFF') ? '\uFEFF' : '';
  if (bom) source = source.slice(1);
  // W2-005: a repeated key is a real document shape, not a corruption, so the
  // effective value is defined once here -- the LAST occurrence in document
  // order -- and every occurrence is kept beside it so Revert can put the
  // original duplicates back instead of collapsing them.
  const out = { bom, sections: {}, sectionOrder: [], keys: {}, occurrences: [] };
  let section = null;
  for (const line of source.split(/\r?\n/)) {
    const sm = /^\s*\[([^\]]+)\]\s*$/.exec(line);
    if (sm) {
      section = sm[1];
      if (!(section in out.sections)) { out.sections[section] = {}; out.sectionOrder.push(section); }
      continue;
    }
    if (section) {
      const km = /^\s*([^=]+?)\s*=(.*)$/.exec(line);
      if (km) { out.sections[section][km[1].trim()] = km[2]; out.keys[section + '.' + km[1].trim()] = km[2]; out.occurrences.push({ section, key: km[1].trim(), value: km[2] }); }
    }
  }
  return out;
}

function removeIniKey(source, section, key) {
  const bom = source.startsWith('\uFEFF') ? '\uFEFF' : '';
  if (bom) source = source.slice(1);
  const eol = source.includes('\r\n') ? '\r\n' : '\n';
  const finalEol = source.endsWith('\n');
  const lines = source.length ? source.split(/\r?\n/) : [];
  if (finalEol) lines.pop();
  const sectionPattern = new RegExp(`^\\s*\\[${section.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\]\\s*$`, 'i');
  const keyPattern = new RegExp(`^\\s*${key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*=`, 'i');
  const start = lines.findIndex((line) => sectionPattern.test(line));
  if (start >= 0) {
    let end = start + 1;
    while (end < lines.length && !isSectionHeader(lines[end])) end += 1;
    const idx = lines.slice(start + 1, end).findIndex((line) => keyPattern.test(line));
    if (idx >= 0) lines.splice(start + 1 + idx, 1);
  }
  return bom + lines.join(eol) + (finalEol || !lines.length ? eol : '');
}
function setIniValue(source, section, key, value) {
  const bom = source.startsWith('\uFEFF') ? '\uFEFF' : '';
  if (bom) source = source.slice(1);
  const eol = source.includes('\r\n') ? '\r\n' : '\n';
  const finalEol = source.endsWith('\n');
  const lines = source.length ? source.split(/\r?\n/) : [];
  if (finalEol) lines.pop();

  const sectionPattern = new RegExp(`^\\s*\\[${section.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\]\\s*$`, 'i');
  const keyPattern = new RegExp(`^\\s*${key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*=`, 'i');
  // W2-005: every occurrence of the owned key is written, so a document that
  // arrived with repeated keys is left with one unambiguous effective value.
  // The OLD first-match-only write left later duplicate lines live, which is
  // exactly the ambiguity this clause exists to remove.
  const targets = [];
  let current = null;
  for (let i = 0; i < lines.length; i += 1) {
    const trimmed = lines[i].trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) { current = trimmed.slice(1, -1); continue; }
    if (current !== null && current.toLowerCase() === section.toLowerCase() && keyPattern.test(lines[i])) targets.push(i);
  }
  if (targets.length) {
    for (const i of targets) lines[i] = `${key}=${value}`;
  } else {
    const start = lines.findIndex((line) => sectionPattern.test(line));
    if (start < 0) {
      if (lines.length && lines[lines.length - 1] !== '') lines.push('');
      lines.push(`[${section}]`, `${key}=${value}`);
    } else {
      let end = start + 1;
      while (end < lines.length && !isSectionHeader(lines[end])) end += 1;
      lines.splice(end, 0, `${key}=${value}`);
    }
  }
  return bom + lines.join(eol) + (finalEol || !lines.length ? eol : '');
}

// W2-002: writers match section/key names case-INSENSITIVELY (see the two
// patterns below), so readers must too. They did not, and the asymmetry is
// silent: OBS writes `[appearance] theme=System`, the snapshot recorded
// `existed:false`, and Revert then DELETED the user's real selection instead of
// restoring it. Lookup is normalised here; the file's own spelling is never
// rewritten, because only lookup semantics were ever ambiguous.
// An INI section header is a line whose trimmed form is [name]; the writers
// above used to decide this with a regex whose escaping survived one rewrite
// and not the next, so the decision is now plain string work.
function isSectionHeader(line) {
  const t = line.trim();
  return t.startsWith('[') && t.endsWith(']');
}
function iniLookup(ini, section, key) {
  const sections = (ini && ini.sections) || {};
  const sectionName = Object.keys(sections).find((s) => s.toLowerCase() === section.toLowerCase());
  if (sectionName === undefined) return undefined;
  // W2-005: the reader resolves a repeated key the same way the writers do --
  // the last occurrence wins -- so lookup and mutation can never disagree.
  const occ = (ini.occurrences || []).filter((o) => o.section.toLowerCase() === sectionName.toLowerCase() && o.key.toLowerCase() === key.toLowerCase());
  if (occ.length) return occ[occ.length - 1].value;
  const body = sections[sectionName] || {};
  const keyName = Object.keys(body).find((k) => k.toLowerCase() === key.toLowerCase());
  return keyName === undefined ? undefined : body[keyName];
}

// W2-005: put back the exact occurrences Apply recorded, duplicates included,
// keeping each line own key spelling and writing only the value. Returns null
// when the live document no longer carries the same number of owned
// occurrences: the key was edited after Apply, and a blind restore would
// overwrite the user own lines instead of recovering them.
function restoreIniOccurrences(source, occurrences) {
  const bom = source.startsWith('\uFEFF') ? '\uFEFF' : '';
  const body = bom ? source.slice(1) : source;
  const eol = body.includes('\r\n') ? '\r\n' : '\n';
  const finalEol = body.endsWith('\n');
  const lines = body.length ? body.split(/\r?\n/) : [];
  if (finalEol) lines.pop();
  const seen = [];
  let current = null;
  for (let i = 0; i < lines.length; i += 1) {
    const trimmed = lines[i].trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) { current = trimmed.slice(1, -1); continue; }
    if (current === null) continue;
    const eq = lines[i].indexOf('=');
    const left = eq < 0 ? '' : lines[i].slice(0, eq).trim();
    if (occurrences.some((o) => o.section.toLowerCase() === current.toLowerCase() && o.key.toLowerCase() === left.toLowerCase())) seen.push(i);
  }
  if (seen.length !== occurrences.length) return null;
  for (let n = 0; n < seen.length; n += 1) {
    const eq = lines[seen[n]].indexOf('=');
    lines[seen[n]] = lines[seen[n]].slice(0, eq + 1) + occurrences[n].value;
  }
  return bom + lines.join(eol) + (finalEol || !lines.length ? eol : '');
}

// Read the Theme-key snapshot. New format is JSON {existed, value}; a legacy
// whole-file .bak is parsed as INI and its Theme key extracted (T-189).
//
// W2-002: the format is chosen by an UNAMBIGUOUS rule and a JSON payload is
// then validated strictly. Previously malformed JSON, or JSON of the wrong
// shape, fell through to the INI branch and came back as a perfectly
// well-formed-looking `{existed:false,value:null}` -- which the fail-closed
// preflight accepted and Revert then used to delete a live Theme key. A
// recovery file we cannot read must be UNREADABLE, not quietly reinterpreted.
function readThemeSnapshot() {
  if (!exists(themeKeyBackup)) return null;
  const raw = fs.readFileSync(themeKeyBackup, 'utf8').replace(/^\uFEFF/, '').trim();
  // JSON is selected by an UNAMBIGUOUS rule: anything opening with `{` is JSON,
  // and a payload opening with `[` counts as legacy INI only when it actually
  // begins with an INI section header -- `[]` is a JSON array, not an empty
  // section, and the old `{`-only test let it sneak into the INI branch.
  const jsonPayload = raw.startsWith('{')
    || (raw.startsWith('[') && !/^\s*\[[^\]\r\n]+\]\s*($|\r?\n)/.test(raw));
  if (jsonPayload) {
    let parsed;
    try { parsed = JSON.parse(raw); } catch (e) { return null; }
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return null;
    if (typeof parsed.existed !== 'boolean') return null;
    // The value contract is part of the schema, not a detail: `existed: true`
    // with a non-string value cannot be written back into an INI, and
    // `existed: false` with a value is a contradiction about what was there.
    if (parsed.existed) {
      if (typeof parsed.value !== 'string') return null;
    } else if (parsed.value !== null && parsed.value !== undefined) {
      return null;
    }
    // W2-005: the occurrence list travels with the record when it is a valid
    // array of the owned shape; anything else keeps the legacy shape.
    let occurrences;
    if (parsed.occurrences !== undefined) {
      if (!Array.isArray(parsed.occurrences)) return null;
      if (parsed.occurrences.some((o) => !o || typeof o !== 'object' || typeof o.section !== 'string'
        || typeof o.key !== 'string' || typeof o.value !== 'string')) return null;
      occurrences = parsed.occurrences;
    } else if (parsed.existed) {
      occurrences = [{ section: THEME_SECTION, key: THEME_KEY, value: parsed.value }];
    } else {
      occurrences = [];
    }
    return { existed: parsed.existed, value: parsed.existed ? parsed.value : null, occurrences };
  }
  const ini = parseIni(raw);
  const v = iniLookup(ini, THEME_SECTION, THEME_KEY);
  // W2-005: the same occurrence list the JSON record carries, so a legacy
  // whole-file snapshot restores duplicates exactly like a modern one.
  const occurrences = ini.occurrences.filter((o) => o.section.toLowerCase() === THEME_SECTION.toLowerCase() && o.key.toLowerCase() === THEME_KEY.toLowerCase());
  return { existed: v !== undefined, value: v === undefined ? null : v, occurrences };
}

function currentThemeKeyValue() {
  if (!exists(userIni)) return undefined;
  const ini = parseIni(fs.readFileSync(userIni, 'utf8'));
  return iniLookup(ini, THEME_SECTION, THEME_KEY);
}

// W2-001: a .ovt is a ZIP archive. `encoding: 'base64'` states how the bytes
// were captured, so a legacy recovery that carried the raw UTF-8 (which an
// older build wrote, and which the operator may still have on disk) is read
// back the same way rather than being decoded as if it were base64.
function replacementOvSnapshot(file) {
  return { existed: true, encoding: 'base64', value: fs.readFileSync(file).toString('base64') };
}

function ovtRestoreBytes(snap) {
  if (snap && snap.encoding === 'base64') return Buffer.from(snap.value, 'base64');
  // Legacy record: written as UTF-8 text by an older build, restored as such.
  return Buffer.from(snap.value, 'utf8');
}

// ─── Revert preflight: the COMPLETE required recovery set (CORE-001) ────────
// An installed Wintage target must have, for user.ini: either the created
// marker or the Theme-key snapshot, and for the .ovt either the created marker
// or the byte snapshot. Missing mandatory recovery is an unverifiable state:
// fail nonzero BEFORE any mutation.
function assertRecoveryComplete() {
  const missing = [];
  if (!exists(userIniCreated) && !exists(themeKeyBackup)) missing.push(`Theme-key snapshot (${path.basename(themeKeyBackup)} or ${path.basename(userIniCreated)})`);
  if (!exists(ovtCreated) && !exists(ovtBackup)) missing.push(`theme snapshot (${path.basename(ovtBackup)} or ${path.basename(ovtCreated)})`);
  if (missing.length) {
    throw new Error(`OBS: required Wintage recovery is missing for ${configDir}: ${missing.join('; ')} - cannot restore an unverifiable state; nothing was changed.`);
  }
  // A snapshot that exists but cannot be parsed is equally unverifiable.
  if (exists(themeKeyBackup) && !readThemeSnapshot()) {
    throw new Error(`OBS: the Theme-key recovery file is corrupt (${themeKeyBackup}) - cannot restore; nothing was changed.`);
  }
  if (exists(ovtBackup) && !ReadRecoveryJson(ovtBackup)) {
    throw new Error(`OBS: the theme recovery file is corrupt (${ovtBackup}) - cannot restore; nothing was changed.`);
  }
}

// Direct (uncoordinated) revert consumes recovery; parent-coordinated revert
// (--keep-recovery) leaves it for the manifest-transition success path.
function consumeRecovery() {
  if (keepRecovery) return;
  remove(themeKeyBackup);
  remove(userIniCreated);
  remove(ovtBackup);
  remove(ovtCreated);
}

// ─── Apply / repaint ────────────────────────────────────────────────────────
// ─── CORE-001: a Wintage-created user.ini is deleted only when nothing but the
// one owned key is left in it. Apply wrote exactly `[Appearance] Theme=<id>`
// into a file that did not exist; every section/key the user has added since
// (OBS writes a lot into user.ini) is their state, so the file survives and only
// the owned key is removed instead.
function createdUserIniIsPure() {
  if (!exists(userIni)) return false;
  const ini = parseIni(fs.readFileSync(userIni, 'utf8'));
  const names = Object.keys(ini.sections);
  // Any section other than [Appearance] is unrelated user state.
  if (names.some((n) => n.toLowerCase() !== THEME_SECTION.toLowerCase())) return false;
  // Inside [Appearance] only the owned key may exist.
  return names.every((n) => {
    const keys = Object.keys(ini.sections[n]);
    return keys.length === 0
      || (keys.length === 1 && keys[0].toLowerCase() === THEME_KEY.toLowerCase());
  });
}

if (revert) {
  if (dryRun) {
    // CORE-004: dry-run must answer the SAME fail-closed question the real
    // revert asks. The old branch printed a positive description and exited 0
    // before evaluating the recovery set, so -WhatIf could bless a revert that
    // was guaranteed to fail closed one step later.
    if (!exists(userIniCreated) && !exists(themeKeyBackup) &&
        !exists(ovtCreated) && !exists(ovtBackup) && !exists(markerFile)) {
      console.log('OBS Studio: no Wintage recovery state - nothing to revert.');
      process.exit(0);
    }
    try {
      assertRecoveryComplete();
    } catch (err) {
      // The real revert would have refused with this exact reason; the preflight
      // must say so rather than describe an operation that cannot run.
      console.error(`OBS Studio: ${err.message}`);
      process.exit(1);
    }
    if (exists(userIniCreated) && exists(userIni) && !createdUserIniIsPure()) {
      console.log(`OBS Studio: would remove only the [${THEME_SECTION}] ${THEME_KEY} key from the current ${path.basename(userIni)} (the file holds unrelated settings and would not be deleted) and remove ${path.basename(themeFile)}`);
    } else {
      console.log(`OBS Studio: would restore the [${THEME_SECTION}] ${THEME_KEY} key into the current ${path.basename(userIni)} and remove ${path.basename(themeFile)}`);
    }
    process.exit(0);
  }
  // Never-installed state (no marker, no snapshot) is a legitimate no-op ONLY
  // when no mutating evidence exists either. A palette marker alone proves a
  // Wintage install (an earlier corrupt/lost-recovery state) - fail closed.
  if (!exists(userIniCreated) && !exists(themeKeyBackup) &&
      !exists(ovtCreated) && !exists(ovtBackup) && !exists(markerFile)) {
    console.log(`OBS Studio: no Wintage recovery state - nothing to revert.`);
    process.exit(0);
  }
  assertRecoveryComplete();
  if (exists(userIniCreated)) {
    // CORE-001: "we created it, so drop it" is only safe while the file still
    // holds nothing but the owned key. Anything else the user added afterwards
    // survives and only the Wintage-owned key is removed from it.
    if (exists(userIni)) {
      if (createdUserIniIsPure()) {
        remove(userIni);
      } else {
        writeAtomic(userIni, removeIniKey(fs.readFileSync(userIni, 'utf8'), THEME_SECTION, THEME_KEY));
        console.log("OBS Studio: the Wintage-created user.ini holds unrelated user settings - removed only the owned Theme key and kept the file.");
      }
    }
    if (!keepRecovery) remove(userIniCreated);
  } else {
    const snap = readThemeSnapshot();
    if (exists(userIni)) {
      let ini = fs.readFileSync(userIni, 'utf8');
      if (snap && snap.existed && snap.occurrences.length) {
        // W2-005: restore the document exactly as Apply found it, every
        // duplicate included. A live document whose occurrence count changed
        // since the snapshot means the key was edited in the meantime, and a
        // blind write would clobber those lines: nothing is touched instead.
        const restored = restoreIniOccurrences(ini, snap.occurrences);
        if (restored === null) {
          console.error(`OBS Studio: --revert refused - ${path.basename(userIni)} no longer holds the ${snap.occurrences.length} owned ${THEME_KEY} entries the recovery recorded; nothing was written.`);
          process.exit(1);
        }
        ini = restored;
      } else if (snap && snap.existed) {
        ini = setIniValue(ini, THEME_SECTION, THEME_KEY, snap.value);
      } else {
        ini = removeIniKey(ini, THEME_SECTION, THEME_KEY);
      }
      writeAtomic(userIni, ini);
    }
  }
  if (exists(ovtCreated)) {
    remove(themeFile);
    if (!keepRecovery) remove(ovtCreated);
  } else {
    const snap = ReadRecoveryJson(ovtBackup);
    if (snap && snap.existed && typeof snap.value === 'string') {
      // W2-001: byte-for-byte restore of a replaced user theme. writeAtomic
      // hands the payload to fs.writeFileSync, which writes a Buffer raw, so
      // the decoded archive is returned exactly as it was captured.
      writeAtomic(themeFile, ovtRestoreBytes(snap));
    } else if (exists(themeFile)) {
      remove(themeFile);
    }
    if (!keepRecovery) remove(ovtBackup);
  }
  if (exists(markerFile)) remove(markerFile);
  consumeRecovery();
  console.log('OBS Studio: restored the previous theme selection into the current settings');
  process.exit(0);
}

if (finalizeRevert) {
  // W2-003: consuming recovery is irreversible, so the prerequisites must be
  // PROVEN rather than assumed. Two of them:
  //   1. the palette marker must be gone. Revert removes it as its last act, so
  //      a marker that is still here means the Revert did not complete (or never
  //      ran) -- consuming would destroy the only evidence needed to finish it.
  //      --manifest-committed carries the caller's proof that the manifest
  //      transition committed, which is the same authorization the Terminal
  //      helper's flag encodes.
  //   2. the recovery artifacts must be VALID. CORE-002: a wrong-shape file is
  //      unverifiable state, not spent state, and deleting it removes the only
  //      record of what the restore actually restored.
  if (exists(markerFile) && !manifestCommitted) {
    console.error('OBS Studio: --finalize-revert refused - the palette marker is still present, so the Revert did not complete; nothing was consumed.');
    process.exit(1);
  }
  if (exists(themeKeyBackup) && !readThemeSnapshot()) {
    console.error(`OBS Studio: --finalize-revert refused - the Theme-key recovery file is not a valid recovery record (${themeKeyBackup}); nothing was consumed.`);
    process.exit(1);
  }
  if (exists(ovtBackup) && !ReadRecoveryJson(ovtBackup)) {
    console.error(`OBS Studio: --finalize-revert refused - the theme recovery file is not a valid recovery record (${ovtBackup}); nothing was consumed.`);
    process.exit(1);
  }
  // Parent-coordinated: the manifest transition has committed; consume the
  // persistent recovery this helper correctly preserved during --revert.
  if (!dryRun) consumeRecovery();
  console.log(JSON.stringify({ finalized: true }));
  process.exit(0);
}

const theme = fs.readFileSync(sourceTheme, 'utf8');
if (!theme.includes(`id: '${THEME_ID}'`) || !theme.includes("extends: 'com.obsproject.Yami.Classic'")) {
  throw new Error('Built OBS theme is missing the Wintage ID or Yami Classic base.');
}

if (dryRun) {
  console.log(`OBS Studio: would install and activate ${palette}`);
  process.exit(0);
}

fs.mkdirSync(configDir, { recursive: true });
// Capture EVERY required recovery artifact BEFORE the first mutation; the
// first generation is never overwritten by a repaint (CORE-001).
if (!exists(userIniCreated) && !exists(themeKeyBackup)) {
  const current = exists(userIni) ? parseIni(fs.readFileSync(userIni, 'utf8')) : { sections: {}, occurrences: [] };
  // W2-002: the same case-insensitive lookup the writers use. Reading it
  // case-sensitively recorded `existed:false` for OBS's own lowercase
  // `[appearance] theme=`, and Revert then deleted the key it should restore.
  const v = iniLookup(current, THEME_SECTION, THEME_KEY);
  // W2-005: every occurrence of the owned key is recorded in document order so
  // Revert restores the original duplicates rather than collapsing them.
  const occurrences = current.occurrences.filter((o) => o.section.toLowerCase() === THEME_SECTION.toLowerCase() && o.key.toLowerCase() === THEME_KEY.toLowerCase());
  writeAtomic(themeKeyBackup, `${JSON.stringify({ existed: v !== undefined, value: v === undefined ? null : v, occurrences }, null, 2)}\n`);
  if (!exists(userIni)) { writeAtomic(userIniCreated, ''); }
}
if (!exists(ovtCreated) && !exists(ovtBackup)) {
  if (exists(themeFile)) {
    // W2-001: a .ovt is a ZIP archive, not text: reading it as UTF-8 and
    // writing the decoded result back corrupts every byte that is not valid
    // UTF-8, so a Revert of a replaced user theme used to restore a file that
    // no longer opens. Capture the bytes as base64 instead.
    writeAtomic(ovtBackup, `${JSON.stringify(replacementOvSnapshot(themeFile), null, 2)}\n`);
  } else {
    writeAtomic(ovtCreated, '');
  }
}
const originalIni = exists(userIni) ? fs.readFileSync(userIni, 'utf8') : '';
writeAtomic(userIni, setIniValue(originalIni, THEME_SECTION, THEME_KEY, THEME_ID));
writeAtomic(themeFile, theme);
// W2-004 test seam: a LATE failure, after user.ini, the theme file and the
// recovery artifacts are already on disk but before the palette marker commits.
// That is the exact shape the parent's snapshot exists for, and it was the one
// shape no gate covered: the helper exited nonzero and the PowerShell parent
// threw past the snapshot it had taken one line earlier. Never set outside
// tests.
if (process.env.WINTAGE_TEST_FAIL_AFTER_OBS_THEME) {
  console.error('OBS: injected late-write failure (WINTAGE_TEST_FAIL_AFTER_OBS_THEME)');
  process.exit(1);
}
writeAtomic(markerFile, `${palette}\n`);
console.log(`OBS Studio: installed and activated ${palette}`);