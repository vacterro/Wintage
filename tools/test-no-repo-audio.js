#!/usr/bin/env node
'use strict';
// T-982: no third-party audio in the git checkout.
//
// A user's chosen completion sound is THEIRS, not redistribution content: an
// earlier build tracked sounds/freebuff.wav, so the next `git add -A` could
// publish a user's audio to the world, and a re-clone wiped it. The repair
// moved the preference AND the copy to %APPDATA%\Wintage, gitignored sounds/,
// dropped the tracked wav, and taught the 33 desktop READMEs where the file
// really lives.
//
// This gate is the standing proof that the repair is still in place. It is
// cheap and offline: it reads the index, the ignore rules and the shipped
// text. It never touches a real user profile, a real install or a real sound.

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
let failures = 0;
let checks = 0;

function assertTrue(cond, label) {
  checks++;
  if (cond) {
    console.log('[PASS] ' + label);
  } else {
    failures++;
    console.log('[FAIL] ' + label);
  }
}

function git(args) {
  const r = spawnSync('git', ['-C', ROOT].concat(args), { encoding: 'utf8' });
  if (r.error) throw r.error;
  return r;
}

function gitText(args) {
  const r = git(args);
  if (r.status !== 0) {
    throw new Error('git ' + args.join(' ') + ' failed (' + r.status + '): ' + (r.stderr || '').trim());
  }
  return r.stdout;
}

function main() {
  // --- 1. No audio file is tracked, anywhere --------------------------------
  const tracked = gitText(['ls-files']).split('\n').filter(Boolean);
  const audio = tracked.filter(f => /\.(wav|mp3|ogg|m4a|flac|aac|opus|wma)$/i.test(f));
  assertTrue(audio.length === 0,
    'no audio file is tracked in the checkout' + (audio.length ? ' (found: ' + audio.join(', ') + ')' : ''));

  const trackedSounds = tracked.filter(f => /^sounds\//i.test(f));
  assertTrue(trackedSounds.length === 0,
    'nothing under sounds/ is tracked' + (trackedSounds.length ? ' (found: ' + trackedSounds.join(', ') + ')' : ''));

  // --- 2. sounds/ is really ignored -----------------------------------------
  const ignored = git(['check-ignore', '-q', '--no-index', 'sounds/freebuff.wav']);
  assertTrue(ignored.status === 0, 'sounds/ is ignored by .gitignore (git check-ignore says so)');

  const ignoreText = fs.readFileSync(path.join(ROOT, '.gitignore'), 'utf8');
  assertTrue(/^sounds\/$/m.test(ignoreText), '.gitignore carries the sounds/ rule itself');

  // --- 3. The installer copies the sound OUTSIDE the checkout ----------------
  const installer = fs.readFileSync(path.join(ROOT, 'desktop', 'WintageInstaller.ps1'), 'utf8');
  assertTrue(/\$script:fbSoundFile\s*=\s*Join-Path\s+\$script:wintageAppData\s+'freebuff-sound\.txt'/.test(installer),
    'the sound PREFERENCE is stored under %APPDATA%\\Wintage, not in the checkout');
  assertTrue(/Join-Path\s+\$script:wintageAppData\s+\('freebuff'\s*\+/.test(installer),
    'the sound COPY is written under %APPDATA%\\Wintage, not into the checkout');

  // The only mention of the checkout's sounds\\ directory may be the MIGRATION
  // that moves a user's file out of it. A write into it would undo the repair.
  const soundsRefs = installer.split(/\r?\n/).map((l, i) => [i + 1, l])
    .filter(([, l]) => /sounds/i.test(l));
  const writers = soundsRefs.filter(([, l]) => /\b(Move-Item|Copy-Item|Set-Content|Out-File|WriteAllText|New-Item)\b/.test(l));
  assertTrue(writers.length === 0,
    'the installer never writes into the checkout sounds directory' +
    (writers.length ? ' (offending line: ' + writers[0][1].trim() + ')' : ''));

  // --- 4. The READMEs point at %APPDATA%, not at a file to commit -----------
  const readmeDir = path.join(ROOT, 'desktop');
  const readmes = fs.readdirSync(readmeDir).filter(f => /^README(\..+)?\.md$/.test(f)).sort();
  assertTrue(readmes.length > 0, 'the desktop READMEs are found (' + readmes.length + ')');

  const missingPref = readmes.filter(f =>
    !fs.readFileSync(path.join(readmeDir, f), 'utf8').includes('freebuff-sound.txt'));
  assertTrue(missingPref.length === 0,
    'every desktop README names the %APPDATA% sound preference' +
    (missingPref.length ? ' (missing in: ' + missingPref.join(', ') + ')' : ''));

  const stillRepo = readmes.filter(f => /(^|[^A-Za-z])sounds[/\\]/.test(fs.readFileSync(path.join(readmeDir, f), 'utf8')));
  assertTrue(stillRepo.length === 0,
    'no desktop README points at a sound file inside the checkout' +
    (stillRepo.length ? ' (still mentions sounds/ in: ' + stillRepo.join(', ') + ')' : ''));

  const tellsToCommit = readmes.filter(f => {
    const lines = fs.readFileSync(path.join(readmeDir, f), 'utf8').split(/\r?\n/);
    return lines.some(l => /commit/i.test(l) && /\bsound|\bchime|\bwav\b|\bmp3\b/i.test(l));
  });
  assertTrue(tellsToCommit.length === 0,
    'no desktop README tells the reader to commit a sound' +
    (tellsToCommit.length ? ' (offending file: ' + tellsToCommit.join(', ') + ')' : ''));
}

try {
  main();
} catch (e) {
  failures++;
  console.log('[FAIL] the gate could not run: ' + (e && e.message ? e.message : e));
}

console.log('');
if (failures > 0) {
  console.log('TESTS FAILED (' + failures + ' of ' + checks + ' checks)');
  process.exitCode = 1;
} else {
  console.log('ALL TESTS PASSED (' + checks + ' checks)');
  process.exitCode = 0;
}
