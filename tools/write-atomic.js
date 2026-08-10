#!/usr/bin/env node
'use strict';

// Shared atomic file write for the install tools (was duplicated across
// install-obs.js, install-windows-theme.js and install-terminal.js): write to a
// temp sibling then rename, so a crash never leaves a half-written target.
// The pid suffix keeps concurrent runs from colliding on the temp name; the
// explicit utf8 encoding makes the byte output independent of platform default.

const fs = require('fs');
const path = require('path');

function writeAtomic(file, content) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temp = `${file}.wintage-tmp-${process.pid}`;
  fs.writeFileSync(temp, content, 'utf8');
  fs.renameSync(temp, file);
}

module.exports = { writeAtomic };
