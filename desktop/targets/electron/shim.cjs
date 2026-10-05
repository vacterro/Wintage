// Wintage shim for Electron applications.
//
// The application's archive is moved to `app.asar` INSIDE this folder and this
// file becomes the entry point. Nothing of the app is rewritten -- only relocated
// -- and the installer's --revert moves it straight back.
//
// (The tidier-looking idea, leaving app.asar where it is and relying on Electron
// preferring `resources/app`, does not work: Electron searches app.asar first and
// the theme silently never runs. tools/install-electron.js has the full note.)
//
// .cjs, not .js, and that is load-bearing. The package.json here is COPIED from the
// application's own so the app keeps its name and version -- and if the app declares
// "type": "module", a .js shim is parsed as ESM and dies on its first `require` with
// a main-process error dialog. Freebuff and CodeNomad both do exactly that. The
// extension pins CommonJS regardless of what the copied manifest says.

const path = require('path');
const fs = require('fs');

const CSS_FILE = path.join(__dirname, 'wintage.css');
const ASAR = path.join(__dirname, 'app.asar');

let TARGET_IDENTITY = '';
try {
  const { app } = require('electron');
  TARGET_IDENTITY = String(app.getName() || '').trim().toLowerCase();
} catch (e) { }
const IS_FREEBUFF = TARGET_IDENTITY === 'freebuff' || TARGET_IDENTITY.includes('freebuff');

let css = '';
try { css = fs.readFileSync(CSS_FILE, 'utf8'); } catch (e) {
  console.error('[wintage] stylesheet missing, loading the app unthemed:', e.message);
}

// The two colours the NATIVE titlebar overlay needs are read back out of the
// stylesheet's own `:root` block rather than shipped as a second file. The
// generated CSS always opens with that block (tools/build-desktop.js), so this has
// exactly one source of truth and a palette switch cannot leave the caption
// buttons painted in the previous theme.
const token = name => {
  const m = new RegExp('--' + name + ':\\s*(#[0-9A-Fa-f]{6})').exec(css);
  return m ? m[1] : null;
};
const T_SURFACE = token('surface');
const T_TEXT = token('textPrimary');
const T_BACKGROUND = token('background');

