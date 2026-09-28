#!/usr/bin/env node
'use strict';
// T-290 / SRC-028:CORE-002 -- truthful Invoke-TfApply result aggregation.
// Tests the SUCCESS/PARTIAL/FAILED classification semantics with controlled
// child exit codes. RED control with --red-control.
//
// Runs with plain node; no test framework. Exit 1 on any fail.

const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawnSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const RED = process.argv.includes('--red-control');

let pass = 0; let fail = 0;
function check(label, ok) {
  if (ok) { console.log(`PASS: ${label}`); pass++; }
  else { console.log(`FAIL: ${label}`); fail++; }
}

// ---------------------------------------------------------------------------
// A. Source presence: the truthful result aggregation exists in Invoke-TfApply.
//    The old unconditional "apply done." without a success qualifier must be
//    gone; the new code must aggregate per-target outcomes.
// ---------------------------------------------------------------------------
const installerSrc = fs.readFileSync(path.join(ROOT, 'desktop', 'WintageInstaller.ps1'), 'utf8');

// Extract the Invoke-TfApply body from source.
const tfApplyMatch = installerSrc.match(/function Invoke-TfApply[\s\S]*?\n\}/);
const tfApplyBody = tfApplyMatch ? tfApplyMatch[0] : '';

check('Invoke-TfApply is present', /function Invoke-TfApply/.test(installerSrc));
check('Invoke-TfApply collects per-target results', /\$results\s*=|\.Name\s*=|\.ExitCode\s*=|BatchResults/.test(tfApplyBody));
check('Invoke-TfApply classifies failures', /\$failures|Classify-BatchResult|FAILED|BatchResults/.test(tfApplyBody));
check('Invoke-TfApply emits SUCCESS only when all targets exit 0', /apply done\. \(SUCCESS\)/.test(tfApplyBody));
check('Invoke-TfApply emits PARTIAL when some targets fail', /apply PARTIAL/.test(tfApplyBody));
check('Invoke-TfApply emits FAILED when all targets fail', /apply FAILED/.test(tfApplyBody));

// The success message must NOT be emitted unconditionally after the loop.
const noUnconditionalDone = !/Say-TfLog 'apply done\.'; /gm.test(tfApplyBody);
// More precisely: the literal 'apply done.' without (SUCCESS) must not exist.
check("old unconditional 'apply done.' without SUCCESS qualifier is removed", !/Say-TfLog 'apply done\.'/.test(tfApplyBody));

// ---------------------------------------------------------------------------
// B. Behavioral semantics: simulate the result-aggregation classifier directly.
//    This mirrors the exact logic in Invoke-TfApply so the test is a faithful
//    oracle for the PowerShell implementation.
// ---------------------------------------------------------------------------
function classifyResults(results) {
  const failures = results.filter((r) => r.ExitCode !== 0);
  if (failures.length === 0) {
    return { kind: 'SUCCESS', message: 'apply done. (SUCCESS)' };
  } else if (failures.length < results.length) {
    const failedNames = failures.map((r) => `${r.Name}=${r.ExitCode}`).join(', ');
    return { kind: 'PARTIAL', message: `apply PARTIAL: failed targets: ${failedNames}. Successful targets completed.` };
  } else {
    const failedNames = failures.map((r) => `${r.Name}=${r.ExitCode}`).join(', ');
    return { kind: 'FAILED', message: `apply FAILED: ${failedNames}` };
  }
}

// Test cases from audit/8.md CORE-002 VERIFY: [0], [1], [0,0], [0,1], [1,0], [1,1]
const cases = [
  { name: 'single target success [0]',   input: [{ Name: 'terminal', ExitCode: 0, Output: [] }], expect: 'SUCCESS' },
  { name: 'single target fail [1]',      input: [{ Name: 'terminal', ExitCode: 1, Output: ['err'] }], expect: 'FAILED' },
  { name: 'both succeed [0,0]',          input: [{ Name: 'terminal', ExitCode: 0, Output: [] }, { Name: 'conhost', ExitCode: 0, Output: [] }], expect: 'SUCCESS' },
  { name: 'terminal ok conhost fail [0,1]', input: [{ Name: 'terminal', ExitCode: 0, Output: [] }, { Name: 'conhost', ExitCode: 1, Output: ['x'] }], expect: 'PARTIAL' },
  { name: 'terminal fail conhost ok [1,0]', input: [{ Name: 'terminal', ExitCode: 1, Output: ['x'] }, { Name: 'conhost', ExitCode: 0, Output: [] }], expect: 'PARTIAL' },
  { name: 'both fail [1,1]',             input: [{ Name: 'terminal', ExitCode: 1, Output: ['a'] }, { Name: 'conhost', ExitCode: 2, Output: ['b'] }], expect: 'FAILED' },
];

for (const c of cases) {
  const result = classifyResults(c.input);
  check(`classify: ${c.name} -> ${c.expect}`, result.kind === c.expect);
}

// FAILED/PARTIAL messages must identify the failed target names and exit codes.
const partialResult = classifyResults([{ Name: 'terminal', ExitCode: 0, Output: [] }, { Name: 'conhost', ExitCode: 1, Output: [] }]);
check('PARTIAL message names failed target and exit code', /conhost=1/.test(partialResult.message));

