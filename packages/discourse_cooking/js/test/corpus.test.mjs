import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';
const bundle = readFileSync(new URL('../../assets/cooking.js',import.meta.url),'utf8');
const corpus = JSON.parse(readFileSync(new URL('./corpus.json',import.meta.url)));
let attempts = 0;
const forbidden = () => { attempts++; throw Error('Host capability access'); };
const context = vm.createContext({fetch:forbidden,XMLHttpRequest:forbidden,require:forbidden,WebSocket:forbidden});
assert.equal(vm.runInContext(bundle,context,{timeout:1000}),'ready');
function cook(raw,profile='post',snapshot={}) { return JSON.parse(context.cook(JSON.stringify({raw,profile,snapshot}))); }
for (const fixture of corpus) test(fixture.name,() => {
  const result = cook(fixture.raw,fixture.profile,fixture.snapshot);
  assert.deepEqual(result.warnings,[]);
  if(fixture.html !== undefined) assert.equal(result.html,fixture.html);
  for(const part of fixture.includes || []) assert.ok(result.html.includes(part),result.html);
  for(const part of fixture.excludes || []) assert.ok(!result.html.includes(part),result.html);
  assert.equal(attempts,0);
});
test('site/account snapshots and custom emoji alias cache do not leak',()=>{
  const raw=':private: ^^ https://example.com/foo';
  const a={siteId:'a',accountId:'one',customEmoji:{private:'https://a.test/private.png'},customEmojiTranslation:{'^^':'private'}};
  assert.ok(cook(raw,'post',a).html.includes('https://a.test/private.png'));
  const b={siteId:'b',accountId:'two'};
  assert.ok(!cook(raw,'post',b).html.includes('https://a.test/private.png'));
  assert.ok(cook(raw,'post',b).html.includes(':private: ^^'));
  const url='https://example.com/foo';
  assert.ok(cook(url,'post',{...a,oneboxes:{[url]:'<div>private secret</div>'}}).html.includes('private secret'));
  assert.ok(!cook(url,'post',b).html.includes('private secret'));
  assert.ok(!cook(url,'post',{siteId:'a',accountId:'two'}).html.includes('private secret'));
});
test('bounded readable failure and recovery',()=>{
  assert.equal(JSON.parse(context.cook('{')).failure,'engine');
  const fail = cook('<script>bad</script>','invalid');
  assert.equal(fail.failure,'engine'); assert.ok(fail.html.includes('&lt;script&gt;'));
  assert.equal(cook('x'.repeat(65537)).failure,'engine');
  assert.equal(cook('healthy').html,'<p>healthy</p>');
});
test('final URL/event policy resists hostile settings and snapshots',()=>{
  for(const payload of ['<h1 onclick="heading--x">hi</h1>', '<img src="data:image/svg+xml;base64,abc" onload="x">', '<a href="jav&#x61;script:alert(1)">link</a>', '<svg><a href="javascript:alert(1)">x</a></svg>']) {
    const out=cook('https://example.com/foo','post',{siteSettings:{allowed_href_schemes:'javascript',allowed_iframes:'https://evil.test/'},oneboxes:{'https://example.com/foo':payload}}).html;
    assert.doesNotMatch(out,/(?:onload|onclick|javascript:|data:image|<svg|<iframe)/i);
  }
});

test('normalized URL policy also covers original-URL metadata',()=>{
  const url = 'https://example.com/foo';
  for(const badUrl of ['//evil.test/p','/&#x2f;evil.test/p','jav&#x61;script:alert(1)','&#106;avascript:alert(1)','data:image/svg+xml,abc']) {
    const html = `<a href="${badUrl}" data-orig-href="${badUrl}">link</a><img src="${badUrl}" data-orig-src="${badUrl}">`;
    const out = cook(url,'post',{oneboxes:{[url]:html}}).html;
    assert.doesNotMatch(out, /(?:href|src)=/i, out);
  }
  const allowed = cook(url,'post',{oneboxes:{[url]:'<img src="https://safe.test/img.png" data-orig-src="https://safe.test/img.png">'}}).html;
  assert.ok(allowed.includes('src="https://safe.test/img.png"'));
  assert.ok(allowed.includes('data-orig-src="https://safe.test/img.png"'));
});
