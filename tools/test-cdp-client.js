#!/usr/bin/env node
'use strict';

// RED controls for the shared CDP transport (tools/cdp-client.js).
//
// The transport is the one place a diagnostic can hang forever, and nothing in
// the offline suite would ever notice: an unbounded Promise only misbehaves when
// the browser dies mid-command, which is precisely the moment the operator is
// not watching. So the transport is driven here against a controllable fake
// socket -- every way a real CDP endpoint can stop answering becomes a
// deterministic assertion.
//
// The broken version this guards against is the original: a `send()` that
// registers a resolver in a Map and never learns that the socket is gone.

const { connect } = require('./cdp-client.js');

let bad = 0;
function pass(label) { console.log('PASS: ' + label); }
function fail(label, detail) { console.error('FAIL: ' + label + (detail ? '\n       ' + detail : '')); bad++; }
function check(label, condition, detail) { condition ? pass(label) : fail(label, detail); }

const sleep = ms => new Promise(r => setTimeout(r, ms));

// A socket the test drives. Nothing here emulates CDP: it records what was sent
// and hands the test the exact control it needs to leave a request in flight.
class FakeSocket {
  constructor(url) {
    this.url = url;
    this.sent = [];
    this.closed = false;
    FakeSocket.last = this;
  }
  send(data) { if (this.closed) throw new Error('socket is closed'); this.sent.push(JSON.parse(data)); }
  close() { this.closed = true; if (this.onclose) this.onclose({}); }
  die() { if (this.onerror) this.onerror({}); }
  // -- driving the peer --
  open() { if (this.onopen) this.onopen({}); }
  deliver(message) { if (this.onmessage) this.onmessage({ data: JSON.stringify(message) }); }
  reply(id, result) { this.deliver({ id, result: result === undefined ? {} : result }); }
  failCommand(id, message) { this.deliver({ id, error: { code: -32000, message } }); }
  event(method, params) { this.deliver({ method, params: params || {} }); }
}

function client(opts) {
  opts = Object.assign({ WebSocket: FakeSocket, timeoutMs: 60 }, opts || {});
  const cdp = connect({ webSocketDebuggerUrl: 'ws://127.0.0.1:9222/devtools/page/FAKE' }, opts);
  // The fake opens on construction unless a control is exercising the
  // never-opened path. Opening it here is what lets a test `await cdp.ready`
  // without first having to reach in and drive the socket.
  if (!opts.manualOpen) FakeSocket.last.open();
  return cdp;
}

async function settled(p) {
  return p.then(v => ({ ok: true, value: v }), e => ({ ok: false, msg: e.message }));
}

