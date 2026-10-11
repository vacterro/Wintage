#!/usr/bin/env node
'use strict';

// A RED control that cannot go red is decoration. This proves the controls in
// test-inspect-web.js actually bite: each entry below is a plausible bad edit
// to the inspector, and the gate must FAIL on every one of them.
//
// It runs entirely on COPIES in a scratch directory, never on the real sources.
// An earlier version mutated tools/inspect-web.js in place, which meant an
// interrupted run left a broken tool on disk -- the exact hazard a test must
// not create. The scratch directory is one level under the project root so the
// gate's `require('..' + '/wintage.user.js')` still resolves.

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const root = path.join(__dirname, '..');
const scratch = path.join(root, '.mutcheck');
const tool = path.join(__dirname, 'inspect-web.js');
const gate = path.join(__dirname, 'test-inspect-web.js');
// Normalised to LF before any anchor is matched. Every multi-line anchor in
// MUTATIONS is written with \n, and this repo checks out on Windows with CRLF,
// so matching raw bytes could not find one of them: the control reported
// "anchor not found", skipped, and still exited 0. Eight of thirty-four
// controls were not running at all, which is the same vacuity this gate exists
// to catch -- it just happened to be living in the harness instead of the
// product.
const original = fs.readFileSync(tool, 'utf8').replace(/\r\n/g, '\n');

