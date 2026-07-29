## H-001: Empty catch blocks in userscript and installer
- **status:** reviewed
- **summary:** Found 10+ empty catch (e) { } blocks in wintage.user.js and one in tools\install-electron.js.
- **main_project_refs:** [wintage.user.js, tools/install-electron.js]
- **critical:** false
- **severity:** P3
- **verified:** grep match
- **details:** Empty catches can swallow errors silently, making debugging difficult. Should probably console.debug(e) or similar if the error is genuinely expected.
