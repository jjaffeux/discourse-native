/* Offline design fixture. Preferences belong only to this mockup. */
const topics = [
  { id: 1, title: 'Welcome to Discourse Meta', category: 'Announcements', tags: ['community'], replies: 128, age: '4m', user: 'sam', color: '#977049', pinned: true, read: true, excerpt: 'A place to discuss Discourse, share ideas, and help each other build thoughtful communities.' },
  { id: 2, title: 'What would make your everyday Discourse experience better?', category: 'UX', tags: ['design', 'feedback'], replies: 24, age: '6m', user: 'hannah', color: '#668e8d', unread: 4, excerpt: 'The little things add up. Which parts of your daily routine could feel simpler, clearer, or a little more enjoyable?' },
  { id: 3, title: 'A simpler way to browse topics on smaller screens', category: 'UX', tags: ['design', 'mobile'], replies: 18, age: '12m', user: 'lilly', color: '#9d6b89', isNew: true, excerpt: 'Exploring a calmer topic list that makes the most of the space available, especially when you are on the go.' },
  { id: 4, title: 'Share what you have been building this week', category: 'Dev', tags: ['community'], replies: 42, age: '18m', user: 'david', color: '#637daf', read: true, excerpt: 'A new theme, a helpful plugin, or a small improvement to your community. We would love to see what you have been working on.' },
  { id: 5, title: 'Category permissions for growing communities', category: 'Support', tags: ['permissions'], replies: 7, age: '26m', user: 'robin', color: '#887b62', unread: 2, excerpt: 'We are reorganizing our categories as the community grows. What is the best way to keep private spaces easy to manage?' },
  { id: 6, title: 'Introducing the new composer experience', category: 'Announcements', tags: ['release'], replies: 86, age: '32m', user: 'martin', color: '#a15f55', excerpt: 'A more natural writing experience, with everything you need close at hand. Try it out and let us know what you think.' },
  { id: 7, title: 'Keep my place when returning to a long discussion', category: 'Feature', tags: ['navigation'], replies: 15, age: '44m', user: 'mei', color: '#737d52', bookmarked: true, unread: 3, excerpt: 'It would be great to return to exactly where I left off, even after checking another topic or switching between forums.' },
  { id: 8, title: 'How do you welcome new members to your community?', category: 'Support', tags: ['community'], replies: 31, age: '1h', user: 'alex', color: '#a37552', read: true, excerpt: 'We are putting together a friendly onboarding flow and looking for inspiration from other community owners.' },
  { id: 9, title: 'Better keyboard navigation for the topic list', category: 'Feature', tags: ['accessibility'], replies: 12, age: '1h', user: 'joffrey', color: '#5f78a7', isNew: true, excerpt: 'Moving between discussions should feel fast and predictable with a keyboard. Here are a few ideas to make that happen.' },
  { id: 10, title: 'Custom fonts in a theme component', category: 'Dev', tags: ['theme-component'], replies: 6, age: '2h', user: 'jordan', color: '#806799', read: true, excerpt: 'Sharing a small theme component for custom fonts, with a few notes about performance and fallbacks.' },
  { id: 11, title: 'Notification preferences for busy categories', category: 'Support', tags: ['notifications'], replies: 9, age: '2h', user: 'sam', color: '#977049', read: true, excerpt: 'I want to follow the conversations I care about without getting notified about every new reply.' },
  { id: 12, title: 'A little more breathing room in the sidebar', category: 'UX', tags: ['design'], replies: 23, age: '3h', user: 'hannah', color: '#668e8d', unread: 5, excerpt: 'A small spacing adjustment that makes it easier to scan categories and move between conversations.' },
  { id: 13, title: 'Plugin development: a guide to getting started', category: 'Dev', tags: ['plugin', 'howto'], replies: 54, age: '4h', user: 'david', color: '#637daf', read: true, excerpt: 'From setting up your development environment to shipping your first plugin. A practical guide for new contributors.' },
  { id: 14, title: 'Resolved: images not loading after a migration', category: 'Support', tags: ['uploads'], replies: 11, age: '5h', user: 'robin', color: '#887b62', closed: true, read: true, excerpt: 'The missing images are now restored. Leaving the troubleshooting steps here for anyone with the same problem.' },
  { id: 15, title: 'Small improvements to the mobile reading experience', category: 'UX', tags: ['mobile'], replies: 17, age: '6h', user: 'lilly', color: '#9d6b89', isNew: true, excerpt: 'A collection of details that could make long discussions feel more comfortable on a phone.' },
  { id: 16, title: 'Community highlights for September', category: 'Announcements', tags: ['community'], replies: 38, age: '8h', user: 'martin', color: '#a15f55', read: true, excerpt: 'A look at what our community has shared and built this month, from helpful answers to creative new projects.' },
];

