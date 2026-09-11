// SRC-006:R007 I/O probe (test asset, loaded via NODE_OPTIONS=--require).
// Logs every byte the Electron tool reads, keyed by resolved path, so the gate
// can prove a healthy palette repaint performs ZERO archive-sized reads.
// The log target is WINTAGE_R007_IOLOG. Never shipped inside production code.
'use strict';
const fs = require('fs');
const path = require('path');
const LOG = process.env.WINTAGE_R007_IOLOG;
if (LOG) {
  const fdPaths = new Map();
  const origOpen = fs.openSync;
  fs.openSync = function (p, flags, mode) {
    const fd = origOpen.apply(this, arguments);
    try { fdPaths.set(fd, path.resolve(String(p))); } catch (e) { /* ignore */ }
    return fd;
  };
  const origRead = fs.readSync;
  fs.readSync = function (fd, buf, off, len, pos) {
    const n = origRead.apply(this, arguments);
    const p = fdPaths.get(fd);
    if (p && n > 0) {
      try { fs.appendFileSync(LOG, JSON.stringify({ op: 'read', path: p, bytes: n }) + '\n'); } catch (e) { /* ignore */ }
    }
    return n;
  };
  const origClose = fs.closeSync;
  fs.closeSync = function (fd) { try { fdPaths.delete(fd); } catch (e) { /* ignore */ } return origClose.apply(this, arguments); };
  const origReadFile = fs.readFileSync;
  fs.readFileSync = function (p, opts) {
    const data = origReadFile.apply(this, arguments);
    try { fs.appendFileSync(LOG, JSON.stringify({ op: 'readFile', path: path.resolve(String(p)), bytes: data ? data.length : 0 }) + '\n'); } catch (e) { /* ignore */ }
    return data;
  };
}