// Claude 1.24012.9 started assigning an explicit near-black `color` to most
// layout wrappers. An important colour inherited from html/body still loses to
// any declaration made directly on a child, so the palette kept painting the
// surfaces and bevels while the ordinary labels became black-on-brown.
//
// Keep this repair Claude-only. The shared stylesheet also serves FreeBuff,
// CodeNomad and browser pages, where flattening every explicit text colour would
// erase useful semantic states. `inherit` walks Claude's wrappers back to the
// palette while retaining the stronger existing rules for links, controls and
// disabled text. The text-fill reset covers WebKit utility classes; SVG and the
// usual icon-font carriers stay outside it so glyphs do not turn into letters.
const CLAUDE_VIEW = /(?:^https:\/\/claude\.ai\/epitaxy(?:[/?#]|$)|\/\.vite\/renderer\/main_window\/index\.html(?:[?#]|$))/i;
const CLAUDE_FOREGROUND_CSS = `
body :where(div, span, p, section, article, aside, main, nav, header, footer,
  ul, ol, li, dl, dt, dd, h1, h2, h3, h4, h5, h6, label, small, strong, em,
  b, time, code, pre, kbd, samp, input, textarea, select, option, button):not(svg):not(svg *):not([aria-hidden="true"]):not([class*="icon" i]):not([class*="glyph" i]):not([class*="symbol" i]) {
  color: inherit !important;
  -webkit-text-fill-color: currentColor !important;
}`;

// ─── SCROLLBAR GUTTERS ───────────────────────────────────────────────────────
// Styling ::-webkit-scrollbar turns Chromium's OVERLAY scrollbars into classic
// ones. Overlay scrollbars are invisible until you scroll, so app authors write
// `overflow: scroll` freely and it costs them nothing — until a theme makes those
// scrollbars classic, and every one of those containers grows a permanent gutter
// with a full-length thumb, on panels that have room to spare. Reported on
// Antigravity, visible on several panels at once.
//
// CSS cannot fix this: there is no selector for "this element's overflow is scroll",
// and blanket-overriding overflow would break containers that need `hidden`. So the
// one narrow change is made from script: computed `scroll` becomes `auto`, which is
// identical when the content actually overflows and hides the gutter when it does
// not. Nothing else is touched.
//
// The SECOND pass is newer and answers the follow-up report — scrollbars that are
// pure decoration, and one that clipped the edge of the Settings button. Those
// containers are on `auto` and DO overflow, by a handful of pixels, because this
// theme itself added a 2px bevel to everything inside them. A scrollbar whose whole
// range is four pixels is not a control, and it costs the panel a full gutter.
//
// `scrollbar-width: none`, not `overflow: hidden`, and the difference is the whole
// safety argument: hiding overflow makes content UNREACHABLE if the guess is wrong
// and the panel later fills up (a chat log is the obvious victim). Hiding only the
// scrollbar keeps the element scrollable by wheel and trackpad no matter what, so
// the worst case of a wrong guess is a missing bar, not lost content. It also
// reclaims the gutter, which `overflow: hidden` would not have done any better.
//
// The decision is re-made, not remembered: a container that grows real content
// gets its scrollbar back on the next pass. That is why NOISE is compared against
// live measurements every time instead of being latched on first sight.
//
// Cost discipline is copied from the userscript, which already paid for this lesson:
// getComputedStyle over a whole document is expensive, so this runs a few bounded
// passes after load and then only on newly added subtrees, never on a timer.
const SCROLL_FIX = `(() => {
  if (window.__wintageScrollFix) return "already running";
  window.__wintageScrollFix = true;

  const NOISE = 8;
  const BUDGET = 200;
  const MARK = "__wintageNoScrollbar";
  // PERF-001 (SRC-007:R012): BUDGET bounds STYLING work, but pre-fix the two
  // operations feeding it were unbounded — nextTreeNode pushed EVERY child of
  // a popped node onto the stack (250,000 direct children = 250,000 array
  // touches to style ONE node), and the observer callback synchronously walked
  // every delivered record AND every addedNodes entry (one childList with
  // 100,000 addedNodes = 100,000 reads before the first budget unit).
  // Both are now cursor-based, and each carries its own deterministic budget:
  //   TRAVERSE_BUDGET — child edges advanced per frame (traversal primitive);
  //   INTAKE_BUDGET   — record/addedNodes entries touched per callback;
  //   ROOT_QUEUE_BUDGET — tree-root queue operations per callback.
  // Wall-clock timing is intentionally NOT part of the acceptance contract:
  // regression tests assert on these counters.
  const TRAVERSE_BUDGET = 400;
  const INTAKE_BUDGET = 200;
  const ROOT_QUEUE_BUDGET = 200;

  const fixOne = el => {
    const cs = getComputedStyle(el);
    let changed = false;
    if (cs.overflowY === "scroll") { el.style.setProperty("overflow-y", "auto", "important"); changed = true; }
    if (cs.overflowX === "scroll") { el.style.setProperty("overflow-x", "auto", "important"); changed = true; }

    const scrollableY = cs.overflowY === "auto" || cs.overflowY === "scroll" || cs.overflowY === "overlay";
    const scrollableX = cs.overflowX === "auto" || cs.overflowX === "scroll" || cs.overflowX === "overlay";
    if (!scrollableY && !scrollableX) return changed;

    const rangeY = el.scrollHeight - el.clientHeight;
    const rangeX = el.scrollWidth - el.clientWidth;
    const noise = rangeY <= NOISE && rangeX <= NOISE;

    if (noise && !el[MARK]) {
      el[MARK] = true;
      el.style.setProperty("scrollbar-width", "none", "important");
      changed = true;
    } else if (!noise && el[MARK]) {
      el[MARK] = false;
      el.style.removeProperty("scrollbar-width");
      changed = true;
    }
    return changed;
  };

  const dirty = new Set();
  const trees = [];
  const treeRoots = new Set();
  const activeTrees = [];
  let frameQueued = false;
  let settleTimer = null;
  let settlePasses = 0;
  let settleNeeded = false;
  // PERF-001: deterministic work counters, for tests and diagnosis.
  const counters = {
    edges: 0,           // traversal child-edges advanced (nextTreeNode work)
    styled: 0,          // elements styled (fixOne calls)
    recordsTouched: 0,  // mutation records consumed by intake
    addedTouched: 0,    // addedNodes entries read by intake
    queueOps: 0,        // queueTree/queueDirty bookkeeping ops
    overflowContinues: 0, // whole-document continuation tokens issued
    maxRetained: 0      // high-water mark of retained traversal/input state
  };
  const noteRetained = () => {
    let n = pendingIntakeBatches() + dirty.size + (trees.length - treeHead);
    for (let i = 0; i < activeTrees.length; i++) {
      const f = activeTrees[i];
      n += f.stack ? f.stack.length : 1;
    }
    if (n > counters.maxRetained) counters.maxRetained = n;
  };

  // PERF-002 (SRC-004): the queue is bounded and ancestor-collapsed. Two
  // measured shapes broke the nominal BUDGET=200:
  //   20,000 flat added roots  -> 20,001 extra getComputedStyle calls over 101
  //                               animation frames (intake was unbounded);
  //    1,000 NESTED added roots -> 501,500 getComputedStyle calls over 2,508
  //                               frames, because a queued parent and its
  //                               descendants each walked the same subtree.
  // Identity dedupe cannot see that: parent and child are different objects.
  const MAX_TREE_ROOTS = 64;
  const MAX_DIRTY = 2000;
  let treeOverflow = false;
  // PERF-002: head index instead of Array.prototype.shift, which is O(n) per
  // removal and therefore O(n^2) over a drained queue. Everything below treeHead
  // is already consumed, so pending work is trees.length - treeHead.
  let treeHead = 0;
  const pendingIntakeBatches = () => pendingIntake.length;
  const hasWork = () => dirty.size || (trees.length - treeHead) > 0 || activeTrees.length || treeOverflow || hasIntakeWork();
  const queueFrame = () => {
    if (frameQueued) return;
    frameQueued = true;
    requestAnimationFrame(flush);
  };
const queueDirty = el => {
     if (!el || el.nodeType !== 1) return;
     // PERF-002: the dirty set is bounded by the same rule as the root queue. An
     // attribute storm delivers one record per element, and one Set entry per record is exactly the
     // per-node retention this finding is about. Past the cap the whole document
     // is re-walked once instead -- a superset of every entry that would have been
     // dropped.
     if (dirty.size >= MAX_DIRTY) {
       if (!treeOverflow) counters.overflowContinues++;
       treeOverflow = true;
       queueFrame();
       return;
     }
     counters.queueOps++;
     dirty.add(el);
     queueFrame();
   };
  const queueTree = root => {
    if (!root || root.nodeType !== 1 || treeRoots.has(root)) return;
    // Ancestor collapse: an already-queued ancestor will walk this subtree, so
    // queueing the descendant only duplicates the walk. Cheap because the check
    // is O(depth) against a Set, never O(queue).
    for (let p = root.parentNode; p; p = p.parentNode) {
      if (treeRoots.has(p)) return;
    }
    // The reverse direction: this root subsumes queued descendants. Drop them
    // rather than walking their subtrees twice. Only the UNCONSUMED span is
    // scanned, and entries are nulled in place so treeHead stays valid.
    if (treeRoots.size && root.contains) {
      for (let i = treeHead; i < trees.length; i++) {
        const queued = trees[i];
        if (!queued || queued === root || !root.contains(queued)) continue;
        trees[i] = null;
        treeRoots.delete(queued);
      }
    }
if (treeRoots.size >= MAX_TREE_ROOTS) {
       // Overflow is ONE bounded continuation token, not one entry per node: the
       // next frame re-walks from documentElement, which is a superset of every
       // root we are dropping here. Nothing is lost, and memory stops scaling
       // with the size of the insertion burst.
       if (!treeOverflow) counters.overflowContinues++;
       treeOverflow = true;
       queueFrame();
       return;
     }
    counters.queueOps++;
    treeRoots.add(root);
    trees.push(root);
    queueFrame();
  };
  const takeRoot = () => {
    while (treeHead < trees.length) {
      const root = trees[treeHead];
      trees[treeHead++] = null;
      if (treeHead > 32 && treeHead * 2 >= trees.length) { trees.splice(0, treeHead); treeHead = 0; }
      if (root) return root;
    }
    if (trees.length) { trees.length = 0; treeHead = 0; }
    if (treeOverflow) {
      treeOverflow = false;
      return document.documentElement;
    }
    return null;
  };
  // PERF-001 (SRC-007:R012): persistent incremental traversal. The old
  // nextTreeNode pushed EVERY child of a popped node onto the stack in one
  // call, so one node with 250,000 direct children touched all 250,000 child
  // entries before a single unit of the 200-node styling budget was consumed.
  //
  // The replacement keeps an explicit { node, childIndex } frame per tree:
  //   - one call advances AT MOST one child edge (counters.edges); a wide
  //     sibling list is consumed through the persistent childIndex, so the
  //     list is never re-enumerated from zero;
  //   - the root itself is visited FIRST (it still receives SCROLL_FIX);
  //   - the pre-order order matches the reference traversal exactly, so
  //     eventual coverage equals a full unbounded walk.
  // The returned element is styled this frame; its subtree is descended into
  // on later calls. Frame childIndex semantics: -1 = the frame's own node has
  // NOT been styled yet (root frames only); >= 0 = node already served, and
  // children before that index are already consumed.
  let edgeBudget = 0; // per-flush traversal allowance, reset in flush()
  // PERF-001 (SRC-007:R012): the ONLY traversal implementation is the bounded
  // persistent cursor below. The historical bulk-children variant (one node
  // with 250,000 direct children enumerating all of them in one budget unit)
  // is gone from the shipped payload entirely: no runtime flag, no page-context
  // hook, no fallback path. Red controls reproduce it from temporary mutated
  // source strings in tools/test-perf-lanes.js, never from shipped branches.
  const nextTreeNode = () => {
    for (;;) {
      let state = activeTrees[activeTrees.length - 1];
      if (!state) {
        const root = takeRoot();
        if (!root) return null;
        treeRoots.delete(root);
        state = { node: root, childIndex: -1 };
        activeTrees.push(state);
      }
      if (state.childIndex === -1) {
        // First serve of this tree: style the root, then descend next call.
        state.childIndex = 0;
        return state.node;
      }
      const kids = state.node.children;
      const kidCount = kids ? kids.length : 0;
      if (state.childIndex < kidCount) {
        // Bounded edge advance: exactly one child edge per call. Reaching the
        // budget parks the cursor mid-list and resumes here next frame.
        if (edgeBudget <= 0) return null;
        edgeBudget--;
        counters.edges++;
        const child = kids[state.childIndex++];
        // childIndex 0 marks the child ALREADY SERVED by this very yield, so
        // its frame never styles it a second time.
        activeTrees.push({ node: child, childIndex: 0 });
        if (child && child.nodeType === 1) return child;
        continue; // non-element child: its empty frame pops on the next pass
      }
      activeTrees.pop(); // subtree exhausted; unwinding costs no edge units
    }
  };
  const scheduleSettle = () => {
    if (settleTimer || settlePasses >= 2 || !settleNeeded || hasWork()) return;
    settleTimer = setTimeout(() => {
      settleTimer = null;
      if (hasWork() || !settleNeeded || settlePasses >= 2) return;
      settleNeeded = false;
      settlePasses++;
      queueTree(document.documentElement);
    }, 600);
  };
  function flush() {
    frameQueued = false;
    edgeBudget = TRAVERSE_BUDGET;
    let budget = BUDGET;
    while (budget-- > 0) {
      let el;
      if (dirty.size) {
        el = dirty.values().next().value;
        dirty.delete(el);
      } else {
        // R012: while mutation intake is still pending, do NOT start new tree
        // walks. Overflow tokens set during intake would otherwise interleave
        // with the walk and force one full document re-walk PER intake frame.
        // Draining intake first collapses them into ONE token -> ONE walk,
        // which is still a superset: it starts after every dropped entry
        // already exists and visits every connected child of the root.
        if (hasIntakeWork()) break;
        el = nextTreeNode();
        if (!el) break;
      }
      counters.styled++;
      if (fixOne(el)) settleNeeded = true;
    }
    noteRetained();
    if (hasWork()) queueFrame();
    else scheduleSettle();
  }

  queueTree(document.documentElement);
  // PERF-001 (SRC-007:R012): BOUNDED MUTATION INTAKE. The old callback
  // synchronously looped every delivered record and every addedNodes entry of
  // every childList record — one 100,000-record delivery or one childList with
  // 100,000 addedNodes performed all of that work in a single observer
  // callback, before any of the queue caps (which only bound RETENTION, not
  // INTAKE) ever applied.
  //
  // Intake is now incremental scheduler state:
  //   - the callback itself does only O(1) bookkeeping and schedules work;
  //   - a persistent pending-intake list carries { records, rIndex, aIndex }
  //     frames, so a partially consumed childList record's addedNodes cursor
  //     survives across callbacks;
  //   - each drain consumes at most INTAKE_BUDGET addedNodes entries plus one
  //     record at a time, and at most ROOT_QUEUE_BUDGET queue operations;
  //   - attribute records always repair their target first (bounded O(1) per
  //     record) and are consumed under the same record budget.
  //
  // Overflow (A3) stays a SUPERSET: when pending intake exceeds the retention
  // cap, the detailed tail records are dropped WITHOUT inspecting them and
  // exactly ONE whole-document continuation is scheduled, which re-walks from
  // documentElement and therefore covers every connected element the dropped
  // tail could have contained. No per-node tokens.
  const pendingIntake = [];       // frames: { records, rIndex, aIndex, targetDone }
  let intakeScheduled = false;
  const MAX_PENDING_BATCHES = 8;  // bounded retained delivery state
  const hasIntakeWork = () => {
    for (let i = 0; i < pendingIntake.length; i++) {
      const f = pendingIntake[i];
      if (f.rIndex < f.records.length) return true;
    }
    return false;
  };
  const drainIntake = () => {
    intakeScheduled = false;
    let recBudget = INTAKE_BUDGET;
    let queueBudget = ROOT_QUEUE_BUDGET;
    for (let bi = 0; bi < pendingIntake.length && recBudget > 0 && queueBudget > 0;) {
      const f = pendingIntake[bi];
      if (f.rIndex >= f.records.length) { pendingIntake.splice(bi, 1); continue; }
      const r = f.records[f.rIndex];
      if (r.type === "attributes") {
        // Target repair is guaranteed: queueDirty on the record target, O(1).
        counters.recordsTouched++;
        recBudget--; queueBudget--;
        f.rIndex++;
        queueDirty(r.target);
        continue;
      }
      // childList: the record target is repairable; added nodes are consumed
      // incrementally against aIndex so a stop halfway through a record's
      // addedNodes preserves the exact cursor and resumes later. aIndex is
      // scoped to the CURRENT record: it resets when the record completes, so
      // every record's target repair and addedNodes are actually consumed.
      if (!f.targetDone) {
        counters.recordsTouched++;
        recBudget--; queueBudget--;
        queueDirty(r.target);
        f.targetDone = true;
      }
      const added = r.addedNodes;
      const addedLen = added ? added.length : 0;
      while (f.aIndex < addedLen) {
        if (queueBudget <= 0) break; // resume later, exact same cursor
        queueBudget--;
        counters.addedTouched++;
        const node = added[f.aIndex++];
        queueTree(node);
      }
      if (f.aIndex < addedLen) break; // mid-addedNodes: frame stays intact
      f.rIndex++; f.aIndex = 0; f.targetDone = false; // advance to next record
    }
    if (hasIntakeWork()) {
      // Continuation is scheduled, never synchronous: the callback/drain does
      // only bounded work and yields.
      if (!intakeScheduled) { intakeScheduled = true; requestAnimationFrame(drainIntake); }
    }
    if (hasWork()) queueFrame(); else scheduleSettle();
  };
   // PERF-001 (SRC-007:R012): the callback does only O(1) bookkeeping — enqueue
  // the batch and schedule the drain. The historical synchronous intake that
  // looped every record and every addedNodes entry inside the callback is gone
  // from the shipped payload: no flag, no page-context hook can re-enable it.
  const newMutationObserver = () => new MutationObserver(records => {
    settleNeeded = true;
     // O(1) per callback: enqueue the batch and schedule the drain. A record
     // batch is never synchronously enumerated here, no matter how large.
     if (pendingIntake.length >= MAX_PENDING_BATCHES) {
       // A3: overflow — stop retaining detailed tail state, do NOT inspect the
       // discarded tail (we do not read its records to discover what is in it),
       // and schedule exactly ONE whole-document continuation. That re-walk is
       // a superset of every connected element in the dropped delivery.
       if (!treeOverflow) counters.overflowContinues++;
       treeOverflow = true;
       queueFrame();
       return;
     }
     pendingIntake.push({ records: records, rIndex: 0, aIndex: 0, targetDone: false });
     if (!intakeScheduled) { intakeScheduled = true; requestAnimationFrame(drainIntake); }
   });
  newMutationObserver().observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ["style", "class"] });

  // Deterministic primitive counters are exposed for tests and diagnosis (A4):
  // acceptance asserts on these, never on wall-clock timing.
  try { window.__wintageScrollCounters = counters; } catch (e) { }

  return "scroll fix installed";
})()`;

// ─── THE REPAINTER, SHIPPED WHOLE ────────────────────────────────────────────
// A stylesheet cannot win against an application that computes its colours in JS,
// and the attempt to paper over that with CSS -- a blanket that wiped backgrounds
// to transparent and re-solidified panels off a list of library NAMES -- lost the
// race against the app's own state writes and left panels unreadable. Both halves
// of that idea are gone now.
//
// The userscript already solves this properly: it measures computed styles and
// writes back only what is actually wrong. So the repainter is NOT reimplemented
// here. tools/build-desktop.js extracts it from wintage.user.js between its
// REPAINTER markers and drops it in below, exactly the way the stylesheet is
// extracted, so a fix made once is a fix made everywhere.
//
// It arrives as a JSON string literal rather than as text pasted inside a template
// literal, and that is not a style preference. The repainter is full of regex
// literals -- /rgba?\(\s*(\d+)/ and its relatives -- and inside a template literal
// every one of those backslashes is an escape: \s collapses to s, \d to d, \( to
// (. The result still parses and silently matches the wrong thing. A single
// backtick in any of its comments ends the string outright, which is precisely how
// this shim shipped unloadable. JSON.stringify is the only encoding that carries
// all of it through verbatim.
const REPAINTER_BODY = /* __REPAINTER__ */ "";

// The one place insertCSS cannot reach. It produces a DOCUMENT stylesheet, and a
// document stylesheet does not cross a shadow boundary, so every rule written for
// a shadow tree has to be carried in and injected root by root -- which is what
// the repainter's pierceShadow does with this.
const SHADOW_CSS = /* __SHADOW_CSS__ */ "";

// Everything the extracted body reads from the userscript's outer scope has to be
// handed to it here. That list is not maintained by hand and hope: build-desktop.js
// fails the build if the userscript ever starts reading something this prelude does
// not define, because the failure mode otherwise is a ReferenceError thrown inside
// executeJavaScript, which surfaces as "the theme just does not work" and nothing
// else.
const REPAINTER_FIX = `(() => {
  if (window.__wintageRepainter) return "already running";
  window.__wintageRepainter = true;

  const W95_VERSION = '${VERSION}';

  // This pack's palette, whole. Not trimmed to what the repainter happens to read
  // today: it builds PALETTE_RGB from Object.keys(T) to recognise its own colours,
  // so a missing token would make it treat one of our own greys as the site's.
  const T = {
    background: '${T.background}',
    backgroundSoft: '${T.backgroundSoft}',
    surface: '${T.surface}',
    surfaceRaised: '${T.surfaceRaised}',
    surfaceAlt: '${T.surfaceAlt}',
    borderDark: '${T.borderDark}',
    borderHighlight: '${T.borderHighlight}',
    bevelLight: '${T.bevelLight}',
    borderMuted: '${T.borderMuted}',
    link: '${T.link}',
    textPrimary: '${T.textPrimary}',
    textSecondary: '${T.textSecondary}',
    textMuted: '${T.textMuted}',
    accentTeal: '${T.accentTeal}',
    accentTealDeep: '${T.accentTealDeep}',
    success: '${T.success}',
    warning: '${T.warning}',
    danger: '${T.danger}',
    dangerText: '${T.dangerText}',
    selection: '${T.selection}',
    compareBack: '${T.compareBack}'
  };

  let IS_TOP = true;
  try { IS_TOP = window.top === window.self; } catch (e) { IS_TOP = false; }

  // The userscript drops to CSS-only on a short list of hosts whose DOM churns
  // hard enough that the repainter costs more than it wins. A desktop shell is one
  // known application rather than the open web, and shipping the repainter here is
  // the entire point of this block, so it stays on.
  const CSS_ONLY_MODE = false;
  // T-902: mirrored from the userscript. The repainter body is a slice of the
  // userscript that reads both of these names -- IS_REDDIT on the CSS-only host
  // gate and IS_CHATGPT as the lean-path label in startSweeping -- so the prelude
  // has to provide them or the extracted body throws a ReferenceError inside
  // executeJavaScript, which the user experiences as "the theme does nothing".
  // A desktop shell is one known application, never a churn-heavy web SPA, so
  // both stay false: same branch as every non-Reddit, non-ChatGPT web host.
  const IS_REDDIT = false;
  const IS_CHATGPT = false;

  // Polarity. Every luminance threshold downstream was written against a dark
  // palette; elev() normalises the incoming value so the same numbers keep their
  // meaning on a light one. Identical to the userscript's, deliberately.
  function lum({ r, g, b }) {
    const lin = v => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4); };
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
  }
  function hexLum(hex) {
    return lum({ r: parseInt(hex.slice(1, 3), 16), g: parseInt(hex.slice(3, 5), 16), b: parseInt(hex.slice(5, 7), 16) });
  }
  function contrast(a, b) { return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05); }
  const BG_LUM = hexLum(T.background);
  const BG_SOFT_LUM = hexLum(T.backgroundSoft);
  const DARK = BG_LUM < 0.18;
  const elev = L => (DARK ? L : 1 - L);

  const SHADOW_CSS = ` + JSON.stringify(SHADOW_CSS) + `;

  function injectStyle(root, id, content) {
    if (root.querySelector && root.querySelector('style[data-w95="' + id + '"]')) return;
    const s = document.createElement('style');
    s.setAttribute('data-w95', id);
    s.setAttribute('data-w95-ver', W95_VERSION);
    s.textContent = content;
    const target = root.head || root.documentElement || root;
    try { target.insertBefore(s, target.firstChild); } catch (e) {
      try { (document.head || document.documentElement).appendChild(s); } catch (e2) { }
    }
  }

  // In the browser the theme is a <style> node and injectLate's whole job is to
  // move it to the end of <head> so late application CSS cannot outrank it by
  // position. Here the stylesheet arrives through insertCSS, which is not a DOM
  // node at all and already applies at author origin after the document's own
  // sheets. There is nothing to move, so this is a deliberate no-op rather than a
  // reimplementation of something that does not apply.
  function injectLate() { }

  // CORE-015: the userscript counts every deliberately-suppressed throw in the
  // hover surgery and the shadow-root pierce instead of hiding it, and exposes
  // one snapshot through window.__wintageDiag(). The repainter body calls
  // noteSuppressed() in those catch blocks, so the prelude MUST provide it or
  // the extracted body would ReferenceError inside executeJavaScript -- which
  // the user experiences as "the theme does nothing", with the error in a place
  // nobody looks. The build's free-identifier gate is what caught exactly that.
  //
  // Same shape and same counter names as the userscript, deliberately: a bug
  // report from a desktop app and one from the browser then read identically.
  const DIAG = { hoverWalkThrows: 0, hoverAppendThrows: 0, sheetGenThrows: 0, shadowPierceThrows: 0, repaintSkippedHighChurn: 0, shadowCssInjected: 0, firstError: null };
  // T-902: the userscript counts every document-wide decision it suppresses on a
  // CSS-only host; the body calls this from those branches, so it must exist here
  // for the same reason noteSuppressed does.
  function noteRepaintSkipped() { DIAG.repaintSkippedHighChurn++; }
  function noteSuppressed(kind, e) {
    DIAG[kind]++;
    if (!DIAG.firstError) DIAG.firstError = { kind: kind, message: (e && e.message) ? e.message : String(e) };
  }
  try {
    window.__wintageDiag = function () {
      return {
        version: W95_VERSION,
        // The pack identity the shim was generated for. Read off the palette
        // rather than interpolated from a slug placeholder: the build's resolver
        // only substitutes the palette-token, FONT, VERSION and bevel
        // placeholders, so a slug placeholder would survive into the shipped
        // file and trip its own unresolved-placeholder gate.
        background: T.background,
        cssOnlyMode: CSS_ONLY_MODE,
        // T-902: same three runtime fields the userscript reports, so a desktop
        // bug report reads like a browser one. A desktop shell is never Reddit,
        // and shadowCssInjected counts the creation-time sheet it does inject.
        redditCssOnly: IS_REDDIT && CSS_ONLY_MODE,
        repaintSkippedHighChurn: DIAG.repaintSkippedHighChurn,
        shadowCssInjected: DIAG.shadowCssInjected,
        suppressed: {
          hoverWalkThrows: DIAG.hoverWalkThrows,
          hoverAppendThrows: DIAG.hoverAppendThrows,
          sheetGenThrows: DIAG.sheetGenThrows,
          shadowPierceThrows: DIAG.shadowPierceThrows
        },
        firstError: DIAG.firstError
      };
    };
  } catch (e) { }

` + REPAINTER_BODY + `

  return "repainter active";
})()`;

// ─── SCROLLING UP MUST MEAN SCROLLING UP ─────────────────────────────────────
// Reported as: read something in the middle of a long conversation, and the view
// snaps back down, repeatedly, until you drag the scrollbar by hand.
//
// Recorded on the live application before a line of this was written, with a
// stack captured on every programmatic scroll. The theme is not the mover, and
// that was worth proving rather than assuming -- the scroller carried zero inline
// writes from this shim, no scrollbar-width, no overflow-y, no bevel. What the
// recorder caught is the application pinning itself to the bottom:
//
//   t+0    scrollTo   from 4400 -> {top: 5896, behavior: "smooth"}   scrollToBottom
//   t+75   scrollTop  from 2600 -> 5896                              ResizeObserver
//
// The reader was at 2600, some 3300px from the bottom. Every chunk that streams in
// resizes the content, the resize observer re-pins, and the reader loses their
// place. A theme has no business rewriting an application's behaviour, so the rule
// here is as narrow as the evidence: keep the intent the USER expressed.
//
// The discriminator is transient activation, and it is exact. Clicking a
// "jump to latest" button leaves navigator.userActivation.isActive true; a
// ResizeObserver callback firing because a token arrived does not. So a
// programmatic scroll TO THE BOTTOM, aimed at a scroller the reader has
// deliberately left, with no user gesture behind it, is dropped. Everything else
// -- their own wheel, their own drag, their own click on the button, the app's
// pinning while they ARE at the bottom -- is untouched, and the moment they come
// back to the bottom the app is free to pin again.
const SCROLL_INTENT_FIX = `(() => {
  if (window.__wintageScrollIntent) return "already running";
  window.__wintageScrollIntent = true;

  // How close to the bottom still counts as "at the bottom". A couple of lines,
  // not a screenful: this decides when the app is allowed to pin again.
  const AT_BOTTOM = 64;
  // How far away counts as "deliberately reading something else". Well past any
  // rounding, sub-pixel or bevel noise.
  const AWAY = 200;

  const AWAY_FLAG = "__wintageReaderAway";
  const proto = Element.prototype;
  const desc = Object.getOwnPropertyDescriptor(proto, "scrollTop");
  const rawScrollTo = proto.scrollTo;

  const range = el => el.scrollHeight - el.clientHeight;
  const distance = el => range(el) - desc.get.call(el);
  // Called from inside an observer callback? Then this is the application
  // reacting, not a person acting. Reading a stack is not free, which is why it
  // happens only after every cheap test has already said "bottom-aimed scroll on
  // a scroller the reader left" -- a handful of times per session, not per frame.
  const reactive = () => {
    let st = "";
    try { st = new Error().stack || ""; } catch (e) { return false; }
    return /ResizeObserver|MutationObserver|IntersectionObserver/.test(st);
  };

  const gesture = () => {
    try { return !!(navigator.userActivation && navigator.userActivation.isActive); }
    catch (e) { return true; }        // cannot tell -> never block
  };

  // Only ever say yes when everything is known. Anything unmeasurable falls
  // through to "allow", because a theme dropping a scroll it did not understand
  // is a far worse failure than a scroll it should have dropped.
  const shouldDrop = (el, targetTop) => {
    if (!el || !el[AWAY_FLAG]) return false;
    const r = range(el);
    if (r < 400) return false;                     // nothing worth losing your place in
    if (r - targetTop > AT_BOTTOM) return false;   // not aimed at the bottom
    // WHO IS CALLING beats WHEN THEY LAST CLICKED.
    // The first version trusted transient activation alone, and it leaked: the
    // flag stays true for about five seconds after ANY click, so pressing send and
    // then scrolling up left the auto-scroll allowed for exactly the window in
    // which it happens. The recorder that diagnosed this printed the real
    // discriminator verbatim -- the re-pin arrives from
    // "at Object.current <- ResizeObserver.<anonymous>". An observer callback is
    // the application reacting to its own content growing; it is never the reader
    // asking for anything, whatever they clicked five seconds ago.
    if (reactive()) return true;
    if (gesture()) return false;                   // the reader asked for it
    return true;
  };

  Object.defineProperty(proto, "scrollTop", {
    configurable: true,
    get() { return desc.get.call(this); },
    set(v) {
      if (shouldDrop(this, Number(v))) return;
      return desc.set.call(this, v);
    }
  });

  proto.scrollTo = function (...args) {
    const opt = args[0];
    const top = opt && typeof opt === "object" ? opt.top : args[1];
    if (typeof top === "number" && shouldDrop(this, top)) return;
    return rawScrollTo.apply(this, args);
  };

  // The reader's own scrolling is what sets and clears the flag. A scroll event
  // fires for programmatic scrolls too, which is why the flag is derived from
  // POSITION rather than from "an event happened": at the bottom, the app may
  // pin; away from it, it may not. That holds no matter who moved it last.
  addEventListener("scroll", ev => {
    const el = ev.target;
    if (!el || el.nodeType !== 1 || range(el) < 400) return;
    const d = distance(el);
    if (d <= AT_BOTTOM) el[AWAY_FLAG] = false;
    else if (d >= AWAY) el[AWAY_FLAG] = true;
  }, { capture: true, passive: true });

  return "scroll intent fix installed";
})()`;

// ─── THEME SWITCH RE-ASSERT ─────────────────────────────────────────────────
// FreeBuff 0.0.55 ships a real theme system (Pierre dark/light, stored under
// localStorage "freebuff:theme", resolved against prefers-color-scheme in
// "system" mode, applied through an inline theme stylesheet). Switching themes
// repaints the whole window with the new theme's computed colours WITHOUT the
// class/style churn the repainter already watches, so without this watcher a
// switch leaves the app half-Wintage, half-Pierre until the next real DOM
// churn. Detection is cheap: a matchMedia listener, a 2s localStorage poll, and
// a narrow documentElement attribute observer. On a switch the palette is
// re-asserted by appending a transient <style> node, which the repainter's own
// observer reads as a stylesheet change and answers with a full force sweep
// over the fresh computed styles.
const THEME_REASSERT_FIX = `(() => {
  if (window.__wintageThemeReassert) return "already running";
  window.__wintageThemeReassert = true;

  const poke = () => {
    if (!document.head) return;
    const s = document.createElement("style");
    s.setAttribute("data-w95-reassert", "1");
    document.head.appendChild(s);
    // Remove next tick so a later theme switch can poke again; the repainter
    // already saw the stylesheet-bearing childList mutation.
    setTimeout(() => { try { s.remove(); } catch (e) { } }, 0);
  };

  try {
    matchMedia("(prefers-color-scheme: dark)").addEventListener("change", poke);
  } catch (e) { }

  let lastTheme = "";
  try { lastTheme = localStorage.getItem("freebuff:theme") || ""; } catch (e) { }
  setInterval(() => {
    let t = "";
    try { t = localStorage.getItem("freebuff:theme") || ""; } catch (e) { }
    if (t !== lastTheme) { lastTheme = t; poke(); }
  }, 2000);

  try {
    new MutationObserver(records => {
      for (const r of records) {
        if (r.type === "attributes" && /theme/i.test(r.attributeName || "")) { poke(); break; }
      }
    }).observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });
  } catch (e) { }

  return "theme re-assert watcher installed";
})()`;

// ─── FREEBUFF POPOVER LAYOUT THRASH FIX ─────────────────────────────────────
// Freebuff's Eo layout hook creates an infinite ResizeObserver ping-pong loop
// on bottom-anchored popovers (.agent-menu) whose unconstrained height exceeds
// the available viewport space. In its ResizeObserver callback it clears
// maxHeight to "" to measure unconstrained height, then sets maxHeight = f px,
// which resizes the element and schedules another ResizeObserver notification
// every single animation frame, causing 60-144fps top-edge jitter.
//
// Observing the constrained container itself with ResizeObserver is what drives
// the loop; window resize and scroll listeners already reposition and reclamp
// the menu properly. Wrapping ResizeObserver.prototype.observe to skip observing
// .agent-menu breaks the feedback loop completely without affecting other UI.
// Clamping .agent-menu and its scroll container via !important CSS ensures
// height stability regardless of inline clears.
const FREEBUFF_POPOVER_FIX = `(() => {
  if (window.__wintageFreebuffPopoverFix) return "already running";
  window.__wintageFreebuffPopoverFix = true;

  try {
    const style = document.createElement("style");
    style.id = "wintage-freebuff-agent-menu";
    style.textContent = [
      ".agent-menu { max-height: calc(100vh - 76px) !important; }",
      ".agent-menu-scroll { max-height: calc(100vh - 84px) !important; overflow-y: auto !important; }"
    ].join("\\n");
    (document.head || document.documentElement).appendChild(style);
  } catch (e) { }

  try {
    const rawObserve = ResizeObserver.prototype.observe;
    ResizeObserver.prototype.observe = function (target, options) {
      if (target && target.classList && (
        target.classList.contains("agent-menu") ||
        (target.matches && target.matches(".agent-menu, [class*='agent-menu']"))
      )) {
        return;
      }
      return rawObserve.call(this, target, options);
    };
  } catch (e) { }

  return "freebuff popover fix installed";
})()`;


// ─── A BAR THAT REPORTS A VALUE: TRIED, MEASURED, WITHDRAWN ──────────────────
// The problem is real and stays on the board. A usage or quota bar carries its
// number in the PROPORTION between fill and track, surface flattening paints both
// the same colour, and the bar survives as a rectangle that reports nothing.
//
// Two detections were tried, and both were withdrawn after counting what they
// actually hit in a live Claude window:
//
//   by shape   -- a child starting at the track's leading edge, as tall as the
//                 track and shorter than it ...................... 234 elements
//   by inline  -- a child whose width is computed inline as a percentage,
//                 or by a scaleX transform ....................... 111 elements
//
// Neither is a gauge detector. The first describes every button, tab and toolbar
// row ever written; the second describes ordinary layout, because a width of 60%
// in a style attribute is how half the web sizes a column. Extra guards -- carries
// no text, holds at most three children -- moved the counts and not the verdict.
//
// What those numbers settle is which way to fail. A gauge that is drawn but hard
// to read is a cosmetic complaint; a hundred controls repainted as solid golden
// blocks is an application nobody can work in, and that is what shipped, briefly.
// So nothing is painted here until a real gauge is read over CDP and a signal is
// found that a control cannot also satisfy. Guessing it from a screenshot has cost
// two rounds already.

// ─── NATIVE CAPTION BUTTONS SITTING ON TOP OF THE APP'S OWN CONTROLS ─────────
// Antigravity is a frameless window with Electron's titleBarOverlay: minimise,
// maximise and close are drawn by Chromium ON TOP of the page, in a strip the
// renderer does not own. The app reserves room for that strip in the layouts it
// knows about -- and not in the ones it does not, which is how the Settings
// section's own close button ended up underneath the caption buttons, visible but
// unclickable. No stylesheet can fix this, because the overlay is not in the DOM.
//
// Chromium does expose the geometry, though: navigator.windowControlsOverlay
// gives the rect the PAGE still owns, so everything outside it in the title strip
// is the overlay. Anything interactive that lands there is moved out from under it
// with a transform -- transform and not margin, because a control positioned
// absolutely (which these usually are) ignores margins entirely.
//
// Deliberately narrow: only small controls, only inside the title strip, and the
// shift is recomputed from scratch on every pass (the transform is cleared before
// measuring) so a resize cannot accumulate offsets. Getting it wrong nudges one
// button a few pixels; not doing it leaves that button unreachable.
const WCO_FIX = `(() => {
  if (window.__wintageWcoFix) return "already running";
  const wco = navigator.windowControlsOverlay;
  if (!wco) return "no window-controls overlay in this window";
  window.__wintageWcoFix = true;

  const SEL = "button, a, summary, input, select, [role=button], [role=tab], [class*=button i], [class*=btn i]";
  const touched = new Set();

  const apply = () => {
    for (const el of touched) el.style.removeProperty("transform");
    touched.clear();
    if (!wco.visible) return;

    const bar = wco.getTitlebarAreaRect();
    if (!bar || !bar.height) return;
    // Whatever the page does NOT own inside the title strip is the overlay. It sits
    // on the right on Windows and Linux, on the left on macOS; both are handled by
    // measuring rather than assuming.
    const rightStrip = bar.x + bar.width < window.innerWidth - 1;
    const from = rightStrip ? bar.x + bar.width : 0;
    const to = rightStrip ? window.innerWidth : bar.x;
    if (to - from < 1) return;

    for (const el of document.querySelectorAll(SEL)) {
      const r = el.getBoundingClientRect();
      if (!r.width || !r.height) continue;
      // In the title strip, and small enough to be a control rather than a panel
      // that merely starts up there.
      if (r.top >= bar.y + bar.height || r.bottom <= bar.y) continue;
      if (r.width > 200 || r.height > 60) continue;
      if (r.right <= from || r.left >= to) continue;
      // Signed by construction: positive when the control pokes into a strip on
      // the right, negative when it pokes into one on the left. Undoing it is the
      // same expression either way.
      const shift = rightStrip ? r.right - from : r.left - to;
      if (Math.abs(shift) < 1) continue;
      el.style.setProperty("transform", "translateX(" + (-shift) + "px)", "important");
      touched.add(el);
    }
  };

  apply();
  let passes = 0;
  const settle = () => { if (++passes < 4) { apply(); setTimeout(settle, 700); } };
  setTimeout(settle, 700);

  // PERF-006: ONE geometry scan per rendered frame. requestAnimationFrame does
  // NOT coalesce separately queued callbacks, so the old
  // \`() => requestAnimationFrame(apply)\` handlers queued one complete
  // querySelectorAll + getBoundingClientRect pass per EVENT. Measured on the
  // pre-fix payload: 100 resize events before a frame -> 100 queued callbacks
  // and 100,000 extra rect reads, 99 of which measured geometry that was
  // already superseded. The latch is cleared immediately BEFORE apply() runs,
  // so an event arriving during the scan still schedules the next frame -- the
  // latest geometry always wins, which is why this is a latch and not a
  // debounce (a debounce would make the controls visibly lag the window).
  let frameQueued = false;
  const queueApply = () => {
    if (frameQueued) return;
    frameQueued = true;
    requestAnimationFrame(() => { frameQueued = false; apply(); });
  };
  window.addEventListener("resize", queueApply);
  try { wco.addEventListener("geometrychange", queueApply); } catch (e) { }

  return "window-controls overlay fix installed";
})()`;

// ─── app.getAppPath() MUST STILL POINT AT THE ARCHIVE ───────────────────────
// This is the one thing the relocation actually breaks, and it breaks loudly in a
// misleading way. Electron sets getAppPath() to the directory it loaded the app
// from -- now `resources/app`, the shim's own folder -- while every module INSIDE
// the archive was written expecting it to be the archive itself. Claude's main
// does exactly that:
//
//   mainWindow.loadFile(path.join(app.getAppPath(), '.vite/renderer/main_window/index.html'))
//
// With the shim in place that resolves to resources/app/.vite/... which does not
// exist, the local load fails, and the app falls back to opening claude.ai --
// so the desktop app silently becomes the web app. Reported as "after patching it
// opens the web version"; nothing about the theme was wrong.
//
// Pointing getAppPath() back at the archive restores exactly what an unpatched
// launch would report. The real value is kept for anything that wants the shim's
// own directory.
// ─── OPT-IN DEBUG PORT ──────────────────────────────────────────────────────
// Themed apps are the hardest thing here to diagnose: the only feedback is a
// screenshot and a restart, which turns every hypothesis into a round trip paid
// for by the user. A debug port replaces that with reading the live document --
// which is how the black-text bug was finally pinned, by asking Blink directly
// which rule won on <body> instead of guessing for eight rounds.
//
// OFF unless a file called `wintage-debug.port` sits next to this shim, holding
// the port number. Deliberate, greppable, and revoked by deleting the file. Never
// on for an ordinary install: a debugging port left open on someone's machine is
// not a detail to leave to memory. Loopback only.
try {
  const portFile = path.join(__dirname, 'wintage-debug.port');
  if (fs.existsSync(portFile)) {
    const port = (fs.readFileSync(portFile, 'utf8').trim() || '9222').replace(/[^0-9]/g, '') || '9222';
    const { app } = require('electron');
    app.commandLine.appendSwitch('remote-debugging-port', port);
    app.commandLine.appendSwitch('remote-debugging-address', '127.0.0.1');
    console.error('[wintage] DEBUG PORT ' + port + ' enabled by ' + portFile + ' - delete that file to turn it off');
  }
} catch (e) { }

try {
  const { app } = require('electron');
  const realGetAppPath = app.getAppPath.bind(app);
  app.getAppPath = () => ASAR;
  app.getShimPath = () => realGetAppPath();
} catch (e) {
  console.error('[wintage] could not redirect getAppPath, the app may load its web build:', e.message);
}

if (css) {
  try {
    const { app } = require('electron');

    // Injection either happened or it did not, and a themed-looking window is not
    // proof (the app may simply have a dark theme of its own). Each result is
    // stamped to a status file next to the stylesheet, so "is the theme actually
    // live in this app?" is answerable without a screenshot or a devtools port —
    // the same reason the userscript stamps data-w95-ver on every style tag.
    // Appended and capped, not overwritten: the stylesheet and the two script
    // fixes report separately and can fail independently, so one overwritten line
    // would hide whichever of them finished first.
    const stamp = text => {
      try {
        const f = path.join(__dirname, 'wintage-status.txt');
        let prev = '';
        try { prev = fs.readFileSync(f, 'utf8'); } catch (e) { }
        fs.writeFileSync(f, (prev + new Date().toISOString() + ' ' + text + '\n').split('\n').slice(-40).join('\n'));
      } catch (e) { }
    };

    // ─── EVERY webContents, NOT EVERY BrowserWindow ─────────────────────────
    // `browser-window-created` reaches a window's OWN webContents and nothing else,
    // and that is not where modern Electron apps keep their interface. Claude's
    // desktop app is the clean example: the BrowserWindow renders a thin shell
    // (.vite/renderer/main_window/index.html) and the entire visible application is
    // a WebContentsView attached to it --
    //
    //   exports.mainWindow = new BrowserWindow(...)
    //   exports.mainView   = new WebContentsView(...)   // the app you actually see
    //
    // -- so the shim faithfully injected 42 KB of stylesheet into the shell, wrote
    // "injected" to the status file, and the user correctly reported that nothing
    // had changed. The status file said the theme was live; the theme was live in a
    // frame with nothing in it.
    //
    // `web-contents-created` fires for every one of them: window contents,
    // WebContentsViews, BrowserViews, <webview> guests and popups. It is a strict
    // superset of what was hooked before, so the apps that already worked are
    // unaffected, and the failure mode it fixes is invisible by construction --
    // which is exactly why it should not be narrowed again without a reason.
    app.on('web-contents-created', (_e, wc) => {
      // dom-ready, did-finish-load and did-frame-finish-load all fire for the same
      // document, so an unguarded handler inserted the same 39 KB stylesheet three
      // times into every renderer. The status file is what made that visible.
      // PERF-004: the dedupe token is a DOCUMENT epoch, not the URL string. A
      // same-URL reload (Ctrl+R, app-triggered) is a NEW document whose insertCSS
      // must run again, but `url === injectedFor` would have skipped it forever.
      // A non-in-place main-frame navigation bumps the epoch; the three events of
      // one document share the same epoch and inject once.
      let injectedEpoch = 0;
      let injectedFor = null;
      const inject = () => {
        let url = '';
        try { url = wc.getURL(); } catch (e) { return; }
        // Devtools is Chromium's own UI, not the application's. Theming it makes
        // the one tool you would use to debug the theme unreadable.
        if (!url || url.startsWith('devtools://')) return;
        if (injectedFor === injectedEpoch) return;
        injectedFor = injectedEpoch;
        wc.executeJavaScript(SCROLL_FIX, true)
          .then(r => stamp('scrollfix: ' + r))
          .catch(err => stamp('scrollfix FAILED: ' + (err && err.message)));
        wc.executeJavaScript(WCO_FIX, true)
          .then(r => stamp('wcofix: ' + r))
          .catch(err => stamp('wcofix FAILED: ' + (err && err.message)));
        wc.executeJavaScript(REPAINTER_FIX, true)
          .then(r => stamp('repainter: ' + r))
          .catch(err => stamp('repainter FAILED: ' + (err && err.message)));
        wc.executeJavaScript(SCROLL_INTENT_FIX, true)
          .then(r => stamp('scrollintent: ' + r))
          .catch(err => stamp('scrollintent FAILED: ' + (err && err.message)));
        if (IS_FREEBUFF) {
          wc.executeJavaScript(THEME_REASSERT_FIX, true)
            .then(r => stamp('themereassert: ' + r))
            .catch(err => stamp('themereassert FAILED: ' + (err && err.message)));
          wc.executeJavaScript(FREEBUFF_POPOVER_FIX, true)
            .then(r => stamp('freebuffpopover: ' + r))
            .catch(err => stamp('freebuffpopover FAILED: ' + (err && err.message)));
        }
        const payload = CLAUDE_VIEW.test(url) ? css + CLAUDE_FOREGROUND_CSS : css;
        // PERF-007: retire the previous key BEFORE installing a replacement, and
        // only store the new key once insertCSS resolved. Storing first meant the
        // sole removal handle advanced to the newest insertion and every earlier
        // stylesheet became unreachable. A stale key from a document that is
        // already gone rejects harmlessly -- that is expected on a real
        // navigation, so it is swallowed rather than reported as a failure.
        const previousKey = wc.__wintageCssKey;
        const install = () => wc.insertCSS(payload, { cssOrigin: 'author' })
          .then(key => { wc.__wintageCssKey = key; stamp('injected ' + payload.length + ' bytes into ' + url); })
          .catch(err => {
            stamp('FAILED: ' + (err && err.message));
            console.error('[wintage] insertCSS failed:', err && err.message);
          });
        if (previousKey && typeof wc.removeInsertedCSS === 'function') {
          wc.__wintageCssKey = null;
          Promise.resolve(wc.removeInsertedCSS(previousKey)).catch(() => { }).then(install);
        } else {
          install();
        }
      };
      wc.on('dom-ready', inject);
      wc.on('did-finish-load', inject);
      // Child frames (iframes) of this contents.
      wc.on('did-frame-finish-load', inject);
      // PERF-004: every non-in-place main-frame navigation is a new document
      // even if the URL string is identical. Bump the epoch on the same
      // navigation hook the renderer treats as a new top document.
      wc.on('did-navigate', () => { injectedEpoch++; });
      // PERF-007 (SRC-004): did-navigate-in-page must NOT bump the epoch. A
      // same-document history/SPA navigation keeps the same document, the same
      // renderer and the same inserted stylesheet -- but bumping the epoch made
      // the next did-frame-finish-load (a child iframe finishing, which happens
      // constantly in an SPA) look like a fresh uninjected document. Measured on
      // the pre-fix handler: one in-page navigation followed by one frame-finish
      // took inserts from 1 to 2 and executeJavaScript calls from 4 to 8, and
      // wc.__wintageCssKey advanced to the newest key so the previous stylesheet
      // could never be removed by key. The renderer-side latches (
      // window.__wintageScrollFix and friends) limited the functional damage to
      // duplicate CSS and wasted IPC, which is exactly why nothing ever showed
      // it. A real reload still reinjects: that fires did-navigate.
    });

    // ─── THE NATIVE CAPTION STRIP ───────────────────────────────────────────
    // The caption buttons are painted by Chromium, outside the page and beyond the
    // reach of any stylesheet, so a frameless app kept a stripe of its stock
    // colours across the top of an otherwise fully themed window.
    //
    // Setting it once after the window is created is NOT enough, and Antigravity is
    // the proof: it ships an ipcMain handler for `window:set-title-bar-overlay` that
    // the renderer calls on every theme change, so our colours were applied at
    // startup and overwritten moments later by the app's own. Reported as "that
    // section top-right still is not painted", with the rest of the window themed.
    //
    // Patching the prototype makes the palette win by construction: the app can call
    // this as often as it likes and the colours are still ours, while everything else
    // it passes (notably `height`, which is layout, not colour) is left alone. Errors
    // are deliberately NOT swallowed here -- this stands in for a real Electron API
    // and a caller that expects it to throw must still see it throw.
    const { BrowserWindow } = require('electron');
    if (T_SURFACE && T_TEXT && BrowserWindow && BrowserWindow.prototype.setTitleBarOverlay) {
      const realSetOverlay = BrowserWindow.prototype.setTitleBarOverlay;
      BrowserWindow.prototype.setTitleBarOverlay = function (options) {
        return realSetOverlay.call(this, Object.assign({}, options, { color: T_SURFACE, symbolColor: T_TEXT }));
      };
      app.on('browser-window-created', (_e, win) => {
        // The CONSTRUCTOR takes titleBarOverlay as an option, not as a call, so the
        // patch above never sees the initial value -- this is what covers it. Throws
        // on a window that has no overlay at all, which is most of them: the normal
        // case, not an error, and the reason the result is stamped rather than logged.
        try {
          win.setTitleBarOverlay({});
          stamp('titlebar overlay repainted');
        } catch (e) { }
        // The window's own background shows through before the first paint and in
        // any gap the page does not cover, so a stock near-black flashed on every
        // launch of an otherwise warm-toned theme.
        if (T_BACKGROUND) { try { win.setBackgroundColor(T_BACKGROUND); } catch (e) { } }
      });
    }
  } catch (e) {
    console.error('[wintage] could not hook window creation, loading the app unthemed:', e.message);
  }
}

// Hand control to the real application. Anything thrown here is the app's own
// problem, not the theme's — but if the shim itself is what broke, the message
// says so plainly, because a user staring at an app that will not start needs to
// know which of the two to blame.
try {
  const { app } = require('electron');
  if (app && app.setAppPath) {
    app.setAppPath(ASAR);
  }
  require(ASAR);
} catch (e) {
  console.error('[wintage] failed to load the original app.asar at ' + ASAR);
  console.error('[wintage] delete this folder (resources/app) to restore the app exactly as it was.');
  throw e;
}
