const fs = require('fs');
let code = fs.readFileSync('desktop/targets/electron/shim.cjs', 'utf8');

code = code.replace(/wc\.insertCSS\(payload, \{ cssOrigin: 'author' \}\)\s*\.then\(\(\) => stamp\('injected ' \+ payload\.length \+ ' bytes into ' \+ url\)\)/, 
`wc.insertCSS(payload, { cssOrigin: 'author' })
          .then(key => { wc.__wintageCssKey = key; stamp('injected ' + payload.length + ' bytes into ' + url); })`);

const topTarget = `let css = '';
try { css = fs.readFileSync(CSS_FILE, 'utf8'); } catch (e) {
  console.error('[wintage] stylesheet missing, loading the app unthemed:', e.message);
}`;

const topReplacement = topTarget + `

// Live Reload Watcher
try {
  let reloadDebounce = null;
  fs.watch(CSS_FILE, (event) => {
    if (event === 'change') {
      clearTimeout(reloadDebounce);
      reloadDebounce = setTimeout(() => {
        try {
          const newCss = fs.readFileSync(CSS_FILE, 'utf8');
          if (newCss === css) return;
          css = newCss;
          const { app } = require('electron');
          app.webContents.getAllWebContents().forEach(wc => {
            let url = '';
            try { url = wc.getURL(); } catch (e) { return; }
            if (!url || url.startsWith('devtools://')) return;
            const payload = (typeof CLAUDE_VIEW !== 'undefined' && CLAUDE_VIEW.test(url)) ? css + CLAUDE_FOREGROUND_CSS : css;
            if (wc.__wintageCssKey) {
              wc.removeInsertedCSS(wc.__wintageCssKey).catch(() => {});
            }
            wc.insertCSS(payload, { cssOrigin: 'author' })
              .then(key => { wc.__wintageCssKey = key; })
              .catch(() => {});
          });
        } catch (e) { }
      }, 50);
    }
  });
} catch (e) { }
`;

code = code.replace(topTarget, topReplacement);

fs.writeFileSync('desktop/targets/electron/shim.cjs', code, 'utf8');
console.log("Success");
