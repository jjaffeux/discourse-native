import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { cpSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const source = fileURLToPath(new URL('..', import.meta.url));
const snapshot = JSON.parse(readFileSync(join(source, 'provenance.json')));
const sha = bytes => createHash('sha256').update(bytes).digest('hex');

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'cooking-vendor-test-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const checkout = join(root, 'upstream');
  const output = join(root, 'bundle');
  cpSync(join(source, 'vendor'), checkout, { recursive: true });
  mkdirSync(output);
  cpSync(join(source, 'vendor.mjs'), join(output, 'vendor.mjs'));
  cpSync(join(source, 'provenance.json'), join(output, 'provenance.json'));
  cpSync(join(source, 'vendor'), join(output, 'vendor'), { recursive: true });
  const git = (...args) => execFileSync('git', ['-C', checkout, ...args], { encoding: 'utf8' }).trim();
  git('init', '--quiet');
  git('add', '.');
  const commit = () => {
    git('-c', 'user.name=Cooking test', '-c', 'user.email=cooking@example.test',
      '-c', 'commit.gpgsign=false', 'commit', '--quiet', '-m', 'Fixture sources');
    return git('rev-parse', 'HEAD');
  };
  const revision = commit();
  const run = (...args) => spawnSync(process.execPath,
    [join(output, 'vendor.mjs'), checkout, ...args], { encoding: 'utf8' });
  return { checkout, output, git, commit, revision, run };
}

function files(root, prefix = '') {
  return readdirSync(join(root, prefix), { withFileTypes: true }).flatMap(entry => {
    const path = prefix ? `${prefix}/${entry.name}` : entry.name;
    return entry.isDirectory() ? files(root, path) : [path];
  }).sort();
}

test('importer preserves the complete cooking source closure and committed bytes', t => {
  const f = fixture(t);
  const paths = Object.keys(snapshot.sha256).sort();
  // A reference checkout may contain unrelated local edits. Import the commit.
  const transcript = 'plugins/chat/assets/javascripts/lib/discourse-markdown/chat-transcript.js';
  writeFileSync(join(f.checkout, transcript), 'uncommitted local edit');
  writeFileSync(join(f.output, 'vendor', 'obsolete.txt'), 'remove stale source');
  const before = f.git('status', '--porcelain');
  const result = f.run(f.revision);
  assert.equal(result.status, 0, result.stderr);
  const manifest = JSON.parse(readFileSync(join(f.output, 'provenance.json')));
  assert.equal(manifest.revision, f.revision);
  assert.deepEqual(Object.keys(manifest.sha256).sort(), paths);
  assert.deepEqual(files(join(f.output, 'vendor')), paths);
  for (const path of paths) {
    const actual = readFileSync(join(f.output, 'vendor', path));
    assert.deepEqual(actual, readFileSync(join(source, 'vendor', path)), path);
    assert.equal(manifest.sha256[path], sha(actual), path);
  }
  assert.equal(f.git('status', '--porcelain'), before);
  // Omitting the revision must replay the current pin, not an old hardcoded SHA.
  const pinned = readFileSync(join(f.output, 'provenance.json'));
  const repeated = f.run();
  assert.equal(repeated.status, 0, repeated.stderr);
  assert.deepEqual(readFileSync(join(f.output, 'provenance.json')), pinned);
});

test('missing upstream sources do not replace the existing snapshot', t => {
  const f = fixture(t);
  const missing = 'plugins/poll/assets/javascripts/lib/discourse-markdown/poll.js';
  f.git('rm', '--quiet', missing);
  const revision = f.commit();
  const before = readFileSync(join(f.output, 'provenance.json'));
  const result = f.run(revision);
  assert.notEqual(result.status, 0);
  assert.ok(result.stderr.includes(missing), result.stderr);
  assert.deepEqual(readFileSync(join(f.output, 'provenance.json')), before);
  for (const path of Object.keys(snapshot.sha256)) {
    assert.equal(sha(readFileSync(join(f.output, 'vendor', path))), snapshot.sha256[path], path);
  }
});
