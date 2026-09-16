/* Design preview. All topics, people, assignments, and dates are sample data. */
const topics = [
  { id: 1, title: 'Quarterly sales forecast and pipeline health', category: 'Sales', tag: 'planning', replies: 18, activity: '6m', assignments: [] },
  { id: 2, title: 'A simpler way to handle customer handoffs', category: 'Sales', tag: 'feedback', replies: 9, activity: '21m', assignments: [] },
  { id: 3, title: 'Notes from this week’s product sync', category: 'Team', tag: 'product', replies: 12, activity: '43m', read: true, assignments: [] },
  { id: 4, title: 'October budget: open questions and approvals', category: 'Finance', tag: 'budget', replies: 31, activity: '1h', assignments: [{ name: 'finance-operations', group: true, post: 22 }, { name: 'Taylor Henry', initials: 'TH', post: 26 }] },
  { id: 5, title: 'Sales Stage Cross Functional', category: 'Sales', tag: 'meetings', replies: 8, activity: '2h', assignments: [{ name: 'Michael Fitz-Payne', initials: 'MF' }], event: { month: 'OCT', day: '14', short: 'Wed · 20:00', schedule: 'Wednesday, 14 October 2026<br>20:00–21:00 · Europe/Paris' } },
  { id: 6, title: 'Improving the new customer onboarding experience', category: 'Sales', tag: 'onboarding', replies: 52, activity: '3h', assignments: [{ name: 'Selase Amey', initials: 'SA', post: 48 }, { name: 'Jonathan Garrett', initials: 'JG', post: 50 }, { name: 'customer-success', group: true }] },
  { id: 7, title: 'What should we cover in the next community call?', category: 'Team', tag: 'community', replies: 16, activity: '4h', assignments: [] },
  { id: 8, title: 'Follow-ups from the September planning session', category: 'Team', tag: 'planning', replies: 27, activity: '6h', assignments: [{ name: 'Jonathan Garrett', initials: 'JG' }, { name: 'Michael Fitz-Payne', initials: 'MF', post: 12 }, { name: 'Taylor Henry', initials: 'TH', post: 15 }, { name: 'finance-operations', group: true, post: 22 }, { name: 'Selase Amey', initials: 'SA', post: 24 }] },
  { id: 9, title: 'Team offsite: product and design', category: 'Team', tag: 'offsite', replies: 24, activity: '8h', read: true, assignments: [], event: { month: 'OCT', day: '22', short: '22–23 Oct · 2 days', schedule: 'Thursday, 22 October 2026 · 09:00<br>to Friday, 23 October 2026 · 17:00<br>Europe/Paris' } },
  { id: 10, title: 'Share something useful you learned this week', category: 'Community', tag: 'discussion', replies: 42, activity: '1d', read: true, assignments: [] },
  { id: 11, title: 'Documentation updates for the next release', category: 'Team', tag: 'documentation', replies: 7, activity: '1d', assignments: [] },
];
const $ = (s) => document.querySelector(s);
const $$ = (s) => [...document.querySelectorAll(s)];
const escapeHTML = (s) => String(s).replace(/[&<>"']/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const query = new URLSearchParams(location.search);
const state = { placement: query.get('placement') === 'column' ? 'column' : 'inline', theme: query.get('theme') === 'light' ? 'light' : 'dark', narrow: query.get('width') === 'narrow' };
const category = (topic) => `<span class="category category--${topic.category.toLowerCase()}">${topic.category}</span>`;
const person = (assignment) => `<span class="assignment__person" aria-label="${escapeHTML(assignment.name)}${assignment.group ? ", group" : ""}"><span class="avatar" aria-hidden="true">${assignment.group ? '<svg class="icon"><use href="#group"/></svg>' : assignment.initials}</span><span class="assignment__name">${escapeHTML(assignment.name)}</span></span>`;
function assignment(topic) {
  if (!topic.assignments.length) return '';
  const first = topic.assignments[0];
  return `<span class="assignment"><span class="assignment__label">Assigned to</span>${person(first)}${first.post ? `<span class="assignment__target" aria-label="Post ${first.post}">#${first.post}</span>` : ''}${topic.assignments.length > 1 ? `<button type="button" class="assignment__more" data-topic="${topic.id}" aria-label="View all ${topic.assignments.length} assignments for ${escapeHTML(topic.title)}">+${topic.assignments.length - 1}</button>` : ''}</span>`;
}
function topicRow(topic) {
  const title = `<a class="topic__title" href="#topic-${topic.id}" data-topic="${topic.id}">${escapeHTML(topic.title)}</a>`;
  const event = topic.event;
  return `<article class="topic ${topic.read ? 'topic--read' : ''}" aria-label="${escapeHTML(topic.title)}">
    <div class="topic__content">
      ${event ? `<div class="topic__event"><span class="date-stamp" aria-label="${event.month} ${event.day}"><span class="date-stamp__month">${event.month}</span><span class="date-stamp__day">${event.day}</span></span><div class="topic__identity">${title}<button type="button" class="event-date" data-date="${topic.id}" aria-label="View schedule for ${escapeHTML(topic.title)}">Event · ${event.short}</button></div></div>` : title}
      <div class="topic__meta">${category(topic)}<span class="tag">${topic.tag}</span>${assignment(topic)}</div>
    </div>
    <div class="category-column">${category(topic)}</div>
    <div class="assignment-column">${assignment(topic) || '<span class="empty" aria-label="Unassigned">—</span>'}</div>
    <span class="number-column" aria-label="${topic.replies} replies">${topic.replies}</span>
    <span class="number-column" aria-label="Last activity ${topic.activity} ago">${topic.activity}</span>
  </article>`;
}
$('#topics').innerHTML = topics.map(topicRow).join('');
function render() {
  $('#study').dataset.placement = state.placement;
  $('#study').dataset.narrow = String(state.narrow);
  document.documentElement.dataset.theme = state.theme;
  $$('button[data-placement]').forEach((button) => button.setAttribute('aria-pressed', String(button.dataset.placement === state.placement)));
  $('#theme-toggle').textContent = state.theme === 'dark' ? 'Light theme' : 'Dark theme';
  $('#width-toggle').textContent = state.narrow ? 'Full width' : '390px pane';
  $('#width-toggle').setAttribute('aria-pressed', String(state.narrow));
  $('#placement-note').textContent = state.placement === 'inline'
    ? 'Only assigned topics show an assignee. Names, post numbers, and +N sit with the topic’s metadata; the title gets the space back.'
    : 'The current column reserves the same width in every row, even when there is no assignment. On narrow screens, assignments already move into the topic.';
  const params = new URLSearchParams({ placement: state.placement, theme: state.theme });
  if (state.narrow) params.set('width', 'narrow');
  history.replaceState(null, '', `${location.pathname}?${params}`);
}
function showDetails(id, scheduleOnly) {
  const topic = topics.find((t) => t.id === Number(id));
  if (!topic) return;
  $('#details-title').textContent = topic.title;
  $('#details-context').textContent = scheduleOnly ? 'EVENT SCHEDULE' : 'SAMPLE TOPIC · ASSIGNMENTS';
  $('#details-body').innerHTML = scheduleOnly
    ? `<p class="schedule">${topic.event.schedule}</p>`
    : topic.assignments.length ? topic.assignments.map((item) => `<div class="details__assignment">${person(item)}<span class="assignment__target">${item.post ? `Post #${item.post}` : 'Topic'}</span></div>`).join('') : '<p class="schedule">This topic has no assignments.</p>';
  $('#details').showModal();
}
$$('button[data-placement]').forEach((button) => button.addEventListener('click', () => { state.placement = button.dataset.placement; render(); }));
$('#theme-toggle').addEventListener('click', () => { state.theme = state.theme === 'dark' ? 'light' : 'dark'; render(); });
$('#width-toggle').addEventListener('click', () => { state.narrow = !state.narrow; render(); });
$('#topics').addEventListener('click', (event) => {
  const date = event.target.closest('[data-date]');
  const topic = event.target.closest('[data-topic]');
  if (date) showDetails(date.dataset.date, true);
  else if (topic) { event.preventDefault(); showDetails(topic.dataset.topic, false); }
});
$('#close-details').addEventListener('click', () => $('#details').close());
$('#done-details').addEventListener('click', () => $('#details').close());
$('#details').addEventListener('click', (event) => {
  if (event.target !== $('#details')) return;
  const rect = $('#details').getBoundingClientRect();
  if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) $('#details').close();
});
render();
