#!/usr/bin/env node
// Test fixture builder (SRC-006:R007 gate): a minimal VALID asar archive with
// a versioned package.json and an optional fat tail of padding, plus an
// optional fused Electron-style exe the fuse reader accepts.
//
//   node build-asar-fixture.js <asar> <version> [padBytes] [--exe <path>]
//
// Layout mirrors tools/test-electron-state.js buildAsar; the padding bytes sit
// AFTER the file data, where no asar reader looks, so any archive-sized read
// during a repaint shows up loudly in the R007 I/O probe.

'use strict';
const fs = require('fs');

const [, , asar, version, padArg] = process.argv;
const exeIdx = process.argv.indexOf('--exe');
if (!asar || !version) {
  console.error('usage: node build-asar-fixture.js <asar> <version> [padBytes] [--exe <path>]');
  process.exit(2);
}
const padBytes = padArg ? parseInt(padArg, 10) : 0;

const data = Buffer.from(JSON.stringify({ name: 'FakeApp', version, main: 'src/main/entry/index.js'.padEnd(40, '.') }, null, 2), 'utf8');
const entry = { size: data.length, offset: '0' };
const json = Buffer.from(JSON.stringify({ files: { 'package.json': entry } }), 'utf8');
const jsonLen = json.length;
const pickleSize = 8 + jsonLen + (4 - ((8 + jsonLen) % 4 || 4));
const base = 8 + pickleSize;
const head = Buffer.alloc(16);
head.writeUInt32LE(4, 0);
head.writeUInt32LE(pickleSize, 4);
head.writeUInt32LE(jsonLen, 8);
head.writeUInt32LE(jsonLen, 12);
const pad = Buffer.alloc(base - 16 - jsonLen);
const tail = padBytes > 0 ? Buffer.alloc(padBytes, 0x57) : Buffer.alloc(0);
fs.writeFileSync(asar, Buffer.concat([head, json, pad, data, tail]));

if (exeIdx > -1 && process.argv[exeIdx + 1]) {
  // Schema v1 fused exe: sentinel + count + fuses (EnableNodeCliInspectSignals
  // style stock bytes, OnlyLoadAppFromAsar enabled) exactly as the production
  // reader parses them.
  const sentinel = Buffer.from('dL7pKGdnNz796PbbjQWNKmHXBZaB9tsX', 'ascii');
  const headB = Buffer.from([1, 8]);
  const fuses = Buffer.alloc(8, 0x30);
  fuses[5] = 0x31;   // EnableEmbeddedAsarIntegrityValidation
  fuses[6] = 0x31;   // OnlyLoadAppFromAsar
  fs.writeFileSync(process.argv[exeIdx + 1], Buffer.concat([Buffer.from('MZ fake exe ', 'ascii'), sentinel, headB, fuses, Buffer.from(' padding', 'ascii')]));
}
console.log('fixture written: ' + asar + (exeIdx > -1 ? ' + ' + process.argv[exeIdx + 1] : ''));