// Includes topic, post, group, and multiple-assignee examples from the Assign plugin.
const assignmentsByTopic = {
  2: [{ name: 'joffrey', color: '#5f78a7', target: 'topic' }],
  3: [{ name: 'design', group: true, target: 'topic' }],
  5: [{ name: 'support', group: true, target: 'topic' }],
  6: [{ name: 'martin', color: '#a15f55', target: 'topic' }, { name: 'hannah', color: '#668e8d', target: '#18' }],
  7: [{ name: 'sam', color: '#977049', target: '#12' }],
  9: [{ name: 'joffrey', color: '#5f78a7', target: 'topic' }],
  12: [{ name: 'hannah', color: '#668e8d', target: 'topic' }, { name: 'design', group: true, target: '#8' }],
  13: [{ name: 'david', color: '#637daf', target: 'topic' }],
};

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];
const escapeHTML = (text) => String(text).replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
const icon = (name) => `<svg class="icon" aria-hidden="true"><use href="#i-${name}"/></svg>`;
const categoryClass = (category) => category.toLowerCase();
const category = (topic) => `<span class="category ${categoryClass(topic.category)}"><span class="category-dot" aria-hidden="true"></span>${escapeHTML(topic.category)}</span>`;
const avatar = (topic) => `<span class="avatar" style="background:${topic.color}" title="Last post by ${topic.user}" aria-label="Last post by ${topic.user}">${topic.user[0].toUpperCase()}</span>`;
const storageKey = 'discourse-topic-list-html-study';
let saved = {};
try { saved = JSON.parse(localStorage.getItem(storageKey)) || {}; } catch { /* File previews can disable storage. */ }
const params = new URLSearchParams(location.search);
const state = {
  mode: ['card', 'compact'].includes(params.get('mode')) ? params.get('mode') : (['card', 'compact'].includes(saved.mode) ? saved.mode : 'compact'),
  theme: ['dark', 'light', 'system'].includes(params.get('theme')) ? params.get('theme') : (['dark', 'light', 'system'].includes(saved.theme) ? saved.theme : 'dark'),
  viewport: params.get('viewport') === 'narrow' ? 'narrow' : 'desktop',
  alignment: ['left', 'center', 'right'].includes(saved.alignment) ? saved.alignment : 'left',
  scale: [85, 100, 115, 130, 150].includes(saved.scale) ? saved.scale : 100,
  gifs: !!saved.gifs,
  feed: 'latest', category: '', tag: '', query: '',
};
const systemTheme = matchMedia('(prefers-color-scheme: dark)');

function persist() {
  try { localStorage.setItem(storageKey, JSON.stringify({ mode: state.mode, theme: state.theme, alignment: state.alignment, scale: state.scale, gifs: state.gifs })); } catch { /* The study also works without persistence. */ }
}

function topicTitle(topic) {
  const statuses = [['pinned', 'pin', 'Pinned'], ['bookmarked', 'bookmark', 'Bookmarked'], ['closed', 'lock', 'Closed']]
    .filter(([key]) => topic[key]).map(([, name, label]) => `<span class="status-icon" role="img" aria-label="${label}" title="${label}">${icon(name)}</span>`).join('');
  const marker = topic.unread ? `<span class="unread" aria-label="${topic.unread} unread replies" title="${topic.unread} unread replies">${topic.unread}</span>` : topic.isNew ? '<span class="new-dot" role="img" aria-label="New topic" title="New topic"></span>' : '';
  return `<div class="topic-title-line">${statuses}<a class="topic-link" href="#topic-${topic.id}" data-topic="${topic.id}" title="${escapeHTML(topic.title)}">${escapeHTML(topic.title)}</a>${marker}</div>`;
}

