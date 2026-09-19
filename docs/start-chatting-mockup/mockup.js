// Standalone design prototype. Native component equivalents are documented in README.md.
const $ = (id) => document.getElementById(id);
const people = [
  { id:'maya', label:'Maya Chen', detail:'maya', initial:'M', color:'peach', type:'People' },
  { id:'theo', label:'Theo Martin', detail:'theo', initial:'T', color:'blue', type:'People' },
  { id:'lena', label:'Lena Fischer', detail:'lena', initial:'L', color:'sage', type:'People' },
  { id:'alex', label:'Alex Rivera', detail:'alex', initial:'A', color:'plum', type:'People' },
  { id:'sarah', label:'Sarah Park', detail:'sarah', initial:'S', color:'rose', type:'People' },
];
const design = { id:'design-team', label:'design', detail:'4 members', type:'Groups', count:4 };
const recent = [
  { ...people[0], id:'chat-maya', detail:'', time:'2m', type:'Recent conversations' },
  { id:'design-chat', label:'Design catch-up', detail:'Maya, Theo, you', time:'1h', type:'Recent conversations', group:true },
  { ...people[1], id:'chat-theo', detail:'', time:'3h', type:'Recent conversations' },
  { ...people[2], id:'chat-lena', detail:'', time:'Yesterday', type:'Recent conversations' },
];
const groupIcon = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" aria-hidden="true"><circle cx="9" cy="8" r="3"/><path d="M3 20v-2a6 6 0 0 1 12 0v2M16 5a3 3 0 0 1 0 6m2 3a5 5 0 0 1 3 4v2"/></svg>';
let composing = false, members = [], visible = [], active = 0, opener = $('reopen');
const escapeHTML = (value) => String(value).replace(/[&<>"']/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const memberCount = () => members.reduce((sum, member) => sum + (member.count || 1), 0);
function avatar(item) {
  return item.group || item.type === 'Groups' ? `<span class="avatar group-avatar">${groupIcon}</span>` : `<span class="avatar ${item.color}">${item.initial}</span>`;
}
function render() {
  const query = $('search').value.trim().toLowerCase();
  visible = query ? [...(composing ? [] : recent), ...people, design].filter(item => `${item.label} ${item.detail}`.toLowerCase().includes(query)) : (composing ? people : recent);
  visible = visible.filter(item => !members.some(member => member.id === item.id));
  if (composing) visible = visible.filter(item => memberCount() + (item.count || 1) <= 10);
  if (!composing && !query) visible.push({id:'new-group', label:'Create a group chat', type:'action'});
  active = Math.max(0, Math.min(active, visible.length - 1));
  let html = '', group = '';
  visible.forEach((item, index) => {
    const heading = composing && !query ? 'Suggested people' : item.type;
    if (heading !== group) {
      if (group) html += '</div>';
      if (item.type === 'action') html += '<div class="separator" role="presentation"></div>';
      html += `<div class="result-group" role="group" aria-label="${item.type === 'action' ? 'Actions' : heading}">`;
      if (item.type !== 'action') html += `<h2 class="group-heading" role="presentation">${heading}</h2>`;
      group = heading;
    }
    html += `<div class="result" id="result-${index}" role="option" aria-selected="${index === active}" data-index="${index}">${item.type === 'action' ? '<span class="action-icon" aria-hidden="true">＋</span>' : avatar(item)}<span class="result-label">${escapeHTML(item.label)}${item.detail ? ` <span class="result-detail">${escapeHTML(item.detail)}</span>` : ''}</span><span class="result-meta" aria-hidden="true"><span class="result-time">${item.time || ''}</span><span class="result-arrow">${composing ? '+' : '↵'}</span></span></div>`;
  });
  if (group) html += '</div>';
  if (!visible.length) html = `<div class="empty"><strong>${memberCount() >= 10 ? 'Your group is ready' : 'No matches found'}</strong>${memberCount() >= 10 ? 'You’ve selected the maximum of 10 people.' : 'Try another name or username.'}</div>`;
  $('results').innerHTML = html;
  syncActive();
  $('announcement').textContent = `${visible.length} results`;
}
function syncActive(scroll = false) {
  document.querySelectorAll('.result').forEach((row, index) => row.setAttribute('aria-selected', index === active));
  if (visible.length) $('search').setAttribute('aria-activedescendant', `result-${active}`);
  else $('search').removeAttribute('aria-activedescendant');
  if (scroll) $(`result-${active}`)?.scrollIntoView({block:'nearest'});
}
function refreshGroup() {
  $('title').textContent = composing ? 'New group chat' : 'Start chatting';
  $('description').textContent = composing ? 'Bring a few people into the conversation.' : 'Pick up a conversation or find someone new.';
  $('group-fields').hidden = !composing;
  $('group-actions').hidden = !composing;
  $('escape-hint').hidden = composing;
  $('enter-hint').textContent = composing ? 'add' : 'open';
  $('search').placeholder = composing ? 'Search users or groups…' : 'Search users, groups, or conversations…';
  $('search').setAttribute('aria-label', composing ? 'Search users or groups' : 'Search users, groups, or conversations');
  $('recipients').innerHTML = members.map((item) => `<button class="button outline recipient" data-remove="${item.id}" aria-label="Remove ${escapeHTML(item.label)}">${escapeHTML(item.label)} <span aria-hidden="true">×</span></button>`).join('') + `<span class="recipient-count">${memberCount()} of 10 people selected</span>`;
  $('create').disabled = members.length === 0;
  render();
}
function select(index) {
  const item = visible[index];
  if (!item) return;
  if (item.id === 'new-group' || (!composing && item.type === 'Groups')) {
    composing = true;
    members = item.type === 'Groups' ? [item] : [];
    $('search').value = '';
    active = 0;
    refreshGroup();
    $('search').focus();
  } else if (composing) {
    members.push(item);
    $('search').value = '';
    active = 0;
    refreshGroup();
    $('search').focus();
    $('announcement').textContent = `${item.label} added. ${memberCount()} ${memberCount() === 1 ? 'person' : 'people'} selected.`;
  } else finish(item.label);
}
function close() {
  $('palette').hidden = true;
  $('closed-state').hidden = false;
  $('search').setAttribute('aria-expanded', 'false');
  opener.focus();
}
function finish(label) {
  $('opened-title').textContent = label;
  $('opened-copy').textContent = 'Conversation selected. This prototype doesn’t send messages.';
  close();
  $('announcement').textContent = `Selected ${label}`;
}
function open(trigger = $('reopen')) {
  opener = trigger;
  composing = false; members = []; active = 0;
  $('search').value = ''; $('group-name').value = '';
  $('palette').hidden = false;
  $('closed-state').hidden = true;
  $('opened-title').textContent = 'Ready when you are.';
  $('opened-copy').textContent = 'Press ⌘ K to start chatting.';
  $('search').setAttribute('aria-expanded', 'true');
  refreshGroup();
  $('search').focus();
}
$('search').addEventListener('input', () => { active = 0; render(); });
$('search').addEventListener('keydown', (event) => {
  if (event.isComposing) return;
  const delta = event.key === 'ArrowDown' || (event.ctrlKey && ['n','j'].includes(event.key)) ? 1 : event.key === 'ArrowUp' || (event.ctrlKey && ['p','k'].includes(event.key)) ? -1 : 0;
  if (delta && visible.length) { event.preventDefault(); active = (active + delta + visible.length) % visible.length; syncActive(true); }
  if (event.key === 'Enter') { event.preventDefault(); select(active); }
});
$('results').addEventListener('pointermove', (event) => { const row = event.target.closest('[data-index]'); if (row) { active = Number(row.dataset.index); syncActive(); } });
$('results').addEventListener('click', (event) => { const row = event.target.closest('[data-index]'); if (row) select(Number(row.dataset.index)); });
$('recipients').addEventListener('click', (event) => { const button = event.target.closest('[data-remove]'); if (button) { members = members.filter(item => item.id !== button.dataset.remove); refreshGroup(); $('search').focus(); } });
$('back').onclick = () => { composing = false; members = []; active = 0; $('search').value = ''; $('group-name').value = ''; refreshGroup(); $('search').focus(); };
$('create').onclick = () => { if (members.length) finish($('group-name').value.trim() || members.map(item => item.label).join(', ')); };
$('close').onclick = close;
$('scrim').onclick = () => { if (!$('palette').hidden) close(); };
$('reopen').onclick = () => open($('reopen'));
$('open-again').onclick = () => open($('open-again'));
$('theme').onclick = () => { document.body.classList.toggle('dark'); $('theme').textContent = document.body.classList.contains('dark') ? 'Light appearance' : 'Dark appearance'; };
document.addEventListener('keydown', (event) => {
  if (event.isComposing) return;
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k' && !event.altKey && !event.shiftKey) { event.preventDefault(); if (event.repeat) return; $('palette').hidden ? open() : close(); }
  if (event.key === 'Escape' && !$('palette').hidden) { event.preventDefault(); close(); }
});
open();