async function main() {
  // ── T1: a reply resolves the request that owns that id ───────────────────
  {
    const cdp = client();
    await cdp.ready;
    const a = cdp.send('Runtime.evaluate', { expression: '1' });
    const b = cdp.send('DOM.enable');
    check('T1 send() emits one JSON message per command with a distinct id',
      FakeSocket.last.sent.length === 2 && FakeSocket.last.sent[0].id !== FakeSocket.last.sent[1].id &&
      FakeSocket.last.sent[0].method === 'Runtime.evaluate' && FakeSocket.last.sent[1].method === 'DOM.enable',
      JSON.stringify(FakeSocket.last.sent));
    FakeSocket.last.reply(FakeSocket.last.sent[1].id, { nodeId: 7 });
    FakeSocket.last.reply(FakeSocket.last.sent[0].id, { result: { value: 1 } });
    const [ra, rb] = await Promise.all([settled(a), settled(b)]);
    check('T1 a reply resolves the request carrying that id',
      ra.ok && JSON.stringify(ra.value) === '{"result":{"value":1}}' && rb.ok && rb.value.nodeId === 7,
      JSON.stringify([ra, rb]));
    cdp.close();
  }

  // ── T2: unsolicited events never advance a request ───────────────────────
  // CDP floods the socket with events as soon as DOM/CSS are enabled. A client
  // that treated one as a reply would resolve the wrong command with garbage.
  {
    const cdp = client({ timeoutMs: 5000 });
    await cdp.ready;
    const p = cdp.send('CSS.getMatchedStylesForNode', { nodeId: 1 });
    FakeSocket.last.event('DOM.documentUpdated', { nodeId: 1 });
    FakeSocket.last.event('Runtime.consoleAPICalled', { type: 'log' });
    FakeSocket.last.deliver({ method: 'Inspector.targetCrashed' });
    check('T2 unsolicited events leave the request pending',
      cdp.pendingCount() === 1, 'pending=' + cdp.pendingCount());
    const raced = await Promise.race([settled(p), sleep(30).then(() => 'still-pending')]);
    check('T2 an event-only stream never resolves the command', raced === 'still-pending', String(raced));
    FakeSocket.last.reply(FakeSocket.last.sent[0].id, { matchedCSSRules: [] });
    check('T2 the real reply still resolves it', (await settled(p)).ok);
    cdp.close();
  }

  // ── T3: a CDP error rejects the request that asked for it ────────────────
  {
    const cdp = client({ timeoutMs: 5000 });
    await cdp.ready;
    const good = cdp.send('Runtime.enable');
    const bad = cdp.send('DOM.getDocument', { depth: -1 });
    // The SECOND command is the one being failed. Failing the first instead
    // would leave `good` unsettled, which is a leak in the TEST rather than in
    // the client -- and an unhandled rejection would then take the gate down
    // before it reported anything.
    FakeSocket.last.failCommand(FakeSocket.last.sent[1].id, 'Invalid parameters');
    const rb = await settled(bad);
    check('T3 a CDP error rejects with the browser\'s own message',
      !rb.ok && /Invalid parameters/.test(rb.msg), JSON.stringify(rb));
    check('T3 the error rejects only the request that asked for it', cdp.pendingCount() === 1);
    FakeSocket.last.reply(FakeSocket.last.sent[0].id, { root: { nodeId: 3 } });
    const rg = await settled(good);
    check('T3 the sibling request is unaffected and still resolves', rg.ok && rg.value.root.nodeId === 3);
    cdp.close();
  }

  // ── T4: a dead socket rejects EVERY outstanding request ───────────────────
  // The bounded-watch contract. If this leaves a Promise pending, the operator
  // watches a frozen number and cannot tell the tool hung from the tool being
  // slow.
  {
    const cdp = client({ timeoutMs: 5000 });
    await cdp.ready;
    const inFlight = [cdp.send('Runtime.evaluate', {}), cdp.send('DOM.enable'), cdp.send('CSS.enable')];
    FakeSocket.last.close();
    const afterClose = await Promise.all(inFlight.map(settled));
    check('T4 a socket close rejects every outstanding request',
      afterClose.every(r => !r.ok && /cdp socket closed/.test(r.msg)),
      JSON.stringify(afterClose));
    check('T4 a close clears the pending table', cdp.pendingCount() === 0, 'pending=' + cdp.pendingCount());
    check('T4 a dead transport is marked closed', cdp.isClosed() === true);
    const late = await settled(cdp.send('Runtime.evaluate', {}));
    check('T4 send() after death rejects immediately instead of hanging',
      !late.ok && /cdp socket closed|closed/.test(late.msg), JSON.stringify(late));
    check('T4 a socket closing before it opens rejects ready()',
      await (async () => {
        const c2 = client({ timeoutMs: 5000, manualOpen: true });
        FakeSocket.last.close();
        return !(await settled(c2.ready)).ok;
      })(),
      'ready() resolved on a socket that never opened');
  }

  // ── T5: a terminal socket error rejects every outstanding request ─────────
  {
    const cdp = client({ timeoutMs: 5000 });
    await cdp.ready;
    const inFlight = [cdp.send('Runtime.evaluate', {}), cdp.send('DOM.enable')];
    FakeSocket.last.die();
    const after = await Promise.all(inFlight.map(settled));
    check('T5 a socket error rejects every outstanding request',
      after.every(r => !r.ok && /websocket failed/.test(r.msg)), JSON.stringify(after));
    check('T5 a socket error clears the pending table', cdp.pendingCount() === 0);
  }

  // ── T6: a stalled command times out on its own ────────────────────────────
  {
    const cdp = client({ timeoutMs: 60 });
    await cdp.ready;
    const started = Date.now();
    const stalled = await settled(cdp.send('Runtime.evaluate', { expression: 'while(1){}' }));
    const took = Date.now() - started;
    check('T6 a command that never gets a reply is rejected by its own timer',
      !stalled.ok && /timed out after 60ms: Runtime\.evaluate/.test(stalled.msg), JSON.stringify(stalled));
    check('T6 the timeout actually waited, and did not wait forever', took >= 50 && took < 2000, took + 'ms');
    check('T6 a timed-out request is dropped from the pending table', cdp.pendingCount() === 0);
    // A late reply to a timed-out command must not resolve anything.
    const before = FakeSocket.last.sent.length;
    FakeSocket.last.reply(FakeSocket.last.sent[before - 1].id, { late: true });
    check('T6 a late reply to a timed-out command resolves nothing', cdp.pendingCount() === 0);
  }

  // ── T7: a resolved request is never later reported as a timeout ──────────
  {
    let unhandled = null;
    const onUnhandled = e => { unhandled = e; };
    process.on('unhandledRejection', onUnhandled);
    const cdp = client({ timeoutMs: 60 });
    await cdp.ready;
    const p = cdp.send('Runtime.evaluate', {});
    FakeSocket.last.reply(FakeSocket.last.sent[0].id, { ok: 1 });
    const r = await settled(p);
    // Wait well past the timer: a timer left armed after the reply would fire
    // here and reject a Promise nobody is watching any more.
    await sleep(200);
    process.removeListener('unhandledRejection', onUnhandled);
    check('T7 a resolved request resolves', r.ok && r.value.ok === 1, JSON.stringify(r));
    check('T7 its timer is cleared, so no late rejection fires',
      unhandled === null, 'unhandled rejection: ' + (unhandled && unhandled.message));
    cdp.close();
  }

  // ── T8: close() cleans up without leaking a waiter ───────────────────────
  {
    const cdp = client({ timeoutMs: 5000 });
    await cdp.ready;
    const inFlight = cdp.send('Runtime.evaluate', {});
    cdp.close();
    const r = await settled(inFlight);
    check('T8 an explicit close() rejects what was in flight',
      !r.ok && /cdp client closed/.test(r.msg), JSON.stringify(r));
    check('T8 close() leaves no pending operation', cdp.pendingCount() === 0);
    check('T8 close() marks the transport closed', cdp.isClosed() === true);
  }

  // ── T9: a send that cannot even be written is refused, not orphaned ───────
  {
    const cdp = client({ timeoutMs: 5000 });
    await cdp.ready;
    FakeSocket.last.closed = true;                 // the socket refuses the write
    const r = await settled(cdp.send('Runtime.enable'));
    check('T9 a socket that refuses the write rejects instead of orphaning the request',
      !r.ok && cdp.pendingCount() === 0, JSON.stringify(r) + ' pending=' + cdp.pendingCount());
    cdp.close();
  }

  if (bad) {
    console.error('\ncdp-transport gate: ' + bad + ' failure(s)');
    process.exit(1);
  }
  console.log('\ncdp-transport gate: PASS');
}

main().catch(e => { console.error('cdp-transport gate CRASHED: ' + (e && e.stack || e)); process.exit(1); });