function assignmentPerson(assignment, showTarget = false) {
  const targetLabel = assignment.target === 'topic' ? 'topic' : `post ${assignment.target}`;
  const label = `Assigned to ${assignment.name}${assignment.group ? ' (group)' : ''}, ${targetLabel}`;
  const portrait = assignment.group
    ? `<span class="avatar group-avatar" aria-hidden="true">${icon('group')}</span>`
    : `<span class="avatar" style="background:${assignment.color}" aria-hidden="true">${assignment.name[0].toUpperCase()}</span>`;
  return `<span class="assignee" aria-label="${escapeHTML(label)}" title="${escapeHTML(label)}">${portrait}<span class="assignee-name">${escapeHTML(assignment.name)}</span>${showTarget && assignment.group ? '<span class="assignment-target">· group</span>' : ''}${showTarget || assignment.target !== 'topic' ? `<span class="assignment-target">${assignment.target}</span>` : ''}</span>`;
}

function assignmentSummary(topic) {
  const assignments = assignmentsByTopic[topic.id] || [];
  if (!assignments.length) return '<span class="unassigned" aria-label="Unassigned" title="Unassigned">—</span>';
  return `<span class="assignment-summary">${assignmentPerson(assignments[0])}${assignments.length > 1 ? `<button class="btn assignment-more" data-topic="${topic.id}" aria-label="Show all ${assignments.length} assignments for ${escapeHTML(topic.title)}" title="${escapeHTML(assignments.slice(1).map((assignment) => `${assignment.name} · ${assignment.target}`).join(', '))}">+${assignments.length - 1}</button>` : ''}</span>`;
}

function assignmentFooter(topic) {
  const assignments = assignmentsByTopic[topic.id] || [];
  if (!assignments.length) return '';
  return `<div class="assignment-footer"><span class="assignment-label">Assigned to</span><div class="assignment-people">${assignments.map((assignment) => assignmentPerson(assignment, true)).join('')}</div></div>`;
}

function compactRow(topic) {
  const assignments = assignmentsByTopic[topic.id] || [];
  return `<tr class="${topic.read ? 'is-read' : ''}">
    <td>${topicTitle(topic)}<div class="topic-meta"><span class="mobile-category ${categoryClass(topic.category)}"><span class="category-dot" aria-hidden="true"></span>${topic.category}</span>${topic.tags.map((tag) => `<span class="tag">${escapeHTML(tag)}</span>`).join('')}</div>
      ${assignments.length ? `<div class="compact-assignment"><span class="assignment-label">Assigned to</span>${assignmentSummary(topic)}</div>` : ''}</td>
    <td class="category-cell">${category(topic)}</td>
    <td class="assignment-cell">${assignmentSummary(topic)}</td>
    <td class="reply-count">${topic.replies}</td>
    <td><div class="last-activity">${avatar(topic)}<time title="Last activity ${topic.age} ago">${topic.age}</time></div></td>
  </tr>`;
}

function cardRow(topic) {
  return `<article class="topic-card ${topic.read ? 'is-read' : ''}">
    <div class="card-heading">${topicTitle(topic)}<time title="Last activity ${topic.age} ago">${topic.age}</time></div>
    <p class="card-excerpt">${escapeHTML(topic.excerpt)}</p>
    <div class="card-footer"><div class="card-taxonomy">${category(topic)}${topic.tags.map((tag) => `<span class="tag">${escapeHTML(tag)}</span>`).join('')}</div>
      <div class="card-activity">${avatar(topic)}<span>Last post by ${topic.user}</span><span>·</span><span>${topic.replies} replies</span></div></div>
    ${assignmentFooter(topic)}
  </article>`;
}

function filteredTopics() {
  let result = topics.filter((topic) =>
    (!state.category || topic.category === state.category) &&
    (!state.tag || topic.tags.includes(state.tag)) &&
    (!state.query || `${topic.title} ${topic.category} ${topic.tags.join(' ')} ${(assignmentsByTopic[topic.id] || []).map((assignment) => assignment.name).join(' ')}`.toLowerCase().includes(state.query.toLowerCase())) &&
    (state.feed !== 'new' || topic.isNew) &&
    (state.feed !== 'unread' || topic.unread));
  if (state.feed === 'top') result = [...result].sort((a, b) => b.replies - a.replies);
  return result;
}

