/* Standalone design prototypes. All actions are local, simulated state. */
const concepts = [
  { id: 'focus', name: 'The balanced room', description: 'A focused stage, useful empty space, and one clear row of call controls.', detail: '<strong>Floating call card.</strong> Room name, live status, mute and leave in a compact surface. The easiest return to the conversation.', recommended: true },
  { id: 'lounge', name: 'The voice lounge', description: 'People first. A quieter, audio-led space that feels like a room, not a meeting.', detail: '<strong>Floating voice capsule.</strong> A smaller footprint, with a live audio mark and direct controls. Best when cameras are usually off.' },
  { id: 'stage', name: 'The video stage', description: 'More space for faces. A taller video canvas with controls always within reach.', detail: '<strong>Floating picture-in-picture.</strong> Keep a visual connection while browsing. Tap the preview to reopen the room.' },
];
const state = Object.fromEntries(concepts.map(c => [c.id, { route: 'room', active: true, muted: false, camera: true, deafened: false, previousMute: false, count: 1, sheet: null, invited: [], rear: false }]));
const root = document.getElementById('concepts');
let toastTimer;
const icon = name => `<svg class="icon" aria-hidden="true"><use href="assets/icons.svg#${name}"></use></svg>`;
const wave = () => '<span class="wave" aria-hidden="true"><i></i><i></i><i></i><i></i></span>';
const camera = () => '<svg class="camera-view" viewBox="60 560 1170 620" preserveAspectRatio="xMidYMid slice" role="img" aria-label="Your camera preview, using the supplied reference image"><image href="assets/reference.png" width="1290" height="2796"/></svg>';
const button = (action, glyph, label, classes = '', pressed = null) => `<button class="icon-btn ${classes}" data-action="${action}" aria-label="${label}" title="${label}" ${pressed === null ? '' : `aria-pressed="${pressed}"`}>${icon(glyph)}</button>`;
const avatar = (initials = 'J', tone = '') => `<span class="avatar ${tone}" aria-hidden="true">${initials}</span>`;
function siteBar() {
  return `<div class="site-bar">${button('browse', 'menu', 'Browse community', 'ghost small')}<div class="site-brand"><span class="site-logo">d</span>Discourse Meetup</div>${button('search', 'search', 'Search preview', 'ghost small')}<span class="tiny-avatar" aria-label="Your profile">JJ</span></div>`;
}
function roomHeader(s) {
  return `<header class="room-header">${button('browse', 'arrow-left', 'Browse while staying in the call', 'ghost small')}<div class="room-title"><h3>Watercooler</h3><p>Discourse Meetup</p></div>${button('invite', 'user-plus', 'Invite people', 'ghost small')}</header><div class="connection-row"><span class="connection-status"><span class="live-dot"></span>Connected <span class="duration">· 04:32</span></span><span>${s.count === 1 ? 'Just you' : `${s.count} in the room`}</span></div>`;
}
function tile(s, id, index) {
  const people = [{ name: 'joffrey', initials: 'J', tone: '' }, { name: 'Sarah', initials: 'S', tone: 'rose' }, { name: 'Sam', initials: 'S', tone: 'blue' }, { name: 'Alex', initials: 'A', tone: 'gold' }];
  const p = people[index];
  const speaking = index === 1 || (s.count === 1 && !s.muted);
  return `<div class="participant-tile ${speaking ? 'speaking' : ''}">${index === 0 && s.camera ? camera() : `<div class="avatar-wrap">${avatar(p.initials, p.tone)}</div>`}${id === 'stage' && index === 0 && s.count === 1 ? `<span class="stage-topline">${icon(s.camera ? 'video' : 'video-off')}${s.camera ? 'Your camera is on' : 'Your camera is off'}</span>` : ''}<div class="tile-caption"><span>${p.name}</span>${index === 0 ? '<span class="you-label">(you)</span>' : ''}${speaking ? wave() : icon(index === 0 && !s.muted ? 'mic' : 'mic-off')}</div></div>`;
}
function controls(s) {
  return `<div class="call-tray"><div class="tray-meta">${s.deafened ? icon('headphone-off') : s.muted ? icon('mic-off') : wave()}<span>${s.deafened ? 'Sound and microphone off' : s.muted ? 'Your microphone is muted' : 'Your microphone is on'}</span></div><div class="tray-controls">${button('mute', s.muted ? 'mic-off' : 'mic', s.muted ? 'Unmute microphone' : 'Mute microphone', s.muted ? 'muted' : 'active', s.muted)}${button('camera', s.camera ? 'video' : 'video-off', s.camera ? 'Turn camera off' : 'Turn camera on', s.camera ? '' : 'active', s.camera)}${button('audio', s.deafened ? 'headphone-off' : 'headphones', s.deafened ? 'Turn sound on' : 'Turn sound off', s.deafened ? 'muted' : '', s.deafened)}${button('more', 'ellipsis', 'More call options')}<span class="tray-separator"></span>${button('leave', 'phone-off', 'Leave room', 'leave')}</div></div>`;
}
function room(s, id) {
  const lounge = id === 'lounge';
  return `${id === 'focus' ? siteBar() : ''}${roomHeader(s)}<div class="room-body">${lounge ? '<p class="room-intro">A place to drop in, catch up,<br>and think out loud.</p>' : ''}<div class="participant-grid ${s.count > 1 ? 'group' : ''}">${Array.from({ length: s.count }, (_, i) => tile(s, id, i)).join('')}</div>${id !== 'stage' ? `<div class="welcome"><h4>${s.count === 1 ? 'Make yourself at home' : lounge ? 'The conversation is open' : 'Everyone’s here'}</h4><p>${s.count === 1 ? 'You’re the first one here.<br>Bring someone into the conversation.' : lounge ? 'Jump in whenever you like.' : 'A good place to catch up and share ideas.'}</p>${s.count === 1 ? `<button class="text-button" data-action="invite">${icon('user-plus')}Invite someone</button>` : ''}</div>` : ''}</div>${controls(s)}<div class="home-indicator"></div>`;
}
function floating(s, id) {
  if (!s.active || s.route === 'room') return '';
  const mute = button('mute', s.muted ? 'mic-off' : 'mic', s.muted ? 'Unmute microphone' : 'Mute microphone', `small ${s.muted ? 'muted' : ''}`, s.muted);
  const leave = button('leave', 'phone-off', 'Leave room', 'small leave');
  const label = `<span class="float-label"><strong>Watercooler</strong><small>${s.muted ? 'Mic muted' : 'Live'} · ${s.count} ${s.count === 1 ? 'person' : 'people'}</small></span>`;
  if (id === 'stage') return `<aside class="float-widget pip" aria-label="Active Watercooler call"><button class="pip-open" data-action="room" aria-label="Return to Watercooler">${s.camera ? camera() : avatar()}<span class="pip-caption">Watercooler ${icon('maximize-2')}</span></button><div class="pip-actions"><span class="pip-time"><span class="live-dot"></span>04:32</span>${mute}${leave}</div></aside>`;
  return `<aside class="float-widget ${id === 'lounge' ? 'capsule' : 'compact'}" aria-label="Active Watercooler call"><button class="float-open" data-action="room" aria-label="Return to Watercooler">${id === 'lounge' ? wave() : `<span class="float-art">${s.camera ? camera() : icon('headphones')}</span>`}${label}</button>${mute}${leave}</aside>`;
}
function browse(s, id) {
  const topics = [
    ['General', 'What’s everyone working on this week?', 'M', '24', '8m'],
    ['Community', 'Small rituals that make a community feel like home', 'S', '18', '26m'],
    ['Design', 'The little details that make a big difference', 'A', '12', '1h'],
    ['General', 'Share something you learned recently', 'J', '31', '2h'],
    ['Community', 'Our next community meetup', 'N', '9', '3h'],
  ];
  return `${siteBar()}<section class="browse-content"><span class="browse-eyebrow">Your community</span><h3>Good conversations.</h3><div class="feed-filters"><strong>Latest</strong><span>New <b>6</b></span><span>Unread <b>12</b></span></div>${topics.map(t => `<article class="topic"><span class="topic-category"><span class="category-dot"></span>${t[0]}</span><h4>${t[1]}</h4><div class="topic-meta"><span class="tiny-avatar">${t[2]}</span><span>Last reply ${t[4]} ago</span>${icon('message-circle')}<span>${t[3]}</span></div></article>`).join('')}</section>${floating(s, id)}<nav class="app-tabs" aria-label="App navigation"><button data-action="browse" class="selected">${icon('house')}Start</button><button data-action="browse">${icon('messages-square')}Topics</button><button data-action="chat">${icon('message-circle')}Chat</button><button data-action="room">${icon('headphones')}Voice</button></nav><div class="home-indicator"></div>`;
}
function sheet(s) {
  if (!s.sheet) return '';
  const title = s.sheet === 'invite' ? 'Bring someone in' : s.sheet === 'more' ? 'Call options' : s.sheet === 'search' ? 'Search the community' : 'Community chat';
  let body;
  if (s.sheet === 'invite') {
    body = '<p>Invite someone to Watercooler.</p>' + ['Sarah', 'Sam', 'Alex'].map((name, i) => `<div class="invite-person">${avatar(name[0], ['rose', 'blue', 'gold'][i])}<span>${name}</span><button class="text-button" data-action="invite-person" data-name="${name}" ${s.invited.includes(name) ? 'disabled' : ''}>${s.invited.includes(name) ? 'Invited' : 'Invite'}</button></div>`).join('');
  } else if (s.sheet === 'more') {
    body = `<button class="menu-action" data-action="audio-output">${icon('headphones')}Audio output<span>Headphones</span></button><button class="menu-action" data-action="flip" ${s.camera ? '' : 'disabled'}>${icon('switch-camera')}Switch camera<span>${s.rear ? 'Rear' : 'Front'}</span></button><button class="menu-action" data-action="invite">${icon('user-plus')}Invite people</button><button class="menu-action" data-action="browse">${icon('minimize-2')}Browse while in call</button>`;
  } else {
    body = '<p>This preview focuses on the voice room. Your call stays connected while you explore the rest of the app.</p><button class="text-button" data-action="close-sheet">Back to browsing</button>';
  }
  return `<div class="sheet-scrim"><section class="sheet" role="dialog" aria-modal="true" aria-label="${title}"><div class="sheet-header"><h4>${title}</h4>${button('close-sheet', 'x', 'Close dialog', 'ghost small')}</div>${body}</section></div>`;
}
function ended() {
  return `${siteBar()}<div class="ended">${icon('phone-off')}<h3>You left Watercooler</h3><p>The room is still here when you need it.</p><button class="text-button" data-action="rejoin">${icon('headphones')}Rejoin room</button></div><div class="home-indicator"></div>`;
}
function conceptMarkup(c, index) {
  const s = state[c.id];
  return `<article class="concept ${c.id}" data-concept="${c.id}"><div class="concept-heading"><span class="concept-number">0${index + 1}</span><h2>${c.name}</h2>${c.recommended ? '<span class="recommendation">Recommended</span>' : ''}</div><p class="concept-description">${c.description}</p><div class="phone"><div class="phone-top"><span>11:41</span><span class="dynamic-island" aria-hidden="true"></span><span class="device-signals">${icon('signal')}${icon('wifi')}${icon('battery-full')}</span></div><div class="phone-content">${s.route === 'browse' ? browse(s, c.id) : s.active ? room(s, c.id) : ended()}${sheet(s)}</div></div><div class="route-indicator"><span>${icon(s.route === 'room' ? 'headphones' : 'messages-square')}${s.route === 'room' ? 'Watercooler room' : 'Browsing topics'}${!s.active ? ' · Call ended' : ''}</span><button data-action="${s.route === 'room' ? 'browse' : 'room'}">${s.route === 'room' ? 'Preview floating widget ↗' : 'Return to room ↗'}</button></div><p class="concept-detail">${c.detail}</p></article>`;
}
function render(id, focusAction) {
  if (id) {
    const i = concepts.findIndex(c => c.id === id);
    root.querySelector(`[data-concept="${id}"]`).outerHTML = conceptMarkup(concepts[i], i);
    const scope = root.querySelector(`[data-concept="${id}"]`);
    const modal = scope.querySelector('.sheet-scrim');
    if (modal) {
      for (const el of scope.querySelector('.phone-content').children) if (el !== modal) el.inert = true;
      modal.querySelector('button')?.focus({ preventScroll: true });
    } else if (focusAction) {
      scope.querySelector(`[data-action="${focusAction}"]`)?.focus({ preventScroll: true });
    }
  } else root.innerHTML = concepts.map(conceptMarkup).join('');
  const routes = new Set(Object.values(state).map(s => s.route));
  document.querySelectorAll('[data-global-route]').forEach(b => b.setAttribute('aria-pressed', routes.size === 1 && routes.has(b.dataset.globalRoute)));
}
function notify(id, message) {
  document.querySelectorAll('.toast').forEach(n => n.remove());
  clearTimeout(toastTimer);
  const node = document.createElement('div'); node.className = 'toast'; node.setAttribute('role', 'status'); node.textContent = message;
  root.querySelector(`[data-concept="${id}"] .phone-content`).append(node);
  toastTimer = setTimeout(() => node.remove(), 2600);
}
root.addEventListener('click', event => {
  const target = event.target.closest('[data-action]');
  if (!target) return;
  const id = target.closest('[data-concept]').dataset.concept;
  const s = state[id];
  const action = target.dataset.action;
  if (action === 'browse' || action === 'room') { s.route = action; s.sheet = null; }
  else if (action === 'mute') { if (s.deafened) { s.deafened = false; s.muted = false; } else s.muted = !s.muted; }
  else if (action === 'camera') s.camera = !s.camera;
  else if (action === 'audio') { if (s.deafened) { s.deafened = false; s.muted = s.previousMute; } else { s.previousMute = s.muted; s.deafened = true; s.muted = true; } }
  else if (['more', 'invite', 'search', 'chat'].includes(action)) s.sheet = action;
  else if (action === 'close-sheet') s.sheet = null;
  else if (action === 'leave') { s.active = false; s.sheet = null; }
  else if (action === 'rejoin') { s.active = true; s.route = 'room'; }
  else if (action === 'invite-person') s.invited.push(target.dataset.name);
  else if (action === 'flip') { s.rear = !s.rear; render(id); notify(id, `${s.rear ? 'Rear' : 'Front'} camera selected · simulated preview`); return; }
  else if (action === 'audio-output') { notify(id, 'Headphones selected · simulated audio output'); return; }
  render(id, action === 'close-sheet' ? 'more' : ['camera', 'mute', 'audio', 'rejoin'].includes(action) ? action : null);
  if (action === 'invite-person') notify(id, `Invitation to ${target.dataset.name} simulated`);
});
root.addEventListener('keydown', event => {
  const dialog = event.target.closest('.sheet');
  if (!dialog) return;
  if (event.key === 'Escape') { const id = dialog.closest('[data-concept]').dataset.concept; state[id].sheet = null; render(id, 'more'); }
  if (event.key === 'Tab') {
    const controls = Array.from(dialog.querySelectorAll('button:not(:disabled)'));
    if (event.shiftKey && document.activeElement === controls[0]) { event.preventDefault(); controls.at(-1).focus(); }
    else if (!event.shiftKey && document.activeElement === controls.at(-1)) { event.preventDefault(); controls[0].focus(); }
  }
});
document.querySelectorAll('[data-global-route]').forEach(button => button.addEventListener('click', () => { for (const s of Object.values(state)) { s.route = button.dataset.globalRoute; s.sheet = null; } render(); }));
document.getElementById('scenario').addEventListener('change', event => { for (const s of Object.values(state)) { s.count = Number(event.target.value); s.sheet = null; } render(); });
document.getElementById('theme').addEventListener('change', event => { root.dataset.theme = event.target.value; });
document.getElementById('reset').addEventListener('click', () => { for (const s of Object.values(state)) Object.assign(s, { route: 'room', active: true, muted: false, camera: true, deafened: false, previousMute: false, count: 1, sheet: null, invited: [], rear: false }); document.getElementById('scenario').value = '1'; render(); });
render();
