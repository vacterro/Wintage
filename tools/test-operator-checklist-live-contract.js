#!/usr/bin/env node
'use strict';
// Documentation contract gate: the live ChatGPT operator acceptance procedure
// (tools/operator-checklist-live-acceptance.md) against the REAL CLI contract
// in tools/inspect-web.js.
//
// WHY IT EXISTS. The checklist is prose a future edit can quietly ruin: delete
// `--full-session` from the documented command and the procedure still looks
// right, still runs, and still prints `accept: true` -- a ROUTE_SCOPED_DIAGNOSTIC
// dressed as a completed live-product acceptance. The CLI itself cannot notice:
// it has no idea which command the operator was told to run. This gate is that
// missing witness. It reads the doc and the CLI and requires the documented
// command to be the CLI's real full-session acceptance command, the documented
// predicates to be the fields the CLI actually emits, and the promotion rules
// to hold where they are claimed: fixture evidence and route-scoped success
// never become LIVE_PRODUCT_VERIFIED.
//
// The behavioural half reuses the R16 fixtures' shape (see tools/test-inspect-web.js
// R15/R16): the same route-scoped conversation-only and Settings-only sessions,
// the same mixed session, driven through the real aggregateWatch/watchVerdict --
// never a hand-written verdict, so this gate fails the moment the CLI contract
// itself changes under the documentation.
//
// The four RED controls are applied by mutating COPIES of the doc in a temp dir,
// never the real one.

const fs = require('fs');
const path = require('path');
const os = require('os');
const W = require('./inspect-web.js');

const DOC = path.join(__dirname, 'operator-checklist-live-acceptance.md');
const CLI = path.join(__dirname, 'inspect-web.js');

// The command the operator must be told to run: the CLI's explicit full-session
// acceptance mode, with the attribute probe and the machine-readable report.
const CANONICAL_WATCH = 'node tools/inspect-web.js watch chatgpt.com 900 --full-session --attribute --json';

// The predicates the checklist must name and the CLI must emit. Pinned here so
// the two are checked against each other rather than against this file's word.
const REQUIRED_PREDICATES = [
  'finished === true',
  'fullSession === true',
  'accept === true',
  'conversationRouteVisited === true',
  'settingsRouteVisited === true',
  'notAcceptingBecause'
];

// Flags the CLI's flag parser actually understands, read out of the source that
// implements them. A doc that names a flag this set lacks is broken prose.
function cliSupportedFlags(cliSrc) {
  const flags = new Set();
  const re = /flags\.has\('(--[a-z0-9-]+)'\)/g;
  let m;
  while ((m = re.exec(cliSrc))) flags.add(m[1]);
  return flags;
}

