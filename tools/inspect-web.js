#!/usr/bin/env node
'use strict';

// Reads a LIVE chatgpt.com tab over the Chrome DevTools Protocol.
//
// Why this exists: tools/test-chatgpt-2026.js proves the intended selectors and
// token declarations EXIST in Wintage. It cannot prove any of the things that
// actually break a theme on a page that ships weekly: that the selectors still
// match, that the mapped variables are consumed, that Wintage wins the cascade,
// or that a redesigned surface (full-page Settings, current navigation, current
// code container) does not leak stock colours. Those need Blink to answer.
//
// Start a user-owned browser with a debugging port and point this at it:
//
//   brave --remote-debugging-port=9222        (or chrome)
//   node tools/inspect-web.js targets
//   node tools/inspect-web.js surface chatgpt.com --json
//   node tools/inspect-web.js rules chatgpt.com '[data-composer-dark]'
//   node tools/inspect-web.js watch chatgpt.com 900
//
// PRIVACY. This tool never reads, logs or requests credentials, cookies, tokens,
// storage values or request headers, and it never emits document HTML. The only
// CDP domains used are Runtime, DOM and CSS. Page reports are rebuilt from a
// structural allowlist before they leave the page, so there is no code path that
// can carry message text, prompt contents or account identity out. The route is
// reported with uuid-like segments replaced by ':id'.
//
// That page-side boundary is necessary and NOT sufficient. A CDP target also
// carries a title and a url, and on chatgpt.com those are the conversation name
// and the conversation id -- the same user content, arriving from a direction
// the in-page allowlist cannot see. So there is a second boundary on the target
// side: one sanitizer, used by every diagnostic that prints a target (the
// listing, the JSON listing, the attach banner, the no-match error), which drops
// the title, drops the query and the fragment, and reduces the route to a fixed
// vocabulary of ChatGPT route names with every other segment as ':id'.
//
// ACCEPTANCE. The matrix below is a PROBE LIST, not an assumption. A surface is
// recorded as observed or absent; nothing is treated as present because it is
// conceptually supposed to exist. What differs is the CONTRACT:
//
//   'always'   must match on every poll where the surface applies;
//   'coverage' must be OBSERVED at least once across the whole operator
//              session -- a code block is absent on a new chat and present on
//              the one that has code, and neither poll is a finding;
//   'optional' absence is never a finding.
//
// A contextual surface that was requested for acceptance and never observed, or
// observed but left UNPROVEN because no token expectation exists for it yet, is
// reported as UNRESOLVED and the run does NOT exit 0. Naming a token for a
// surface nobody has seen render would be a guess dressed as a contract, and a
// green gate that proves nothing is worse than a red one.

const { debugPort, pageTargets, connect, die } = require('./cdp-client.js');

const WINTAGE_STAMP = 'data-w95-';

// Computed properties worth reading on a themed surface. Colour, border and
// shadow are what a leak shows up in; the rest are cheap and catch the case
// where a surface has the right colour for the wrong reason.
const DEFAULT_PROPS = [
  'backgroundColor', 'color', 'borderTopColor', 'borderTopWidth', 'borderTopStyle', 'boxShadow'
];
// Layout properties ChatGPT owns. Recorded so the code-block scrolling contract
// can be PROVEN (see `attribute`): if switching Wintage off does not move these,
// Wintage is not overriding the site's scroll behaviour.
const LAYOUT_PROPS = ['overflowY', 'overflowX', 'maxHeight', 'height', 'position'];

const SELECTOR = s => ({ id: s.id, label: s.label, selector: s.selector });

// ── The live surface matrix ────────────────────────────────────────────────
//
// `contract` is the acceptance semantics, and it is NOT a single boolean. The
// previous matrix had one `required: true` flag meaning "must be here on every
// poll", and it was applied to a code block and a user message bubble. That is
// not a stricter gate, it is a broken one: a brand-new chat has no user message
// and no code block, and full-page Settings has no composer at all. A poll there
// produces failures that describe the operator's navigation, not the theme.
//
//   'always'   -- must be present on every poll where the surface applies.
//   'coverage' -- contextual. Must be OBSERVED at least once across the whole
//                 operator session; its absence on any single poll is not a
//                 finding. This is the contract for a code block, a user
//                 message, a menu, a Settings page.
//   'optional' -- recorded structurally; absence is not a finding, ever.
//
// `scope` says which part of the app a surface belongs to, so a conversation
// matrix is not demanded while the operator is on Settings.
const CONTRACT = { ALWAYS: 'always', COVERAGE: 'coverage', OPTIONAL: 'optional' };
const SCOPE = { ANY: 'any', CONVERSATION: 'conversation', SETTINGS: 'settings' };

// ── October 2026 shell, September 2026 rollout fallbacks ───────────────────
// ChatGPT rehashed its structural shell. The live page now exposes
// #web-mobile-root, [data-testid="desktop-app-shell"],
// main[aria-label="ChatGPT"], [role="region"][aria-label="Conversation"],
// the sidebar accessibility landmark and #mobile-composer-prompt. The previous
// generation (#root, #app-shell-sidebar, [data-composer-dark],
// [data-testid="prompt-textarea"]) is still live on accounts part-way through a
// rollout, so it stays -- but as a FALLBACK, never as the only selector.
//
// A selector list is ordered, and querySelector takes the first match, so
// putting the current contract first is what makes the report describe the
// shell actually on screen. Generated x* atomic class names are deliberately
// absent: they are build output and are rehashed on every rollout.
const CURRENT_SIDEBAR = '[role="complementary"][aria-label="Sidebar"], aside[aria-label="Sidebar"]';

const SURFACES = [
  { id: 'root', label: 'document / root application surface', selector: 'html', contract: CONTRACT.ALWAYS, scope: SCOPE.ANY },
  { id: 'root-body', label: 'body surface', selector: 'body', contract: CONTRACT.ALWAYS, scope: SCOPE.ANY },
  { id: 'root-app', label: 'root app container', selector: '#web-mobile-root, #root', contract: CONTRACT.ALWAYS, scope: SCOPE.ANY },
  { id: 'app-shell', label: 'current desktop app shell frame', selector: '[data-testid="desktop-app-shell"]', contract: CONTRACT.COVERAGE, scope: SCOPE.ANY },
  // The viewport owner between the app shell and everything visible inside it.
  // This is the node that actually PAINTS the pixels of the central workspace on
  // routes where the conversation does not fill the height -- an empty/new chat
  // above all. Omitting it is invisible to every selector-presence check in this
  // repo, because its PARENT is themed and still matches: a parent-themed,
  // child-opaque-stock shell renders exactly like the reported black workspace
  // while all four October hooks report present. That is why it gets its own
  // surface AND its own viewport-ownership evidence rather than a `background`
  // declaration inside the app-shell block.
  // 2026-10-04, measured on a signed-in tab: the app exposes NO data-testid for
  // either shell, no #thread, and no aria-label on <main>. The viewport owner is now
  // a div.thread-scroll-container inside a themed <main>, and the editor is a
  // role=textbox contenteditable div with neither id nor testid. The old selectors
  // did not stop matching by breaking -- they stopped matching by being replaced,
  // so two ALWAYS contracts read MISSING on a page the product paints correctly.
  { id: 'app-scroll-container', label: 'app shell scroll container (viewport owner)', selector: '[data-testid="mobile-app-shell-scroll-container"], div.thread-scroll-container, main', contract: CONTRACT.ALWAYS, scope: SCOPE.ANY, props: DEFAULT_PROPS.concat(['backgroundImage']).concat(LAYOUT_PROPS) },
  { id: 'conversation', label: 'main conversation surface', selector: 'main[aria-label="ChatGPT"], main', contract: CONTRACT.COVERAGE, scope: SCOPE.CONVERSATION },
  { id: 'conversation-region', label: 'conversation scroll region', selector: '[role="region"][aria-label="Conversation"]', contract: CONTRACT.COVERAGE, scope: SCOPE.CONVERSATION },
  { id: 'thread', label: 'thread list container', selector: '#thread', contract: CONTRACT.COVERAGE, scope: SCOPE.CONVERSATION },
  { id: 'sidebar', label: 'expanded sidebar', selector: CURRENT_SIDEBAR + ', #app-shell-sidebar', contract: CONTRACT.ALWAYS, scope: SCOPE.ANY },
  {
    id: 'sidebar-legacy-slideover', label: 'legacy rollout sidebar (slideover)',
    selector: '#stage-slideover-sidebar', contract: CONTRACT.OPTIONAL, scope: SCOPE.ANY
  },
  {
    id: 'sidebar-legacy-tiny', label: 'legacy rollout sidebar (tiny bar)',
    selector: '#stage-sidebar-tiny-bar', contract: CONTRACT.OPTIONAL, scope: SCOPE.ANY
  },
  { id: 'nav-entry', label: 'sidebar navigation entry', selector: CURRENT_SIDEBAR + ' a, #app-shell-sidebar nav a, #app-shell-sidebar a[href^="/c/"], #app-shell-sidebar a[href^="/g/"]', contract: CONTRACT.COVERAGE, scope: SCOPE.ANY },
  { id: 'nav-project', label: 'project navigation entry', selector: CURRENT_SIDEBAR + ' a[href^="/g/"], #app-shell-sidebar a[href^="/g/"]', contract: CONTRACT.COVERAGE, scope: SCOPE.ANY },
  { id: 'user-message', label: 'user message bubble', selector: '[data-user-message-bubble="true"]', contract: CONTRACT.COVERAGE, scope: SCOPE.CONVERSATION },
  // Measured 2026-10-04 by walking up from a code block that is known to sit
  // inside an answer, on a signed-in tab with the product's own sheet injected.
  // ChatGPT has dropped [data-message-author-role] entirely (article,
  // [data-message-author-role], [data-message-id], [data-testid^=agent-message]
  // and [data-conversation-turn] are ALL absent from today's DOM), but the
  // markdown root still carries the role in the attribute's OWN VALUE --
  // data-markdown-text-style="assistant-message" -- which is the mirror image of
  // the user side's group/user-message class. That is why it can be trusted to
  // exclude user turns by construction rather than by a sample count. The
  // legacy hook is kept as an alternative so the surface survives a shell that
  // brings the old attribute back.
  { id: 'assistant-message', label: 'assistant message content', selector: '[data-markdown-text-style="assistant-message"], [data-message-author-role="assistant"]', contract: CONTRACT.COVERAGE, scope: SCOPE.CONVERSATION },
  // The September composer container hooks. Optional by the same argument as
  // the legacy sidebars: the current shell exposes no stable container hook --
  // Wintage paints #mobile-composer-prompt directly rather than guessing a
  // parent -- so demanding these on a current account would make every live
  // pass report a false failure. Present in a September rollout, still judged.
  { id: 'composer-root', label: 'composer root (rollout fallback)', selector: '[data-composer-dark]', contract: CONTRACT.OPTIONAL, scope: SCOPE.CONVERSATION },
  { id: 'composer-body', label: 'composer body (rollout fallback)', selector: '[data-composer-body]', contract: CONTRACT.OPTIONAL, scope: SCOPE.CONVERSATION },
  // The October contract named an id and a testid; today's editor has neither (measured
  // 2026-10-04 on a signed-in tab: DIV.ProseMirror, aria-label="Ask ChatGPT", no id,
  // no data-testid). role=textbox + contenteditable is the durable part of the contract
  // -- the generated class is not, and binding to it would make the contract a build
  // artifact.
  { id: 'prompt-editor', label: 'prompt editor', selector: '#mobile-composer-prompt, [data-testid="prompt-textarea"], [role="textbox"][contenteditable="true"]', contract: CONTRACT.ALWAYS, scope: SCOPE.CONVERSATION },
  { id: 'composer-utility', label: 'composer utility / action controls', selector: '[data-composer-utility-bar], [data-composer-dark] [role="toolbar"]', contract: CONTRACT.COVERAGE, scope: SCOPE.CONVERSATION },
  { id: 'header-mode', label: 'header pressed mode control', selector: 'header button[aria-pressed="true"], #page-header button[aria-pressed="true"]', contract: CONTRACT.COVERAGE, scope: SCOPE.CONVERSATION },
  { id: 'code-block', label: 'code block container', selector: '[data-markdown-copy="code-block"]', contract: CONTRACT.COVERAGE, scope: SCOPE.CONVERSATION, props: DEFAULT_PROPS.concat(LAYOUT_PROPS) },
  { id: 'code-block-pre', label: 'code block text/pre region', selector: '[data-markdown-copy="code-block"] pre', contract: CONTRACT.COVERAGE, scope: SCOPE.CONVERSATION, props: DEFAULT_PROPS.concat(LAYOUT_PROPS) },
  { id: 'code-block-actions', label: 'code block header / action region', selector: '[data-markdown-copy="code-block"] button', contract: CONTRACT.OPTIONAL, scope: SCOPE.CONVERSATION },
  { id: 'thread-footer', label: 'thread footer / fade container', selector: '#thread-bottom-container', contract: CONTRACT.COVERAGE, scope: SCOPE.CONVERSATION },
  { id: 'menu', label: 'menu', selector: '[role="menu"]', contract: CONTRACT.COVERAGE, scope: SCOPE.ANY },
  { id: 'listbox', label: 'listbox', selector: '[role="listbox"]', contract: CONTRACT.COVERAGE, scope: SCOPE.ANY },
  { id: 'popover', label: 'popover', selector: '[popover]', contract: CONTRACT.COVERAGE, scope: SCOPE.ANY },
  { id: 'dialog', label: 'dialog', selector: 'dialog[open], [role="dialog"]', contract: CONTRACT.COVERAGE, scope: SCOPE.ANY },
  { id: 'settings-page', label: 'full-page Settings surface', route: /^\/settings(\/|$)/, selector: 'main', contract: CONTRACT.ALWAYS, scope: SCOPE.SETTINGS },
  { id: 'settings-nav', label: 'Settings navigation', route: /^\/settings(\/|$)/, selector: 'nav[aria-label="Settings"], main nav, main [role="navigation"], main [role="tablist"]', contract: CONTRACT.COVERAGE, scope: SCOPE.SETTINGS },
  { id: 'customize', label: 'Customize / integrations surface', route: /^\/(g\/gizmos|settings\/(apps|connectors|plugins))/i, selector: 'main', contract: CONTRACT.COVERAGE, scope: SCOPE.SETTINGS }
];

