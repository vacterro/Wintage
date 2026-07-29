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
      // live in this app?" is answerable without a screenshot or a devtools port —
      // the same reason the userscript stamps data-w95-ver on every style tag.
      const stamp = text => {
        try { fs.writeFileSync(path.join(__dirname, 'wintage-status.txt'), new Date().toISOString() + ' ' + text + '\n'); } catch (e) { }
      };
      const inject = () => {
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
// problem, not the theme's — but if the shim itself is what broke, the message
// says so plainly, because a user staring at an app that will not start needs to
// know which of the two to blame.
try {
  require(ASAR);
} catch (e) {
  console.error('[wintage] failed to load the original app.asar at ' + ASAR);
  console.error('[wintage] delete this folder (resources/app) to restore the app exactly as it was.');
  throw e;
}
