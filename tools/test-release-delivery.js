#!/usr/bin/env node
// Unit test for the delivery detector the release now runs (T-983).
//
// The detector under test: tools/check-deployed-userscript.js
//
// The detector was written for the network: it fetches the artifact the
// browser installs. A suite gate must not need the network, so this test
// serves the SAME detector from a local HTTP server and checks the three
// verdicts the release acts on:
//   0 CURRENT          - the served artifact IS this build
//   1 STALE_DEPLOYMENT - the served artifact is NOT this build
//   2 UNKNOWN          - the artifact could not be fetched
// Nothing here leaves the machine.

const fs = require('fs');
const http = require('http');
const path = require('path');
const { spawn } = require('child_process');

const TOOL = path.join(__dirname, 'check-deployed-userscript.js');
const TREE = path.join(__dirname, '..', 'wintage.user.js');
let failures = 0;
let checks = 0;

function assertTrue(cond, label) {
  checks++;
  if (cond) {
    console.log('[PASS] ' + label);
  } else {
    failures++;
    console.log('[FAIL] ' + label);
  }
}

function runTool(url) {
  return new Promise(resolve => {
    const child = spawn(process.execPath, [TOOL, '--json', '--url', url], { encoding: 'utf8' });
    let out = '';
    let err = '';
    child.stdout.on('data', d => { out += d; });
    child.stderr.on('data', d => { err += d; });
    child.on('close', code => {
      let json = null;
      try { json = JSON.parse(out); } catch (e) { /* reported by the caller */ }
      resolve({ code, out, err, json });
    });
  });
}

async function main() {
  const tree = fs.readFileSync(TREE, 'utf8');
  let contract = null;
  try {
    contract = require('./chatgpt-live-contract.js');
  } catch (e) {
    contract = null;
  }
  const hooks = contract ? contract.CURRENT_LIVE_HOOKS.map(h => h.css) : [];

  // A served artifact that is a DIFFERENT build: the version does not match.
  const stale = tree.replace(/(@version\s+)[\d.]+/, '$10.0.1').replace(/(W95_VERSION\s*=\s*['"])[\d.]+/, '$10.0.1');
  // A served artifact that is this build but missing a current-live hook.
  let nohook = tree;
  if (hooks.length) {
    const h = hooks[0];
    nohook = tree.split(h).join('/* removed by the test */');
  }

  const server = http.createServer((req, res) => {
    const route = (req.url || '/').split('?')[0];
    if (route === '/current') {
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end(tree);
    } else if (route === '/stale') {
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end(stale);
    } else if (route === '/nohook') {
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end(nohook);
    } else {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('not found');
    }
  });

  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  const base = 'http://127.0.0.1:' + port;

  try {
    let r = await runTool(base + '/current');
    assertTrue(r.code === 0 && r.json && r.json.verdict === 'CURRENT',
      'the served build that IS this tree is CURRENT (code ' + r.code + ', verdict ' + (r.json && r.json.verdict) + ')');

    r = await runTool(base + '/stale');
    assertTrue(r.code === 1 && r.json && r.json.verdict === 'STALE_DEPLOYMENT',
      'a served artifact of another build is STALE_DEPLOYMENT (code ' + r.code + ', verdict ' + (r.json && r.json.verdict) + ')');

    if (hooks.length) {
      r = await runTool(base + '/nohook');
      assertTrue(r.code === 1 && r.json && r.json.verdict === 'STALE_DEPLOYMENT' &&
        r.json.publishedMissingHooks && r.json.publishedMissingHooks.length === 1,
        'a served artifact missing a current-live hook is STALE_DEPLOYMENT (code ' + r.code + ')');
    } else {
      console.log('[SKIP] the hook case: tools/chatgpt-live-contract.js carries no current-live hooks');
    }

    r = await runTool(base + '/missing');
    assertTrue(r.code === 2 && r.json && r.json.verdict === 'UNKNOWN',
      'an artifact that cannot be fetched is UNKNOWN, not STALE (code ' + r.code + ', verdict ' + (r.json && r.json.verdict) + ')');
  } finally {
    await new Promise(resolve => server.close(resolve));
  }

  console.log('');
  if (failures > 0) {
    console.log('TESTS FAILED (' + failures + ' of ' + checks + ' checks)');
    process.exitCode = 1;
  } else {
    console.log('ALL TESTS PASSED (' + checks + ' checks)');
    process.exitCode = 0;
  }
}

main();
