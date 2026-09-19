import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import test from 'node:test';
const sandbox=vm.createContext({});
vm.runInContext(readFileSync(new URL('../../assets/cooking.js',import.meta.url),'utf8'),sandbox);
const modules=['chat-source','chat-slash-format','chat-html-inline','chat-transcript','discourse-local-dates','spoiler-alert','offline-missing-uploads','cooking-links','cooking-bidi','cooking-media','cooking-mentions'].map(id=>({id}));
for(const fixture of JSON.parse(readFileSync(new URL('chat-corpus.json',import.meta.url)))) test(fixture.name,()=>{
 const result=JSON.parse(sandbox.cook(JSON.stringify({...fixture,configuration:{modules},snapshot:{baseUrl:'https://a.test',context:fixture.context,pluginContext:{'discourse-local-dates':{settings:{discourse_local_dates_enabled:true}}},...fixture.snapshot}})));
 assert.equal(result.failure,undefined,JSON.stringify(result));
 if(fixture.html!==undefined) assert.equal(result.html,fixture.html);
 for(const value of fixture.includes||[]) assert.ok(result.html.includes(value),`${result.html} missing ${value}`);
 for(const value of fixture.excludes||[]) assert.ok(!result.html.includes(value),`${result.html} includes ${value}`);
});
