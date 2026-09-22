import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import test from 'node:test';

const sandbox = vm.createContext({});
vm.runInContext(readFileSync(new URL('../../assets/cooking.js', import.meta.url), 'utf8'), sandbox);
function cook(raw, enabled = true) {
  const result = JSON.parse(sandbox.cook(JSON.stringify({
    raw, profile: 'post',
    configuration: { modules: [{ id: 'checklist', owner: 'cooking', version: '1', profiles: ['post'], enabledSetting: 'checklist_enabled' }] },
    snapshot: { pluginContext: { cooking: { settings: { checklist_enabled: enabled } } } },
  })));
  assert.equal(result.failure, undefined, JSON.stringify(result));
  return result.html;
}

test('upstream checklist states cook with ordinary Markdown content', () => {
  const html = cook('[ ] Open\n[x] **Done**\n[X] Permanent\n[] Empty\n\n- [ ] Bullet');
  assert.equal(html.match(/chcklst-box/g).length, 5, html);
  assert.equal(html.match(/chcklst-box checked/g).length, 2, html);
  assert.ok(html.includes('<strong>Done</strong>'), html);
  assert.ok(html.includes('<ul>'), html);
});

test('checklists respect site settings without leaking between requests', () => {
  assert.ok(cook('[ ] Task').includes('chcklst-box'));
  assert.ok(!cook('[ ] Task', false).includes('chcklst-box'));
  assert.ok(cook('[x] Task').includes('chcklst-box checked'));
});

test('code, escapes and links do not become task controls', () => {
  for (const raw of ['`[x] Code`', '```\n[ ] Code\n```', '    [ ] Code', '\\[ ] Escaped', '[x](https://example.com)', '[x] Link\n\n[x]: https://example.com']) {
    assert.ok(!cook(raw).includes('chcklst-box'), raw);
  }
});