// Full-page Settings and the Customize/integrations pages are routes, not
// conversation states. Every conversation-scoped surface is inapplicable here,
// which is what stops a Settings poll from manufacturing four phantom failures.
function isSettingsRoute(path) {
  return typeof path === 'string' &&
    (/\/settings(\/|$)/i.test(path) || /^\/g\/gizmos/i.test(path));
}

// The operator is asked to open these during the bounded pass. They are the
// ACCEPTANCE surfaces: their absence from a session is unresolved work, and --
// the part that was broken -- their being merely UNPROVEN must not be allowed
// to read as a pass.
const ACCEPTANCE_SURFACES = new Set([
  'conversation', 'conversation-region', 'app-shell', 'sidebar', 'nav-entry',
  'nav-project', 'user-message', 'assistant-message', 'composer-root',
  'composer-body', 'prompt-editor', 'code-block', 'menu', 'popover',
  'listbox', 'dialog', 'settings-page', 'settings-nav', 'customize'
]);

// Acceptance surfaces for which NO token expectation exists yet, because naming
// one offline would be a guess at a selector the project has never seen render.
// A surface may leave this list ONE way: a live run proves which Wintage
// semantic token it is supposed to consume, and that token is added. Until then
// these are reported UNPROVEN and are non-accepting -- deliberately, so the
// tool cannot exit 0 after proving nothing about the very surfaces the operator
// was asked to open.
// `prompt-editor` is here because the claim that it "is no longer a guess" is
// falsified by vintage.user.js itself. The current-shell element the selector
// matches, [data-testid="prompt-textarea"], receives color and caret-color and
// NO background (CHATGPT_FAST_CSS); the one variant that IS painted,
// #mobile-composer-prompt, is a different element and carries T.surface, not
// --composer-background-color. Expecting the token anyway reports a mismatch
// the product never promised to fix, and it is an ACCEPTANCE surface, so that
// phantom mismatch keeps a correct page from ever going green. Naming its token
// is exactly the move the rule above reserves for a live run -- see the
// `ownership.opaqueAncestor` block, which is what such a run must read.
// `nav-entry`, `prompt-editor` and `dialog` LEFT this list on 2026-10-04 by the rule
// above, on a signed-in tab with the product's own CHATGPT_FAST_CSS injected, and
// are the only three that left it that way:
//   nav-entry      transparent on the live tab; its container (#app-shell-sidebar)
//                  computes to --color-token-side-bar-background = #1A1810.
//   prompt-editor  transparent; its container [data-composer-dark] computes to
//                  --composer-background-color = #332E22. The old note here said the
//                  editor gets no background of its own and therefore must not be
//                  held to a token -- that is now expressed as a TRANSPARENT_HOSTS
//                  entry, which keeps the observation and stops the phantom mismatch
//                  at the same time.
//   dialog         an open dialog computed to rgb(61, 55, 42) = #3D372A =
//                  T.surfaceRaised, the token CHATGPT_FAST_CSS declares on :root.
// `settings-page` and `customize` LEFT this list the same way, later on 2026-10-04:
//   settings-page  on /settings/general-settings <main> computes to rgb(35, 32, 24)
//                  = #232018, the same backgroundSoft token the conversation main is
//                  held to.
//   customize      on /settings/plugins-settings (which is where /settings/connectors
//                  redirects today) its <main> computes to the same rgb(35, 32, 24).
//   menu, listbox, popover LEFT it too. CHATGPT_FAST_CSS paints `dialog`,
//                  [popover], [role="menu"], [role="listbox"], [role="dialog"] and
//                  [role="alertdialog"] in ONE rule to T.surfaceRaised
//                  (wintage.user.js:1926), so three of those four selectors are the
//                  SAME authored contract dialog already proved -- naming their
//                  token is reading the product, not guessing one. menu was then
//                  measured live (aria-haspopup="menu" opened, [role="menu] computed
//                  to rgb(61, 55, 42) = #3D372A). listbox and popover hold that token
//                  with NO live observation: today's shell opens only menu and dialog
//                  overlays, so they stay in requiredCoverageNotObserved, which is
//                  where an unopened surface is honestly recorded.
//   assistant-message
//                  LEFT it because the hook changed, not because the token did:
//                  [data-message-author-role] is gone from today's DOM, and walking up
//                  from a code block inside an answer found
//                  [data-markdown-text-style="assistant-message"] -- the role in the
//                  attribute's own value, mirroring the user side's group/user-message.
//                  It is transparent over the themed <main>, so it is a TRANSPARENT_HOST.
//   settings-nav    LEFT it for the same reason as assistant-message: the live Settings
//                  route DOES render nav[aria-label="Settings"] -- outside <main> and
//                  with no [role=navigation], which is why the old 'main nav' selector
//                  could not see it and the surface read as absent. It is transparent
//                  inside the themed #app-shell-sidebar.
// What is left is still a guess, and still non-accepting:
//   nav-project    this profile renders zero a[href^="/g/"] links on every route
//                  measured (conversation and settings), so there is nothing to read.
//                  Creating one is an operator action inside the product account.
const DECLARED_UNPROVEN_ACCEPTANCE = [
  'nav-project'
];

