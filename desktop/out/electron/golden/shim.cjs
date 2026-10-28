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
const REPAINTER_BODY = "\r\n\r\n  // CORE-003: once an excluded route has been quarantined in THIS document,\r\n  // nothing may republish theme effects into it. The asynchronous entry points\r\n  // that (re)apply styling -- the global stylesheet install, shadow piercing,\r\n  // the force scheduler and the sweeper start -- read the fence and return\r\n  // without mutating.\r\n  //\r\n  // The script-scope fence is initialized before bootstrap; Electron's prelude\r\n  // declares the same binding for the extracted repainter body.\r\n\r\n  function parseRGB(str) {\r\n    if (!str) return null;\r\n    const m = str.match(/rgba?\\(\\s*(\\d+)\\s*,\\s*(\\d+)\\s*,\\s*(\\d+)(?:\\s*[,/]\\s*([\\d.]+))?/);\r\n    if (!m) return null;\r\n    return { r: +m[1], g: +m[2], b: +m[3], a: m[4] !== undefined ? parseFloat(m[4]) : 1 };\r\n  }\r\n  // Write-if-changed: re-verify passes revisit every element, so identical\r\n  // rewrites must not invalidate styles or churn the style attribute.\r\n  // CORE-003: what this theme overwrote on each element's inline style, kept\r\n  // only so the excluded-route quarantine can put it back. A WeakMap so a\r\n  // painted element that detaches keeps no entry, and a plain object per\r\n  // element so a repeated rewrite of the same property records the FIRST\r\n  // pre-theme value (the one that has to be restored), not its own output.\r\n  const ownedInlineOriginals = new WeakMap();\r\n  function setImp(el, prop, val) {\r\n    const st = el && el.style;\r\n    if (!st || typeof st.getPropertyValue !== 'function' || typeof st.setProperty !== 'function') return false;\r\n    const priority = typeof st.getPropertyPriority === 'function' ? st.getPropertyPriority(prop) : null;\r\n    if (st.getPropertyValue(prop) !== val || priority !== 'important') {\r\n      // CORE-003: the quarantine restores what THIS theme overwrote, not every\r\n      // declaration on the element. A site's own !important on the same\r\n      // property must survive an excluded-route quarantine exactly as it was,\r\n      // so the pre-write value and priority are recorded on the first write of\r\n      // each (element, property) pair and dropped again on restore.\r\n      let rec = ownedInlineOriginals.get(el);\r\n      if (!rec) { rec = {}; ownedInlineOriginals.set(el, rec); }\r\n      if (!(prop in rec)) {\r\n        rec[prop] = { value: st.getPropertyValue(prop), priority: priority };\r\n      }\r\n      st.setProperty(prop, val, 'important');\r\n    }\r\n    return true;\r\n  }\r\n\r\n  // 🚨 READ/WRITE SPLIT — this was THE idle-CPU bug (v1.3.0) 🚨\r\n  // process() used to read getComputedStyle and write inline styles in the same\r\n  // loop. Every inline write invalidates style, so the NEXT element's read had\r\n  // to force a whole-document style recalc — and this theme's own selectors make\r\n  // that the most expensive recalc shape there is (`*`, `*, *::before, *::after`,\r\n  // the 8-`:not([class*=\"…\" i])` icon-font selector, the 12-negation hover-freeze\r\n  // selector). One write per element therefore bought one full recalc per\r\n  // element. Measured live on en.wikipedia.org/wiki/World_War_II, 16921 elements,\r\n  // published v1.2.1 eval'd in-page:\r\n  //     2500 elements, reads only ................  70.6 ms\r\n  //     2500 elements, interleaved read+write ....  1069–1994 ms   ← old code\r\n  //     2500 elements, batched read-then-write ...  230.9 ms  (~190 ms of which\r\n  //                                                 is ONE whole-doc recalc)\r\n  // One real instrumented sweeper tick measured 253 ms per 1.5 s interval =\r\n  // 16.9 % of a core, permanently, on a page that was doing nothing.\r\n  //\r\n  // So process() now ONLY READS. Instead of writing, it appends [el, prop, val]\r\n  // triples to a queue that the caller flushes once at the end: N recalcs -> 1.\r\n  // A flat array (not objects) keeps the queue allocation-free per element.\r\n  //\r\n  // Correctness note on batching: `color` is inherited, so a child no longer\r\n  // sees its parent's just-corrected color while being read — it fails the\r\n  // contrast check against the ORIGINAL inherited value and gets its own\r\n  // explicit inline color. Identical final pixels, one extra declaration; it\r\n  // can never resolve to a DIFFERENT color, only to the same one stated twice.\r\n  // Non-inherited properties (background, border-*) are unaffected either way.\r\n  //\r\n  // Attribute writes stay inline and are deliberately NOT queued: setAttribute\r\n  // ('data-w95-done') is not referenced by any selector in this theme, so it\r\n  // invalidates nothing (measured: 6.7 ms for all 16921 elements), and\r\n  // removeAttribute('bgcolor'/'background') is a no-op when absent.\r\n  // 🚨 SELF-WRITE SUPPRESSION IS BY IDENTITY, NEVER BY A TIME WINDOW (v1.4.2) 🚨\r\n  // 'style' IS in the observer's attributeFilter, which ADR-002 said never to do.\r\n  // It is worth doing — a site mutating an existing element's inline style is\r\n  // otherwise invisible, and catching it with an event is what let the 30s\r\n  // polling heartbeat be deleted entirely. But setImp writes inline styles, so\r\n  // the observer WILL be handed its own output and the suppression has to be\r\n  // airtight.\r\n  //\r\n  // The first attempt muted all 'style' records for 100ms after each flush.\r\n  // Measured on a static article (16595 elements), 12-second window:\r\n  //     site alone, no theme .......    0 style mutations\r\n  //     with the theme ............. 9466 style mutations\r\n  // i.e. every single one was ours. The mute discarded them at flush time, so\r\n  // there was no runaway — but 9466 records were still allocated, delivered\r\n  // through a microtask, and pushed into pendingMuts to be walked by the next\r\n  // debounce. And it was only ever timing-safe by luck: the filter runs at the\r\n  // END of the 60ms debounce, so any flush that lands >100ms before its debounce\r\n  // fires (i.e. exactly when the main thread is busy, which is exactly during a\r\n  // heavy sweep) lets our own writes through, and each one that gets processed\r\n  // clears data-w95-done and re-processes the element, generating more writes.\r\n  // A blanket window also drops the SITE's real style changes for 100ms.\r\n  //\r\n  // So: record precisely which elements we wrote, then drain the observer queue\r\n  // ourselves with takeRecords() before the callback ever runs, keeping every\r\n  // record that was not ours. Timing-independent and scoped to the exact\r\n  // elements involved.\r\n  const selfWritten = new Set();\r\n\r\n  function flushWrites(w) {\r\n    if (!w.length) return;\r\n    for (let i = 0; i < w.length; i += 3) {\r\n      if (setImp(w[i], w[i + 1], w[i + 2])) selfWritten.add(w[i]);\r\n    }\r\n    w.length = 0;\r\n    // takeRecords() returns AND clears the pending queue, so this runs before\r\n    // the observer callback is ever invoked for these mutations.\r\n    let kept = 0;\r\n    for (const obs of [mainObserver, shadowObserver]) {\r\n      let recs;\r\n      try { recs = obs.takeRecords(); } catch (e) { continue; }\r\n      for (let i = 0; i < recs.length; i++) {\r\n        const m = recs[i];\r\n        if (m.type === 'attributes' && m.attributeName === 'style' && selfWritten.has(m.target)) continue;\r\n        pendingMuts.push(m);\r\n        kept++;\r\n      }\r\n    }\r\n    selfWritten.clear();\r\n    // Anything genuinely foreign that was queued alongside our writes still has\r\n    // to be handled; the debounce is not running at this point (flushWrites is\r\n    // called at the END of it, and from runSweeper), so it needs re-arming.\r\n    // Known and accepted gap: a site style-change on an element WE also wrote to\r\n    // in the same batch is dropped. It is self-healing — the next sweep re-reads\r\n    // that element's computed style from scratch.\r\n    if (kept && !debounceTimer) onMutations(EMPTY_MUTATIONS);\r\n  }\r\n  const EMPTY_MUTATIONS = [];\r\n\r\n  // 🚨 SATURATED COLOUR -> ONE OF THREE SEMANTIC TOKENS (UI.md law 5) 🚨\r\n  // The pre-1.4.0 rule multiplied a light saturated background by 0.18, which\r\n  // \"preserved the hue\" — and in doing so emitted an unbounded set of arbitrary\r\n  // colours that trace to no token at all. GitHub's diff green became one\r\n  // brown-green, GitLab's a different one, a warning banner a third: iron law 5\r\n  // broken every time, and every site kept its own colour signature.\r\n  //\r\n  // UI.md ships exactly three semantic colours, so the site's own hue only has to\r\n  // answer one question: which of the three did it mean? Hue sectors, wide and\r\n  // deliberately coarse, because the answer only needs to be right to within\r\n  // \"green / amber / red\":\r\n  //   red-ish    (>=345 or <35 deg) -> --danger\r\n  //   yellow-ish (35..75 deg)       -> --warning\r\n  //   green-ish  (75..170 deg)      -> --success\r\n  // Everything else — blues, purples, teals, magentas — carries no shared meaning\r\n  // across sites, so it becomes plain --surfaceRaised rather than being forced\r\n  // into a status colour it never claimed.\r\n  function semanticToken(c) {\r\n    const max = Math.max(c.r, c.g, c.b), min = Math.min(c.r, c.g, c.b), d = max - min;\r\n    if (d === 0) return T.surfaceRaised;\r\n    let h;\r\n    if (max === c.r) h = 60 * (((c.g - c.b) / d) % 6);\r\n    else if (max === c.g) h = 60 * ((c.b - c.r) / d + 2);\r\n    else h = 60 * ((c.r - c.g) / d + 4);\r\n    if (h < 0) h += 360;\r\n    if (h >= 345 || h < 35) return T.danger;\r\n    if (h < 75) return T.warning;\r\n    if (h < 170) return T.success;\r\n    return T.surfaceRaised;\r\n  }\r\n\r\n  // UI.md's five permitted sizes, and the role mapping GLOBAL_CSS uses. Kept as\r\n  // lookups so the JS enforcement below can never drift from the CSS layer.\r\n  const SIZE_ALLOWED = new Set(['10px', '11px', '12px', '14px', '16px']);\r\n  const LADDER = {\r\n    H1: '16px', H2: '14px', H3: '14px', H4: '14px', H5: '14px', H6: '14px',\r\n    SMALL: '10px', SUB: '10px', SUP: '10px', FIGCAPTION: '10px'\r\n  };\r\n  // The palette as the browser serialises it, for cheap \"is this already one of\r\n  // ours?\" tests against a computed value.\r\n  const PALETTE_RGB = new Set(Object.keys(T).map(k => {\r\n    const h = T[k];\r\n    return 'rgb(' + parseInt(h.slice(1, 3), 16) + ', ' + parseInt(h.slice(3, 5), 16) + ', ' + parseInt(h.slice(5, 7), 16) + ')';\r\n  }));\r\n\r\n  const ICONISH = /icon|fa-|symbols|glyph|mdi|bi-/i;\r\n  function isIconish(el) {\r\n    // className is an SVGAnimatedString on SVG elements, not a string — read the\r\n    // attribute instead of trusting the property.\r\n    const c = el.getAttribute && el.getAttribute('class');\r\n    return c ? ICONISH.test(c) : false;\r\n  }\r\n\r\n  const JS_SKIP_SELECTOR = '#movie_player, .html5-video-player, ytd-player, ytd-thumbnail, yt-img-shadow, ytd-avatar-shape, yt-avatar-shape, #avatar, #author-thumbnail, ytd-logo, yt-icon, yt-icon-shape, ytcp-bar-chart, .ytcp-bar-chart, [class*=\"bar-chart\" i], [class*=\"comparison-bar\" i], [class*=\"trend-cell\" i], ytcp-table-cell-compare-period, [class*=\"screen-pause\" i], [class*=\"player-screen\" i], [class*=\"video-screen\" i], [class*=\"vjs-text-track\" i], [class*=\"inset-0\" i], [class*=\"stretched-link\" i], [class*=\"cover-link\" i]';\r\n  const SHADOW_SKIP_TAGS = new Set(['YTD-LOGO', 'YT-ICON', 'YT-ICON-SHAPE', 'YT-IMG-SHADOW', 'YTD-AVATAR-SHAPE', 'YT-AVATAR-SHAPE', 'VIDEO', 'AUDIO', 'CANVAS', 'IFRAME']);\r\n  const TAG_SKIP = /^(IMG|VIDEO|CANVAS|PICTURE|IFRAME|SVG|PATH|CIRCLE|RECT|LINE|POLYGON|POLYLINE|ELLIPSE|DEFS|SYMBOL|USE|STYLE|SCRIPT|LINK|META|HEAD|HTML|BR|HR|WBR|TEMPLATE|NOSCRIPT|AUDIO|SOURCE|TRACK|OPTION|OPTGROUP)$/i;\r\n\r\n  const piercedRoots = new Set();\r\n  let forceLapActive = false;\r\n  let forceLapId = 0;\r\n\r\n  // PERF-004 (SRC-004): the observer options are declared ONCE, here, because\r\n  // the registration has to be rebuilt later (see pruneShadowRegistry) and a\r\n  // rebuild that does not match the original registration silently changes what\r\n  // is observed. Declared beside piercedRoots rather than beside the observer so\r\n  // pierceShadow -- which sits above the observer -- can read it without a TDZ\r\n  // ReferenceError.\r\n  const SHADOW_OBS_OPTS = {\r\n    childList: true,\r\n    subtree: true,\r\n    attributes: true,\r\n    attributeFilter: ['class', 'bgcolor', 'background', 'style']\r\n  };\r\n\r\n  function pierceShadow(host) {\r\n    // CORE-003: no new shadow root takes the theme while the route is excluded.\r\n    if (routeQuarantined) return;\r\n    const tag = (host.tagName || '').toUpperCase();\r\n    if (SHADOW_SKIP_TAGS.has(tag)) return;\r\n    if (!host.shadowRoot || piercedRoots.has(host.shadowRoot)) return;\r\n    // PERF-005 (SRC-063, T-404): a root discovered DURING a force lap is\r\n    // registered immediately and stamped for the NEXT lap. The live iterator may\r\n    // encounter it -- a Set tolerates insertion during iteration -- and the\r\n    // lap loop skips anything stamped past its own id, so the next lap's fresh\r\n    // iterator simply picks it up. That replaces a second strong-owner Set that\r\n    // was repaid in full, unbounded, in the one callback where the lane is not\r\n    // root-budgeted.\r\n    host.shadowRoot.__wintageLapId = forceLapActive ? forceLapId + 1 : forceLapId;\r\n    registerStyleRoot(host.shadowRoot);\r\n    try {\r\n      injectStyle(host.shadowRoot, 'shadow', ACTIVE_SHADOW_CSS);\r\n      if (!CSS_ONLY_MODE) {\r\n        shadowObserver.observe(host.shadowRoot, SHADOW_OBS_OPTS);\r\n        stylesDirty = true;\r\n      } else {\r\n        // T-902: a per-shadow-root observer is exactly the fan-out the CSS-only\r\n        // contract forbids. The root keeps its creation-time stylesheet and is\r\n        // never observed.\r\n        noteRepaintSkipped();\r\n      }\r\n    } catch (e) { noteSuppressed('shadowPierceThrows', e); }\r\n  }\r\n\r\n\r\n  // ─── :hover RULE SURGERY (v29.1 / R013) ─────────────────────────────────────\r\n  // Strips paint properties out of every readable :hover rule so sites cannot\r\n  // flashbang-highlight on hover. Functional props (display, visibility,\r\n  // opacity, transform) are left untouched so hover-opened menus keep working.\r\n  // Cross-origin sheets that throw on cssRules access are covered by the CSS\r\n  // freeze rule in GLOBAL_CSS/SHADOW_CSS instead.\r\n  const STYLE_SHEET_BUDGET = 32;\r\n  const STYLE_RULE_BUDGET = 500;\r\n  const STYLE_ROOT_BUDGET = 16;\r\n  const HOVER_PAINT = /^(background|box-shadow|filter|backdrop-filter|color|border|outline|text-decoration|text-shadow|--)/;\r\n  const sheetSeen = new WeakMap(); // sheet -> { gen, count } at last pass\r\n  // PERF-010: same-count stylesheet replacement (CSSStyleSheet.replace /\r\n  // replaceSync, or STYLE text replacement) is a normal mutation shape and\r\n  // must invalidate the per-sheet hover-surgery cache. cssRules.length is\r\n  // not a generation identifier: it can stay constant while every rule is\r\n  // rewritten. We instrument the CSSStyleSheet prototype once at startup to\r\n  // bump a per-sheet generation token whenever ANY rule-mutating API runs.\r\n  // The bounded style cursor then re-walks the sheet whenever either length or\r\n  // generation changes, instead of silently skipping same-count changes.\r\n  if (CSS_ONLY_MODE) noteRepaintSkipped();\r\n  if (!CSS_ONLY_MODE && typeof CSSStyleSheet !== 'undefined' && CSSStyleSheet.prototype) {\r\n    const proto = CSSStyleSheet.prototype;\r\n    // T-397 handover box, republished by EVERY generation and read at call time\r\n    // by the hooks installed below. Those hooks live on a shared prototype for\r\n    // the document's whole life, so closing over this pass's stylesDirty and\r\n    // requestLightSweep meant a newer generation loaded over the page never took\r\n    // ownership: every later CSSOM mutation kept waking the FIRST generation's\r\n    // scheduler. The box republishes OUTSIDE the installation guard below,\r\n    // because the generation that skips installation is exactly the one whose\r\n    // closure must be replaced.\r\n    proto.__wintageSheetOwner = function (sheet) {\r\n      try { if (sheet && typeof sheet === 'object') sheet.__wintageGen = (sheet.__wintageGen || 0) + 1; } catch (e) { }\r\n      try { stylesDirty = true; } catch (e) { }\r\n      try { requestLightSweep(); } catch (e) { }\r\n    };\r\n    if (!proto.__wintageInstrumented) {\r\n    CSSStyleSheet.prototype.__wintageInstrumented = true;\r\n    // PERF-001 (audit/7.md, SRC-018:R013): a direct CSSOM mutation\r\n    // (insertRule / deleteRule / replaceSync / replace) need not create a DOM\r\n    // MutationObserver record, so before this fix the generation token advanced\r\n    // while NO scheduler debt was set: the change stayed untreated until some\r\n    // unrelated DOM event happened to set stylesDirty. The generation bump and\r\n    // the scheduler wake are now ONE operation, and the wake is the existing\r\n    // coalesced light lane (one pending timer however many mutations arrive).\r\n    const bumpStyleSheet = function (sheet) {\r\n      // The installed hooks call THIS function, which was captured by the\r\n      // generation that wrapped the prototype. It owns nothing itself: it\r\n      // forwards to whichever generation last published the box, and falls\r\n      // back to a bare generation bump only if that write was refused.\r\n      const owner = proto.__wintageSheetOwner;\r\n      if (owner) { owner(sheet); return; }\r\n      try { if (sheet && typeof sheet === 'object') sheet.__wintageGen = (sheet.__wintageGen || 0) + 1; } catch (e) { }\r\n    };\r\n    if (typeof proto.replace === 'function' && !proto.__wintagePatchedReplace) {\r\n      const origReplace = proto.replace;\r\n      // replace() is ASYNC. Invalidating at call time stamps the NEW generation\r\n      // onto the OLD rules: a style pass that runs before fulfillment scans the\r\n      // old rules under the new generation, sheetSeen records that generation,\r\n      // and the completed same-count replacement is then indistinguishable from\r\n      // an already-scanned sheet. So invalidation is attached to Promise\r\n      // FULFILLMENT only, a rejection is a no-op, and the ORIGINAL Promise is\r\n      // returned unchanged (identity preserved).\r\n      proto.replace = function () {\r\n        const r = origReplace.apply(this, arguments);\r\n        const sheet = this;\r\n        if (r && typeof r.then === 'function') {\r\n          r.then(function () { bumpStyleSheet(sheet); }, function () { });\r\n          return r;\r\n        }\r\n        bumpStyleSheet(sheet);\r\n        return r;\r\n      };\r\n      proto.__wintagePatchedReplace = true;\r\n    }\r\n    if (typeof proto.replaceSync === 'function' && !proto.__wintagePatchedReplaceSync) {\r\n      const origReplaceSync = proto.replaceSync;\r\n      // Native return value and thrown exceptions are preserved: if the native\r\n      // call throws, invalidate never runs (only a successful operation\r\n      // advances the generation and arms the continuation).\r\n      proto.replaceSync = function () { const r = origReplaceSync.apply(this, arguments); bumpStyleSheet(this); return r; };\r\n      proto.__wintagePatchedReplaceSync = true;\r\n    }\r\n    if (typeof proto.insertRule === 'function' && !proto.__wintagePatchedInsert) {\r\n      const origInsert = proto.insertRule;\r\n      proto.insertRule = function () { const r = origInsert.apply(this, arguments); bumpStyleSheet(this); return r; };\r\n      proto.__wintagePatchedInsert = true;\r\n    }\r\n    if (typeof proto.deleteRule === 'function' && !proto.__wintagePatchedDelete) {\r\n      const origDelete = proto.deleteRule;\r\n      proto.deleteRule = function () { const r = origDelete.apply(this, arguments); bumpStyleSheet(this); return r; };\r\n      proto.__wintagePatchedDelete = true;\r\n    }\r\n    }\r\n  }\r\n  // TARGET C: lazy STYLE text replacement detection on sheet encounter.\r\n  // Zero full STYLE node queries across roots.\r\n  function bumpStyleElementSheets(sheet) {\r\n    if (!sheet) return;\r\n    try {\r\n      const node = sheet.ownerNode;\r\n      if (node && (node.nodeName === 'STYLE' || node.tagName === 'STYLE')) {\r\n        if (node.__wintageLastText !== node.textContent) {\r\n          node.__wintageLastText = node.textContent;\r\n          sheet.__wintageGen = (sheet.__wintageGen || 0) + 1;\r\n        }\r\n      }\r\n    } catch (e) { noteSuppressed('sheetGenThrows', e); }\r\n  }\r\n\r\n  // CORE-003: stripHoverRule DELETES declarations from rules the site wrote.\r\n  // That is a mutation of foreign state with no snapshot until now, so the\r\n  // excluded-route quarantine could never put it back. Every first-time strip\r\n  // records the removed name/value/priority triples keyed BY RULE, so nothing is\r\n  // written onto the site's own CSSOM rule object and a rule the page drops\r\n  // releases its snapshot with it. A later strip of the same rule records\r\n  // nothing (the originals are already frozen) and only removes what a newer\r\n  // pass read. restoreHoverRules() drains the registry, so no rule is retained\r\n  // past the restore that needed it.\r\n  const HOVER_REGISTRY_CAP = 4096;\r\n  const hasWeakRef = typeof WeakRef !== 'undefined';\r\n  const hoverStrippedRules = [];          // WeakRef handles, compacted at the cap\r\n  const hoverStrippedOriginals = new WeakMap();  // rule -> frozen pre-strip triples\r\n  const hoverHandleOf = function (entry) {\r\n    if (hasWeakRef && entry && typeof entry.deref === 'function') {\r\n      try { return entry.deref(); } catch (e) { return null; }\r\n    }\r\n    return entry || null;\r\n  };\r\n  function compactHoverRegistry() {\r\n    if (!hoverStrippedRules.length) return;\r\n    const kept = [];\r\n    for (let i = 0; i < hoverStrippedRules.length; i++) {\r\n      if (hoverHandleOf(hoverStrippedRules[i])) kept.push(hoverStrippedRules[i]);\r\n    }\r\n    hoverStrippedRules.length = 0;\r\n    for (let i = 0; i < kept.length; i++) hoverStrippedRules.push(kept[i]);\r\n  }\r\n  function stripHoverRule(rule) {\r\n    const st = rule.style;\r\n    if (!st) return;\r\n    let originals = hoverStrippedOriginals.get(rule);\r\n    const firstStrip = !originals;\r\n    if (firstStrip) originals = { props: [], values: [], priorities: [] };\r\n    const names = [];\r\n    for (let i = 0; i < st.length; i++) names.push(st[i]);\r\n    for (let i = 0; i < names.length; i++) {\r\n      if (!HOVER_PAINT.test(names[i])) continue;\r\n      if (firstStrip) {\r\n        originals.props.push(names[i]);\r\n        originals.values.push(typeof st.getPropertyValue === 'function' ? st.getPropertyValue(names[i]) : '');\r\n        originals.priorities.push(typeof st.getPropertyPriority === 'function' ? st.getPropertyPriority(names[i]) : '');\r\n      }\r\n      st.removeProperty(names[i]);\r\n    }\r\n    // Nothing was actually stripped (a rule with no matching declarations):\r\n    // track nothing at all rather than remembering it forever.\r\n    if (!firstStrip || !originals.props.length) return;\r\n    try { hoverStrippedOriginals.set(rule, originals); } catch (e) { }\r\n    try { hoverStrippedRules.push(hasWeakRef ? new WeakRef(rule) : rule); } catch (e2) { hoverStrippedRules.push(rule); }\r\n    if (hoverStrippedRules.length > HOVER_REGISTRY_CAP) compactHoverRegistry();\r\n  }\r\n\r\n  function restoreHoverRules() {\r\n    for (let i = 0; i < hoverStrippedRules.length; i++) {\r\n      const rule = hoverHandleOf(hoverStrippedRules[i]);\r\n      if (!rule) continue;\r\n      const originals = hoverStrippedOriginals.get(rule);\r\n      if (originals) {\r\n        for (let j = 0; j < originals.props.length; j++) {\r\n          try { rule.style.setProperty(originals.props[j], originals.values[j], originals.priorities[j]); } catch (e) { }\r\n        }\r\n        try { hoverStrippedOriginals.delete(rule); } catch (e2) { }\r\n      }\r\n    }\r\n    // The registry exists only between a strip and its restore; leaving it\r\n    // populated would retain every hover rule in the document for life.\r\n    hoverStrippedRules.length = 0;\r\n  }\r\n\r\n  // TARGET D: Iterative, bounded rule traversal with persistent stack frame.\r\n  // Replaces recursive walkRules. Every cssRules index read consumes ruleBudget.\r\n  function drainStyleRules(task, ruleBudget) {\r\n    let budgetRemaining = ruleBudget;\r\n    while (task.stack.length > 0 && budgetRemaining > 0) {\r\n      const frame = task.stack[task.stack.length - 1];\r\n      if (frame.index >= frame.length) {\r\n        task.stack.pop();\r\n        continue;\r\n      }\r\n      let rule;\r\n      try {\r\n        rule = frame.container[frame.index];\r\n      } catch (e) {\r\n        if (task.mode === 'append') {\r\n          try { throw e; } catch (e) { noteSuppressed('hoverAppendThrows', e); }\r\n        } else {\r\n          try { throw e; } catch (e) { noteSuppressed('hoverWalkThrows', e); }\r\n        }\r\n        rule = null;\r\n      }\r\n      frame.index++;\r\n      budgetRemaining--;\r\n\r\n      if (!rule) continue;\r\n      if (rule.type === 7) continue; // CSSRule.KEYFRAMES_RULE has no :hover rules\r\n\r\n      try {\r\n        if (rule.selectorText && rule.selectorText.indexOf(':hover') !== -1) {\r\n          stripHoverRule(rule);\r\n        }\r\n        let nested = null;\r\n        try {\r\n          if (rule.cssRules && rule.cssRules.length > 0) nested = rule.cssRules;\r\n        } catch (e) { }\r\n        if (nested) {\r\n          task.stack.push({\r\n            container: nested,\r\n            index: 0,\r\n            length: nested.length\r\n          });\r\n        }\r\n      } catch (e) { noteSuppressed('hoverWalkThrows', e); }\r\n    }\r\n    return ruleBudget - budgetRemaining;\r\n  }\r\n\r\n  let activeStyleTask = null;\r\n  let styleCursorRoot = null;\r\n  let styleCursorRootIterator = null;\r\n  let styleCursorListIndex = 0;\r\n  let styleCursorSheetIndex = 0;\r\n\r\n  // R013 / TARGET D: style-lap membership is FINITE. `piercedRoots.values()`\r\n  // is a LIVE Set iterator, so a root pierced while a style lap is running\r\n  // would otherwise join that same lap (unbounded, and it makes the lap's size\r\n  // a function of how long the lap takes, which is exactly the coupling\r\n  // TARGET A removed from the force lane). Every root is stamped with a\r\n  // monotonic sequence when it is registered; a style lap captures the\r\n  // sequence reached when it STARTS; a root stamped later is deferred to the\r\n  // NEXT lap. Deferral costs root budget (discovery is never free) and keeps\r\n  // the style debt set, so the later lap is guaranteed to happen.\r\n  let styleRootSeq = 0;                     // monotonic registration stamp\r\n  let styleLapSeqLimit = 0;                 // stamp captured by the ACTIVE lap\r\n  const styleLapDeferredRoots = new Set();  // arrived during the active lap\r\n\r\n  // Single registration point: membership stamp and registry add stay together\r\n  // so no future caller can add a root that a running lap would swallow.\r\n  function registerStyleRoot(root) {\r\n    // A frozen/exotic root cannot take the stamp; it then reads as pre-existing\r\n    // (undefined > limit is false) and is served by the current lap. Failing\r\n    // open here can only cost work, never coverage.\r\n    try { root.__wintageStyleSeq = ++styleRootSeq; } catch (e) { }\r\n    try { piercedRoots.add(root); } catch (e) { }\r\n  }\r\n\r\n  // TARGET B & G: Bounded incremental style work draining.\r\n  function drainStyleWork(sheetBudget, ruleBudget, rootBudget = STYLE_ROOT_BUDGET) {\r\n    let rulesRemaining = ruleBudget;\r\n    let sheetsRemaining = sheetBudget;\r\n    let rootsRemaining = rootBudget;\r\n    let changed = false;\r\n\r\n    // 1. Drain active task if one is in flight\r\n    if (activeStyleTask) {\r\n      const currentGen = activeStyleTask.sheet.__wintageGen || 0;\r\n      if (currentGen !== activeStyleTask.gen) {\r\n        // Generation changed mid-task; re-initialize task with the new generation!\r\n        const newSheet = activeStyleTask.sheet;\r\n        let newCount;\r\n        try { newCount = newSheet.cssRules ? newSheet.cssRules.length : 0; } catch (e) { newCount = -1; }\r\n        let newRules;\r\n        try { newRules = newSheet.cssRules; } catch (e) { newRules = null; }\r\n        if (newRules && newCount > 0) {\r\n          activeStyleTask = {\r\n            sheet: newSheet,\r\n            gen: currentGen,\r\n            count: newCount,\r\n            mode: 'full',\r\n            stack: [{\r\n              container: newRules,\r\n              index: 0,\r\n              length: newCount\r\n            }]\r\n          };\r\n        } else {\r\n          sheetSeen.set(newSheet, { gen: currentGen, count: newCount });\r\n          activeStyleTask = null;\r\n        }\r\n      }\r\n      if (activeStyleTask) {\r\n        const spent = drainStyleRules(activeStyleTask, rulesRemaining);\r\n        rulesRemaining -= spent;\r\n        if (activeStyleTask.stack.length === 0) {\r\n          if ((activeStyleTask.sheet.__wintageGen || 0) === activeStyleTask.gen) {\r\n            sheetSeen.set(activeStyleTask.sheet, { gen: activeStyleTask.gen, count: activeStyleTask.count });\r\n          }\r\n          activeStyleTask = null;\r\n          changed = true;\r\n        } else {\r\n          return { done: false, changed };\r\n        }\r\n      }\r\n    }\r\n\r\n    // 2. Discover sheets incrementally across document and pierced roots\r\n    if (styleCursorRoot === null) {\r\n      if (stylesDirty) {\r\n        styleCursorRoot = document;\r\n        styleCursorRootIterator = null;\r\n        styleCursorListIndex = 0;\r\n        styleCursorSheetIndex = 0;\r\n        // TARGET D: capture the membership boundary for THIS lap.\r\n        styleLapSeqLimit = styleRootSeq;\r\n        styleLapDeferredRoots.clear();\r\n      } else {\r\n        return { done: true, changed };\r\n      }\r\n    }\r\n\r\n    while (sheetsRemaining > 0 && rulesRemaining > 0 && styleCursorRoot !== null) {\r\n      const list = (styleCursorListIndex === 0 ? styleCursorRoot.styleSheets : styleCursorRoot.adoptedStyleSheets);\r\n      const listLen = list ? list.length : 0;\r\n\r\n      if (styleCursorSheetIndex < listLen) {\r\n        const sheet = list[styleCursorSheetIndex];\r\n        styleCursorSheetIndex++;\r\n        sheetsRemaining--;\r\n\r\n        if (sheet) {\r\n          const node = sheet.ownerNode;\r\n          if (!node || !node.getAttribute || !node.getAttribute('data-w95')) {\r\n            bumpStyleElementSheets(sheet);\r\n            let count;\r\n            try { count = sheet.cssRules ? sheet.cssRules.length : 0; } catch (e) { count = -1; }\r\n            const gen = sheet.__wintageGen || 0;\r\n            const seen = sheetSeen.get(sheet);\r\n\r\n            if (count === -1) {\r\n              // Throwing / cross-origin: mark seen so we don't retry forever (TARGET D/8)\r\n              sheetSeen.set(sheet, { gen, count: -1 });\r\n            } else if (seen && seen.gen === gen && seen.count === count) {\r\n              // Clean\r\n            } else {\r\n              const isAppend = seen && seen.gen === gen && seen.count < count;\r\n              let rules = null;\r\n              try { rules = sheet.cssRules; } catch (e) { rules = null; }\r\n\r\n              if (rules && count > 0) {\r\n                // TARGET F: Append uses the EXACT same rule budget and task stack\r\n                activeStyleTask = {\r\n                  sheet,\r\n                  gen,\r\n                  count,\r\n                  mode: isAppend ? 'append' : 'full',\r\n                  stack: [{\r\n                    container: rules,\r\n                    index: isAppend ? seen.count : 0,\r\n                    length: count\r\n                  }]\r\n                };\r\n\r\n                const spent = drainStyleRules(activeStyleTask, rulesRemaining);\r\n                rulesRemaining -= spent;\r\n\r\n                if (activeStyleTask.stack.length === 0) {\r\n                  // TARGET E: Completion-safe sheetSeen\r\n                  if ((sheet.__wintageGen || 0) === gen) {\r\n                    sheetSeen.set(sheet, { gen, count });\r\n                  }\r\n                  activeStyleTask = null;\r\n                  changed = true;\r\n                } else {\r\n                  return { done: false, changed };\r\n                }\r\n              } else {\r\n                sheetSeen.set(sheet, { gen, count });\r\n              }\r\n            }\r\n          }\r\n        }\r\n      } else {\r\n        if (styleCursorListIndex === 0) {\r\n          styleCursorListIndex = 1;\r\n          styleCursorSheetIndex = 0;\r\n        } else {\r\n          styleCursorListIndex = 0;\r\n          styleCursorSheetIndex = 0;\r\n          if (styleCursorRoot === document) {\r\n            styleCursorRootIterator = piercedRoots.values();\r\n          }\r\n          if (styleCursorRootIterator) {\r\n            let nextRoot = null;\r\n            while (rootsRemaining > 0) {\r\n              const n = styleCursorRootIterator.next();\r\n              if (n.done) {\r\n                styleCursorRootIterator = null;\r\n                break;\r\n              }\r\n              rootsRemaining--;\r\n              const r = n.value;\r\n              // TARGET D: stamped after this lap started -> next lap. Discovery\r\n              // already consumed root budget above; the debt flag at the end of\r\n              // the lap keeps the continuation scheduled.\r\n              let stampedLate = false;\r\n              try { stampedLate = r.__wintageStyleSeq > styleLapSeqLimit; } catch (e) { stampedLate = false; }\r\n              if (stampedLate) { styleLapDeferredRoots.add(r); continue; }\r\n              let detached = false;\r\n              try { detached = !r.host || !r.host.isConnected; } catch (e) { detached = true; }\r\n              if (!detached) { nextRoot = r; break; }\r\n            }\r\n            styleCursorRoot = nextRoot;\r\n            if (rootsRemaining <= 0 && styleCursorRootIterator) {\r\n              return { done: false, changed };\r\n            }\r\n          } else {\r\n            styleCursorRoot = null;\r\n          }\r\n        }\r\n      }\r\n    }\r\n\r\n    if (styleCursorRoot === null && activeStyleTask === null) {\r\n      // TARGET D: incomplete membership is NOT completion. Roots that arrived\r\n      // mid-lap (or arrived after the iterator ran out) leave the debt set, so\r\n      // the scheduler arms the next lap instead of the work being lost.\r\n      if (styleLapDeferredRoots.size > 0 || styleRootSeq > styleLapSeqLimit) {\r\n        return { done: false, changed };\r\n      }\r\n      stylesDirty = false;\r\n      return { done: true, changed };\r\n    }\r\n\r\n    return { done: false, changed };\r\n  }\r\n\r\n  // R013 / TARGET G: there is no root-level stripHoverSheets() helper any more.\r\n  // It was the last place a stylesheet could be walked OUTSIDE the scheduler\r\n  // (the light lane called it once per root, and a root-level helper call is\r\n  // unbounded by construction). Every sheet now goes through drainStyleWork's\r\n  // persistent cursor, so the only way to reach CSSOM is a budgeted slice.\r\n\r\n  // `w` is the caller's write queue (see flushWrites). Reads only — every style\r\n  // change is appended, never applied here.\r\n  function process(el, force, w) {\r\n    // v29 FIX: the old `el.closest(':hover')` guard was fatal — html/body match\r\n    // :hover whenever the cursor is anywhere over the viewport, so closest()\r\n    // returned truthy for EVERY element and the sweeper silently processed\r\n    // nothing while the mouse was on the page (= dark-on-dark text never got\r\n    // contrast-fixed). Only skip elements that are themselves in an interactive\r\n    // state chain; they get retried on later sweeps.\r\n    try {\r\n      if (el && el.matches && el.matches(':hover,:active,:focus')) return;\r\n    } catch (e) { }\r\n\r\n    if (!el || el.nodeType !== 1) return;\r\n    if (!force && el.hasAttribute('data-w95-done')) return;\r\n    el.setAttribute('data-w95-done', '1');\r\n\r\n    if (el.shadowRoot) pierceShadow(el);\r\n\r\n    const cs = window.getComputedStyle(el);\r\n\r\n    // 🚨 INFINITE ANIMATIONS GET PAUSED, NOT SPED UP (v1.4.1) 🚨\r\n    // The global 'animation-duration: 0.001s' makes FINITE animations instant,\r\n    // which is the goal. On an INFINITE animation it does the opposite of\r\n    // stopping it. Measured exactly, via the Web Animations API on a real\r\n    // spinner (duration 1ms, iterations Infinity):\r\n    //     iterations in 1 second .............. 1000   (site intended: 1)\r\n    //     iterations per 60fps frame ..........   16.7 (site intended: 0)\r\n    //     angle rendered on 6 consecutive frames:\r\n    //       240deg, 120deg, 0deg, 240deg, 120deg, 0deg\r\n    // 16.667ms per frame divided by a 1ms duration leaves a repeating 2/3\r\n    // remainder, so a spinner does not freeze — it strobes between exactly three\r\n    // rotations forever. That is worse than the smooth spin it replaced, and it\r\n    // makes this theme's \"zero animations\" claim false. ADR-001 checked that\r\n    // Chromium does not FLOOD animationiteration events here and stopped there;\r\n    // it never checked what was actually on screen. See ADR-004.\r\n    //\r\n    // Pausing is safe precisely where the 0.001s compromise is pointless: an\r\n    // infinite animation's 'animationend' NEVER fires, so no animationend-driven\r\n    // state machine can be waiting on one — and keeping animationend alive is the\r\n    // entire reason 0.001s was chosen over 0s/none in the first place (ADR-001).\r\n    // 'paused' rather than 'animation: none' because a paused animation keeps\r\n    // applying its current computed value: cancelling instead would snap the\r\n    // element back to its base state, which for a pulse/skeleton loop is often\r\n    // opacity 0 — i.e. it would make content vanish.\r\n    //\r\n    // Known residual risk: code that drives state from 'animationiteration'\r\n    // (some marquee and carousel loops) will stall. Rare, and the alternative is\r\n    // a permanent three-position strobe on every spinner on the web.\r\n    //\r\n    // This runs BEFORE shouldSkip on purpose. The two commonest spinner shapes\r\n    // are both in the skip set: Tailwind's 'svg.animate-spin' (SVG is in\r\n    // TAG_SKIP) and a spinner inside a loading <button> (shouldSkip matches\r\n    // closest('button')). Checking after the skip would miss exactly the cases\r\n    // that matter.\r\n    const iterCount = cs.animationIterationCount;\r\n    if (iterCount && iterCount.indexOf('infinite') !== -1) {\r\n      w.push(el, 'animation-play-state', 'paused');\r\n    }\r\n\r\n    // 🚨 UI.md HARD INVARIANTS, ENFORCED FROM JS BECAUSE CSS CANNOT WIN (v1.4.3) 🚨\r\n    // Our universal rules are '* { border-radius: 0 !important }' etc, which score\r\n    // specificity (0,0,0). A site's own '!important' beats them the moment it has\r\n    // any specificity at all, and an ID rule beats them absolutely — no number of\r\n    // ':root' prefixes can outrank (1,0,0). Measured on stackoverflow.com:\r\n    //     a.bar-sm ....................... border-radius 4px   (site .class wins)\r\n    //     h1.fs-headline1 ................ font-size 27px      (site .class wins)\r\n    //     h2.fs-body2 .................... font-size 15px\r\n    //     #onetrust-banner-sdk ........... box-shadow present  (site #id wins)\r\n    // Inline '!important' is the one declaration that outranks every author rule\r\n    // regardless of selector, and that is exactly what setImp writes. So these\r\n    // three invariants are re-asserted here whenever the computed value actually\r\n    // disagrees. The check is nearly free — 'cs' is already resolved, this is three\r\n    // more property reads — and the write is skipped entirely when the CSS layer\r\n    // already won, which is the overwhelming majority of elements (14 of 3362 on\r\n    // the page above).\r\n    //\r\n    // Runs BEFORE shouldSkip because these are universal invariants: a rounded\r\n    // corner or a drop shadow is just as wrong on a <button> or an <img> as\r\n    // anywhere else, and buttons are skipped by shouldSkip via closest('button').\r\n    if (cs.borderTopLeftRadius !== '0px' || cs.borderTopRightRadius !== '0px' ||\r\n      cs.borderBottomLeftRadius !== '0px' || cs.borderBottomRightRadius !== '0px') {\r\n      w.push(el, 'border-radius', '0');\r\n    }\r\n    if (cs.boxShadow && cs.boxShadow !== 'none') {\r\n      w.push(el, 'box-shadow', 'none');\r\n    }\r\n    // Type ladder, same role mapping as GLOBAL_CSS. Icon-font carriers are\r\n    // exempt for the same reason as in CSS: their font-size IS their glyph size.\r\n    const fs = cs.fontSize;\r\n    if (fs && !SIZE_ALLOWED.has(fs) && !isIconish(el)) {\r\n      w.push(el, 'font-size', LADDER[(el.tagName || '').toUpperCase()] || '12px');\r\n    }\r\n\r\n    if (shouldSkip(el)) {\r\n      // Controls and their contents are deliberately kept out of the generic\r\n      // repainter so our bevels and labels survive (that is what the\r\n      // closest('button') skip is for). But CSS alone cannot defend them: a site\r\n      // rule with ID specificity and !important beats our button rule outright.\r\n      // Measured on stackoverflow.com's cookie banner —\r\n      //     #onetrust-consent-sdk #onetrust-accept-btn-handler\r\n      //         { background: var(--black-600) !important; color: #fff !important }\r\n      // scores (2,0,0) against our 'button { … !important }' at (0,0,1), and\r\n      //     #onetrust-banner-sdk * { color: var(--black-600) !important }\r\n      // at (1,0,0) beats every universal colour rule we have. The result was\r\n      // near-black text on near-black surfaces inside the banner, on elements the\r\n      // repainter had explicitly excluded.\r\n      //\r\n      // So: clamp, but only what is PROVABLY off-palette. A correctly themed\r\n      // control already computes to a palette value and is skipped here, so this\r\n      // cannot flatten our own bevel colours or relabel button internals — which\r\n      // is exactly the regression the skip exists to prevent.\r\n      if (el.closest && el.closest('button')) {\r\n        if (cs.color && !PALETTE_RGB.has(cs.color)) {\r\n          w.push(el, 'color', T.textPrimary);\r\n        }\r\n        const cbg = parseRGB(cs.backgroundColor);\r\n        if (cbg && cbg.a > 0.3 && !PALETTE_RGB.has(cs.backgroundColor)) {\r\n          w.push(el, 'background-color', isIconish(el) ? T.textPrimary : T.surfaceRaised);\r\n        }\r\n      }\r\n      return;\r\n    }\r\n\r\n    el.removeAttribute('background');\r\n    el.removeAttribute('bgcolor');\r\n\r\n    // Checkbox/radio: only force native appearance on a REAL, visible control\r\n    // (the confirmed invisible-checked-state bug). Skip entirely for the\r\n    // hidden-proxy pattern (opacity:0 / near-zero size / clipped) that custom\r\n    // switch components rely on — see the CSS comment above for why.\r\n    const tagUC = (el.tagName || '').toUpperCase();\r\n    if (tagUC === 'INPUT') {\r\n      const inputType = (el.type || '').toLowerCase();\r\n      if (inputType === 'checkbox' || inputType === 'radio') {\r\n        // opacity is the ONLY reliable signal — every accessible custom-switch\r\n        // technique uses it (keyboard/screen-reader focus requires the real\r\n        // input stay hit-testable, ruling out display:none). Size is NOT a\r\n        // reliable signal: a checkbox with appearance:none and no explicit\r\n        // width/height collapses to 0x0 in Chromium regardless of whether the\r\n        // site intentionally hid it — a live test confirmed a genuinely\r\n        // BROKEN, unstyled real checkbox (the original government-form bug\r\n        // shape) also measures 0x0, so a size check produces false positives\r\n        // that silently reintroduce that exact bug.\r\n        const hiddenProxy = parseFloat(cs.opacity) < 0.05;\r\n        if (!hiddenProxy) {\r\n          w.push(el, 'appearance', 'auto', el, '-webkit-appearance', 'auto');\r\n        }\r\n        return;\r\n      }\r\n    }\r\n\r\n    // UI.md law 2: zero gradients. Pre-1.4.0 this only killed LIGHT gradients,\r\n    // which left every dark-themed site's own coloured gradients intact — and a\r\n    // gradient is the most identity-carrying surface treatment there is, so\r\n    // leaving them meant sites still looked like themselves. Now ALL gradient\r\n    // functions go, whatever their hue.\r\n    //\r\n    // Only gradient FUNCTIONS, never url(): a huge number of sites still draw\r\n    // their icons as background-image sprites, and killing url() backgrounds\r\n    // deletes those icons outright. This is why the kill lives in JS at all — CSS\r\n    // cannot say \"background-image: none, but only if it is a gradient\".\r\n    //\r\n    // progress/meter/slider are exempt: their fill IS a gradient on many sites,\r\n    // and flattening it leaves a progress bar that cannot show progress — which\r\n    // UI.md itself wants preserved (\"long work reports progress in text\").\r\n    const bgImg = cs.backgroundImage;\r\n    if (bgImg && bgImg !== 'none' && /(^|\\s|,)(linear|radial|conic|repeating-linear|repeating-radial|repeating-conic)-gradient\\(/i.test(bgImg)) {\r\n      const tagG = (el.tagName || '').toUpperCase();\r\n      const roleG = el.getAttribute ? el.getAttribute('role') : null;\r\n      if (tagG !== 'PROGRESS' && tagG !== 'METER' && roleG !== 'progressbar' && roleG !== 'slider') {\r\n        w.push(el, 'background-image', 'none');\r\n      }\r\n    }\r\n\r\n    // PAGE-SIZED PHOTO BACKDROPS.\r\n    // url() backgrounds are deliberately kept (see above): on most elements they\r\n    // are icons, and killing them leaves invisible buttons. But at page scale the\r\n    // same rule is what left steamcommunity.com with its neon profile artwork\r\n    // blazing down both sides of a themed column -- the site paints a photo on a\r\n    // full-bleed div, our surfaces go brown around it, and the result is the\r\n    // screenshot the user sent.\r\n    //\r\n    // Size is the discriminator, and it is a safe one: nothing that is an icon is\r\n    // 70% of the viewport in BOTH dimensions.\r\n    //\r\n    // But getBoundingClientRect FORCES LAYOUT, and this whole file exists in its\r\n    // current shape because layout thrash once burned 94% of the main thread\r\n    // (ADR-004, and the sweep-rate hot loop in ADR-006). \"Only when a url() is\r\n    // present\" is not a tight enough guard on its own: an icon-sprite-heavy page\r\n    // has hundreds of those. So the measurement is gated behind a pure DOM-shape\r\n    // test first -- a page-level backdrop is always near the top of the tree,\r\n    // never buried twelve divs deep -- which costs no layout at all and leaves a\r\n    // handful of candidates per page.\r\n    if (bgImg && bgImg !== 'none' && /url\\(/i.test(bgImg)) {\r\n      let depth = 0, p = el;\r\n      while (p && p !== document.body && p !== document.documentElement && depth < 5) { p = p.parentElement; depth++; }\r\n      if (depth < 5) {\r\n        const r = el.getBoundingClientRect();\r\n        if (r.width > innerWidth * 0.7 && r.height > innerHeight * 0.7) {\r\n          w.push(el, 'background-image', 'none');\r\n        }\r\n      }\r\n    }\r\n\r\n    // 🚨 FLOATING SURFACES ARE MEASURED, NOT NAMED 🚨\r\n    // GLOBAL_CSS re-solidifies popovers off a list of NAMES -- role=\"menu\",\r\n    // [class*=\"popup\" i], [class*=\"dropdown\" i], the radix and floating-ui portal\r\n    // attributes -- because the surface-flattening wipe above would otherwise leave\r\n    // them see-through with the page behind them showing through. That list has\r\n    // missed the same app twice now (E-381, E-407): Claude's popovers carry none of\r\n    // those markers.\r\n    //\r\n    // Adding more names does not fix a name list, it postpones it. Every entry is\r\n    // one library's vocabulary, and an app that renames a component or swaps its\r\n    // popover library drops off the list at its next release with nothing to show\r\n    // for it -- no error, no failing gate, just a hole in the theme that the user\r\n    // finds. So the test below asks what a popover IS, in terms the layout engine\r\n    // answers and a rename cannot change: out of flow, big enough to read, and\r\n    // actually covering content it does not own. The same test is part of the\r\n    // repainter block below, which build-desktop.js extracts (REPAINTER\r\n    // START/END) and ships inside the Electron shim; there it is the whole\r\n    // mechanism -- FLOAT_FIX was folded into the repainter and no longer exists\r\n    // as a separate patch.\r\n    //\r\n    // The last of the three replaced an \"explicit z-index, not auto\" test that\r\n    // shipped in the first pass and was wrong on the first app it met: Claude's\r\n    // Settings panel is role=\"dialog\", position: fixed, 606x720 over a 638x1079\r\n    // window, and z-index: auto. It stacks by paint order, which is ordinary.\r\n    // Requiring a number was requiring a habit, and a habit is a name in disguise.\r\n    if (cs.position === 'fixed' || cs.position === 'absolute') {\r\n      // Free checks first, all off the computed style already read above.\r\n      // pointer-events:none means a scrim or a measurement probe, never a panel.\r\n      // COST GATE, AND IT IS NOT OPTIONAL. Everything below this line forces\r\n      // layout -- a rect read, then a hit test -- and the first version of this\r\n      // block ran both for EVERY out-of-flow element on every pass, then took\r\n      // data-w95-done OFF the small ones so they were measured again forever.\r\n      // On a page with hundreds of absolutely-positioned icons that is a\r\n      // permanent hot loop: reported as the CPU pinned at idle on chatgpt.com,\r\n      // and it is exactly the thrash ADR-004/ADR-006 exist to prevent.\r\n      // A panel always has children, and childElementCount costs nothing.\r\n      if (el.childElementCount > 0 &&\r\n        cs.pointerEvents !== 'none' && cs.visibility !== 'hidden' && cs.opacity !== '0') {\r\n        // Layout reads start here, and only for the handful of elements that got\r\n        // this far -- the ordering is the ADR-004/ADR-006 discipline, same as the\r\n        // page-backdrop test above.\r\n        const r = el.getBoundingClientRect();\r\n        // Closed, or the zero-size wrapper that HOSTS the panel: nothing to do.\r\n        // It is NOT re-dirtied here. A popover is mounted closed and opened by a\r\n        // style or class flip, and both are in the observer's attributeFilter --\r\n        // so the open lands as a mutation, which clears data-w95-done and brings\r\n        // the element back through here already measuring its real size. Marking\r\n        // it dirty on every pass instead bought exactly nothing and cost a\r\n        // forced layout per element per sweep, forever.\r\n        // Covers the whole viewport: never solidified, that would black out the\r\n        // page -- but never ignored either. A backdrop that TAKES POINTER EVENTS\r\n        // owns the window, and the wipe erases the dim it announces itself with.\r\n        // An invisible modal still eats every click, which is how CodeNomad's tabs\r\n        // stopped responding. Give the dim back, translucent, so the page stays\r\n        // legible under it. No pointer events or no explicit stacking order means\r\n        // scenery rather than a modal, and scenery is left alone.\r\n        if (r.width > innerWidth * 0.92 && r.height > innerHeight * 0.92) {\r\n          if (cs.zIndex && cs.zIndex !== 'auto') {\r\n            w.push(el, 'background-color', 'color-mix(in srgb, ' + T.background + ' 55%, transparent)',\r\n              el, 'background-image', 'none');\r\n          }\r\n        } else if (r.width >= 40 && r.height >= 24) {\r\n          // The hit test decides. Everything above admits far too much: if the\r\n          // paint stack under this element's own centre holds nothing but its own\r\n          // ancestors, it is an adornment inside its own card and inheriting the\r\n          // surface is correct. Anything foreign under it means it covers content\r\n          // it does not own, which is what floating means.\r\n          // STATE COLOURS ARE NOT REPAINTED, AND THAT IS MEASURED TOO. The\r\n          // working/waiting/done indicators carry their whole meaning in a\r\n          // background colour, which is why the wipe already excludes them. That\r\n          // exclusion is what lets this be a measurement instead of a second name\r\n          // list: after the wipe, a surface that needs solidifying is transparent\r\n          // BY DEFINITION, so anything still holding a colour is holding it on\r\n          // purpose. A condition, not an early return -- an element that keeps its\r\n          // own colour still needs the rest of process(): contrast, borders, radius.\r\n          const ownBg = parseRGB(cs.backgroundColor);\r\n          const cx = Math.min(Math.max(r.left + r.width / 2, 1), innerWidth - 1);\r\n          const cy = Math.min(Math.max(r.top + r.height / 2, 1), innerHeight - 1);\r\n          let stack = null;\r\n          if (!(ownBg && ownBg.a > 0.08)) {\r\n            try { stack = document.elementsFromPoint(cx, cy); } catch (e) { }\r\n          }\r\n          const at = stack ? stack.indexOf(el) : -1;\r\n          // MEDIA, not just video/canvas: an img, picture or inline svg is\r\n          // artwork this surface does not own, and painting an opaque\r\n          // surfaceRaised panel plus a bevel over it hides the image. Hero\r\n          // badges, carousel captions and avatar overlays are the common case.\r\n          const MEDIA = 'video, audio, canvas, img, picture, svg';\r\n          let isOverMediaOrCanvas = false;\r\n          for (let k = at + 1; at >= 0 && k < stack.length; k++) {\r\n            const u = stack[k];\r\n            if (u.tagName === 'VIDEO' || u.tagName === 'AUDIO' || u.tagName === 'CANVAS' ||\r\n              u.tagName === 'IMG' || u.tagName === 'PICTURE' || u.tagName === 'SVG' ||\r\n              (u.closest && u.closest(MEDIA)) ||\r\n              (u.querySelector && u.querySelector(MEDIA))) {\r\n              isOverMediaOrCanvas = true;\r\n              break;\r\n            }\r\n          }\r\n          if (!isOverMediaOrCanvas) {\r\n            for (let k = at + 1; at >= 0 && k < stack.length; k++) {\r\n              const under = stack[k];\r\n              if (under === document.body || under === document.documentElement) continue;\r\n              if (under.contains(el)) continue;\r\n              // Internal card/post layers (stretched links, click-catchers, card overlays)\r\n              // share an ancestor card/post/article with under: solidifying them obscures the card text.\r\n              const elComp = el.closest && el.closest('article, [class*=\"card\" i], [class*=\"post\" i], [class*=\"item\" i], shreddit-post');\r\n              const underComp = under.closest && under.closest('article, [class*=\"card\" i], [class*=\"post\" i], [class*=\"item\" i], shreddit-post');\r\n              if (elComp && underComp && elComp === underComp) continue;\r\n              if (el.tagName === 'A' ||\r\n                (el.matches && el.matches('[class*=\"inset-0\" i], [class*=\"stretched-link\" i], [class*=\"cover-link\" i]'))) {\r\n                continue;\r\n              }\r\n              w.push(el, 'background-color', T.surfaceRaised,\r\n                el, 'background-image', 'none',\r\n                el, 'color', T.textPrimary,\r\n                el, 'border-width', '2px',\r\n                el, 'border-style', 'solid',\r\n                el, 'border-color', T.bevelLight + ' ' + T.borderDark + ' ' + T.borderDark + ' ' + T.bevelLight,\r\n                el, 'box-shadow', 'none',\r\n                // The bevel is added to a box the site already sized; absorb it.\r\n                el, 'box-sizing', 'border-box');\r\n              break;\r\n            }\r\n          }\r\n        }\r\n      }\r\n    }\r\n\r\n    // 🚨 NEVER RE-GRADE A COLOUR THAT IS ALREADY OURS 🚨\r\n    // The repainter classifies by luminance, and our own tokens have luminances\r\n    // that land in its buckets: --backgroundSoft #1E1408 (lum 0.0088) and\r\n    // --surfaceRaised #362812 (lum 0.0234) both fall in the \"< 0.05\" bucket and\r\n    // were being re-graded to --surface on every pass. Caught live on wikipedia\r\n    // the moment the dark band was widened: body went from #1E1408 to #2A1C0A,\r\n    // and dialogs / th / hovercards would have drifted the same way, so the whole\r\n    // surface hierarchy would slowly collapse onto one shade. A palette value is\r\n    // by definition already correct — leave it alone.\r\n    const bgColor = cs.backgroundColor;\r\n    if (bgColor && bgColor !== 'transparent' && !PALETTE_RGB.has(bgColor)) {\r\n      const bg = parseRGB(bgColor);\r\n      // ZCode's usage popup binds its quota-bar fills INLINE to the app's own\r\n      // chart token: style=\"background-color: var(--color-usage-chart-1)\".\r\n      // Re-grading those would do two harms at once: overwrite the var()\r\n      // reference in the style ATTRIBUTE with a resolved literal (destroying\r\n      // the exact substring the GLOBAL_CSS \"5 hours\" label rule anchors on, so\r\n      // the label would dim itself again after the next sweep and re-orange on\r\n      // every React remount), and flatten the three quota bars into one\r\n      // palette shade, killing the per-column distinction the popup exists\r\n      // for. The token family is scoped, not a blanket var() exemption, so\r\n      // nothing else on any other site changes behaviour.\r\n      if (!(bg && el.style && /var\\(--color-usage-chart-/i.test(el.style.backgroundColor || ''))) {\r\n        if (bg && bg.a > 0.08) {\r\n          const L = elev(lum(bg));\r\n          const spread = Math.max(bg.r, bg.g, bg.b) - Math.min(bg.r, bg.g, bg.b);\r\n          const grayish = spread <= 24;\r\n          let repaint = null;\r\n          if (L > 0.45) {\r\n            // Flashbang surface — the far end of our own polarity, so on the golden\r\n            // palette this is literally the old \"light surface\" branch and on a light\r\n            // palette it is the site's dark chrome. Low-alpha tints go fully transparent\r\n            // (the \"gray rectangle blocks\"), neutral solids go dark brown, and\r\n            // saturated light tints (GitHub diff green/red, warning yellows,\r\n            // highlight rows) snap to the semantic token they meant.\r\n            if (bg.a <= 0.35) repaint = 'transparent';\r\n            else if (grayish) repaint = T.backgroundSoft;\r\n            else repaint = semanticToken(bg);\r\n          } else if (L >= 0.004) {\r\n            // DARK SURFACES. Two gaps used to let a site keep its own dark palette\r\n            // here, both measured on amazon.com:\r\n            //   #nav-belt  #131921  spread 14, lum 0.0094 — grayish, but the old\r\n            //     \"near-black is left alone\" floor was 0.015, so it survived.\r\n            //   #nav-main  #232f3e  spread 27, lum 0.0274 — over the old grayish\r\n            //     cutoff of 24 but under the saturated cutoff of 60, so it fell\r\n            //     through BOTH branches and was never touched at all.\r\n            // A dark navy chrome bar is a surface, not an accent, so the neutral\r\n            // band is widened to spread <= 60 and the two branches are merged:\r\n            // anything genuinely saturated (> 60) still goes to a semantic token,\r\n            // everything else joins the vintage brown scale.\r\n            //\r\n            // The floor drops from 0.015 to 0.004, which still leaves true black\r\n            // alone — video players and modal scrims sit at or near lum 0 — while\r\n            // catching real chrome like #131921.\r\n            repaint = spread > 60\r\n              ? semanticToken(bg)\r\n              : (L >= 0.13 ? T.surfaceAlt : L >= 0.05 ? T.surfaceRaised : T.surface);\r\n          }\r\n          if (repaint) {\r\n            w.push(el, 'background', repaint, el, 'background-color', repaint, el, 'background-image', 'none');\r\n          }\r\n        }\r\n      }\r\n    }\r\n\r\n    // Same guard for text: --textSecondary #B09558 has a channel spread of 88, so\r\n    // the \"not grayish\" branch would have flattened every secondary label to\r\n    // --textPrimary on the next pass. Palette in, palette out, untouched.\r\n    const fgColor = cs.color;\r\n    if (fgColor && !PALETTE_RGB.has(fgColor)) {\r\n      const fg = parseRGB(fgColor);\r\n      if (fg && fg.a > 0.1) {\r\n        // Contrast is measured against the ACTUAL backdrop this theme paints, not\r\n        // against a constant. It used to read `const darkBg = 0.008` with the\r\n        // comment \"luminance of #1E1408\" — correct, and correct only for golden:\r\n        // on a light palette that constant claims every dark text colour is\r\n        // perfectly readable, so the whole 4.5:1 branch below stops firing exactly\r\n        // where it is needed most.\r\n        const rawFgLum = lum(fg);\r\n        const fgLum = elev(rawFgLum);\r\n        const cr = contrast(rawFgLum, BG_SOFT_LUM);\r\n        const grayish = Math.max(fg.r, fg.g, fg.b) - Math.min(fg.r, fg.g, fg.b) <= 40;\r\n\r\n        if (el.closest && el.closest('a')) {\r\n          // Anything inside a link takes the link colour when it is unreadable,\r\n          // washed out, OR simply not one of ours — the last clause is iron law 5\r\n          // and it was missing. Measured on amazon.com: span#nav-cart-count kept\r\n          // #f08804 and span.navFooterDescText kept #999999, because both are\r\n          // legible enough (7.1:1 and 6.3:1) that the first two tests passed them\r\n          // through. Legible is not the same as on-palette.\r\n          if (cr < 4.5 || (fgLum > 0.4 && grayish) || !PALETTE_RGB.has(fgColor)) {\r\n            w.push(el, 'color', T.link);\r\n          }\r\n        } else {\r\n          if (cr < 4.5) {\r\n            w.push(el, 'color', T.textPrimary);\r\n          } else if (grayish) {\r\n            if (fgLum > 0.4) w.push(el, 'color', T.textPrimary);\r\n            else if (fgLum > 0.15) w.push(el, 'color', T.textSecondary);\r\n          } else {\r\n            // Legible but SATURATED text — a site's own coloured heading, tag or\r\n            // status label. Left alone pre-1.4.0, which is another way sites kept\r\n            // their own voice, so it gets normalised too: to --textPrimary.\r\n            //\r\n            // Deliberately NOT to semanticToken() like the background path does.\r\n            // --success/--warning/--danger are BACKGROUND tokens; as text on\r\n            // --backgroundSoft they measure 2.6:1 / 3.4:1 / 1.8:1, all far under\r\n            // the WCAG AA 4.5:1 UI.md also demands. Snapping coloured text onto\r\n            // them would trade one iron law for a worse violation of the\r\n            // accessibility floor — and UI.md settles that tie itself: \"error\r\n            // text must be readable without color alone.\"\r\n            w.push(el, 'color', T.textPrimary);\r\n          }\r\n        }\r\n      }\r\n    }\r\n\r\n    // Light/white border lines (table rules, row separators, panel edges) →\r\n    // vintage brown, per side. Fields keep their golden bevels (buttons are\r\n    // already excluded by shouldSkip). Saturated colored borders (e.g. red\r\n    // error outlines) are left alone via the grayish check.\r\n    const tg = (el.tagName || '').toUpperCase();\r\n    if (!/^(INPUT|TEXTAREA|SELECT|BUTTON)$/.test(tg)) {\r\n      const SIDES = ['Top', 'Right', 'Bottom', 'Left'];\r\n      for (let i = 0; i < 4; i++) {\r\n        const s = SIDES[i];\r\n        if (cs['border' + s + 'Width'] === '0px' || cs['border' + s + 'Style'] === 'none') continue;\r\n        const bc = parseRGB(cs['border' + s + 'Color']);\r\n        if (!bc || bc.a <= 0.1) continue;\r\n        const grayish = Math.max(bc.r, bc.g, bc.b) - Math.min(bc.r, bc.g, bc.b) <= 60;\r\n        if (grayish && elev(lum(bc)) > 0.18) {\r\n          w.push(el, 'border-' + s.toLowerCase() + '-color', T.surfaceRaised);\r\n        }\r\n      }\r\n    }\r\n  }\r\n\r\n  function shouldSkip(el) {\r\n    const tag = (el.tagName || '').toUpperCase();\r\n    if (TAG_SKIP.test(tag)) return true;\r\n    if (el.namespaceURI === 'http://www.w3.org/2000/svg' && tag !== 'SVG') return true;\r\n    if (tag === 'INPUT') {\r\n      const t = (el.type || '').toLowerCase();\r\n      // Natively-rendered controls: repainting them hides the checked state.\r\n      // checkbox/radio are handled specially in process() (need computed\r\n      // style to tell a real control from a hidden custom-switch proxy).\r\n      if (t === 'range' || t === 'color' || t === 'file') return true;\r\n    }\r\n    if (el.closest && el.closest('button')) return true;\r\n    if (el.closest && el.closest('video, audio')) return true;\r\n    // CSS above owns CodeNomad's native semantic state dot. Repainting it would\r\n    // erase the working/idle distinction after the first mutation batch.\r\n    try { if (el.matches && el.matches('.status-indicator.session-status > .status-dot')) return true; } catch (e) { }\r\n    try { if (el.closest && el.closest(JS_SKIP_SELECTOR)) return true; } catch (e) { }\r\n    return false;\r\n  }\r\n\r\n  // Mutations accumulate in a queue with a fixed 60ms flush. The previous\r\n  // clearTimeout+reset pattern silently DROPPED every batch except the last\r\n  // one (each reset discarded the prior closure's mutations) and could starve\r\n  // forever on continuously-mutating pages.\r\n  let debounceTimer = null;\r\n  let pendingMuts = [];\r\n  const attrCooldown = new WeakMap(); // element -> last attribute-triggered process time\r\n\r\n  // Generic circuit breaker for sites not on the known-host list. A universal\r\n  // userscript cannot predict every future SPA, so it must fail cold rather than\r\n  // turn a new framework's mutation storm into a space heater. Once tripped, the\r\n  // CSS theme remains active but all JavaScript repaint work stops for this page.\r\n  const MUTATION_WINDOW_MS = 2000;\r\n  const MUTATION_RECORD_LIMIT = 10000;\r\n  const MUTATION_WORK_LIMIT_MS = 600;\r\n  const ADDED_NODE_BUDGET = 500;\r\n  // PERF-001 (SRC-063): the attribute lane's per-slice bound and its retained\r\n  // state bound. process() reaches window.getComputedStyle before most semantic\r\n  // skipping, so a legal 10,000-record window used to mean 10,000\r\n  // computed-style reads in ONE task, with the 600 ms breaker only able to\r\n  // react after the task had already monopolised the main thread.\r\n  const ATTRIBUTE_PROCESS_BUDGET = 250;\r\n  const ATTRIBUTE_PENDING_CAP = 2000;\r\n  const ATTRIBUTE_SLICE_MS = 0;\r\n  // Attribute targets awaiting a repair. Keyed BY ELEMENT, which is the collapse:\r\n  // process() reads current final DOM/computed state, never historical mutation\r\n  // values, so 10,000 records for one target are one repair, and 10,000 records\r\n  // for 10,000 targets are 10,000 repairs -- bounded per slice below.\r\n  const attributePending = new Set();\r\n  let attributeIter = null;\r\n  let attributeLaneActive = false;\r\n  let attributeOverflowed = false;\r\n  let mutationWindowStart = performance.now();\r\n  let mutationRecords = 0;\r\n  let mutationWorkMs = 0;\r\n  let repainterSuspended = CSS_ONLY_MODE;\r\n\r\n  function resetMutationWindow(now) {\r\n    mutationWindowStart = now;\r\n    mutationRecords = 0;\r\n    mutationWorkMs = 0;\r\n  }\r\n\r\n  function suspendRepainter(reason) {\r\n    if (repainterSuspended) return;\r\n    repainterSuspended = true;\r\n    try { mainObserver.disconnect(); } catch (e) { }\r\n    try { shadowObserver.disconnect(); } catch (e) { }\r\n    // PERF-003 (SRC-063): a prune that was mid-migration when the lane died\r\n    // still owns a staged observer holding every survivor it had filled in so\r\n    // far. Disconnecting only the outgoing generation would leave that one\r\n    // registered -- and holding those ShadowRoots -- for the rest of the page's\r\n    // life, which is the exact leak this ticket is about.\r\n    if (shadowStagedObserver) {\r\n      try { shadowStagedObserver.takeRecords(); } catch (e) { }\r\n      try { shadowStagedObserver.disconnect(); } catch (e) { }\r\n      shadowStagedObserver = null;\r\n    }\r\n    shadowMigrationActive = false;\r\n    shadowPrunePhase = 0;\r\n    shadowPruneScanIter = null;\r\n    shadowPruneStageIter = null;\r\n    shadowPruneRemovedAny = false;\r\n    shadowPruneQueued = false;\r\n    // The hover-surgery registry is the same class of owner -- handles over\r\n    // CSSOM rules nothing will ever restore once the lane is dead.\r\n    try { hoverStrippedRules.length = 0; } catch (e) { }\r\n    // PERF-001 (SRC-063): the attribute lane's retained targets are the same\r\n    // class of owner -- a live Set of elements nothing will ever drain once the\r\n    // lane is dead. Suspension is permanent, so release them here.\r\n    attributeLaneActive = false;\r\n    attributeIter = null;\r\n    attributeOverflowed = false;\r\n    try { attributePending.clear(); } catch (e) { }\r\n    if (debounceTimer) { clearTimeout(debounceTimer); debounceTimer = null; }\r\n    if (sweepTimer) { clearTimeout(sweepTimer); sweepTimer = null; sweepPlannedAt = 0; }\r\n    pendingMuts.length = 0;\r\n    forcePassesOwed = 0;\r\n    // PERF-007 (SRC-002): suspension is permanent for the page. Without a\r\n    // future runSweeper to prune, every still-tracked piercedRoots entry would\r\n    // keep its shadow subtree and style objects alive forever. Drop the\r\n    // registry now so detached DOM can be GC'd; the live roots keep whatever\r\n    // was already injected into them.\r\n    try { piercedRoots.clear(); } catch (e) { }\r\n    try { forceRootCursors.clear(); } catch (e) { }\r\n    // SRC-006:R010: the lap workset is the same class of retention (a live\r\n    // array of roots nothing will ever drain once the lane is dead).\r\n    forceLapWorkset = null;\r\n    forceLapIndex = 0;\r\n    forceLapRemaining = 0;\r\n    // PERF-001: the deferred debt belongs to a lap that no longer exists.\r\n    forceDeferredRoots = 0;\r\n    // PERF-003 (SRC-004): the light registry is the same class of retention --\r\n    // a Set of elements that nothing will ever drain once the lane is dead.\r\n    try { lightDirty.clear(); } catch (e) { }\r\n    forceLapActive = false;\r\n    // PERF-003 (SRC-018:R015): suspension is permanent, so it must be a COMPLETE\r\n    // scheduler-state disposal boundary. The previous cleanup missed the style\r\n    // lane's strong owners: styleLapDeferredRoots is a Set that STRONGLY owns\r\n    // ShadowRoots; activeStyleTask strongly owns its\r\n    // sheet; styleCursorRoot directly owns the current Document/ShadowRoot; and\r\n    // styleCursorRootIterator is a live iterator over them. With no future pass\r\n    // to drain or overwrite them, a page that tripped the breaker could freeze a\r\n    // large dead DOM/CSSOM retention graph for the rest of the document's life.\r\n    // WeakMap caches (sheetSeen, attrCooldown) and the already-injected theme\r\n    // stay: they do not own their keys and must keep working.\r\n    try { styleLapDeferredRoots.clear(); } catch (e) { }\r\n    activeStyleTask = null;\r\n    styleCursorRoot = null;\r\n    styleCursorRootIterator = null;\r\n    styleCursorListIndex = 0;\r\n    styleCursorSheetIndex = 0;\r\n    styleLapSeqLimit = styleRootSeq;\r\n    lightPending = false;\r\n    stylesDirty = false;\r\n    try {\r\n      document.documentElement.setAttribute('data-w95-perf', 'css-only');\r\n      document.documentElement.setAttribute('data-w95-perf-reason', reason);\r\n    } catch (e) { }\r\n  }\r\n\r\n  // ─── CORE-003: the excluded-route safety quarantine ───────────────────────\r\n  // suspendRepainter stops the machinery; it is NOT a safety boundary. The\r\n  // global styles already injected into the document, the constructable sheets\r\n  // adopted into it and into every shadow root, the thousands of inline\r\n  // !important overrides the repainter wrote, the root background/color\r\n  // override, the declarations ripped out of site hover rules, and the root\r\n  // attribute observer that re-asserts the root override are all still live and\r\n  // still theming. On an excluded route (auth, payment, challenge) that is the\r\n  // exact failure CORE-003 names, so they are removed here. Every step is\r\n  // best-effort and the whole function is idempotent: a quarantine is a safety\r\n  // action, never a reason to throw into a history hook.\r\n  function removeInjectedStyleNodes(root) {\r\n    if (!root || typeof root.querySelectorAll !== 'function') return;\r\n    const nodes = root.querySelectorAll('style[data-w95]');\r\n    for (let i = 0; i < nodes.length; i++) {\r\n      try { nodes[i].remove(); } catch (e) { }\r\n    }\r\n  }\r\n\r\n  function dropAdoptedThemeSheets(root) {\r\n    if (!root || !Array.isArray(root.adoptedStyleSheets)) return;\r\n    // Every sheet this theme builds stamps its content and/or generation on\r\n    // itself; a foreign sheet carries neither marker.\r\n    const kept = root.adoptedStyleSheets.filter((sheet) => !!sheet\r\n      && sheet.__w95Content === undefined && sheet.__w95Ver === undefined);\r\n    if (kept.length !== root.adoptedStyleSheets.length) {\r\n      try { root.adoptedStyleSheets = kept; } catch (e) { }\r\n    }\r\n    if (root.__w95Sheets) root.__w95Sheets = {};\r\n  }\r\n\r\n  function quarantineThemeStyles() {\r\n    // CORE-003: nothing republishes theme effects into this document from here on.\r\n    // A plain assignment: it cannot throw, so the fence cannot fail open.\r\n    routeQuarantined = true;\r\n    // 1. Stop the SECOND writer first. The root attribute observer repaints the\r\n    //    root overrides the moment they are missing, so removing them before it\r\n    //    is stopped would be undone by its own callback.\r\n    if (rootAttributeObserver) {\r\n      try { rootAttributeObserver.disconnect(); } catch (e) { }\r\n      rootAttributeObserver = null;\r\n    }\r\n    // 2. Undo the root background/color overrides and the root markers.\r\n    const root = document.documentElement;\r\n    if (root) {\r\n      const attrs = ['data-w95-dark', 'data-w95-theme', 'data-w95-x', 'data-w95-reddit',\r\n        'data-w95-google', 'data-w95-chatgpt', 'data-w95-done'];\r\n      for (let i = 0; i < attrs.length; i++) {\r\n        try { root.removeAttribute(attrs[i]); } catch (e) { }\r\n      }\r\n      if (rootInlineOriginals) {\r\n        try {\r\n          root.style.removeProperty('background-color');\r\n          root.style.removeProperty('color');\r\n        } catch (e) { }\r\n      }\r\n    }\r\n    // 3. The injected stylesheets: the DOM copies and the adopted sheets.\r\n    removeInjectedStyleNodes(document);\r\n    dropAdoptedThemeSheets(document);\r\n    // 4. Every shadow root this theme registered, including the ones whose WeakRef\r\n    //    entry has not been collected yet (a collected one is already gone).\r\n    try {\r\n      const roots = Element.prototype.__wintageShadowRoots;\r\n      if (roots && typeof roots.length === 'number') {\r\n        for (let i = 0; i < roots.length; i++) {\r\n          const entry = roots[i];\r\n          const shadow = entry && typeof entry === 'object' && typeof entry.deref === 'function'\r\n            ? entry.deref()\r\n            : entry;\r\n          if (!shadow) continue;\r\n          removeInjectedStyleNodes(shadow);\r\n          dropAdoptedThemeSheets(shadow);\r\n        }\r\n      }\r\n    } catch (e) { }\r\n    // 5. Stylesheet mutations: put the stripped hover declarations back.\r\n    restoreHoverRules();\r\n    // 6. Inline overrides. Restore exactly what this theme wrote, nothing else:\r\n    //    the recorded pre-write value goes back on the property (or the property\r\n    //    is removed when there was none), so a site's own declaration on the same\r\n    //    element -- including a site !important on a property this theme also\r\n    //    wrote -- survives the quarantine untouched. Stripping every\r\n    //    !important declaration instead would delete foreign site state, which is\r\n    //    the opposite of what an excluded-route safety boundary may do.\r\n    if (typeof document.querySelectorAll === 'function') {\r\n      const painted = document.querySelectorAll('[data-w95-done]');\r\n      for (let i = 0; i < painted.length; i++) {\r\n        try {\r\n          const el = painted[i];\r\n          const st = el.style;\r\n          const rec = ownedInlineOriginals.get(el);\r\n          if (rec && st && typeof st.setProperty === 'function') {\r\n            for (const name in rec) {\r\n              const o = rec[name];\r\n              if (o.value === '') {\r\n                try { st.removeProperty(name); } catch (e) { }\r\n              } else {\r\n                try { st.setProperty(name, o.value, o.priority || ''); } catch (e) { }\r\n              }\r\n            }\r\n            ownedInlineOriginals.delete(el);\r\n          }\r\n          el.removeAttribute('data-w95-done');\r\n        } catch (e) { }\r\n      }\r\n    }\r\n    // 7. The perf attributes the suspension wrote describe a live theme lane;\r\n    //    on an excluded route nothing is repainting.\r\n    if (root) {\r\n      // paintRoot runs before ordinary repainter bookkeeping and <html> need\r\n      // not appear in the painted-element query. Restore its initial values\r\n      // after that query so a later recording cannot overwrite them.\r\n      if (rootInlineOriginals) {\r\n        for (const name of ['background-color', 'color']) {\r\n          const original = rootInlineOriginals[name];\r\n          try {\r\n            if (original.value) root.style.setProperty(name, original.value, original.priority);\r\n            else root.style.removeProperty(name);\r\n          } catch (e) { }\r\n        }\r\n        rootInlineOriginals = null;\r\n      }\r\n      try { root.removeAttribute('data-w95-perf'); } catch (e) { }\r\n      try { root.removeAttribute('data-w95-perf-reason'); } catch (e) { }\r\n    }\r\n  }\r\n\r\n  function noteMutationPressure(records) {\r\n    const now = performance.now();\r\n    if (now - mutationWindowStart >= MUTATION_WINDOW_MS) resetMutationWindow(now);\r\n    mutationRecords += records;\r\n    if (mutationRecords > MUTATION_RECORD_LIMIT || mutationWorkMs > MUTATION_WORK_LIMIT_MS) {\r\n      suspendRepainter(mutationRecords > MUTATION_RECORD_LIMIT ? 'mutation-rate' : 'mutation-work');\r\n      return true;\r\n    }\r\n    return false;\r\n  }\r\n\r\n  function addWorkPressure(ms, reason) {\r\n    const now = performance.now();\r\n    if (now - mutationWindowStart >= MUTATION_WINDOW_MS) resetMutationWindow(now);\r\n    mutationWorkMs += ms;\r\n    if (mutationWorkMs > MUTATION_WORK_LIMIT_MS) suspendRepainter(reason);\r\n  }\r\n\r\n  // PERF-004 (SRC-004): detached shadow roots had TWO retention owners and only\r\n  // one of them was ever released. runSweeper pruned piercedRoots and\r\n  // forceRootCursors, but MutationObserver has no per-target unobserve, so the\r\n  // detached root stayed a registered target of the shared shadowObserver until\r\n  // the whole observer was disconnected -- i.e. until suspendRepainter or the\r\n  // page died. Worse, onMutations handled no removedNodes at all, so a quiet\r\n  // removal scheduled no cleanup: a measured removal-only batch produced zero\r\n  // force requests and zero light requests, and the registry only shrank when\r\n  // some unrelated work happened to run a sweep.\r\n  //\r\n  // The repair is deliberately NOT a walk of every removed subtree (that costs\r\n  // O(removed nodes) on exactly the batches that are already large). It scans\r\n  // piercedRoots -- bounded by how many roots we pierced -- drops the\r\n  // disconnected ones, and if any went away rebuilds the shared observer's\r\n  // registration from the survivors. Pending records are taken before the\r\n  // disconnect and handed straight back to onMutations, so a legitimate shadow\r\n  // mutation delivered in the same tick is not dropped.\r\n  // PERF-003 (SRC-063): the prune above was ONE synchronous task over the whole\r\n  // registry -- and because MutationObserver has no per-target unobserve, a\r\n  // single detached root made it disconnect the shared observer and re-observe\r\n  // every survivor. Measured: 50,000 roots + one dead root = 50,000\r\n  // connectivity checks + 49,999 observe() calls in a single invocation, and\r\n  // none of it was fed to addWorkPressure. The main force/style lanes are\r\n  // root-budgeted; this side lane was not.\r\n  //\r\n  // It is now a resumable state machine. Each task touches at most\r\n  // SHADOW_PRUNE_ROOT_BUDGET roots and re-arms itself:\r\n  //   SCAN  -- a persistent Set iterator finds detached roots across many tasks\r\n  //   STAGE -- a REPLACEMENT observer is filled in while the outgoing one stays\r\n  //            live, so no root is ever unobserved\r\n  //   SWAP  -- takeRecords, hand the outgoing observer over, disconnect it\r\n  //\r\n  // Exactly-once delivery across the overlap is a superset argument: the\r\n  // outgoing observer has had every survivor registered since before the first\r\n  // root was staged, so anything the staged observer sees during migration is\r\n  // already in the outgoing queue. The staged observer therefore drops its\r\n  // batches while shadowMigrationActive is true, and the swap order\r\n  // (takeRecords -> repoint -> disconnect -> flag) hands each record to exactly\r\n  // one of the two: before takeRecords the outgoing queue has it, after\r\n  // disconnect() only the staged one can have it.\r\n  const SHADOW_PRUNE_ROOT_BUDGET = 512;\r\n  const SHADOW_PRUNE_STEP_MS = 0;\r\n  let shadowPruneQueued = false;\r\n  // 0 = idle, 1 = SCAN, 2 = STAGE. An explicit phase, because the two phases\r\n  // have separate cursors: without it every STAGE task re-armed a fresh SCAN\r\n  // and the cycle never advanced.\r\n  let shadowPrunePhase = 0;\r\n  let shadowPruneScanIter = null;\r\n  let shadowPruneStageIter = null;\r\n  let shadowPruneRemovedAny = false;\r\n  let shadowStagedObserver = null;\r\n  let shadowMigrationActive = false;\r\n\r\n  // Staged deliveries are duplicates for the whole migration window; see above.\r\n  function onShadowStagedMutations(records) {\r\n    if (shadowMigrationActive) return;\r\n    onMutations(records);\r\n  }\r\n\r\n  function finishShadowPrune() {\r\n    shadowPrunePhase = 0;\r\n    shadowPruneScanIter = null;\r\n    shadowPruneStageIter = null;\r\n    shadowPruneRemovedAny = false;\r\n    shadowPruneQueued = false;\r\n    if (!shadowStagedObserver) return;\r\n    shadowMigrationActive = false;\r\n    try {\r\n      shadowStagedObserver.takeRecords();\r\n      shadowStagedObserver.disconnect();\r\n    } catch (e) { }\r\n    shadowStagedObserver = null;\r\n  }\r\n\r\n  // ONE budgeted step. Returns with the cycle either finished or re-armed.\r\n  function pruneShadowRegistry() {\r\n    if (repainterSuspended) { finishShadowPrune(); return; }\r\n    const startedAt = performance.now();\r\n    if (shadowPrunePhase === 0) {\r\n      shadowPrunePhase = 1;\r\n      shadowPruneScanIter = piercedRoots.values();\r\n    }\r\n    if (shadowPrunePhase === 1) {\r\n      let scanDone = false;\r\n      for (let i = 0; i < SHADOW_PRUNE_ROOT_BUDGET; i++) {\r\n        const step = shadowPruneScanIter.next();\r\n        if (step.done) { scanDone = true; break; }\r\n        const root = step.value;\r\n        try {\r\n          if (!root.host || !root.host.isConnected) {\r\n            piercedRoots.delete(root);\r\n            forceRootCursors.delete(root);\r\n            shadowPruneRemovedAny = true;\r\n          }\r\n        } catch (e) { }\r\n      }\r\n      if (!scanDone) {\r\n        setTimeout(pruneShadowRegistry, SHADOW_PRUNE_STEP_MS);\r\n        addWorkPressure(performance.now() - startedAt, 'shadow-prune');\r\n        return;\r\n      }\r\n      shadowPruneScanIter = null;\r\n      // Nothing detached (or nothing is observed at all): the registration is\r\n      // already correct, so the observer is left completely alone.\r\n      if (!shadowPruneRemovedAny || CSS_ONLY_MODE) {\r\n        if (CSS_ONLY_MODE) noteRepaintSkipped();\r\n        finishShadowPrune(); return;\r\n      }\r\n      shadowStagedObserver = new MutationObserver(onShadowStagedMutations);\r\n      shadowMigrationActive = true;\r\n      shadowPruneStageIter = piercedRoots.values();\r\n      shadowPrunePhase = 2;\r\n    }\r\n    let stageDone = false;\r\n    for (let i = 0; i < SHADOW_PRUNE_ROOT_BUDGET; i++) {\r\n      const step = shadowPruneStageIter.next();\r\n      if (step.done) { stageDone = true; break; }\r\n      const root = step.value;\r\n      try {\r\n        // A root can detach between SCAN and STAGE. Drop it here instead of\r\n        // registering it, so the replacement never re-acquires what the scan\r\n        // just released.\r\n        if (!root.host || !root.host.isConnected) {\r\n          piercedRoots.delete(root);\r\n          forceRootCursors.delete(root);\r\n          continue;\r\n        }\r\n        shadowStagedObserver.observe(root, SHADOW_OBS_OPTS);\r\n      } catch (e) { }\r\n    }\r\n    if (!stageDone) {\r\n      setTimeout(pruneShadowRegistry, SHADOW_PRUNE_STEP_MS);\r\n      addWorkPressure(performance.now() - startedAt, 'shadow-prune');\r\n      return;\r\n    }\r\n    // SWAP. Every survivor is already on the staged observer, so the outgoing\r\n    // one can be released with no unobserved window.\r\n    shadowPruneStageIter = null;\r\n    let pending = null;\r\n    try {\r\n      pending = shadowObserver.takeRecords();\r\n      const outgoing = shadowObserver;\r\n      shadowObserver = shadowStagedObserver;\r\n      shadowStagedObserver = null;\r\n      outgoing.disconnect();\r\n      // Last: only now may the staged observer deliver on its own account.\r\n      shadowMigrationActive = false;\r\n    } catch (e) { }\r\n    try { if (pending && pending.length) onMutations(pending); } catch (e) { }\r\n    shadowPrunePhase = 0;\r\n    shadowPruneRemovedAny = false;\r\n    shadowPruneQueued = false;\r\n    addWorkPressure(performance.now() - startedAt, 'shadow-prune');\r\n  }\r\n  function requestShadowPrune() {\r\n    // shadowPruneQueued is held for the WHOLE cycle, not just the first task, so\r\n    // a burst of removal batches while a 50,000-root migration is in flight\r\n    // cannot stack up concurrent scans.\r\n    if (shadowPruneQueued || repainterSuspended || !piercedRoots.size) return;\r\n    shadowPruneQueued = true;\r\n    // Bounded, one-shot, and never a poll: only a batch that actually carried\r\n    // removals gets here.\r\n    setTimeout(pruneShadowRegistry, 250);\r\n  }\r\n\r\n  // PERF-001 (SRC-063): ONE bounded attribute slice. Called by the debounce\r\n  // batch and then re-armed by itself until attributePending is drained, so the\r\n  // batch callback's work is bounded no matter how many UNIQUE targets the\r\n  // delivery carried. Each slice owns its own write buffer and flushes it, which\r\n  // is what keeps corrections visible while the rest of the debt is still owed.\r\n  function drainAttributeSlice() {\r\n    if (!attributeLaneActive) return;\r\n    if (repainterSuspended) { finishAttributeLane(); return; }\r\n    const startedAt = performance.now();\r\n    if (attributeIter === null) attributeIter = attributePending.values();\r\n    const w = [];\r\n    let exhausted = false;\r\n    for (let i = 0; i < ATTRIBUTE_PROCESS_BUDGET; i++) {\r\n      const step = attributeIter.next();\r\n      if (step.done) { exhausted = true; break; }\r\n      const el = step.value;\r\n      try {\r\n        // Added-then-removed inside the same window: a detached element has no\r\n        // computed style worth reading and no pixels to fix. Same rule the\r\n        // added-node lane already applies; a CONNECTED target is never dropped.\r\n        if (!el || el.nodeType !== 1 || !el.isConnected) continue;\r\n        // PERF-002: the processed target leaves the pending set here, not at\r\n        // lane finish. Capacity must be consumed by UNFINISHED work only, or a\r\n        // healthy actively-draining lane fills to its cap on completed entries.\r\n        // Deleting the current key during iteration is well-defined and the\r\n        // live-iterator continuation contract is unchanged.\r\n        try { attributePending.delete(el); } catch (e) { }\r\n        // Cooldown semantics preserved verbatim, just moved off the record loop:\r\n        // carousels and virtual scrollers toggle classes many times a second, and\r\n        // during the cooldown the element is only marked dirty for the light\r\n        // sweep. Nothing time-windowed is decided from a stale record any more.\r\n        const now = Date.now();\r\n        if ((attrCooldown.get(el) || 0) + 500 > now) {\r\n          el.removeAttribute('data-w95-done');\r\n          markLightDirty(el);\r\n          requestLightSweep();\r\n        } else {\r\n          attrCooldown.set(el, now);\r\n          el.removeAttribute('data-w95-done');\r\n          process(el, false, w);\r\n        }\r\n      } catch (e) { }\r\n    }\r\n    flushWrites(w);\r\n    // PERF-001 (SRC-063): the breaker is charged PER SLICE, so a deliberately\r\n    // slow process() is caught between slices rather than after the whole batch.\r\n    addWorkPressure(performance.now() - startedAt, 'attribute-slice');\r\n    if (repainterSuspended) { finishAttributeLane(); return; }\r\n    // Budget spent with debt left: yield and resume the same cursor. Debt gone:\r\n    // release the retained targets now rather than at the next suspension.\r\n    if (!exhausted) { setTimeout(drainAttributeSlice, ATTRIBUTE_SLICE_MS); return; }\r\n    finishAttributeLane();\r\n  }\r\n\r\n  function finishAttributeLane() {\r\n    attributeLaneActive = false;\r\n    attributeIter = null;\r\n    try { attributePending.clear(); } catch (e) { }\r\n  }\r\n\r\n  function startAttributeLane() {\r\n    if (attributeLaneActive || !attributePending.size) return;\r\n    attributeLaneActive = true;\r\n    if (attributeIter === null) attributeIter = attributePending.values();\r\n    setTimeout(drainAttributeSlice, ATTRIBUTE_SLICE_MS);\r\n  }\r\n\r\n  function onMutations(mutations) {\r\n    if (repainterSuspended || noteMutationPressure(mutations.length)) return;\r\n    for (let i = 0; i < mutations.length; i++) pendingMuts.push(mutations[i]);\r\n    if (debounceTimer) return;\r\n    debounceTimer = setTimeout(() => {\r\n      debounceTimer = null;\r\n      if (repainterSuspended) { pendingMuts.length = 0; return; }\r\n      const workStarted = performance.now();\r\n      const batch = pendingMuts;\r\n      pendingMuts = [];\r\n      const w = [];\r\n      const added = [];\r\n      let styleishAdded = false;\r\n      // PERF-003 (SRC-002): a single MutationRecord's addedNodes can be tens\r\n      // of thousands of elements (framework bulk-insert / virtualised list\r\n      // mount). The 500-node budget used to be enforced only during process()\r\n      // after every element had already been pushed into the unbounded `added`\r\n      // array AND a Set built from it. Bound the collection walk itself:\r\n      // stop retaining node refs the moment ADDED_NODE_BUDGET is reached,\r\n      // mark the batch truncated, and request a deferred force reverify.\r\n      // A truncated batch with STYLE/LINK nodes (even beyond the cutoff) must\r\n      // still mark stylesDirty so the deferred sweep re-checks.\r\n      let collectionBudget = ADDED_NODE_BUDGET;\r\n      let addedTruncatedDuringCollection = false;\r\n      let addedCollected = 0;\r\n      let removalSeen = false;\r\n      for (const m of batch) {\r\n        // Class/bgcolor changes restyle existing elements (SPA hydration, lazy\r\n        // CSS-in-JS) — re-process them or they keep stale baked-in colors.\r\n        // Hover-chain elements are skipped inside process() and retried later,\r\n        // so hover class-toggles don't bake in highlight colors.\r\n        if (m.type === 'attributes') {\r\n          const t = m.target;\r\n          if (t && t.nodeType === 1) {\r\n            // Class/bgcolor changes restyle existing elements (SPA hydration, lazy\r\n            // CSS-in-JS). This record loop now costs O(1) per record: it reads\r\n            // only the tag, and defers the actual repair to the bounded\r\n            // attribute lane. Style discovery stays HERE and stays complete,\r\n            // because a STYLE/LINK target must mark stylesDirty even when the\r\n            // repair for that element is deferred or dropped.\r\n            const tag = (t.tagName || '').toUpperCase();\r\n            if (tag === 'STYLE' || (tag === 'LINK' && (t.rel || '').toLowerCase().includes('stylesheet'))) {\r\n              styleishAdded = true;\r\n            }\r\n            // PERF-001 (SRC-063): collapse BY TARGET. 10,000 class records on one\r\n            // element is one repair -- process() reads current final state, so\r\n            // the intermediate values are worthless. The Set gives that collapse\r\n            // for free and bounds retained state by ATTRIBUTE_PENDING_CAP.\r\n            // PERF-002: an element already awaiting repair is a free re-add,\r\n            // so dedup runs BEFORE the capacity test. Charging it as new work\r\n            // tripped a false overflow -- and an unnecessary force sweep -- at\r\n            // the configured capacity.\r\n            if (attributePending.has(t)) continue;\r\n            if (attributePending.size >= ATTRIBUTE_PENDING_CAP) attributeOverflowed = true;\r\n            else attributePending.add(t);\r\n          }\r\n          continue;\r\n        }\r\n        if (m.type === 'childList') {\r\n          const target = m.target;\r\n          if (target && target.nodeType === 1) {\r\n            if (target.hasAttribute && target.hasAttribute('data-w95')) continue;\r\n            const tag = (target.tagName || '').toUpperCase();\r\n            if (tag === 'STYLE' || (tag === 'LINK' && (target.rel || '').toLowerCase().includes('stylesheet'))) {\r\n              styleishAdded = true;\r\n            }\r\n          }\r\n          // PERF-004 (SRC-004): a batch that carried removals schedules ONE\r\n          // bounded shadow-registry cleanup. Only the FACT of a removal is read\r\n          // here -- never the removed nodes themselves, which is what keeps this\r\n          // O(1) per record on exactly the batches that are already large.\r\n          if (m.removedNodes && m.removedNodes.length) removalSeen = true;\r\n        }\r\n        for (let ni = 0; ni < m.addedNodes.length; ni++) {\r\n          // PERF-002 (SRC-018:R014): collection does ONLY O(1) per-node\r\n          // bookkeeping for the hard intake bound. Stylesheet discovery is\r\n          // DEFERRED to the deduplicated retained-root set below, so a nested\r\n          // batch (parser/SPA hydration reports a container AND its descendants)\r\n          // no longer runs an overlapping descendant query per collected node\r\n          // before the ancestor dedup. Measured pre-fix: 500 nested roots -> 500\r\n          // querySelector calls and 124,750 descendant visits for 500 process\r\n          // calls; the dedup reduced DOM processing but arrived after the\r\n          // quadratic selector work.\r\n          if (addedCollected >= collectionBudget) { addedTruncatedDuringCollection = true; break; }\r\n          const node = m.addedNodes[ni];\r\n          if (node.nodeType !== 1) continue;\r\n          if (node.hasAttribute && node.hasAttribute('data-w95')) continue;\r\n          added.push(node);\r\n          addedCollected++;\r\n        }\r\n      }\r\n\r\n      // De-dup the batch before touching anything (v1.3.0). The parser and SPA\r\n      // hydration routinely report a container AND its descendants as separate\r\n      // addedNodes records in the SAME batch, and the old loop walked every\r\n      // record's whole subtree — so a node covered by an ancestor's walk was\r\n      // re-read, and the code even cleared its data-w95-done first to guarantee\r\n      // the redundant pass happened. Keep only records with no added ancestor in\r\n      // this batch; walking up parentNode is O(depth), never O(batch²).\r\n      if (added.length) {\r\n        const inBatch = new Set(added);\r\n        let addedProcessed = 0;\r\n        let addedTruncated = false;\r\n        for (const node of added) {\r\n          let covered = false;\r\n          for (let p = node.parentNode; p; p = p.parentNode) {\r\n            if (inBatch.has(p)) { covered = true; break; }\r\n          }\r\n          // Added then removed again inside the same 60ms window: a detached\r\n          // element has no computed style worth reading and no pixels to fix.\r\n          if (covered || !node.isConnected) continue;\r\n          // PERF-002 (SRC-018:R014): stylesheet discovery runs ONCE per RETAINED\r\n          // top-level root, after deduplication. The root's own tag first, then\r\n          // at most ONE descendant query -- not one query per collected node\r\n          // (most of which are descendants of another retained root).\r\n          if (!styleishAdded) {\r\n            const tag = (node.tagName || '').toUpperCase();\r\n            if (tag === 'STYLE' || (tag === 'LINK' && (node.rel || '').toLowerCase().includes('stylesheet'))) {\r\n              styleishAdded = true;\r\n            } else if (node.querySelector && node.querySelector('style,link[rel*=stylesheet i]')) {\r\n              styleishAdded = true;\r\n            }\r\n          }\r\n          node.removeAttribute && node.removeAttribute('data-w95-done');\r\n          process(node, false, w);\r\n          addedProcessed++;\r\n          const kids = node.getElementsByTagName('*');\r\n          for (let i = 0; i < kids.length; i++) {\r\n            if (addedProcessed >= ADDED_NODE_BUDGET) { addedTruncated = true; break; }\r\n            kids[i].removeAttribute && kids[i].removeAttribute('data-w95-done');\r\n            process(kids[i], false, w);\r\n            addedProcessed++;\r\n          }\r\n          if (addedProcessed >= ADDED_NODE_BUDGET) { addedTruncated = true; break; }\r\n        }\r\n        // PERF-002 (SRC-018:R014): coverage at the budget boundary. The old\r\n        // fallback relied on a pre-R013 assumption (`scanStyles = force ||\r\n        // stylesDirty`) that no longer exists: runSweeper always calls\r\n        // drainStyleWork, and drainStyleWork is gated by stylesDirty. So a\r\n        // truncated batch MUST set stylesDirty=true -- an inline STYLE in the\r\n        // uninspected tail is unknown, and a force pass alone would not scan it.\r\n        // A non-truncated batch sets stylesDirty only when a style was actually\r\n        // detected, so ordinary DOM churn still does not force a scan.\r\n        if (addedTruncated || addedTruncatedDuringCollection) {\r\n          stylesDirty = true;\r\n          requestForceSweep();\r\n        } else if (styleishAdded) {\r\n          stylesDirty = true;\r\n          requestForceSweep();\r\n        }\r\n      }\r\n      // PERF-001 (SRC-063): retained attribute state has a hard bound, and the\r\n      // overflow path is a COVERAGE SUPERSET, not a scan: the force lane\r\n      // re-verifies a rotating window of the document and eventually reaches\r\n      // every connected element, exactly like the added-node truncation above.\r\n      // Promote once and drop what was retained rather than repairing it here.\r\n      if (attributeOverflowed) {\r\n        attributeOverflowed = false;\r\n        finishAttributeLane();\r\n        stylesDirty = true;\r\n        requestForceSweep();\r\n      }\r\n      flushWrites(w);\r\n      if (removalSeen) requestShadowPrune();\r\n      // The attribute debt is owed to a lane of its own; this callback only\r\n      // ever pays for its own first slice.\r\n      startAttributeLane();\r\n      addWorkPressure(performance.now() - workStarted, 'mutation-work');\r\n    }, 60);\r\n  }\r\n  const mainObserver = new MutationObserver(onMutations);\r\n  // PERF-003 (SRC-063): `let`, not `const` -- pruneShadowRegistry migrates this\r\n  // registration onto a replacement observer one bounded task at a time, and\r\n  // pierceShadow must reach the CURRENT generation while that is happening.\r\n  let shadowObserver = new MutationObserver(onMutations);\r\n  let observersStarted = false;\r\n\r\n  function startObservers() {\r\n    if (CSS_ONLY_MODE || repainterSuspended || observersStarted) {\r\n      if (CSS_ONLY_MODE) noteRepaintSkipped();\r\n      return;\r\n    }\r\n    const obsTarget = document.documentElement || document;\r\n    if (!obsTarget) return;\r\n    try {\r\n      mainObserver.observe(obsTarget, {\r\n        childList: true,\r\n        subtree: true,\r\n        attributes: true,\r\n        attributeFilter: ['class', 'bgcolor', 'background', 'style']\r\n      });\r\n      observersStarted = true;\r\n    } catch (e) { }\r\n  }\r\n\r\n  // Force passes are budgeted: on huge pages (endless feeds) each pass\r\n  // re-verifies a rotating 2500-element window instead of the whole DOM, so a\r\n  // single pass never janks the main thread; full coverage arrives over a few\r\n  // rotations. The scheduler is now adaptive: when nothing changes, it backs\r\n  // off instead of ticking forever in the background like a stubborn appliance.\r\n  const FORCE_BUDGET = 2500;\r\n  // SRC-006:R010: element work is not the only per-slice cost. Root-LEVEL work\r\n  // (disconnected-root pruning, hover-sheet processing, workset construction,\r\n  // iteration from root zero, the completion scan) used to run over ALL\r\n  // pierced roots on EVERY force continuation slice, so with many ShadowRoots\r\n  // a tiny element budget still paid O(R) per slice. Root work gets its own\r\n  // hard per-slice bound: at most FORCE_ROOT_BUDGET roots are served per\r\n  // slice, and a lap keeps a persistent ordered workset + cursor so\r\n  // continuation slices resume where the previous one stopped.\r\n  const FORCE_ROOT_BUDGET = 64;\r\n  const LIGHT_MAX_NODES = FORCE_BUDGET;\r\n  const forceRootCursors = new Map();\r\n  let forceLapWorkset = null;   // ordered roots of the CURRENT lap (document once, then a registry snapshot)\r\n  let forceLapIndex = 0;        // cursor into forceLapWorkset; advances monotonically within a lap\r\n  let forceLapRemaining = 0;    // roots not yet done/dropped in this lap; O(1) completion detection\r\n  // PERF-001: roots registered DURING a running lap are stamped for the NEXT\r\n  // one. The skip is charged to this lap's discovery budget above, and the\r\n  // count is the debt this lap leaves behind: when the lap completes, the next\r\n  // lap is scheduled automatically, so deferred roots are processed without\r\n  // waiting for an unrelated mutation or stylesheet event to ask for a sweep.\r\n  let forceDeferredRoots = 0;\r\n\r\n  let forcePassesOwed = 0;\r\n  let lightPending = false;\r\n  let sweepTimer = null;\r\n  let stylesDirty = false;\r\n\r\n  // 🚨 THE SWEEP RATE IS FLOOR-LIMITED. NOTHING MAY SCHEDULE A SWEEP AT 0ms 🚨\r\n  // Measured on a real chatgpt.com conversation (3392 elements, 15s, primitives\r\n  // counted by wrapping them on the prototypes):\r\n  //     querySelectorAll ....    151 calls  -> ~10 sweeps per SECOND\r\n  //     getComputedStyle ....  42563 calls\r\n  //     Element.closest .....  80114 calls\r\n  //     setAttribute ........  43080 calls\r\n  //     long tasks .......... 14158 ms out of 15000 (~94% of wall time)\r\n  // With the script disabled the same page spent 2517ms. So the engine was\r\n  // running roughly 150 full sweeps in 15 seconds instead of ten.\r\n  //\r\n  // Cause: requestForceSweep() ended in scheduleNextSweep(true), i.e. a 0ms\r\n  // timer, and it is called from the mutation handler on every batch that\r\n  // contains added nodes. On a React app that inserts nodes continuously, every\r\n  // insertion queued an immediate full sweep, whose own writes and stylesheet\r\n  // check queued the next one. Back-to-back sweeps with no floor.\r\n  //\r\n  // Two rules now make that impossible:\r\n  //   1. MIN_SWEEP_GAP — a hard minimum between the END of one sweep and the\r\n  //      START of the next. However much churn arrives, sweeps cannot exceed\r\n  //      one per second. This is the actual safety property; the adaptive\r\n  //      backoff below is only an idle optimisation on top of it.\r\n  //   2. A pending timer that already fires SOONER is never replaced by a later\r\n  //      one, and never cancelled and re-armed. The old code cleared and re-armed\r\n  //      the timer on every call, so a stream of requests could keep pushing the\r\n  //      timer around instead of letting it fire.\r\n  const MIN_SWEEP_GAP = 1000;\r\n  let lastSweepEnd = 0;\r\n  let sweepPlannedAt = 0;\r\n\r\n  function scheduleSweep(delay, kind) {\r\n    if (repainterSuspended || document.hidden) return;\r\n    const now = Date.now();\r\n    // Never sooner than MIN_SWEEP_GAP after the last sweep finished.\r\n    const earliest = lastSweepEnd + MIN_SWEEP_GAP - now;\r\n    const d = Math.max(delay, earliest, 0);\r\n    const fireAt = now + d;\r\n    // An already-pending sweep that lands sooner wins; do not churn the timer.\r\n    if (sweepTimer && sweepPlannedAt <= fireAt) return;\r\n    if (sweepTimer) clearTimeout(sweepTimer);\r\n    sweepPlannedAt = fireAt;\r\n    sweepTimer = setTimeout(() => {\r\n      sweepTimer = null;\r\n      sweepPlannedAt = 0;\r\n      if (document.hidden) return;\r\n\r\n      // PERF-005 (SRC-002): force debt drains first. A pending light request\r\n      // is only skipped when a force pass just ran and there is still debt,\r\n      // because the force pass is a superset of the light work.\r\n      const force = forcePassesOwed > 0;\r\n      if (force) forcePassesOwed--;\r\n\r\n      // PERF-003 (SRC-004): CONSUME the light token before the pass it caused.\r\n      // It used to be read again after runSweeper returned, so the still-true\r\n      // token scheduled a second identical pass -- measured: one isolated\r\n      // requestLightSweep() produced 2 timer callbacks and 2 sweeps, the second\r\n      // re-running the full dirty selector with nothing left to do. Re-arming\r\n      // now happens only if a NEW request arrived DURING the pass.\r\n      if (!force) lightPending = false;\r\n\r\n      runSweeper(force);\r\n\r\n      // Drainable scheduler (PERF-005): after a light pass, re-arm only when a\r\n      // light request arrived while this pass was running (lightPending was\r\n      // cleared above, so a true value can only come from during-pass work) or\r\n      // bounded dirty work remains. After a force pass that exhausted its\r\n      // budget, runSweeper already re-armed itself when incomplete.\r\n      if (!force && (lightPending || lightDirty.size)) {\r\n        lightPending = false;\r\n        lastSweepEnd = Date.now();\r\n        scheduleSweep(MIN_SWEEP_GAP, 'light');\r\n        return;\r\n      }\r\n      lastSweepEnd = Date.now();\r\n\r\n      // No automatic reschedule here. Fresh work comes from mutations,\r\n      // stylesheet loads, visibility changes, or the explicit load-time passes.\r\n    }, d);\r\n  }\r\n\r\n  // A request means \"there is fresh work, revisit soon\" — soon being the fast\r\n  // lane, NEVER immediately. runSweeper itself calls this (the bounded style\r\n  // lane reporting a changed sheet), so an immediate schedule here is a direct\r\n  // sweep-calls-sweep loop.\r\n  //\r\n  function requestForceSweep() {\r\n    // CORE-003: an excluded route is quarantined; no force lane may repaint it.\r\n    if (routeQuarantined) return;\r\n    if (repainterSuspended) return;\r\n    if (forcePassesOwed < 1) forcePassesOwed = 1;\r\n    forceLapActive = true;\r\n    scheduleSweep(1500, 'force');\r\n  }\r\n\r\n  // PERF-005: attrCooldown relies on \"the next light sweep\" to revisit an\r\n  // element whose attribute toggled during cooldown, but no such sweep was\r\n  // ever scheduled. This is the missing bounded light-work request: mark\r\n  // lightPending and re-arm. It coalesces (one timer), stays floor-limited,\r\n  // and a light pass never turns into an endless force cycle.\r\n  //\r\n  // PERF-003 (SRC-004): the light lane now carries its OWN bounded dirty\r\n  // registry instead of rediscovering work with a document-wide negative\r\n  // selector. `root.querySelectorAll('*:not([data-w95-done])')` materialised\r\n  // the COMPLETE matching NodeList before the 2500-node budget was consulted --\r\n  // measured at 12,000 materialised matches for 2,500 process() calls -- and on\r\n  // a settled page it still made the selector engine walk every root to return\r\n  // nothing. Every caller that clears the done marker without immediately\r\n  // re-processing registers the element here, so discovery is O(dirty), not\r\n  // O(document). Past the cap the work is promoted ONCE to the force lane,\r\n  // which is a strict superset and already incremental.\r\n  const LIGHT_DIRTY_MAX = 2000;\r\n  const lightDirty = new Set();\r\n  function markLightDirty(el) {\r\n    if (!el || el.nodeType !== 1) return;\r\n    if (lightDirty.size >= LIGHT_DIRTY_MAX) { requestForceSweep(); return; }\r\n    lightDirty.add(el);\r\n  }\r\n  function requestLightSweep() {\r\n    if (repainterSuspended || document.hidden) return;\r\n    if (lightPending) { if (!sweepTimer) scheduleSweep(MIN_SWEEP_GAP, 'light'); return; }\r\n    lightPending = true;\r\n    scheduleSweep(MIN_SWEEP_GAP, 'light');\r\n  }\r\n\r\n  function runSweeper(force) {\r\n    if (repainterSuspended) return;\r\n    const sweepStarted = performance.now();\r\n    const w = [];\r\n\r\n    // R013 / TARGET G: the light lane no longer strips hover sheets\r\n    // synthetically for document + every pierced root. Dirty style work IS\r\n    // scheduler debt now: one bounded slice is drained here, and an incomplete\r\n    // slice schedules its own continuation, so a DOM continuation never\r\n    // restarts stylesheet enumeration.\r\n    const styleRes = drainStyleWork(STYLE_SHEET_BUDGET, STYLE_RULE_BUDGET);\r\n    if (styleRes.changed) {\r\n      if (force) {\r\n        forcePassesOwed = Math.max(forcePassesOwed, 1);\r\n      } else {\r\n        requestForceSweep();\r\n      }\r\n    }\r\n\r\n    if (!force) {\r\n      // PERF-003 (SRC-004): the light lane drains its OWN bounded registry and\r\n      // never touches the root list.\r\n      let remaining = LIGHT_MAX_NODES;\r\n      let incomplete = false;\r\n      for (const el of lightDirty) {\r\n        if (remaining <= 0) { incomplete = true; break; }\r\n        lightDirty.delete(el);\r\n        if (!el.isConnected) continue;\r\n        try { process(el, false, w); } catch (e) { }\r\n        remaining--;\r\n      }\r\n      flushWrites(w);\r\n      // Sweep-work accounting feeds the mutation-work suspension guard.\r\n      addWorkPressure(performance.now() - sweepStarted, 'sweep-work');\r\n      if ((incomplete || !styleRes.done) && !repainterSuspended && !document.hidden) {\r\n        requestLightSweep();\r\n      }\r\n      return;\r\n    }\r\n\r\n    // ---- FORCE LANE (R013 / PERF-002) ----\r\n    // Persistent incremental root cursor.\r\n    // Document served once per lap, pierced roots advanced incrementally.\r\n    // Zero full materialization `[document, ...piercedRoots]`.\r\n    if (!forceLapActive || !forceLapWorkset) {\r\n      forceLapActive = true;\r\n      forceLapWorkset = {\r\n        docDone: false,\r\n        iterator: piercedRoots.values(),\r\n        currentRoot: null,\r\n        lapFinished: false,\r\n        id: ++forceLapId\r\n      };\r\n      forceLapIndex = 0;\r\n      forceLapRemaining = 1;\r\n      forceDeferredRoots = 0;\r\n      stylesDirty = false;\r\n      forceRootCursors.clear();\r\n    }\r\n\r\n    let remaining = FORCE_BUDGET;\r\n    let rootsServed = 0;\r\n\r\n    // 1. Serve document once per lap\r\n    if (!forceLapWorkset.docDone && remaining > 0 && rootsServed < FORCE_ROOT_BUDGET) {\r\n      const root = document;\r\n      let state = forceRootCursors.get(root);\r\n      if (!state) {\r\n        const walker = (root.createTreeWalker ? root.createTreeWalker(root, 0x1 /* SHOW_ELEMENT */, null) : null);\r\n        state = { walker, total: 0, done: false };\r\n        forceRootCursors.set(root, state);\r\n      }\r\n      try {\r\n        while (remaining > 0) {\r\n          const node = state.walker ? state.walker.nextNode() : null;\r\n          if (!node) { state.done = true; break; }\r\n          process(node, true, w);\r\n          state.total++;\r\n          remaining--;\r\n        }\r\n      } catch (e) { state.done = true; }\r\n\r\n      if (state.done) {\r\n        forceLapWorkset.docDone = true;\r\n        forceLapIndex++;\r\n        rootsServed++;\r\n      } else {\r\n        rootsServed++;\r\n      }\r\n    }\r\n\r\n    // 2. Advance pierced roots incrementally\r\n    if (forceLapWorkset.docDone) {\r\n      while (rootsServed < FORCE_ROOT_BUDGET && remaining > 0) {\r\n        if (!forceLapWorkset.currentRoot) {\r\n          if (!forceLapWorkset.iterator) {\r\n            forceLapWorkset.lapFinished = true;\r\n            break;\r\n          }\r\n          const next = forceLapWorkset.iterator.next();\r\n          if (next.done) {\r\n            forceLapWorkset.lapFinished = true;\r\n            break;\r\n          }\r\n          const candidate = next.value;\r\n          // PERF-005: a root stamped for a future lap is not this lap's work.\r\n          // work. It already lives in piercedRoots, so nothing has to be\r\n          // transferred when this lap finishes.\r\n          if (candidate.__wintageLapId && candidate.__wintageLapId > forceLapWorkset.id) {\r\n            // PERF-001: the iterator advance is charged against the SAME\r\n            // discovery budget every other root costs. Skipping used to be\r\n            // free, so a heap of future-stamped roots could enumerate 50,000\r\n            // advances inside one task with rootsServed still 0.\r\n            rootsServed++;\r\n            forceDeferredRoots++;\r\n            continue;\r\n          }\r\n          forceLapWorkset.currentRoot = candidate;\r\n        }\r\n\r\n        const root = forceLapWorkset.currentRoot;\r\n        let detached = false;\r\n        try { detached = !root.host || !root.host.isConnected; } catch (e) { detached = true; }\r\n        if (detached) {\r\n          try { piercedRoots.delete(root); forceRootCursors.delete(root); } catch (e) { }\r\n          forceLapWorkset.currentRoot = null;\r\n          forceLapIndex++;\r\n          rootsServed++;\r\n          continue;\r\n        }\r\n\r\n        let state = forceRootCursors.get(root);\r\n        if (!state) {\r\n          const walker = (root.createTreeWalker ? root.createTreeWalker(root, 0x1 /* SHOW_ELEMENT */, null) : null);\r\n          state = { walker, total: 0, done: false };\r\n          forceRootCursors.set(root, state);\r\n        }\r\n        try {\r\n          while (remaining > 0) {\r\n            const node = state.walker ? state.walker.nextNode() : null;\r\n            if (!node) { state.done = true; break; }\r\n            process(node, true, w);\r\n            state.total++;\r\n            remaining--;\r\n          }\r\n        } catch (e) { state.done = true; }\r\n\r\n        if (state.done) {\r\n          forceLapWorkset.currentRoot = null;\r\n          forceLapIndex++;\r\n          rootsServed++;\r\n        } else {\r\n          rootsServed++;\r\n          break;\r\n        }\r\n      }\r\n    }\r\n\r\n    flushWrites(w);\r\n    addWorkPressure(performance.now() - sweepStarted, 'sweep-work');\r\n\r\n    const lapComplete = forceLapWorkset.docDone && !forceLapWorkset.currentRoot && forceLapWorkset.lapFinished;\r\n    const styleComplete = styleRes.done;\r\n\r\n    if (force && forceLapActive) {\r\n      if (lapComplete) {\r\n        // PERF-001: a lap that deferred roots owes exactly one more lap, and\r\n        // that continuation is requested HERE rather than left to chance. With\r\n        // no other mutation or stylesheet debt, the deferred roots would\r\n        // otherwise never be processed at all.\r\n        const oweContinuation = forceDeferredRoots > 0;\r\n        forceDeferredRoots = 0;\r\n        forceRootCursors.clear();\r\n        forceLapWorkset = null;\r\n        forceLapIndex = 0;\r\n        forceLapRemaining = 0;\r\n        forceLapActive = false;\r\n        if (oweContinuation) requestForceSweep();\r\n      } else if (!repainterSuspended && !document.hidden) {\r\n        forcePassesOwed = Math.max(forcePassesOwed, 1);\r\n        scheduleSweep(MIN_SWEEP_GAP);\r\n      }\r\n      if (!styleComplete && !repainterSuspended && !document.hidden) {\r\n        requestLightSweep();\r\n      }\r\n    }\r\n  }\r\n\r\n  // Elements processed before the site's CSS finished loading bake in unstyled\r\n  // values and would otherwise stay wrong forever (white surfaces that \"heal\"\r\n  // only when the SPA happens to re-render them). Full re-verify passes\r\n  // (force=true) re-check EVERY element: at DOMContentLoaded, again 1s later\r\n  // once late CSS settled, then on demand whenever requestForceSweep() fires.\r\n  // The write-if-changed guard in setImp keeps repeat passes cheap.\r\n  function startSweeping() {\r\n    // CORE-003: a deferred settling pass must not repaint a quarantined route.\r\n    if (routeQuarantined) return;\r\n    paintRoot();\r\n    injectLate();\r\n    startObservers();\r\n    if (CSS_ONLY_MODE) {\r\n      noteRepaintSkipped();\r\n      try {\r\n        paintRoot();\r\n        document.documentElement.setAttribute('data-w95-perf', 'css-only');\r\n        document.documentElement.setAttribute('data-w95-perf-reason', IS_REDDIT ? 'reddit-lean-css' : (IS_CHATGPT ? 'chatgpt-lean-css' : 'known-high-churn-host'));\r\n      } catch (e) { }\r\n      // One final cascade-order correction after late app CSS arrives. No DOM\r\n      // scan, no observer, no repeating timer.\r\n      window.addEventListener('load', function () {\r\n        paintRoot();\r\n        injectLate();\r\n      }, { once: true });\r\n      return;\r\n    }\r\n    // The boot pass measured ONE 716ms long task on a 16921-element page, right\r\n    // when the site's own init scripts are competing for the main thread — the\r\n    // \"have to reload a couple of times before it comes up\" symptom. The\r\n    // read/write split above is what actually shrinks it; deferring the second\r\n    // pass past load keeps it out of the critical window as well.\r\n    // CSS already paints immediately. Corrective JS work is deferred and\r\n    // floor-limited instead of blocking DOMContentLoaded with a full traversal.\r\n    requestForceSweep();\r\n    setTimeout(() => { stylesDirty = true; requestForceSweep(); }, 1500);\r\n\r\n    if (!IS_TOP) {\r\n      // Sub-frame: bounded settling passes, then nothing. The MutationObserver\r\n      // stays live, so a late-loading embed still gets themed — that path is\r\n      // event-driven and costs zero while idle.\r\n      setTimeout(() => { stylesDirty = true; requestForceSweep(); }, 3000);\r\n      return;\r\n    }\r\n\r\n    // Top frame: event-driven sweeps only. Idle means idle; fresh work\r\n    // re-arms the scheduler through mutations, stylesheet loads, or focus/visibility changes.\r\n\r\n    // Pages that finished loading while the tab was hidden got no sweeps; on\r\n    // return, re-verify immediately so the user never sees stale white. This is\r\n    // the ONE place a sweep still runs synchronously without waiting for the\r\n    // floor — it is user-initiated (they just looked at the tab) and happens at\r\n    // most once per tab switch, so it cannot form a loop.\r\n    document.addEventListener('visibilitychange', () => {\r\n      if (!document.hidden) {\r\n        // A tab switch must not synchronously walk a 20,000-node conversation.\r\n        // Repaint later through the same rate-limited lane as every other cause.\r\n        stylesDirty = true;\r\n        requestForceSweep();\r\n      } else if (sweepTimer) {\r\n        clearTimeout(sweepTimer);\r\n        sweepTimer = null;\r\n        sweepPlannedAt = 0;\r\n      }\r\n    });\r\n\r\n    // Late external stylesheet loads can alter computed styles without DOM\r\n    // churn. Catch them once and reschedule a real pass instead of polling.\r\n    document.addEventListener('load', (evt) => {\r\n      const t = evt.target;\r\n      if (!t || t.nodeType !== 1) return;\r\n      if ((t.tagName || '').toUpperCase() !== 'LINK') return;\r\n      const rel = (t.rel || '').toLowerCase();\r\n      if (rel.includes('stylesheet')) {\r\n        stylesDirty = true;\r\n        requestForceSweep();\r\n      }\r\n    }, true);\r\n  }\r\n\r\n  if (document.readyState === 'loading') {\r\n    document.addEventListener('DOMContentLoaded', startSweeping, { once: true });\r\n  } else {\r\n    startSweeping();\r\n  }\r\n\r\n  ";

