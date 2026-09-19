(() => {
  'use strict';
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
  const paths = {
    home: '<path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1z"/>',
    layers: '<path d="m3 7 9-4 9 4-9 4zM3 12l9 4 9-4M3 17l9 4 9-4"/>',
    chat: '<path d="M21 11.5a8.5 8.5 0 0 1-8.5 8.5H4l-2 2V11.5A8.5 8.5 0 0 1 10.5 3h2a8.5 8.5 0 0 1 8.5 8.5Z"/>',
    mic: '<rect x="9" y="2" width="6" height="13" rx="3"/><path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3m-4 0h8"/>',
    settings: '<path d="m9 3-.5 3-2 1-3-.5-1.5 3 2.5 2v2L2 15.5l1.5 3 3-.5 2 1 .5 3h4l.5-3 2-1 3 .5 1.5-3-2.5-2v-2L20 9.5l-1.5-3-3 .5-2-1-.5-3Z"/><circle cx="11" cy="12.5" r="3"/>',
    search: '<circle cx="10.5" cy="10.5" r="7"/><path d="m16 16 5 5"/>',
    chevrons: '<path d="m8 8 4-4 4 4m-8 8 4 4 4-4"/>',
    down: '<path d="m6 9 6 6 6-6"/>', right: '<path d="m9 5 7 7-7 7"/>',
    back: '<path d="m14 5-7 7 7 7"/>', close: '<path d="m6 6 12 12M6 18 18 6"/>',
    plus: '<path d="M12 4v16M4 12h16"/>', inbox: '<path d="M5 4h14l3 12v4H2v-4L5 4Zm-3 12h6l2 3h4l2-3h6"/>',
    pencil: '<path d="m15 4 5 5M4 15 16 3a2 2 0 0 1 5 5L9 20l-6 1z"/>',
    users: '<circle cx="9" cy="7" r="4"/><path d="M2 21v-2a7 7 0 0 1 14 0v2M17 4a4 4 0 0 1 0 8m2 3a5 5 0 0 1 3 5"/>',
    filter: '<path d="M3 4h18l-7 8v7l-4 2V12z"/>', calendar: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M7 2v6m10-6v6M3 11h18M7 15h2m4 0h2m-8 3h2"/>',
    more: '<circle cx="12" cy="5" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="12" cy="19" r="1"/>',
    link: '<path d="m10 14 4-4M8 16l-2 2a4 4 0 0 1-6-6l5-5a4 4 0 0 1 6 0m2 1 2-2a4 4 0 0 1 6 6l-5 5a4 4 0 0 1-6 0" transform="translate(1 0)"/>',
    flag: '<path d="M5 22V3m0 0c5-4 9 4 14 0v11c-5 4-9-4-14 0"/>',
    hash: '<path d="m10 3-4 18M18 3l-4 18M3 9h18M2 15h18"/>',
    star: '<path d="m12 2 3 6 7 1-5 5 1 7-6-3-6 3 1-7-5-5 7-1z"/>',
    check: '<path d="m5 12 4 4L20 5"/>', palette: '<path d="M12 3a9 9 0 1 0 0 18h2a2 2 0 0 0 0-4 2 2 0 0 1 0-4h3c6 0 3-10-5-10Z"/><circle cx="7" cy="10" r=".6"/><circle cx="11" cy="7" r=".6"/><circle cx="16" cy="8" r=".6"/>',
    bell: '<path d="M18 8a6 6 0 0 0-12 0v6l-3 4h18l-3-4Zm-9 13h6"/>',
    heart: '<path d="M12 21 3 12a6 6 0 0 1 9-8 6 6 0 0 1 9 8z"/>',
    send: '<path d="m3 3 19 9-19 9 4-9-4-9Zm4 9h15"/>',
    volume: '<path d="m3 9 4 0 5-5v16l-5-5H3zM16 8a6 6 0 0 1 0 8m3-11a10 10 0 0 1 0 14"/>',
    bookmark: '<path d="M5 3h14v19l-7-5-7 5z"/>', shield: '<path d="m12 2 9 4v6c0 5-9 10-9 10S3 17 3 12V6z"/>'
  };
  const icon = name => `<svg viewBox="0 0 24 24" aria-hidden="true">${paths[name] || paths.layers}</svg>`;
  $$('[data-icon]').forEach(el => el.innerHTML = icon(el.dataset.icon));
  const escape = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const device = $('#device'), screen = $('#screen'), overlay = $('#overlay');
  const instances = [
    {name:'Dracula',mono:'Dc',url:'dracula.discourse.group'},
    {name:'Discourse Meta',mono:'D',url:'meta.discourse.org'},
    {name:'Design Kitchen',mono:'Dk',url:'design-kitchen.example'},
    {name:'Nature Club',mono:'N',url:'nature-club.example'},
    {name:'Good Assembly',mono:'GA',url:'good-assembly.example'},
    {name:'Sunday Bakers',mono:'SB',url:'sunday-bakers.example'},
    {name:'Local',mono:'L',url:'local.example'},
    {name:'Studio',mono:'Su',url:'studio.example'}
  ];
  const categories = [['baking','#eeb347'],['plants','#57b2cc'],['keyboards','#70c691'],['travel','#bb89d8'],['books','#ec9c67'],['hiking','#67bfb0'],['wellness','#d8ba6b']];
  const topics = [
    {title:'What’s on your desk this September?',category:'keyboards',color:'#70c691',author:'mila',initial:'M',replies:24,time:'12m',excerpt:'A small space, a good keyboard, and a little green.',text:'The days are getting a little shorter, so I’ve been making my corner feel a bit warmer. A new desk mat, a quieter keyboard, and a plant that is somehow still alive.',question:'What’s one small thing that makes your workspace feel like yours?'},
    {title:'The weekend baking thread',category:'baking',color:'#eeb347',author:'leo',initial:'L',replies:18,time:'28m',excerpt:'Sourdough, cinnamon rolls, and everything in between.',text:'Starting a little tradition: share whatever came out of your oven this weekend. Perfect loaves and slightly wonky experiments are equally welcome.',question:'I’m trying a slow-rise focaccia. What are you making?'},
    {title:'A few trails worth taking the long way for',category:'hiking',color:'#67bfb0',author:'sam',initial:'S',replies:9,time:'1h',excerpt:'The best part was the bit we hadn’t planned.',text:'We took the smaller path just before the ridge and ended up finding the quietest part of the whole walk. Sometimes the detour is the reason to go.',question:'Do you have a favorite route for a slow Sunday?'},
    {title:'What are you reading right now?',category:'books',color:'#ec9c67',author:'jules',initial:'J',replies:42,time:'2h',excerpt:'A fresh stack for the new season.',text:'I’m looking for the kind of book that makes you miss your stop. Fiction, essays, something completely unexpected — I’d love to hear what has stayed with you lately.',question:'What would you pass along to a friend?'},
    {title:'Help me find a home for this monstera',category:'plants',color:'#57b2cc',author:'nina',initial:'N',replies:7,time:'3h',excerpt:'It may have outgrown its favorite window.',text:'My monstera has had an excellent summer and is now taking over the living room. I’m considering moving it away from the window, but I don’t want to upset a good thing.',question:'Any advice on keeping a very enthusiastic plant happy?'}
  ];
  let instance = 0, history = [{mode:'home',view:'sidebar'}], cursor = 0, focusReturn = null;
  let filter = 'Latest', chatTab = 'channels', likes = new Set(), messages = [], replyDraft = '', activeRoom = null;
  const state = () => history[cursor];
  const announce = text => $('#announcement').textContent = text;
  const row = (name, glyph, action, count = '', extra = '') => `<button class="sidebar-row ${extra}" ${action}>${icon(glyph)}<span class="row-label">${name}</span>${count ? `<span class="count">${count}</span>` : ''}</button>`;
  const group = (name, content) => `<details class="sidebar-group" open><summary>${icon('down')}${name}</summary>${content}</details>`;
  const topicAction = (title, index = 0) => `data-open="list" data-title="${escape(title)}" data-topic="${index}"`;
  function sidebar() {
    return row('Topics','layers',topicAction('Topics'),'917','featured') +
      row('Messages','inbox',topicAction('Messages'),'3') + row('New topic','plus','data-sheet="compose"') +
      row('Drafts','pencil',topicAction('Drafts'),'2') + row('Users','users','data-open="users" data-title="Users"') +
      row('Upcoming events','calendar','disabled title="Calendar"') +
      row('More','more','data-sheet="more"') +
      group('App',row('General Info on App &amp; Testers','link','data-read="0"')) +
      group('Frequents',row('Weekly Update','calendar','data-read="0"') + row('Design Bugs','flag','data-read="0"') + row('Assigned','users',topicAction('Assigned'))) +
      group('Categories',categories.map(([name,color]) => `<button class="sidebar-row" data-open="list" data-title="${name}"><span class="category-dot" style="--category-color:${color}"></span><span class="row-label">${name}</span><span class="count">1</span></button>`).join(''));
  }
  function rail() {
    return `<aside class="rail" aria-label="Instances"><button class="rail-home" data-mode="home" aria-label="Home">${icon('home')}</button><hr>${instances.map((i,n) => `<button data-instance="${n}" aria-label="Switch to ${escape(i.name)}" aria-current="${n === instance}">${escape(i.mono)}</button>`).join('')}<button class="rail-add" data-sheet="add-instance" aria-label="Add instance">${icon('plus')}</button></aside>`;
  }
  function toolbar(label, action = '') { return `<div class="page-toolbar"><button class="icon-button" data-back aria-label="Go back">${icon('back')}</button><span>${escape(label)}</span>${action}</div>`; }
  function topicRows(list = topics) {
    return list.map(topic => `<button class="topic-row" data-read="${topics.indexOf(topic)}"><div class="topic-meta"><span class="category-dot" style="--category-color:${topic.color}"></span>${topic.category}<span style="margin-left:auto">${topic.time}</span></div><div class="topic-title">${topic.title}</div><div class="topic-footer"><span class="avatar">${topic.initial}</span>${topic.author}<span class="reply-count">${icon('chat')}${topic.replies}</span></div></button>`).join('');
  }
  function listPage(s) {
    const categoryTopics = topics.filter(t => t.category === s.title);
    let list = categoryTopics.length ? categoryTopics : topics;
    if (filter === 'New') list = list.slice(0,2);
    if (filter === 'Unread') list = list.slice(2);
    return `<section class="content-page">${toolbar('Home',`<button class="icon-button toolbar-action" data-sheet="compose" aria-label="New topic">${icon('plus')}</button>`)}<div class="page-title"><h2>${escape(s.title || 'Topics')}</h2></div><div class="filter-row"><label class="topic-filter"><span class="sr-only">Topic view</span><select id="topic-filter">${['Latest','New','Unread'].map(f => `<option value="${f}" ${f === filter ? 'selected' : ''}>${f}</option>`).join('')}</select>${icon('down')}</label></div>${topicRows(list)}<p class="small-label">You’re all caught up.</p></section>`;
  }
  function usersPage() {
    const members = [['mila','Mila','Plants, keyboards, and small projects.'],['sam','Sam','Building things together.'],['nina','Nina','Usually outside, sometimes baking.'],['joffrey','Joffrey','Making room for good conversations.']];
    return `<section class="content-page">${toolbar('Home')}<div class="page-title"><h2>Users</h2><span class="small-label">4 members</span></div><div class="users-list">${members.map(([username,name,bio]) => `<button class="member-row" data-channel="${username}"><span class="avatar">${name[0]}</span><span class="member-info"><strong>${name}</strong><span>@${username}</span><small>${bio}</small></span><span class="member-message">${icon('chat')}<span class="sr-only">Message ${name}</span></span></button>`).join('')}</div></section>`;
  }
  function reader(s) {
    const t = topics[s.topic || 0];
    return `<article class="content-page reader">${toolbar('Topics',`<span class="small-label toolbar-action">1 / ${t.replies + 1}</span>`)}<div class="topic-meta"><span class="category-dot" style="--category-color:${t.color}"></span>${t.category}</div><h2>${t.title}</h2><div class="author"><span class="avatar">${t.initial}</span><div><b>${t.author}</b><time>Today · 10:24 am</time></div><span class="badge">Original post</span></div><div class="post-body"><p>${t.text}</p><p>${t.question}</p></div><div class="post-actions"><button class="outline-button" data-like="${s.topic || 0}" aria-pressed="${likes.has(s.topic || 0)}" aria-label="Like post">${icon('heart')}${likes.has(s.topic || 0) ? 13 : 12}</button><button class="primary-button" data-sheet="reply">${icon('chat')}Reply</button></div><div class="author"><span class="avatar">S</span><div><b>sam</b><time>Today · 10:38 am</time></div></div><div class="post-body"><p>I love these little glimpses into everyone’s day. There’s always something here I want to try.</p><div class="post-quote">${t.question}</div><p>Looking forward to seeing what everyone else shares.</p></div></article>`;
  }
  function chatSidebar() {
    const channels = row('design','hash','data-channel="design"','4','channel-row') +
      row('general','hash','data-channel="general"','18','channel-row') +
      row('off-topic','hash','data-channel="off-topic"','7','channel-row') +
      row('app-feedback','hash','data-channel="app-feedback"','','channel-row');
    const dms = ['mila','sam','nina'].map((name,n) => `<button class="sidebar-row channel-row" data-channel="${name}"><span class="avatar">${name[0].toUpperCase()}</span><span class="row-label">${name}<span class="channel-sub">${['Shared a photo','See you tomorrow!','That looks great'][n]}</span></span>${n===0?'<span class="badge">3</span>':''}</button>`).join('');
    return `<section class="sidebar full chat-sidebar"><div class="chat-tabs" role="tablist" aria-label="Chat conversations">${[['channels','Channels','29'],['dms','DMs','3']].map(([id,label,count]) => `<button id="chat-tab-${id}" role="tab" data-chat-tab="${id}" aria-selected="${chatTab===id}" aria-controls="chat-panel-${id}" tabindex="${chatTab===id?0:-1}">${label}<span class="badge">${count}</span></button>`).join('')}</div><div id="chat-panel-channels" class="chat-tab-panel" role="tabpanel" aria-labelledby="chat-tab-channels" ${chatTab==='channels'?'':'hidden'}>${channels}</div><div id="chat-panel-dms" class="chat-tab-panel" role="tabpanel" aria-labelledby="chat-tab-dms" ${chatTab==='dms'?'':'hidden'}>${dms}</div></section>`;
  }
  function chatPage(s) {
    return `<section class="content-page">${toolbar('Chat')}<div class="page-title"><h2># ${escape(s.channel)}</h2><span class="small-label">12 members</span></div><p class="small-label">Today, September 19</p><div class="chat-message"><span class="avatar">M</span><div><b>mila</b><time>10:42</time><p>A little corner for the things we’re working on. What’s everyone up to today?</p></div></div><div class="chat-message"><span class="avatar">S</span><div><b>sam</b><time>10:45</time><p>Taking the new mobile layout for a spin. Having a little more room for the conversation feels really natural.</p></div></div>${messages.filter(m => m.channel === s.channel).map(m => `<div class="chat-message"><span class="avatar">J</span><div><b>joffrey</b><time>Now</time><p>${escape(m.text)}</p></div></div>`).join('')}<form class="chat-composer" id="chat-form"><input name="message" aria-label="Message" placeholder="Message #${escape(s.channel)}" autocomplete="off" required><button class="primary-button" aria-label="Send message">${icon('send')}</button></form></section>`;
  }
  function voiceSidebar() {
    return `<section class="sidebar full"><div class="mode-heading">Voice <small>Drop in, say hello</small></div>${['The lounge','Working together','After hours'].map((name,n) => `<div class="room-card"><div class="room-top">${icon('volume')}${name}</div><p>${['A good place for a little catch-up.','A quiet room to keep each other company.','For the conversations that wander.'][n]}</p><div class="room-people">${n===0?'<span class="avatar">M</span><span class="avatar">S</span><span>&nbsp; 2 here</span>':'No one here yet'}<button class="primary-button" data-room="${name}">${activeRoom===name?'Reopen':'Open'}</button></div></div>`).join('')}</section>`;
  }
  function roomPage(s) {
    const content = `<p class="sheet-description">${activeRoom===s.title?'You’ve joined this room in the preview.':'Take a look before joining. Your microphone stays off until you choose to join.'}</p><div class="room-people"><span class="avatar">M</span><span class="avatar">S</span><span>&nbsp; mila and sam are here</span></div><p class="sheet-description" style="margin-top:24px">${activeRoom===s.title?'Microphone muted · Local demo':'Voice room · Local demo'}</p><button class="primary-button" data-join="${escape(s.title)}">${icon('mic')}${activeRoom===s.title?'Leave room':'Join room muted'}</button>`;
    return `<section class="content-page">${toolbar('Voice')}<div class="page-title"><h2>${escape(s.title)}</h2></div>${content}</section>`;
  }
  function render() {
    const s = state();
    const contentPage = s.view !== 'sidebar';
    device.classList.toggle('content-view', contentPage);
    $('.app-header').hidden = contentPage;
    $('.bottom-nav').hidden = contentPage;
    if (s.view === 'topic') screen.innerHTML = reader(s);
    else if (s.view === 'list') screen.innerHTML = listPage(s);
    else if (s.view === 'users') screen.innerHTML = usersPage();
    else if (s.view === 'channel') screen.innerHTML = chatPage(s);
    else if (s.view === 'room') screen.innerHTML = roomPage(s);
    else if (s.mode === 'home') screen.innerHTML = `<div class="home-layout">${rail()}<section class="sidebar" aria-label="Forum navigation">${sidebar()}</section></div>`;
    else screen.innerHTML = s.mode === 'chat' ? chatSidebar() : voiceSidebar();
    $$('.bottom-nav [data-mode]').forEach(b => b.setAttribute('aria-current', b.dataset.mode === s.mode ? 'page' : 'false'));
    $('#preview-back').disabled = cursor === 0;
    $('#preview-forward').disabled = cursor === history.length-1;
    $('#history-label').textContent = s.view === 'topic' ? 'Reading topic' : s.view === 'channel' ? `# ${s.channel}` : s.title || s.mode[0].toUpperCase()+s.mode.slice(1);
    $('#instance-name').textContent = instances[instance].name;
    $('.identity .instance-logo').textContent = instances[instance].mono;
    announce($('#history-label').textContent);
  }
  function navigate(next) {
    if (JSON.stringify(state()) === JSON.stringify(next)) return;
    history = history.slice(0,cursor+1); history.push(next); cursor++; render();
  }
  function moveHistory(delta) {
    if (!overlay.hidden) { closeSheet(); return; }
    const next = cursor + delta;
    if (next < 0 || next >= history.length) return;
    cursor = next; render();
  }
  function switchInstance(index) {
    instance = index; history = [{mode:'home',view:'sidebar'}]; cursor = 0;
    messages = []; activeRoom = null; chatTab = 'channels'; closeSheet(); render();
  }
  function closeSheet() {
    if (overlay.hidden) return;
    overlay.hidden = true; overlay.innerHTML = '';
    [...device.children].filter(c => c !== overlay).forEach(c => c.inert = false);
    focusReturn?.focus();
  }
  function openSheet(type, data = '') {
    if (overlay.hidden) focusReturn = document.activeElement;
    overlay.classList.toggle('instance-menu', type === 'instances' || type === 'forum-menu');
    let title = '', content = '';
    if (type === 'search') {
      title = 'Search';
      content = `<p class="sheet-description">In ${escape(instances[instance].name)}</p><label class="search-field">${icon('search')}<input id="search-input" aria-label="Search topics" placeholder="Search topics, people, and more…" autocomplete="off"></label><div class="sheet-label" id="search-label">RECENT CONVERSATIONS</div><div class="search-results" id="search-results">${topicRows(topics.slice(0,3))}</div>`;
    } else if (type === 'forum-menu') {
      title = instances[instance].name;
      content = `<a class="sidebar-row" href="https://${escape(instances[instance].url)}" target="_blank" rel="noopener noreferrer">${icon('link')}<span class="row-label">Open forum in browser</span></a>${row('Settings','settings','data-sheet="settings"')}${row('Remove forum','close',`data-sheet="remove-instance" ${instances.length < 2 ? 'disabled' : ''}`)}`;
    } else if (type === 'remove-instance') {
      title = 'Remove forum';
      content = `<p class="sheet-description">Remove ${escape(instances[instance].name)} from this local preview?</p><button class="primary-button" data-remove-instance>Remove forum</button>`;
    } else if (type === 'instances') {
      title = 'Your communities';
      content = `<p class="sheet-description">Pick up the conversation somewhere else.</p>${instances.map((i,n) => `<button class="instance-option" data-instance="${n}" aria-pressed="${n===instance}"><span class="instance-logo">${escape(i.mono)}</span><span><b>${escape(i.name)}</b><small>${escape(i.url)}</small></span>${n===instance?`<span class="check">${icon('check')}</span>`:''}</button>`).join('')}<div class="sidebar-group">${row('Add a community','plus','data-sheet="add-instance"')}</div>`;
    } else if (type === 'settings') {
      title = 'Forum settings';
      content = `<p class="sheet-description">Make ${escape(instances[instance].name)} feel like home.</p>${row('Appearance','palette','data-sheet="appearance"',icon('right'))}${row('Notifications','bell','data-sheet="notification-settings"',icon('right'))}${row('Your profile','users','data-sheet="profile"',icon('right'))}<div class="sidebar-group">${row('Switch community','layers','data-sheet="instances"',icon('right'))}</div>`;
    } else if (type === 'appearance') {
      title = 'Appearance';
      content = `<p class="sheet-description">A look that’s yours, for ${escape(instances[instance].name)}.</p><div class="sheet-label">COLOR SCHEME</div><div class="appearance-options">${['dark','light'].map(theme => `<button data-theme-choice="${theme}" aria-pressed="${device.dataset.theme===theme}"><span class="theme-swatch swatch-${theme}"></span>${theme === 'dark' ? 'Dracula dark' : 'Dracula light'}</button>`).join('')}</div><button class="outline-button" data-sheet="settings">${icon('back')}Forum settings</button>`;
    } else if (type === 'profile') {
      title = 'Your profile';
      content = `<div class="author"><span class="avatar">J</span><div><b>joffrey</b><time>${escape(instances[instance].name)}</time></div></div>${row('Bookmarks','bookmark',topicAction('Bookmarks'))}${row('Messages','inbox',topicAction('Messages'),'3')}${row('Drafts','pencil',topicAction('Drafts'),'2')}`;
    } else if (type === 'more') {
      title = 'Explore the forum';
      content = ['Latest','New','Unread','Top','Bookmarks','Assigned'].map((name,n) => row(name,['layers','plus','inbox','star','bookmark','users'][n],topicAction(name))).join('');
    } else if (type === 'reply' || type === 'compose') {
      title = type === 'reply' ? 'Reply to the conversation' : 'New topic';
      content = `<p class="sheet-description">A local draft for this prototype.</p><form id="draft-form"><textarea aria-label="Your draft" placeholder="Start writing…" required>${escape(replyDraft)}</textarea><button class="primary-button">Save draft</button></form>`;
    } else if (type === 'notifications') {
      title = 'Notifications';
      content = `${row('mila replied to What’s on your desk this September?','chat','data-read="0"','12m')}${row('leo mentioned you in The weekend baking thread','bell','data-read="1"','28m')}`;
    } else if (type === 'notification-settings') {
      title = 'Notification preferences';
      content = `<p class="sheet-description">Notification preferences for this preview.</p>${['Mentions and replies','Direct messages','Chat activity'].map((name,n) => `<label class="sidebar-row"><span class="row-label">${name}</span><input type="checkbox" ${n<2?'checked':''} aria-label="${name}"></label>`).join('')}`;
    } else if (type === 'add-instance') {
      title = 'Add a community';
      content = `<p class="sheet-description">Add a sample community to this preview.</p><form id="instance-form"><label class="search-field"><input name="community" aria-label="Community name" placeholder="Community name" required maxlength="30"></label><button class="primary-button">Add community</button></form>`;
    }
    overlay.innerHTML = `<section class="sheet" role="dialog" aria-modal="true" aria-labelledby="sheet-title"><div class="sheet-handle"></div><div class="sheet-heading"><h2 id="sheet-title">${escape(title)}</h2><button class="icon-button" data-close aria-label="Close sheet">${icon('close')}</button></div>${content}</section>`;
    overlay.hidden = false;
    [...device.children].filter(c => c !== overlay).forEach(c => c.inert = true);
    (overlay.querySelector('input,textarea') || overlay.querySelector('[data-close]')).focus();
  }
  let suppressClick = false;
  device.addEventListener('click', event => {
    if (suppressClick) { event.preventDefault(); event.stopPropagation(); return; }
    const b = event.target.closest('button');
    if (!b) { if (event.target === overlay) closeSheet(); return; }
    if (b.hasAttribute('data-close')) closeSheet();
    else if (b.hasAttribute('data-back')) moveHistory(-1);
    else if (b.hasAttribute('data-remove-instance') && instances.length > 1) { instances.splice(instance,1); switchInstance(Math.max(0,instance-1)); }
    else if (b.dataset.instance !== undefined) switchInstance(Number(b.dataset.instance));
    else if (b.dataset.sheet) openSheet(b.dataset.sheet);
    else if (b.dataset.mode) navigate({mode:b.dataset.mode,view:'sidebar'});
    else if (b.dataset.open) { closeSheet(); navigate({mode:'home',view:b.dataset.open,title:b.dataset.title}); }
    else if (b.dataset.read !== undefined) { closeSheet(); navigate({mode:'home',view:'topic',topic:Number(b.dataset.read)}); }
    else if (b.dataset.chatTab) { chatTab = b.dataset.chatTab; render(); $(`#chat-tab-${chatTab}`).focus(); }
    else if (b.dataset.channel) { closeSheet(); navigate({mode:'chat',view:'channel',channel:b.dataset.channel}); }
    else if (b.dataset.like !== undefined) { const n=Number(b.dataset.like); likes.has(n) ? likes.delete(n) : likes.add(n); render(); }
    else if (b.dataset.themeChoice) { device.dataset.theme = b.dataset.themeChoice; openSheet('appearance'); }
    else if (b.dataset.room) navigate({mode:'voice',view:'room',title:b.dataset.room});
    else if (b.dataset.join) { activeRoom = activeRoom===b.dataset.join ? null : b.dataset.join; render(); }
  });
  device.addEventListener('change', event => {
    if (event.target.id !== 'topic-filter') return;
    filter = event.target.value;
    render();
    $('#topic-filter').focus();
  });
  $('#forum-menu').onclick = () => openSheet('forum-menu');
  $('#notifications').onclick = () => openSheet('notifications');
  $('#search').onclick = () => openSheet('search');
  $('#settings').onclick = () => openSheet('settings');
  $('#profile').onclick = () => openSheet('profile');
  $('#preview-back').onclick = () => moveHistory(-1);
  $('#preview-forward').onclick = () => moveHistory(1);
  $$('[data-width]').forEach(b => b.onclick = () => {
    $('.device-stage').style.setProperty('--preview-width',`${b.dataset.width}px`);
    $$('.preview-controls button').forEach(other => other.setAttribute('aria-pressed',other === b));
    $('.device-caption>span:last-child').textContent = `${b.dataset.width} × 844`;
  });
  overlay.addEventListener('input', event => {
    if (event.target.id !== 'search-input') return;
    const query = event.target.value.trim().toLowerCase();
    const results = topics.filter(t => `${t.title} ${t.category} ${t.author}`.toLowerCase().includes(query));
    $('#search-label').textContent = query ? `${results.length} RESULTS` : 'RECENT CONVERSATIONS';
    $('#search-results').innerHTML = results.length ? topicRows(query ? results : results.slice(0,3)) : '<p class="sheet-description">No topics found. Try “baking”, “books”, or “mila”.</p>';
  });
  device.addEventListener('submit',event => {
    event.preventDefault();
    if (event.target.id === 'chat-form') {
      const input = event.target.elements.message;
      if (!input.value.trim()) return;
      messages.push({channel:state().channel,text:input.value.trim()}); render();
      $('.content-page').scrollTop = $('.content-page').scrollHeight;
      $('#chat-form input').focus();
    } else if (event.target.id === 'draft-form') {
      replyDraft = $('textarea',event.target).value;
      closeSheet(); announce('Draft saved in the prototype.');
    } else if (event.target.id === 'instance-form') {
      const name = event.target.elements.community.value.trim();
      if (!name) return;
      instances.push({name,mono:name.slice(0,2),url:'Local preview'}); switchInstance(instances.length-1);
    }
  });
  document.addEventListener('keydown',event => {
    if (event.target.matches('[data-chat-tab]') && ['ArrowLeft','ArrowRight','Home','End'].includes(event.key) && !event.altKey) {
      event.preventDefault();
      chatTab = event.key === 'Home' ? 'channels' : event.key === 'End' ? 'dms' : chatTab === 'channels' ? 'dms' : 'channels';
      render(); $(`#chat-tab-${chatTab}`).focus();
      return;
    }
    if (event.key === 'Escape' && !overlay.hidden) { closeSheet(); return; }
    if (event.key === 'Tab' && !overlay.hidden) {
      const controls = $$('button,input,textarea,a',overlay).filter(el => !el.disabled);
      const first = controls[0], last = controls[controls.length-1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    }
    if (event.altKey && ['ArrowLeft','ArrowRight'].includes(event.key)) { event.preventDefault(); moveHistory(event.key==='ArrowLeft'?-1:1); }
  });
  let gesture = null;
  const feedback = $('#swipe-feedback');
  screen.addEventListener('pointerdown',event => {
    if (event.target.closest('input,textarea') || event.button !== 0) return;
    gesture = {x:event.clientX,y:event.clientY,id:event.pointerId};
  });
  screen.addEventListener('pointermove',event => {
    if (!gesture) return;
    const dx = event.clientX-gesture.x, dy = event.clientY-gesture.y;
    if (Math.abs(dy)>30 && Math.abs(dy)>Math.abs(dx)) { gesture=null; feedback.style.display='none'; return; }
    if (Math.abs(dx)>18 && Math.abs(dx)>Math.abs(dy)*1.5) {
      screen.setPointerCapture(event.pointerId);
      feedback.classList.toggle('forward',dx<0);
      feedback.innerHTML = icon(dx>0?'back':'right');
      feedback.style.display = (dx>0 ? cursor>0 : cursor<history.length-1) ? 'grid' : 'none';
      feedback.style.opacity = Math.min(1,Math.abs(dx)/80);
    }
  });
  screen.addEventListener('pointerup',event => {
    feedback.style.display='none';
    if (!gesture) return;
    const dx = event.clientX-gesture.x, dy = event.clientY-gesture.y;
    if (Math.abs(dx)>65 && Math.abs(dx)>Math.abs(dy)*1.5) {
      suppressClick = true; setTimeout(() => suppressClick=false,100);
      moveHistory(dx>0?-1:1);
    }
    gesture=null;
  });
  screen.addEventListener('pointercancel',() => { gesture=null; feedback.style.display='none'; });
  render();
})();