// ── The in-page probe ──────────────────────────────────────────────────────
// One Runtime.evaluate for the whole matrix: per-selector DOM round trips are
// what made "check seventeen surfaces" slow enough that nobody ran it. The
// matrix arrives as DATA (this function is a pure string builder) so the probe
// has no selector baked into it and the RED controls can drive it with fixtures.
function buildProbeExpression(surfaces, opts) {
  const defs = JSON.stringify(surfaces.map(s => ({
    id: s.id,
    label: s.label,
    selector: s.selector,
    // The page reports what it SAW; the acceptance contract is Node-side, where
    // SURFACES is authoritative. Emitting it here too keeps a hand-built
    // record (fixtures, an old report replayed from disk) interpretable.
    required: s.contract === CONTRACT.ALWAYS,
    contract: s.contract || CONTRACT.OPTIONAL,
    route: s.route ? s.route.source : null,
    props: s.props || DEFAULT_PROPS
  })));
  const attribute = !!(opts && opts.attribute);
  return `(function(){
  var DEFS = ${defs};
  var ATTRIBUTE = ${attribute};
  var propsOf = function (el, props) {
    var cs = getComputedStyle(el), out = {};
    for (var i = 0; i < props.length; i++) { out[props[i]] = cs[props[i]]; }
    return out;
  };
  // A background-image summary, not the value. A gradient can only carry colours
  // and lengths, so nothing private can reach it -- but the raw string can be
  // hundreds of characters of nothing an operator needs. What matters is its
  // KIND and the colours in it, because the header/footer fades are exactly how
  // a stock ChatGPT charcoal survives a correctly themed parent.
  var imageSummary = function (v) {
    var s = String(v || '');
    var kind = s.indexOf('gradient(') !== -1 ? 'gradient' : (s.indexOf('url(') !== -1 ? 'image' : 'other');
    var colors = [], re = /(#[0-9a-f]{3,8}|rgba?\\([^)]*\\))/gi, m;
    while ((m = re.exec(s)) !== null && colors.length < 8) colors.push(m[1].toLowerCase());
    return { kind: kind, colors: colors };
  };
  // Wintage's own stylesheets are the <style data-w95="..."> nodes injectStyle()
  // creates, so ownership is a structural fact, not a guess at a marker.
  var w95sheets = [].slice.call(document.querySelectorAll('style[' + ${JSON.stringify('data-w95')} + ']'));
  var w95off = false;
  // The state each sheet was in when this probe started. Attribution switches
  // the theme OFF inside a try/finally below; restoring to "whatever the page
  // actually had" is the only version of this that cannot damage a page whose
  // operator arrived with a sheet disabled.
  var priorDisabled = w95sheets.map(function (s) { try { return !!s.disabled; } catch (e) { return false; } });
  // Resolve a semantic token to the concrete colour it paints, so expectations
  // are expressed against Wintage's own live palette instead of a hex copied
  // out of the source. Custom properties read back as their authored token
  // stream, so they are painted onto a scratch node to get a computed rgb().
  var scratch = document.createElement('span');
  scratch.style.cssText = 'position:absolute;left:-9999px;top:0;width:1px;height:1px;visibility:hidden';
  var scratchHost = document.body || document.documentElement;
  try { scratchHost.appendChild(scratch); } catch (e0) { }
  // EXCEPTION SAFETY. A diagnostic that dies with the theme switched off leaves
  // the operator staring at an unthemed page and blaming the page. Everything
  // temporary this probe touches -- the theme's own stylesheets and the scratch
  // node -- is undone here, and only here, whether the body returned, threw, or
  // the node was replaced underneath us. Restoration itself is defensive: a
  // sheet that vanished mid-read must not stop the others from coming back.
  var restore = function () {
    w95off = false;
    for (var i = 0; i < w95sheets.length; i++) {
      try { w95sheets[i].disabled = priorDisabled[i]; } catch (e1) { }
    }
    try {
      if (scratch && scratch.parentNode) scratch.parentNode.removeChild(scratch);
    } catch (e2) {
      try { if (scratch && scratch.remove) scratch.remove(); } catch (e3) { }
    }
  };
  try {
  var tokenColor = function (name) {
    scratch.style.backgroundColor = '';
    scratch.style.backgroundColor = 'var(' + name + ')';
    var v = getComputedStyle(scratch).backgroundColor;
    return v === 'rgba(0, 0, 0, 0)' || v === '' ? null : v;
  };
  var out = { url_host: location.host, route: null, attribute: ATTRIBUTE, wintage: {}, tokens: {}, surfaces: [] };
  out.route = location.pathname.replace(/[0-9a-f]{8}-[0-9a-f-]{20,}/gi, ':id').replace(/[0-9a-f]{16,}/gi, ':id');
  out.wintage = {
    stamped: document.documentElement.hasAttribute(${JSON.stringify('data-w95-chatgpt')}),
    sheets: w95sheets.length,
    versions: w95sheets.map(function (s) { return s.getAttribute('data-w95-ver'); })
  };
  var rootcs = getComputedStyle(document.documentElement);
  var TOKEN_NAMES = ['--chat-background-color','--app-color-background-surface','--color-surface',
    '--color-surface-secondary','--color-background-panel','--color-token-main-surface-primary',
    '--color-token-main-surface-secondary','--color-token-main-surface-tertiary',
    '--color-token-side-bar-background','--composer-background-color','--composer-surface',
    '--user-message-background-color','--color-background-user-message','--codeblock-background-color',
    '--color-token-text-code-block-background','--token-text-primary','--token-text-secondary',
    // --background is what <html> is actually held to (paintRoot writes T.background
    // inline; see SURFACE_TOKENS.root). It has to be resolved HERE as well as in the
    // opaque probe, because the raw getPropertyValue fallback below yields the
    // authored "#1A1810" rather than a computed rgb(), so a token the expectation
    // names but this list omits reports "resolved to nothing" on a page that is fine.
    '--background',
    // Same reason, and it is one of the tokens the product's OWN sheet declares on
    // :root (CHATGPT_FAST_CSS, wintage.user.js:1879): an open dialog computes to it,
    // and an expectation naming a token this list omits reads "resolved to nothing".
    '--surfaceRaised'];
  for (var t = 0; t < TOKEN_NAMES.length; t++) {
    out.tokens[TOKEN_NAMES[t]] = tokenColor(TOKEN_NAMES[t]) || rootcs.getPropertyValue(TOKEN_NAMES[t]).trim() || null;
  }
  for (var i = 0; i < DEFS.length; i++) {
    var d = DEFS[i], rec = { id: d.id, label: d.label, selector: d.selector || null, required: d.required, contract: d.contract };
    if (d.route) {
      if (!(new RegExp(d.route)).test(location.pathname)) { rec.routeOnly = true; rec.present = false; out.surfaces.push(rec); continue; }
      rec.routeMatched = true;
    }
    var nodes = d.selector ? document.querySelectorAll(d.selector) : [];
    rec.count = nodes.length;
    rec.present = nodes.length > 0;
    if (nodes.length) {
      var el = nodes[0];
      try { rec.style = propsOf(el, d.props); } catch (e) { rec.style = null; }
      try {
        var r = el.getBoundingClientRect();
        rec.visible = !!(r.width && r.height);
      } catch (e2) { rec.visible = null; }
      // Structural identity only: the attributes that NAME a surface, never its
      // content. aria-label is deliberately absent -- on a sidebar entry or a
      // project row it carries the conversation or project title, which is user
      // content, and nothing in this tool needs it. ATTRIBUTE additionally
      // proves whether Wintage is the source of a value by switching the sheets
      // off and reading the same node again -- if nothing moves, the site (not
      // Wintage) owns that property.
      var ALLOWED = ['id','role','data-testid','data-w95','data-w95-ver','aria-pressed','aria-selected','aria-expanded','aria-haspopup','aria-modal','data-state','contenteditable'];
      rec.node = { tag: el.tagName.toLowerCase() };
      for (var a = 0; a < ALLOWED.length; a++) {
        var av = el.getAttribute(ALLOWED[a]);
        if (av !== null && av !== undefined) rec.node[ALLOWED[a]] = String(av).slice(0, 120);
      }
      if (ATTRIBUTE) {
        w95off = true; w95sheets.forEach(function (s) { try { s.disabled = true; } catch (e4) { } });
        rec.withoutWintage = propsOf(el, d.props);
        w95off = false; w95sheets.forEach(function (s) { try { s.disabled = false; } catch (e5) { } });
        // Built locally, then attached once. Assigning straight onto rec per
        // property is the shape that breaks when rec is anything but a plain
        // literal, and a diagnostic that dies halfway is worse than none.
        var ownsMap = {};
        for (var k in rec.style) {
          if (Object.prototype.hasOwnProperty.call(rec.style, k)) {
            ownsMap[k] = (rec.style[k] !== rec.withoutWintage[k]) ? true : false;
          }
        }
        rec.vintageOwns = ownsMap;
      }
      // Viewport ownership. Every selector check in this repo answers "does X
      // exist"; none of them answers "is X the thing painting the pixels I can
      // see". Those come apart exactly in the reported failure: the app shell,
      // the main element and the conversation region are ALL themed and all
      // present, while one opaque full-height layer between them and the content
      // owns the whole central workspace. So each surface also reports the box it
      // covers, the fraction of the viewport that is, whether it is transparent
      // at all, and the nearest ancestor that is genuinely opaque.
      try {
        var r2 = el.getBoundingClientRect();
        var vw = document.documentElement.clientWidth || window.innerWidth || 0;
        var vh = document.documentElement.clientHeight || window.innerHeight || 0;
        var varea = vw * vh;
        var cs2 = getComputedStyle(el);
        var bg2 = cs2.backgroundColor;
        var bgi2 = cs2.backgroundImage;
        var opaqueAncestor = null, up = el.parentElement, hops = 0;
        while (up && hops < 40) {
          var c3 = getComputedStyle(up);
          var b3 = c3.backgroundColor;
          var i3 = c3.backgroundImage;
          var solid = b3 && b3 !== 'rgba(0, 0, 0, 0)' && b3 !== 'transparent';
          var painted = i3 && i3 !== 'none';
          if (solid || painted) {
            opaqueAncestor = { tag: up.tagName.toLowerCase(), backgroundColor: solid ? b3 : null, backgroundImage: painted ? imageSummary(i3) : null };
            break;
          }
          up = up.parentElement; hops++;
        }
        rec.ownership = {
          width: Math.round(r2.width),
          height: Math.round(r2.height),
          coverage: varea > 0 ? Math.round((Math.max(0, r2.width) * Math.max(0, r2.height)) / varea * 1000) / 1000 : null,
          backgroundColor: bg2,
          backgroundImage: bgi2 && bgi2 !== 'none' ? imageSummary(bgi2) : null,
          transparent: !bg2 || bg2 === 'rgba(0, 0, 0, 0)' || bg2 === 'transparent',
          opaqueAncestor: opaqueAncestor
        };
      } catch (e6) { rec.ownership = null; }
    }
    out.surfaces.push(rec);
  }
  return out;
  } finally {
    restore();
  }
})()`;
}

