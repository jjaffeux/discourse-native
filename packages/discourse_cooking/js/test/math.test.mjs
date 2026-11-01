import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import test from 'node:test';
const sandbox=vm.createContext({});
vm.runInContext(readFileSync(new URL('../../assets/cooking.js',import.meta.url),'utf8'),sandbox);
function cook(raw,settings={},profile='post') {
  const result=JSON.parse(sandbox.cook(JSON.stringify({raw,profile,
    configuration:{modules:[{id:'discourse-math',owner:'discourse-math',version:'1',enabledSetting:'discourse_math_enabled'}]},
    snapshot:{pluginContext:{'discourse-math':{settings:{discourse_math_enabled:true,discourse_math_provider:'mathjax',discourse_math_enable_latex_delimiters:true,...settings}}}},
  })));
  assert.equal(result.failure,undefined,JSON.stringify(result));return result.html;
}
test('exact upstream inline boundaries, protected Markdown, and escaping',()=>{
  for(const raw of ['$x$','。$x$،','\\(x\\)','%sqrt(x)%']) {
    assert.match(cook(raw,{discourse_math_enable_asciimath:true}),/class="(?:math|asciimath)"/);
  }
  for(const raw of ['a$x$','$x$a','😀$x$','☃$x$','$x$😀','∑$x$','`$x$`','```\n$x$\n```','[link](https://example.com/$x$)','<span title="$x$">text</span>','\\$x$','$x\ny$','$$a\na\n$$"']) {
    assert.doesNotMatch(cook(raw),/class="math"/,raw);
  }
  assert.match(cook('$<script>$'),/&lt;script&gt;/);
});
test('display delimiters and incomplete multiline follow upstream',()=>{
  for(const raw of ['$$x+1$$','$$\nx+1\n$$','$$\nx+1','\\[x+1\\]','> $$\n> x+1\n> $$','- $$\n  x+1\n  $$']) assert.match(cook(raw),/<div class="math">/,raw);
  assert.match(cook('Before\n$$\nx+1\nAfter'),/x\+1\nAfter/);
  assert.doesNotMatch(cook('\\(x\\)',{discourse_math_enable_latex_delimiters:false}),/class="math"/);
});
test('provider, enablement and profile remain isolated per request',()=>{
  assert.match(cook('%sqrt(x)%',{discourse_math_enable_asciimath:true}),/asciimath/);
  assert.doesNotMatch(cook('%sqrt(x)%',{discourse_math_enable_asciimath:true,discourse_math_provider:'katex'}),/asciimath/);
  assert.doesNotMatch(cook('$x$',{discourse_math_enabled:false}),/class="math"/);
  assert.match(cook('$x$',{},'chat'),/class="math"/);
  assert.match(cook('$x$'),/class="math"/);
});
