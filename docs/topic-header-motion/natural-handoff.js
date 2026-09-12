/* Full-content continuation of direction 02. All state belongs to this page. */
(() => {
  const root = document.getElementById('full-header-lab');
  const find = (selector) => root.querySelector(selector);
  const all = (selector) => [...root.querySelectorAll(selector)];
  const scroller = find('#conversation');
  const reader = find('#reader');
  const dock = find('#taxonomy-dock');
  const toolbar = find('#topic-header');
  const popup = find('#popover');
  const popupBody = find('#popover-content');
  const slider = find('#scroll-position');
  const motionPreference = matchMedia('(prefers-reduced-motion: reduce)');
  const appearancePreference = matchMedia('(prefers-color-scheme: dark)');
  const baseTitle = 'Customer Support Coverage Week - Seville 🇪🇸 2026';
  const longTitle = `${baseTitle}: coordinating schedules, travel, and team availability across every time zone`;
  const baseTags = ['world-meetups', 'seville'];
  const categoryChoices = { staff: ['world meetups', 'team updates'], support: ['installation', 'troubleshooting'], general: ['announcements', 'community'] };
  const state = { title: baseTitle, parent: 'staff', child: 'world meetups', tags: [...baseTags], assignee: '', closed: false, event: false, message: false, pinned: false, archived: false, listed: true, deleted: false };
  let reduced = motionPreference.matches;
  let motionOverridden = false;
  let themeOverridden = false;
  let frame = 0;
  let scrollFrame = 0;
  let noticeTimer = 0;
  let activePopup = '';
  let popupOpener = null;
  let editing = false;
  let titleCrossing = 0;
  let dockOrigin = 0;
  let postTops = [];
  const clamp = (value) => Math.max(0, Math.min(1, value));
  const escape = (value) => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const paths = {
    collapse: '<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M15 3v18M7 12h5m-3-3 3 3-3 3"/>',
    lock: '<rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3M12 14v3"/>',
    external: '<path d="M14 3h7v7M21 3l-9 9M10 5H5a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-5"/>',
    'chevron-down': '<path d="m6 9 6 6 6-6"/>',
    pencil: '<path d="m15 4 5 5M4 15 15 4a3.5 3.5 0 0 1 5 5L9 20l-6 1 1-6Z"/>',
    link: '<path d="m10 13 4-4M8 16l-1 1a4 4 0 0 1-6-6l5-5a4 4 0 0 1 6 0M16 8l1-1a4 4 0 0 1 6 6l-5 5a4 4 0 0 1-6 0" transform="translate(0 1) scale(.95)"/>',
    wrench: '<path d="M21 5a6 6 0 0 1-8 8l-8 8-3-3 8-8a6 6 0 0 1 8-8l-4 4 4 3 3-4Z"/>',
    user: '<circle cx="9" cy="7" r="3"/><path d="M3 21v-3a6 6 0 0 1 12 0v3M19 7v6M16 10h6"/>',
    bell: '<path d="M6 9a6 6 0 0 1 12 0v5l2 3H4l2-3V9M10 21h4"/>',
    inbox: '<path d="M4 5h16v14H4zM4 13h5l1 3h4l1-3h5"/>',
    chat: '<path d="M20 11a8 8 0 0 1-8 8H4l1.4-4.2A8 8 0 1 1 20 11Z"/>',
    search: '<circle cx="10" cy="10" r="6"/><path d="m15 15 5 5"/>',
    settings: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3"/>',
    close: '<path d="m6 6 12 12M6 18 18 6"/>',
    calendar: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M7 3v4M17 3v4M3 11h18M7 15h3M14 15h3"/>',
    tag: '<path d="M3 3h8l10 10-8 8L3 11V3Z"/><circle cx="7" cy="7" r="1"/>',
    down: '<path d="m7 10 5 5 5-5M12 15V4M5 20h14"/>',
    heart: '<path d="M20 5a5 5 0 0 0-8 1 5 5 0 0 0-8-1c-4 4 0 9 8 15 8-6 12-11 8-15Z"/>',
  };
  const icon = name => `<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths[name] || paths.inbox}</svg>`;
  const fillIcons = () => all('[data-icon]').forEach(node => { node.innerHTML = icon(node.dataset.icon); });
  const people = [{name:'Alex',initial:'A',color:''},{name:'Maya',initial:'M',color:'maya'},{name:'Sam',initial:'S',color:'sam'}];
  const posts = [
    [0, '2h ago', '<p>Sharing the support coverage plan for our week in Seville. Let’s make sure there’s always someone available while the rest of the team is at the meetup.</p><p>A little overlap between shifts should give us time for a proper handover. Here’s a starting point:</p><div class="coverage"><div class="coverage-row"><span>Morning · 09:00–13:00</span><span>Afternoon · 12:30–17:00</span></div><div class="coverage-row"><span>Mon — Maya</span><span>Alex</span></div><div class="coverage-row"><span>Tue — Maya</span><span>Sam</span></div><div class="coverage-row"><span>Wed — Alex</span><span>Sam</span></div></div><p>Add your availability below and we’ll fill in the rest together.</p>'],
    [1, '1h ago', '<p>Monday and Tuesday mornings work for me. I’ll check the queue before the sessions start and leave handover notes here.</p><blockquote>A little overlap between shifts should give us time for a proper handover.</blockquote><p>Yes, let’s keep that half hour. <span class="mention">@sam</span>, does Tuesday afternoon still work for you?</p>'],
    [2, '1h ago', '<p>Tuesday afternoon is good! I can take Wednesday too.</p><p>If anything needs a longer follow-up, I’ll add it here so the next person has the full context.</p>'],
    [0, '48m ago', '<p>Perfect. I’ve added both of you to the schedule.</p><p>Let’s keep all times in the local Seville time zone to make it easier to coordinate once everyone arrives.</p>'],
    [1, '35m ago', '<p>Good call on the time zone. I’ll add a calendar block for each of my shifts.</p><p>Happy to cover Thursday morning as well if we still need someone.</p>'],
    [2, '22m ago', '<p>All set for Tuesday and Wednesday. I’ll check in with the morning person before taking over.</p><p>Looking forward to seeing everyone in Seville!</p>'],
    [0, '18m ago', '<p>Thanks, everyone. We have Monday through Thursday covered now. I’ll pin the final schedule before we leave.</p>'],
    [1, '12m ago', '<p>Calendar updated. I’ll bring the handover notes template we used last time — it worked well for keeping things short and useful.</p>'],
    [2, '5m ago', '<p>Looks like we’re all set. See you there!</p>'],
  ];
  find('#posts').innerHTML = posts.map(([personIndex,time,html], i) => {
    const p = people[personIndex];
    return `<article class="post" data-post="${i+1}" aria-label="Post ${i+1} by ${p.name}"><span class="avatar ${p.color}" aria-hidden="true">${p.initial}</span><div><div class="post-heading"><strong>${p.name}</strong><time>${time} · #${i+1}</time></div><div class="post-copy">${html}</div><span class="post-reactions">${icon('heart')} ${i%4+1}</span></div></article>`;
  }).join('') + '<div class="conversation-end">You’re all caught up.</div>';

  function flash(message) { clearTimeout(noticeTimer); find('#notice').textContent = message; noticeTimer = setTimeout(() => { find('#notice').textContent = ''; }, 2200); }
  function setTheme(dark) { document.documentElement.dataset.theme = dark ? 'dark' : 'light'; find('#theme').textContent = dark ? 'Light theme' : 'Dark theme'; }
  function fitTags() {
    const list = find('#tag-list');
    const overflow = find('#tag-overflow');
    const edit = find('#edit-tags');
    find('#add-tag').hidden = state.tags.length > 0;
    edit.hidden = state.tags.length === 0;
    list.replaceChildren();
    overflow.hidden = true;
    if (!state.tags.length) return;
    const chips = state.tags.slice(0, 3).map(tag => {
      const b = document.createElement('button'); b.type = 'button'; b.className = 'native-badge';
      b.textContent = `# ${tag}`; b.dataset.action = 'browse-tag'; b.dataset.tag = tag; b.title = `Open tag ${tag}`; b.setAttribute('aria-label', `Open tag ${tag}`); list.append(b); return b;
    });
    const widths = chips.map(chip => chip.getBoundingClientRect().width);
    const available = find('#tag-controls').clientWidth;
    let visible = chips.length;
    for (; visible >= 0; visible--) {
      overflow.hidden = visible === state.tags.length;
      overflow.textContent = visible ? `+${state.tags.length-visible}` : `Tags · ${state.tags.length}`;
      const needed = widths.slice(0,visible).reduce((a,b)=>a+b,0) + Math.max(0,visible-1)*7 + edit.offsetWidth + 7 + (overflow.hidden ? 0 : overflow.offsetWidth + (visible ? 7 : 0));
      if (needed <= available || visible === 0) break;
    }
    chips.forEach((chip,i) => { if (i >= visible) chip.remove(); });
    overflow.setAttribute('aria-label', `View and edit all ${state.tags.length} topic tags`);
  }
  function updateState() {
    all('[data-topic-title]').forEach(node => { node.textContent = state.title; });
    [find('#edit-large-title'), find('#edit-compact-title')].forEach(button => button.setAttribute('aria-label', `Edit topic title: ${state.title}`));
    find('#edit-compact-title').title = state.title;
    find('#parent-name').textContent = state.parent;
    find('.privacy-icon').innerHTML = state.parent === 'staff' ? icon('lock') : '<span class="category-square"></span>';
    find('#child-name').textContent = state.child;
    find('#toolbar-category-name').textContent = state.message ? 'Private message' : state.child;
    find('#category-controls').hidden = state.message;
    for (const [action,label] of [['category',`Edit topic category: ${state.parent}`],['subcategory',`Edit topic subcategory: ${state.child}`],['browse-parent',`Browse ${state.parent}`],['browse-child',`Browse ${state.child}`]]) {
      const button = find(`[data-action="${action}"]`); button.setAttribute('aria-label', label); button.title = label;
    }
    find('#closed-badge').hidden = !state.closed;
    find('#event-trigger').hidden = !state.event;
    const assignment = find('#assignment-trigger');
    assignment.title = state.assignee ? `Manage assignment to ${state.assignee}` : 'Assign topic';
    assignment.setAttribute('aria-label', assignment.title);
    find('#assignee-label').textContent = state.assignee || 'Assign topic';
    find('#assignee-icon').innerHTML = state.assignee ? `<span class="avatar ${state.assignee.toLowerCase()}">${escape(state.assignee[0])}</span>` : icon('user');
    measure();
  }
  function measure() {
    const rect = reader.getBoundingClientRect();
    const contentLeft = find('.post-heading').getBoundingClientRect().left - rect.left;
    reader.style.setProperty('--text-inset', `${contentLeft}px`);
    reader.style.setProperty('--actions-space', `${find('#toolbar-actions').getBoundingClientRect().width + 24}px`);
    const origin = scroller.getBoundingClientRect().top;
    const offset = scroller.scrollTop;
    titleCrossing = find('#opening-title').getBoundingClientRect().bottom - origin + offset - 52;
    // offsetTop is the normal-flow location, independent of sticky positioning.
    dockOrigin = find('#opening-title').getBoundingClientRect().bottom - origin + offset;
    postTops = all('.post').map(post => post.getBoundingClientRect().top - origin + offset);
    fitTags(); paint();
  }
  function paint() {
    const offset = scroller.scrollTop;
    const progress = editing ? 0 : reduced ? Number(offset >= titleCrossing) : clamp((offset-titleCrossing+14)/28);
    const opacity = clamp(progress*2-1);
    toolbar.style.setProperty('--handoff', opacity);
    toolbar.style.setProperty('--category-opacity', 1-clamp(progress*2));
    find('#compact-title').inert = opacity === 0;
    find('#compact-title').setAttribute('aria-hidden', String(opacity === 0));
    find('#toolbar-category').setAttribute('aria-hidden', String(progress >= .5));
    dock.dataset.pinned = String(offset >= dockOrigin-52);
    slider.value = Math.min(560, offset);
    slider.setAttribute('aria-valuetext', `${Math.round(offset)} pixels from the top`);
    find('#scroll-value').textContent = `${Math.round(offset)} px`;
    let postNumber = 1;
    postTops.forEach((top,i) => { if (top <= offset+115) postNumber = i+1; });
    if (offset+scroller.clientHeight >= scroller.scrollHeight-1) postNumber = posts.length;
    find('#post-counter').textContent = `${postNumber} / 9`;
    if (reduced) find('#play-label').textContent = offset > 200 ? 'Back to top' : 'Jump to reading';
    if (activePopup) positionPopup();
  }
  function setScroll(top) { scroller.scrollTop = top; paint(); }
  function stopPlayback() { cancelAnimationFrame(frame); frame = 0; find('#play-label').textContent = reduced ? (scroller.scrollTop > 200 ? 'Back to top' : 'Jump to reading') : 'Play scroll'; find('.play-glyph').textContent = '▶'; }
  function play() {
    if (frame) { stopPlayback(); return; }
    if (editing) finishEditing(false);
    closePopup();
    if (reduced) { setScroll(scroller.scrollTop > 200 ? 0 : 360); return; }
    setScroll(0); const start = performance.now();
    const stops = [[0,0],[500,0],[3100,Math.max(180,titleCrossing+65)],[4200,460],[4850,438],[5300,438],[7300,0]];
    find('#play-label').textContent = 'Pause'; find('.play-glyph').textContent = 'Ⅱ';
    const tick = now => {
      const t = now-start;
      if (t>=7300) { setScroll(0); stopPlayback(); return; }
      const i = stops.findIndex(([at])=>at>t); const a=stops[i-1], b=stops[i];
      setScroll(a[1]+(b[1]-a[1])*(t-a[0])/(b[0]-a[0])); frame=requestAnimationFrame(tick);
    };
    frame=requestAnimationFrame(tick);
  }

  function closePopup(restore=false) {
    popup.hidden=true; activePopup='';
    all('[aria-controls="popover"]').forEach(button=>button.setAttribute('aria-expanded','false'));
    if (restore) (popupOpener?.isConnected && popupOpener.offsetWidth ? popupOpener : find('#edit-tags')).focus({preventScroll:true});
  }
  function positionPopup() {
    if (!popupOpener) return;
    const box=reader.getBoundingClientRect(), anchor=popupOpener.getBoundingClientRect();
    const top=Math.max(49,Math.min(anchor.bottom-box.top+6,reader.clientHeight-205));
    const left=Math.max(10,Math.min(anchor.left-box.left,reader.clientWidth-popup.offsetWidth-10));
    popup.style.setProperty('--popover-top', `${top}px`);
    popup.style.setProperty('--popover-left', `${left}px`);
    popup.style.setProperty('--popover-right','auto');
    popup.style.setProperty('--popover-height',`${reader.clientHeight-top-43}px`);
  }
  const option = (label, action, value='', selected=false) => `<button class="popup-option" data-action="${action}" data-value="${escape(value)}">${escape(label)}${selected?'<span class="check" aria-hidden="true">✓</span>':''}</button>`;
  function showPopup(kind, opener) {
    stopPlayback();
    if (activePopup===kind && popupOpener===opener) { closePopup(true); return; }
    closePopup(); activePopup=kind; popupOpener=opener; popup.hidden=false;
    opener.setAttribute('aria-controls','popover'); opener.setAttribute('aria-expanded','true');
    let heading='', html='';
    if (kind==='category' || kind==='subcategory') {
      heading=kind==='category'?'Edit topic category':'Edit topic subcategory';
      const choices=kind==='category'?Object.keys(categoryChoices):categoryChoices[state.parent];
      const chosen=kind==='category'?state.parent:state.child;
      html=`<input class="popup-search" type="search" aria-label="Search categories" placeholder="Search categories…">${choices.map(c=>option(c,'choose-category',c,c===chosen)).join('')}<hr class="popup-divider">${option('Browse '+chosen,'browse-current')}`;
    } else if (kind==='tags') {
      heading='Topic tags';
      const choices=[...new Set([...state.tags,...baseTags,'planning','support','meetup-2026'])];
      html=`<input class="popup-search" type="search" aria-label="Search tags" placeholder="Search tags…"><div class="popup-tag-options">${choices.map(tag=>`<label class="tag-choice"><input type="checkbox" data-tag="${escape(tag)}" ${state.tags.includes(tag)?'checked':''}><span># ${escape(tag)}</span></label>`).join('')}</div><p class="popup-caption">Select to add or remove a tag.</p>`;
    } else if (kind==='assign') {
      heading=state.assignee?'Assignments':'Assign topic';
      html=`<p class="popup-caption">Topic ${state.assignee?'assigned to '+escape(state.assignee):'unassigned'}</p>${people.map(p=>`<button class="popup-option" data-action="choose-assignee" data-value="${p.name}"><span class="avatar ${p.color}" aria-hidden="true">${p.initial}</span>${p.name}${state.assignee===p.name?'<span class="check" aria-hidden="true">✓</span>':''}</button>`).join('')}${state.assignee?'<hr class="popup-divider">'+option('Remove assignment','choose-assignee',''):''}`;
    } else if (kind==='share') {
      heading='Share topic'; html=`<h4 class="share-title">${escape(state.title)}</h4><label class="sr-only" for="share-url">Topic link</label><input class="share-url" id="share-url" readonly value="https://forum.example/t/seville-coverage/123"><div class="share-actions"><button class="native-button" data-action="copy-link">Copy link</button><button class="native-button" data-action="preview-action" data-value="Reply as new topic">Reply as new topic</button></div>`;
    } else if (kind==='actions') {
      heading='More topic actions';
      html=option('Flag topic','preview-action','Flag topic')+option(state.pinned?'Unpin topic':'Pin topic','toggle-status','pinned')+option('Select posts','preview-action','Select posts')+option(state.closed?'Open topic':'Close topic','toggle-status','closed')+option(state.archived?'Unarchive topic':'Archive topic','toggle-status','archived')+option(state.listed?'Make topic unlisted':'Make topic visible','toggle-status','listed')+'<hr class="popup-divider">'+option(state.deleted?'Recover topic':'Delete topic','delete-preview');
    } else if (kind==='event') {
      heading='Event'; html='<p class="popup-caption">Sep 21, 2026 · 09:00<br>Seville · Europe/Madrid</p>';
    } else if (kind==='notifications') {
      heading='Notifications'; html='<p class="popup-caption">3 unread items</p>'+option('Maya replied to this topic','preview-action','Maya’s reply')+option('Sam mentioned you','preview-action','Sam’s mention')+option('New topic in staff','preview-action','New topic');
    } else if (kind==='profile') {
      heading='Profile'; html=option('Set status','preview-action','Set status')+option('Bookmarks','preview-action','Bookmarks')+option('Preferences','preview-action','Preferences');
    }
    find('#popover-heading').textContent=heading; popupBody.innerHTML=html; positionPopup();
    (popupBody.querySelector('input:not([readonly]),button') || find('[data-action="close-popover"]')).focus({preventScroll:true});
  }

  function beginEditing() {
    stopPlayback(); closePopup(); editing=true; setScroll(0);
    find('#hero-title').hidden=true; find('#title-editor').hidden=false; find('#title-input').value=state.title;
    find('#title-input').focus({preventScroll:true}); measure();
  }
  function finishEditing(save) {
    if (save) { const title=find('#title-input').value.trim(); if (!title) { find('#title-input').reportValidity(); return; } state.title=title; }
    editing=false; find('#title-editor').hidden=true; find('#hero-title').hidden=false; updateState(); find('#edit-large-title').focus({preventScroll:true});
  }
  function browse(label) { find('#list-filter-label').textContent=label; closePopup(true); flash(`Browsing ${label}`); }
  root.addEventListener('click', async event => {
    const control=event.target.closest('[data-action]'); if (!control) return;
    const action=control.dataset.action;
    if (['category','subcategory','tags','assign','actions','share','event','notifications','profile'].includes(action)) showPopup(action,control);
    else if (action==='close-popover') closePopup(true);
    else if (action==='edit-title') beginEditing();
    else if (action==='cancel-title') finishEditing(false);
    else if (action==='choose-category') {
      if (activePopup==='category') { state.parent=control.dataset.value; state.child=categoryChoices[state.parent][0]; }
      else state.child=control.dataset.value;
      closePopup(true); updateState();
    } else if (action==='browse-parent') browse(state.parent);
    else if (action==='browse-child') browse(state.child);
    else if (action==='browse-current') browse(activePopup==='category'?state.parent:state.child);
    else if (action==='browse-tag') browse('# '+control.dataset.tag);
    else if (action==='choose-assignee') { state.assignee=control.dataset.value; closePopup(true); updateState(); }
    else if (action==='toggle-status') { state[control.dataset.value]=!state[control.dataset.value]; closePopup(true); updateState(); flash(control.textContent); }
    else if (action==='delete-preview') {
      if (state.deleted) { state.deleted=false; closePopup(true); flash('Topic recovered in mockup'); }
      else { find('#popover-heading').textContent='Delete topic?'; popupBody.innerHTML='<p class="popup-caption">This only changes the local preview.</p>'+option('Cancel','close-popover')+option('Delete topic','confirm-delete'); positionPopup(); popupBody.querySelector('button').focus(); }
    } else if (action==='confirm-delete') { state.deleted=true; closePopup(true); flash('Topic deleted in mockup · Recover it from topic actions'); }
    else if (action==='preview-action') { closePopup(true); flash(`${control.dataset.value} · preview`); }
    else if (action==='copy-link') {
      try { await navigator.clipboard.writeText(find('#share-url').value); flash('Example link copied'); }
      catch { find('#share-url').select(); flash('Select and copy the example link'); }
    } else if (action==='latest') { stopPlayback(); closePopup(); setScroll(scroller.scrollHeight); }
    else if (action==='collapse') { stopPlayback(); closePopup(); find('#preview').classList.add('collapsed'); find('#reader-closed').hidden=false; find('[data-action="reopen"]').focus(); }
    else if (action==='reopen') reopen();
  });
  function reopen() { find('#preview').classList.remove('collapsed'); find('#reader-closed').hidden=true; find('[data-action="collapse"]').focus({preventScroll:true}); measure(); }
  find('#reopen-topic').addEventListener('click',reopen);
  popupBody.addEventListener('input', event => {
    if (!event.target.matches('.popup-search')) return;
    const term=event.target.value.toLowerCase();
    popupBody.querySelectorAll('.popup-option,.tag-choice').forEach(row=>{ row.hidden=!row.textContent.toLowerCase().includes(term); });
  });
  popupBody.addEventListener('change',event=>{
    const tag=event.target.dataset.tag; if (!tag) return;
    state.tags=event.target.checked?[...new Set([...state.tags,tag])]:state.tags.filter(value=>value!==tag); fitTags();
  });
  find('#title-editor').addEventListener('submit',event=>{event.preventDefault();finishEditing(true);});
  find('#title-input').addEventListener('keydown',event=>{if(event.key==='Enter'&&!event.shiftKey){event.preventDefault();finishEditing(true);}});
  root.addEventListener('keydown',event=>{if(event.key==='Escape'){if(activePopup)closePopup(true);else if(editing)finishEditing(false);}});
  document.addEventListener('pointerdown',event=>{if(activePopup&&!popup.contains(event.target)&&!popupOpener?.contains(event.target))closePopup();});
  scroller.addEventListener('scroll',()=>{cancelAnimationFrame(scrollFrame);scrollFrame=requestAnimationFrame(paint);},{passive:true});
  ['wheel','touchstart','pointerdown','keydown'].forEach(event=>scroller.addEventListener(event,stopPlayback,{passive:true}));
  slider.addEventListener('input',()=>{stopPlayback();closePopup();setScroll(Number(slider.value));});
  find('#top').addEventListener('click',()=>{stopPlayback();setScroll(0);});
  find('#play').addEventListener('click',play);
  find('#viewport').addEventListener('change',event=>{stopPlayback();root.classList.toggle('narrow-mode',event.target.value==='narrow');measure();});
  find('#long-title').addEventListener('change',event=>{stopPlayback();state.title=event.target.checked?longTitle:baseTitle;updateState();});
  find('#scenario').addEventListener('change',event=>{
    stopPlayback();closePopup();if(editing)finishEditing(false);
    const scenario=event.target.value;
    Object.assign(state,{assignee:scenario==='assigned'?'Sam':'',closed:scenario==='assigned',event:scenario==='event',message:scenario==='message',tags:scenario==='tags'?[...baseTags,'planning','support','meetup-2026','travel','handover','scheduling']: [...baseTags]});
    updateState();setScroll(0);
  });
  find('#theme').addEventListener('click',()=>{themeOverridden=true;setTheme(document.documentElement.dataset.theme!=='dark');});
  appearancePreference.addEventListener('change',()=>{if(!themeOverridden)setTheme(appearancePreference.matches);});
  find('#reduce-motion').checked=reduced;
  find('#reduce-motion').addEventListener('change',event=>{motionOverridden=true;reduced=event.target.checked;stopPlayback();paint();});
  motionPreference.addEventListener('change',()=>{if(!motionOverridden){reduced=motionPreference.matches;find('#reduce-motion').checked=reduced;stopPlayback();paint();}});
  find('#inline-account').addEventListener('change',event=>{(event.target.checked?find('#toolbar-account-slot'):find('.window-bar')).append(find('#account-actions'));measure();});
  const observer=new ResizeObserver(measure);
  [reader,find('#toolbar-actions'),find('#opening-title')].forEach(node=>observer.observe(node));
  document.addEventListener('visibilitychange',()=>{if(document.hidden)stopPlayback();});
  window.addEventListener('pagehide',()=>{stopPlayback();cancelAnimationFrame(scrollFrame);clearTimeout(noticeTimer);observer.disconnect();});
  fillIcons();setTheme(appearancePreference.matches);updateState();paint();
})();
