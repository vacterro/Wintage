done: v1.18.0. SAIPENVIEW now RECOLOURED, not stylesheet-appended: only its own `--token:#hex` values change, so the text no longer moves (proven by masking every hex and diffing against the backup - structurally identical, 695 lines both sides). T-053 fixed for real (Git-Safe helper; this release committed+pushed under a pipe with no manual finish). Two CRLF bugs found by hunt: the apply-themes release gate could never go green on a CRLF working copy, and a test's fixture stripped nothing because JS dot does not match CR - a green test that covered nothing. `Wintage Installer.cmd` at the repo root so the GUI is obvious. T-047 closed as accepted-as-is.
remaining: nothing an agent can close alone.
awaiting: T-029 only - the 30-second live check described below.

T-029, in full: after the @sandbox raw change the userscript should still run in PAGE context, which is what lets it theme shadow DOM. Nothing offline can observe that, and it fails SILENTLY (everything else looks fine, shadow roots just stay unthemed). Open reddit.com or youtube.com with Wintage active, F12 console, run:
  [...document.querySelectorAll('*')].filter(e=>e.shadowRoot).slice(0,3).map(e=>[e.tagName, !!e.shadowRoot.querySelector('style[data-w95]')])
Every entry should read true. Then switch palette from the Tampermonkey menu and navigate to a different domain - the choice must survive.
