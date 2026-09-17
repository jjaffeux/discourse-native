'use strict';

// The six visible screenshot rows, in their original order. No inferred totals.
const participants = Object.freeze([
  { name: 'pengguna1', username: 'Alfima', status: 'going' },
  { name: 'AnneClaire', username: 'AnneClaire', status: 'going' },
  { name: 'Angeline Yodo', username: 'ayodo', status: 'going' },
  { name: 'Danielle Lloyd', username: 'Danielle', status: 'going' },
  { name: 'Emily Roman', username: 'Emily_Roman', status: 'going' },
  { name: 'Flavia Sasaki Siqueira', username: 'fsasaki', status: 'going' },
]);
const paths = {
  search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4 4"/>',
  close: '<path d="m6 6 12 12M6 18 18 6"/>',
  check: '<path d="m5 12 4 4L19 6"/>',
  star: '<path d="m12 3 2.8 5.7 6.3.9-4.6 4.4 1.1 6.3-5.6-3-5.6 3 1.1-6.3L3 9.6l6.2-.9Z"/>',
  people: '<circle cx="9" cy="8" r="3"/><path d="M3 21v-2a6 6 0 0 1 12 0v2M16 5a3 3 0 0 1 0 6m2 4a5 5 0 0 1 3 4v2"/>',
  desktop: '<rect x="3" y="4" width="18" height="13" rx="2"/><path d="M8 21h8m-4-4v4"/>',
  mobile: '<rect x="6" y="2" width="12" height="20" rx="2"/><path d="M10 18h4"/>',
  compare: '<rect x="3" y="3" width="7" height="18" rx="1"/><rect x="14" y="3" width="7" height="18" rx="1"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1 1m12 12 1 1M5 19l1-1M18 6l1-1"/>',
  moon: '<path d="M20.5 14A9 9 0 0 1 10 3.5 9 9 0 1 0 20.5 14Z"/>',
};
const icon = (name) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths[name]}</svg>`;
const escapeHtml = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const filters = [ ['all', 'All', 'people'], ['going', 'Going', 'check'], ['interested', 'Interested', 'star'], ['not_going', 'Not going', 'close'] ];
const concepts = [
  { id:'compact', title:'Compact list', text:'A small, focused dialog that feels like an extension of the event card. People lead; responses stay quiet and easy to scan.', points:['Names and handles stay together','Initials give each row a visual anchor','Search and filters remain in reach'], note:'My recommendation: the best fit with the Compact event card.', recommended:true, caption:'520px dialog · 28px controls · 52px rows' },
  { id:'rail', title:'Status rail', text:'Move response filters to the side and give the roster a continuous vertical rhythm. The list feels more like a small directory.', points:['A clear place to switch response','Simple, avatar-free rows','Filters move above the list on mobile'], note:'A little wider on desktop; useful when switching between responses often.', caption:'610px dialog · persistent status navigation' },
  { id:'directory', title:'Directory', text:'The most condensed view. Search sits beside the title, and aligned columns make it easy to read across a longer list.', points:['Compact rows with inline handles','A consistent response column','Names wrap naturally on small screens'], note:'Best for scanning larger rosters; slightly more structured than the list.', caption:'610px dialog · 44px desktop rows' },
];
const state = { concept:'compact', width:'desktop', compare:false, theme:'dark' };
const views = Object.fromEntries(concepts.map(c => [c.id,{filter:'all',query:'',closed:false}]));
const search = id => `<div class="search-wrap"><label class="search" for="search-${id}">${icon('search')}<input type="search" id="search-${id}" placeholder="Search participants" aria-label="Search participants" autocomplete="off" spellcheck="false"><button class="icon-button clear-search" aria-label="Clear search" type="button" hidden>${icon('close')}</button></label></div>`;
const tabs = id => `<div class="filters" role="tablist" aria-label="Participant response" data-tabs="${id}">${filters.map(([value,label,glyph])=>`<button class="filter" role="tab" id="tab-${id}-${value}" data-filter="${value}" aria-selected="${value==='all'}" tabindex="${value==='all'?0:-1}" aria-controls="results-${id}">${icon(glyph)}${label}</button>`).join('')}</div>`;
const close = '<button class="icon-button close-dialog" aria-label="Close participants">'+icon('close')+'</button>';
const list = (id, directory=false) => `${directory?'<div class="column-headings" aria-hidden="true"><span>Participant</span><span>Response</span></div>':''}<div class="list-area" id="results-${id}" role="tabpanel" aria-labelledby="tab-${id}-all" tabindex="0"><ul class="people" aria-label="Participants"></ul><div class="empty" hidden></div></div>`;
const footer = '<footer class="dialog-footer"><span class="result-count" role="status" aria-live="polite"></span><button class="button primary close-dialog">Done</button></footer>';
function dialog(id) {
  const heading = `<header class="dialog-heading"><h3 id="title-${id}">Participants</h3>${id==='directory'?`<div class="header-actions">${search(id)}${close}</div>`:close}</header>`;
  let body = id==='rail'?`<div class="rail-body">${tabs(id)}<div class="rail-main">${search(id)}${list(id)}</div></div>`:id==='directory'?`${tabs(id)}${list(id,true)}`:`${search(id)}${tabs(id)}${list(id)}`;
  return `<section class="dialog ${id}" role="region" aria-labelledby="title-${id}">${heading}${body}${footer}</section><div class="closed" hidden><p>Participants closed.</p><button class="button reopen">Open participants</button></div>`;
}
for (const [index,c] of concepts.entries()) {
  const article = document.createElement('article');
  article.className='study'; article.dataset.study=c.id;
  article.innerHTML=`<aside class="study-notes"><span class="eyebrow">DIRECTION 0${index+1} / 03</span><h2>${c.title}</h2><p>${c.text}</p>${c.recommended?`<span class="recommendation">${icon('check')}Recommended</span>`:''}<ol class="principles">${c.points.map(p=>`<li>${p}</li>`).join('')}</ol><p class="tradeoff">${c.note}</p></aside><div class="stage"><div class="preview">${dialog(c.id)}</div><p class="preview-caption">${c.caption}</p></div>`;
  document.querySelector('#studies').append(article);
  article.querySelector('input').addEventListener('input', event => {views[c.id].query=event.target.value; renderResults(c.id);});
  article.querySelector('.clear-search').addEventListener('click',()=>{views[c.id].query='';article.querySelector('input').value='';renderResults(c.id);article.querySelector('input').focus();});
  article.querySelectorAll('[data-filter]').forEach(button=>button.addEventListener('click',()=>selectFilter(c.id,button.dataset.filter)));
  article.querySelector('.filters').addEventListener('keydown',event=>{
    const keys=['ArrowRight','ArrowDown','ArrowLeft','ArrowUp','Home','End'];
    if(!keys.includes(event.key))return;
    event.preventDefault(); const current=filters.findIndex(f=>f[0]===views[c.id].filter);
    const next=event.key==='Home'?0:event.key==='End'?filters.length-1:(current+(['ArrowRight','ArrowDown'].includes(event.key)?1:-1)+filters.length)%filters.length;
    selectFilter(c.id,filters[next][0]);article.querySelector(`[data-filter="${filters[next][0]}"]`).focus();
  });
  article.querySelectorAll('.close-dialog').forEach(button=>button.addEventListener('click',()=>setClosed(c.id,true)));
  article.querySelector('.reopen').addEventListener('click',()=>setClosed(c.id,false));
  article.querySelector('.dialog').addEventListener('keydown',event=>{if(event.key==='Escape'){event.preventDefault();setClosed(c.id,true);}});
  renderResults(c.id);
}
function selectFilter(id,filter){
  views[id].filter=filter;
  const article=document.querySelector(`[data-study="${id}"]`);
  article.querySelectorAll('[data-filter]').forEach(button=>{const active=button.dataset.filter===filter;button.setAttribute('aria-selected',String(active));button.tabIndex=active?0:-1;});
  article.querySelector('.list-area').setAttribute('aria-labelledby',`tab-${id}-${filter}`);
  renderResults(id);
}
function initials(name){const words=name.trim().split(/\s+/);return (words[0][0]+(words.length>1?words[words.length-1][0]:'')).toUpperCase();}
function renderResults(id){
  const article=document.querySelector(`[data-study="${id}"]`), view=views[id];
  const query=view.query.trim().toLocaleLowerCase().replace(/^@/,'');
  const rows=participants.filter(person=>(view.filter==='all'||person.status===view.filter)&&`${person.name} ${person.username}`.toLocaleLowerCase().includes(query));
  article.querySelector('.people').innerHTML=rows.map(person=>`<li><button class="person" data-profile="${escapeHtml(person.username)}" aria-label="Open profile for ${escapeHtml(person.name)}, @${escapeHtml(person.username)}, Going"><span class="avatar" aria-hidden="true">${initials(person.name)}</span><span class="identity"><span class="person-name">${escapeHtml(person.name)}</span><span class="username">@${escapeHtml(person.username)}</span></span><span class="response">${icon('check')}Going</span></button></li>`).join('');
  article.querySelectorAll('[data-profile]').forEach(button=>button.addEventListener('click',()=>announce(`@${button.dataset.profile} · Profile navigation is preview-only here.`)));
  article.querySelector('.result-count').textContent=`${rows.length} shown`;
  article.querySelector('.clear-search').hidden=!view.query;
  const empty=article.querySelector('.empty'); empty.hidden=rows.length!==0;
  empty.innerHTML=`${icon('search')}<strong>No participants found</strong><p>${query?'Try another name or username.':'Try a different response filter.'}</p><button class="button reset-results">${query?'Clear search':'Show all participants'}</button>`;
  empty.querySelector('button').addEventListener('click',()=>{if(query){view.query='';article.querySelector('input').value='';renderResults(id);article.querySelector('input').focus();}else selectFilter(id,'all');});
}
function setClosed(id,closed){const article=document.querySelector(`[data-study="${id}"]`);views[id].closed=closed;article.querySelector('.dialog').hidden=closed;article.querySelector('.closed').hidden=!closed;(closed?article.querySelector('.reopen'):article.querySelector('input')).focus();}
let toastTimer;
function announce(message){const toast=document.querySelector('#toast');toast.textContent=message;toast.classList.add('visible');clearTimeout(toastTimer);toastTimer=setTimeout(()=>toast.classList.remove('visible'),3000);}
function renderView(save=true){
  document.documentElement.dataset.theme=state.theme;document.body.classList.toggle('narrow',state.width==='mobile');
  document.querySelectorAll('[data-study]').forEach(el=>{el.hidden=!state.compare&&el.dataset.study!==state.concept;});
  document.querySelectorAll('[data-concept]').forEach(el=>el.setAttribute('aria-pressed',String(el.dataset.concept===state.concept)));
  document.querySelectorAll('[data-width]').forEach(el=>el.setAttribute('aria-pressed',String(el.dataset.width===state.width)));
  document.querySelector('#compare').setAttribute('aria-pressed',String(state.compare));
  document.querySelector('#theme').innerHTML=icon(state.theme==='dark'?'sun':'moon')+`<span>${state.theme==='dark'?'Light':'Dark'}</span>`;
  document.querySelector('#theme').setAttribute('aria-label',`Switch to ${state.theme==='dark'?'light':'dark'} theme`);
  document.querySelectorAll('.preview-caption').forEach((el,index)=>{el.textContent=state.width==='mobile'?'360px mobile preview · same content':concepts[index].caption;});
  if(save){const hash=new URLSearchParams({concept:state.concept});if(state.compare)hash.set('compare','all');if(state.width==='mobile')hash.set('width','mobile');if(state.theme==='light')hash.set('theme','light');history.replaceState(null,'','#'+hash);}
}
function readLocation(){const params=new URLSearchParams(location.hash.slice(1));if(concepts.some(c=>c.id===params.get('concept')))state.concept=params.get('concept');state.compare=params.get('compare')==='all';state.width=params.get('width')==='mobile'?'mobile':'desktop';state.theme=params.get('theme')==='light'?'light':'dark';renderView(false);}
document.querySelectorAll('[data-icon]').forEach(el=>{el.innerHTML=icon(el.dataset.icon);});
document.querySelectorAll('[data-concept]').forEach(button=>button.addEventListener('click',()=>{state.concept=button.dataset.concept;state.compare=false;renderView();}));
document.querySelectorAll('[data-width]').forEach(button=>button.addEventListener('click',()=>{state.width=button.dataset.width;renderView();}));
document.querySelector('#compare').addEventListener('click',()=>{state.compare=!state.compare;renderView();});
document.querySelector('#theme').addEventListener('click',()=>{state.theme=state.theme==='dark'?'light':'dark';renderView();});
window.addEventListener('hashchange',readLocation);readLocation();