function renderTopics() {
  const visible = filteredTopics();
  if (!visible.length) {
    $('#topic-content').innerHTML = '<div class="empty"><strong>No matching topics</strong><p>Try another search or clear your filters.</p><button class="btn" id="clear-filters">Clear filters</button></div>';
    $('#clear-filters').addEventListener('click', () => { state.category = ''; state.tag = ''; state.query = ''; state.feed = 'latest'; $('#category-filter').value = ''; $('#tag-filter').value = ''; $('#topic-search').value = ''; updateFeed(); renderTopics(); });
  } else if (state.mode === 'compact') {
    $('#topic-content').innerHTML = `<table class="topics-table"><caption class="sr-only">Topics in compact view</caption><colgroup><col><col class="category-col"><col class="assignment-col"><col class="replies-col"><col class="activity-col"></colgroup><thead><tr><th scope="col">Topic</th><th scope="col" class="category-cell">Category</th><th scope="col" class="assignment-cell">Assigned to</th><th scope="col" class="replies-heading">Replies</th><th scope="col">Activity</th></tr></thead><tbody>${visible.map(compactRow).join('')}</tbody></table>`;
  } else {
    $('#topic-content').innerHTML = `<div class="cards">${visible.map(cardRow).join('')}</div>`;
  }
  $('#result-count').textContent = `${visible.length} ${visible.length === 1 ? 'topic' : 'topics'}${visible.length !== topics.length ? ` of ${topics.length}` : ''}`;
  $('#mode-label').innerHTML = `${icon(state.mode === 'compact' ? 'table' : 'card')}${state.mode === 'compact' ? 'Compact' : 'Card'} view`;
  $$('[data-topic]').forEach((link) => link.addEventListener('click', (event) => { event.preventDefault(); openTopic(Number(link.dataset.topic)); }));
}

function setMode(mode, announce = false) {
  state.mode = mode;
  $$('[data-mode]').forEach((button) => button.setAttribute('aria-pressed', String(button.dataset.mode === mode)));
  const compact = mode === 'compact';
  $('#edition').textContent = compact ? '02 / COMPACT' : '01 / CARD · CURRENT';
  $('#preview-heading').textContent = compact ? 'More conversations. Less scrolling.' : 'A little context before you dive in.';
  $('#preview-description').textContent = compact ? 'A quiet table that keeps titles, categories, and activity in view.' : 'The existing card layout, with excerpts and room for each conversation.';
  $('#note-title').textContent = compact ? 'One row, the essentials.' : 'The current view, kept familiar.';
  $('#note-description').textContent = compact ? 'Titles and tags on the left. Category, assignees, replies, and activity line up for scanning. +1 reveals additional assignments.' : 'Outlined cards retain excerpts, category and tag details, and the last reply’s author. Assignments sit in a dedicated footer.';
  if (announce) $('#settings-status').textContent = `Topic list set to ${mode === 'compact' ? 'Compact' : 'Card'}`;
  $('#topic-scroll').scrollTop = 0;
  renderTopics();
  persist();
}

function setTheme(theme) {
  state.theme = theme;
  const actual = theme === 'system' ? (systemTheme.matches ? 'dark' : 'light') : theme;
  document.documentElement.dataset.theme = actual;
  $('#appearance').value = theme;
  const label = `Switch to ${actual === 'dark' ? 'light' : 'dark'} theme`;
  $('#theme-toggle').setAttribute('aria-label', label);
  $('#theme-toggle').title = label;
  $('#theme-toggle').innerHTML = icon(actual === 'dark' ? 'sun' : 'moon');
  persist();
}

function setViewport(viewport) {
  state.viewport = viewport;
  $('#app-window').classList.toggle('narrow', viewport === 'narrow');
  $$('[data-viewport]').forEach((button) => button.setAttribute('aria-pressed', String(button.dataset.viewport === viewport)));
}

function updateFeed() {
  $$('[data-feed]').forEach((button) => { const active = state.feed === button.dataset.feed; button.classList.toggle('active', active); button.setAttribute('aria-pressed', String(active)); });
}

function setAlignment(alignment) {
  state.alignment = alignment;
  $('#app-window').classList.remove('alignment-left', 'alignment-center', 'alignment-right');
  $('#app-window').classList.add(`alignment-${alignment}`);
  $$('[data-align]').forEach((button) => button.setAttribute('aria-pressed', String(button.dataset.align === alignment)));
  persist();
}

