const fs = require('fs');
const path = require('path');
const ROOT = process.cwd();
const file = 'desktop/out/vscode/wintage-themes/package.json';
const prev = fs.readFileSync(file, 'utf8');
const tpl = fs.readFileSync('desktop/targets/vscode/template.json', 'utf8');
const version = (/\/\/ @version\s+(\d+\.\d+\.\d+)/.exec(fs.readFileSync('wintage.user.js', 'utf8')) || [, '0.0.0'])[1];
let content = tpl.replace(/\$\{version\}/g, version);
console.log('prev length:', prev.length);
console.log('content length:', content.length);
console.log('prev === content:', prev === content);
for (let i = 0; i < Math.min(prev.length, content.length); i++) {
  if (prev[i] !== content[i]) {
    console.log(`Diff at ${i}: prev charCode ${prev.charCodeAt(i)}, content charCode ${content.charCodeAt(i)}`);
    console.log(`prev string around diff: ${prev.substring(Math.max(0, i - 10), i + 10)}`);
    console.log(`content string around diff: ${content.substring(Math.max(0, i - 10), i + 10)}`);
    break;
  }
}
