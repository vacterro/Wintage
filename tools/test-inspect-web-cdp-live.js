#!/usr/bin/env node
'use strict';
// Drives the REAL tools/inspect-web.js CLI against a REAL browser over REAL CDP.
//
// WHY. tools/test-inspect-web.js proves the probe, the sanitizer, the
// aggregator and the verdict against mock page reports. It never opens a
// socket: nothing in the repo exercised tools/cdp-client.js end to end. That
// gap is invisible until an operator runs the live acceptance pass for T-359
// and the transport is the thing that breaks. This closes it without an
// account, so the operator's step is "open the surfaces", not "debug the tool".
//
// WHAT IT PROVES. The transport, the probe, the watch loop, the five report
// fields the T-359 verify clause names, the privacy sanitizer, and -- the
// point of the exercise -- that the tool still REFUSES to accept when the
// acceptance surfaces are unproven.
//
// WHAT IT DOES NOT PROVE. Anything about the real chatgpt.com. Its DOM, its
// tokens and its routes are not here. A green run here is a green tool, not a
// green product; T-359 still needs the operator's signed-in tab.

const assert = require('assert');
const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const FIXTURE = path.join(__dirname, 'fixtures', 'chatgpt-surface.html');
const CLI = path.join(__dirname, 'inspect-web.js');
// The live CLI proves the tool against a real browser; the module is imported for
// one thing only -- reading the SAME unproven list the tool applies, so this gate
// cannot assert a stale copy of it.
const INSPECTOR = require('./inspect-web.js');

const CHROME_CANDIDATES = [
  'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
  'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
  'C:\\Program Files\\BraveSoftware\\Brave-Browser\\Application\\brave.exe',
  'C:\\Program Files (x86)\\BraveSoftware\\Brave-Browser\\Application\\brave.exe'
];

// The conversation text planted in the fixture. The tool's contract is that
// it never emits conversation text; if the sanitizer regresses, this appears.
const SENTINELS = ['SENTINEL_USER_TEXT_DO_NOT_EMIT_9f3a2c', 'SENTINEL_ASSISTANT_TEXT_DO_NOT_EMIT_7b1e4d'];

const sleep = ms => new Promise(r => setTimeout(r, ms));

function findBrowser() {
  for (const p of CHROME_CANDIDATES) if (fs.existsSync(p)) return p;
  return null;
}

function getJson(port, route) {
  return new Promise((resolve, reject) => {
    const req = http.get({ host: '127.0.0.1', port, path: route, timeout: 2000 }, r => {
      let d = '';
      r.on('data', c => { d += c; });
      r.on('end', () => { try { resolve(JSON.parse(d)); } catch (e) { reject(e); } });
    });
    req.on('timeout', () => { req.destroy(new Error('timeout')); });
    req.on('error', reject);
  });
}

async function waitForCdp(port, deadlineMs) {
  const end = Date.now() + deadlineMs;
  while (Date.now() < end) {
    try { return await getJson(port, '/json/version'); } catch (e) { await sleep(250); }
  }
  throw new Error('browser never opened a CDP endpoint on port ' + port);
}

// The watch prints one JSON line per unique observation, then the final
// aggregate as a pretty-printed object. The aggregate is the only one holding
// "finished", and it is printed last, so walk back to its opening brace.
function parseFinal(stdout) {
  const at = stdout.lastIndexOf('"finished"');
  if (at < 0) throw new Error('watch produced no final aggregate:\n' + stdout.slice(-2000));
  const start = stdout.lastIndexOf('{', at);
  return JSON.parse(stdout.slice(start).trim());
}

// Each unique observation is a single JSON line carrying the raw per-surface
// DOM result. This is where "the probe actually queried the live document"
// is visible; the aggregate deliberately drops mere presence.
function parseObservations(stdout) {
  const out = [];
  for (const line of stdout.split('\n')) {
    const t = line.trim();
    if (!t.startsWith('{') || !t.includes('"at"')) continue;
    try { out.push(JSON.parse(t)); } catch (e) { /* the pretty final block */ }
  }
  return out;
}

