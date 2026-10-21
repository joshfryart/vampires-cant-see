'use strict';
// C0 parity: the full-frame draw log at effects 0 must match the v0.15.0 fixture for the four fixed scenes.
// Re-runs tools/frame-golden.mjs into a temp file and compares every entry with tests/fixtures/frame-v0150.json.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const ROOT = path.resolve(__dirname, '..');
const FIXTURE = path.join(ROOT, 'tests', 'fixtures', 'frame-v0150.json');

test('full-frame draw log at effects 0 is hash-identical to frame-v0150.json', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'vcs-frame-'));
  const out = path.join(dir, 'frame.json');
  try {
    execFileSync(process.execPath, [path.join(ROOT, 'tools', 'frame-golden.mjs'), out], { cwd: ROOT, stdio: 'pipe' });
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