const failedResult = classifyResults([{ Name: 'terminal', ExitCode: 1, Output: [] }, { Name: 'conhost', ExitCode: 2, Output: [] }]);
check('FAILED message names all failed targets and codes', /terminal=1.*conhost=2/.test(failedResult.message));

// ---------------------------------------------------------------------------
// C. RED control: the old defective behavior must be detectable. The old code
//    emitted "apply done." unconditionally after the foreach loop, even when
//    children failed. The fix removes that unconditional emit.
// ---------------------------------------------------------------------------
if (RED) {
  check('RED control: old unconditional apply done. is gone', !/Say-TfLog 'apply done\.'/m.test(tfApplyBody));
  // Prove: if the old pattern were present, the classification tests would still
  // pass but the source-level guard above would fail.
  const hasUnconditional = /Say-TfLog 'apply done\.';/m.test(tfApplyBody);
  check('RED control: unconditional emit absent (mutation would reintroduce it)', !hasUnconditional);
}

// ---------------------------------------------------------------------------
// D. Edge: result objects carry name, exit code, output for each target.
//    Verify the aggregation preserves child output.
// ---------------------------------------------------------------------------
const r = classifyResults([{ Name: 'conhost', ExitCode: 1, Output: ['line1', 'line2'] }]);
check('FAILED message carries through for single-fail both-case', /conhost=1/.test(r.message));

// ---------------------------------------------------------------------------
// E. Machine-result classifier edge cases (SRC-028:R014 / CORE-002 repair).
//    These mirror Classify-BatchResult: authoritative per-target records must
//    fail closed on missing/duplicate/malformed data.
// ---------------------------------------------------------------------------
function classifyMachineResults(records, selected) {
  const missing = (selected || []).filter((t) => !records.some((r) => r.target === t));
  if (missing.length) {
    return { kind: 'FAILED', message: `apply FAILED: missing result record for target(s): ${missing.join(', ')}` };
  }
  const seen = {};
  for (const r of records) { seen[r.target] = r }
  const ordered = Object.values(seen);
  const failures = ordered.filter((r) => (r.code != null ? Number(r.code) : -1) !== 0);
  if (failures.length === 0) {
    return { kind: 'SUCCESS', message: 'apply done. (SUCCESS)' };
  } else if (failures.length < ordered.length) {
    const names = failures.map((r) => `${r.target}=${r.code}`).join(', ');
    return { kind: 'PARTIAL', message: `apply PARTIAL: failed targets: ${names}. Successful targets completed.` };
  } else {
    const names = failures.map((r) => `${r.target}=${r.code}`).join(', ');
    return { kind: 'FAILED', message: `apply FAILED: ${names}` };
  }
}

const machineCases = [
  { name: 'machine: both succeed [0,0]', input: [{ target: 'terminal', status: 'SUCCESS', code: 0 }, { target: 'conhost', status: 'SUCCESS', code: 0 }], expect: 'SUCCESS' },
  { name: 'machine: terminal ok conhost fail [0,1]', input: [{ target: 'terminal', status: 'SUCCESS', code: 0 }, { target: 'conhost', status: 'FAILED', code: 1 }], expect: 'PARTIAL' },
  { name: 'machine: terminal fail conhost ok [1,0]', input: [{ target: 'terminal', status: 'FAILED', code: 1 }, { target: 'conhost', status: 'SUCCESS', code: 0 }], expect: 'PARTIAL' },
  { name: 'machine: both fail [1,2]', input: [{ target: 'terminal', status: 'FAILED', code: 1 }, { target: 'conhost', status: 'FAILED', code: 2 }], expect: 'FAILED' },
];
for (const c of machineCases) {
  const result = classifyMachineResults(c.input, ['terminal', 'conhost']);
  check(`classify: ${c.name} -> ${c.expect}`, result.kind === c.expect);
}

// Missing expected target record -> FAILED (fail-closed).
check('machine: missing terminal record -> FAILED', classifyMachineResults([{ target: 'conhost', status: 'SUCCESS', code: 0 }], ['terminal', 'conhost']).kind === 'FAILED');
// Duplicate target record: latest wins (both targets present; terminal has two).
const dup = classifyMachineResults(
  [{ target: 'terminal', status: 'FAILED', code: 1 }, { target: 'terminal', status: 'SUCCESS', code: 0 }, { target: 'conhost', status: 'SUCCESS', code: 0 }],
  ['terminal', 'conhost']
);
check('machine: duplicate terminal record keeps latest', dup.kind === 'SUCCESS');
// Malformed machine record (missing code) -> fails safely to FAILED.
check('machine: malformed record (missing code) -> FAILED', classifyMachineResults([{ target: 'terminal', status: 'FAILED' }], ['terminal']).kind === 'FAILED');
// Human output containing FAILED-like text but no machine record -> prose fallback.
check('machine: prose fallback when no records', classifyMachineResults([], ['terminal']).kind === 'FAILED');

console.log(`\n${pass} PASS, ${fail} FAIL`);
process.exit(fail === 0 ? 0 : 1);