// ── Opaque surface audit ───────────────────────────────────────────────────
//
// The question that actually matters is not "does selector X exist" but "which
// element is painting the pixels I can see". A page can have every intended
// selector present and themed -- parent, shell, main, conversation -- and still
// render a stock-black workspace, because one opaque layer between them and the
// content owns the whole viewport. That is the reported regression, and it is
// invisible to a presence check.
//
// This walks the live DOM instead of a fixed selector list, so an UNKNOWN layer
// is reported rather than missed. It is deliberately bounded: only nodes
// covering a real fraction of the viewport, and only those that paint
// something.
//
// PRIVACY. Nothing here reads content. No textContent, no title, no aria-label,
// no href/src, no conversation id. What is emitted per node: tag, the stable
// structural attributes, viewport coverage, computed background colour, a
// colour-only summary of any background-image, and whether Wintage is the
// source. Generated x* class names are reported for DIAGNOSIS only and are
// explicitly not contracts -- the caller cannot turn one into a selector,
// because this tool only prints.
function buildOpaqueExpression(opts) {
  const minCoverage = Number((opts && opts.minCoverage) > 0 ? opts.minCoverage : 0.1);
  const rootSel = (opts && opts.root) || '[data-testid="desktop-app-shell"], #web-mobile-root, #root';
  const tokenNames = JSON.stringify([
    '--chat-background-color', '--app-color-background-surface', '--color-surface',
    '--color-surface-secondary', '--color-background-panel', '--color-token-main-surface-primary',
    '--color-token-main-surface-secondary', '--color-token-main-surface-tertiary',
    '--color-token-side-bar-background', '--composer-background-color', '--composer-surface',
    '--user-message-background-color', '--codeblock-background-color', '--background', '--backgroundSoft'
  ]);
  return `(function(){
  var ROOT = ${JSON.stringify(rootSel)};
  var MIN = ${minCoverage};
  var TOKEN_NAMES = ${tokenNames};
  var ALLOWED = ['id','role','data-testid','data-w95','data-w95-ver','data-state'];
  var w95sheets = [].slice.call(document.querySelectorAll('style[data-w95]'));
  var imageSummary = function (v) {
    var s = String(v || '');
    var kind = s.indexOf('gradient(') !== -1 ? 'gradient' : (s.indexOf('url(') !== -1 ? 'image' : 'other');
    var colors = [], re = /(#[0-9a-f]{3,8}|rgba?\\([^)]*\\))/gi, m;
    while ((m = re.exec(s)) !== null && colors.length < 8) colors.push(m[1].toLowerCase());
    return { kind: kind, colors: colors };
  };
  var isClear = function (c) { return !c || c === 'rgba(0, 0, 0, 0)' || c === 'transparent'; };
  // The palette Wintage is painting RIGHT NOW, resolved through the same scratch
  // node the main probe uses, so "is this Wintage-coloured" is asked against the
  // live theme rather than a hex copied out of the source.
  var scratch = document.createElement('span');
  scratch.style.cssText = 'position:absolute;left:-9999px;top:0;width:1px;height:1px;visibility:hidden';
  try { (document.body || document.documentElement).appendChild(scratch); } catch (e0) { }
  var tokenColor = function (name) {
    scratch.style.backgroundColor = '';
    scratch.style.backgroundColor = 'var(' + name + ')';
    var v = getComputedStyle(scratch).backgroundColor;
    return isClear(v) ? null : v;
  };
  var palette = {};
  try { for (var t = 0; t < TOKEN_NAMES.length; t++) palette[TOKEN_NAMES[t]] = tokenColor(TOKEN_NAMES[t]); } catch (e1) { }
  try { if (scratch.parentNode) scratch.parentNode.removeChild(scratch); } catch (e2) { }

  var root = document.querySelector(ROOT);
  // Attribution is only meaningful when Wintage is actually running. With no
  // injected sheet, every semantic token on the page is CHATGPT's own, so
  // resolving them and calling a match "Wintage's" would report a perfectly
  // unthemed page as themed -- the exact class of false green this mode exists
  // to remove. With the theme off, nothing is attributable.
  var attributionLive = w95sheets.length > 0 && document.documentElement.hasAttribute('data-w95-chatgpt');
  var out = { url_host: location.host, root_found: !!root, min_coverage: MIN,
    wintage: { stamped: document.documentElement.hasAttribute('data-w95-chatgpt'), sheets: w95sheets.length, attribution_live: attributionLive },
    palette: palette, viewport: { width: document.documentElement.clientWidth, height: document.documentElement.clientHeight },
    nodes: [], stock_nodes: 0 };
  if (!root) return out;
  var vw = out.viewport.width, vh = out.viewport.height, varea = vw * vh;
  var all = [root].concat(Array.prototype.slice.call(root.querySelectorAll('*')));
  var seen = [];
  for (var i = 0; i < all.length; i++) {
    var el = all[i];
    var cs = getComputedStyle(el);
    if (cs.visibility === 'hidden' || cs.display === 'none') continue;
    if (isClear(cs.backgroundColor) && (!cs.backgroundImage || cs.backgroundImage === 'none')) continue;
    var r = el.getBoundingClientRect();
    if (!(r.width > 0 && r.height > 0)) continue;
    var cov = varea > 0 ? (r.width * r.height) / varea : 0;
    if (cov < MIN) continue;
    var bg = cs.backgroundColor;
    var bgi = cs.backgroundImage && cs.backgroundImage !== 'none' ? imageSummary(cs.backgroundImage) : null;
    // Wintage attribution: does this node's own colour equal a live palette
    // token? Not "is an ancestor themed" -- the whole failure mode is a themed
    // ancestor under an unthemed child.
    var owner = null;
    if (attributionLive) {
      for (var k in palette) {
        if (Object.prototype.hasOwnProperty.call(palette, k) && palette[k] && palette[k] === bg) { owner = k; break; }
      }
    }
    var rec = {
      tag: el.tagName.toLowerCase(),
      coverage: Math.round(cov * 1000) / 1000,
      width: Math.round(r.width), height: Math.round(r.height),
      backgroundColor: bg,
      backgroundImage: bgi,
      vintageToken: owner,
      position: cs.position
    };
    for (var a = 0; a < ALLOWED.length; a++) {
      var av = el.getAttribute(ALLOWED[a]);
      if (av !== null && av !== undefined) rec[ALLOWED[a]] = String(av).slice(0, 120);
    }
    // Generated atomic classes, for diagnosis only. They are reported so an
    // operator can recognise a build artefact when one shows up, and they are
    // never a contract: nothing in this file turns a class name into a selector.
    var cls = (el.getAttribute('class') || '').trim();
    if (cls) rec.class_sample = cls.split(/\\s+/).filter(function (c) { return /^x[0-9a-z]{5,}$/.test(c); }).slice(0, 4).join(' ');
    out.nodes.push(rec);
  }
  out.nodes.sort(function (p, q) { return q.coverage - p.coverage; });
  // The verdict: a large opaque region that is NOT one of Wintage's own palette
  // colours is the regression, whatever it is called.
  for (var n = 0; n < out.nodes.length; n++) if (!out.nodes[n].vintageToken) out.stock_nodes++;
  return out;
})()`;
}

// The exit decision, separated from main() so it can be driven without a
// browser. stock_nodes > 0 was the whole test, and a probe that found no app
// shell at all reports zero stock nodes -- so the command exited 0 on exactly
// the page it exists to catch, while the console warned "NOT FOUND -- nothing
// under the app shell was audited". An audit that measured nothing is not a
// pass (T-391).
function opaqueGateRed(report) {
  if (!report || typeof report !== 'object') return true;
  if (report.root_found === false) return true;
  return Number(report.stock_nodes) > 0;
}

function opaqueGateReason(report) {
  if (!report || typeof report !== 'object') return 'no opaque report was produced';
  if (report.root_found === false) return 'the app shell was not found: nothing under it was audited';
  return Number(report.stock_nodes) > 0 ? 'a large opaque region is painting a colour Wintage does not own' : '';
}

// The mirror case for `rules`: "this element no longer exists" is an answer,
// not a clean check. The neighbouring malformed-CDP path already throws for
// the same class of failure one screen away (T-392).
function rulesGateRed(found) {
  return !(found && found.nodeId);
}

function sanitizeOpaqueReport(raw) {
  if (!raw || typeof raw !== 'object') throw new Error('Malformed opaque report');
  const out = {
    url_host: typeof raw.url_host === 'string' ? raw.url_host.slice(0, 120) : null,
    root_found: !!raw.root_found,
    min_coverage: Number.isFinite(raw.min_coverage) ? raw.min_coverage : 0.1,
    wintage: {
      stamped: !!(raw.wintage && raw.wintage.stamped),
      sheets: Number(raw.wintage && raw.wintage.sheets) || 0,
      // Carried explicitly, because "no node could be attributed" and "every
      // node was attributed" are opposite findings that look identical in the
      // node list alone.
      attribution_live: !!(raw.wintage && raw.wintage.attribution_live)
    },
    viewport: {
      width: Number(raw.viewport && raw.viewport.width) || 0,
      height: Number(raw.viewport && raw.viewport.height) || 0
    },
    palette: {},
    nodes: [],
    stock_nodes: Number(raw.stock_nodes) || 0
  };
  const pal = (raw.palette && typeof raw.palette === 'object') ? raw.palette : {};
  for (const k of Object.keys(pal)) {
    if (/^--[a-z0-9-]+$/i.test(k) && (typeof pal[k] === 'string' || pal[k] === null)) {
      out.palette[k] = typeof pal[k] === 'string' ? pal[k].slice(0, 60) : null;
    }
  }
  for (const n of (Array.isArray(raw.nodes) ? raw.nodes : [])) {
    if (!n || typeof n !== 'object' || typeof n.tag !== 'string') continue;
    const rec = { tag: n.tag.slice(0, 20) };
    if (Number.isFinite(n.coverage)) rec.coverage = Math.max(0, Math.min(1, n.coverage));
    if (Number.isFinite(n.width)) rec.width = Math.round(n.width);
    if (Number.isFinite(n.height)) rec.height = Math.round(n.height);
    if (typeof n.backgroundColor === 'string') rec.backgroundColor = n.backgroundColor.slice(0, 60);
    rec.backgroundImage = sanitizeImageSummary(n.backgroundImage);
    if (typeof n.vintageToken === 'string') rec.vintageToken = n.vintageToken.slice(0, 60);
    if (typeof n.position === 'string') rec.position = n.position.slice(0, 20);
    for (const k of ['id', 'role', 'data-testid', 'data-w95', 'data-state']) {
      if (typeof n[k] === 'string') rec[k] = n[k].slice(0, 120);
    }
    if (typeof n.class_sample === 'string') rec.class_sample = n.class_sample.slice(0, 80);
    out.nodes.push(rec);
  }
  return out;
}

function renderOpaqueConsole(report) {
  const L = [];
  L.push('host    : ' + report.url_host);
  L.push('wintage : stamp=' + report.wintage.stamped + ' sheets=' + report.wintage.sheets +
    '  attribution=' + (report.wintage.attribution_live ? 'live' : 'OFF -- no colour below can be credited to Wintage'));
  L.push('viewport: ' + report.viewport.width + 'x' + report.viewport.height +
    '   threshold: >= ' + Math.round(report.min_coverage * 100) + '% of viewport');
  L.push('root    : ' + (report.root_found ? 'found' : 'NOT FOUND -- nothing under the app shell was audited'));
  L.push('');
  if (!report.nodes.length) {
    L.push('no opaque node above the threshold. Either the page is fully themed, or the');
    L.push('app shell root selector did not match -- check with `rules`.');
    return L.join('\n');
  }
  L.push('-- ' + report.nodes.length + ' opaque node(s) above threshold, ' + report.stock_nodes + ' NOT a Wintage palette colour --');
  for (const n of report.nodes) {
    L.push('  ' + (n.vintageToken ? 'wintage ' : 'STOCK   ') +
      String(Math.round((n.coverage || 0) * 100) + '%').padStart(4) +
      '  ' + n.tag.padEnd(10) +
      (n['data-testid'] ? '[data-testid=' + n['data-testid'] + ']' : (n.id ? '#' + n.id : '')).padEnd(46) +
      ' bg=' + n.backgroundColor +
      (n.backgroundImage ? ' img=' + n.backgroundImage.kind + '[' + n.backgroundImage.colors.join(' ') + ']' : ''));
    if (!n.vintageToken) L.push('           ^^ NOT a Wintage palette colour -- this node owns stock pixels' +
      (n.class_sample ? '  (generated classes, diagnostic only: ' + n.class_sample + ')' : ''));
  }
  L.push('');
  L.push('Generated x* classes are printed for DIAGNOSIS ONLY. They are rehashed on');
  L.push('every rollout and must never become a stylesheet contract.');
  return L.join('\n');
}

