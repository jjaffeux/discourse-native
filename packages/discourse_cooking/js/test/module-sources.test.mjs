import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, symlinkSync, realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash } from 'node:crypto';
import { loadModuleCatalog, pluginSourceImports } from '../module-sources.mjs';
const digest = text => createHash('sha256').update(text).digest('hex');

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'trusted-cooking-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const dir = join(root, 'lib/src/plugins/fixture/tool/cooking');
  mkdirSync(dir, { recursive: true });
  const source = 'export function setup() {}';
  writeFileSync(join(dir, 'fixture.js'), source);
  const module = { id: 'fixture', owner: 'fixture', version: '1', stage: 'syntax', source: 'fixture.js', inputs: {'fixture.js': digest(source)}, policy: {} };
  const entry = { owner: 'fixture', manifest: 'lib/src/plugins/fixture/tool/cooking/module.json' };
  const save = () => { const text = JSON.stringify(module); writeFileSync(join(dir,'module.json'),text); entry.sha256 = digest(text); };
  save();
  return { root, dir, entry, module, save, load: () => loadModuleCatalog([entry], root, join(root,'packages/discourse_cooking/js')) };
}
test('trusted plugin source retains owner and resolves only its hashed source', t => {
  const f = fixture(t);
  assert.equal(f.load()[0].owner, 'fixture');
  assert.match(f.load()[0].importPath, /lib\/src\/plugins\/fixture\/tool\/cooking\/fixture.js$/);
});
test('foreign owner and unhashed or modified sources are rejected', t => {
  const f = fixture(t);
  f.entry.owner = 'foreign';
  assert.throws(f.load, /Foreign owner/);
  f.entry.owner = 'fixture';
  f.module.inputs = {}; f.save();
  assert.throws(f.load, /hash every source/);
  f.module.inputs = {'fixture.js': digest('old')}; f.save();
  assert.throws(f.load, /hash mismatch/);
});
test('manifest traversal, source traversal and symlink escape are rejected', t => {
  const f = fixture(t);
  const original = f.entry.manifest;
  f.entry.manifest = 'lib/src/plugins/fixture/tool/cooking/../../other/module.json';
  assert.throws(f.load, /manifest path/);
  f.entry.manifest = original;
  f.module.source = '../foreign.js'; f.save();
  assert.throws(f.load, /invalid plugin cooking source/);
  f.module.source = 'escape.js';
  const escaped = join(f.root,'outside.js'); writeFileSync(escaped,'export function setup() {}');
  symlinkSync(escaped,join(f.dir,'escape.js'));
  f.module.inputs = {'escape.js': digest('export function setup() {}')}; f.save();
  assert.throws(f.load, /escapes its owner/);
});

test('a plugin cannot import a source omitted from its hash declaration', t => {
  const f = fixture(t);
  const resolve = pluginSourceImports(f.load(), f.root);
  assert.equal(resolve(join(f.dir,'fixture.js'),'./fixture.js'),realpathSync(join(f.dir,'fixture.js')));
  writeFileSync(join(f.dir,'unlisted.js'),'export const secret = true;');
  assert.throws(()=>resolve(join(f.dir,'fixture.js'),'./unlisted.js'),/Unhashed/);
  assert.throws(()=>resolve(join(f.dir,'fixture.js'),'../foreign.js'),/inside their owner/);
  assert.throws(()=>resolve(join(f.dir,'fixture.js'),'node:fs'),/inside their owner/);
});
