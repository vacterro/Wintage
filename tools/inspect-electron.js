#!/usr/bin/env node
// Reads a LIVE themed Electron app over the Chrome DevTools Protocol.
//
// Why this exists: the only other feedback loop for a themed desktop app is
// "change something, ask the user to restart, look at a screenshot", and that
// loop cost this project eight rounds on a single bug before anyone asked Blink
// directly which rule was winning. It answered in one call. Two more bugs after
// it were found the same way, in minutes.
//
// Requires the shim's opt-in debug port: put the port number in a file called
// `wintage-debug.port` next to the installed shim and restart the app. Deleting
// that file turns it off again.
//
//   node tools/inspect-electron.js targets
//   node tools/inspect-electron.js rules <url-part> <selector>     # who wins, per property
//   node tools/inspect-electron.js eval <url-part> <file.js>       # run an expression
//
// `rules` is the one that matters: it prints the cascade the way the DevTools
// Styles pane does, including origin, so "our rule loses to theirs" stops being a
// theory. Injected stylesheets show up as origin `injected`.

const http = require('http');
const fs = require('fs');

const PORT = process.env.WINTAGE_DEBUG_PORT || 9222;
const [cmd, urlPart, arg] = process.argv.slice(2);

function targets() {
  return new Promise((resolve, reject) => {
    http.get({ host: '127.0.0.1', port: PORT, path: '/json/list' }, r => {
      let d = ''; r.on('data', c => d += c);
      r.on('end', () => { try { resolve(JSON.parse(d)); } catch (e) { reject(e); } });
    }).on('error', reject);
  });
}

// One connection, commands awaited BY ID. The first version advanced a step per
// message and broke the moment CDP sent anything unsolicited -- and CDP sends
// events constantly once DOM/CSS are enabled, so it broke immediately.
function connect(target) {
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  const pending = new Map();
  let id = 0;
  const ready = new Promise((res, rej) => { ws.onopen = res; ws.onerror = () => rej(new Error('websocket failed')); });
  ws.onmessage = ev => {
    const m = JSON.parse(ev.data);
    if (m.id === undefined) return;                       // an event, not a reply
    const p = pending.get(m.id);
    if (!p) return;
    pending.delete(m.id);
    m.error ? p.reject(new Error(m.error.message)) : p.resolve(m.result);
  };
  return {
    ready,
    send(method, params) {
      const mine = ++id;
      return new Promise((resolve, reject) => {
        pending.set(mine, { resolve, reject });
        ws.send(JSON.stringify({ id: mine, method, params: params || {} }));
      });
    },
    close() { ws.close(); }
  };
}

const die = msg => { console.error(msg); process.exit(1); };

(async () => {
  let list;
  try { list = await targets(); }
  catch (e) {
    die('no debug port on 127.0.0.1:' + PORT + ' (' + e.message + ')\n' +
      'Put the port number in wintage-debug.port next to the installed shim and restart the app.');
  }
  const pages = list.filter(t => t.type === 'page');

  if (!cmd || cmd === 'targets') {
    for (const t of pages) console.log('[' + t.type + '] ' + JSON.stringify(t.title) + '  ' + t.url);
    return;
  }

  const target = pages.find(t => t.url.includes(urlPart || ''));
  if (!target) die('no page whose url contains ' + JSON.stringify(urlPart));

  const cdp = connect(target);
  await cdp.ready;
  console.log('attached: ' + target.url);

  if (cmd === 'eval') {
    const expression = fs.readFileSync(arg, 'utf8');
    const r = await cdp.send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
    if (r.exceptionDetails) console.log('EXCEPTION: ' + JSON.stringify(r.exceptionDetails.exception).slice(0, 500));
    else console.log(typeof r.result.value === 'string' ? r.result.value : JSON.stringify(r.result.value, null, 1));
    cdp.close();
    return;
  }

  if (cmd === 'rules') {
    await cdp.send('DOM.enable');
    await cdp.send('CSS.enable');
    const doc = await cdp.send('DOM.getDocument', { depth: 1 });
    const found = await cdp.send('DOM.querySelector', { nodeId: doc.root.nodeId, selector: arg });
    if (!found.nodeId) { console.log('selector matched nothing: ' + arg); cdp.close(); return; }
    const res = await cdp.send('CSS.getMatchedStylesForNode', { nodeId: found.nodeId });
    if (res.inlineStyle && res.inlineStyle.cssText) console.log('INLINE: ' + res.inlineStyle.cssText.slice(0, 300));
    console.log('--- matched rules (later beats earlier at equal weight) ---');
    for (const e of res.matchedCSSRules || []) {
      const props = e.rule.style.cssProperties
        .filter(p => p.value && !/^\s*$/.test(p.value))
        .map(p => p.name + ':' + p.value + (p.important ? ' !' : ''));
      if (!props.length) continue;
      console.log('[' + e.rule.origin + '] ' + e.rule.selectorList.text.slice(0, 90));
      console.log('        ' + props.join('; ').slice(0, 240));
    }
    cdp.close();
    return;
  }

  cdp.close();
  die('usage: targets | rules <url-part> <selector> | eval <url-part> <file.js>');
})().catch(e => die(String(e.message || e)));