// ── Node-side report handling (pure; the RED controls drive this) ──────────

// The privacy boundary. The in-page probe already emits an allowlist, but a
// single misspelled key in a future edit would otherwise walk straight out of
// this tool, so the report is REBUILT here from the allowlist rather than
// filtered. Anything not named simply does not survive.
const ALLOWED_STYLE_KEYS = new Set(DEFAULT_PROPS.concat(LAYOUT_PROPS));
const ALLOWED_NODE_KEYS = new Set([
  'tag', 'id', 'role', 'data-testid', 'data-w95', 'data-w95-ver', 'aria-pressed',
  'aria-selected', 'aria-expanded', 'aria-haspopup', 'aria-modal', 'data-state', 'contenteditable'
]);
// Named explicitly so the RED control can assert on its absence: a sidebar or
// project entry puts the conversation or project title in aria-label, and this
// tool reports structure, not what the user was talking about.
const NEVER_EMITTED_NODE_KEYS = ['aria-label', 'title', 'alt', 'placeholder', 'value'];

// Viewport ownership has its OWN allowlist, rebuilt here rather than filtered,
// for the same reason the style allowlist is: a key that is not named must not
// be able to survive. The image summary carries colours only -- never a url, a
// path or a fragment -- so it cannot become a channel for private content.
const OWNERSHIP_KEYS = new Set([
  'width', 'height', 'coverage', 'backgroundColor', 'backgroundImage',
  'transparent', 'opaqueAncestor'
]);

