/* Local HTML/CSS comparison. Sample data only; no forum requests or writes. */
const topics = [
  { id: 1, title: 'Sales pipeline review and follow-ups', category: 'Sales', tag: 'planning', replies: 18, activity: '6m', read: true, excerpt: 'Notes, open questions, and follow-ups from our latest pipeline review.', assignments: [] },
  { id: 2, title: 'Sales Stage Cross Functional', category: 'Sales', tag: 'meetings', replies: 8, activity: '2h', excerpt: 'Review the sales stages together and agree on the next steps.', assignments: [{ name: 'joffrey', target: 'Topic' }, { name: 'sales', group: true, target: 'Post #8' }], event: { date: '14 Oct', day: '14', month: 'OCT', time: '20:00', stampTime: 'Wed · 20:00', start: 'Wednesday, 14 October 2026', startTime: '20:00', end: 'Wednesday, 14 October 2026', endTime: '21:00', iso: '2026-10-14T20:00:00+02:00', kind: 'Timed event' } },
  { id: 3, title: 'Community planning day', category: 'Team', tag: 'community', replies: 12, activity: '1d', excerpt: 'A day to share what is working and plan the next quarter together.', assignments: [{ name: 'community', group: true, target: 'Topic' }], event: { date: '16 Oct', day: '16', month: 'OCT', time: 'All day', stampTime: 'Fri · All day', start: 'Friday, 16 October 2026', startTime: 'All day', iso: '2026-10-16', kind: 'All-day event' } },
  { id: 4, title: 'Team offsite: product and design', category: 'Team', tag: 'offsite', replies: 24, activity: '3h', excerpt: 'Two days to work through the roadmap, share ideas, and spend time together.', assignments: [], event: { date: '22–23 Oct', day: '22', month: 'OCT', time: '2 days', stampTime: '22–23 Oct · 2 days', start: 'Thursday, 22 October 2026', startTime: '09:00', end: 'Friday, 23 October 2026', endTime: '17:00', iso: '2026-10-22T09:00:00+02:00', kind: 'Multi-day event' } },
];
const variants = [
  { id: 'inline', letter: 'A', title: 'Inline schedule', note: '<strong>The quietest option.</strong> A calendar icon and “Event” label make the date explicit. No extra container; the title stays in charge.', recommended: true },
  { id: 'badge', letter: 'B', title: 'Schedule badge', note: '<strong>A little more emphasis.</strong> A soft background groups the event date and time. Easier to spot in a busy list, with a slightly taller row.' },
  { id: 'stamp', letter: 'C', title: 'Calendar stamp', note: '<strong>Most recognizable at a glance.</strong> The month and day sit beside the title. Works well for event-heavy lists, but gives the date more space.' },
];
const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];
const escapeHTML = (text) => String(text).replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
const icon = (name) => `<svg class="icon" aria-hidden="true"><use href="#${name}"/></svg>`;
const query = new URLSearchParams(location.search);
const state = {
  focus: variants.some((variant) => variant.id === query.get('option')) ? query.get('option') : 'all',
  mode: query.get('mode') === 'card' ? 'card' : 'compact',
  theme: query.get('theme') === 'light' ? 'light' : 'dark',
  narrow: query.get('width') === 'narrow',
};

function category(topic) {
  return `<span class="category ${topic.category === 'Team' ? 'category--team' : ''}">${escapeHTML(topic.category)}</span>`;
}

function assignments(topic) {
  if (!topic.assignments.length) return '';
  const first = topic.assignments[0];
  return `<div class="topic__assignment"><span class="assignment-label">Assigned to</span><span class="assignee" aria-label="${escapeHTML(first.target)} assigned to ${escapeHTML(first.name)}${first.group ? ', group' : ''}"><span class="avatar" aria-hidden="true">${first.group ? icon('group') : escapeHTML(first.name[0].toUpperCase())}</span>${escapeHTML(first.name)}</span>${topic.assignments.length > 1 ? `<button type="button" class="assignment-more" data-topic="${topic.id}" aria-label="View all ${topic.assignments.length} assignments for ${escapeHTML(topic.title)}">+${topic.assignments.length - 1}</button>` : ''}</div>`;
}

function eventDate(topic, variant) {
  const event = topic.event;
  const label = `Event: ${event.start}, ${event.startTime}${event.end ? ` to ${event.end}, ${event.endTime}` : ''}, Europe/Paris. View schedule.`;
  if (variant === 'stamp') {
    return `<button type="button" class="event-date" data-date="${topic.id}" aria-label="${escapeHTML(label)}"><span class="event-date__kind">Event</span><span class="event-date__separator" aria-hidden="true">·</span><span>${escapeHTML(event.stampTime)}</span></button>`;
  }
  return `<button type="button" class="event-date" data-date="${topic.id}" aria-label="${escapeHTML(label)}">${icon('calendar')}<span class="event-date__kind">Event</span><span class="event-date__separator" aria-hidden="true">·</span><time class="event-date__date" datetime="${event.iso}">${event.date}</time><span class="event-date__separator" aria-hidden="true">·</span><span class="event-date__time">${event.time}</span></button>`;
}