// The one place insertCSS cannot reach. It produces a DOCUMENT stylesheet, and a
// document stylesheet does not cross a shadow boundary, so every rule written for
// a shadow tree has to be carried in and injected root by root -- which is what
// the repainter's pierceShadow does with this.
const SHADOW_CSS = "\r\n    /* Height-only 1ms transition + near-zero animation (see GLOBAL_CSS motion\r\n       note): transitionend/animationend keep firing for collapse + rc-motion\r\n       state machines, without touching top/left/width/transform. */\r\n    /* animation-fill-mode: forwards for the same snapback reason as the global\r\n       layer -- a shadow tree reveals its content the same way a light one does. */\r\n    * { border-radius: 0 !important; transition-property: height, max-height, min-height !important; transition-duration: 0.001s !important; transition-delay: 0s !important; animation-duration: 0.001s !important; animation-delay: 0s !important; animation-iteration-count: 1 !important; animation-fill-mode: forwards !important; }\r\n    /* Zero shadow / zero blur, same as the global layer (UI.md law 2). Shadow\r\n       roots are where modern component libraries keep their elevation, so\r\n       skipping this here would leave every web-component card floating while the\r\n       rest of the page is flat. */\r\n    *, *::before, *::after { box-shadow: none !important; text-shadow: none !important; backdrop-filter: none !important; -webkit-backdrop-filter: none !important; }\r\n    *:not(img):not(svg):not(video):not(canvas):not(picture):not(image), *::before, *::after { filter: none !important; }\r\n    /* Type ladder, same five steps and the same disjoint-selector trick as the\r\n       global layer (see the specificity note there — layering the exceptions on\r\n       top instead silently flattens every heading to 12px). */\r\n    *:not(svg):not(path):not(i):not(h1):not(h2):not(h3):not(h4):not(h5):not(h6):not(small):not(sub):not(sup):not(figcaption):not([class*=\"icon\" i]):not([class*=\"fa-\" i]):not([class*=\"symbols\" i]):not([class*=\"glyph\" i]):not([class*=\"mdi\" i]):not([class*=\"bi-\" i]):not([class*=\"codicon\" i]):not([class*=\"lucide\" i]):not([class*=\"octicon\" i]):not([class*=\"remixicon\" i]):not([class*=\"phosphor\" i]):not([class*=\"iconify\" i]):not([class*=\"feather\" i]):not([data-icon]):not([data-cds=\"Icon\"]) {\r\n      font-size: 12px !important; line-height: 1.2 !important;\r\n    }\r\n    h1 { font-size: 16px !important; line-height: 1.2 !important; }\r\n    h2, h3, h4, h5, h6 { font-size: 14px !important; line-height: 1.2 !important; }\r\n    small, sub, sup, figcaption { font-size: 10px !important; line-height: 1.2 !important; }\r\n    *:not(svg):not(path) { font-weight: 400 !important; font-style: normal !important; }\r\n    /* ':host X' matches X inside this shadow tree and scores (0,1,1), beating the\r\n       (0,0,2) base rule above — the same specificity fix the global layer makes\r\n       with ':root'. A bare 'b' here would lose and nothing would be bold. */\r\n    :host b, :host strong, :host th, :host h1, :host h2, :host h3, :host h4, :host h5, :host h6,\r\n    :host summary, :host legend, :host label, :host button, :host shreddit-button, :host [role=\"button\"],\r\n    :host .btn, :host [class~=\"button\" i], :host [class~=\"btn\" i] { font-weight: 700 !important; }\r\n    :host b, :host strong, :host p, :host li, :host dd, :host dt, :host h1, :host h2, :host h3, :host h4, :host h5, :host h6 { color: #E2CA95 !important; }\r\n    :host i, :host em, :host cite, :host var, :host dfn, :host q, :host blockquote { font-style: italic !important; }\r\n    /* No 99,999-second hover freeze here either. Shadow-tree pseudo-elements\r\n       are exactly where shimmer loaders and decorative hover layers tend to live,\r\n       so keeping permanent transitions here is especially expensive. */\r\n    *:not(svg):not(path):not(i):not([class*=\"icon\" i]):not([class*=\"fa-\" i]):not([class*=\"symbols\" i]):not([class*=\"glyph\" i]):not([class*=\"mdi\" i]):not([class*=\"bi-\" i]):not([class*=\"codicon\" i]):not([class*=\"lucide\" i]):not([class*=\"octicon\" i]):not([class*=\"remixicon\" i]):not([class*=\"phosphor\" i]):not([class*=\"iconify\" i]):not([class*=\"feather\" i]):not([data-icon]):not([data-cds=\"Icon\"]) {\r\n      font-family: Verdana_m1, Verdana, Tahoma, \"MS Sans Serif\", sans-serif !important; -webkit-font-smoothing: none !important; -moz-osx-font-smoothing: unset !important; font-smooth: never !important; text-rendering: optimizeSpeed !important;\r\n    }\r\n    input, textarea, select, option, button, code, pre, kbd, samp, tt, [class*=\"code\" i], [class*=\"mono\" i] { font-family: Verdana_m1, Verdana, Tahoma, \"MS Sans Serif\", sans-serif !important; }\r\n     :host {\r\n       --radius: 0px; --shreddit-border-radius: 0px; --md-sys-shape-corner-full: 0px;\r\n       --color-neutral-content: #E2CA95; --color-neutral-content-strong: #E2CA95;\r\n       --color-neutral-content-weak: #C5AB6E; --color-neutral-content-muted: #95804C;\r\n       --color-tone-1: #E2CA95; --color-tone-2: #C5AB6E;\r\n       --color-neutral-background: #3A2616; --color-neutral-background-weak: #4A341B;\r\n       --shreddit-content-background: #3A2616; --shreddit-post-background: #4A341B;\r\n       --m3c-surface: #4A341B; --m3c-surface-container: #4A341B; --color-surface: #4A341B;\r\n       background-color: transparent !important; background-image: none !important; color: #E2CA95 !important;\r\n     }\r\n     [slot=\"title\"], [slot=\"title\"] a, a[slot=\"title\"], a[id*=\"post-title\"], [id*=\"post-title\"] {\r\n       color: #E2CA95 !important;\r\n     }\r\n    /* Ad-iframe load-flash fix, scoped to known ad hosts only — see GLOBAL_CSS note (unconditional would break transparent widget overlays) */\r\n    iframe[src*=\"doubleclick.net\" i], iframe[src*=\"googlesyndication.com\" i],\r\n    iframe[src*=\"google.com/ads\" i], iframe[id*=\"google_ads_iframe\" i],\r\n    iframe[id*=\"gpt_unit\" i], iframe[src*=\"adservice.google\" i],\r\n    iframe[src*=\"amazon-adsystem.com\" i], iframe[src*=\"taboola.com\" i],\r\n    iframe[src*=\"outbrain.com\" i] {\r\n      background-color: #3A2616 !important;\r\n    }\r\n    /* 🚨 :not(:root) IS LOAD-BEARING, DO NOT DROP IT 🚨\r\n       Inside a shadow tree an attribute selector can never match the document root,\r\n       so this guard costs nothing there — but this stylesheet does not only live in\r\n       shadow trees. tools/build-desktop.js CONCATENATES GLOBAL_CSS + SHADOW_CSS into\r\n       the single sheet the Electron shim injects into a whole document, and there\r\n       [class] matches <html class=\"dark\"> like any other element. The root then gets\r\n       color: inherit with nothing above it to inherit from, so it computes to the\r\n       INITIAL value — black — and every descendant inherits that same black through\r\n       this very rule. background-color: transparent does the same to the root's\r\n       background.\r\n       That is what made Claude unreadable: black text on the themed brown, immune\r\n       even to an inline important because the sheet is injected at user origin\r\n       there. Proved live over CDP: removing the class attribute from <html> turned\r\n       the whole transcript from rgb(0,0,0) to rgb(212,200,154) and restoring it put\r\n       the black back. Apps whose <html> carries no class (the Electron shell,\r\n       about:blank) were untouched, which is exactly why it read as a Claude-specific\r\n       mystery for eight rounds. :root is never a thing to hand inherit to.\r\n       (No backticks in this comment: it sits inside a template literal and one would\r\n       end it. node --check caught that too, on the very same edit.) */\r\n    div, span, section, article, aside, nav, header, footer, main {\r\n      /* Blanket wipe retired (T-121) */\r\n    }\r\n\r\n\r\n\r\n    button, input[type=\"button\"], input[type=\"submit\"], input[type=\"reset\"], shreddit-button, .btn,\r\n    [class~=\"button\" i], [class~=\"btn\" i], a[role=\"button\"], span[role=\"button\"], summary {\r\n      background-color: #5A4324 !important; color: #E2CA95 !important; border: 2px solid !important; border-color: #826941 #1C1208 #1C1208 #826941 !important; box-shadow: none !important;\r\n      cursor: pointer !important; font-family: Verdana_m1, Verdana, Tahoma, \"MS Sans Serif\", sans-serif !important; box-sizing: border-box !important;\r\n      padding: 2px 6px !important; min-width: 24px !important; min-height: 20px !important;\r\n    }\r\n    button:active, shreddit-button:active, .btn:active, [class~=\"button\" i]:active, [class~=\"btn\" i]:active, summary:active { background-color: #4A341B !important; border: 2px solid !important; border-color: #1C1208 #826941 #826941 #1C1208 !important; box-shadow: none !important; transform: translate(1px, 1px) !important; }\r\n    /* Disabled: label colour only, bevel and surface stay (UI.md bans opacity here) */\r\n    button:disabled, shreddit-button:disabled, button[aria-disabled=\"true\"], [role=\"button\"][aria-disabled=\"true\"] {\r\n      color: #95804C !important; background-color: #5A4324 !important; opacity: 1 !important; cursor: not-allowed !important; border: 2px solid !important; border-color: #826941 #1C1208 #1C1208 #826941 !important; box-shadow: none !important;\r\n    }\r\n\r\n    /* Paint-only: display:none here deleted ::before icon glyphs (see GLOBAL_CSS) */\r\n    /* background-COLOR, not the shorthand: the shorthand also reset\r\n       background-image and deleted every url() glyph on a control's\r\n       pseudo-element (provider logos, sprites) — same repair as GLOBAL_CSS. */\r\n    button::before, button::after, .btn::before, .btn::after { background-color: transparent !important; box-shadow: none !important; filter: none !important; }\r\n    /* Same exclusions as the light-DOM wipe retired in T-121 */\r\n\r\n    input:not([type=\"button\"]):not([type=\"submit\"]):not([type=\"reset\"]):not([type=\"checkbox\"]):not([type=\"radio\"]) { background-color: #24170C !important; color: #E2CA95 !important; border: 2px solid !important; border-color: #1C1208 #826941 #826941 #1C1208 !important; box-shadow: none !important; box-sizing: border-box !important; }\r\n    input:not([type=\"button\"]):not([type=\"submit\"]):not([type=\"reset\"]):not([type=\"checkbox\"]):not([type=\"radio\"]):not([type=\"range\"]):not([type=\"color\"]):not([type=\"file\"]),\r\n    select:not([multiple]):not([size]), select[size=\"1\"] { height: 20px !important; padding: 1px 3px !important; }\r\n    select[multiple], select[size]:not([size=\"1\"]) { height: auto !important; min-height: 48px !important; padding: 1px 3px !important; }\r\n    textarea { min-height: 64px !important; resize: none !important; padding: 1px 3px !important; }\r\n    /* appearance:auto not forced here either — see GLOBAL_CSS checkbox note */\r\n    input[type=\"checkbox\"], input[type=\"radio\"] { accent-color: #D3B57A !important; background-image: none !important; }\r\n    input::placeholder, textarea::placeholder { color: #95804C !important; }\r\n    input:focus-visible, textarea:focus-visible, select:focus-visible, button:focus-visible, a:focus-visible,\r\n    summary:focus-visible, [tabindex]:focus-visible, [role=\"button\"]:focus-visible, [contenteditable]:focus-visible {\r\n      outline: 1px dotted #E2CA95 !important; outline-offset: -4px !important;\r\n    }\r\n    th { background-color: #4A341B !important; color: #E2CA95 !important; border: 2px solid !important; border-color: #826941 #1C1208 #1C1208 #826941 !important; box-shadow: none !important; }\r\n    *::selection, ::selection { background-color: #5A4324 !important; color: #E2CA95 !important; }\r\n\r\n    /* Hover recolor stays zeroed out here too — only real clickable controls respond. */\r\n    button:hover, shreddit-button:hover, .btn:hover { background-color: #634B2B !important; border: 2px solid !important; border-color: #826941 #1C1208 #1C1208 #826941 !important; box-shadow: none !important; }\r\n    a, a:link { color: #D3B57A !important; text-decoration: none !important; }\r\n    a:visited { color: #C5AB6E !important; }\r\n    a:hover { text-decoration: underline !important; background-color: transparent !important; }\r\n    @supports (scrollbar-color: #665033 #342012) {\r\n      * { scrollbar-color: #665033 #342012 !important; }\r\n    }\r";

