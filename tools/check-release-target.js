#!/usr/bin/env node
// Release target identity: does the remote the release PUSHES to name the same
// repository the userscript's own @updateURL points at?
//
// WHY THIS EXISTS. The release pushed to a remote NAMED "origin" and verified
// that the ref moved. It never asked what "origin" was, and it never compared
// that with the URL the browsers actually poll. Two live public remotes pointed
// at two different repositories, so a release could report success while every
// installed copy kept polling the other one -- forever, because the poll URL
// lives inside the installed script's own metadata.
//
// WHAT IT CHECKS. The push destination and the polled URL must name the SAME
// repository (host + path), the same branch, and the same file. Any other
// outcome is a release into a place nobody looks.
//
// EXIT: 0 = the destination and the polled URL agree.
//       1 = they disagree -- the release would publish where nobody polls.
//       2 = it could not be determined (no remote, no update URL, unreadable).

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const argv = process.argv.slice(2);
const AS_JSON = argv.includes('--json');

// An ABSENT flag and a flag given an EMPTY value are different facts. The
// truthy test below used to treat them as the same, so a caller that could
// not read its push URL (an empty string) got the gate's own re-resolution of
// the remote instead -- a different source of truth answering for a value the
// caller had already failed to obtain.
function opt(name, fallback) {
  const i = argv.indexOf(name);
  if (i < 0 || argv[i + 1] === undefined) return fallback;
  return argv[i + 1];
}

const SCRIPT = opt('--script', path.join(__dirname, '..', 'wintage.user.js'));
const BRANCH = opt('--branch', 'main');
const REMOTE = opt('--remote', 'origin');

// --- URL shapes -------------------------------------------------------------

