import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
const sandbox = vm.createContext({});
vm.runInContext(readFileSync(new URL('../../assets/cooking.js', import.meta.url), 'utf8'), sandbox);
function cook(raw, enabled = true, installed = true) {
  return JSON.parse(sandbox.cook(JSON.stringify({
    raw, profile: 'post', configuration: {modules: installed ? [{id: 'discourse-policy', enabledSetting: 'policy_enabled'}] : []},
    snapshot: {pluginContext: {'discourse-policy': {settings: {policy_enabled: enabled}}}},
  }))).html;
}
test('policy syntax preserves rich content, known attributes and default version', () => {
  const html = cook('[policy groups="staff,helpers" reminder="weekly" private="true"]\n**Read this**\n[/policy]');
  assert.match(html, /class="policy"/);
  assert.match(html, /data-groups="staff,helpers"/);
  assert.match(html, /data-version="1"/);
  assert.match(html, /data-reminder="weekly"/);
  assert.match(html, /data-private="true"/);
  assert.match(html, /<strong>Read this<\/strong>/);
});
test('legacy group, opaque version and calendar attributes retain upstream meaning', () => {
  const html = cook('[policy group="staff" version="spring" renew="quarterly" renew-start="2026-11-01" accept="I agree"]\nBody\n[/policy]');
  for (const attr of ['data-group="staff"','data-version="spring"','data-renew="quarterly"','data-renew-start="2026-11-01"','data-accept="I agree"']) assert.ok(html.includes(attr),html);
});
test('disabled, absent and missing-group markup has no live policy definition', () => {
  assert.doesNotMatch(cook('[policy groups="staff"]\nBody\n[/policy]', false), /class="policy"/);
  assert.doesNotMatch(cook('[policy groups="staff"]\nBody\n[/policy]', true, false), /class="policy"/);
  assert.doesNotMatch(cook('[policy]\nBody\n[/policy]'), /class="policy"/);
});
test('quoted definitions remain nested and arbitrary data attributes are sanitized', () => {
  const html = cook('> [policy groups="staff"]\n> Quoted\n> [/policy]');
  assert.match(html, /<blockquote>[\s\S]*class="policy"[\s\S]*<\/blockquote>/);
  assert.doesNotMatch(cook('[policy groups="staff" surprise="secret"]\nBody\n[/policy]'), /data-surprise/);
});
