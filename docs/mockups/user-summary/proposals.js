/* Sample data only. No requests, persistence, dependencies or account writes. */
const params = new URLSearchParams(location.search);
const direction = document.body.dataset.direction || 'overview';
let previewState = params.get('state') || 'ready';
document.documentElement.dataset.theme = params.get('theme') === 'dark' ? 'dark' : 'light';
const paths = {
  heart: '<path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8Z"/>',
  reply: '<path d="m9 10-5 5 5 5M4 15h11a5 5 0 0 0 0-10h-3"/>',
  topic: '<path d="M21 11.5a8.5 8.5 0 0 1-8.5 8.5H4l-2 2V11.5A8.5 8.5 0 0 1 10.5 3H13a8 8 0 0 1 8 8.5Z"/><path d="M7 9h9M7 13h6"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  arrow: '<path d="M5 12h14m-5-5 5 5-5 5"/>',
  link: '<path d="m10 13 4-4M8 16l-1 1a4 4 0 0 1-6-6l4-4a4 4 0 0 1 6 0m2 10a4 4 0 0 0 6 0l4-4a4 4 0 0 0-6-6l-1 1" transform="translate(1 0) scale(.9)"/>',
  medal: '<circle cx="12" cy="8" r="5"/><path d="m8 12-2 9 6-3 6 3-2-9"/>',
  book: '<path d="M12 6c-3-3-7-3-10-1v14c3-2 7-2 10 1 3-3 7-3 10-1V5c-3-2-7-2-10 1Zm0 0v14"/>',
  calendar: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M16 3v4M8 3v4M3 11h18"/>',
  moon: '<path d="M20.5 13a8.5 8.5 0 1 1-9.5-9.5A7 7 0 0 0 20.5 13Z"/>',
  close: '<path d="m6 6 12 12M6 18 18 6"/>',
  refresh: '<path d="M20 8a8 8 0 0 0-14-3L3 8m0-5v5h5m-4 8a8 8 0 0 0 14 3l3-3m0 5v-5h-5"/>',
  eye: '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/>',
};
const icon = name => `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true">${paths[name] || paths.topic}</svg>`;
const esc = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const topics = [
  ['A calmer, more focused topic page', 'UX', 'Aug 28', 186],
  ['Small improvements that make a big difference', 'Feature', 'Aug 16', 124],
  ['Making keyboard navigation feel natural', 'UX', 'Jul 30', 98],
  ['A better home for your bookmarks', 'Feature', 'Jul 12', 76],
  ['What makes a great community welcome?', 'Community', 'Jun 24', 64],
  ['Making room for longer conversations', 'UX', 'Jun 8', 52],
];
const replies = [
  ['What should we simplify next?', 'UX', 'Sep 4', 94],
  ['Designing for the conversations in between', 'Community', 'Aug 24', 81],
  ['Making notifications more useful', 'Feature', 'Aug 20', 67],
  ['A few thoughts on the new composer', 'UX', 'Aug 8', 58],
  ['Better defaults for growing communities', 'Community', 'Jul 27', 43],
  ['A more helpful first visit', 'Support', 'Jul 19', 31],
];
const categories = [
  ['UX', '#8b78b8', 22, 318], ['Feature', '#4d8fbd', 14, 246],
  ['Community', '#689d7c', 8, 174], ['Support', '#c3925d', 4, 126],
];
const people = {
  received: [['Maya Chen','maya','MC',248,'green'],['Sam Rivera','sam','SR',196,'orange'],['Jamie Park','jamie','JP',154,'plum'],['Robin Lee','robin','RL',121,'blue']],
  given: [['Jamie Park','jamie','JP',184,'plum'],['Maya Chen','maya','MC',163,'green'],['Robin Lee','robin','RL',109,'blue'],['Sam Rivera','sam','SR',92,'orange']],
  replied: [['Sam Rivera','sam','SR',86,'orange'],['Maya Chen','maya','MC',72,'green'],['Robin Lee','robin','RL',51,'blue'],['Jamie Park','jamie','JP',43,'plum']],
};
const links = [['A guide to building welcoming communities','discourse.org',342],['Writing useful feature requests','meta.discourse.org',218],['Designing clear, accessible interfaces','w3.org',156]];
const badges = [['Great Topic','Received 50 likes on a topic.'],['Good Reply','Received 25 likes on a reply.'],['Enthusiast','Visited on 10 consecutive days.'],['Anniversary','An active community member for a year.']];
const count = (value) => previewState === 'empty' ? '0' : value;
const category = name => `<span class="category" style="--category:${categories.find(x => x[0] === name)?.[1] || '#689d7c'}">${esc(name)}</span>`;
const avatar = (initials = 'AM', color = 'blue', large = false) => `<span class="d-avatar ${color} ${large ? 'large' : ''}" data-kit="DAvatar" aria-hidden="true">${initials}</span>`;
const identity = () => `<div class="identity">${avatar('AM','blue',true)}<div><strong>Alex Morgan</strong><p>@alex · Discourse Meta</p></div></div>`;
const inspectButton = (label, body, contents, cls = 'd-button') => `<button class="${cls}" aria-label="${esc(label)}. ${esc(body)}" data-inspect-title="${esc(label)}" data-inspect-body="${esc(body)}">${contents}</button>`;
const card = (title, description, body, action = '') => `<section class="d-card" data-kit="DCard"><div class="card-head"><div><h2>${title}</h2>${description ? `<p>${description}</p>` : ''}</div>${action}</div><div class="card-body">${body}</div></section>`;
let tabId = 0;
function tabs(label, items, segmented = false) {
  const id = `tabs-${++tabId}`;
  return `<div class="tab-set" data-kit="DTabs"><div class="d-tabs ${segmented ? 'segmented' : ''}" role="tablist" aria-label="${label}">${items.map((item,i) => `<button role="tab" id="${id}-tab-${i}" aria-controls="${id}-panel-${i}" aria-selected="${i === 0}" tabindex="${i === 0 ? 0 : -1}">${item[0]}</button>`).join('')}</div>${items.map((item,i) => `<div role="tabpanel" id="${id}-panel-${i}" aria-labelledby="${id}-tab-${i}" tabindex="0" ${i ? 'hidden' : ''}>${item[1]}</div>`).join('')}</div>`;
}
function topicList(rows, ranked = false) {
  return `<div class="item-list" data-kit="DItemGroup">${rows.map((row,i) => inspectButton(row[0], `${row[1]} · ${row[2]}, 2026 · ${row[3]} likes`, `${ranked ? `<span class="rank">${String(i+1).padStart(2,'0')}</span>` : ''}<span class="item-content"><span class="item-title">${row[0]}</span><span class="item-meta">${category(row[1])}<span>·</span><span>${row[2]}</span></span></span><span class="count">${icon('heart')}${row[3]}</span>`, 'd-item')).join('')}</div>`;
}
function peopleList(kind) {
  return `<div class="people-list" data-kit="DItemGroup">${people[kind].map(p => inspectButton(p[0], `@${p[1]} · ${p[3]} ${kind === 'replied' ? 'replies exchanged with Alex' : kind === 'given' ? 'likes given by Alex' : 'likes given to Alex'}`, `${avatar(p[2],p[4])}<span class="item-content"><span class="item-title">${p[0]}</span><span class="item-meta">@${p[1]}</span></span><span class="person-count"><b>${p[3]}</b><small>${kind === 'replied' ? 'replies' : 'likes'}</small></span>`, 'd-item')).join('')}</div>`;
}
function categoryTable() {
  return `<table class="d-table" data-kit="DTable"><thead><tr><th scope="col">Category</th><th scope="col">Topics</th><th scope="col">Replies</th></tr></thead><tbody>${categories.map(c=>`<tr><td>${category(c[0])}</td><td>${inspectButton(`${c[0]} topics`, `Search preview: @alex #${c[0].toLowerCase()} in:first · ${c[2]} topics`,c[2],'d-button ghost')}</td><td>${inspectButton(`${c[0]} replies`, `Search preview: @alex #${c[0].toLowerCase()} · ${c[3]} replies`,c[3],'d-button ghost')}</td></tr>`).join('')}</tbody></table>`;
}
function linkList() {
  return `<div class="item-list">${links.map(l=>inspectButton(l[0], `${l[1]} · ${l[2]} clicks`, `${icon('link')}<span class="item-content"><span class="item-title">${l[0]}</span><span class="item-meta">${l[1]}</span></span><span class="person-count"><b>${l[2]}</b><small>clicks</small></span>`,'d-item')).join('')}</div>`;
}
const badgeList = () => `<div class="badge-list" data-kit="DBadge">${badges.map(b=>inspectButton(b[0],b[1],`${icon('medal')}${b[0]}`,'d-badge')).join('')}</div>`;
const metrics = [
  ['Likes received','2,846','1,209 likes given','heart'],
  ['Replies written','864','48 topics started','reply'],
  ['Days visited','312','All time','calendar'],
  ['Time reading','18d','7h in the last 60 days','book'],
];
function statRow(profile = false) {
  if (previewState === 'private') return '';
  const items = profile ? [metrics[0],metrics[1],['Topics started','48','All time','topic']] : metrics;
  return `<dl class="stats">${items.map(m=>`<div class="stat" data-kit="DText"><dt>${profile ? '' : icon(m[3])}${m[0]}</dt><dd>${count(m[1])}</dd><small>${previewState === 'empty' ? 'All time' : m[2]}</small></div>`).join('')}</dl>`;
}
const detailsData = [['Topics viewed','3,428'],['Posts read','24,680'],['Bookmarks','36'],['Likes given','1,209'],['Topics started','48'],['Recent read time','7h · last 60 days']];
function detailedStats() {
  if (previewState === 'private') return '';
  return `<details class="stats-detail" data-kit="DCollapsible"><summary>More statistics</summary><dl class="detail-grid">${detailsData.map(m=>`<div><dt>${m[0]}</dt><dd>${count(m[1])}</dd></div>`).join('')}</dl></details>`;
}
const head = (title, description) => `<header class="page-head"><div><h1>${title}</h1><p class="muted">${description}</p></div>${identity()}</header>`;
const footer = () => `<footer class="summary-footer"><span>All-time summary · Recent reading covers the last 60 days</span><span>Discourse Meta</span></footer>`;
function emptyContent() {
  return `<section class="d-card"><div class="d-empty" data-kit="DEmpty">${icon('topic')}<h2>Your story starts with a conversation.</h2><p>As you read, reply and connect with people, your highlights will appear here.</p>${inspectButton('Explore conversations','The app would open the topic list.',`Explore conversations ${icon('arrow')}`,'d-button primary')}</div></section>`;
}
function overview() {
  return `${head('Your community, at a glance.', 'The conversations, people and ideas you keep coming back to.')}
    <div class="flow">
      ${previewState !== 'private' ? `<section class="d-card" aria-label="All-time statistics">${statRow()}${detailedStats()}</section>` : ''}
      ${previewState === 'empty' ? emptyContent() : `<div class="columns">
        <div class="flow">${card('Conversations that resonated', 'Your most liked contributions', tabs('Contribution type', [['Top topics',topicList(topics)],['Top replies',topicList(replies)]]))}
          ${card('Where you contribute', 'Topics and replies by category', categoryTable())}</div>
        <div class="flow">${card('Your community', 'The people around your conversations', tabs('Community relationship', [['Liked by',peopleList('received')],['You liked',peopleList('given')],['Replied to',peopleList('replied')]],true))}
          ${card('Links worth sharing', 'Your most visited links',linkList())}
          ${card('A few milestones', 'Badges you have earned',badgeList())}</div>
      </div>`}
    </div>${footer()}`;
}
function dataRows(rows) {
  return `<dl class="data-rows">${rows.map(m=>`<div><dt>${m[0]}</dt><dd>${count(m[1])}</dd></div>`).join('')}</dl>`;
}
function editorial() {
  return `<header class="page-head">${identity()}<span class="d-badge secondary">Your summary</span></header>
    <div class="editorial-hero"><div><div class="eyebrow">Your contributions</div><h1>Good conversations<br>leave a mark.</h1><p class="muted">A look back at the ideas you shared and the people you connected with.</p></div>${previewState !== 'private' ? `<div class="hero-number"><strong>${count('2,846')}</strong><span>${icon('heart')} likes received</span></div>` : ''}</div>
    ${previewState === 'empty' ? emptyContent() : `<div class="editorial-grid"><div>
      <section class="d-card featured"><span class="d-badge secondary">${icon('topic')} Your most liked topic</span><h2>${topics[0][0]}</h2><div class="item-meta">${category(topics[0][1])}<span>·</span><span>${topics[0][2]}, 2026</span></div><div class="feature-bottom"><span class="count">${icon('heart')} ${topics[0][3]} likes</span>${inspectButton(topics[0][0], `${topics[0][3]} likes · ${topics[0][1]} · ${topics[0][2]}, 2026`, `Open topic ${icon('arrow')}`, 'd-button primary')}</div></section>
      <div class="section-head"><div><h2>More ideas you shared</h2><p class="caption">Your other top topics</p></div></div>${topicList(topics.slice(1))}
      <div class="section-head"><div><h2>Replies that helped</h2><p class="caption">Your most appreciated replies</p></div>${icon('reply')}</div>${topicList(replies,true)}
      <div class="section-head"><h2>Links worth passing on</h2></div>${linkList()}
    </div><aside class="editorial-side">
      ${previewState !== 'private' ? `<section><h2>A curious mind</h2><div class="reading-number">18d</div><p class="caption">spent reading · 7h in the last 60 days</p>${dataRows([['Days visited','312'],['Topics viewed','3,428'],['Posts read','24,680'],['Topics started','48'],['Replies written','864'],['Likes given','1,209'],['Bookmarks','36']])}</section>` : ''}
      <section><h2>Familiar faces</h2><p class="caption">People you connect with most</p><div style="margin-top:16px">${tabs('Community relationship', [['Replied to',peopleList('replied')],['Liked by',peopleList('received')],['You liked',peopleList('given')]],true)}</div></section>
      <section><h2>Your corners of the community</h2><div style="margin-top:16px">${categoryTable()}</div></section>
      <section><h2>Milestones along the way</h2><div style="margin-top:12px">${badgeList()}</div></section>
    </aside></div>`}${footer()}`;
}
function profile() {
  const rail = `<aside class="profile-rail"><section class="d-card profile-card">${avatar('AM','blue',true)}<h1>Alex Morgan</h1><p class="handle">@alex</p><p class="site-label"><span class="brand-mark" aria-hidden="true"></span>Discourse Meta</p>${previewState !== 'private' ? dataRows([['Days visited','312'],['Time reading','18d'],['Likes given','1,209'],['Bookmarks','36']]) : ''}</section></aside>`;
  const highlights = `<div class="flow">${previewState !== 'private' ? `<section class="d-card">${statRow(true)}</section>` : ''}${previewState === 'empty' ? emptyContent() : `<div class="equal-columns">${card('Top topics','',topicList(topics))}${card('Top replies','',topicList(replies))}</div>${card('Your milestones','',badgeList())}`}</div>`;
  const connections = previewState === 'empty' ? emptyContent() : `<div class="connection-cards">${card('Most replied to','',peopleList('replied'))}${card('Most liked by','',peopleList('received'))}${card('Most liked','',peopleList('given'))}</div>`;
  const reading = `<div class="flow">${previewState !== 'private' ? card('Time well spent','', `<div class="reading-number">${count('18d')}</div><p class="caption">All-time reading · ${count('7h')} in the last 60 days</p>${dataRows([['Topics viewed','3,428'],['Posts read','24,680'],['Bookmarks','36']])}`) : ''}${previewState === 'empty' ? emptyContent() : `${card('Top categories','',categoryTable())}${card('Top links','',linkList())}`}</div>`;
  return `<div class="profile-layout">${rail}<div class="profile-content">${tabs('Summary section',[['Highlights',highlights],['Connections',connections],['Reading',reading]])}</div></div>${footer()}`;
}
function render() {
  tabId = 0;
  document.body.className = direction === 'contributions' ? 'editorial' : direction === 'profile' ? 'profile' : 'overview';
  const alert = previewState === 'error' ? `<div class="d-alert" role="status" data-kit="DAlert">${icon('refresh')}<div><strong>Couldn’t refresh your summary.</strong><p>You’re seeing the last saved version.</p></div><button class="d-button" data-retry>Try again</button></div>` : '';
  const loading = `<div role="status" aria-label="Loading summary" class="flow"><div class="skeleton" style="height:64px;width:65%"></div><div class="d-card loading-block"><div class="skeleton" style="height:80px"></div></div><div class="equal-columns">${Array.from({length:2},()=>`<div class="d-card loading-block">${Array.from({length:4},()=>'<div class="skeleton" style="height:36px"></div>').join('')}</div>`).join('')}</div></div>`;
  document.getElementById('app').innerHTML = `<header class="topbar"><span class="brand-mark" aria-hidden="true"></span><span class="wordmark">Discourse</span><span class="divider"></span><span class="muted">Summary</span><div class="right"><span class="caption">Discourse Meta</span><button class="d-button ghost icon-only" data-theme aria-label="Toggle color theme">${icon('moon')}</button></div></header><main class="app-page">${alert}${previewState === 'loading' ? loading : ({overview,contributions:editorial,profile}[direction] || overview)()}</main>`;
}
render();
const dialog = document.createElement('dialog');
dialog.setAttribute('aria-labelledby','dialog-title');
dialog.innerHTML = `<div class="dialog-head"><h2 id="dialog-title"></h2><button class="d-button ghost icon-only" data-close aria-label="Close preview">${icon('close')}</button></div><p id="dialog-body"></p><p class="dialog-note">Illustrative content. In the app, this opens the existing topic, user card, category search or badge detail.</p>`;
document.body.append(dialog);
document.addEventListener('click', event => {
  const button = event.target.closest('button');
  if (!button) return;
  if (button.hasAttribute('data-theme')) {
    document.documentElement.dataset.theme = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
  } else if (button.hasAttribute('data-retry')) {
    previewState = 'ready'; render();
  } else if (button.hasAttribute('data-close')) dialog.close();
  else if (button.hasAttribute('data-inspect-title')) {
    document.getElementById('dialog-title').textContent = button.dataset.inspectTitle;
    document.getElementById('dialog-body').textContent = button.dataset.inspectBody;
    dialog.showModal();
  } else if (button.getAttribute('role') === 'tab') activateTab(button);
});
function activateTab(button) {
  const list = button.parentElement;
  for (const tab of list.children) {
    const selected = tab === button;
    tab.setAttribute('aria-selected',String(selected)); tab.tabIndex = selected ? 0 : -1;
    document.getElementById(tab.getAttribute('aria-controls')).hidden = !selected;
  }
}
document.addEventListener('keydown', event => {
  if (event.target.getAttribute('role') !== 'tab') return;
  if (!['ArrowRight','ArrowLeft','Home','End'].includes(event.key)) return;
  const tabs = [...event.target.parentElement.children];
  const index = tabs.indexOf(event.target);
  const next = event.key === 'Home' ? 0 : event.key === 'End' ? tabs.length-1 : (index + (event.key === 'ArrowRight' ? 1 : -1) + tabs.length) % tabs.length;
  event.preventDefault(); activateTab(tabs[next]); tabs[next].focus(); tabs[next].scrollIntoView({block:'nearest',inline:'nearest'});
});
dialog.addEventListener('click', event => { if (event.target === dialog) { const r=dialog.getBoundingClientRect(); if(event.clientX<r.left||event.clientX>r.right||event.clientY<r.top||event.clientY>r.bottom) dialog.close(); } });
window.addEventListener('message', event => {
  if (event.source !== parent || !event.data || event.data.type !== 'summary-preview') return;
  if (['dark','light'].includes(event.data.theme)) document.documentElement.dataset.theme = event.data.theme;
  if (['ready','empty','private','error','loading'].includes(event.data.state) && event.data.state !== previewState) { previewState = event.data.state; render(); }
});
