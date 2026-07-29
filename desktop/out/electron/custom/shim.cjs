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
// a main-process error dialog. Freebuff does exactly that. The extension pins CommonJS
// regardless of what the copied manifest says.

const path = require('path');
const fs = require('fs');

const CSS_FILE = path.join(__dirname, 'wintage.css');
const ASAR = path.join(__dirname, 'app.asar');

let css = '';
try { css = fs.readFileSync(CSS_FILE, 'utf8'); } catch (e) {
  console.error('[wintage] stylesheet missing, loading the app unthemed:', e.message);
}

// в”Ђв”Ђв”Ђ SCROLLBAR GUTTERS в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
// Styling ::-webkit-scrollbar turns Chromium's OVERLAY scrollbars into classic
// ones. Overlay scrollbars are invisible until you scroll, so app authors write
// `overflow: scroll` freely and it costs them nothing вЂ” until a theme makes those
// scrollbars classic, and every one of those containers grows a permanent 16px
// gutter with a full-length thumb, on panels that have room to spare. Reported on
// Antigravity, visible on several panels at once.
//
// CSS cannot fix this: there is no selector for "this element's overflow is scroll",
// and blanket-overriding overflow would break containers that need `hidden`. So the
// one narrow change is made from script: computed `scroll` becomes `auto`, which is
// identical when the content actually overflows and hides the gutter when it does
// not. Nothing else is touched.
//
// Cost discipline is copied from the userscript, which already paid for this lesson:
// getComputedStyle over a whole document is expensive, so this runs a few bounded
// passes after load and then only on newly added subtrees, never on a timer.
const SCROLL_FIX = `(() => {
  if (window.__wintageScrollFix) return "already running";
  window.__wintageScrollFix = true;
  
  const fixOne = el => {
    const cs = getComputedStyle(el);
    let fixed = false;
    if (cs.overflowY === "scroll") { el.style.setProperty("overflow-y", "auto", "important"); fixed = true; }
    if (cs.overflowX === "scroll") { el.style.setProperty("overflow-x", "auto", "important"); fixed = true; }
    return fixed;
  };
  
  const fixTree = root => {
    const els = root.querySelectorAll ? root.querySelectorAll("*") : [];
    for (const el of els) fixOne(el);
  };
  
  fixTree(document);
  let passes = 0;
  const settle = () => { if (++passes < 3) { fixTree(document); setTimeout(settle, 600); } };
  setTimeout(settle, 600);
  
  let queued = false;
  const mutations = [];
  new MutationObserver(records => {
    mutations.push(...records);
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => {
      queued = false;
      const recs = mutations.splice(0, mutations.length);
      for (const r of recs) {
        if (r.type === "childList") {
          for (const node of r.addedNodes) {
            if (node.nodeType === 1) { fixOne(node); fixTree(node); }
          }
        } else if (r.type === "attributes") {
          if (r.target.nodeType === 1) fixOne(r.target);
        }
      }
    });
  }).observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ["style", "class"] });
  
  return "scroll fix installed";
})()`;

// Registered BEFORE the real main runs, so no window can be created and finish
// loading before the listener exists. Injection is attached to both dom-ready and
// did-finish-load: a renderer that navigates (sign-in flows, in-app reloads) fires
// them again, and insertCSS does not survive a navigation.
if (css) {
  try {
    const { app } = require('electron');
    app.on('browser-window-created', (_e, win) => {
      // Injection either happened or it did not, and a themed-looking window is not
      // proof (the app may simply have a dark theme of its own). Each result is
      // stamped to a status file next to the stylesheet, so "is the theme actually
      // live in this app?" is answerable without a screenshot or a devtools port вЂ”
      // the same reason the userscript stamps data-w95-ver on every style tag.
      // Appended and capped, not overwritten: the stylesheet and the scrollbar fix
      // report separately and can fail independently, so one overwritten line would
      // hide whichever of them finished first.
      const stamp = text => {
        try {
          const f = path.join(__dirname, 'wintage-status.txt');
          let prev = '';
          try { prev = fs.readFileSync(f, 'utf8'); } catch (e) { }
          fs.writeFileSync(f, (prev + new Date().toISOString() + ' ' + text + '\n').split('\n').slice(-40).join('\n'));
        } catch (e) { }
      };
      // dom-ready, did-finish-load and did-frame-finish-load all fire for the same
      // document, so an unguarded handler inserted the same 39 KB stylesheet three
      // times into every renderer. The status file is what made that visible. Keyed
      // on the URL, so a real navigation still re-injects (insertCSS does not
      // survive one) while the three events for one document inject once.
      let injectedFor = null;
      const inject = () => {
        const url = win.webContents.getURL();
        if (url === injectedFor) return;
        injectedFor = url;
        win.webContents.executeJavaScript(SCROLL_FIX, true)
          .then(r => stamp('scrollfix: ' + r))
          .catch(err => stamp('scrollfix FAILED: ' + (err && err.message)));
        win.webContents.insertCSS(css, { cssOrigin: 'author' })
          .then(() => stamp('injected ' + css.length + ' bytes into ' + win.webContents.getURL()))
          .catch(err => {
            stamp('FAILED: ' + (err && err.message));
            console.error('[wintage] insertCSS failed:', err && err.message);
          });
      };
      win.webContents.on('dom-ready', inject);
      win.webContents.on('did-finish-load', inject);
      // Child renderers (webviews, popups) get it too.
      win.webContents.on('did-frame-finish-load', inject);
    });
  } catch (e) {
    console.error('[wintage] could not hook window creation, loading the app unthemed:', e.message);
  }
}

// Hand control to the real application. Anything thrown here is the app's own
// problem, not the theme's вЂ” but if the shim itself is what broke, the message
// says so plainly, because a user staring at an app that will not start needs to
// know which of the two to blame.
try {
  require(ASAR);
} catch (e) {
  console.error('[wintage] failed to load the original app.asar at ' + ASAR);
  console.error('[wintage] delete this folder (resources/app) to restore the app exactly as it was.');
  throw e;
}

