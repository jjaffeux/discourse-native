import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import test from 'node:test';
import {finalSanitize} from '../src/final-sanitize.js';

const corpus = JSON.parse(readFileSync(new URL('post-corpus.json', import.meta.url)));
let attempts = 0;
const forbidden = () => { attempts++; throw Error('Host capability access'); };
const sandbox = vm.createContext({fetch:forbidden, XMLHttpRequest:forbidden,
  require:forbidden, WebSocket:forbidden});
vm.runInContext(readFileSync(new URL('../../assets/cooking.js', import.meta.url), 'utf8'), sandbox);
function cook(fixture) {
  const snapshot = structuredClone({...corpus.snapshot, ...fixture.snapshot});
  for (const [owner, settings] of Object.entries(fixture.pluginSettings || {})) {
    Object.assign(snapshot.pluginContext[owner].settings, settings);
  }
  const modules = corpus.configuration.modules.filter(m => !(fixture.omitModules || []).includes(m.id));
  const result = JSON.parse(sandbox.cook(JSON.stringify({raw:fixture.raw,
    profile:fixture.profile || 'post', configuration:{modules}, snapshot})));
  assert.equal(result.failure, undefined, JSON.stringify(result));
  assert.equal(attempts, 0);
  return result.html;
}
for (const fixture of corpus.fixtures) test(fixture.name, () => {
  const html = cook(fixture);
  if (fixture.html !== undefined) assert.equal(html, fixture.html);
  for (const value of fixture.includes || []) assert.ok(html.includes(value), `${html} missing ${value}`);
  for (const value of fixture.excludes || []) assert.ok(!html.includes(value), `${html} includes ${value}`);
  for (const [value,count] of Object.entries(fixture.counts || {})) assert.equal(html.split(value).length - 1, count, html);
});
test('poll IDs match an independent UTF-8 JSON MD5 oracle', () => {
  for (const text of ['Café', '猫 😺', 'é é', 'العربية', '👨‍👩‍👧‍👦', 'quote " and \\ slash']) {
    const hash = createHash('md5').update(JSON.stringify([text]), 'utf8').digest('hex');
    assert.ok(cook({raw:`[poll]\n* ${text}\n* other\n[/poll]`}).includes(`data-poll-option-id="${hash}"`), text);
  }
});
test('post feature settings and HTML policy do not leak between cooks', () => {
  const raw = '[poll]\n* A\n* B\n[/poll]';
  assert.ok(cook({raw}).includes('class="poll"'));
  assert.ok(!cook({raw,pluginSettings:{poll:{poll_enabled:false}}}).includes('class="poll"'));
  assert.ok(cook({raw}).includes('class="poll"'));
  const details = '[details="More" open]\nBody\n[/details]';
  assert.ok(cook({raw:details}).includes('<details open>'));
  assert.ok(!cook({raw:details,omitModules:['details']}).includes('<details'));
});
test('reviewed details boolean attribute is unavailable on other tags', () => {
  assert.equal(finalSanitize('<details open><summary>More</summary></details>', [{details:['open'],summary:[]}]), '<details open><summary>More</summary></details>');
  for (const tag of ['div','span','a','summary']) assert.throws(() => finalSanitize(`<${tag} open>`, [{[tag]:['open']}]), /Unsafe policy attribute/);
  assert.throws(() => finalSanitize('', [{div:['data-custom-url']}]), /Unsafe policy attribute/);
});