// Every inspect-web command line the doc contains, as tokens.
function documentedCommands(docText) {
  const out = [];
  const re = /node tools\/inspect-web\.js[^\n`]*/g;
  let m;
  while ((m = re.exec(docText))) out.push(m[0].trim());
  return out;
}

function watchCommands(docText) {
  return documentedCommands(docText).filter(c => /\bwatch\b/.test(c));
}

// The promotion rule, machine-readable: may this final report be published as
// LIVE_PRODUCT_VERIFIED? It may not, unless the CLI itself ran the FULL-session
// contract and every predicate the checklist names holds. A route-scoped success
// and a fixture-only success are both refused here, which is what makes them
// unpromotable by prose anywhere else in the repo.
function liveAcceptanceVerdict(finalReport) {
  if (!finalReport || typeof finalReport !== 'object') return false;
  if (finalReport.fullSession !== true) return false;          // route-scoped diagnostic
  if (finalReport.finished !== true) return false;
  if (finalReport.accept !== true) return false;
  if (Array.isArray(finalReport.notAcceptingBecause) && finalReport.notAcceptingBecause.length) return false;
  if (finalReport.conversationRouteVisited !== true) return false;
  if (finalReport.settingsRouteVisited !== true) return false;
  if (Array.isArray(finalReport.unresolvedAcceptance) && finalReport.unresolvedAcceptance.length) return false;
  if (Array.isArray(finalReport.neverObservedAcceptance) && finalReport.neverObservedAcceptance.length) return false;
  return true;
}

// ── documentation checks ────────────────────────────────────────────────────
// Returns the list of reasons the doc fails to describe the CLI contract. The
// real doc must produce none; the RED copies must produce at least one.
function checkDoc(docText, cliSrc) {
  const problems = [];
  const flags = cliSupportedFlags(cliSrc);

  // 1. The canonical full-session command is documented, verbatim.
  if (docText.indexOf(CANONICAL_WATCH) < 0) {
    problems.push('the documented live acceptance command is not the CLI full-session command: ' +
      CANONICAL_WATCH);
  }

  // 2. Every documented watch command is either the full-session command or is
  //    explicitly labelled a route-scoped diagnostic. The default CLI mode is
  //    route-scoped on purpose, so the doc may legitimately mention one; what
  //    it may not do is present one as the acceptance procedure.
  for (const cmd of watchCommands(docText)) {
    if (cmd.indexOf(CANONICAL_WATCH) === 0) continue;
    const window = docText.slice(Math.max(0, docText.indexOf(cmd) - 120), docText.indexOf(cmd));
    if (!/ROUTE_SCOPED|route-scoped/i.test(window)) {
      problems.push('a watch command is documented without --full-session and without identifying itself as a ROUTE_SCOPED_DIAGNOSTIC: ' + cmd);
    }
  }

  // 3. Every flag the doc hands the operator is a flag the CLI actually parses.
  for (const cmd of documentedCommands(docText)) {
    for (const f of (cmd.match(/--[a-z0-9-]+/g) || [])) {
      if (!flags.has(f)) problems.push('documented command uses an unsupported CLI flag ' + f + ': ' + cmd);
    }
  }

  // 4. The canonical command is parseable by the CLI's own shape: watch, a
  //    host, a bounded seconds value, the full-session mode.
  const shape = CANONICAL_WATCH.split(/\s+/);
  if (shape[2] !== 'watch' || shape[3] !== 'chatgpt.com' || !/^\d+$/.test(shape[4])) {
    problems.push('the canonical live command does not match the CLI grammar (host + seconds)');
  }
  if (!cliSrc.includes("flags.has('--full-session')")) {
    problems.push('the CLI source no longer parses --full-session; the documented contract is unreal');
  }
  if (!/fullSession:\s*!!fullSession/.test(cliSrc)) {
    problems.push('the CLI final report does not emit the fullSession predicate');
  }

  // 5. Each predicate the task requires is named in the doc AND emitted by the
  //    CLI's final report. Both directions: a doc predicate the CLI never
  //    prints is a promise the operator cannot check, and a CLI predicate the
  //    doc omits is an unchecked acceptance lever.
  for (const p of REQUIRED_PREDICATES) {
    const name = p.split(/\s/)[0];
    if (docText.indexOf(p) < 0) {
      problems.push('the checklist does not state the final-report predicate: ' + p);
    }
    if (!new RegExp(name + '\\s*:').test(cliSrc)) {
      problems.push('the CLI final report does not carry ' + name + ', which the checklist requires');
    }
  }

  // 6. The four verdict classes are named, with the promotion boundary intact:
  //    a route-scoped diagnostic is not a live acceptance, and fixture evidence
  //    is not live acceptance.
  for (const cls of ['ROUTE_SCOPED_DIAGNOSTIC', 'BROWSER_FIXTURE_VERIFIED',
                     'LIVE_PRODUCT_VERIFIED', 'NEEDS_OPERATOR_LIVE']) {
    if (docText.indexOf(cls) < 0) problems.push('the checklist does not name the verdict class ' + cls);
  }
  if (!/ROUTE_SCOPED_DIAGNOSTIC[^.]*is[^.]*not[^.]*live|never[^.]*completed live-product acceptance/i.test(docText.replace(/\s+/g, ' '))) {
    problems.push('the checklist does not declare that a ROUTE_SCOPED_DIAGNOSTIC is not a completed live-product acceptance');
  }
  if (docText.indexOf('Never claim live acceptance from the Chromium fixture gates alone') < 0) {
    problems.push('the checklist loses the fixture-vs-live boundary');
  }

  // 7. The fixture gate names are marked fixture evidence, never live evidence.
  for (const gate of ['test-chatgpt-assistant-content.js', 'test-chatgpt-viewport-coverage.js',
                      'test-provider-image-preservation.js']) {
    const at = docText.indexOf(gate);
    if (at < 0) continue;                       // not every layout must list them
    const near = docText.slice(Math.max(0, at - 400), at + 200);
    if (!/BROWSER_FIXTURE_VERIFIED|fixture/i.test(near)) {
      problems.push('the fixture gate ' + gate + ' is not identified as fixture-only evidence');
    }
  }
  if (docText.indexOf('They are BROWSER_FIXTURE_VERIFIED') < 0) {
    problems.push('the fixture gates are no longer explicitly marked BROWSER_FIXTURE_VERIFIED, so fixture evidence can be read as live acceptance');
  }

  return problems;
}

// ── the R16 fixture sessions, same shape as tools/test-inspect-web.js ────────
// Not a copy-paste of those fixtures by accident: the gate must judge the SAME
// sessions the CLI judge runs, so an inspector change that softens watchVerdict
// turns this red even when the documentation is untouched.
const W95_BG = 'rgb(28, 28, 32)';
function surface(over) {
  return Object.assign({
    id: 'x', label: 'x', selector: '#x', required: false,
    present: true, count: 1, visible: true,
    style: { backgroundColor: W95_BG, color: 'rgb(232, 226, 200)' },
    withoutWintage: null, vintageOwns: null, node: { tag: 'div' }
  }, over);
}
function report(surfaces, tokens) {
  return {
    url_host: 'chatgpt.com', route: '/c/:id', wintage: { stamped: true, sheets: 1 },
    // The same token table tools/test-inspect-web.js drives R15/R16 with --
    // the gate proves the DOCUMENTATION against the CLI's real judge, so the
    // fixtures it judges must be the fixtures that judge is proven on.
    tokens: tokens || {
      '--chat-background-color': W95_BG,
      '--color-token-side-bar-background': 'rgb(20, 20, 24)',
      '--composer-background-color': 'rgb(36, 34, 30)',
      '--user-message-background-color': 'rgb(44, 42, 36)',
      '--codeblock-background-color': 'rgb(12, 12, 16)',
      '--background': W95_BG,
      '--surfaceRaised': 'rgb(61, 55, 42)'
    },
    surfaces
  };
}
const valueFor = (id) => {
  const t = W.SURFACE_TOKENS[id];
  const name = Array.isArray(t) ? t[0] : t;
  return (report([]).tokens[name]) || W95_BG;
};
function onRoute(route, paintOf, skipIds) {
  const skip = new Set(skipIds || []);
  const conv = (s) => s.scope === W.SCOPE.CONVERSATION;
  const sett = (s) => s.scope === W.SCOPE.SETTINGS;
  const r = W.sanitizePageReport(report(W.SURFACES.map(s => {
    const applies = s.route
      ? s.route.test(route)
      : (conv(s) ? !W.isSettingsRoute(route) : (sett(s) ? W.isSettingsRoute(route) : true));
    if (!applies || skip.has(s.id)) {
      return surface({ id: s.id, label: s.label, selector: s.selector, present: false, count: 0, style: null, routeOnly: true });
    }
    return surface({
      id: s.id, label: s.label, selector: s.selector,
      required: s.contract === W.CONTRACT.ALWAYS,
      routeMatched: s.route ? true : undefined,
      style: { backgroundColor: paintOf(s) }
    });
  })));
  r.route = route;
  return r;
}
const chatOnly = W.aggregateWatch([onRoute('/c/:id', s => valueFor(s.id))]);
const settingsOnly = W.aggregateWatch([onRoute('/settings/general', s => valueFor(s.id))]);
const mixed = W.aggregateWatch([
  onRoute('/c/:id', s => valueFor(s.id)),
  onRoute('/settings/general', s => valueFor(s.id))
]);

// The CLI's final report, shaped exactly the way inspect-web.js prints it.
function finalReportFor(agg, fullSession) {
  const v = W.watchVerdict(agg, { fullSession: !!fullSession });
  return {
    finished: true,
    fullSession: !!fullSession,
    accept: v.accept,
    notAcceptingBecause: v.reasons,
    conversationRouteVisited: agg.conversationRouteVisited,
    settingsRouteVisited: agg.settingsRouteVisited,
    unresolvedAcceptance: agg.unresolvedAcceptance,
    neverObservedAcceptance: agg.neverObservedAcceptance
  };
}

let bad = 0;
function pass(label) { console.log('PASS: ' + label); }
function fail(label, detail) { console.error('FAIL: ' + label + (detail ? '\n       ' + detail : '')); bad++; }
function check(label, condition, detail) { condition ? pass(label) : fail(label, detail); }

function tempDoc(text) {
  const p = path.join(os.tmpdir(), 'operator-checklist-red-' + Math.random().toString(36).slice(2) + '.md');
  fs.writeFileSync(p, text);
  return p;
}

function main() {
  const docText = fs.readFileSync(DOC, 'utf8');
  const cliSrc = fs.readFileSync(CLI, 'utf8');

  // ── GREEN: the real doc describes the real CLI ────────────────────────────
  const problems = checkDoc(docText, cliSrc);
  check('the documented live acceptance command is the CLI full-session command, verbatim',
    problems.length === 0, problems.join('; '));
  check('and the full-session flag survives every parse of the CLI source',
    cliSupportedFlags(cliSrc).has('--full-session'),
    'the CLI parses no --full-session flag; the documented command cannot run');

  // ── positive controls: what stays legal ───────────────────────────────────
  // E. A route-scoped diagnostic remains legitimate work and still accepts.
  check('E a route-scoped conversation-only diagnostic remains legal and accepting',
    W.watchVerdict(chatOnly).accept === true && W.watchVerdict(settingsOnly).accept === true,
    JSON.stringify({ c: W.watchVerdict(chatOnly).reasons, s: W.watchVerdict(settingsOnly).reasons }));
  // ...and it cannot be promoted: the CLI marks it route-scoped and the
  // promotion rule refuses it.
  check('E a route-scoped success cannot be promoted to LIVE_PRODUCT_VERIFIED',
    liveAcceptanceVerdict(finalReportFor(chatOnly, false)) === false &&
    liveAcceptanceVerdict(finalReportFor(settingsOnly, false)) === false,
    'a route-scoped report was accepted as live acceptance');

  // F..H. The full-session contract, judged on the real fixtures.
  check('F a full session that visited both families with everything themed accepts',
    liveAcceptanceVerdict(finalReportFor(mixed, true)) === true,
    JSON.stringify(finalReportFor(mixed, true)));
  check('G a full session missing the Settings family refuses and names it',
    liveAcceptanceVerdict(finalReportFor(chatOnly, true)) === false &&
    finalReportFor(chatOnly, true).notAcceptingBecause.some(r => r.indexOf('Settings route family was never visited') >= 0),
    JSON.stringify(finalReportFor(chatOnly, true).notAcceptingBecause));
  check('H a full session missing the conversation family refuses and names it',
    liveAcceptanceVerdict(finalReportFor(settingsOnly, true)) === false &&
    finalReportFor(settingsOnly, true).notAcceptingBecause.some(r => r.indexOf('conversation route family was never visited') >= 0),
    JSON.stringify(finalReportFor(settingsOnly, true).notAcceptingBecause));

  // C, behavioural half: fixture-only evidence is refused by the same rule.
  check('C fixture-only evidence is refused by the promotion rule',
    liveAcceptanceVerdict({ finished: true, fullSession: false, accept: true,
      notAcceptingBecause: [], conversationRouteVisited: false, settingsRouteVisited: false,
      evidence_class: 'BROWSER_FIXTURE_VERIFIED' }) === false,
    'a fixture report was accepted as live acceptance');

  // ── RED controls: four mutations, each must fail the documentation gate ───
  // A. --full-session removed from the documented live command.
  const redA = tempDoc(docText.replace(CANONICAL_WATCH,
    'node tools/inspect-web.js watch chatgpt.com 900 --attribute --json'));
  check('RED A the gate fails when --full-session is removed from the documented live command',
    checkDoc(fs.readFileSync(redA, 'utf8'), cliSrc).length > 0,
    'the gate accepted a doc whose live command downgrades to a route-scoped diagnostic');
  fs.unlinkSync(redA);

  // B. The command replaced with an unsupported CLI flag.
  const redB = tempDoc(docText.replace(CANONICAL_WATCH,
    'node tools/inspect-web.js watch chatgpt.com 900 --full-session --attribute --json --super-flag'));
  check('RED B the gate fails when the documented command uses an unsupported CLI flag',
    checkDoc(fs.readFileSync(redB, 'utf8'), cliSrc).length > 0,
    'the gate accepted a doc naming a flag the CLI does not parse');
  fs.unlinkSync(redB);

  // C. Fixture-only evidence presented as LIVE_PRODUCT_VERIFIED.
  const redC = tempDoc(docText.replace(
    '- [ ] 7. The 3 Chromium fixture gates pass. They are BROWSER_FIXTURE_VERIFIED:',
    '- [ ] 7. The 3 Chromium fixture gates pass. They count as LIVE_PRODUCT_VERIFIED:'));
  check('RED C the gate fails when fixture-only evidence is presented as live-product verified',
    checkDoc(fs.readFileSync(redC, 'utf8'), cliSrc).length > 0,
    'the gate accepted a doc promoting fixture evidence to live acceptance');
  fs.unlinkSync(redC);

  // D. A route-scoped watch, without both route families, promoted to live.
  // Every occurrence is mutated: the predicate list under
  // "LIVE_PRODUCT_VERIFIED requires all of" names the same command, and
  // leaving one intact would let the doc pass on a stale copy.
  const redD = tempDoc(docText.split(CANONICAL_WATCH)
    .join('node tools/inspect-web.js watch chatgpt.com 900 --attribute --json')
    .replace("The bounded full-session acceptance pass runs",
      "The bounded route-scoped watch pass runs"));
  const redDProblems = checkDoc(fs.readFileSync(redD, 'utf8'), cliSrc);
  check('RED D the gate refuses a route-scoped watch promoted to a completed live acceptance',
    redDProblems.length > 0 && liveAcceptanceVerdict(finalReportFor(chatOnly, false)) === false,
    redDProblems.join('; ') || 'the doc gate passed and the report was still promotable');
  fs.unlinkSync(redD);

  // The RED mutations must actually have applied -- a mutation that matches
  // nothing would "pass" this gate by testing an unchanged copy.
  check('and the RED A/B/C/D anchors were all present before mutation',
    docText.indexOf(CANONICAL_WATCH) >= 0 &&
    docText.indexOf('BROWSER_FIXTURE_VERIFIED:') >= 0,
    'an anchor string moved; the RED controls above no longer test what they claim');

  if (bad) {
    console.error('\noperator-checklist contract gate: ' + bad + ' failure(s)');
    process.exit(1);
  }
  console.log('\noperator-checklist contract gate: PASS');
}

main();