// Everything the extracted body reads from the userscript's outer scope has to be
// handed to it here. That list is not maintained by hand and hope: build-desktop.js
// fails the build if the userscript ever starts reading something this prelude does
// not define, because the failure mode otherwise is a ReferenceError thrown inside
// executeJavaScript, which surfaces as "the theme just does not work" and nothing
// else.
const REPAINTER_FIX = `(() => {
  if (window.__wintageRepainter) return "already running";
  window.__wintageRepainter = true;

  const W95_VERSION = '1.36.11';

  // This pack's palette, whole. Not trimmed to what the repainter happens to read
  // today: it builds PALETTE_RGB from Object.keys(T) to recognise its own colours,
  // so a missing token would make it treat one of our own greys as the site's.
  const T = {
    background: '#342012',
    backgroundSoft: '#3A2616',
    surface: '#4A341B',
    surfaceRaised: '#5A4324',
    surfaceAlt: '#634B2B',
    borderDark: '#1C1208',
    borderHighlight: '#D3B57A',
    bevelLight: '#826941',
    borderMuted: '#665033',
    link: '#D3B57A',
    textPrimary: '#E2CA95',
    textSecondary: '#C5AB6E',
    textMuted: '#95804C',
    accentTeal: '#008080',
    accentTealDeep: '#006060',
    success: '#5B9630',
    warning: '#969630',
    danger: '#963030',
    dangerText: '#D37676',
    selection: '#5A4324',
    compareBack: '#24170C'
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
  function paintRoot() { }

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
  const ACTIVE_SHADOW_CSS = SHADOW_CSS;

  // CORE-003: the userscript keeps the bootstrap root-attribute observer in a
  // script-scope binding so the excluded-route quarantine can stop it BEFORE the
  // attributes and the inline overrides come off, instead of one repaint later.
  // The repainter body’s suspendRepainter disconnects that same handle, so this
  // prelude must declare it or the body ReferenceErrors inside executeJavaScript --
  // which is the failure the build’s free-identifier gate refuses to ship.
  let rootAttributeObserver = null;
  // CORE-003: the userscript's quarantine fence is a script-scope binding, so
  // the repainter body reads it from the outer scope and this prelude must
  // declare it -- the same requirement as rootAttributeObserver above.
  let routeQuarantined = false;
  let rootInlineOriginals = null;
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