function runWatch(cdpPort, urlPart, seconds) {
  return new Promise(resolve => {
    const child = spawn(process.execPath, [CLI, 'watch', urlPart, String(seconds), '--json', '--attribute'], {
      cwd: ROOT,
      env: Object.assign({}, process.env, {
        WINTAGE_DEBUG_PORT: String(cdpPort),
        WINTAGE_WATCH_INTERVAL: '800'
      })
    });
    let out = '', err = '';
    child.stdout.on('data', d => { out += d; });
    child.stderr.on('data', d => { err += d; });
    child.on('close', code => resolve({ code, out, err }));
  });
}

async function main() {
  assert.ok(fs.existsSync(FIXTURE), 'fixture missing: ' + FIXTURE);
  const browser = findBrowser();
  assert.ok(browser, 'no Chrome/Brave found; the live transport cannot be proven on this machine');

  const html = fs.readFileSync(FIXTURE);
  const server = http.createServer((req, res) => {
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
    res.end(html);
  });
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const sitePort = server.address().port;

  // A fresh --user-data-dir: this profile holds no cookies and no session, and
  // it is a temp dir this process owns and deletes.
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'w95-cdp-live-'));
  const cdpPort = 9000 + (process.pid % 900);
  const url = `http://127.0.0.1:${sitePort}/c/fixture`;
  const child = spawn(browser, [
    '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
    '--remote-debugging-port=' + cdpPort, '--user-data-dir=' + profile, url
  ], { stdio: 'ignore' });

  let result;
  try {
    await waitForCdp(cdpPort, 30000);
    result = await runWatch(cdpPort, '127.0.0.1', 10);
  } finally {
    // Only ever the PID this process started.
    try { child.kill(); } catch (e) { /* already gone */ }
    server.close();
    try { fs.rmSync(profile, { recursive: true, force: true }); } catch (e) { /* temp dir */ }
  }

  const final = parseFinal(result.out);

  // 1. The five fields the T-359 verify clause names must all be present.
  for (const f of ['observedEver', 'mismatchedEver', 'unprovenEver',
                   'requiredCoverageNotObserved', 'optionalNotObserved']) {
    assert.ok(Array.isArray(final[f]), 'report field missing or not a list: ' + f);
  }

  // 2. The probe really reached the DOM. A transport that silently returned an
  //    empty page would satisfy the shape check above and prove nothing, so
  //    assert on the raw per-surface presence the live document reported.
  //    Union across the session, NOT the first snapshot: the opening poll can
  //    legitimately land mid-parse, which is exactly why the watch aggregates
  //    rather than reading one frame. Asserting on frame zero made this gate
  //    pass or fail on machine load.
  const observations = parseObservations(result.out);
  assert.ok(observations.length > 0, 'watch recorded no unique observation');
  const present = new Set();
  for (const o of observations) {
    for (const s of o.report.surfaces) if (s.present) present.add(s.id);
  }
  const rendered = ['root', 'root-body', 'root-app', 'conversation', 'thread', 'sidebar',
    'nav-entry', 'nav-project', 'user-message', 'assistant-message', 'composer-root',
    'composer-body', 'prompt-editor', 'composer-utility', 'header-mode', 'code-block',
    'code-block-pre', 'code-block-actions', 'thread-footer', 'menu', 'listbox',
    'popover', 'dialog'];
  for (const id of rendered) {
    assert.ok(present.has(id),
      'fixture renders ' + id + ' but the live probe did not find it in the document');
  }

  // 3. Surfaces that carry a token expectation must classify as themed, which
  //    means the round trip was token -> computed background -> comparison.
  // Derived from the matrix, not copied: a hard-coded list here would keep
  // asserting a surface is themed after its token was removed, and would miss a
  // surface that GAINED one. Every rendered, token-bearing, non-transparent host
  // must classify themed.
  const transparentHosts = new Set(['nav-entry', 'prompt-editor', 'code-block-actions']);
  const themed = INSPECTOR.SURFACES.filter(x => INSPECTOR.SURFACE_TOKENS[x.id] && !transparentHosts.has(x.id))
    .map(x => x.id)
    .filter(id => present.has(id));
  for (const id of themed) {
    assert.ok(final.observedEver.includes(id),
      id + ' has a token expectation and is rendered, but never classified as themed');
  }
  assert.deepStrictEqual(final.mismatchedEver, [],
    'fixture sets each surface background to its own token, so nothing may mismatch');

  // 4. The deliberately-unproven surfaces must land in unprovenEver, not in
  //    observedEver. This is the project's own refusal to call an unexamined
  //    surface themed, and it is the behaviour T-359 depends on. The list is
  //    DECLARED_UNPROVEN_ACCEPTANCE itself, not a copy: it started as six surfaces and
  //    emptied to one on 2026-10-04 as each was proved on the live page, and a
  //    hard-coded list here would have kept asserting they are still unprovable
  //    -- which is the exact drift this gate exists to catch.
  for (const id of INSPECTOR.DECLARED_UNPROVEN_ACCEPTANCE) {
    if (!present.has(id)) continue;                      // never opened here; nothing was claimed
    assert.ok(final.unprovenEver.includes(id),
      id + ' carries no token expectation and must stay UNPROVEN by design');
    assert.ok(!final.observedEver.includes(id),
      id + ' has no token expectation and must never be reported as themed');
  }
  // ...and the ones that DID leave that list must now be proven -- the other half
  // of the same contract, and the one a copy of the list would have missed.
  // Derived rather than copied: every requested surface that carries a token has,
  // by definition, left the list, so a stale copy here is precisely the drift.
  for (const id of INSPECTOR.ACCEPTANCE_SURFACES) {
    if (!present.has(id) || !INSPECTOR.SURFACE_TOKENS[id]) continue;
    assert.ok(final.observedEver.includes(id),
      id + ' left DECLARED_UNPROVEN_ACCEPTANCE and is rendered with a token, so it must ' +
      'classify as themed rather than silently reading UNPROVEN');
  }

  // 5. The tool must still REFUSE. The acceptance surfaces carry no token
  //    expectation, so a run that cannot open them is non-accepting BY
  //    DESIGN. A green here would mean the gate stopped gating.
  assert.strictEqual(final.accept, false,
    'watch accepted a run that proved nothing about the acceptance surfaces');
  assert.ok(final.unresolvedAcceptance.length > 0,
    'expected unresolved acceptance surfaces, got none');
  assert.strictEqual(result.code, 1,
    'non-accepting watch must exit 1, got ' + result.code);

  // 6. Privacy. Conversation text planted in the fixture must not appear in
  //    stdout or stderr on the way out.
  for (const s of SENTINELS) {
    assert.ok(!result.out.includes(s), 'watch leaked conversation text: ' + s);
    assert.ok(!result.err.includes(s), 'watch leaked conversation text to stderr: ' + s);
  }

  console.log('PASS: live CDP transport attaches to a real browser and completes a bounded watch');
  console.log('PASS: probe found all ' + rendered.length + ' rendered surfaces in the live document');
  console.log('PASS: ' + themed.length + ' token-bearing surfaces classified themed, 0 mismatched');
  console.log('PASS: the tool refuses to accept a run that proved nothing (exit ' + result.code +
    ', ' + final.unresolvedAcceptance.length + ' acceptance surfaces unresolved)');
  console.log('PASS: no conversation text emitted by the sanitizer');
}

main().catch(e => { console.error('FAILED: ' + (e && e.message || e)); process.exit(1); });