function setScale(scale) {
  state.scale = scale;
  $('#app-window').style.setProperty('--scale', scale / 100);
  $('#text-value').value = `${scale}%`;
  $('#text-decrease').disabled = scale === 85;
  $('#text-increase').disabled = scale === 150;
  $('#text-reset').disabled = scale === 100;
  persist();
}

function openTopic(id) {
  const topic = topics.find((topic) => topic.id === id);
  $('#topic-dialog-title').textContent = topic.title;
  $('#topic-dialog-category').innerHTML = category(topic);
  $('#topic-dialog-assignments').innerHTML = assignmentFooter(topic);
  $('#topic-dialog-excerpt').textContent = topic.excerpt;
  $('#topic-dialog-activity').textContent = `${topic.replies} replies · Last post by ${topic.user}`;
  $('#topic-dialog').showModal();
}

$$('[data-mode]').forEach((button) => button.addEventListener('click', () => setMode(button.dataset.mode, true)));
$$('[data-viewport]').forEach((button) => button.addEventListener('click', () => setViewport(button.dataset.viewport)));
$$('[data-align]').forEach((button) => button.addEventListener('click', () => setAlignment(button.dataset.align)));
$$('[data-open-settings]').forEach((button) => button.addEventListener('click', () => $('#settings-dialog').showModal()));
$$('[data-close-dialog]').forEach((button) => button.addEventListener('click', () => button.closest('dialog').close()));
$$('dialog').forEach((dialog) => dialog.addEventListener('click', (event) => {
  if (event.target !== dialog) return;
  const bounds = dialog.getBoundingClientRect();
  if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) dialog.close();
}));
$$('.toggle-group').forEach((group) => group.addEventListener('keydown', (event) => {
  if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
  const buttons = [...group.querySelectorAll('button[aria-pressed]')];
  if (!buttons.length || !buttons.includes(document.activeElement)) return;
  event.preventDefault();
  const current = buttons.indexOf(document.activeElement);
  const next = event.key === 'Home' ? 0 : event.key === 'End' ? buttons.length - 1 : (current + (event.key === 'ArrowRight' ? 1 : -1) + buttons.length) % buttons.length;
  buttons[next].focus(); buttons[next].click();
}));
$$('[data-feed]').forEach((button) => button.addEventListener('click', () => { state.feed = button.dataset.feed; updateFeed(); renderTopics(); $('#topic-scroll').scrollTop = 0; }));
$$('[data-category]').forEach((button) => button.addEventListener('click', () => { state.category = state.category === button.dataset.category ? '' : button.dataset.category; $('#category-filter').value = state.category; renderTopics(); }));
$('#category-filter').addEventListener('change', (event) => { state.category = event.target.value; renderTopics(); });
$('#tag-filter').addEventListener('change', (event) => { state.tag = event.target.value; renderTopics(); });
$('#topic-search').addEventListener('input', (event) => { state.query = event.target.value; renderTopics(); });
$('#theme-toggle').addEventListener('click', () => setTheme(document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark'));
$('#appearance').addEventListener('change', (event) => setTheme(event.target.value));
systemTheme.addEventListener('change', () => { if (state.theme === 'system') setTheme('system'); });
const scales = [85, 100, 115, 130, 150];
$('#text-decrease').addEventListener('click', () => setScale(scales[Math.max(0, scales.indexOf(state.scale) - 1)]));
$('#text-increase').addEventListener('click', () => setScale(scales[Math.min(scales.length - 1, scales.indexOf(state.scale) + 1)]));
$('#text-reset').addEventListener('click', () => setScale(100));
$('#gif-toggle').addEventListener('click', () => { state.gifs = !state.gifs; $('#gif-toggle').setAttribute('aria-checked', String(state.gifs)); persist(); });
document.addEventListener('keydown', (event) => {
  if (event.key === '/' && !event.ctrlKey && !event.metaKey && !$('dialog[open]') && !['INPUT', 'TEXTAREA', 'SELECT'].includes(document.activeElement.tagName)) { event.preventDefault(); $('#topic-search').focus(); }
});

$('#new-count').textContent = topics.filter((topic) => topic.isNew).length;
$('#unread-count').textContent = topics.filter((topic) => topic.unread).length;
$('#gif-toggle').setAttribute('aria-checked', String(state.gifs));
setTheme(state.theme);
setViewport(state.viewport);
setAlignment(state.alignment);
setScale(state.scale);
setMode(state.mode);
if (params.get('settings') === 'open') $('#settings-dialog').showModal();