function topicRow(topic, variant) {
  const title = `<a class="topic__title ${topic.read ? 'topic__title--read' : ''}" data-topic="${topic.id}" href="#topic-${topic.id}">${escapeHTML(topic.title)}</a>`;
  const stamp = topic.event && variant === 'stamp';
  return `<article class="topic" aria-label="${escapeHTML(topic.title)}">
    <div class="topic__content">
      ${stamp ? `<div class="topic__event-identity"><span class="date-stamp" aria-label="${topic.event.start}"><span class="date-stamp__month">${topic.event.month}</span><span class="date-stamp__day">${topic.event.day}</span></span><div class="topic__identity">${title}${eventDate(topic, variant)}</div></div>` : `${title}${topic.event ? eventDate(topic, variant) : ''}`}
      <p class="topic__excerpt">${escapeHTML(topic.excerpt)}</p>
      <div class="topic__meta">${category(topic)}<span class="tag">${escapeHTML(topic.tag)}</span></div>
      ${assignments(topic)}
    </div>
    <div class="topic__category">${category(topic)}</div>
    <div class="topic__assigned-column">${assignments(topic) || '<span aria-label="Unassigned">—</span>'}</div>
    <span class="topic__number topic__number--replies" aria-label="${topic.replies} replies">${topic.replies}</span>
    <span class="topic__number topic__number--activity" aria-label="Last activity ${topic.activity} ago">${topic.activity}</span>
  </article>`;
}

$('#proposals').innerHTML = variants.map((variant) => `<section class="proposal proposal--${variant.id}" data-proposal="${variant.id}" aria-labelledby="heading-${variant.id}">
  <header class="proposal__heading"><span class="proposal__letter">${variant.letter}</span><h2 id="heading-${variant.id}">${variant.title}</h2>${variant.recommended ? '<span class="recommendation">Recommended</span>' : ''}</header>
  <div class="preview"><header class="preview__topbar"><span class="preview__title">Topics</span><span class="preview__feed">Latest conversations</span></header>
    <div class="topic-heading" aria-hidden="true"><span>Topic</span><span class="topic-heading__category">Category</span><span class="topic-heading__assignment">Assigned to</span><span class="topic-heading__number">Replies</span><span class="topic-heading__number">Activity</span></div>
    ${topics.map((topic) => topicRow(topic, variant.id)).join('')}
    <footer class="preview__footer">4 topics · 3 events</footer>
  </div><p class="proposal__note">${variant.note}</p>
</section>`).join('');

function renderState() {
  $('#study').dataset.focus = state.focus;
  $('#study').dataset.mode = state.mode;
  $('#study').dataset.narrow = String(state.narrow);
  document.documentElement.dataset.theme = state.theme;
  $$('[data-proposal]').forEach((element) => { element.hidden = state.focus !== 'all' && element.dataset.proposal !== state.focus; });
  $$('button[data-focus]').forEach((button) => button.setAttribute('aria-pressed', String(button.dataset.focus === state.focus)));
  $$('button[data-mode]').forEach((button) => button.setAttribute('aria-pressed', String(button.dataset.mode === state.mode)));
  $('#width-toggle').setAttribute('aria-pressed', String(state.narrow));
  $('#width-toggle').textContent = state.narrow ? 'Full width' : 'Narrow';
  const nextTheme = state.theme === 'dark' ? 'Light' : 'Dark';
  $('#theme-toggle').innerHTML = `${icon(nextTheme === 'Light' ? 'sun' : 'moon')}<span>${nextTheme}</span>`;
  $('#theme-toggle').setAttribute('aria-label', `Switch to ${nextTheme.toLowerCase()} theme`);
  const params = new URLSearchParams({ option: state.focus, mode: state.mode, theme: state.theme });
  if (state.narrow) params.set('width', 'narrow');
  history.replaceState(null, '', `${location.pathname}?${params}`);
}

function showDetails(id, scheduleOnly) {
  const topic = topics.find((item) => item.id === Number(id));
  if (!topic) return;
  $('#details-title').textContent = topic.title;
  $('#details-context').textContent = scheduleOnly ? topic.event.kind : 'Sample topic';
  const event = topic.event;
  $('#details-body').innerHTML = `${event ? `<dl><dt>Starts</dt><dd>${event.start}<span>${event.startTime}</span></dd>${event.end ? `<dt>Ends</dt><dd>${event.end}<span>${event.endTime}</span></dd>` : ''}<dt>Timezone</dt><dd>Europe/Paris<span>CEST · UTC+02:00${event.time === 'All day' ? ' · All-day calendar date' : ''}</span></dd></dl>` : `<p>${escapeHTML(topic.excerpt)}</p>`}${!scheduleOnly && topic.assignments.length ? `<div class="details__assignments">Assignments${topic.assignments.map((item) => `<p>${escapeHTML(item.target)} → ${escapeHTML(item.name)}${item.group ? ' (group)' : ''}</p>`).join('')}</div>` : ''}`;
  $('#details').showModal();
}

$$('button[data-focus]').forEach((button) => button.addEventListener('click', () => { state.focus = button.dataset.focus; renderState(); }));
$$('button[data-mode]').forEach((button) => button.addEventListener('click', () => { state.mode = button.dataset.mode; renderState(); }));
$('#width-toggle').addEventListener('click', () => { state.narrow = !state.narrow; renderState(); });
$('#theme-toggle').addEventListener('click', () => { state.theme = state.theme === 'dark' ? 'light' : 'dark'; renderState(); });
$('#proposals').addEventListener('click', (event) => {
  const date = event.target.closest('[data-date]');
  const topic = event.target.closest('[data-topic]');
  if (date) showDetails(date.dataset.date, true);
  else if (topic) { event.preventDefault(); showDetails(topic.dataset.topic, false); }
});
$('#close-details').addEventListener('click', () => $('#details').close());
$('#done-details').addEventListener('click', () => $('#details').close());
$('#details').addEventListener('click', (event) => {
  if (event.target !== $('#details')) return;
  const bounds = $('#details').getBoundingClientRect();
  if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) $('#details').close();
});
renderState();
