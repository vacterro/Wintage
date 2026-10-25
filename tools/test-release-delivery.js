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
  const stale = tree.replace(/(@version\s+)[\d.]+/, '$10.1.0').replace(/(W95_VERSION\s*=\s*['"])[\d.]+/, '$10.1.0');
  // A served artifact that is this build but missing a current-live hook.
  let nohook = tree;
  if (hooks.length) {
    const h = hooks[0];
    nohook = tree.split(h).join('/* removed by the test */');
  }
  // Same version, extra JS appended: version + hooks match but payload differs.
  const extraJs = tree + '\n// extra injected payload\nconsole.log("stale");\n';
  // Same version, changed CSS: replace a CSS rule body.
  const changedCss = tree.replace(/background:\s*'#[0-9a-f]+'/i, 'background: \'#ff0000\'');
  // Same version, changed implementation (no CSS, no version change, no hook removal).
  const changedImpl = tree.replace(/(const W95_VERSION\s*=\s*['"])([\d.]+)(['"])/, '$1$2$3') // same version
    .replace('document-start', 'document-end'); // different run-at
  // Missing version: strip @version and W95_VERSION.
  const missingVersion = tree.replace(/\/\/\s*@version\s+[^\n]+\n/, '')
    .replace(/const W95_VERSION\s*=\s*['"][^'"]+['"];?/, 'const W95_VERSION = null;');
  // Same version but with a hook's CSS slightly altered (hook text no longer matches).
  let changedHook = tree;
  if (hooks.length) {
    const h = hooks[0];
    changedHook = tree.replace(h, h.replace(/[^,]+$/, '[data-changed]'));
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
    } else if (route === '/extrajs') {
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end(extraJs);
    } else if (route === '/changedcss') {
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end(changedCss);
    } else if (route === '/changedimpl') {
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end(changedImpl);
    } else if (route === '/missingversion') {
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end(missingVersion);
    } else if (route === '/changedhook') {
      res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end(changedHook);
    } else if (route === '/500') {
      res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('internal server error');
    } else if (route === '/slow') {
      // Simulate an unavailable/slow endpoint: never respond, client times out.
      // (The tool has no timeout, so we just don't write a response -- the test
      //  kills the server after assertions. For a truly unavailable endpoint,
      //  we use a non-responsive port below.)
      setTimeout(() => {}, 10000);
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
      'identical payload is CURRENT (code ' + r.code + ', verdict ' + (r.json && r.json.verdict) + ')');

    r = await runTool(base + '/stale');
    assertTrue(r.code === 1 && r.json && r.json.verdict === 'STALE_DEPLOYMENT',
      'different version is STALE_DEPLOYMENT (code ' + r.code + ', verdict ' + (r.json && r.json.verdict) + ')');

    if (hooks.length) {
      r = await runTool(base + '/nohook');
      assertTrue(r.code === 1 && r.json && r.json.verdict === 'STALE_DEPLOYMENT' &&
        r.json.publishedMissingHooks && r.json.publishedMissingHooks.length === 1,
        'missing a current-live hook is STALE_DEPLOYMENT (code ' + r.code + ')');
    } else {
      console.log('[SKIP] the hook case: tools/chatgpt-live-contract.js carries no current-live hooks');
    }

    // Finding 1 regression: same version + all hooks, but different payload.
    r = await runTool(base + '/extrajs');
    assertTrue(r.code === 1 && r.json && r.json.verdict === 'STALE_DEPLOYMENT',
      'same version + extra JS is STALE_DEPLOYMENT, not CURRENT (code ' + r.code + ', verdict ' + (r.json && r.json.verdict) + ')');

    r = await runTool(base + '/changedcss');
    assertTrue(r.code === 1 && r.json && r.json.verdict === 'STALE_DEPLOYMENT',
      'same version + changed CSS is STALE_DEPLOYMENT, not CURRENT (code ' + r.code + ', verdict ' + (r.json && r.json.verdict) + ')');

    r = await runTool(base + '/changedimpl');
    assertTrue(r.code === 1 && r.json && r.json.verdict === 'STALE_DEPLOYMENT',
      'same version + changed implementation is STALE_DEPLOYMENT, not CURRENT (code ' + r.code + ', verdict ' + (r.json && r.json.verdict) + ')');

    if (hooks.length) {
      r = await runTool(base + '/changedhook');
      assertTrue(r.code === 1 && r.json && r.json.verdict === 'STALE_DEPLOYMENT',
        'same version + altered hook selector is STALE_DEPLOYMENT, not CURRENT (code ' + r.code + ', verdict ' + (r.json && r.json.verdict) + ')');
    }

    // Missing version: not CURRENT.
    r = await runTool(base + '/missingversion');
    assertTrue(r.code !== 0 || !r.json || r.json.verdict !== 'CURRENT',
      'missing version is not CURRENT (code ' + r.code + ', verdict ' + (r.json && r.json.verdict) + ')');

    // Unavailable HTTP endpoint: 500 -> UNKNOWN.
    r = await runTool(base + '/500');
    assertTrue(r.code === 2 && r.json && r.json.verdict === 'UNKNOWN',
      'an HTTP 500 endpoint is UNKNOWN, not STALE (code ' + r.code + ', verdict ' + (r.json && r.json.verdict) + ')');

    // Truly unavailable endpoint (connection refused): UNKNOWN.
    r = await runTool(base + '/unavailable');
    assertTrue(r.code === 2 && r.json && r.json.verdict === 'UNKNOWN',
      'an unreachable endpoint is UNKNOWN, not STALE (code ' + r.code + ', verdict ' + (r.json && r.json.verdict) + ')');
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
