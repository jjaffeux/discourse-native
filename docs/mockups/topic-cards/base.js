
'use strict';
const paths={
 plus:'M12 5v14M5 12h14',down:'m7 10 5 5 5-5',right:'m9 5 7 7-7 7',left:'m15 5-7 7 7 7',up:'m7 14 5-5 5 5',close:'m6 6 12 12M6 18 18 6',check:'m5 12 4 4 10-10',search:'M21 21l-5-5M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0',filter:'M4 5h16M7 11h10M10 17h4',sliders:'M4 6h7m4 0h5M4 12h2m4 0h10M4 18h10m4 0h2M15 6a2 2 0 1 1-4 0 2 2 0 0 1 4 0M10 12a2 2 0 1 1-4 0 2 2 0 0 1 4 0M18 18a2 2 0 1 1-4 0 2 2 0 0 1 4 0',panel:'M15 4v16M5 4h14a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1',message:'M20 11a8 8 0 0 1-8 8H5l-3 3V11a9 9 0 0 1 18 0Z',circle:'M20 12a8 8 0 1 1-16 0 8 8 0 0 1 16 0',pin:'m9 3 9 9-4 1-4 4-3-3 4-4-2-7ZM7 14l-4 7',lock:'M7 10V7a5 5 0 0 1 10 0v3M5 10h14v11H5zM12 14v3',bookmark:'M6 3h12v18l-6-4-6 4V3Z',calendar:'M4 5h16v16H4zM8 2v6M16 2v6M4 10h16',tag:'M3 3h7l11 11-7 7L3 10V3ZM7 7h.01',refresh:'M20 7v5h-5M4 17v-5h5M6 6a8 8 0 0 1 13 3M18 18a8 8 0 0 1-13-3',bell:'M5 17h14l-2-4V9a5 5 0 0 0-10 0v4l-2 4ZM10 21h4',sun:'M12 2v2M12 20v2M2 12h2M20 12h2M5 5l1 1M18 18l1 1M5 19l1-1M18 6l1-1M16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0',moon:'M20 15a8 8 0 0 1-11-11 9 9 0 1 0 11 11Z',phone:'M7 2h10v20H7zM11 18h2',monitor:'M3 4h18v13H3zM12 17v4M8 21h8',inbox:'M5 3h14l3 12v6H2v-6L5 3ZM2 15h6l2 3h4l2-3h6',warning:'m12 3 10 18H2L12 3ZM12 9v5M12 17h.01',arrowUp:'M12 20V4m-6 6 6-6 6 6',arrowDown:'M12 4v16m-6-6 6 6 6-6',user:'M16 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0M4 21v-2a8 8 0 0 1 16 0v2',users:'M14 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0M2 21v-2a8 8 0 0 1 16 0v2M18 4a4 4 0 0 1 0 7M19 14a7 7 0 0 1 3 5v2',globe:'M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0M3 12h18M12 3c5 5 5 13 0 18-5-5-5-13 0-18',layers:'m12 3 10 6-10 6L2 9l10-6ZM2 14l10 6 10-6',mail:'M3 5h18v14H3zM3 5l9 8 9-8',reply:'m9 5-7 7 7 7M2 12h12a7 7 0 0 1 7 7',caption:'M2 5h20v14H2zM10 10a3 3 0 1 0 0 4M18 10a3 3 0 1 0 0 4',external:'M14 3h7v7M21 3 11 13M10 3H3v18h18v-7',sort:'M8 4v16m-4-4 4 4 4-4M16 20V4m-4 4 4-4 4 4',dots:'M5 12h.01M12 12h.01M19 12h.01'};
