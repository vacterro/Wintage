#!/usr/bin/env node
// Deployed-artifact detector: is the userscript the browser INSTALLS the same
// build this checkout has?
//
// WHY THIS EXISTS. Defect 1 of the v1.36.6 report was not a selector defect. The
// published artifact at the README's own install URL was three versions behind
// the working tree, so the T-903 ChatGPT viewport fix had never been loaded by
// the reporting browser -- while the source, the fixtures, the parity gate and
// the local file all said it was fixed. Every static gate in this repository is
// green in that state, because they all read the WORKING TREE. The delivery path
// (commit -> push -> raw.githubusercontent.com) is the one link they never
// touched, and it is the link the user actually experiences.
//
// WHAT IT CHECKS. Version equality (the header `@version` and the internal
// `W95_VERSION` must agree with the tree in BOTH directions), and the
// current-live ChatGPT contract hooks from tools/chatgpt-live-contract.js, which
// are the pixels the reported defect was about. A published artifact MISSING the
// hooks is reported as STALE DEPLOYMENT -- the finding that changed the branch
// decision -- not as a source defect.
//
// WHY IT IS NOT IN THE BLOCKING SUITE. It needs the network and GitHub to be
// reachable. A repository gate that fails on a train, on a VPN-less box, or
// during a GitHub incident is a gate people learn to ignore, and tests/Run-Tests.ps1
// must stay deterministic. Run it deliberately, before and after a release, and
// on any bug report that claims a fix "did not work".
//
//   node tools/check-deployed-userscript.js            # human readable
//   node tools/check-deployed-userscript.js --json     # for scripts
//   node tools/check-deployed-userscript.js --url <u>  # another artifact
//
// EXIT: 0 = published artifact carries this checkout's build and contract.
//       1 = stale: the browser is not running this code.
//       2 = the artifact could not be fetched (unknown, NOT a source defect).

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const DEFAULT_URL = 'https://gitlab.com/vacuum34/wintage/-/raw/main/wintage.user.js';
const argv = process.argv.slice(2);
const AS_JSON = argv.includes('--json');
const urlIdx = argv.indexOf('--url');
const URL = urlIdx >= 0 && argv[urlIdx + 1] ? argv[urlIdx + 1] : DEFAULT_URL;

function localVersion(src) {
  const header = /\/\/\s*@version\s+([^\s]+)/.exec(src);
  const internal = /const W95_VERSION\s*=\s*['"]([^'"]+)['"]/.exec(src);
  return { header: header ? header[1] : null, internal: internal ? internal[1] : null };
}

function sha256(buf) {
  return crypto.createHash('sha256').update(buf).digest('hex');
}

async function fetchBytes(url) {
  const res = await fetch(url, { redirect: 'follow' });
  if (!res.ok) throw new Error('HTTP ' + res.status + ' from ' + url);
  return Buffer.from(await res.arrayBuffer());
}

async function main() {
  const treePath = path.join(__dirname, '..', 'wintage.user.js');
  const treeBuf = fs.readFileSync(treePath);
  const tree = treeBuf.toString('utf8');
  const tv = localVersion(tree);
  const treeDigest = sha256(treeBuf);

  let contract = null;
  try {
    contract = require('./chatgpt-live-contract.js');
  } catch (e) {
    contract = null;
  }
  const hooks = contract ? contract.CURRENT_LIVE_HOOKS.map(h => h.css) : [];

  let publishedBuf = null;
  let fetchError = null;
  try {
    publishedBuf = await fetchBytes(URL);
  } catch (e) {
    fetchError = String(e && e.message ? e.message : e);
  }

  const report = {
    url: URL,
    tree: tv,
    treeFile: treePath,
    treeDigest: treeDigest,
    publishedDigest: null,
    publishedVersion: null,
    publishedMissingHooks: [],
    publishedPresentHooks: [],
    verdict: 'UNKNOWN',
    detail: ''
  };

  if (!publishedBuf) {
    report.verdict = 'UNKNOWN';
    report.detail = 'artifact could not be fetched: ' + fetchError
      + ' -- this says nothing about the source; a build can be perfectly correct and unreadable.';
    return finish(report, 2);
  }

  const published = publishedBuf.toString('utf8');
  const publishedDigest = sha256(publishedBuf);
  report.publishedDigest = publishedDigest;

  const pv = localVersion(published);
  report.publishedVersion = pv;
  for (const h of hooks) {
    if (published.includes(h)) report.publishedPresentHooks.push(h);
    else report.publishedMissingHooks.push(h);
  }

  const sameVersion = pv.header && tv.header && pv.header === tv.header && pv.internal === tv.internal;
  const contractComplete = report.publishedMissingHooks.length === 0;
  const samePayload = publishedDigest === treeDigest;

  if (samePayload) {
    report.verdict = 'CURRENT';
    report.detail = 'the install URL serves byte-identical payload (sha256 '
      + publishedDigest.substring(0, 16) + '…), version ' + (pv.header || '(none)')
      + ' with all ' + hooks.length + ' current-live hook(s) present.';
    return finish(report, 0);
  }

  report.verdict = 'STALE_DEPLOYMENT';
  const bits = [];
  if (!sameVersion) {
    bits.push('install URL serves ' + (pv.header || '(none)')
      + ' while this tree is ' + (tv.header || '(none)')
      + (pv.header !== pv.internal ? ' (published header/internal DISAGREE: ' + pv.header + '/' + pv.internal + ')' : '')
      + (tv.header !== tv.internal ? ' (tree header/internal DISAGREE: ' + tv.header + '/' + tv.internal + ')' : ''));
  }
  if (!contractComplete) {
    bits.push('the published artifact lacks ' + report.publishedMissingHooks.length + ' current-live hook(s): '
      + report.publishedMissingHooks.join(' | '));
  }
  if (sameVersion && contractComplete && !samePayload) {
    bits.push('version and hooks match but the deliverable payload differs (sha256 tree '
      + treeDigest.substring(0, 16) + '… ≠ published ' + publishedDigest.substring(0, 16) + '…)');
  }
  report.detail = bits.join('; ')
    + ' -- the browser runs the PUBLISHED build, so a source-side fix cannot be live. '
    + 'This is a delivery gap (commit and push), not proof of a selector defect.';
  return finish(report, 1);
}

function finish(report, code) {
  if (AS_JSON) {
    console.log(JSON.stringify(report, null, 2));
  } else {
    console.log('deployed userscript check');
    console.log('  install URL : ' + report.url);
    console.log('  tree file   : ' + report.treeFile);
    console.log('  tree        : @version ' + report.tree.header + ' / W95_VERSION ' + report.tree.internal);
    console.log('  published   : ' + (report.publishedVersion
      ? '@version ' + report.publishedVersion.header + ' / W95_VERSION ' + report.publishedVersion.internal
      : '(not fetched)'));
    console.log('  contract    : ' + report.publishedPresentHooks.length + ' present, '
      + report.publishedMissingHooks.length + ' missing');
    console.log('  verdict     : ' + report.verdict);
    console.log('  detail      : ' + report.detail);
  }
  // NOT process.exit(): on Windows this file exits while undici still holds the
  // fetch socket, and a hard exit then trips a libuv assertion that replaces the
  // verdict's exit code with 127. Setting the code and returning lets Node close
  // the socket on its own, so the caller sees the verdict it was promised.
  process.exitCode = code;
  return code;
}

main().catch(e => {
  console.error('deployed userscript check: fatal -- ' + (e && e.stack ? e.stack : e));
  process.exitCode = 2;
});
