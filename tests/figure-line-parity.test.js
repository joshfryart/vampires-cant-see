'use strict';
// B1 parity: the posePerson / drawLineFigure split must leave the line figure's draw-call log unchanged.
// Re-runs tools/figure-golden.mjs into a temp file and compares every entry with the v0.14.0 fixture.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const ROOT = path.resolve(__dirname, '..');
const FIXTURE = path.join(ROOT, 'tests', 'fixtures', 'figure-line-v0140.json');

test('line figure draw log is hash-identical to figure-line-v0140.json', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'vcs-fig-'));
  const out = path.join(dir, 'fig.json');
  try {
    execFileSync(process.execPath, [path.join(ROOT, 'tools', 'figure-golden.mjs'), out], { cwd: ROOT, stdio: 'pipe' });
    const want = JSON.parse(fs.readFileSync(FIXTURE, 'utf8'));
    const got = JSON.parse(fs.readFileSync(out, 'utf8'));
    assert.strictEqual(got.count, want.count);
    assert.strictEqual(got.entries.length, want.entries.length);
    for (let i = 0; i < want.entries.length; i++) {
      assert.deepStrictEqual(got.entries[i], want.entries[i], want.entries[i].key);
    }
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
