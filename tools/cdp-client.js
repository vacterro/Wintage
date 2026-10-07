#!/usr/bin/env node
'use strict';

// Shared Chrome DevTools Protocol client. One implementation, two hosts:
// inspect-electron.js (the shim's opt-in debug port) and inspect-web.js (a
// user-owned Chromium/Brave started with --remote-debugging-port). The protocol
// and the failure modes are identical; only the port and the default page
// filter differ, so a second copy of `connect()` would be a second thing to fix
// when CDP changes.

const http = require('http');

const DEFAULT_PORT = 9222;
const DEFAULT_COMMAND_TIMEOUT_MS = 15000;

function envInt(name, fallback) {
  const n = Number(process.env[name]);
  return Number.isInteger(n) && n > 0 ? n : fallback;
}

function debugPort() {
  return envInt('WINTAGE_DEBUG_PORT', DEFAULT_PORT);
}

function listTargets(port) {
  return new Promise((resolve, reject) => {
    const req = http.get({ host: '127.0.0.1', port, path: '/json/list' }, r => {
      let d = '';
      r.on('data', c => { d += c; });
      r.on('end', () => {
        let parsed;
        try { parsed = JSON.parse(d); }
        catch (e) { reject(new Error('debug port returned non-JSON (' + e.message + ')')); return; }
        // A target list that is not an array means we are talking to something
        // that is not a CDP endpoint. Failing here is the difference between
        // "no debug port" and a silent empty page list, which every caller
        // would read as "the surface does not exist".
        if (!Array.isArray(parsed)) { reject(new Error('debug port did not return a target list')); return; }
        resolve(parsed);
      });
    });
    req.on('error', reject);
    req.setTimeout(5000, () => { req.destroy(new Error('debug port timed out')); });
  });
}

function pageTargets(port) {
  return listTargets(port).then(list => list.filter(t => t && t.type === 'page'));
}

// One connection, commands awaited BY ID. The first version advanced a step per
// message and broke the moment CDP sent anything unsolicited -- and CDP sends
// events constantly once DOM/CSS are enabled, so it broke immediately.
//
// BOUNDED. A Promise with no timeout and no close path is an unbounded wait: if
// the operator closes the tab, the browser quits, or the socket dies mid-command,
// the reply never comes and the caller hangs forever. That is fatal here, because
// the watch pass is *promised* to be bounded -- a tool that can hang indefinitely
// on transport death is not bounded, it just usually finishes. So every request
// carries a timer, a close or a socket error fails every outstanding request at
// once, and a settled request drops its timer so a reply that arrives at 14.9s
// cannot be reported as a timeout at 15.1s.
function connect(target, opts) {
  if (!target || typeof target.webSocketDebuggerUrl !== 'string') {
    throw new Error('target has no webSocketDebuggerUrl');
  }
  opts = opts || {};
  const WSImpl = opts.WebSocket || (typeof WebSocket !== 'undefined' ? WebSocket : null);
  if (!WSImpl) throw new Error('no WebSocket implementation available for the CDP transport');
  const defaultTimeout = Number.isInteger(opts.timeoutMs) && opts.timeoutMs > 0
    ? opts.timeoutMs
    : envInt('WINTAGE_CDP_TIMEOUT', DEFAULT_COMMAND_TIMEOUT_MS);

  const ws = new WSImpl(target.webSocketDebuggerUrl);
  const pending = new Map();
  let id = 0;
  let closed = false;
  let death = null;

  // One terminal event, one cause, every waiter. Refusing to double-fire is not
  // tidiness: a request must be rejected exactly once, or the caller's catch and
  // its unhandled-rejection handler both fire for the same failure.
  function failAll(err) {
    if (!pending.size) return;
    const waiters = [...pending.values()];
    pending.clear();
    for (const p of waiters) {
      clearTimeout(p.timer);
      p.reject(err);
    }
  }
  function terminal(err) {
    if (closed) return;
    closed = true;
    death = err;
    failAll(err);
  }

  // `ready` is settled by the socket itself, and a socket that closes or errors
  // BEFORE it ever opened must reject it -- otherwise the first `await
  // cdp.ready` in every caller hangs on a connection that is already gone. After
  // the socket is up these are no-ops.
  let openReady = null;
  const ready = new Promise((res, rej) => { openReady = { res, rej }; });
  ws.onopen = () => openReady.res();
  ws.onerror = () => {
    const err = new Error('websocket failed');
    terminal(err);
    openReady.rej(err);
  };
  ws.onclose = () => {
    const err = new Error('cdp socket closed');
    terminal(err);
    openReady.rej(err);
  };
  ws.onmessage = ev => {
    let m;
    try { m = JSON.parse(ev.data); } catch (e) { return; }
    if (m.id === undefined) return;                       // an event, not a reply
    const p = pending.get(m.id);
    if (!p) return;
    pending.delete(m.id);
    clearTimeout(p.timer);                                 // a settled request is never a timeout
    m.error ? p.reject(new Error(m.error.message)) : p.resolve(m.result);
  };

  return {
    ready,
    send(method, params, sendOpts) {
      if (closed) {
        return Promise.reject(death || new Error('cdp transport is closed'));
      }
      sendOpts = sendOpts || {};
      const ms = Number.isInteger(sendOpts.timeoutMs) && sendOpts.timeoutMs > 0
        ? sendOpts.timeoutMs
        : defaultTimeout;
      const mine = ++id;
      return new Promise((resolve, reject) => {
        const entry = { resolve, reject, timer: null };
        entry.timer = setTimeout(() => {
          if (!pending.has(mine)) return;                  // already answered
          pending.delete(mine);
          reject(new Error('cdp command timed out after ' + ms + 'ms: ' + method));
        }, ms);
        // Deliberately NOT unref'd. An unref'd timeout cannot fire once the
        // event loop would otherwise drain, so a stalled command would make the
        // process exit SILENTLY instead of rejecting -- which is the exact
        // unbounded hang this client exists to prevent, wearing a different hat.
        // Every settle path clears the timer, so it never outlives its command.
        pending.set(mine, entry);
        try { ws.send(JSON.stringify({ id: mine, method, params: params || {} })); }
        catch (e) { clearTimeout(entry.timer); pending.delete(mine); reject(e); }
      });
    },
    // Exposed so the RED control can prove cleanup actually happened rather than
    // inferring it from a rejection message.
    pendingCount() { return pending.size; },
    isClosed() { return closed; },
    close() {
      terminal(new Error('cdp client closed'));
      try { ws.close(); } catch (e) { /* already gone */ }
    }
  };
}

function die(msg) {
  console.error(msg);
  process.exit(1);
}

module.exports = { debugPort, listTargets, pageTargets, connect, die, DEFAULT_PORT, DEFAULT_COMMAND_TIMEOUT_MS };