const $=id=>document.getElementById(id);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const icon=(name,cls='')=>`<svg class="i ${cls}" viewBox="0 0 24 24" aria-hidden="true"><path d="${paths[name]||paths.circle}"/></svg>`;
const iconButton=(name,label,action,extra='')=>`<button class="icon-button" title="${esc(label)}" aria-label="${esc(label)}" data-action="${action}" ${extra}>${icon(name)}</button>`;
const avatar=(name,group=false)=>`<span class="avatar" style="--avatar:${({Sam:'#465d54',Sarah:'#675044',Joffrey:'#505377',Hannah:'#655473',Martin:'#666040',Alex:'#3e616c',Maya:'#705251',Falco:'#555c3e'})[name]||'#4e5358'}" aria-hidden="true">${group?icon('users'):esc(name.slice(0,2).toUpperCase())}</span>`;
const categoryColors={Design:'#a48bbd',Features:'#80ac8a',Support:'#d7b470',Announcements:'#779dd0',Community:'#72aca6',Engineering:'#748cc3',Accessibility:'#b486b0',UX:'#c19577'};
const cats=[{name:'Design',children:['UX','Accessibility']},{name:'Engineering',children:['Features']},{name:'Support',children:[]},{name:'Announcements',children:[]},{name:'Community',children:[]}];
const a=(name,target='Topic',group=false)=>({name,target,group});
const topics=[
 {id:101,views:1240,title:'A calmer, more focused topic list',category:'Design',child:'UX',tags:['interface','feedback','desktop','navigation'],replies:24,age:'2m',minutes:2,author:'Joffrey',unread:4,visited:false,assign:[a('Sarah'),a('Design team','Post #12',true)],excerpt:'Bring the conversations forward. Give each topic a little breathing room, and let the details stay quietly in reach.',forum:'Discourse Meta',days:0},
 {id:102,title:'Welcome to the Discourse community',category:'Announcements',tags:['getting-started'],replies:128,age:'18m',minutes:18,author:'Sam',pinned:true,visited:false,excerpt:'A few things to know before you jump in: how to find your way around, start a conversation, and make yourself at home.',forum:'Discourse Meta',days:25},
 {id:103,title:'September community call',category:'Community',tags:['events'],replies:16,age:'36m',minutes:36,author:'Hannah',unread:2,event:{month:'SEP',day:'24',summary:'Event · Thu, Sep 24 · 16:00–17:00',start:'Thursday, September 24, 2026 · 16:00',end:'Thursday, September 24, 2026 · 17:00',zone:'Europe/Paris (UTC+02:00)'},excerpt:'Join us to share what you are building, hear what is coming next, and meet other community builders.',forum:'Discourse Meta',days:2},
 {id:104,views:640,title:'Keyboard shortcuts that stay out of your way',category:'Engineering',child:'Features',tags:['keyboard','accessibility'],replies:9,age:'1h',minutes:60,author:'Martin',isNew:true,assign:[a('Alex','Post #8')],excerpt:'A small set of predictable shortcuts makes moving between topics feel natural. Arrow keys, Enter, and a clear place to return to.',forum:'Discourse Meta',days:0},
 {id:105,title:'Make long category names easier to scan',category:'Design',child:'UX',tags:['navigation','desktop'],replies:7,age:'2h',minutes:120,author:'Sarah',visited:true,bookmarked:true,excerpt:'The parent category gives useful context, especially when similar names appear in different sections of a forum.',forum:'Discourse Meta',days:4},
 {id:106,views:2310,title:'Images occasionally fail to load after reconnecting',category:'Support',tags:['bug','uploads'],replies:31,age:'3h',minutes:180,author:'Falco',unread:6,assign:[a('Support team','Topic',true)],excerpt:'The connection comes back, but a few inline images are still missing. Refreshing the topic brings them back.',forum:'Discourse Meta',days:3},
 {id:107,title:'A better home for your saved drafts',category:'Engineering',child:'Features',tags:['composer'],replies:42,age:'4h',minutes:240,author:'Maya',visited:true,newReplies:true,excerpt:'Pick up exactly where you left off, whether you were writing a new topic, a reply, or a private message.',forum:'Discourse Meta',days:11},
 {id:108,views:870,title:'Design systems workshop',category:'Design',tags:['events','design-system'],replies:12,age:'5h',minutes:300,author:'Sarah',event:{month:'OCT',day:'02',summary:'Event · Oct 2–3 · All day',start:'Friday, October 2, 2026',end:'Saturday, October 3, 2026',zone:'All-day calendar dates'},assign:[a('Design team','Topic',true),a('Maya','Post #4')],excerpt:'Two days of practical sessions on building a shared design language, with room for your questions and examples.',forum:'Discourse Meta',days:5},
 {id:109,views:347,title:'Improving screen reader announcements',category:'Design',child:'Accessibility',tags:['accessibility'],replies:18,age:'7h',minutes:420,author:'Alex',visited:true,assign:[a('Platform accessibility working group','Post #12',true)],excerpt:'Keep list navigation concise while making unread counts, category paths, and controls independently discoverable.',forum:'Discourse Meta',days:9},
 {id:110,title:'Release notes · September 2026',category:'Announcements',tags:['release'],replies:64,age:'1d',minutes:1440,author:'Sam',visited:true,closed:true,pinned:true,bookmarked:true,excerpt:'This release includes improvements to the reading experience, topic assignments, event schedules, and offline recovery.',forum:'Discourse Meta',days:15},
 {id:111,title:'What does your community’s workspace look like? ✨',category:'Community',tags:['showcase','discussion'],replies:86,age:'1d',minutes:1500,author:'Hannah',visited:false,isNew:true,excerpt:'A space to share your setup, trade small ideas, and see the different ways people make Discourse their own.',forum:'Discourse Meta',days:1},
 {id:112,title:'Search should remember the filters I already picked',category:'Engineering',child:'Features',tags:['search','feedback'],replies:21,age:'2d',minutes:2880,author:'Joffrey',visited:true,excerpt:'Switching from Latest to Unread should keep the category and tags intact, with each list remembering its scroll position.',forum:'Discourse Meta',days:17},
 {id:113,title:'Native app testing notes',category:'Engineering',tags:['desktop'],replies:5,age:'2d',minutes:3100,author:'Alex',visited:true,forum:'Discourse Meta',days:20},
 {id:114,title:'A small guide to writing useful bug reports',category:'Support',tags:['getting-started','bug'],replies:8,age:'3d',minutes:4320,author:'Maya',visited:false,forum:'Discourse Meta',days:60},
 {id:115,title:'Community gardening: keeping old discussions useful',category:'Community',tags:['discussion'],replies:53,age:'4d',minutes:5760,author:'Sam',visited:true,forum:'Discourse Meta',days:110},
 {id:116,title:'How we organize product feedback',category:'Design',tags:['feedback'],replies:35,age:'5d',minutes:7200,author:'Sarah',visited:true,forum:'Discourse Meta',days:320}
];
const messages=[
 {id:201,title:'Following up on the topic list proposal',author:'Sarah',replies:4,age:'5m',minutes:5,unread:2,excerpt:'Thanks for sharing the first pass. I left a few thoughts about the spacing and the category column.',tags:['design'],box:'inbox'},
 {id:202,title:'Your invitation to the September community call',author:'Hannah',replies:0,age:'1h',minutes:60,isNew:true,excerpt:'We would love to hear what you have been working on. Here are the details for next week.',tags:[],box:'inbox'},
 {id:203,title:'Re: Troubleshooting image uploads',author:'Falco',replies:8,age:'3h',minutes:180,visited:true,tags:['support'],box:'inbox'},
 {id:204,title:'A quick question about keyboard navigation',author:'Alex',replies:3,age:'1d',minutes:1440,visited:true,tags:[],box:'sent'},
 {id:205,title:'Thanks for helping with the release',author:'Sam',replies:2,age:'4d',minutes:5760,visited:true,tags:[],box:'archive'}
];
const drafts=[{title:'Small improvements to the reading experience',type:'New topic',icon:'layers'},{title:'A calmer, more focused topic list',type:'Reply',icon:'reply'},{title:'Notes from the community call',type:'Voice transcript',icon:'caption'},{title:'Following up with the design team',type:'Private message',icon:'mail'},{title:'Ideas for the next release',type:'New topic',icon:'layers'},{title:'Accessibility testing notes',type:'Reply',icon:'reply'}];
const params=new URLSearchParams(location.search);
const state={scene:params.get('scene')||'topics',view:params.get('state')||'ready',feed:'latest',newScope:'all',period:'year',category:'',child:'',tags:[],query:'',mode:'compact',forceCard:false,excerpts:false,theme:params.get('theme')||'dark',narrow:params.get('width')==='narrow',reader:null,split:true,cursor:101,keyboard:false,limit:12,incoming:3,notification:'Regular',signedIn:true,assignee:'Everyone',order:'default',ascending:false,forums:{'Discourse Meta':true,'Discourse Design':true,'Discourse Native':true},forumQueries:{},large:false};
let toastTimer,loadTimer,popoverOwner,dialogOwner,keyboardPrefix=0,pullStart=null,pullDistance=0,scrollPositions=new Map();
const isMessages=()=>['messages','group'].includes(state.scene);
const tagsAll=()=>[...new Set(topics.flatMap(t=>t.tags))].sort();
function baseTopics(){
 if(isMessages())return messages;
 if(state.scene==='aggregate')return topics.map((t,i)=>({...t,forum:['Discourse Meta','Discourse Design','Discourse Native'][i%3]})).filter(t=>state.forums[t.forum]&&(!state.forumQueries[t.forum]||matchesQuery(t,state.forumQueries[t.forum])));
 if(state.scene==='assigned')return topics.filter(t=>t.assign?.length&&(state.assignee==='Everyone'||t.assign.some(a=>a.name===state.assignee)));
 return topics;
}
// Sample-data adapter for the existing TopicFilterInput / TopicFilterSuggestions contract.
// Flutter must reuse those classes and server-provided filter_option_info, not this fixture engine.
function scanFilterQuery(text){
 const terms=[];let start=null,quote=null,escaped=false;
 for(let i=0;i<text.length;i++){const c=text[i];if(start===null){if(/\s/.test(c))continue;start=i;}
  if(quote){if(escaped)escaped=false;else if(c==='\\')escaped=true;else if(c===quote)quote=null;continue;}
  if((c==='"'||c==="'")&&(i===start||text[i-1]===':')){quote=c;continue;}
  if(/\s/.test(c)){terms.push({value:text.slice(start,i),start,end:i});start=null;}
 }
 if(start!==null)terms.push({value:text.slice(start),start,end:text.length});
 return {terms,atBoundary:!quote&&/\s$/.test(text)};
}
const filterSlug=value=>value.toLowerCase().replace(/\s+/g,'-');
const unquoteFilter=value=>value.replace(/^(['"])(.*)\1$/,'$2').replace(/\\(['"])/g,'$1');
function matchesQuery(t,q){return scanFilterQuery(q).terms.every(({value:token})=>{
 const prefix=token.match(/^(-=|=-|-|=)/)?.[0]||'';token=token.slice(prefix.length);
 const colon=token.indexOf(':'),key=token.slice(0,colon).toLowerCase(),value=unquoteFilter(token.slice(colon+1)).toLowerCase();let match;
 const multi=test=>value.split(',').some(part=>part.split('+').every(test));
 if(key==='status')match=value==='open'?!t.closed:value==='closed'?!!t.closed:false;
 else if(key==='in')match=value==='bookmarked'?!!t.bookmarked:value==='unread'?!!t.unread:false;
 else if(key==='category')match=[t.category,t.child,[t.category,t.child].filter(Boolean).map(filterSlug).join(':')].filter(Boolean).some(v=>filterSlug(v)===value);
 else if(key==='tag'||key==='tags')match=multi(v=>t.tags?.some(tag=>tag.toLowerCase()===v));
 else if(key==='assigned')match=value==='*'?!!t.assign?.length:multi(v=>t.assign?.some(a=>filterSlug(a.name)===v||a.name.toLowerCase()===v));
 else if(key==='created-after')match=Number.isFinite(Number(value))&&t.days<=Number(value);
 else match=[t.title,t.excerpt,...(t.tags||[]),...(t.assign||[]).map(a=>a.name)].join(' ').toLowerCase().includes(unquoteFilter(token).toLowerCase());
 return prefix.includes('-')?!match:!!match;
});}
const filterOptions=[
 {name:'assigned:',description:'Assigned to a person or group',type:'assigned',priority:1,icon:'users'},
 {name:'category:',description:'Topics in a category or subcategory',type:'category',priority:1,icon:'layers'},
 {name:'created-after:',description:'Topics created after a date',type:'date',priority:0,icon:'calendar'},
 {name:'in:bookmarked',description:'Topics you have bookmarked',priority:1,icon:'bookmark'},
 {name:'in:unread',description:'Topics with unread replies',priority:1,icon:'circle'},
 {name:'status:open',description:'Open conversations',priority:1,icon:'message'},
 {name:'status:closed',description:'Closed conversations',priority:0,icon:'lock'},
 {name:'tag:',alias:'tags:',description:'Topics carrying a tag',type:'tag',priority:1,icon:'tag'}
];
let filterCompletions=[],filterSelection=-1,filterSuggestionsOpen=false;
function filterSuggestions(text){
 const scanned=scanFilterQuery(text),last=scanned.atBoundary?null:scanned.terms.at(-1),word=last?.value||'';
 const prefix=word.match(/^(-=|=-|-|=)/)?.[0]||'',bare=word.slice(prefix.length).toLowerCase(),colon=bare.indexOf(':');
 const name=colon<0?'':bare.slice(0,colon),option=filterOptions.find(o=>o.type&&(o.name===name+':'||o.alias===name+':'));
 if(!word)return filterOptions.filter(o=>o.priority===1);
 if(option){
  const value=bare.slice(colon+1),parts=['tag','assigned'].includes(option.type)?value.split(/[,+]/):[value];
  const term=parts.at(-1),used=parts.slice(0,-1),valuePrefix=value.slice(0,value.length-term.length),full=value=>prefix+name+':'+valuePrefix+value;
  let values=[];
  if(option.type==='category')values=cats.flatMap(c=>[{term:filterSlug(c.name),label:c.name,category:c.name},...c.children.map(child=>({term:filterSlug(c.name)+':'+filterSlug(child),label:c.name+' › '+child,category:child}))]);
  if(option.type==='tag')values=tagsAll().map(tag=>({term:tag,label:tag,count:topics.filter(t=>t.tags.includes(tag)).length}));
  if(option.type==='assigned')values=[{term:'*',label:'Anyone',description:'Topics with an assignment'},...[...new Map(topics.flatMap(t=>t.assign||[]).map(a=>[a.name,a])).values()].map(a=>({term:filterSlug(a.name),label:a.name,description:a.group?'Group':'Person',icon:a.group?'users':'user'}))];
  if(option.type==='date')values=[['1','Yesterday'],['7','Last week'],['30','Last month'],['365','Last year']].map(([term,label])=>({term,label}));
  let result=values.filter(v=>!used.includes(v.term)&&(v.term.includes(term)||v.label.toLowerCase().includes(term))).map(v=>({...v,name:full(v.term),description:v.description||v.label,icon:v.icon||option.icon,keepOpen:option.type==='tag'}));
  if(option.type==='tag'&&result.some(v=>v.term===term))result.push({name:full(term+',') ,description:'Add any of these tags',icon:'plus',keepOpen:true},{name:full(term+'+'),description:'Require all of these tags',icon:'plus',keepOpen:true});
  return result.slice(0,option.type==='category'?10:20);
 }
 return filterOptions.filter(o=>(o.name.includes(bare)||o.alias?.includes(bare))&&o.name!==bare).map(o=>({...o,name:prefix+o.name})).sort((a,b)=>Number(b.name.startsWith(word))-Number(a.name.startsWith(word))||a.name.length-b.name.length).slice(0,20);
}
function renderFilterSuggestions(refresh=true){
 const input=$('filter-query'),list=$('filter-suggestions');if(!input||!list)return;
 if(refresh){filterCompletions=filterSuggestions(input.value);filterSelection=-1;filterSuggestionsOpen=filterCompletions.length>0;}
 list.hidden=!filterSuggestionsOpen;input.setAttribute('aria-expanded',String(filterSuggestionsOpen));
 if(filterSuggestionsOpen&&filterSelection>=0)input.setAttribute('aria-activedescendant','filter-option-'+filterSelection);else input.removeAttribute('aria-activedescendant');
 list.innerHTML=filterSuggestionsOpen?filterCompletions.map((v,i)=>`<button type="button" class="filter-suggestion" id="filter-option-${i}" role="option" aria-selected="${i===filterSelection}" tabindex="-1" data-filter-suggestion="${i}">${v.category?badgeCategory(v.category):icon(v.icon||'filter')}<span class="menu-label"><span>${esc(v.label||v.name)}</span>${v.description&&v.description!==v.label?`<span class="description">${esc(v.description)}</span>`:v.category?`<span class="description">${esc(v.name)}</span>`:''}</span>${v.count?`<span class="suggestion-count">${v.count}</span>`:''}</button>`).join(''):'';
 $('filter-hint').textContent=filterSuggestionsOpen?'↑ ↓ to browse · Enter or Tab to complete · Esc to dismiss':'Combine filters and text, then apply to this list.';
 if(filterSelection>=0)$('filter-option-'+filterSelection)?.scrollIntoView({block:'nearest'});
}
function acceptFilterSuggestion(index){
 const choice=filterCompletions[index],input=$('filter-query');if(!choice||!input)return;
 const scanned=scanFilterQuery(input.value),last=scanned.atBoundary?null:scanned.terms.at(-1);
 const replacement=choice.name+(choice.name.endsWith(':')||choice.keepOpen?'':' ');
 input.value=last?input.value.slice(0,last.start)+replacement:input.value+replacement;
 input.focus({preventScroll:true});input.setSelectionRange(input.value.length,input.value.length);renderFilterSuggestions();
}
function filtered(){let rows=baseTopics().filter(t=>{
 if(isMessages()){if(state.feed==='unread'&&!t.unread&&!t.isNew)return false;if(state.feed!=='unread'&&t.box!==state.feed)return false;}
 else{if(state.feed==='unread'&&!t.unread&&!t.newReplies)return false;if(state.feed==='unseen'&&t.visited)return false;if(state.feed==='new'){if(!t.isNew&&!t.unread&&!t.newReplies)return false;if(state.newScope==='topics'&&!t.isNew)return false;if(state.newScope==='replies'&&!t.unread&&!t.newReplies)return false;}}
 if(state.category&&t.category!==state.category)return false;if(state.child&&t.child!==state.child)return false;
 if(state.tags.length&&!state.tags.every(tag=>t.tags?.includes(tag)))return false;
 if(state.query&&!matchesQuery(t,state.query))return false;
 if(state.feed==='top'&&t.days>({all:Infinity,year:365,quarter:90,month:30,week:7,today:0})[state.period])return false;
 return true;
 });
 if(state.feed==='top')rows.sort((a,b)=>b.replies-a.replies);
 if(state.feed==='trending')rows.sort((a,b)=>b.replies/(b.minutes+90)-a.replies/(a.minutes+90));
 if(state.order!=='default'){const v=t=>state.order==='activity'?-t.minutes:state.order==='posts'?t.replies+1:topicViews(t);rows.sort((a,b)=>(state.order==='category'?(b.category||'').localeCompare(a.category||''):v(b)-v(a))*(state.ascending?-1:1));}
 return rows;
}
const topicViews=t=>t.views??t.replies*17;
function identity(){return JSON.stringify([state.scene,state.feed,state.newScope,state.period,state.category,state.child,state.tags,state.query]);}
function rememberScroll(){scrollPositions.set(identity(),$('list-scroll').scrollTop);}
function change(mutator,{keepReader=true}={}){clearTimeout(loadTimer);loadTimer=null;rememberScroll();mutator();state.limit=12;state.keyboard=false;if(!keepReader)state.reader=null;render();$('list-scroll').scrollTop=scrollPositions.get(identity())||0;}
function badgeCategory(name){return `<span class="category-mark" style="--category:${categoryColors[name]||'#8e8e9c'}"></span>`;}
function categoryMarkup(t,cls=''){if(!t.category)return '';return `<span class="category-cell ${cls}"><button class="category-link" data-category="${esc(t.category)}" title="Category: ${esc(t.category)}">${badgeCategory(t.category)}<span>${esc(t.category)}</span></button>${t.child?`${icon('right')}<button class="category-link" data-category="${esc(t.category)}" data-child="${esc(t.child)}" title="Subcategory: ${esc(t.child)}">${badgeCategory(t.child)}<span>${esc(t.child)}</span></button>`:''}</span>`;}
function assignmentMarkup(t){if(!t.assign?.length)return '';const first=t.assign[0];return `<span class="meta-dot"></span><span class="assignment"><span class="assignment-label">Assigned to</span>${avatar(first.name,first.group)}<span class="assignment-name" title="${esc(first.name)} · ${esc(first.target)}">${esc(first.name)}</span>${first.target!=='Topic'?`<span>${esc(first.target.replace('Post ',' '))}</span>`:''}${t.assign.length>1?`<button class="assignment-more" data-open="${t.id}" title="View all ${t.assign.length} assignments" aria-label="View all ${t.assign.length} assignments">+${t.assign.length-1}</button>`:''}</span>`;}
function rowMarkup(t){const selected=state.reader===t.id||(!state.reader&&state.cursor===t.id);return `<article class="topic ${t.visited?'visited':''} ${selected?'current':''} ${state.keyboard&&state.cursor===t.id?'keyboard':''}" data-topic="${t.id}" aria-label="${esc(t.title)}${t.unread?`, ${t.unread} unread replies`:t.isNew?', new topic':t.newReplies?', new replies':''}">
 <div class="topic-main">${t.event?`<span class="event-stamp" aria-hidden="true"><small>${t.event.month}</small><strong>${t.event.day}</strong></span>`:''}
 <div class="title-content"><div class="title-line">${t.closed?`<span class="status-icon" title="Closed" aria-label="Closed">${icon('lock')}</span>`:''}${t.pinned?`<span class="status-icon" title="Pinned" aria-label="Pinned">${icon('pin')}</span>`:''}${t.bookmarked?`<span class="status-icon bookmark" title="Bookmarked" aria-label="Bookmarked">${icon('bookmark')}</span>`:''}<a class="topic-title" href="#topic-${t.id}" data-open="${t.id}" title="${esc(t.title)}">${esc(t.title)}</a>${t.unread?`<span class="count" title="${t.unread} unread replies">${t.unread}</span>`:t.isNew?'<span class="dot" title="New topic"></span>':t.newReplies?'<span class="dot" title="New replies"></span>':''}</div>
 ${t.excerpt?`<p class="excerpt">${esc(t.excerpt)}</p>`:''}
 ${t.event?`<div class="event-meta"><button class="schedule" data-schedule="${t.id}">${esc(t.event.summary)}</button></div>`:''}
 <div class="row-metadata">${state.scene==='aggregate'?`<span class="forum-name">${esc(t.forum)}</span>`:''}${categoryMarkup(t,'mobile-meta')}${(t.tags||[]).slice(0,2).map(tag=>`<button class="tag" data-tag="${tag}" title="Filter by ${tag}">${esc(tag)}</button>`).join('')}${t.tags?.length>2?`<button class="tag-overflow" data-tags="${t.id}" title="${esc(t.tags.slice(2).join(', '))}">+${t.tags.length-2}</button>`:''}${assignmentMarkup(t)}<span class="mobile-replies" style="display:none">${t.replies} replies</span></div></div></div>
 ${isMessages()?'<span class="category-cell desktop muted">Private message</span>':categoryMarkup(t,'desktop')}
 <div class="last-poster desktop" title="Last post by ${esc(t.author)}">${avatar(t.author)}<span>${esc(t.author)}</span></div>
 <span class="num replies ${t.unread?'has-unread':''}" aria-label="${t.replies} replies">${t.replies}</span>${state.scene==='assigned'?`<span class="num views" aria-label="${topicViews(t)} views">${topicViews(t).toLocaleString('en-US')}</span>`:''}<time class="num activity" title="Last activity ${t.age} ago">${t.age}</time></article>`;}
function creationControl(){
 if(!state.signedIn)return '';
 return `<div class="create"><button class="plain-button" data-action="compose">${icon('plus')}${isMessages()?'New message':'New topic'}</button>${!isMessages()?`<button class="icon-button drafts" data-menu="drafts" title="Recent drafts" aria-label="Recent drafts, ${drafts.length} saved" aria-haspopup="dialog">${icon('down')}</button>`:''}</div>`;
}
function headerActions(){return `<div class="utility"><button class="icon-button circle" data-menu="advanced" title="Filter topics" aria-label="Filter topics" aria-haspopup="dialog" aria-expanded="false">${icon('filter')}${state.query?'<span class="indicator"></span>':''}</button><button class="icon-button circle" data-menu="display" title="Display options" aria-label="Display options" aria-haspopup="dialog" aria-expanded="false">${icon('sliders')}<span class="indicator"></span></button></div>`;}
function header(){const title=isMessages()?'Messages':state.scene==='aggregate'?'All forums':state.scene==='assigned'?'Assigned to Design':state.child||state.category||'Topics';
 $('topbar').innerHTML=`<h1 class="heading">${state.child?`<span class="heading-parent">${esc(state.category)}</span>${icon('right')}`:''}${state.category?`<button class="heading-title" data-action="category-details" title="About ${esc(title)}">${esc(title)}</button>`:`<span>${esc(title)}</span>`}</h1>${isMessages()?`<span class="separator"></span><button class="filter-trigger" data-menu="inbox" aria-haspopup="dialog">${state.scene==='group'?icon('users'):icon('user')}<span>${state.scene==='group'?'team':'Personal'}</span>${icon('down')}</button>`:''}<span class="grow"></span>${headerActions()}`;
}
// Fixture counts model tracked topics, rather than the sum of unread posts.
// In production, use the existing tracking counts and keep zero/unknown counts hidden.
function feedCount(feed){
 if(!state.signedIn)return 0;
 const rows=isMessages()?messages:topics;
 if(feed==='unread')return rows.filter(t=>isMessages()?(t.unread||t.isNew):(t.unread||t.newReplies)).length;
 if(feed==='new'&&!isMessages())return rows.filter(t=>t.isNew||t.unread||t.newReplies).length;
 return 0;
}
const periodLabels={year:'Year',quarter:'Quarter',month:'Month',week:'Week',today:'Today',all:'All time'};
const feedLabel=()=>isMessages()?({inbox:'Inbox',unread:'Unread',sent:'Sent',archive:'Archive'})[state.feed]:state.feed==='top'?`Top · ${periodLabels[state.period]}`:({latest:'Latest',unread:'Unread',new:'New',unseen:'Unseen',trending:'Trending'})[state.feed];
function toolbar(){
 $('toolbar').innerHTML=`<div class="filters"><button class="feed-pill" data-menu="feed" aria-haspopup="dialog" aria-expanded="false">${feedLabel()||'Latest'}${feedCount(state.feed)>0?`<span class="count">${feedCount(state.feed)}</span>`:''}${icon('down')}</button>${!isMessages()?`<button class="filter-trigger" data-menu="category" aria-haspopup="dialog">${state.category?badgeCategory(state.category):icon('layers')}<span>${esc(state.category||'Categories')}</span>${icon('down')}</button>${state.category&&cats.find(c=>c.name===state.category)?.children.length?`<button class="filter-trigger" data-menu="subcategory" aria-haspopup="dialog">${state.child?badgeCategory(state.child):''}<span>${esc(state.child||'Subcategories')}</span>${icon('down')}</button>`:''}<button class="filter-trigger" data-menu="tags" aria-haspopup="dialog">${icon('tag')}<span>${state.tags.length?esc(state.tags.length===1?state.tags[0]:`${state.tags.length} tags`):'Tags'}</span>${icon('down')}</button>`:''}</div>${state.scene==='aggregate'?`<button class="plain-button forum-filters" data-menu="forums" aria-haspopup="dialog">${icon('globe')}Forum filters <span class="count">${Object.values(state.forums).filter(Boolean).length}</span>${icon('down')}</button>`:''}${state.scene==='assigned'?`<div class="assignment-filters"><button class="plain-button" data-menu="assignee">${icon('users')}${esc(state.assignee)}${icon('down')}</button></div>`:''}`;
 renderContext();
}
function renderContext(){let html='';
 if(state.feed==='new'&&!isMessages()){html+=`<span class="muted">Show</span><div class="segment" aria-label="New activity scope">${['all','topics','replies'].map(k=>`<button data-new-scope="${k}" aria-pressed="${state.newScope===k}">${k[0].toUpperCase()+k.slice(1)}${k==='all'?'':`<span class="count">${topics.filter(t=>k==='topics'?t.isNew:(t.unread||t.newReplies)).length}</span>`}</button>`).join('')}</div>`;}

 if(state.query)html+=`<span class="query-chip">${esc(state.query)}<button data-action="clear-query" aria-label="Clear query">${icon('close')}</button></span>`;
 $('contextbar').innerHTML=html;
}
function skeletons(){return Array.from({length:9},(_,i)=>`<div class="topic skeleton-row" aria-hidden="true"><div class="topic-main"><span class="skeleton" style="width:${[67,85,55,73,61][i%5]}%"></span><span class="skeleton short"></span></div><span class="skeleton"></span><span class="skeleton"></span><span class="skeleton"></span>${state.scene==='assigned'?'<span class="skeleton"></span>':''}<span class="skeleton"></span></div>`).join('');}
function sortHeading(label,order,cls=''){
 if(isMessages()||state.scene==='aggregate')return `<span class="num ${cls}">${label}</span>`;
 const active=state.order===order;
 const next=active?(state.ascending?'Restore default order':`Sort by ${label.toLowerCase()}, ascending`):`Sort by ${label.toLowerCase()}, descending`;
 const status=active?`, sorted ${state.ascending?'ascending':'descending'}`:'';
 return `<span class="num ${cls}"><button class="column-sort" data-sort="${order}" aria-pressed="${active}" aria-label="${label}${status}. ${next}" title="${next}">${icon(active?(state.ascending?'arrowUp':'arrowDown'):'sort')}<span>${label}</span></button></span>`;
}
function renderRows(){const rows=filtered();const transient=['loading','empty','caught','noresults','error'].includes(state.view);$('table-shell').classList.toggle('assigned',state.scene==='assigned');$('table-shell').classList.toggle('cards',(state.forceCard||state.mode==='card'));$('table-shell').classList.toggle('messages',isMessages());$('table-shell').classList.toggle('show-excerpts',state.excerpts);
 $('columns').innerHTML=`<span>${isMessages()?'Message':'Topic'}</span><span class="category-heading">${isMessages()?'Visibility':'Category'}</span><span class="poster-heading">Last reply</span>${sortHeading('Replies','posts','replies-heading')}${state.scene==='assigned'?sortHeading('Views','views','views-heading'):''}${sortHeading('Activity','activity')}`;
 $('feed-status').innerHTML=state.view==='incoming'&&state.incoming?`<button class="incoming" data-action="incoming">${icon('arrowUp')}See ${state.incoming} new or updated topics</button>`:state.view==='refresh-error'?`<div class="error-banner" role="alert">${icon('warning')}Couldn't refresh. Your loaded topics are still available.<button data-action="retry">Retry</button></div>`:'';
 if(state.view==='loading'){$('list-scroll').innerHTML=`<span class="sr-only" role="status">Loading topics</span>${skeletons()}`;$('list-scroll').setAttribute('aria-busy','true');}
 else{$('list-scroll').removeAttribute('aria-busy');if(transient||!rows.length){const hasFilters=state.query||state.tags.length||state.category;const kind=state.view==='ready'?(hasFilters?'noresults':state.feed==='unread'?'caught':'empty'):state.view;const contents={empty:['inbox','Nothing here yet.','Start a conversation in this space.'],caught:['check','You’re all caught up.','New replies will appear here when the conversation continues.'],noresults:['search','No topics found.','Try another search or change the filters.'],error:['warning','Couldn’t load topics.','Check your connection and try again.']}[kind]||['search','No topics found.','Try another search or change the filters.'];$('list-scroll').innerHTML=`<div class="empty">${icon(contents[0])}<h2>${contents[1]}</h2><p>${contents[2]}</p>${kind==='error'?'<button class="subtle-button" data-action="retry">Retry</button>':kind==='empty'&&state.signedIn?'<button class="subtle-button" data-action="compose">New topic</button>':kind==='noresults'?'<button class="subtle-button" data-action="reset-filters">Clear filters</button>':''}</div>`;}else{$('list-scroll').innerHTML=rows.slice(0,state.limit).map(rowMarkup).join('')+(state.view==='page-error'?`<div class="error-banner" role="alert">${icon('warning')}Couldn't load more topics.<button data-action="retry-page">Retry</button></div>`:state.view==='loading-more'?'<div class="load-more" role="status"><span class="spinner"></span>Loading more topics…</div>':rows.length>state.limit?'<div class="load-more" id="page-sentinel"><span class="spinner"></span>Loading more topics…</div>':`<div class="end-note">You’ve reached the end of ${isMessages()?'your messages':'this list'}.</div>`);}}
 renderFooter();
}
function renderFooter(){const rows=filtered();const index=rows.findIndex(t=>t.id===(state.reader||state.cursor));
 $('footer').innerHTML=`${creationControl()}${state.category&&state.signedIn?`<span class="separator"></span><button class="plain-button notification" data-menu="notification" aria-haspopup="dialog" title="Category notification level">${icon('bell')}<span class="notification-label">${esc(state.notification)}</span>${icon('down')}</button>`:''}<span class="grow"></span>${state.reader?`${iconButton('up',isMessages()?'Previous message':'Previous topic','previous',!state.reader||!rows.length||index===0?'disabled':'')}${iconButton('down',isMessages()?'Next message':'Next topic','next',!state.reader||!rows.length||index>=rows.length-1?'disabled':'')}`:''}`;
}
function renderReader(){const t=[...topics,...messages].find(t=>t.id===state.reader);$('frame').classList.toggle('reading',!!t);if(!t){$('reader').innerHTML='';return;}
 $('reader').innerHTML=`<header class="reader-top">${iconButton('left','Back to topics','close-reader')}<span class="grow">${isMessages()?'Private message':'Topic preview'}</span>${t.bookmarked?`<span title="Bookmarked">${icon('bookmark')}</span>`:''}${iconButton('close','Close topic preview','close-reader')}</header><div class="reader-content"><span class="eyebrow">${t.closed?'Closed conversation':t.pinned?'Pinned conversation':isMessages()?'Personal inbox':'Discourse Meta'}</span><h1>${esc(t.title)}</h1>${categoryMarkup(t)}<div class="reader-author">${avatar(t.author)}<span>${esc(t.author)}</span><span class="muted">· ${t.age} ago</span></div><p class="reader-copy">${esc(t.excerpt||'A conversation from your community. The source list stays in place as you move between topics.')}</p>${t.event?`<button class="subtle-button schedule" data-schedule="${t.id}">${icon('calendar')}${esc(t.event.summary)}</button>`:''}${t.assign?.length?`<section class="reader-section"><h3>Assignments · ${t.assign.length}</h3>${t.assign.map(a=>`<div class="assignment-detail">${avatar(a.name,a.group)}<span>${esc(a.name)}</span><small>${esc(a.target)}</small></div>`).join('')}</section>`:''}<section class="reader-section"><h3>${t.replies} ${t.replies===1?'reply':'replies'}${t.unread?` · ${t.unread} unread`:''}</h3><p class="muted" style="font-size:12px">This is a local topic preview. Use the arrows below to try moving through the current list.</p>${t.unread||t.isNew||t.newReplies?`<button class="subtle-button" data-action="mark-read" data-id="${t.id}">${icon('check')}Finish reading sample</button>`:''}</section></div><footer class="reader-footer"><span class="grow">${t.unread?`Continue at first unread reply`:'Start of conversation'}</span>${iconButton('up','Previous topic','previous',(!filtered().length||filtered().findIndex(x=>x.id===t.id)===0)?'disabled':'')}${iconButton('down','Next topic','next',filtered().findIndex(x=>x.id===t.id)>=filtered().length-1?'disabled':'')}</footer>`;
}
function render(){header();toolbar();renderRows();renderReader();document.documentElement.dataset.theme=state.theme;$('frame').classList.toggle('narrow',state.narrow);$('frame').classList.toggle('large-text',state.large);$('scene-select').value=state.scene;$('state-select').value=state.view;$('theme-toggle').innerHTML=icon(state.theme==='dark'?'sun':'moon')+(state.theme==='dark'?'Light':'Dark');$('theme-toggle').setAttribute('aria-label',`Switch to ${state.theme==='dark'?'light':'dark'} theme`);$('width-toggle').innerHTML=icon(state.narrow?'monitor':'phone')+(state.narrow?'Desktop':'390px');$('width-toggle').setAttribute('aria-pressed',String(state.narrow));saveURL();}
function saveURL(){const p=new URLSearchParams();if(state.scene!=='topics')p.set('scene',state.scene);if(state.view!=='ready')p.set('state',state.view);if(state.theme!=='dark')p.set('theme',state.theme);if(state.narrow)p.set('width','narrow');history.replaceState(null,'',location.pathname+(p.size?'?'+p:'')+location.hash);}
function toast(message){$('toast').textContent=message;clearTimeout(toastTimer);toastTimer=setTimeout(()=>$('toast').textContent='',3200);}
function closePopover(restore=true){if($('popover').matches(':popover-open'))$('popover').hidePopover();if(popoverOwner){popoverOwner.setAttribute('aria-expanded','false');if(restore&&popoverOwner.isConnected)popoverOwner.focus({preventScroll:true});}}
function menuItem(label,attrs='',name='',selected=false,description='',count=null){return `<button class="menu-item" ${attrs}>${name?icon(name):''}<span class="menu-label">${esc(label)}${description?`<span class="description">${esc(description)}</span>`:''}</span>${count===null?(selected?icon('check','check'):''):`<span class="menu-trailing">${selected?icon('check','check'):''}${count>0?`<span class="count" aria-label="${count} ${isMessages()?'messages':'topics'}">${count}</span>`:''}</span>`}</button>`;}
function openMenu(name,owner){closePopover(false);popoverOwner=owner;$('popover').setAttribute('aria-label',({feed:'Choose topic feed',category:'Choose category',tags:'Filter by tags',display:'Display options',advanced:'Filter topics',drafts:'Recent drafts'})[name]||'Options');let html='';
 if(name==='inbox')html=`<h3>Message inbox</h3>${menuItem('Personal','data-scene="messages"','user',state.scene==='messages','Messages sent directly to you')}${menuItem('team','data-scene="group"','users',state.scene==='group','Shared group inbox')}`;
 if(name==='feed'){
  const opts=isMessages()?[['inbox','Inbox'],['unread','Unread'],...(state.scene==='group'?[]:[['sent','Sent']]),['archive','Archive']]:[['latest','Latest'],...(state.signedIn?[['unread','Unread'],['new','New'],['unseen','Unseen']]:[]),['top','Top'],['trending','Trending']];
  html=opts.map(([v,l])=>v==='top'?`<div class="feed-period-group" role="group" aria-labelledby="top-periods-label"><div class="feed-group-title" id="top-periods-label">Top</div><div class="feed-periods">${Object.entries(periodLabels).map(([period,label])=>menuItem(label,`data-period="${period}"`,'',state.feed==='top'&&state.period===period,'',0)).join('')}</div></div>`:menuItem(l,`data-feed="${v}"`,'',state.feed===v,({latest:'Recently active conversations',unread:'Replies in conversations you follow',new:'New topics and replies',unseen:'Topics you haven’t visited',trending:'Conversations gaining momentum'})[v]||'',feedCount(v))).join('');
 }
 if(name==='category'||name==='subcategory'){const sub=name==='subcategory';const values=sub?(cats.find(c=>c.name===state.category)?.children||[]):cats.map(c=>c.name);html=`<input class="menu-search" aria-label="Search categories" placeholder="Find a category…" data-menu-search><div data-menu-options>${menuItem(sub?'All subcategories':'Categories',sub?'data-subcategory=""':'data-category=""','layers',sub?!state.child:!state.category)}${values.map(v=>`<button class="menu-item" ${sub?`data-subcategory="${v}"`:`data-category="${v}"`}>${badgeCategory(v)}<span>${v}</span>${(sub?state.child:state.category)===v?icon('check','check'):''}</button>`).join('')}</div>`;}
 if(name==='tags')html=`<input class="menu-search" aria-label="Search tags" placeholder="Find tags…" data-menu-search><div data-menu-options>${menuItem('Tags','data-action="all-tags"','tag',!state.tags.length)}${tagsAll().map(tag=>`<button class="menu-item" data-toggle-tag="${tag}" role="checkbox" aria-checked="${state.tags.includes(tag)}"><span class="check-box ${state.tags.includes(tag)?'checked':''}">${state.tags.includes(tag)?icon('check'):''}</span>${esc(tag)}</button>`).join('')}</div><div class="menu-rule"></div><p class="help">Match all selected tags.</p>`;
 if(name==='display')html=`<h3>Display</h3>${menuItem('Compact',`data-mode="compact" ${state.forceCard?'disabled':''}`,'filter',!state.forceCard&&state.mode==='compact')}${menuItem('Card',`data-mode="card" ${state.forceCard?'disabled':''}`,'layers',(state.forceCard||state.mode==='card'))}<div class="menu-rule"></div>${menuItem('Show excerpts','data-action="excerpts"','message',state.excerpts)}${menuItem('Larger text','data-action="large"','caption',state.large)}<div class="menu-rule"></div><h3>Open topics</h3>${menuItem('Beside the list','data-reader-mode="split"','panel',state.split)}${menuItem('In a dialog','data-reader-mode="dialog"','layers',!state.split)}`;
 if(name==='advanced')html=`<h3>Filter topics</h3><form id="filter-form"><input id="filter-query" name="query" role="combobox" aria-label="Topic filter query" aria-autocomplete="list" aria-controls="filter-suggestions" aria-expanded="false" aria-describedby="filter-hint" placeholder="Filter by category, tag, or other criteria" value="${esc(state.query)}" autocomplete="off" spellcheck="false"><div id="filter-suggestions" role="listbox" aria-label="Filter suggestions" hidden></div><button class="subtle-button" type="submit">Apply filter</button><p class="help" id="filter-hint">Combine filters and text, then apply to this list.</p></form>`;
 if(name==='drafts')html=`<h3>Recent drafts</h3>${menuItem('All drafts','data-action="all-drafts"','layers')}<div class="menu-rule"></div>${drafts.slice(0,4).map((d,i)=>menuItem(d.title,`data-draft="${i}"`,d.icon,false,d.type)).join('')}<div class="menu-rule"></div>${menuItem(`+${Math.max(0,drafts.length-4)} other drafts · view all`,'data-action="all-drafts"')}`;
 if(name==='notification')html='<h3>Category notifications</h3>'+Object.entries({'Watching':'Notify me about all new topics and replies','Tracking':'Track unread replies in this category','Watching first post':'Notify me when a topic is created','Regular':'Notify me when mentioned or replied to','Muted':'Hide from Latest and avoid notifications'}).map(([n,d])=>menuItem(n,`data-notification="${n}"`,'bell',state.notification===n,d)).join('');
 if(name==='account')html=`<h3>Joffrey · Discourse Meta</h3>${menuItem('Preferences','data-action="preferences"','sliders')}${menuItem('Saved drafts','data-action="all-drafts"','layers')}<div class="menu-rule"></div>${menuItem('View signed-out state','data-scene="guest"','user')}`;
 if(name==='assignee')html='<h3>Assigned to</h3>'+['Everyone',...new Set(topics.flatMap(t=>(t.assign||[]).map(a=>a.name)))].map(n=>menuItem(n,`data-assignee="${esc(n)}"`,'users',state.assignee===n)).join('');
 if(name==='forums')html=`<h3>Forum filters</h3>${Object.entries(state.forums).map(([n,on])=>`<button class="menu-item" data-forum="${n}" role="checkbox" aria-checked="${on}"><span class="check-box ${on?'checked':''}">${on?icon('check'):''}</span>${n}</button><form class="forum-filter-form" data-forum-name="${n}"><input name="query" aria-label="Filter ${n}" placeholder="Use forum default" value="${esc(state.forumQueries[n]||'')}"><button class="plain-button" type="submit">Apply</button></form>`).join('')}`;
 $('popover').innerHTML=html;$('popover').showPopover();owner.setAttribute('aria-expanded','true');const rect=owner.getBoundingClientRect(),p=$('popover');p.style.left=Math.max(12,Math.min(rect.left,innerWidth-p.offsetWidth-12))+'px';const below=rect.bottom+7;const aboveAnchor=owner.closest('.footer')?.getBoundingClientRect().top??rect.top;const top=below+p.offsetHeight>innerHeight-12?aboveAnchor-p.offsetHeight-7:below;p.style.top=Math.max(12,Math.min(top,innerHeight-p.offsetHeight-12))+'px';(p.querySelector('input,button,select')||p).focus({preventScroll:true});if(name==='advanced')renderFilterSuggestions();}
function showDialog(title,content,wide=false){const wasOpen=$('dialog').open;if(!wasOpen)dialogOwner=$('popover').matches(':popover-open')?popoverOwner:document.activeElement;closePopover(false);$('dialog').className=wide?'coverage-dialog':'';$('dialog').innerHTML=`<header class="dialog-header"><h2 id="dialog-title">${esc(title)}</h2>${iconButton('close','Close dialog','close-dialog')}</header><div class="dialog-body">${content}</div>`;if(!wasOpen)$('dialog').showModal();}
function openTopic(id){state.reader=Number(id);state.cursor=Number(id);state.keyboard=false;if(state.split){renderRows();renderReader();const t=$('list-scroll').querySelector(`[data-topic="${id}"]`);t?.scrollIntoView({block:'nearest'});$('reader').querySelector('button')?.focus({preventScroll:true});}else{const t=[...topics,...messages].find(t=>t.id===Number(id));showDialog(t.title,`<p>${esc(t.excerpt||'A conversation from your community.')}</p>${t.assign?.map(a=>`<div class="assignment-detail">${avatar(a.name,a.group)}${esc(a.name)}<small>${esc(a.target)}</small></div>`).join('')||''}${t.event?`<button class="subtle-button" data-schedule="${t.id}">${icon('calendar')}${esc(t.event.summary)}</button>`:''}<p>${t.replies} replies · Last activity ${t.age} ago</p><div class="dialog-actions">${iconButton('up','Previous topic','previous',filtered().findIndex(x=>x.id===t.id)<=0?'disabled':'')}${iconButton('down','Next topic','next',filtered().findIndex(x=>x.id===t.id)>=filtered().length-1?'disabled':'')}</div>`);renderRows();}}
function scene(value){change(()=>{state.scene=value;state.feed=['messages','group'].includes(value)?'inbox':'latest';state.category=value==='category'?'Design':'';state.child=value==='category'?'UX':'';state.tags=[];state.query='';state.signedIn=value!=='guest';state.view='ready';state.assignee='Everyone';state.order='default';state.ascending=false;},{keepReader:false});}
function schedule(id){const t=topics.find(t=>t.id===Number(id));showDialog('Event schedule',`<h3>${esc(t.title)}</h3><dl class="schedule-details"><dt>Starts</dt><dd>${esc(t.event.start)}</dd><dt>Ends</dt><dd>${esc(t.event.end)}</dd><dt>Timezone</dt><dd>${esc(t.event.zone)}</dd></dl><p>Event dates are separate from the topic’s last activity.</p>`);}
function compose(draftIndex){const draft=draftIndex==null?null:drafts[draftIndex];const title=draft?'Resume draft':isMessages()?'New message':'New topic';showDialog(title,`<form id="compose-form">${isMessages()||draft?.type==='Private message'?'<label>Recipients<input name="recipients" placeholder="Username or group" required></label>':''}<label>Title<input name="title" required placeholder="What would you like to discuss?" value="${esc(draft?.title||'')}"></label><label>Message<textarea name="body" placeholder="Write your thoughts…">${draft?'A few thoughts I wanted to share with the community…':''}</textarea></label><p style="font-size:11px">Local mockup · saved drafts stay in this preview only.</p><div class="dialog-actions"><button type="button" class="plain-button" data-action="close-dialog">Cancel</button><button type="submit" class="subtle-button primary">Save draft</button></div></form>`);$('dialog').querySelector('input')?.focus();}
function coverage(){showDialog('Topic list · feature map',`<p class="coverage-intro">One design, with the existing list’s details kept in reach. Use the preview strip to switch contexts and data states. All content and actions are local examples.</p>${[
 ['Reference','Near-black canvas, a rounded continuous panel, a slim title bar, pill feed selector, circular utility buttons, muted column labels, and rounded hover / selected rows. The title is plain; creation and recent drafts sit at the bottom left.'],
 ['Header & feeds','Latest, Unread, New, Unseen, Top and Trending. Unread and New show topic counts in the menu and selected pill when positive. New keeps All / Topics / Replies with counts. Top groups all six periods directly in the feed menu, with the selected period named in the trigger. It uses no separate refinement row. Category titles retain their parent breadcrumb and details.'],
 ['Filtering','Parent category, dependent subcategory and multiple tags work together. Search remains in the app’s top-level bar. Category and tag links in each row navigate independently. The filter menu previews the existing filter autocomplete: keywords, category paths, tags, people/groups, multi-value tags and keyboard completion. In Flutter, reuse TopicFilterInput and its existing suggestion engine / site lookups. Remove the separate Filter route and sidebar entry; applying a query stays in the current list.'],
 ['Rows','Event date stamps are the only leading decoration; ordinary rows start with the title/status icons. Unread counts, new-topic and new-reply dots, read title colors, pinned / bookmarked / closed icons, Unicode titles, category breadcrumbs, two visible tags with overflow, excerpts, last-poster identity, reply count and relative activity.'],
 ['Assignments','Inline person or group identity, full name, topic or post target, and +N disclosure. The preview exposes every assignment. Unassigned rows leave no empty column.'],
 ['Events','Calendar stamp and explicit event label, timed / all-day / multi-day examples, a full schedule dialog and timezone. Activity remains independent.'],
 ['Footer','New topic and recent drafts sit at the bottom left, followed by category notifications. The up/down icon buttons open the previous/next topic in the current list, independent of browsing history. The app’s top-level bar owns refresh.'],
 ['List behavior','Every topic-list context uses the full available pane width without the 825px reading-lane limit, in Compact and Card. Headers, rows, footer and all loading / empty / error states share that width. Initial skeletons, incoming-topic banner, retained rows on refresh failure, pagination loading / retry, empty and caught-up states. Scroll positions survive feed changes; pull down at the top to refresh on touch screens. Finishing an unread sample removes it from Unread.'],
 ['Other contexts','Personal and group message inboxes, Inbox / Unread / Sent / Archive (Sent is personal only), new message, forum identity and per-forum filters in Aggregate, group-assignment member filter and sortable Replies / Views / Activity headers, signed-out controls.'],
 ['Display & access','The Display menu owns Compact and Card; remove the duplicate layout preference from app settings during implementation. Optional excerpts, light / dark, a 390px pane, larger text, responsive columns, a retained list beside the reader, native dialog focus handling, Escape, visible keyboard focus, and reduced motion. ↑ / ↓ or J / K select; Enter / O open; G then J / K open adjacent topics; Home / End jump.'],
 ['Prototype boundary','The file does not contact a server or modify the Flutter app. Search / filter grammar, account controls, creation, tracking, pagination and reader content use sample data. Native virtualization, real permissions, server queries and plugin lifecycle remain implementation requirements.']
 ].map(([h,b])=>`<div class="coverage-row"><strong>${h}</strong><span>${b}</span></div>`).join('')}`,true);}
function retry(){state.view='ready';render();toast('Topics are up to date.');}
function resetFilters(){change(()=>{state.category='';state.child='';state.tags=[];state.query='';state.feed=isMessages()?'inbox':'latest';state.view='ready';});}
function navigateTopic(delta){const rows=filtered(),i=rows.findIndex(t=>t.id===state.reader);const t=rows[i<0?0:i+delta];if(t){state.limit=Math.max(state.limit,i+delta+1);openTopic(t.id);}}
document.addEventListener('click',event=>{const b=event.target.closest('button,a[data-open],article[data-topic]');if(!b)return;if(b.disabled)return;
 if(b.dataset.menu){if($('popover').matches(':popover-open')&&popoverOwner===b)closePopover();else openMenu(b.dataset.menu,b);return;}
 const d=b.dataset;if(d.filterSuggestion!==undefined){acceptFilterSuggestion(Number(d.filterSuggestion));return;}if(d.open){if(event.metaKey||event.ctrlKey||event.shiftKey)return;event.preventDefault();closePopover(false);openTopic(d.open);return;}if(d.topic){openTopic(d.topic);return;}
 if(d.category!==undefined){closePopover(false);change(()=>{state.category=d.category;state.child=d.child||'';state.view='ready';});return;}
 if(d.subcategory!==undefined){closePopover(false);change(()=>{state.child=d.subcategory;});return;}
 if(d.tag){if($('dialog').open)$('dialog').close();change(()=>{state.tags=[d.tag];});return;}
 if(d.toggleTag){const original=$('toolbar').querySelector('[data-menu="tags"]');change(()=>{state.tags=state.tags.includes(d.toggleTag)?state.tags.filter(t=>t!==d.toggleTag):[...state.tags,d.toggleTag];});openMenu('tags',$('toolbar').querySelector('[data-menu="tags"]')||original);return;}
 if(d.tags){const t=topics.find(t=>t.id===Number(d.tags));showDialog('Topic tags',`<p>${esc(t.title)}</p>${t.tags.map(tag=>menuItem(tag,`data-tag="${tag}"`,'tag')).join('')}`);return;}
 if(d.schedule){schedule(d.schedule);return;}if(d.scene){closePopover(false);scene(d.scene);return;}
 if(d.feed){closePopover(false);change(()=>state.feed=d.feed);return;}if(d.newScope){change(()=>state.newScope=d.newScope);return;}if(d.period){closePopover(false);change(()=>{state.feed='top';state.period=d.period;});return;}
 if(d.mode){if(state.forceCard)return;closePopover(false);if($('dialog').open)$('dialog').close();const offset=$('list-scroll').scrollTop;state.mode=d.mode;render();$('list-scroll').scrollTop=offset;return;}
 if(d.readerMode){state.split=d.readerMode==='split';closePopover();return;}
 if(d.query!==undefined){closePopover(false);change(()=>state.query=d.query);return;}
 if(d.draft!==undefined){compose(Number(d.draft));return;}if(d.notification){state.notification=d.notification;closePopover(false);renderFooter();toast(`${state.category} notifications: ${d.notification}`);return;}
 if(d.assignee){closePopover(false);change(()=>state.assignee=d.assignee);return;}if(d.sort){
  change(()=>{if(state.order!==d.sort){state.order=d.sort;state.ascending=false;}else if(!state.ascending){state.ascending=true;}else{state.order='default';state.ascending=false;}});
  const sortControls = [...document.querySelectorAll(`[data-sort="${d.sort}"]`)];
  sortControls.find(control => control.getClientRects().length)?.focus({preventScroll:true});
  toast(state.order==='default'?'Default order restored.':`${({category:'Category',posts:'Replies',views:'Views',activity:'Activity'})[state.order]}: ${state.ascending?'ascending':'descending'}.`);return;
 }
 if(d.forum){state.forums[d.forum]=!state.forums[d.forum];renderRows();toolbar();openMenu('forums',$('toolbar').querySelector('[data-menu="forums"]'));return;}
 const action=d.action;if(!action)return;
 switch(action){
 case 'theme':state.theme=state.theme==='dark'?'light':'dark';render();break;
 case 'width':state.narrow=!state.narrow;render();break;
 case 'coverage':coverage();break;
 case 'close-dialog':$('dialog').close();break;
 case 'compose':compose();break;
 case 'all-drafts':showDialog('Saved drafts',drafts.map((dr,i)=>menuItem(dr.title,`data-draft="${i}"`,dr.icon,false,dr.type)).join(''));break;
 case 'clear-query':change(()=>state.query='');break;
 case 'all-tags':closePopover(false);change(()=>state.tags=[]);break;
 case 'reset-filters':resetFilters();break;
 case 'excerpts':state.excerpts=!state.excerpts;closePopover(false);render();break;
 case 'large':state.large=!state.large;closePopover(false);render();break;
 case 'close-reader':{const id=state.reader;state.reader=null;render();requestAnimationFrame(()=>$('list-scroll').querySelector(`[data-open="${id}"]`)?.focus({preventScroll:true}));break;}
 case 'previous':navigateTopic(-1);break;case 'next':navigateTopic(1);break;
 case 'mark-read':{const t=[...topics,...messages].find(t=>t.id===Number(d.id));t.unread=0;t.isNew=false;t.newReplies=false;t.visited=true;toolbar();renderRows();renderReader();toast('Sample topic read. The unread list has updated.');break;}
 case 'retry':state.view='loading';render();setTimeout(retry,650);break;
 case 'retry-page':state.view='loading-more';renderRows();setTimeout(()=>{state.limit+=12;retry();},650);break;
 case 'incoming':state.incoming=0;state.view='ready';topics.unshift({id:190,title:'Share your feedback on the new reading experience',category:'Design',child:'UX',tags:['feedback'],replies:0,age:'now',minutes:0,author:'Maya',isNew:true,days:0},{id:191,title:'Today’s community highlights',category:'Community',tags:['discussion'],replies:2,age:'now',minutes:1,author:'Sam',isNew:true,days:0},{id:192,title:'A small fix for reconnecting',category:'Engineering',tags:['bug'],replies:1,age:'now',minutes:1,author:'Alex',isNew:true,days:0});state.cursor=190;render();$('list-scroll').scrollTop=0;toast('3 new topics loaded.');break;
 case 'signin':scene('topics');toast('Signed-in preview enabled.');break;
 case 'preferences':showDialog('Preferences',`<label>Appearance<select id="preference-theme" aria-label="Appearance"><option value="dark" ${state.theme==='dark'?'selected':''}>Dark</option><option value="light" ${state.theme==='light'?'selected':''}>Light</option></select></label><p>Topic list layout is available from the Display menu above the list.</p>`);break;
 case 'category-details':showDialog(state.child||state.category,`<p>Conversations about ${esc((state.child||state.category).toLowerCase())}, shared ideas, and thoughtful improvements to Discourse.</p><p>${topics.filter(t=>t.category===state.category).length} sample topics · ${esc(state.category)}${state.child?' › '+esc(state.child):''}</p>`);break;
 }
});
document.addEventListener('input',event=>{if(event.target.id==='filter-query'){renderFilterSuggestions();return;}if(event.target.matches('[data-menu-search]')){const value=event.target.value.toLowerCase();$('popover').querySelectorAll('[data-menu-options] button').forEach(b=>b.hidden=!b.textContent.toLowerCase().includes(value));}});
document.addEventListener('change',event=>{if(event.target.id==='preference-theme'){state.theme=event.target.value;render();}});
document.addEventListener('submit',event=>{event.preventDefault();const f=event.target;if(f.id==='filter-form'){const q=new FormData(f).get('query');closePopover(false);change(()=>state.query=q);}
 if(f.classList.contains('forum-filter-form')){state.forumQueries[f.dataset.forumName]=new FormData(f).get('query');renderRows();toast('Forum filter applied.');}
 if(f.id==='compose-form'){const data=new FormData(f);drafts.unshift({title:String(data.get('title')),type:isMessages()?'Private message':'New topic',icon:isMessages()?'mail':'layers'});$('dialog').close();renderFooter();toast('Draft saved in this preview.');}
});
$('scene-select').addEventListener('change',e=>scene(e.target.value));
$('state-select').addEventListener('change',e=>{state.view=e.target.value;state.reader=null;state.limit=12;if(state.view==='incoming'){state.incoming=3;for(let i=topics.length-1;i>=0;i--)if(topics[i].id>=190&&topics[i].id<=192)topics.splice(i,1);}if(state.view==='end')state.limit=100;render();if(['loading-more','page-error','end'].includes(state.view))$('list-scroll').scrollTop=$('list-scroll').scrollHeight;});
$('dialog').addEventListener('click',e=>{if(e.target===$('dialog')){const r=$('dialog').getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)$('dialog').close();}});
$('dialog').addEventListener('close',()=>{if(!state.split&&state.reader){state.reader=null;renderRows();}if(dialogOwner?.isConnected)dialogOwner.focus({preventScroll:true});});
$('popover').addEventListener('toggle',e=>{if(e.newState==='closed')popoverOwner?.setAttribute('aria-expanded','false');});
document.addEventListener('keydown',e=>{
 if(e.target.id==='filter-query'&&!e.isComposing){
  if(['ArrowDown','ArrowUp'].includes(e.key)){e.preventDefault();if(!filterSuggestionsOpen)renderFilterSuggestions();if(filterCompletions.length){filterSelection=filterSelection<0?(e.key==='ArrowDown'?0:filterCompletions.length-1):(filterSelection+(e.key==='ArrowDown'?1:-1)+filterCompletions.length)%filterCompletions.length;renderFilterSuggestions(false);}return;}
  if(filterSuggestionsOpen&&['Enter','Tab'].includes(e.key)){e.preventDefault();acceptFilterSuggestion(Math.max(0,filterSelection));return;}
  if(filterSuggestionsOpen&&e.key==='Escape'){e.preventDefault();filterSuggestionsOpen=false;renderFilterSuggestions(false);return;}
 }
 if(e.key==='Escape'&&!$('dialog').open&&!$('popover').matches(':popover-open')&&state.reader){state.reader=null;render();$('list-scroll').focus();return;}
 if(e.key==='Escape'&&$('popover').matches(':popover-open')){e.preventDefault();closePopover();return;}
 if($('popover').matches(':popover-open')&&!e.target.matches('input,textarea,select')&&['ArrowDown','ArrowUp','Home','End'].includes(e.key)){const items=[...$('popover').querySelectorAll('button:not([hidden])')];let i=items.indexOf(document.activeElement);i=e.key==='Home'?0:e.key==='End'?items.length-1:(i+(e.key==='ArrowDown'?1:-1)+items.length)%items.length;items[i]?.focus();e.preventDefault();return;}if(e.target.matches('input,textarea,select')||e.ctrlKey||e.metaKey||e.altKey||$('dialog').open||$('popover').matches(':popover-open'))return;
 if(state.reader&&Date.now()-keyboardPrefix<1000&&['j','k'].includes(e.key)){e.preventDefault();keyboardPrefix=0;navigateTopic(e.key==='j'?1:-1);return;}if(e.key==='g'){keyboardPrefix=Date.now();return;}if(!e.target.closest('.list-pane'))return;const rows=filtered();if(!rows.length)return;let index=rows.findIndex(t=>t.id===state.cursor);let handled=true;
 if(['ArrowDown','j','J'].includes(e.key))index=Math.min(rows.length-1,index+1);else if(['ArrowUp','k','K'].includes(e.key))index=Math.max(0,index-1);else if(e.key==='Home')index=0;else if(e.key==='End')index=rows.length-1;else if(['Enter','o'].includes(e.key)&&e.target.id==='list-scroll'){e.preventDefault();openTopic(state.cursor);return;}else handled=false;
 if(handled){e.preventDefault();state.cursor=rows[index].id;state.keyboard=true;state.limit=Math.max(state.limit,index+1);renderRows();$('list-scroll').focus({preventScroll:true});$('list-scroll').querySelector(`[data-topic="${state.cursor}"]`)?.scrollIntoView({block:'nearest'});}
});
$('list-scroll').addEventListener('scroll',()=>{const el=$('list-scroll');if(state.view!=='ready'||!$('page-sentinel')||loadTimer)return;if(el.scrollTop+el.clientHeight>=el.scrollHeight-60){loadTimer=setTimeout(()=>{loadTimer=null;if(state.view!=='ready')return;const offset=el.scrollTop;state.limit+=8;renderRows();el.scrollTop=offset;},700);}});
$('list-scroll').addEventListener('touchstart',e=>{pullStart=e.touches.length===1&&$('list-scroll').scrollTop===0?e.touches[0].clientY:null;pullDistance=0;},{passive:true});
$('list-scroll').addEventListener('touchmove',e=>{if(pullStart==null)return;pullDistance=e.touches[0].clientY-pullStart;if(pullDistance>15){e.preventDefault();$('feed-status').innerHTML=`<div class="incoming">${icon('refresh')}${pullDistance>70?'Release to refresh':'Pull to refresh'}</div>`;}},{passive:false});
$('list-scroll').addEventListener('touchend',()=>{if(pullDistance>70){$('feed-status').innerHTML='<div class="incoming"><span class="spinner"></span>Refreshing…</div>';setTimeout(retry,650);}else if(pullStart!=null)renderRows();pullStart=null;pullDistance=0;});
// Invalid query parameters cannot strand the prototype in an unknown context.
if(![...$('scene-select').options].some(o=>o.value===state.scene))state.scene='topics';
if(![...$('state-select').options].some(o=>o.value===state.view))state.view='ready';
new ResizeObserver(([entry])=>{
 const forceCard=entry.contentRect.width<320;
 if(forceCard===state.forceCard)return;
 state.forceCard=forceCard;
 $('table-shell').classList.toggle('cards',state.forceCard||state.mode==='card');
 if(popoverOwner?.dataset.menu==='display'&&$('popover').matches(':popover-open'))openMenu('display',popoverOwner);
}).observe(document.querySelector('.list-pane'));
const initialScene=state.scene,initialView=state.view;scene(initialScene);state.view=initialView;if(initialView==='end')state.limit=100;render();const linkedTopic=Number(location.hash.replace('#topic-',''));if([...topics,...messages].some(t=>t.id===linkedTopic))openTopic(linkedTopic);if(params.get('menu')==='feed')openMenu('feed',$('toolbar').querySelector('[data-menu="feed"]'));
