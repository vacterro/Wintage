#!/usr/bin/env node
'use strict';

// RED controls for the live ChatGPT inspector (tools/inspect-web.js).
//
// The tool this guards is a diagnostic that only runs against a signed-in page,
// so the offline suite can never exercise it directly -- which is exactly the
// condition under which a diagnostic silently rots. So the logic a wrong result
// would come from (classify, sanitize, dedupe, response validation) is exported
// and driven here with fixtures: a change that would make the live run report a
// false PASS fails offline, on every suite run.
//
// Every control is written to FAIL against the obvious broken version: a
// swallowed CDP error, a filter-instead-of-rebuild privacy boundary, a Set that
// is never checked, an absent-selector branch that returns quietly.

const fs = require('fs');
const path = require('path');
const W = require('./inspect-web.js');

let bad = 0;
function pass(label) { console.log('PASS: ' + label); }
function fail(label, detail) { console.error('FAIL: ' + label + (detail ? '\n       ' + detail : '')); bad++; }
function check(label, condition, detail) { condition ? pass(label) : fail(label, detail); }

const W95_BG = 'rgb(28, 28, 32)';
const STOCK_BG = 'rgb(31, 41, 55)';   // a stock slate, i.e. a leak

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
    tokens: Object.assign({
      '--chat-background-color': W95_BG,
      '--color-token-side-bar-background': 'rgb(20, 20, 24)',
      '--composer-background-color': 'rgb(36, 34, 30)',
      '--user-message-background-color': 'rgb(44, 42, 36)',
      '--codeblock-background-color': 'rgb(12, 12, 16)',
      '--background': W95_BG,
      // An open dialog on the live 2026-10-04 tab computed to rgb(61, 55, 42).
      '--surfaceRaised': 'rgb(61, 55, 42)'
    }, tokens || {}),
    surfaces: surfaces
  };
}

function clone(r) { return JSON.parse(JSON.stringify(r)); }

