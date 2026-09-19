import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import test from 'node:test';
const sandbox=vm.createContext({});
vm.runInContext(readFileSync(new URL('../../assets/cooking.js',import.meta.url),'utf8'),sandbox);
const modules=['chat-source','chat-slash-format','chat-html-inline','chat-transcript','discourse-local-dates','spoiler-alert','offline-missing-uploads'].map(id=>({id}));
function cook(raw,context={},snapshot={},profile='chat') {
 const result=JSON.parse(sandbox.cook(JSON.stringify({raw,profile,configuration:{modules},snapshot:{baseUrl:'https://a.test',context,pluginContext:{'discourse-local-dates':{settings:{discourse_local_dates_enabled:true}}},...snapshot}})));
 assert.equal(result.failure,undefined,JSON.stringify(result));return result.html;
}
test('Chat slash recognition and single-paragraph formatting',()=>{
 assert.equal(cook('/me **waves**',{authorUsername:'<Alice>'}),'<p><em class="chat-message-action">&lt;Alice&gt; <strong>waves</strong></em></p>');
 assert.equal(cook('/shrug'),'<p>¯\\_(ツ)_/¯</p>');
 assert.equal(cook('/tableflip wow'),'<p>wow (╯°□°)╯︵ ┻━┻</p>');
 assert.match(cook('/ME waves',{authorUsername:'A'}),/\/ME waves/);
 assert.match(cook('/me waves\n',{authorUsername:'A'}),/\/me waves/);
 assert.match(cook('/me - item',{authorUsername:'A'}),/^<ul>/);
 assert.doesNotMatch(cook('/me - item',{authorUsername:'A'}),/chat-message-action/);
});
test('ordinary and bot dialects',()=>{
 assert.equal(cook('# Heading'),'<p># Heading</p>');
 assert.match(cook('# Heading',{authorId:-1}),/<h1>/);
 assert.match(cook('<kbd onclick="bad()">K</kbd> <mark>M</mark>'),/<kbd>K<\/kbd> <mark>M<\/mark>/);
 assert.doesNotMatch(cook('[details=Title]Secret[/details]'),/<details/);
});
test('transcript nested chat dialect',()=>{
 const html=cook('[chat quote="Alice;1;2026-01-01T12:00:00Z" channel="General" channelId="2"]\n# Heading\n[/chat]',{}, {},'post');
 assert.match(html,/class="chat-transcript"/);assert.match(html,/<p># Heading<\/p>/);assert.match(html,/data-message-id="1"/);
});
test('local dates normalize and use UTC with fixed locale',()=>{
 const html=cook('[date=2026-3-29 time=02:30:00 timezone="Europe/Paris"]');
 assert.match(html,/data-date="2026-03-29"/);assert.match(html,/2026-03-29T01:30:00Z/);
 const french=cook('[date=2026-3-29 format="LL"]',{locale:'fr'});
 assert.match(french,/29 mars 2026/);
 assert.match(cook('[date=2026-3-29 format="LL"]'),/March 29, 2026/);
});
test('nested transcript hashtag priority differs from its post parent',()=>{
 const tag={type:'tag',slug:'same',ref:'same',id:1,text:'Tag',relative_url:'/tag/same'};
 const channel={type:'channel',slug:'same',ref:'same',id:2,text:'Channel',relative_url:'/chat/c/-/2'};
 const html=cook('#same\n\n[chat quote="Alice;1;2026-01-01" channelId="2"]\n#same\n[/chat]',{}, {hashtags:{'same::tag':tag,'same::channel':channel}},'post');
 assert.match(html,/href="\/tag\/same"/);assert.match(html,/href="\/chat\/c\/-\/2"/);
});
test('transcript metadata is text and cannot inject HTML',()=>{
 const html=cook('[chat quote="Alice;1;2026-01-01" channel="<img src=x onerror=bad()>" channelId="javascript:bad()" threadTitle="<script>bad()</script>"]\nhello\n[/chat]');
 assert.doesNotMatch(html,/<img|<script|href="javascript/);assert.match(html,/&lt;img/);
});