function sanitizeImageSummary(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const kind = ['gradient', 'image', 'other'].includes(raw.kind) ? raw.kind : 'other';
  const colors = Array.isArray(raw.colors)
    ? raw.colors.filter(c => typeof c === 'string' && /^(#[0-9a-f]{3,8}|rgba?\([0-9.,\s/%-]+\))$/i.test(c)).slice(0, 8)
    : [];
  return { kind, colors };
}

function sanitizeOpaqueAncestor(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const out = {};
  if (typeof raw.tag === 'string' && /^[a-z][a-z0-9-]{0,20}$/i.test(raw.tag)) out.tag = raw.tag.toLowerCase();
  if (typeof raw.backgroundColor === 'string' && raw.backgroundColor.length <= 60) out.backgroundColor = raw.backgroundColor;
  if (raw.backgroundImage) out.backgroundImage = sanitizeImageSummary(raw.backgroundImage);
  return out.tag ? out : null;
}

function sanitizeOwnership(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const out = {};
  for (const k of ['width', 'height']) {
    if (Number.isFinite(raw[k])) out[k] = Math.round(raw[k]);
  }
  if (Number.isFinite(raw.coverage)) out.coverage = Math.max(0, Math.min(1, raw.coverage));
  if (typeof raw.backgroundColor === 'string' && raw.backgroundColor.length <= 60) out.backgroundColor = raw.backgroundColor;
  out.backgroundImage = sanitizeImageSummary(raw.backgroundImage);
  out.transparent = raw.transparent === true;
  if (raw.opaqueAncestor) out.opaqueAncestor = sanitizeOpaqueAncestor(raw.opaqueAncestor);
  return Object.keys(out).length ? out : null;
}

function sanitizeStyle(style) {
  if (!style || typeof style !== 'object') return null;
  const out = {};
  for (const k of Object.keys(style)) {
    if (ALLOWED_STYLE_KEYS.has(k) && typeof style[k] === 'string') out[k] = style[k].slice(0, 200);
  }
  return out;
}

function sanitizeNode(node) {
  if (!node || typeof node !== 'object') return null;
  const out = {};
  for (const k of Object.keys(node)) {
    if (ALLOWED_NODE_KEYS.has(k) && typeof node[k] === 'string') out[k] = node[k].slice(0, 120);
  }
  return out.tag ? out : null;
}

function sanitizePageReport(raw) {
  if (!raw || typeof raw !== 'object' || !Array.isArray(raw.surfaces)) {
    throw new Error('Malformed page report: expected an object with a surfaces array');
  }
  const out = {
    url_host: typeof raw.url_host === 'string' ? raw.url_host.slice(0, 120) : null,
    route: typeof raw.route === 'string' ? raw.route.slice(0, 200) : null,
    // Whether the run actually attributed the cascade. A report that claims a
    // verdict without having switched Wintage off is weaker than it looks, so
    // the mode travels with the evidence.
    attribute: raw.attribute === true,
    wintage: {
      stamped: !!(raw.wintage && raw.wintage.stamped),
      sheets: Number.isFinite(raw.wintage && raw.wintage.sheets) ? raw.wintage.sheets : 0
    },
    tokens: {},
    surfaces: []
  };
  const tokens = (raw.tokens && typeof raw.tokens === 'object') ? raw.tokens : {};
  for (const k of Object.keys(tokens)) {
    if (/^--[a-z0-9-]+$/i.test(k) && (typeof tokens[k] === 'string' || tokens[k] === null)) {
      out.tokens[k] = typeof tokens[k] === 'string' ? tokens[k].slice(0, 80) : null;
    }
  }
  for (const s of raw.surfaces) {
    if (!s || typeof s !== 'object' || typeof s.id !== 'string') continue;
    // Cascade attribution: which properties Wintage is the source of. Rebuilt
    // from the same style allowlist, so it can never widen what the report emits.
    let owns = null;
    if (s.vintageOwns && typeof s.vintageOwns === 'object') {
      owns = {};
      for (const k of Object.keys(s.vintageOwns)) {
        if (ALLOWED_STYLE_KEYS.has(k)) owns[k] = !!s.vintageOwns[k];
      }
    }
    out.surfaces.push({
      id: s.id.slice(0, 60),
      label: typeof s.label === 'string' ? s.label.slice(0, 120) : '',
      selector: typeof s.selector === 'string' ? s.selector.slice(0, 300) : null,
      // Carried, not trusted: contractOf() resolves the matrix entry first. Kept
      // so a record built outside the probe still says what it claimed.
      required: !!s.required,
      contract: CONTRACT_KEYS.includes(s.contract) ? s.contract : undefined,
      present: !!s.present,
      routeMatched: s.routeMatched === true ? true : undefined,
      routeOnly: s.routeOnly === true ? true : undefined,
      count: Number.isFinite(s.count) ? s.count : (s.present ? 1 : 0),
      visible: typeof s.visible === 'boolean' ? s.visible : null,
      style: sanitizeStyle(s.style),
      withoutWintage: sanitizeStyle(s.withoutWintage),
      vintageOwns: owns,
      // Viewport ownership travels with every surface, but is deliberately NOT
      // in fingerprintPageReport(): coverage moves continuously as the operator
      // scrolls, and folding it into the change-detection key would make every
      // poll of a long conversation a "unique observation".
      ownership: sanitizeOwnership(s.ownership),
      node: sanitizeNode(s.node)
    });
  }
  return out;
}

// A report is only comparable to another report if identity ignores everything
// that changes between polls. Watch mode re-probes every two seconds over a
// fifteen-minute operator pass; without this it would emit the same twenty-six
// surfaces hundreds of times and bury the one thing that actually changed.
function fingerprintPageReport(report) {
  const parts = report.surfaces.map(s => [
    s.id,
    s.present ? 1 : 0,
    s.count,
    s.visible === null ? '?' : (s.visible ? 1 : 0),
    s.style ? JSON.stringify(s.style) : '',
    s.wintageOwns ? JSON.stringify(s.vintageOwns) : '',
    s.node ? JSON.stringify(s.node) : ''
  ].join('|'));
  return report.route + '::' + report.wintage.stamped + '::' + report.url_host + '::' + parts.join(';');
}

function collectUnique(seen, report) {
  const key = fingerprintPageReport(report);
  if (seen.has(key)) return { fresh: [], duplicate: true, total: seen.size };
  seen.add(key);
  return { fresh: [report], duplicate: false, total: seen.size };
}

// A surface is a MISMATCH when it is present and its colour is not Wintage's
// live token for that surface. The value names the semantic variable the
// surface is supposed to consume, and may be an ARRAY when the surface
// legitimately consumes one of several Wintage surface tokens -- a bounded
// allowed palette, which is a contract rather than a guess, unlike inventing a
// selector to make a gate green.
//
// The keys here are surface ids. They were not always: this map carried
// `assistant` while the matrix's id is `assistant-message`, so the assistant
// message could never reach a themed or mismatch classification and every run
// silently reported it as unproven. A key that names no surface is a dead
// expectation, which is why test-inspect-web.js fails on one.
const SURFACE_TOKENS = {
  // `html` is NOT held to --chat-background-color. paintRoot sets
  // background-color: T.background !important INLINE on <html> for every host
  // (wintage.user.js:536), and an inline !important outranks the !important in
  // CHATGPT_FAST_CSS, so the stylesheet's backgroundSoft never wins there. Proven
  // live on a signed-in chatgpt.com tab: <html> computes to rgb(26, 24, 16) =
  // #1A1810 = T.background, while --chat-background-color resolves to #232018.
  // Expecting the stylesheet's value made a correct page report a mismatch on
  // every single poll, which is how a ticket can stay blocked forever on a run
  // that has nothing to find.
  root: '--background',
  'root-body': '--chat-background-color',
  'root-app': '--chat-background-color',
  'app-shell': '--chat-background-color',
  // The scroll container is a full-viewport surface, so it is held to the same
  // token as the shell above it. Naming it here is what turns "the selector
  // exists in the stylesheet" into "the pixels you can see are Wintage's".
  'app-scroll-container': '--chat-background-color',
  conversation: '--chat-background-color',
  'conversation-region': '--chat-background-color',
  'nav-entry': '--color-token-side-bar-background',
  // Measured 2026-10-04 on /settings/general-settings in a signed-in tab: <main>
  // computes to rgb(35, 32, 24) = backgroundSoft, the same token the conversation
  // main is held to. settings-nav is still a guess -- the live Settings route
  // renders no [role=navigation] and no data-testid for it -- so it stays.
  'settings-page': '--chat-background-color',
  // Measured 2026-10-04 on /settings/plugins-settings (which is where
  // /settings/connectors redirects today): the Customize main computes to
  // rgb(35, 32, 24), the same backgroundSoft token. settings-nav stays unproven --
  // that route renders no navigation landmark at all, so there is nothing to read.
  customize: '--chat-background-color',
  thread: '--chat-background-color',
  sidebar: '--color-token-side-bar-background',
  'sidebar-legacy-slideover': '--color-token-side-bar-background',
  'sidebar-legacy-tiny': '--color-token-side-bar-background',
  'user-message': '--user-message-background-color',
  // The assistant markdown root paints nothing of its own; its nearest opaque
  // ancestor on the live tab is the same <main> the conversation surface is held
  // to. TRANSPARENT_HOSTS says so explicitly below.
  'assistant-message': '--chat-background-color',
  'composer-root': '--composer-background-color',
  'composer-body': '--composer-background-color',
  // Measured 2026-10-04 on a signed-in tab with the product's own sheet injected.
  // These four carry their container's token and are declared transparent hosts
  // below: the product paints the container and leaves the child alone, so reading
  // the child alone would either report UNPROVEN (no expectation) or MISMATCH
  // (transparent, correct) -- neither of which is a finding about the page.
  'prompt-editor': '--composer-background-color',
  'code-block-actions': '--codeblock-background-color',
  // An open dialog is painted surfaceRaised on the live tab (rgb(61, 55, 42) =
  // #3D372A). --surfaceRaised is declared by CHATGPT_FAST_CSS on :root
  // (wintage.user.js:1879), so this is the product's own token, not a copy.
  // CHATGPT_FAST_CSS paints ALL of these in ONE rule (wintage.user.js:1926):
  //   dialog, [popover], [role="menu"], [role="listbox"], [role="dialog"],
  //   [role="alertdialog"] { background-color: T.surfaceRaised !important; ... }
  // so menu, listbox and popover are not three guesses -- they are the same
  // authored selector list dialog already proved. menu was then MEASURED live on
  // 2026-10-04 (aria-haspopup="menu" opened, [role="menu"] computed to
  // rgb(61, 55, 42)). listbox and popover still carry the same token WITHOUT a
  // live observation: today's shell opens only menu and dialog overlays
  // (aria-haspopup is {menu, dialog} and there are zero [popover] attributes),
  // so they remain in requiredCoverageNotObserved rather than pretending otherwise.
  dialog: '--surfaceRaised',
  menu: '--surfaceRaised',
  listbox: '--surfaceRaised',
  popover: '--surfaceRaised',
  // Measured 2026-10-04 on /settings/plugins-settings: nav[aria-label="Settings"]
  // is transparent, sits inside #app-shell-sidebar, and its nearest opaque
  // ancestor computes to rgb(26, 24, 16) -- the sidebar token below. The old
  // selector, 'main nav', could not see it at all: this navigation renders
  // OUTSIDE <main> and carries no [role=navigation], which is why the surface
  // had read as "the live route renders no navigation landmark".
  'settings-nav': '--color-token-side-bar-background',
  'code-block': '--codeblock-background-color',
  'code-block-pre': '--codeblock-background-color',
  'thread-footer': '--chat-background-color'
};

const CONTRACT_KEYS = [CONTRACT.ALWAYS, CONTRACT.COVERAGE, CONTRACT.OPTIONAL];
const SCOPE_KEYS = [SCOPE.ANY, SCOPE.CONVERSATION, SCOPE.SETTINGS];

function matrixEntry(id) { return SURFACES.find(s => s.id === id) || null; }

// The matrix is authoritative. A report built by the probe carries a contract
// too, but a hand-built or replayed record must not be able to downgrade its own
// acceptance class -- otherwise anything that can write a report can decide that
// the gate does not apply to it.
function contractOf(surface) {
  const entry = matrixEntry(surface.id);
  const c = (entry && entry.contract) || surface.contract ||
    (surface.required ? CONTRACT.ALWAYS : CONTRACT.OPTIONAL);
  return CONTRACT_KEYS.includes(c) ? c : CONTRACT.OPTIONAL;
}

function scopeOf(surface) {
  const entry = matrixEntry(surface.id);
  const s = (entry && entry.scope) || surface.scope || SCOPE.ANY;
  return SCOPE_KEYS.includes(s) ? s : SCOPE.ANY;
}

// Does this surface have any business being judged on the page we are looking
// at? A route-gated surface is judged only on its own route, and a
// conversation-scoped one is not judged at all while the operator is on
// Settings. The page's own route verdict is preferred -- it was computed
// against the real pathname, which no amount of redaction can preserve.
function surfaceApplies(surface, path) {
  const entry = matrixEntry(surface.id);
  if (surface.routeOnly === true) return false;
  if (surface.routeMatched === true) return true;
  if (entry && entry.route) return typeof path === 'string' && entry.route.test(path);
  const scope = scopeOf(surface);
  if (scope === SCOPE.CONVERSATION) return !isSettingsRoute(path);
  if (scope === SCOPE.SETTINGS) return isSettingsRoute(path);
  return true;
}

function classifySurface(surface, tokens, route) {
  const path = typeof route === 'string' ? route : (typeof surface.route === 'string' ? surface.route : '');
  if (!surfaceApplies(surface, path)) return { state: 'not-applicable', why: null };
  const contract = contractOf(surface);
  if (!surface.present) {
    // An 'always' contract that did not match IS a regression. A 'coverage'
    // contract that did not match on this poll is not: the operator has not
    // opened that surface yet, and the session-level aggregation is where that
    // is decided.
    return contract === CONTRACT.ALWAYS
      ? { state: 'MISSING', why: 'required contract did not match in the live DOM on ' + (path || '/') }
      : { state: 'absent', why: null };
  }
  // No token expectation is NOT the same as a pass. It means this surface is
  // only being recorded structurally, and saying so is the whole point: a gate
  // that calls an unexamined surface "themed" reports a fully themed page for a
  // page it never actually checked.
  const token = SURFACE_TOKENS[surface.id];
  if (!token) return { state: 'unproven', why: 'no token expectation defined for this surface' };
  const wanted = Array.isArray(token) ? token : [token];
  const resolved = wanted.map(t => ({ token: t, value: tokens ? tokens[t] : null }));
  if (!resolved.some(r => r.value)) {
    return { state: 'unproven', why: 'token ' + wanted.join(' | ') + ' resolved to nothing on this page' };
  }
  const got = surface.style && surface.style.backgroundColor;
  if (!got) return { state: 'unproven', why: 'no background-color was readable' };
  if (!resolved.some(r => r.value === got)) {
    return {
      state: 'MISMATCH',
      why: 'background-color ' + got + ' is not ' + wanted.join(' | ') +
        ' (' + resolved.map(r => r.token + '=' + r.value).join(', ') + ')'
    };
  }
  return { state: 'themed', why: null };
}

function summarize(report) {
  const tokens = report.tokens || {};
  const route = typeof report.route === 'string' ? report.route : '';
  const observed = [];
  const mismatches = [];
  const missing = [];
  const unproven = [];
  const notApplicable = [];
  for (const s of report.surfaces) {
    const c = classifySurface(s, tokens, route);
    if (c.state === 'not-applicable') { notApplicable.push(s.id); continue; }
    if (c.state === 'absent') continue;                 // not open yet, or optional: not a finding
    if (c.state === 'themed') { observed.push({ id: s.id, state: c.state, count: s.count }); continue; }
    if (c.state === 'MISMATCH') { mismatches.push({ id: s.id, label: s.label, selector: s.selector, why: c.why, style: s.style }); continue; }
    if (c.state === 'MISSING') { missing.push({ id: s.id, label: s.label, selector: s.selector, why: c.why }); continue; }
    unproven.push({ id: s.id, label: s.label, why: c.why });
  }
  reconcileComposerPair(report, observed, mismatches, unproven);
  reconcileTransparentHosts(report, observed, mismatches, unproven);
  return { observed, mismatches, missing, unproven, notApplicable };
}

// The composer has TWO surface contracts, not one: under the `default` utility-bar
// variant the product paints [data-composer-dark] itself and leaves its body alone,
// and under `home` it deliberately leaves that root layout-only and paints
// [data-composer-body] instead (wintage.user.js:1621-1633). Whichever variant a live
// tab is on, the member that variant does NOT paint is transparent on a page that is
// correct -- and both shapes were measured live on signed-in tabs -- so SURFACE_TOKENS,
// which names one token per surface, cannot express it.
//
// Corrected here rather than in classifySurface, and that placement is the point: the
// root's conformance DEPENDS ON ITS SIBLING, which a per-surface call cannot see.
// Transparency is accepted only while the OTHER member is observed AND themed, so
// "this one is transparent" can never launder "nothing painted the composer" -- a stock
// composer with no themed sibling on either side keeps failing both ways.
function reconcileComposerPair(report, observed, mismatches, unproven) {
  const surfaces = report.surfaces || [];
  const byId = id => surfaces.find(s => s.id === id);
  const clear = (id, sibling) => {
    const el = byId(id);
    if (!el || !el.style || el.style.backgroundColor !== 'rgba(0, 0, 0, 0)') return;
    if (!observed.some(o => o.id === sibling)) return;    // no themed sibling: the mismatch stands
    const mis = mismatches.findIndex(m => m.id === id);
    if (mis < 0) return;                                  // already absent/unproven; nothing to correct
    mismatches.splice(mis, 1);
    observed.push({ id, state: 'themed', count: el.count });
    const stray = unproven.findIndex(u => u.id === id);
    if (stray >= 0) unproven.splice(stray, 1);
  };
  clear('composer-root', 'composer-body');                 // the `home` variant
  clear('composer-body', 'composer-root');                 // the `default` variant
}

// Some surfaces are painted by their CONTAINER and are deliberately transparent
// themselves: a nav entry inside a themed sidebar, the editor inside a themed
// composer, the scroll viewport inside a themed <main>. Each is mapped to the one
// surface that must be themed for its own transparency to be correct, measured
// 2026-10-04 on a signed-in tab. This is the same reasoning as the composer pair,
// generalized: the surface's conformance depends on something the per-surface call
// cannot see.
//
// It cannot launder an unthemed page. The container has to be OBSERVED AND THEMED in
// the same report: on a stock page every container is itself a mismatch, nothing
// clears, and each of these still reports what it reports today.
const TRANSPARENT_HOSTS = {
  'nav-entry': 'sidebar',
  'settings-nav': 'sidebar',
  'assistant-message': 'conversation',
  'prompt-editor': 'composer-root',
  'code-block-actions': 'code-block',
  'app-scroll-container': 'root-body'
};

function reconcileTransparentHosts(report, observed, mismatches, unproven) {
  const themed = new Set(observed.map(o => o.id));
  const surfaces = report.surfaces || [];
  for (const id of Object.keys(TRANSPARENT_HOSTS)) {
    if (!themed.has(TRANSPARENT_HOSTS[id])) continue;      // the container is not themed: the mismatch stands
    const el = surfaces.find(s => s.id === id);
    if (!el || !el.style || el.style.backgroundColor !== 'rgba(0, 0, 0, 0)') continue;
    const mis = mismatches.findIndex(m => m.id === id);
    if (mis >= 0) mismatches.splice(mis, 1);
    else continue;                                         // already themed/absent
    observed.push({ id, state: 'themed', count: el.count });
    const stray = unproven.findIndex(u => u.id === id);
    if (stray >= 0) unproven.splice(stray, 1);
  }
}

// ── Session aggregation ────────────────────────────────────────────────────
// A bounded watch pass is a SESSION, not a sequence of independent verdicts.
// The previous aggregation unioned every transient absence into `missingEver`,
// so a code block that was absent on the first poll and correctly observed on
// the second still finished the pass as a failure. That made the requested
// multi-route operator pass structurally incapable of returning a trustworthy
// answer: the operator cannot do 900 seconds of navigation without a single
// early poll missing something contextual.
//
// Coverage is therefore decided once, over the whole session. A contextual
// surface is satisfied by having been OBSERVED at least once -- being wrong
// still counts as observed, because the mismatch is reported separately and
// must not be laundered into "never seen".
function aggregateWatch(observations) {
  const observedEver = new Set();
  const mismatchedEver = new Set();
  const unprovenEver = new Set();
  const requiredMissingEver = new Set();
  const presentEver = new Set();
  const seen = [];
  for (const r of observations) {
    if (!r || !Array.isArray(r.surfaces)) continue;
    seen.push(r);
    const s = summarize(r);
    for (const o of s.observed) { observedEver.add(o.id); presentEver.add(o.id); }
    for (const m of s.mismatches) { mismatchedEver.add(m.id); presentEver.add(m.id); }
    for (const m of s.missing) requiredMissingEver.add(m.id);
    for (const u of s.unproven) { unprovenEver.add(u.id); presentEver.add(u.id); }
  }
  const coverageNeeded = SURFACES.filter(s => s.contract === CONTRACT.COVERAGE).map(s => s.id);
  const optionalIds = SURFACES.filter(s => s.contract === CONTRACT.OPTIONAL).map(s => s.id);
  // An always-required contract that was never seen on ANY poll fails the same
  // way one that was seen and did not match. Without this, a watch pass whose
  // polls all failed -- or produced nothing at all -- would report an empty
  // sheet of findings and read as a clean run.
  for (const s of SURFACES) {
    if (s.contract === CONTRACT.ALWAYS && !presentEver.has(s.id)) requiredMissingEver.add(s.id);
  }
  const requiredCoverageNotObserved = coverageNeeded.filter(id => !presentEver.has(id));
  const optionalNotObserved = optionalIds.filter(id => !presentEver.has(id));
  // A requested surface that was opened and could not be judged is the failure
  // mode that let Settings and menus exit green while proving nothing.
  //
  // The OTHER failure mode is a requested surface that was never opened at all,
  // and it used to slip through: this came from unprovenEver alone, which by
  // definition holds only surfaces that WERE seen, while the two coverage
  // reasons are contract-scoped and so exempt every CONTRACT.OPTIONAL surface.
  // composer-root and composer-body are optional (the two composer variants --
  // the product paints one and leaves the other's layout transparent) and both
  // are requested for acceptance, so a session that opened neither, or opened
  // only one, produced three empty reason lists and an ACCEPTING verdict. The
  // acceptance declaration says their absence is unresolved work, so absence
  // is folded in here. Scoped to ACCEPTANCE_SURFACES rather than to a contract
  // on purpose: this must not turn every optional surface into a demand, only
  // the ones the operator was actually asked to open.
  const neverObservedAcceptance = [...ACCEPTANCE_SURFACES].filter(id => !presentEver.has(id));
  const unresolvedAcceptance = [...new Set([
    ...[...unprovenEver].filter(id => ACCEPTANCE_SURFACES.has(id)),
    ...neverObservedAcceptance
  ])];
  return {
    observations: seen.length,
    observedEver: [...observedEver],
    mismatchedEver: [...mismatchedEver],
    unprovenEver: [...unprovenEver],
    requiredMissingEver: [...requiredMissingEver],
    requiredCoverageNotObserved,
    optionalNotObserved,
    unresolvedAcceptance,
    neverObservedAcceptance
  };
}

function watchVerdict(agg) {
  const reasons = [];
  if (agg.mismatchedEver.length) reasons.push(agg.mismatchedEver.length + ' surface(s) mismatched');
  if (agg.requiredMissingEver.length) reasons.push(agg.requiredMissingEver.length + ' always-required surface(s) never matched or never seen');
  if (agg.requiredCoverageNotObserved.length) reasons.push(agg.requiredCoverageNotObserved.length + ' requested surface(s) never observed');
  // Both halves name themselves: "observed but UNPROVEN" was a lie for a surface
  // the operator never opened, and the reason string is what the operator reads.
  if (agg.unresolvedAcceptance.length) {
    reasons.push(agg.unresolvedAcceptance.length + ' requested surface(s) unresolved' +
      (agg.neverObservedAcceptance.length ? ': NEVER OPENED ' + agg.neverObservedAcceptance.join(', ') : '') +
      (agg.unprovenEver.length ? ': observed but UNPROVEN ' + agg.unprovenEver.join(', ') : ''));
  }
  return { accept: reasons.length === 0, reasons, unresolvedAcceptance: agg.unresolvedAcceptance };
}

function renderConsole(report, summary) {
  const L = [];
  L.push('host    : ' + report.url_host + report.route);
  L.push('wintage : stamp=' + report.wintage.stamped + ' sheets=' + report.wintage.sheets);
  L.push('');
  L.push('-- observed ' + summary.observed.length + ' / ' + report.surfaces.length + ' surfaces --');
  for (const s of report.surfaces) {
    const c = classifySurface(s, report.tokens, report.route);
    const mark = c.state === 'themed' ? 'THEMED  ' : c.state === 'observed' ? 'observed'
      : c.state === 'absent' ? 'absent  ' : c.state === 'not-applicable' ? 'n/a      ' : c.state.toUpperCase();
    const bg = s.style && s.style.backgroundColor ? ' bg=' + s.style.backgroundColor : '';
    const ctr = contractOf(s);
    L.push('  [' + mark + '] ' + s.id.padEnd(26) + ' n=' + String(s.count).padEnd(5) + ' ' + ctr.padEnd(8) + bg);
    if (c.why) L.push('             ' + c.why);
  }
  if (summary.mismatches.length) {
    L.push('');
    L.push('-- MISMATCHES: ' + summary.mismatches.length + ' --');
    for (const m of summary.mismatches) L.push('  ' + m.id + '  ' + m.selector + '\n    ' + m.why);
  }
  if (summary.missing.length) {
    L.push('');
    L.push('-- MISSING ALWAYS-REQUIRED CONTRACTS: ' + summary.missing.length + ' --');
    for (const m of summary.missing) L.push('  ' + m.id + '  ' + m.selector);
  }
  if (summary.unproven.length) {
    L.push('');
    L.push('-- UNPROVEN (observed, but no token expectation): ' + summary.unproven.length + ' --');
    for (const m of summary.unproven) {
      L.push('  ' + m.id + '  ' + m.why +
        (ACCEPTANCE_SURFACES.has(m.id) ? '   [REQUESTED FOR ACCEPTANCE -- NOT ACCEPTING]' : ''));
    }
  }
  L.push('');
  L.push('NOTHING ABOVE IS A VERDICT ON A SURFACE THAT WAS ABSENT. Absent means the');
  L.push('selector did not match in this capture, not that ChatGPT does not paint it.');
  L.push('A CONTEXTUAL surface is decided over the whole session, not on one poll.');
  return L.join('\n');
}

async function evaluate(cdp, expression) {
  let res;
  try {
    res = await cdp.send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
  } catch (e) {
    throw new Error('Runtime.evaluate failed: ' + e.message);
  }
  // A truncated or shape-shifted CDP reply must not read as "nothing found".
  // Every caller above this point treats an empty surface list as a pass, so an
  // unvalidated value here is exactly how a live gate goes falsely green.
  if (res && res.exceptionDetails) {
    const ex = res.exceptionDetails.exception;
    throw new Error('Probe threw in page: ' + ((ex && (ex.description || ex.value)) || res.exceptionDetails.text));
  }
  if (!res || typeof res !== 'object' || !res.result || typeof res.result !== 'object') {
    throw new Error('Malformed CDP response: Runtime.evaluate returned no result object');
  }
  if (res.result.subtype === 'error' || !('value' in res.result)) {
    throw new Error('Malformed CDP response: Runtime.evaluate returned no serializable value');
  }
  return res.result.value;
}

// ── Target display: the boundary the page sanitizer cannot cover ────────────
// The page report is rebuilt from an allowlist, but target metadata leaks
// BEFORE that boundary and no amount of page-side hygiene reaches it. A CDP
// target carries a title and a url, and on chatgpt.com the title is the
// conversation name and the url is the conversation or project id. Four output
// paths used to print one of them raw: the `targets` listing, `targets --json`,
// the attach banner, and the "no page matched" error.
//
// So there is exactly ONE representation, and no other code path in this file
// is allowed to print a target. host + a route whose segments come from a fixed
// vocabulary of ChatGPT route names; everything else is ':id'. That is enough
// to tell two open tabs apart -- chatgpt.com/c/:id versus chatgpt.com/settings/
// apps -- and not enough to say what either one is about. The query and the
// fragment are dropped entirely rather than scrubbed, because a scrubbed query
// is a leak waiting for a parameter nobody has met yet.
const SAFE_ROUTE_SEGMENTS = new Set([
  'c', 'g', 'settings', 'apps', 'connectors', 'plugins', 'gizmos', 'share', 'new',
  'chat', 'chats', 'explore', 'code', 'search', 'conversations', 'projects',
  'account', 'custom', 'customize', 'temporary-chat', 'image', 'images', 'voice',
  'sora', 'canvas', 'memory', 'files', 'tasks', 'admin', 'business', 'enterprise',
  'auth', 'login', 'logout', 'register', 'home', 'about', 'legal', 'privacy',
  'terms', 'help', 'status', 'blog', 'pricing', 'api', 'docs', 'orgs', 'workspace',
  'deep-research', 'code-interpreter'
]);

function sanitizeRoute(path) {
  if (typeof path !== 'string' || path === '') return '/';
  const out = path.split('/').map(seg => (seg === '' ? '' : (SAFE_ROUTE_SEGMENTS.has(seg.toLowerCase()) ? seg : ':id')));
  return out.join('/') || '/';
}

function sanitizeTargetUrl(rawUrl) {
  const cut = String(rawUrl || '').split('#')[0].split('?')[0];
  const m = /^([a-z][a-z0-9+.-]*:)?(\/\/)?([^/?#]*)(\/[^?#]*)?$/i.exec(cut);
  if (!m) return { scheme: null, host: null, path: null, display: '(no url)' };
  const scheme = m[1] ? m[1].slice(0, -1) : null;
  // A target with no authority (`about:blank`, `data:...`) has no path worth
  // printing either: the path IS the payload, and the payload is exactly the
  // kind of thing this function exists to not emit.
  if (!m[2]) return { scheme, host: null, path: null, display: (scheme || 'unknown') + ':(opaque)' };
  const host = m[3].replace(/^.*@/, '');                 // never emit credentials
  const path = sanitizeRoute(m[4] || '/');
  return { scheme, host: host || null, path, display: (scheme || 'https') + '://' + (host || '(no host)') + path };
}

// The ONE shape a target may take on its way out of this tool. The title is
// accepted as input and dropped without being inspected: a title can be a
// conversation name, a project name, or the text of an unsent draft, and there
// is no subset of "safe" titles.
function sanitizeTargetDisplay(target) {
  const url = sanitizeTargetUrl(target && target.url);
  return { type: String((target && target.type) || 'unknown').slice(0, 40), host: url.host, path: url.path, display: url.display };
}

function renderTargetLine(target) { return '[' + sanitizeTargetDisplay(target).display + ']'; }

function targetsJson(pages) {
  return JSON.stringify(pages.map(sanitizeTargetDisplay), null, 1);
}

function renderAttachLine(target) { return 'attached: ' + sanitizeTargetDisplay(target).display; }

function renderNoMatch(urlPart, pages) {
  const seen = (pages || []).map(p => '  ' + sanitizeTargetDisplay(p).display).join('\n') || '  (no page targets)';
  return 'no page whose url contains ' + JSON.stringify(urlPart) + '\nopen pages:\n' + seen;
}

async function pickPage(urlPart) {
  const port = debugPort();
  const pages = await pageTargets(port);
  // Matching uses the RAW url on purpose: a redacted /c/:id would no longer
  // contain the substring the operator typed. Raw never leaves this function.
  const target = pages.find(t => (t.url || '').includes(urlPart));
  if (!target) throw new Error(renderNoMatch(urlPart, pages));
  return target;
}

const sleep = ms => new Promise(r => setTimeout(r, ms));

async function main() {
  const argv = process.argv.slice(2);
  const flags = new Set(argv.filter(a => a.startsWith('--')));
  const rest = argv.filter(a => !a.startsWith('--'));
  const [cmd, a, b] = rest;
  const json = flags.has('--json');
  const attribute = flags.has('--attribute');
  const port = debugPort();

  if (!cmd || cmd === 'targets') {
    const pages = await pageTargets(port);
    if (json) { console.log(targetsJson(pages)); return; }
    for (const t of pages) console.log(renderTargetLine(t));
    return;
  }

  const urlPart = cmd === 'targets' ? '' : (a || 'chatgpt.com');
  const target = await pickPage(urlPart);
  const cdp = connect(target);
  await cdp.ready;
  if (!json) console.error(renderAttachLine(target));

  if (cmd === 'rules') {
    await cdp.send('DOM.enable');
    await cdp.send('CSS.enable');
    const doc = await cdp.send('DOM.getDocument', { depth: 1 });
    if (!doc || !doc.root) throw new Error('Malformed CDP response: DOM.getDocument returned no root');
    const found = await cdp.send('DOM.querySelector', { nodeId: doc.root.nodeId, selector: b });
    if (rulesGateRed(found)) { console.error('selector matched nothing: ' + b); cdp.close(); process.exitCode = 1; return; }
    const res = await cdp.send('CSS.getMatchedStylesForNode', { nodeId: found.nodeId });
    const rules = [];
    for (const e of (res && res.matchedCSSRules) || []) {
      const props = e.rule.style.cssProperties
        .filter(p => p.value && !/^\s*$/.test(p.value))
        .map(p => p.name + ':' + p.value + (p.important ? ' !' : ''));
      if (!props.length) continue;
      const sel = e.rule.selectorList.text;
      rules.push({
        origin: e.rule.origin,
        wintage: sel.includes(WINTAGE_STAMP),
        selector: sel.slice(0, 200),
        properties: props.join('; ').slice(0, 400)
      });
    }
    if (json) { console.log(JSON.stringify(rules, null, 1)); cdp.close(); return; }
    if (res && res.inlineStyle && res.inlineStyle.cssText) console.log('INLINE: ' + res.inlineStyle.cssText.slice(0, 300));
    console.log('--- matched rules (later beats earlier at equal weight) ---');
    for (const r of rules) {
      console.log('[' + r.origin + (r.wintage ? ' WINTAGE' : '') + '] ' + r.selector);
      console.log('        ' + r.properties);
    }
    cdp.close();
    return;
  }

  if (cmd === 'opaque') {
    // The root selector is an argument so the audit can be pointed at a page
    // that has not moved to the current shell yet; the default is the current
    // contract, never a generated class.
    const opaqueRaw = await evaluate(cdp, buildOpaqueExpression({
      minCoverage: envFloat('WINTAGE_OPAQUE_MIN', 0.1),
      root: b || undefined
    }));
    const opaque = sanitizeOpaqueReport(opaqueRaw);
    if (json) console.log(JSON.stringify(opaque, null, 1));
    else console.log(renderOpaqueConsole(opaque));
    cdp.close();
    // Non-zero when a large opaque region is painting a colour Wintage does not
    // own, and equally when the probe could not measure at all (T-391).
    if (opaqueGateRed(opaque)) {
      const why = opaqueGateReason(opaque);
      console.error('opaque audit FAILED: ' + why);
      process.exitCode = 1;
    }
    return;
  }

  if (cmd !== 'surface' && cmd !== 'watch') {
    cdp.close();
    die('usage: targets | surface [url-part] | rules <url-part> <selector> | opaque [url-part] [root-selector] | watch [url-part] [seconds]');
  }

  const expression = buildProbeExpression(SURFACES, { attribute });

  if (cmd === 'surface') {
    const raw = await evaluate(cdp, expression);
    const report = sanitizePageReport(raw);
    const summary = summarize(report);
    if (json) console.log(JSON.stringify({ report, summary }, null, 1));
    else console.log(renderConsole(report, summary));
    cdp.close();
    // A single capture is still an acceptance statement, so it obeys the same
    // rule: a requested surface that is unproven is not a pass.
    const one = aggregateWatch([report]);
    if (summary.mismatches.length || summary.missing.length ||
        one.unresolvedAcceptance.length) process.exitCode = 1;
    return;
  }

  // watch: a bounded operator pass. The operator opens surfaces by hand; the
  // tool records what CHANGES, so the output is a diff of the session rather
  // than fifteen minutes of the same page.
  const seconds = Math.max(5, Number(b) || 900);
  const interval = Number(envInt('WINTAGE_WATCH_INTERVAL', 2000));
  const deadline = Date.now() + seconds * 1000;
  const seen = new Set();
  const unique = [];
  let duplicateCount = 0;
  console.error('watching ' + urlPart + ' for ' + seconds + 's -- navigate by hand; Ctrl-C to stop early');
  while (Date.now() < deadline) {
    const raw = await evaluate(cdp, expression);
    const report = sanitizePageReport(raw);
    const { fresh, duplicate, total } = collectUnique(seen, report);
    if (duplicate) duplicateCount++;
    for (const f of fresh) {
      unique.push(f);
      const s = summarize(f);
      if (json) { console.log(JSON.stringify({ at: new Date().toISOString(), report: f, summary: s })); continue; }
      console.log('\n=== unique observation ' + total + ' :: ' + f.route + ' ===');
      console.log(renderConsole(f, s));
    }
    await sleep(interval);
  }
  const agg = aggregateWatch(unique);
  const verdict = watchVerdict(agg);
  if (json) {
    console.log(JSON.stringify({
      finished: true, urlPart, seconds, uniqueObservations: unique.length,
      duplicatePollsSuppressed: duplicateCount,
      observedEver: agg.observedEver,
      mismatchedEver: agg.mismatchedEver,
      unprovenEver: agg.unprovenEver,
      requiredMissingEver: agg.requiredMissingEver,
      requiredCoverageNotObserved: agg.requiredCoverageNotObserved,
      optionalNotObserved: agg.optionalNotObserved,
      unresolvedAcceptance: agg.unresolvedAcceptance,
      accept: verdict.accept, notAcceptingBecause: verdict.reasons
    }, null, 1));
  } else {
    console.log('\n=== watch finished ===');
    console.log('unique observations : ' + unique.length);
    console.log('duplicate polls     : ' + duplicateCount + ' suppressed');
    const row = (label, list) => console.log(label.padEnd(30) + ': ' + (list.length ? list.join(', ') : 'none'));
    console.log('');
    console.log('-- REQUESTED SURFACES, AS THE SESSION SAW THEM --');
    row('observed + proven themed', agg.observedEver);
    row('observed + MISMATCHED', agg.mismatchedEver);
    row('observed but UNPROVEN', agg.unprovenEver);
    row('requested, NEVER OPENED', agg.neverObservedAcceptance);
    row('required, never observed', agg.requiredCoverageNotObserved);
    console.log('');
    console.log('-- ALWAYS-REQUIRED CONTRACTS --');
    row('never matched', agg.requiredMissingEver);
    console.log('');
    console.log('-- OPTIONAL, absence is not a finding --');
    row('not observed', agg.optionalNotObserved);
    console.log('');
    console.log('ACCEPTANCE VERDICT: ' + (verdict.accept ? 'accept' : 'NOT ACCEPTING'));
    for (const r of verdict.reasons) console.log('  - ' + r);
    if (!verdict.accept) {
      console.log('');
      console.log('An UNPROVEN requested surface is NOT a pass. Until a live run proves which');
      console.log('Wintage semantic token it consumes, it stays unresolved by design.');
    }
  }
  cdp.close();
  if (!verdict.accept) process.exitCode = 1;
}

function envInt(name, fallback) {
  const v = Number(process.env[name]);
  return Number.isInteger(v) && v > 0 ? v : fallback;
}

function envFloat(name, fallback) {
  const v = Number(process.env[name]);
  return Number.isFinite(v) && v > 0 && v <= 1 ? v : fallback;
}

module.exports = {
  SURFACES, DEFAULT_PROPS, LAYOUT_PROPS, SURFACE_TOKENS, TRANSPARENT_HOSTS, NEVER_EMITTED_NODE_KEYS,
  CONTRACT, SCOPE, ACCEPTANCE_SURFACES, DECLARED_UNPROVEN_ACCEPTANCE, SAFE_ROUTE_SEGMENTS,
  buildProbeExpression, sanitizePageReport, sanitizeStyle, sanitizeNode,
  fingerprintPageReport, collectUnique, classifySurface, summarize, renderConsole,
  aggregateWatch, watchVerdict, contractOf, scopeOf, surfaceApplies, isSettingsRoute,
  sanitizeTargetUrl, sanitizeTargetDisplay, sanitizeRoute,
  renderTargetLine, targetsJson, renderAttachLine, renderNoMatch,
  buildOpaqueExpression, sanitizeOpaqueReport, sanitizeOpaqueAncestor, sanitizeImageSummary, renderOpaqueConsole,
  opaqueGateRed, opaqueGateReason, rulesGateRed,
  evaluate
};

if (require.main === module) {
  main().catch(e => die(String(e.message || e)));
}
