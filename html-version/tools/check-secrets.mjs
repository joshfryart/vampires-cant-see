// Fails (exit 1) if any tracked text file looks like it holds a key or token.
// Run before every commit/push: node tools/check-secrets.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SKIP = new Set(['.git', 'node_modules', 'shots', 'dist']);
const PATTERNS = [
  [/sk-ant-[A-Za-z0-9_-]{10,}/, 'Anthropic API key'],
  [/sk-[A-Za-z0-9]{32,}/, 'API secret key'],
  [/ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|gh[ous]_[A-Za-z0-9]{20,}/, 'GitHub token'],
  [/-----BEGIN [A-Z ]*PRIVATE KEY-----/, 'private key'],
  [/AKIA[0-9A-Z]{16}/, 'AWS key'],
  [/xox[abprs]-[A-Za-z0-9-]{10,}/, 'Slack token'],
  [/ANTHROPIC_API_KEY\s*=\s*\S+/, 'Anthropic key assignment']
];

let hits = 0;
function walk(dir) {
  for (const name of fs.readdirSync(dir)) {
    if (SKIP.has(name)) continue;
    const p = path.join(dir, name);
    const st = fs.statSync(p);
    if (st.isDirectory()) { walk(p); continue; }
    if (st.size > 2e6 || /\.(png|jpg|gif|zip|ico|woff2?)$/i.test(name)) continue;
    if (p === new URL(import.meta.url).pathname) continue;
    const text = fs.readFileSync(p, 'utf8');
    for (const [re, label] of PATTERNS) {
      if (re.test(text)) { hits++; console.error('SECRET? ' + label + ' in ' + path.relative(ROOT, p)); }
    }
  }
}
walk(ROOT);
if (hits) { console.error(hits + ' possible secret(s). Remove before committing.'); process.exit(1); }
console.log('check-secrets: clean');