// A polled userscript URL is <repo>/<raw marker>/<branch>/<file>. Three shapes
// occur in the wild: GitLab's "/-/raw/", the classic "/raw/" and the
// raw.githubusercontent.com host form, where the host itself carries "raw." and
// the path is <owner>/<repo>/<branch>/<file>.
function parseRawUrl(url) {
  if (!url) return null;
  const m = /^(https?):\/\/([^/]+)(\/.*)$/i.exec(url.trim());
  if (!m) return null;
  const scheme = m[1].toLowerCase();
  let host = m[2].toLowerCase();
  const rest = m[3];

  const gitlab = /^\/(.+?)\/-\/raw\/([^/]+)\/(.+)$/.exec(rest);
  if (gitlab) {
    return { scheme, host, repo: gitlab[1], branch: gitlab[2], file: gitlab[3], shape: 'gitlab' };
  }
  const classic = /^\/(.+?)\/raw\/([^/]+)\/(.+)$/.exec(rest);
  if (classic) {
    return { scheme, host, repo: classic[1], branch: classic[2], file: classic[3], shape: 'raw' };
  }
  if (host.startsWith('raw.')) {
    const parts = rest.replace(/^\//, '').split('/');
    if (parts.length >= 3) {
      // raw.githubusercontent.com serves github.com repositories; the "raw."
      // prefix sits in front of the COMPANY name, not the host.
      const repoHost = host === 'raw.githubusercontent.com' ? 'github.com' : host.slice(4);
      return {
        scheme,
        host: repoHost,
        repo: parts.slice(0, -2).join('/'),
        branch: parts[parts.length - 2],
        file: parts[parts.length - 1],
        shape: 'raw-host'
      };
    }
  }
  return null;
}

// A remote URL is <scheme>://<host>/<path>[.git] or the scp form
// git@<host>:<path>[.git].
function parseRemoteUrl(url) {
  if (!url) return null;
  const text = url.trim();
  const scp = /^(?:[^@/]+@)?([^:/]+):(?!\/)(.+)$/.exec(text);
  if (scp && !/^[a-z][a-z0-9+.-]*:\/\//i.test(text)) {
    return { scheme: 'ssh', host: scp[1].toLowerCase(), repo: scp[2].replace(/\.git$/i, '').replace(/\/+$/, '') };
  }
  const m = /^(https?|git|ssh):\/\/(?:[^@/]+@)?([^/]+)\/(.+)$/i.exec(text);
  if (!m) return null;
  return {
    scheme: m[1].toLowerCase(),
    host: m[2].toLowerCase(),
    repo: m[3].replace(/\.git$/i, '').replace(/\/+$/, '')
  };
}

function sameRepo(a, b) {
  return !!a && !!b && a.host === b.host && a.repo.toLowerCase() === b.repo.toLowerCase();
}

function sameBranch(a, b) {
  return !!a && !!b && a.branch === b.branch;
}

function sameFile(a, b) {
  return !!a && !!b && a.file === b.file;
}

function sameScheme(a, b) {
  return !!a && !!b && a.scheme === b.scheme;
}

function requireHttps(parsed, label, problems) {
  if (parsed && parsed.scheme !== 'https') {
    problems.push(label + ' must use HTTPS transport, found ' + parsed.scheme);
    return false;
  }
  return true;
}

function headerValue(src, name) {
  const m = new RegExp('^//\\s*@' + name + '\\s+(\\S+)\\s*$', 'm').exec(src);
  return m ? m[1] : null;
}

function main() {
  const report = {
    script: SCRIPT,
    remote: REMOTE,
    remoteUrl: null,
    remoteRepo: null,
    updateUrl: null,
    updateRepo: null,
    downloadUrl: null,
    downloadRepo: null,
    branch: BRANCH,
    file: path.basename(SCRIPT),
    verdict: 'UNKNOWN',
    problems: [],
    // A fact that could NOT be determined is not a mismatch. The verdict was
    // read out of the problem TEXT ("could not", "carries no", "not a ..."), so
    // a new kind of missing fact -- an empty push destination -- was read as
    // MISMATCH, and the release's own failed read of its destination looked
    // like a wrong destination. The flag says what the text used to guess.
    unknown: false,
    detail: ''
  };

  let src;
  try {
    src = fs.readFileSync(SCRIPT, 'utf8');
  } catch (e) {
    report.detail = 'could not read the userscript: ' + (e && e.message ? e.message : e);
    return finish(report, 2);
  }

  report.updateUrl = headerValue(src, 'updateURL');
  report.downloadUrl = headerValue(src, 'downloadURL');
  if (!report.updateUrl) { report.problems.push('the userscript carries no @updateURL'); report.unknown = true; }
  if (!report.downloadUrl) { report.problems.push('the userscript carries no @downloadURL'); report.unknown = true; }

  // The push destination: an explicit --remote-url wins, otherwise ask git.
  // An explicit but EMPTY value is a FAILED read, not an absent flag: the
  // release passes what it could read, and if that read produced nothing the
  // answer must be UNKNOWN rather than this gate quietly asking git a second
  // time and accepting a destination the caller never saw.
  const explicit = opt('--remote-url', null);
  if (explicit !== null) {
    report.remoteUrl = explicit;
    if (!explicit) { report.problems.push('the push destination was given as an empty URL'); report.unknown = true; }
  } else {
    try {
      report.remoteUrl = execFileSync('git', ['-C', path.join(__dirname, '..'), 'remote', 'get-url', REMOTE], {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'ignore']
      }).trim();
    } catch (e) {
      report.problems.push('could not read the push destination (git remote get-url ' + REMOTE + ')');
      report.unknown = true;
    }
  }

  const remote = parseRemoteUrl(report.remoteUrl);
  if (!remote && report.remoteUrl) { report.problems.push('the push destination is not a repository URL: ' + report.remoteUrl); report.unknown = true; }
  report.remoteRepo = remote ? remote.host + '/' + remote.repo : null;

  const update = parseRawUrl(report.updateUrl);
  const download = parseRawUrl(report.downloadUrl);
  report.updateRepo = update ? update.host + '/' + update.repo : null;
  report.downloadRepo = download ? download.host + '/' + download.repo : null;

  if (report.updateUrl && !update) { report.problems.push('the @updateURL is not a raw userscript URL: ' + report.updateUrl); report.unknown = true; }
  if (report.downloadUrl && !download) { report.problems.push('the @downloadURL is not a raw userscript URL: ' + report.downloadUrl); report.unknown = true; }

  // The release PUSH destination, @updateURL, and @downloadURL must all
  // identify the SAME canonical repository (host + path), the SAME branch, the
  // SAME file, and the SAME transport. Any disagreement is a release into a
  // place nobody polls or downloads from.
  const identities = [
    { label: 'release push destination', ...remote },
    { label: '@updateURL', ...update },
    { label: '@downloadURL', ...download }
  ].filter(i => i.host && i.repo);

  // Transport: all raw script URLs must be HTTPS.
  for (const p of [update, download]) {
    if (p) requireHttps(p, 'raw script URL', report.problems);
  }

  if (remote && update) {
    if (!sameRepo(remote, update)) {
      report.problems.push('the release publishes to ' + remote.host + '/' + remote.repo +
        ' but the clients poll ' + update.host + '/' + update.repo);
    }
    if (!sameBranch({ branch: BRANCH }, update)) {
      report.problems.push('the clients poll the ' + update.branch + ' branch but the release publishes ' + BRANCH);
    }
    if (!sameFile({ file: report.file }, update)) {
      report.problems.push('the clients poll ' + update.file + ' but the release builds ' + report.file);
    }
  }

  if (update && download) {
    if (!sameRepo(update, download)) {
      report.problems.push('@updateURL names ' + update.host + '/' + update.repo +
        ' but @downloadURL names ' + download.host + '/' + download.repo);
    }
    if (!sameBranch(update, download)) {
      report.problems.push('@updateURL points at branch ' + update.branch +
        ' but @downloadURL points at branch ' + download.branch);
    }
    if (!sameFile(update, download)) {
      report.problems.push('@updateURL points at ' + update.file +
        ' but @downloadURL points at ' + download.file);
    }
    if (!sameScheme(update, download)) {
      report.problems.push('@updateURL uses ' + update.scheme +
        ' but @downloadURL uses ' + download.scheme);
    }
  }

  // Three-way agreement: repo, branch, file across all three identities.
  if (remote && update && download) {
    const repos = new Set([remote.host + '/' + remote.repo, update.host + '/' + update.repo, download.host + '/' + download.repo]);
    const branches = new Set([BRANCH, update.branch, download.branch]);
    const files = new Set([report.file, update.file, download.file]);
    if (repos.size > 1) {
      report.problems.push('the three destinations disagree on repository: ' +
        remote.host + '/' + remote.repo + ' vs ' + update.host + '/' + update.repo + ' vs ' + download.host + '/' + download.repo);
    }
    if (branches.size > 1) {
      report.problems.push('the three destinations disagree on branch: ' +
        BRANCH + ' vs ' + update.branch + ' vs ' + download.branch);
    }
    if (files.size > 1) {
      report.problems.push('the three destinations disagree on file: ' +
        report.file + ' vs ' + update.file + ' vs ' + download.file);
    }
  }

  if (report.problems.length === 0) {
    report.verdict = 'MATCH';
    report.detail = 'the release publishes to ' + report.remoteRepo + ' and the clients poll ' +
      report.updateUrl + ' (' + BRANCH + '/' + report.file + ')';
    return finish(report, 0);
  }
  if (report.unknown) {
    report.verdict = 'UNKNOWN';
    report.detail = report.problems.join('; ');
    return finish(report, 2);
  }
  report.verdict = 'MISMATCH';
  report.detail = report.problems.join('; ');
  return finish(report, 1);
}

function finish(report, code) {
  if (AS_JSON) {
    console.log(JSON.stringify(report, null, 2));
  } else {
    console.log('release target check');
    console.log('  script      : ' + report.script);
    console.log('  push to     : ' + (report.remoteUrl || '(unknown)') + (report.remoteRepo ? '  [' + report.remoteRepo + ']' : ''));
    console.log('  update URL  : ' + (report.updateUrl || '(none)') + (report.updateRepo ? '  [' + report.updateRepo + ']' : ''));
    console.log('  download URL: ' + (report.downloadUrl || '(none)') + (report.downloadRepo ? '  [' + report.downloadRepo + ']' : ''));
    console.log('  branch/file : ' + report.branch + ' / ' + report.file);
    console.log('  verdict     : ' + report.verdict);
    console.log('  detail      : ' + report.detail);
  }
  process.exitCode = code;
  return code;
}

main();