const MUTATIONS = [
  ['unexamined surface reported as themed',
    "  if (!token) return { state: 'unproven', why: 'no token expectation defined for this surface' };",
    "  if (!token) return { state: 'themed', why: null };"],
  ['missing required surface swallowed',
    "    return contract === CONTRACT.ALWAYS\n      ? { state: 'MISSING', why: 'required contract did not match in the live DOM on ' + (path || '/') }",
    "    return contract !== 'never'\n      ? { state: 'absent', why: null }"],
  ['a CONTEXTUAL surface demanded on every poll again',
    "    return contract === CONTRACT.ALWAYS",
    "    return contract !== CONTRACT.OPTIONAL"],
  ['stock surface accepted when the token is unresolved',
    "  if (!resolved.some(r => r.value)) {\n    return { state: 'unproven', why: 'token ' + wanted.join(' | ') + ' resolved to nothing on this page' };\n  }",
    "  if (!resolved.some(r => r.value)) {\n    return { state: 'themed', why: null };\n  }"],
  ['session coverage stops being decided over the whole session',
    "  const requiredCoverageNotObserved = applicableCoverageNeeded.filter(id => !presentEver.has(id));",
    "  const requiredCoverageNotObserved = [];"],
  ['a never-seen always-required contract stops failing the run',
    "      if (seen.length === 0 || applicableEver.has(mat.id)) requiredMissingEver.add(mat.id);",
    "    if (false) requiredMissingEver.add(s.id);"],
  // Anchored on the unproven HALF of the derivation, not on the whole statement:
  // T-388 split unresolvedAcceptance into an observed-but-unprovable half and a
  // never-observed half, and they fail for different reasons, so they need
  // different controls. Mutating the statement itself would have made this one
  // silently cover both.
  ['a requested surface is allowed to pass while UNPROVEN',
    "...[...unprovenEver].filter(id => ACCEPTANCE_SURFACES.has(id)),",
    "...[],"],
  // The sibling of the control above, and the one that was MISSING: that control
  // removes the observed-but-unprovable half of the demand, this one removes the
  // never-observed half. Without it the gate could drop a requested surface the
  // operator never opened and every assertion would still be satisfied -- which
  // is exactly what happened until T-388.
  ['a requested surface the operator never opened stops being unresolved',
    "  const neverObservedAcceptance = [...ACCEPTANCE_SURFACES].filter(id => {\n    if (presentEver.has(id)) return false;\n    // A session with no usable poll has opened nothing anywhere: every requested\n    // surface is unresolved, not just the ones a route would have judged.\n    if (seen.length === 0) return true;\n    if (requiredRoutesNeverVisited.includes(id)) return false;\n    if (!applicableEver.has(id)) return false;\n    if (COMPOSER_ACCEPTANCE_GROUP.includes(id) &&\n        COMPOSER_ACCEPTANCE_GROUP.some(x => presentEver.has(x))) return false;\n    return true;\n  });",
    "  const neverObservedAcceptance = [];"],
  // The 2026-10-10 composer acceptance repair: an absent sibling used to be
  // demanded per-id, so a correct single-variant shell read NON-ACCEPTING. The
  // group exemption is the fix -- this restores the per-id demand and requires
  // the A/B/C fixtures (sibling absent / current shell) to go red.
  ['composer acceptance reverts to demanding every rollout variant per id',
    "    if (COMPOSER_ACCEPTANCE_GROUP.includes(id) &&\n        COMPOSER_ACCEPTANCE_GROUP.some(x => presentEver.has(x))) return false;\n",
    ""],
  // Fixture F's negative half: without it the ownership-inheritance rule could
  // be loosened to "ancestor has some colour" and a stock owner would inherit.
  ['a transparent child inherits without its owner being observed and themed',
    "    if (!anc || !anc.surfaceId || !themed.has(anc.surfaceId)) continue;",
    "    if (!anc) continue;"],
  ['the assistant message loses its token expectation again',
    "  'assistant-message': '--chat-background-color',",
    "  assistant: '--chat-background-color',"],
  ['a Settings poll demands the conversation matrix again',
    "  if (scope === SCOPE.CONVERSATION) return !isSettingsRoute(path);",
    "  if (scope === SCOPE.CONVERSATION) return true;"],
  ['the route sanitizer stops redacting opaque ids',
    "(SAFE_ROUTE_SEGMENTS.has(seg.toLowerCase()) ? seg : ':id')",
    "(SAFE_ROUTE_SEGMENTS.has(seg.toLowerCase()) || seg.length < 999 ? seg : ':id')"],
  ['the target listing prints the title again',
    "  const url = sanitizeTargetUrl(target && target.url);",
    "  const url = sanitizeTargetUrl(target && (target.title + ' ' + target.url));"],
  ['the no-match error prints the raw open-page urls',
    "  const seen = (pages || []).map(p => '  ' + sanitizeTargetDisplay(p).display).join('\\n') || '  (no page targets)';",
    "  const seen = (pages || []).map(p => '  ' + (p.url || '')).join('\\n') || '  (no page targets)';"],
  ['the JSON target listing prints raw urls',
    "  return JSON.stringify(pages.map(sanitizeTargetDisplay), null, 1);",
    "  return JSON.stringify(pages.map(p => ({ type: p.type, url: p.url })), null, 1);"],
  ['the attach banner prints the raw target url',
    "function renderAttachLine(target) { return 'attached: ' + sanitizeTargetDisplay(target).display; }",
    "function renderAttachLine(target) { return 'attached: ' + (target.url || ''); }"],
  ['attribution stops being exception-safe',
    "  } finally {\n    restore();\n  }",
    "  }\n  restore();"],
  ['restoration clobbers the state the page arrived in',
    "      try { w95sheets[i].disabled = priorDisabled[i]; } catch (e1) { }",
    "      try { w95sheets[i].disabled = false; } catch (e1) { }"],
  ['dedupe always reports fresh',
    "  if (seen.has(key)) return { fresh: [], duplicate: true, total: seen.size };",
    "  if (false) return { fresh: [], duplicate: true, total: seen.size };"],
  ['dedupe collapses every observation to one',
    "  if (seen.has(key)) return { fresh: [], duplicate: true, total: seen.size };\n  seen.add(key);",
    "  seen.clear(); seen.add(key); return { fresh: [report], duplicate: false, total: seen.size };"],
  ['privacy boundary filters instead of rebuilding',
    "function sanitizeNode(node) {\n  if (!node || typeof node !== 'object') return null;\n  const out = {};",
    "function sanitizeNode(node) {\n  if (!node || typeof node !== 'object') return null;\n  const out = Object.assign({}, node);"],
  ['in-page allowlist widened to carry text',
    "      var ALLOWED = ['id','role','data-testid','data-w95','data-w95-ver','aria-pressed','aria-selected','aria-expanded','aria-haspopup','aria-modal','data-state','contenteditable'];",
    "      var ALLOWED = ['id','role','text','data-testid','data-w95','data-w95-ver','aria-pressed','aria-selected','aria-expanded','aria-haspopup','aria-modal','data-state','contenteditable'];"],
  ['malformed CDP reply resolves as an empty report',
    "  if (!res || typeof res !== 'object' || !res.result || typeof res.result !== 'object') {\n    throw new Error('Malformed CDP response: Runtime.evaluate returned no result object');\n  }",
    "  if (!res || !res.result) return [];"],
  ['page throw reported as a malformed reply',
    "  if (res && res.exceptionDetails) {",
    "  if (false && res && res.exceptionDetails) {"],
  ['malformed page report coerced into an all-clear',
    "function sanitizePageReport(raw) {\n  if (!raw || typeof raw !== 'object' || !Array.isArray(raw.surfaces)) {\n    throw new Error('Malformed page report: expected an object with a surfaces array');\n  }",
    "function sanitizePageReport(raw) {\n  if (!raw || typeof raw !== 'object' || !Array.isArray(raw.surfaces)) {\n    return { url_host: null, route: null, wintage: { stamped: false, sheets: 0 }, tokens: {}, surfaces: [] };\n  }"],
  ['aggregation demands every route-scoped surface of a single-route session',
    "  const applicableCoverageNeeded = coverageNeeded.filter(id => seen.length === 0 || applicableEver.has(id));",
    "  const applicableCoverageNeeded = coverageNeeded;"],
  ['class-fragment selector allowed into the matrix',
    "CURRENT_SIDEBAR + ' a, #app-shell-sidebar nav a, #app-shell-sidebar a[href^=\"/c/\"], #app-shell-sidebar a[href^=\"/g/\"]",
    "selector: '[class*=\"sidebar\"]'"],
  ['code block no longer probes ChatGPT-owned layout',
    "{ id: 'code-block', label: 'code block container', selector: '[data-markdown-copy=\"code-block\"]', contract: CONTRACT.COVERAGE, scope: SCOPE.CONVERSATION, props: DEFAULT_PROPS.concat(LAYOUT_PROPS) },",
    "{ id: 'code-block', label: 'code block container', selector: '[data-markdown-copy=\"code-block\"]', contract: CONTRACT.COVERAGE, scope: SCOPE.CONVERSATION },"],
  ['full-page Settings dropped from the matrix',
    "  { id: 'settings-page', label: 'full-page Settings surface', route: /^\\/settings(\\/|$)/, selector: 'main', contract: CONTRACT.ALWAYS, scope: SCOPE.SETTINGS },",
    ""],
  ['live expectations name a token Wintage does not declare',
    "  sidebar: '--color-token-side-bar-background',",
    "  sidebar: '--color-token-sidebar-background',"],
  // The transparent-host allowance is the one rule in the classifier that can turn
  // a finding into a pass, so its control has to exist: without the mapping the
  // correct-page assertion goes red.
  ['a transparent host loses the container it depends on',
    "  'code-block-actions': 'code-block'",
    "  'code-block-actions': 'nowhere'"],
  ['a transparent host is accepted with nothing painted at all',
    "    if (!themed.has(TRANSPARENT_HOSTS[id])) continue;",
    "    if (false) continue;"],
  // The two hosts added from the 2026-10-04 live measurements get their own control
  // each. The pair above proves the RULE is conditional; these prove the two new
  // entries are actually load-bearing, which a generic control would not -- if
  // 'settings-nav' were never consulted, nothing above would notice.
  ['the settings-nav transparent host loses the sidebar it depends on',
    "  'settings-nav': 'sidebar',",
    "  'settings-nav': 'nowhere',"],
  ['the assistant-message transparent host loses the conversation it depends on',
    "  'assistant-message': 'conversation',",
    "  'assistant-message': 'nowhere',"],
  ['caller gains a credential-bearing CDP domain',
    "const { debugPort, pageTargets, connect, die } = require('./cdp-client.js');",
    "const { debugPort, pageTargets, connect, die } = require('./cdp-client.js');\nconst cdp_getAllCookies = 1; // Network.getAllCookies"],
  ['summarize stops reporting mismatches',
    "    if (c.state === 'MISMATCH') { mismatches.push({ id: s.id, label: s.label, selector: s.selector, why: c.why, style: s.style }); continue; }",
    "    if (c.state === 'MISMATCH') { continue; }"],
  ['the sanitizer stops rebuilding the node allowlist',
    "function sanitizeNode(node) {\n  if (!node || typeof node !== 'object') return null;\n  const out = {};\n  for (const k of Object.keys(node)) {",
    "function sanitizeNode(node) {\n  if (!node || typeof node !== 'object') return null;\n  const out = {};\n  for (const k of ['tag','id','aria-label','title','text']) {"],
  ['the probe stops recording cascade attribution',
    "        rec.vintageOwns = ownsMap;",
    "        rec.vintageOwns = null;"],
  ['the report hides whether attribution actually ran',
    "    attribute: raw.attribute === true,",
    "    attribute: true,"],
  ['attribution stops toggling the theme off',
    "        w95off = true; w95sheets.forEach(function (s) { try { s.disabled = true; } catch (e4) { } });",
    "        w95off = false; w95sheets.forEach(function (s) { try { s.disabled = false; } catch (e4) { } });"],
  ['attribution stops being opt-in',
    "  var ATTRIBUTE = ${attribute};",
    "  var ATTRIBUTE = true;"]
];