async function main() {
  // ── R1: a missing REQUIRED live selector is reported ────────────────────
  // The obvious broken version returns an empty surfaces array when nothing
  // matched, which renders as "no mismatches" -- the same false PASS the
  // offline gate was rewritten to stop producing.
  {
    const r = W.sanitizePageReport(report([
      surface({ id: 'sidebar', selector: '#app-shell-sidebar', required: true, present: false, count: 0, style: null })
    ]));
    const s = W.summarize(r);
    check('R1 missing required selector is reported as MISSING',
      s.missing.length === 1 && s.missing[0].id === 'sidebar',
      'got ' + JSON.stringify(s.missing) + ' / mismatches ' + JSON.stringify(s.mismatches));
    check('R1 a missing required selector is not silently counted as observed',
      s.observed.length === 0 && s.unproven.length === 0);
    check('R1 the render names the missing contract by selector',
      /MISSING ALWAYS-REQUIRED/.test(W.renderConsole(r, s)) && /#app-shell-sidebar/.test(W.renderConsole(r, s)));
  }

  // …but an OPTIONAL surface that is absent costs nothing, or a fifteen-minute
  // watch pass would drown its operator in "absent" lines.
  {
    const r = W.sanitizePageReport(report([
      surface({ id: 'dialog', present: false, count: 0, style: null })
    ]));
    const s = W.summarize(r);
    check('R1b an absent optional surface is not a finding',
      s.missing.length === 0 && s.mismatches.length === 0 && s.unproven.length === 0);
  }

  // ── R2: an observed surface on a stock colour is a MISMATCH ──────────────
  {
    const r = W.sanitizePageReport(report([
      surface({ id: 'sidebar', selector: '#app-shell-sidebar', style: { backgroundColor: STOCK_BG } })
    ]));
    const s = W.summarize(r);
    check('R2 a stock computed surface is reported as MISMATCH',
      s.mismatches.length === 1 && s.mismatches[0].id === 'sidebar',
      JSON.stringify(s.mismatches));
    check('R2 the mismatch names the offending value and the token',
      /rgb\(31, 41, 55\)/.test(s.mismatches[0].why) && /--color-token-side-bar-background/.test(s.mismatches[0].why),
      s.mismatches[0].why);
    check('R2 the console render surfaces the mismatch, not just the JSON',
      /MISMATCH/.test(W.renderConsole(r, s)));
  }

  // A surface with no token expectation must be UNPROVEN, never "themed".
  // Calling it themed is the exact blindness the ticket names: a gate that only
  // knows what it expected passes on whatever it was shown.
  //
  // The surface is picked from the matrix rather than named. It used to be `menu`,
  // which stopped working on 2026-10-04 for the right reason: menu left
  // DECLARED_UNPROVEN_ACCEPTANCE and gained the product's own overlay token, so it
  // is now falsifiable rather than unprovable. A hard-coded id here would have kept
  // testing a case that no longer exists while saying nothing about the case that
  // does.
  {
    const noToken = W.SURFACES.find(x => !W.SURFACE_TOKENS[x.id] &&
      !W.DECLARED_UNPROVEN_ACCEPTANCE.includes(x.id));
    check('R2b the matrix still contains a surface with no token expectation to test',
      !!noToken, 'every surface now carries a token; this check needs a new subject');
    if (noToken) {
      const r = W.sanitizePageReport(report([
        surface({ id: noToken.id, selector: noToken.selector, style: { backgroundColor: W95_BG } })
      ]));
      const s = W.summarize(r);
      check('R2b a surface with no token expectation is UNPROVEN, not themed',
        s.unproven.length === 1 && s.unproven[0].id === noToken.id && s.mismatches.length === 0,
        JSON.stringify(s));
    }
  }

  // An unresolvable token is UNPROVEN too, not a pass.
  {
    const r = W.sanitizePageReport(report([
      surface({ id: 'composer-root', required: true, style: { backgroundColor: W95_BG } })
    ], { '--composer-background-color': null }));
    const s = W.summarize(r);
    check('R2c an unresolved token leaves the surface UNPROVEN, not passing',
      s.unproven.length === 1 && s.mismatches.length === 0,
      JSON.stringify(s));
  }

  // The happy path must still pass, or R1/R2 prove only that everything fails.
  {
    const r = W.sanitizePageReport(report([
      surface({ id: 'composer-root', required: true, style: { backgroundColor: 'rgb(36, 34, 30)' } })
    ]));
    const s = W.summarize(r);
    check('R2d a surface on the live token value is themed',
      s.observed.length === 1 && s.observed[0].state === 'themed' && s.mismatches.length === 0,
      JSON.stringify(s));
  }

  // ── R3: repeated identical observations are deduplicated ─────────────────
  {
    const seen = new Set();
    const r = report([surface({ id: 'sidebar', style: { backgroundColor: W95_BG } })]);
    const first = W.collectUnique(seen, W.sanitizePageReport(clone(r)));
    const second = W.collectUnique(seen, W.sanitizePageReport(clone(r)));
    const third = W.collectUnique(seen, W.sanitizePageReport(clone(r)));
    check('R3 the first observation is fresh', first.fresh.length === 1 && first.duplicate === false);
    check('R3 identical re-observations are suppressed', second.fresh.length === 0 && second.duplicate === true);
    check('R3 the seen-set does not grow on duplicates', seen.size === 1 && third.total === 1);

    // A real change is NOT suppressed, or dedupe becomes a filter that hides
    // the one state an operator navigated to see.
    const moved = W.sanitizePageReport(report([
      surface({ id: 'sidebar', style: { backgroundColor: STOCK_BG } })
    ]));
    const fourth = W.collectUnique(seen, moved);
    check('R3 a changed surface is not suppressed', fourth.fresh.length === 1 && seen.size === 2);

    // A route change alone is a distinct observation (Settings is a route).
    const settings = W.sanitizePageReport(clone(r));
    settings.route = '/settings/general';
    const fifth = W.collectUnique(seen, settings);
    check('R3 a route change is a distinct observation', fifth.fresh.length === 1 && seen.size === 3);
  }

  // ── R4: sensitive text cannot leave the tool ─────────────────────────────
  // The sanitizer must REBUILD from an allowlist. A blacklist that removed a
  // known-bad key would still pass this, so the fixture also uses a key nobody
  // has ever heard of and a secret smuggled into a value.
  {
    const SECRET = 'my secret conversation about the merger with acme';
    const hostile = {
      url_host: 'chatgpt.com', route: '/c/:id',
      wintage: { stamped: true, sheets: 1 },
      tokens: { '--chat-background-color': W95_BG, ['--leak:' + SECRET]: SECRET },
      surfaces: [{
        id: 'user-message', label: 'user message bubble', required: true, present: true, count: 1,
        text: SECRET,
        innerText: SECRET,
        textContent: SECRET,
        value: SECRET,
        neverHeardOfThisKey: SECRET,
        node: { tag: 'div', id: 'msg', role: 'article', title: SECRET, 'aria-label': SECRET },
        style: { backgroundColor: W95_BG, content: '"' + SECRET + '"' },
        withoutWintage: null, vintageOwns: null
      }]
    };
    const clean = W.sanitizePageReport(hostile);
    const serialised = JSON.stringify(clean);
    check('R4 no sensitive value survives sanitization', !serialised.includes(SECRET),
      'leaked as: ' + serialised.slice(0, 400));
    check('R4 the structural keys that DO survive are the ones theming needs',
      clean.surfaces[0].node.id === 'msg' && clean.surfaces[0].node.role === 'article' &&
      clean.surfaces[0].style.backgroundColor === W95_BG,
      JSON.stringify(clean.surfaces[0].node));
    check('R4 a hostile token key is dropped, not truncated',
      !Object.keys(clean.tokens).some(k => k.includes('leak')));

    // A long conversation title is a plausible nav entry, and aria-label is
    // where it lives, so it must be named as never-emitted rather than merely
    // left out today.
    check('R4 attributes that can carry user content are named as never-emitted',
      ['aria-label', 'title'].every(k => W.NEVER_EMITTED_NODE_KEYS.includes(k)) &&
      !W.NEVER_EMITTED_NODE_KEYS.some(k => Object.keys(clean.surfaces[0].node).includes(k)),
      JSON.stringify(W.NEVER_EMITTED_NODE_KEYS));

    // The in-page half must never ask for text in the first place.
    const src = fs.readFileSync(path.join(__dirname, 'inspect-web.js'), 'utf8');
    const expr = W.buildProbeExpression(W.SURFACES, { attribute: false });
    check('R4 the probe expression never reads text from the page',
      !/textContent|innerText|\.value\b/.test(expr), 'probe asked for page text');
    check('R4 the probe never requests a user-content attribute',
      !W.NEVER_EMITTED_NODE_KEYS.some(k => new RegExp("'" + k + "'").test(expr)),
      'probe requested a user-content attribute');
    // There are TWO privacy boundaries: the allowlist inside the page and the
    // rebuild in Node. They must be the SAME list. If the in-page one widens,
    // text crosses into the page report before Node ever sees it -- and a
    // Node-side filter would then quietly cover for it, which is precisely the
    // single-boundary failure this test exists to prevent.
    const inPage = /var ALLOWED = \[([^\]]*)\]/.exec(expr);
    const inPageKeys = inPage ? inPage[1].split(',').map(k => k.trim().replace(/^'|'$/g, '')).filter(Boolean) : [];
    const expectedKeys = ['id', 'role', 'data-testid', 'data-w95', 'data-w95-ver', 'aria-pressed',
      'aria-selected', 'aria-expanded', 'aria-haspopup', 'aria-modal', 'data-state', 'contenteditable'];
    check('R4 the in-page attribute allowlist is exactly the exported one',
      inPageKeys.length === expectedKeys.length && expectedKeys.every(k => inPageKeys.includes(k)),
      'in page: ' + inPageKeys.join(', '));
    check('R4 the in-page allowlist names nothing that can carry user content',
      !W.NEVER_EMITTED_NODE_KEYS.some(k => inPageKeys.includes(k)),
      'in page: ' + inPageKeys.join(', '));
    check('R4 the tool never calls a cookie/storage/credential CDP domain',
      !/getAllCookies|getCookies|localStorage|sessionStorage|DOMStorage|extraInfo|Authorization/i.test(src),
      'tool touched a credential-bearing CDP domain');
  }

  // ── R5: malformed CDP responses fail loudly, never as a false PASS ───────
  {
    const bad = [
      ['no reply at all', undefined],
      ['null reply', null],
      ['reply with no result object', {}],
      ['reply with a null result', { result: null }],
      ['reply with an empty result', { result: {} }],
      ['an errored result value', { result: { type: 'object', subtype: 'error' } }],
      ['a reply whose value is missing', { result: { type: 'undefined' } }]
    ];
    const outcomes = [];
    for (const [label, reply] of bad) {
      const cdp = { send: () => Promise.resolve(reply) };
      outcomes.push([
        label,
        W.evaluate(cdp, '1').then(() => ({ ok: true }), e => ({ ok: false, msg: e.message }))
      ]);
    }
    const transport = W.evaluate({ send: () => Promise.reject(new Error('websocket closed')) }, '1')
      .then(() => ({ ok: true }), e => ({ ok: false, msg: e.message }));
    const settled = await Promise.all(outcomes.map(o => o[1]).concat([transport]));
    const messages = outcomes.map((o, i) => o[0] + ' -> ' + (settled[i].ok ? 'RESOLVED' : settled[i].msg));
    const named = settled.filter(s => !s.ok && /Malformed CDP response/.test(s.msg)).length;

    check('R5 every malformed CDP reply is refused, not resolved as an empty report',
      settled.slice(0, bad.length).every(s => !s.ok),
      messages.join(' | '));
    check('R5 the refusal names the CDP method, so the operator knows what broke',
      named === bad.length, named + '/' + bad.length + ' named :: ' + messages.join(' | '));
    check('R5 a closed transport rejects with a named cause',
      !settled[settled.length - 1].ok && /Runtime\.evaluate failed/.test(settled[settled.length - 1].msg),
      JSON.stringify(settled[settled.length - 1]));

    // An in-page throw must surface the page's own message, not "no findings".
    const thrown = await W.evaluate(
      { send: () => Promise.resolve({ exceptionDetails: { text: 'Uncaught', exception: { description: 'TypeError: getComputedStyle is not a function' } } }) },
      '1'
    ).then(() => null, e => e.message);
    check('R5 an in-page throw is reported as a throw',
      thrown !== null && /TypeError: getComputedStyle/.test(thrown), String(thrown));

    // The report shape itself: sanitize must refuse a non-report rather than
    // coerce it into an empty, all-clear report.
    const rejects = [undefined, null, 'nope', {}, { surfaces: null }, []];
    let refusedReports = 0;
    for (const r of rejects) {
      try { W.sanitizePageReport(r); } catch (e) { refusedReports++; }
    }
    check('R5 sanitizePageReport refuses a malformed report', refusedReports === rejects.length,
      refusedReports + '/' + rejects.length + ' refused');
    const junk = W.sanitizePageReport({ surfaces: [null, 7, { noId: true }] });
    check('R5 unusable surface entries are dropped, and the report is still shaped',
      junk.surfaces.length === 0 && Array.isArray(junk.surfaces));
  }

  // ── R6: cascade attribution reads the site, not the theme ────────────────
  {
    const owns = { backgroundColor: true, overflowY: false, maxHeight: false };
    const r = W.sanitizePageReport(report([
      surface({
        id: 'code-block', selector: '[data-markdown-copy="code-block"]',
        style: { backgroundColor: W95_BG, overflowY: 'auto', maxHeight: '400px' },
        withoutWintage: { backgroundColor: STOCK_BG, overflowY: 'auto', maxHeight: '400px' },
        vintageOwns: owns
      })
    ]));
    const s = r.surfaces[0] || {};
    // Captured once: the attribution map is read by key from here on, so a
    // surface with no attribution at all fails as an empty map rather than as
    // a crash partway through the block.
    const vo = s.vintageOwns || {};
    const layoutKeys = ['overflowY', 'overflowX', 'maxHeight', 'height', 'position'];
    check('R6 the sanitizer carries the attribution map through', Object.keys(vo).length > 0,
      JSON.stringify(s));
    check('R6 a themed surface is recorded as owned by Wintage', vo.backgroundColor === true,
      JSON.stringify(vo));
    check('R6 unchanged values with Wintage off are recorded as NOT owned by Wintage',
      vo.overflowY === false && vo.maxHeight === false, JSON.stringify(vo));
    // Acceptance item: code-block scrolling stays ChatGPT's. Prove it from the
    // report rather than from the source, since the source cannot see the site.
    const layoutOwnedByWintage = layoutKeys.filter(k => vo[k] === true);
    check('R6 the code container reports no layout property owned by Wintage',
      layoutOwnedByWintage.length === 0, 'Wintage owns ' + layoutOwnedByWintage.join(', '));
    // A stock colour that survives with Wintage switched off is a leak, and it
    // must still be a MISMATCH on a run that recorded no attribution at all.
    const unattributed = W.sanitizePageReport(report([
      surface({ id: 'code-block', style: { backgroundColor: STOCK_BG } })
    ]));
    check('R6 a leak is still a MISMATCH when attribution is unavailable',
      W.summarize(unattributed).mismatches.length === 1,
      JSON.stringify(W.summarize(unattributed)));
    check('R6 the layout read-back survives sanitization',
      unattributed.surfaces[0] && unattributed.surfaces[0].vintageOwns === null);
    // A report that claims a verdict without having switched Wintage off is
    // weaker than it looks, so the mode travels with the evidence.
    const attributed = W.sanitizePageReport(Object.assign(clone(report([])), { attribute: true }));
    const plain = W.sanitizePageReport(Object.assign(clone(report([])), { attribute: false }));
    check('R6 the report states whether the cascade was actually attributed',
      attributed.attribute === true && plain.attribute === false,
      'attribute=' + attributed.attribute + '/' + plain.attribute);
    // …and a run without --attribute must never invent an ownership map.
    check('R6 an unattributed run reports no ownership map',
      plain.surfaces.every(s => s.vintageOwns === null), 'ownership map present without attribution');
    // The probe is a generated string, so its attribution contract is asserted
    // on the generated text -- and the mutation gate proves this bites. The
    // second half matters as much as the first: attribution switches the
    // theme's stylesheets off, so it must be opt-in and never run on a poll.
    const attrExpr = W.buildProbeExpression(W.SURFACES, { attribute: true });
    const plainExpr = W.buildProbeExpression(W.SURFACES, { attribute: false });
    check('R6 the probe builds an ownership map when attribution is requested',
      /rec\.vintageOwns = ownsMap/.test(attrExpr) && /s\.disabled = true/.test(attrExpr),
      'attribution probe does not toggle and compare');
    check('R6 attribution is opt-in: a plain poll never switches the theme off',
      /var ATTRIBUTE = false/.test(plainExpr) && /if \(ATTRIBUTE\) \{/.test(plainExpr),
      'a plain poll would switch Wintage stylesheets off');
  }

  // ── R7: the matrix is a probe list, not an assumption ────────────────────
  {
    const ids = W.SURFACES.map(s => s.id);
    check('R7 surface ids are unique', new Set(ids).size === ids.length);
    check('R7 the matrix still covers the full-page Settings surface',
      W.SURFACES.some(s => s.id === 'settings-page' && !!s.route) &&
      W.SURFACES.some(s => s.id === 'settings-nav' && !!s.route),
      'the full-page Settings surface or its navigation is missing from the matrix');
    check('R7 the code block is probed for the layout ChatGPT owns',
      W.SURFACES.some(s => s.id === 'code-block' && W.LAYOUT_PROPS.every(p => (s.props || []).includes(p))),
      'code-block does not record overflow/maxHeight/height');
    check('R7 menus, popovers and dialogs are all in the matrix',
      ['menu', 'popover', 'dialog', 'listbox'].every(id => ids.includes(id)));
    check('R7 every required surface names a selector',
      W.SURFACES.filter(s => s.required).every(s => typeof s.selector === 'string'),
      'a required surface has no selector');
    // No class-fragment selector may enter the matrix either: a probe built on
    // `[class*="..."]` teaches the next person that generated classes are stable.
    const fragments = W.SURFACES
      .flatMap(s => (s.selector || '').split(',').map(x => x.trim()))
      .filter(Boolean)
      .filter(x => /\[class\s*[~^$*|]?=/i.test(x));
    check('R7 no class-fragment selector in the live matrix', fragments.length === 0, fragments.join(', '));
    // The expectations must name tokens Wintage really declares for ChatGPT.
    // Otherwise the live gate compares a surface against a variable nobody sets
    // and reports every chat as broken -- or, worse, is edited to expect nothing.
    // Read the sheet ChatGPT actually RECEIVES, not GLOBAL_CSS: at runtime
    // ACTIVE_GLOBAL_CSS routes ChatGPT to CHATGPT_FAST_CSS, so validating the
    // universal sheet here would assert against CSS that never reaches the page
    // -- the same wrong-stylesheet defect that kept the ChatGPT shell gate green
    // while the live workspace was stock.
    const user = fs.readFileSync(path.join(__dirname, '..', 'wintage.user.js'), 'utf8');
    const marker = 'const CHATGPT_FAST_CSS = `';
    const cssStart = user.indexOf(marker) + marker.length;
    const css = user.slice(cssStart, cssStart + /\n[ \t]*`;/.exec(user.slice(cssStart)).index);
    const declared = new Set([...css.matchAll(/(--[a-z0-9-]+)\s*:\s*\$\{T\./gi)].map(m => m[1]));
    const expected = [...new Set(Object.values(W.SURFACE_TOKENS))];
    const undeclared = expected.filter(t => !declared.has(t));
    check('R7 every token the live matrix expects is one Wintage declares on the active ChatGPT stylesheet',
      undeclared.length === 0,
      'not declared in CHATGPT_FAST_CSS: ' + undeclared.join(', '));
    check('R7 the live expectations cover the chat surface, sidebar, composer, user and code tokens',
      ['--chat-background-color', '--color-token-side-bar-background', '--composer-background-color',
        '--user-message-background-color', '--codeblock-background-color']
        .every(t => expected.includes(t)),
      expected.join(', '));
  }

  // ── R8: target metadata cannot leak either ───────────────────────────────
  // The in-page allowlist covers the REPORT. It cannot cover a CDP target, whose
  // title on chatgpt.com IS the conversation name and whose url carries the
  // conversation/project id. Four output paths used to print one raw. A
  // blacklist here would be decoration, so every fixture below is a DIFFERENT
  // shape of leak and the assertion is on the absence of the secret, not on the
  // presence of a particular redaction.
  {
    const TITLE_SECRET = 'Q3 merger talking points';
    const URL_SECRET = 'hunter2';
    const FRAGMENT_SECRET = 'draft-untitled-9';
    const CONV = '9f8b7a6c-1111-2222-3333-444455556666';
    const HOSTILE = [
      { type: 'page', title: TITLE_SECRET, url: 'https://chatgpt.com/c/' + CONV },
      { type: 'page', title: TITLE_SECRET, url: 'https://chatgpt.com/g/ZmFrZS1wcm9qZWN0LWlk' },
      { type: 'page', title: TITLE_SECRET, url: 'https://chatgpt.com/c/' + CONV + '?token=' + URL_SECRET },
      { type: 'page', title: TITLE_SECRET, url: 'https://chatgpt.com/c/' + CONV + '#' + FRAGMENT_SECRET },
      { type: 'page', title: TITLE_SECRET, url: 'https://user:' + URL_SECRET + '@chatgpt.com/c/' + CONV },
      { type: 'page', title: TITLE_SECRET, url: 'about:blank' },
      { type: 'iframe', title: TITLE_SECRET, url: 'https://chatgpt.com/team/Acme%20Corp/threads' }
    ];
    const SECRETS = [TITLE_SECRET, URL_SECRET, FRAGMENT_SECRET, CONV, 'ZmFrZS1wcm9qZWN0LWlk', 'Acme', 'hunter2'];
    // EVERY diagnostic path that can print a target, not just the one the
    // fixture happens to exercise.
    const renders = [];
    for (const t of HOSTILE) {
      renders.push(W.renderTargetLine(t));
      renders.push(W.renderAttachLine(t));
    }
    renders.push(W.targetsJson(HOSTILE));
    renders.push(W.renderNoMatch('chatgpt.com', HOSTILE));
    const all = renders.join('\n');
    const leaked = SECRETS.filter(s => all.includes(s));
    check('R8 no target title, id, query, fragment or credential survives any target render',
      leaked.length === 0, 'leaked: ' + leaked.join(' / '));
    check('R8 no rendered target carries a query string or a fragment',
      !/[?#]/.test(renders.filter(r => r.indexOf('://') !== -1).join('\n')),
      renders.filter(r => r.indexOf('://') !== -1).join(' | '));
    check('R8 a ChatGPT conversation id is reduced to :id',
      W.sanitizeTargetUrl('https://chatgpt.com/c/' + CONV).display === 'https://chatgpt.com/c/:id',
      W.sanitizeTargetUrl('https://chatgpt.com/c/' + CONV).display);
    check('R8 a base64-looking project id is reduced to :id',
      /\/g\/:id$/.test(W.sanitizeTargetUrl('https://chatgpt.com/g/ZmFrZS1wcm9qZWN0LWlk').display),
      W.sanitizeTargetUrl('https://chatgpt.com/g/ZmFrZS1wcm9qZWN0LWlk').display);
    // The sanitizer has to still be USEFUL: an operator picking a tab needs to
    // tell two pages apart. A redaction that flattened every target to one
    // string would pass every assertion above and be useless.
    check('R8 candidates stay distinguishable without exposing content',
      new Set(HOSTILE.map(t => W.sanitizeTargetDisplay(t).display)).size >= 3,
      HOSTILE.map(t => W.sanitizeTargetDisplay(t).display).join(' | '));
    check('R8 known route words survive so the operator can recognise the page',
      W.sanitizeTargetUrl('https://chatgpt.com/settings/apps').display === 'https://chatgpt.com/settings/apps',
      W.sanitizeTargetUrl('https://chatgpt.com/settings/apps').display);
    check('R8 an opaque non-navigational target is named, not printed',
      W.sanitizeTargetUrl('about:blank').display === 'about:(opaque)' &&
      !/blank/.test(W.sanitizeTargetUrl('about:blank').display),
      W.sanitizeTargetUrl('about:blank').display);
    // The strongest form: the target TITLE is never read at all, and no console
    // call in the tool prints a raw target field. Raw urls may still be read
    // for MATCHING -- a redacted /c/:id no longer contains what the operator
    // typed -- so the assertion is on the output side, not on the source.
    const src8 = fs.readFileSync(path.join(__dirname, 'inspect-web.js'), 'utf8');
    check('R8 the target title is never read anywhere in the tool',
      !/\.title\b/.test(src8.replace(/^\s*\/\/.*$/gm, '')),
      'the tool still reads a target title');
    const consoleLines = src8.split('\n').filter(l => /console\.(log|error)/.test(l));
    check('R8 no console call prints a raw target field',
      !consoleLines.some(l => /\.url|\.title/.test(l)),
      consoleLines.filter(l => /\.url|\.title/.test(l)).join(' | '));
    check('R8 the four target output paths all go through the one sanitizer',
      ['renderTargetLine', 'targetsJson', 'renderAttachLine', 'renderNoMatch']
        .every(fn => new RegExp(fn + '\\(').test(src8)) &&
      !/console\.(log|error)\('\[' \+ t\.type/.test(src8),
      'a target is still printed some other way');
  }

  // ── R9: contextual surfaces are a SESSION contract, not a per-poll one ───
  // The defect: a code block absent on poll 1 and present on poll 2 was
  // unioned into missingEver and failed the whole pass, so a 900-second
  // operator run could not produce a trustworthy verdict.
  {
    const newChat = W.sanitizePageReport(report([
      surface({ id: 'sidebar', style: { backgroundColor: 'rgb(20, 20, 24)' } }),
      surface({ id: 'code-block', present: false, count: 0, style: null }),
      surface({ id: 'user-message', present: false, count: 0, style: null })
    ]));
    newChat.route = '/';
    const withCode = W.sanitizePageReport(report([
      surface({ id: 'sidebar', style: { backgroundColor: 'rgb(20, 20, 24)' } }),
      surface({ id: 'code-block', style: { backgroundColor: 'rgb(12, 12, 16)' } }),
      surface({ id: 'user-message', present: false, count: 0, style: null })
    ]));
    withCode.route = '/c/:id';

    const poll1 = W.summarize(newChat);
    check('R9 a contextual surface absent on poll 1 is not a failure',
      poll1.missing.length === 0 && poll1.mismatches.length === 0,
      JSON.stringify(poll1));
    const agg = W.aggregateWatch([newChat, withCode]);
    check('R9 a code block absent on poll 1 and present on poll 2 satisfies coverage',
      agg.requiredCoverageNotObserved.includes('code-block') === false,
      JSON.stringify(agg.requiredCoverageNotObserved));
    check('R9 the session still reports a requested surface it never saw at all',
      agg.requiredCoverageNotObserved.includes('user-message') === true,
      JSON.stringify(agg.requiredCoverageNotObserved));
    check('R9 coverage-not-observed is a distinct bucket from optional-not-observed',
      agg.optionalNotObserved.includes('code-block-actions') === true &&
      agg.optionalNotObserved.includes('code-block') === false,
      JSON.stringify(agg.optionalNotObserved));
    // A real mismatch seen once must survive later healthy polls.
    const leaked = W.sanitizePageReport(report([
      surface({ id: 'sidebar', style: { backgroundColor: STOCK_BG } })
    ]));
    const healed = W.sanitizePageReport(report([
      surface({ id: 'sidebar', style: { backgroundColor: 'rgb(20, 20, 24)' } })
    ]));
    const mixed = W.aggregateWatch([leaked, healed]);
    check('R9 a mismatch observed once stays reported after later good states',
      mixed.mismatchedEver.includes('sidebar') && mixed.observedEver.includes('sidebar') &&
      W.watchVerdict(mixed).accept === false,
      JSON.stringify(mixed));
  }

  // ── R10: a Settings poll must not demand the conversation matrix ─────────
  {
    const settingsPoll = W.sanitizePageReport(report([
      surface({ id: 'settings-page', routeMatched: true, selector: 'main', style: { backgroundColor: 'rgb(1, 2, 3)' } }),
      surface({ id: 'settings-nav', routeMatched: true, selector: 'main nav', style: { backgroundColor: 'rgb(1, 2, 3)' } }),
      // The whole conversation surface matrix, legitimately absent on Settings.
      surface({ id: 'composer-root', present: false, count: 0, style: null }),
      surface({ id: 'composer-body', present: false, count: 0, style: null }),
      surface({ id: 'prompt-editor', present: false, count: 0, style: null }),
      surface({ id: 'user-message', present: false, count: 0, style: null }),
      surface({ id: 'code-block', present: false, count: 0, style: null })
    ]));
    settingsPoll.route = '/settings/general';
    const s = W.summarize(settingsPoll);
    check('R10 a Settings poll with no composer produces no missing-contract failure',
      s.missing.length === 0, JSON.stringify(s.missing));
    check('R10 the conversation surfaces are inapplicable, not merely absent',
      ['composer-root', 'composer-body', 'prompt-editor'].every(id => s.notApplicable.includes(id)) &&
      s.notApplicable.includes('user-message') && s.notApplicable.includes('code-block'),
      JSON.stringify(s.notApplicable));
    // The converse: a conversation poll must not demand the Settings surfaces.
    const chatPoll = W.sanitizePageReport(report([
      surface({ id: 'composer-root', style: { backgroundColor: 'rgb(36, 34, 30)' } }),
      surface({ id: 'settings-page', routeOnly: true, present: false, count: 0, style: null })
    ]));
    chatPoll.route = '/c/:id';
    const cs = W.summarize(chatPoll);
    check('R10 a conversation poll does not demand the Settings surface',
      cs.missing.length === 0 && cs.notApplicable.includes('settings-page'),
      JSON.stringify(cs));
  }

  // ── R11: a requested surface is never a PASS while UNPROVEN ──────────────
  // The defect: Settings, settings-nav, menu, listbox, popover and dialog were
  // in the matrix with no token expectation, so classifySurface returned
  // UNPROVEN, and the exit status ignored unproven surfaces. An operator could
  // open Settings and every menu, prove nothing about their theming, and exit 0.
  {
    const ids = W.SURFACES.map(s => s.id);
    const tokensOnlyForKnown = Object.keys(W.SURFACE_TOKENS);
    check('R11 every token expectation names a surface that exists',
      tokensOnlyForKnown.every(id => ids.includes(id)),
      'dangling: ' + tokensOnlyForKnown.filter(id => !ids.includes(id)).join(', '));
    check('R11 the assistant MESSAGE is keyed by its own surface id',
      W.SURFACE_TOKENS['assistant-message'] === '--chat-background-color' &&
      W.SURFACE_TOKENS.assistant === undefined,
      JSON.stringify(W.SURFACE_TOKENS['assistant-message']));
    check('R11 every requested surface exists in the matrix',
      [...W.ACCEPTANCE_SURFACES].every(id => ids.includes(id)),
      'unknown: ' + [...W.ACCEPTANCE_SURFACES].filter(id => !ids.includes(id)).join(', '));
    // Every acceptance surface must have a classification strategy: either a
    // token expectation, or an EXPLICIT declaration that it has none yet. A
    // surface that is neither is simply unexamined, which is the defect.
    const strategyless = [...W.ACCEPTANCE_SURFACES].filter(id =>
      !W.SURFACE_TOKENS[id] && !W.DECLARED_UNPROVEN_ACCEPTANCE.includes(id));
    check('R11 every requested surface has a declared classification strategy',
      strategyless.length === 0, 'no strategy at all: ' + strategyless.join(', '));
    // A capture that is present-but-unprovable must be reported as UNRESOLVED and
    // non-accepting rather than folded into a pass. The surface that carries that
    // half is read from DECLARED_UNPROVEN_ACCEPTANCE itself rather than named here:
    // menu and settings-nav used to carry it and both LEFT the list on 2026-10-04 on
    // live evidence, and a copy would have kept asserting they are still unprovable
    // -- which is the exact drift this check exists to catch.
    const guessedId = W.DECLARED_UNPROVEN_ACCEPTANCE[0];
    const guessedSel = (W.SURFACES.find(x => x.id === guessedId) || {}).selector || '#x';
    const menuSeen = W.sanitizePageReport(report([
      surface({ id: guessedId, selector: guessedSel, style: { backgroundColor: W95_BG } })
    ]));
    // settings-page LEFT DECLARED_UNPROVEN_ACCEPTANCE on 2026-10-04 on live evidence
    // (see the token comment in inspect-web.js), so the same capture that used to be
    // UNPROVEN is now a real finding: a Settings surface painted the wrong colour is a
    // MISMATCH, which is stronger than "cannot be judged" and is what the live run
    // measured. menu is the mirror of settings-page -- it left the list too, and
    // CHATGPT_FAST_CSS binds [role="menu"] to the same T.surfaceRaised the live
    // measurement read off an opened menu -- so a menu painted the wrong colour is a
    // MISMATCH now rather than a shrug. That is the whole point of the token: it
    // makes the surface falsifiable.
    const settingsSeen = W.sanitizePageReport(report([
      surface({ id: 'settings-page', routeMatched: true, selector: 'main', style: { backgroundColor: 'rgb(4, 5, 6)' } })
    ]));
    settingsSeen.route = '/settings/general';
    const menuWrong = W.sanitizePageReport(report([
      surface({ id: 'menu', selector: '[role="menu"]', style: { backgroundColor: STOCK_BG } })
    ]));
    const agg = W.aggregateWatch([menuSeen, settingsSeen, menuWrong]);
    check('R11 a surface still without a token is reported UNPROVEN, not themed',
      W.summarize(menuSeen).unproven.length === 1 && agg.unprovenEver.includes(guessedId) &&
      !agg.observedEver.includes(guessedId),
      JSON.stringify({ guessedId, u: agg.unprovenEver }));
    check('R11 a Settings surface with a proved token is a MISMATCH when painted wrong, not UNPROVEN',
      agg.mismatchedEver.includes('settings-page') && !agg.unprovenEver.includes('settings-page'),
      JSON.stringify({ m: agg.mismatchedEver, u: agg.unprovenEver }));
    check('R11 a menu under the product\'s own overlay token is a MISMATCH when painted wrong',
      agg.mismatchedEver.includes('menu') && !agg.unprovenEver.includes('menu'),
      JSON.stringify({ m: agg.mismatchedEver, u: agg.unprovenEver }));
    check('R11 an unproven requested surface makes the run NON-ACCEPTING',
      W.watchVerdict(agg).accept === false &&
      W.watchVerdict(agg).unresolvedAcceptance.includes(guessedId),
      JSON.stringify(W.watchVerdict(agg)));
    check('R11 the console render flags an unproven requested surface explicitly',
      /REQUESTED FOR ACCEPTANCE -- NOT ACCEPTING/.test(W.renderConsole(menuSeen, W.summarize(menuSeen))));
    // A fully proven session is the only thing that accepts. Built from the
    // real matrix rather than a hand-picked pair, so "everything the operator
    // was asked to open was seen and judged" is what is actually asserted --
    // and the token contracts the surfaces are currently missing are lent to it
    // here, which isolates the reason a real run cannot accept today to exactly
    // one thing: nobody has proved which token those surfaces consume yet.
    const BASE = report([]).tokens;                       // the fixture token table
    const valueFor = (id) => {
      const t = W.SURFACE_TOKENS[id];
      const name = Array.isArray(t) ? t[0] : t;
      return (name && BASE[name]) || W95_BG;
    };
    const fullSession = () => W.sanitizePageReport(report(W.SURFACES.map(s => surface({
      id: s.id, label: s.label, selector: s.selector,
      required: s.contract === W.CONTRACT.ALWAYS,
      routeMatched: s.route ? true : undefined,
      style: { backgroundColor: valueFor(s.id) }
    }))));
    const lent = {};
    for (const id of W.DECLARED_UNPROVEN_ACCEPTANCE) {
      lent[id] = W.SURFACE_TOKENS[id];
      W.SURFACE_TOKENS[id] = '--chat-background-color';
    }
    const pa = W.aggregateWatch([fullSession()]);
    const pv = W.watchVerdict(pa);
    for (const id of Object.keys(lent)) {
      if (lent[id] === undefined) delete W.SURFACE_TOKENS[id]; else W.SURFACE_TOKENS[id] = lent[id];
    }
    check('R11 a session where every requested surface was seen and proven accepts',
      pv.accept === true, JSON.stringify({ reasons: pv.reasons, agg: pa }));
    check('R11 and it has no unresolved acceptance and no uncovered request',
      pa.unresolvedAcceptance.length === 0 && pa.requiredCoverageNotObserved.length === 0 &&
      pa.requiredMissingEver.length === 0 && pa.mismatchedEver.length === 0,
      JSON.stringify(pa));
    check('R11 the borrowed contracts are handed back -- the source of truth is unchanged',
      W.DECLARED_UNPROVEN_ACCEPTANCE.every(id => !W.SURFACE_TOKENS[id]),
      'a test left a token expectation behind');
    // A requested surface the operator never opened is unresolved work too, and
    // until this gate existed it was invisible: unresolvedAcceptance came from
    // unprovenEver alone (surfaces that WERE seen and could not be judged), and
    // the two coverage reasons are contract-scoped, so composer-root and
    // composer-body -- CONTRACT.OPTIONAL, and the only acceptance surfaces that
    // are -- fell out of all three. The session below is otherwise perfect, so
    // the ONLY thing that can make it non-accepting is their absence.
    {
      const COMPOSER_PAIR = ['composer-root', 'composer-body'];
      const pairIsAcceptance = COMPOSER_PAIR.every(id => W.ACCEPTANCE_SURFACES.has(id));
      const pairIsOptional = COMPOSER_PAIR.every(id => {
        const s = W.SURFACES.find(x => x.id === id);
        return s && s.contract === W.CONTRACT.OPTIONAL;
      });
      check('R11 the composer pair really is the acceptance-surface-by-optional-contract case this covers',
        pairIsAcceptance && pairIsOptional,
        'the fixture stopped being the shape it was written for: ' +
        JSON.stringify(COMPOSER_PAIR.map(id => ({
          id,
          acceptance: W.ACCEPTANCE_SURFACES.has(id),
          contract: (W.SURFACES.find(x => x.id === id) || {}).contract
        }))));
      const sessionWithout = (drop) => {
        const lent2 = {};
        for (const id of W.DECLARED_UNPROVEN_ACCEPTANCE) {
          lent2[id] = W.SURFACE_TOKENS[id];
          W.SURFACE_TOKENS[id] = '--chat-background-color';
        }
        const built = W.aggregateWatch([W.sanitizePageReport(report(W.SURFACES
          .filter(s => !drop.includes(s.id))
          .map(s => surface({
            id: s.id, label: s.label, selector: s.selector,
            required: s.contract === W.CONTRACT.ALWAYS,
            routeMatched: s.route ? true : undefined,
            style: { backgroundColor: valueFor(s.id) }
          }))))]);
        for (const id of Object.keys(lent2)) {
          if (lent2[id] === undefined) delete W.SURFACE_TOKENS[id]; else W.SURFACE_TOKENS[id] = lent2[id];
        }
        return W.watchVerdict(built);
      };
      const bothGone = sessionWithout(COMPOSER_PAIR);
      check('R11 a requested surface that was NEVER observed is unresolved, not a pass',
        bothGone.accept === false && bothGone.unresolvedAcceptance.includes('composer-root') &&
        bothGone.unresolvedAcceptance.includes('composer-body'),
        JSON.stringify(bothGone));
      // One at a time, because reconcileComposerPair deliberately lets the member
      // a variant does not paint read as transparent -- a sibling being PRESENT is
      // not the same as this one having been observed, and the old gate confused
      // the two by ignoring presence entirely.
      for (const id of COMPOSER_PAIR) {
        const oneGone = sessionWithout([id]);
        check('R11 and the same holds for one composer member alone (' + id + ')',
          oneGone.accept === false && oneGone.unresolvedAcceptance.includes(id),
          JSON.stringify(oneGone));
      }
      check('R11 and the full page still accepts -- the demand is scoped to what was asked for',
        sessionWithout([]).accept === true, JSON.stringify(sessionWithout([])));
    }
    // A surface painted by its container is transparent on a CORRECT page, and
    // transparent on a stock one too -- so the allowance has to be conditional on
    // that container being themed in the same report. Both halves are asserted
    // here, because the second half is the one that would otherwise be untested:
    // a rule that reads "transparent is fine" with no condition passes the first
    // check and accepts every unthemed page ever pointed at it.
    {
      const CODE = 'rgb(13, 13, 13)';
      const pair = (blockBg, actionBg) => W.sanitizePageReport({
        route: '/c/abc',
        tokens: { '--codeblock-background-color': CODE },
        surfaces: [
          { id: 'code-block', label: 'code block', required: false, present: true, count: 1, style: { backgroundColor: blockBg } },
          { id: 'code-block-actions', label: 'code block actions', required: false, present: true, count: 1, style: { backgroundColor: actionBg } }
        ]
      });
      const themedPage = W.summarize(pair(CODE, 'rgba(0, 0, 0, 0)'));
      check('R11 a transparent host passes while its container is themed',
        themedPage.observed.some(o => o.id === 'code-block-actions') &&
        !themedPage.mismatches.some(m => m.id === 'code-block-actions'),
        JSON.stringify(themedPage));
      const stockPage = W.summarize(pair('rgba(0, 0, 0, 0)', 'rgba(0, 0, 0, 0)'));
      check('R11 and it still fails when nothing themed that container',
        stockPage.mismatches.some(m => m.id === 'code-block-actions') &&
        !stockPage.observed.some(o => o.id === 'code-block-actions'),
        JSON.stringify(stockPage));
    }
    // The same conditional allowance for the two hosts added on 2026-10-04 from
    // live measurements: the assistant markdown root over the themed <main>, and
    // the Settings navigation inside the themed #app-shell-sidebar. Both are
    // asserted through the SAME builder as code-block-actions rather than by a
    // second hand-written pair, because the failure this guards against is exactly
    // a host that stops being conditional.
    {
      const MAIN = 'rgb(35, 32, 24)';
      const SIDE = 'rgb(26, 24, 16)';
      const hostPair = (id, containerId, tokenName, themedValue, containerBg, hostBg) =>
        W.summarize(W.sanitizePageReport({
          route: id === 'assistant-message' ? '/c/abc' : '/settings/general',
          tokens: { [tokenName]: themedValue },
          surfaces: [
            { id: containerId, label: containerId, required: false, present: true, count: 1, style: { backgroundColor: containerBg } },
            { id: id, label: id, required: false, present: true, count: 1, style: { backgroundColor: hostBg } }
          ]
        }));
      for (const [id, containerId, token, themed, host] of [
        ['assistant-message', 'conversation', '--chat-background-color', MAIN, 'rgba(0, 0, 0, 0)'],
        ['settings-nav', 'sidebar', '--color-token-side-bar-background', SIDE, 'rgba(0, 0, 0, 0)']
      ]) {
        const good = hostPair(id, containerId, token, themed, themed, host);
        check('R11 ' + id + ' passes as a transparent host while ' + containerId + ' is themed',
          good.observed.some(o => o.id === id) && !good.mismatches.some(m => m.id === id),
          JSON.stringify(good));
        const bad = hostPair(id, containerId, token, themed, 'rgba(0, 0, 0, 0)', host);
        check('R11 and ' + id + ' still fails when ' + containerId + ' is not themed',
          bad.mismatches.some(m => m.id === id) && !bad.observed.some(o => o.id === id),
          JSON.stringify(bad));
      }
    }
    // The mirror image: an empty session must not accept, and must name what it
    // never saw rather than reporting a clean sheet of empty buckets.
    const nothing = W.aggregateWatch([]);
    check('R11 an empty session does not accept and names every request it missed',
      W.watchVerdict(nothing).accept === false &&
      nothing.requiredCoverageNotObserved.includes('settings-nav') &&
      nothing.requiredCoverageNotObserved.includes('menu') &&
      nothing.requiredMissingEver.includes('settings-page'),
      JSON.stringify(nothing.requiredCoverageNotObserved));
    // The bounded allowed palette: a surface legitimately consuming one of
    // several Wintage surface tokens is a contract, not a loosening.
    {
      const savedMenu = W.SURFACE_TOKENS.menu;
      W.SURFACE_TOKENS.menu = ['--chat-background-color', '--color-surface-secondary'];
      const tokens = Object.assign({}, report([]).tokens, {
        '--chat-background-color': W95_BG, '--color-surface-secondary': STOCK_BG
      });
      const one = W.sanitizePageReport({
        url_host: 'chatgpt.com', route: '/c/:id', wintage: { stamped: true, sheets: 1 },
        tokens, surfaces: [surface({ id: 'menu', style: { backgroundColor: STOCK_BG } })]
      });
      const other = W.sanitizePageReport({
        url_host: 'chatgpt.com', route: '/c/:id', wintage: { stamped: true, sheets: 1 },
        tokens, surfaces: [surface({ id: 'menu', style: { backgroundColor: 'rgb(9, 9, 9)' } })]
      });
      check('R11 a surface matching ANY token in a bounded palette is themed',
        W.summarize(one).observed.length === 1, JSON.stringify(W.summarize(one)));
      check('R11 and a surface matching NONE of them is still a MISMATCH',
        W.summarize(other).mismatches.length === 1, JSON.stringify(W.summarize(other)));
      W.SURFACE_TOKENS.menu = savedMenu;
    }
  }

  // ── R12: attribution cannot leave the theme switched off ──────────────────
  // The probe DISABLES Wintage's own stylesheets to attribute the cascade. With
  // no try/finally, any throw between the disable and the re-enable leaves the
  // operator on an unthemed page -- and a diagnostic that damages the page it
  // measures is not a diagnostic. Driven by evaluating the REAL generated probe
  // against a stub DOM whose getComputedStyle throws mid-attribution, which is
  // the only way to exercise the generated string rather than a paraphrase of it.
  {
    const vm = require('vm');
    const expr = W.buildProbeExpression([
      { id: 'sidebar', label: 'sidebar', selector: '#app-shell-sidebar', contract: W.CONTRACT.ALWAYS, scope: W.SCOPE.ANY }
    ], { attribute: true });
    check('R12 the probe restores through a finally, not a trailing statement',
      /} finally \{\s*restore\(\);/.test(expr.replace(/(\r|\n) +/g, ' ')) || /finally \{[^}]*restore\(\);/.test(expr),
      'no finally guard in the generated probe');

    // A minimal DOM: enough for the probe to run, with one switch that makes
    // the mid-attribution read throw exactly the way a disappearing node does.
    function harness(opts) {
      const state = { scratchAttached: false, disabledSeen: [] };
      const mkSheet = (i) => ({
        tagName: 'STYLE', disabled: false, _i: i,
        getAttribute: (k) => (k === 'data-w95-ver' ? '1.0.0-' + i : null)
      });
      const sheets = [mkSheet(0), mkSheet(1)];
      const target = {
        tagName: 'DIV', getAttribute: () => null, getBoundingClientRect: () => ({ width: 10, height: 10 })
      };
      const scratch = {
        style: {},
        get parentNode() { return state.scratchAttached ? { removeChild: (n) => { state.scratchAttached = false; } } : null; },
        remove() { state.scratchAttached = false; }
      };
      const documentElement = {
        hasAttribute: (k) => k === 'data-w95-chatgpt'
      };
      const doc = {
        documentElement,
        // The probe queries the DOCUMENT, not the body.
        querySelectorAll: (sel) => (sel.indexOf('data-w95') !== -1 ? sheets : (sel === '#app-shell-sidebar' ? [target] : [])),
        body: {
          appendChild: () => { state.scratchAttached = true; return scratch; }
        },
        createElement: () => scratch
      };
      // The throw is keyed on the THEME BEING OFF, not on a call counter: the
      // probe reads the same node twice by design, and only the second read --
      // the one attribution makes with the stylesheets disabled -- is the
      // failure this control is about.
      const gcs = (el) => {
        if (el === target) {
          state.disabledSeen.push(sheets.map(s => s.disabled).join(','));
          if (opts.throwMid && sheets.some(s => s.disabled)) {
            throw new TypeError('getComputedStyle is not a function');
          }
        }
        return { backgroundColor: 'rgb(1, 2, 3)', getPropertyValue: () => '' };
      };
      return { state, sheets, expr, document: doc, gcs };
    }

    for (const opts of [{ throwMid: false }, { throwMid: true }]) {
      const h = harness(opts);
      let threw = false;
      try {
        vm.runInNewContext(h.expr, { document: h.document, getComputedStyle: h.gcs, location: { host: 'chatgpt.com', pathname: '/c/:id' } });
      } catch (e) { threw = true; }
      const label = opts.throwMid ? 'after a mid-attribution throw' : 'on the happy path';
      check('R12 the probe really does switch the theme off (control, ' + label + ')',
        h.state.disabledSeen.some(d => d === 'true,true'),
        'theme was never disabled: ' + JSON.stringify(h.state.disabledSeen));
      check('R12 Wintage stylesheets are all re-enabled ' + label,
        h.sheets.every(s => s.disabled === false),
        'left as ' + h.sheets.map(s => s.disabled).join(','));
      check('R12 the scratch node is cleaned up ' + label,
        h.state.scratchAttached === false, 'scratch node left in the page');
      if (opts.throwMid) check('R12 the simulated attribution failure did in fact throw', threw);
    }

    // The sheets are restored to what they were, not merely to false: an
    // operator who arrived with a sheet disabled keeps it disabled.
    {
      const h = harness({ throwMid: true });
      h.sheets[0].disabled = true;                    // as the page had it
      h.sheets[1].disabled = true;
      try { vm.runInNewContext(h.expr, { document: h.document, getComputedStyle: h.gcs, location: { host: 'chatgpt.com', pathname: '/' } }); } catch (e) { }
      check('R12 restoration returns each sheet to the state the page had it in',
        h.sheets[0].disabled === true && h.sheets[1].disabled === true,
        'clobbered to ' + h.sheets.map(s => s.disabled).join(','));
    }
    // A sheet that vanishes mid-read must not stop the others from coming back.
    {
      const h = harness({ throwMid: false });
      Object.defineProperty(h.sheets[0], 'disabled', {
        get() { return false; },
        set() { throw new Error('sheet was removed from the document'); }
      });
      let out = null;
      try { out = vm.runInNewContext(h.expr, { document: h.document, getComputedStyle: h.gcs, location: { host: 'chatgpt.com', pathname: '/' } }); } catch (e) { }
      check('R12 a sheet that cannot be restored does not abort the restore of the rest',
        out !== null && h.sheets[1].disabled === false,
        'the whole probe died on one dead sheet');
    }
  }

  // T-391/T-392: the two commands that reported success on a page they never
  // inspected. Both exit decisions were unreachable from a test because they
  // lived inline in main(); they are now named functions, and the point of these
  // cases is that the FLOOR is what decides -- an empty measurement is not a
  // pass, whatever it is called.
  {
    const absent = W.sanitizeOpaqueReport({
      url_host: 'chatgpt.com', root_found: false, min_coverage: 0.1,
      wintage: { stamped: true, sheets: 3, attribution_live: true },
      viewport: { width: 1280, height: 800 }, palette: {}, nodes: [], stock_nodes: 0
    });
    check('R13 an app shell that was not found is NOT a clean opaque audit',
      W.opaqueGateRed(absent) === true && W.opaqueGateReason(absent).includes('not found'),
      'the opaque command exited 0 on the page it exists to catch');

    const measured = W.sanitizeOpaqueReport({
      url_host: 'chatgpt.com', root_found: true, min_coverage: 0.1,
      wintage: { stamped: true, sheets: 3, attribution_live: true },
      viewport: { width: 1280, height: 800 }, palette: {}, nodes: [{ tag: 'main', vintageToken: '--background' }], stock_nodes: 0
    });
    check('R13 and a measured page with no stock colour stays clean',
      W.opaqueGateRed(measured) === false,
      'the floor is now too high and would red every healthy page');

    const stock = W.sanitizeOpaqueReport({
      url_host: 'chatgpt.com', root_found: true, min_coverage: 0.1,
      wintage: { stamped: true, sheets: 3, attribution_live: true },
      viewport: { width: 1280, height: 800 }, palette: {}, nodes: [{ tag: 'div' }], stock_nodes: 1
    });
    check('R13 and the original regression still reds: a stock-coloured region painting',
      W.opaqueGateRed(stock) === true,
      'the pre-existing stock_nodes check was replaced rather than added to');

    check('R14 a selector that matched nothing is a failed lookup, not a clean one',
      W.rulesGateRed({ nodeId: 0 }) === true && W.rulesGateRed(null) === true && W.rulesGateRed(undefined) === true,
      'the rules command exited 0 for an element that no longer exists');
    check('R14 and a selector that resolved a node stays clean',
      W.rulesGateRed({ nodeId: 7 }) === false,
      'the floor is now too high for the working case');
  }

  if (bad) {
    console.error('\nlive-inspector gate: ' + bad + ' failure(s)');
    process.exit(1);
  }
  console.log('\nlive-inspector gate: PASS');
}

main().catch(e => { console.error('live-inspector gate CRASHED: ' + (e && e.stack || e)); process.exit(1); });