fs.mkdirSync(scratch, { recursive: true });
let leaks = 0;
try {
  // Baseline: unmutated copies must be green, or every "red" below is noise.
  // The scratch dir also needs the shared client, since the copies resolve
  // requires relative to themselves, not to tools/.
  fs.writeFileSync(path.join(scratch, 'inspect-web.js'), original);
  fs.copyFileSync(path.join(__dirname, 'cdp-client.js'), path.join(scratch, 'cdp-client.js'));
  fs.copyFileSync(gate, path.join(scratch, 'test-inspect-web.js'));
  try {
    execFileSync(process.execPath, [path.join(scratch, 'test-inspect-web.js')], { stdio: 'pipe' });
    console.log('PASS: the unmutated copies are green (a red that means nothing is not a control)');
  } catch (e) {
    console.error('FAIL: the unmutated copies are NOT green -- fix the gate before trusting the mutations');
    process.exit(1);
  }

  for (const [name, from, to] of MUTATIONS) {
    if (!original.includes(from)) { console.error('FAIL: mutation anchor not found: ' + name); leaks++; continue; }
    fs.writeFileSync(path.join(scratch, 'inspect-web.js'), original.replace(from, to));
    let wentRed = false;
    let why = '';
    try {
      execFileSync(process.execPath, [path.join(scratch, 'test-inspect-web.js')], { stdio: 'pipe' });
    } catch (e) {
      wentRed = true;
      why = String((e.stdout || '') + (e.stderr || '')).split('\n')
        .filter(l => l.startsWith('FAIL:')).slice(0, 2).join(' / ').slice(0, 200);
    }
    if (wentRed) console.log('PASS: goes red on "' + name + '"' + (why ? '  [' + why.trim() + ']' : ''));
    else { console.error('FAIL: still green on "' + name + '" -- that control does not bite'); leaks++; }
  }
} finally {
  fs.rmSync(scratch, { recursive: true, force: true });
}

if (leaks) {
  console.error('\nmutation gate: ' + leaks + ' control(s) did not go red');
  process.exit(1);
}
console.log('\nmutation gate: PASS (every control goes red)');
