'use strict';

// Self-contained local demonstrations; no account data or network mutations.
const paths = {
  people: '<circle cx="9" cy="8" r="3"/><path d="M3 21v-2a6 6 0 0 1 12 0v2H3Zm13-16a3 3 0 0 1 0 6m2 4a5 5 0 0 1 3 4v2h-3"/>',
  calendar: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M16 3v4M8 3v4M3 11h18m-13 5h2m4 0h2"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  pin: '<path d="M19 10c0 5-7 11-7 11S5 15 5 10a7 7 0 1 1 14 0Z"/><circle cx="12" cy="10" r="2.3"/>',
  chevron: '<path d="m6 9 6 6 6-6"/>',
  check: '<path d="m5 12 4 4L19 6"/>',
  star: '<path d="m12 3 2.8 5.7 6.3.9-4.6 4.4 1.1 6.3-5.6-3-5.6 3 1.1-6.3L3 9.6l6.2-.9Z"/>',
  close: '<path d="m6 6 12 12M6 18 18 6"/>',
  more: '<circle cx="5" cy="12" r="1" fill="currentColor"/><circle cx="12" cy="12" r="1" fill="currentColor"/><circle cx="19" cy="12" r="1" fill="currentColor"/>',
  chat: '<path d="M21 11.5a8.4 8.4 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.4 8.4 0 0 1-3.8-.9L3 21l1.9-5.7a8.4 8.4 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.4 8.4 0 0 1 3.8-.9h.5a8.5 8.5 0 0 1 8 8Z"/><path d="M8 10h8m-8 4h5"/>',
  globe: '<circle cx="12" cy="12" r="9"/><ellipse cx="12" cy="12" rx="4" ry="9"/><path d="M3 12h18"/>',
  arrow: '<path d="M7 17 17 7M7 7h10v10"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1 1m12 12 1 1M5 19l1-1M18 6l1-1"/>',
  moon: '<path d="M20.5 14A9 9 0 0 1 10 3.5 9 9 0 1 0 20.5 14Z"/>',
  desktop: '<rect x="3" y="4" width="18" height="13" rx="2"/><path d="M8 21h8m-4-4v4"/>',
  mobile: '<rect x="6" y="2" width="12" height="20" rx="2"/><path d="M10 18h4"/>',
  grid: '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
  sparkle: '<path d="m12 3 2.3 6.7L21 12l-6.7 2.3L12 21l-2.3-6.7L3 12l6.7-2.3Z"/>',
};
const icon = (name, css = '') => '<svg class="icon ' + css + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + paths[name] + '</svg>';
// Only fields visible in the supplied screenshot. The link destination is unknown.
const eventData = Object.freeze({
  title: 'Dinner @Petra',
  visibility: 'Public',
  creator: 'Aimee',
  date: 'Sep 29, 2026',
  time: '20:15 → 22:15',
  timezone: 'Europe/Madrid',
  location: 'Meet in the hotel community room to travel together-',
  linkLabel: 'Google link',
  description: [
    'Distance from Only YOU Hotel Sevilla',
    'Please check the bus route on the day to see if it is more convenient.',
    'Arrival by Tram + Walk:',
    'Please check the bus route on the day to see if it is more convenient.',
    'Walk approximately 6–8 minutes to the Luis de Morales tram stop',
    'Take the T1 MetroCentro tram → Archivo de Indias (current end of line)',
    'Walk approximately 12–15 minutes to the restaurant',
    'Reference Topic:',
  ],
  going: 2,
  interested: 0,
});
const meta = () => '<div class="meta">' + icon('globe') + '<span>' + eventData.visibility + '</span><span class="dot">·</span><span>Created by</span><span class="creator-avatar" aria-hidden="true">A</span><span>' + eventData.creator + '</span></div>';
const more = () => '<button type="button" class="button icon-button ghost more" data-action="menu" aria-label="Event actions">' + icon('more') + '</button>';
const dateTile = () => '<div class="date-tile"><span>SEP</span><strong>29</strong></div>';
const title = () => '<h3>' + eventData.title + '</h3>';
const dateTime = () => '<div class="detail date-detail">' + icon('clock') + '<div><strong>' + eventData.date + ', ' + eventData.time + '</strong><small>' + eventData.timezone + '</small></div></div>';
const locationDetail = () => '<div class="detail location-detail" data-optional="location">' + icon('pin') + '<p>' + eventData.location + ' <button class="text-link" data-action="location">' + eventData.linkLabel + ' ' + icon('arrow') + '</button></p></div>';
const description = id => '<div class="description-block" data-optional="description"><div class="description-text" id="description-' + id + '">' + eventData.description.map(line => '<p>' + line + '</p>').join('') + '</div><button class="button ghost description-toggle" aria-expanded="false" aria-controls="description-' + id + '"><span>Show full description</span>' + icon('chevron') + '</button></div>';
const attendance = () => '<div class="attendance">' + icon('people') + '<span><strong><span data-count="going">' + eventData.going + '</span> going</strong><span class="dot">·</span><span class="interested-count"><span data-count="interested">' + eventData.interested + '</span> interested</span></span></div>';
const chat = () => '<button class="button ghost chat-action" data-action="chat">' + icon('chat') + 'Open event chat</button>';
const social = () => '<div class="social-row">' + attendance() + chat() + '</div>';
const rsvp = () => '<div class="rsvp" role="group" aria-label="Your event response">' + [['going', 'check', 'Going'], ['interested', 'star', 'Interested'], ['not_going', 'close', 'Not going']].map(([value, glyph, label]) => '<button class="button rsvp-button" data-response="' + value + '" aria-pressed="false">' + icon(glyph) + '<span>' + label + '</span></button>').join('') + '</div>';
const footer = () => '<div class="event-footer">' + rsvp() + '</div>';
const templates = {
  showcase: () => '<div class="event showcase"><div class="event-header"><div class="heading-content">' + meta() + title() + '</div>' + dateTile() + more() + '</div><div class="event-body"><div class="event-details">' + dateTime() + locationDetail() + '</div>' + description('showcase') + social() + '</div>' + footer() + '</div>',
  rail: () => '<div class="event rail"><div class="date-rail"><span class="rail-month">SEP</span><strong>29</strong><span class="rail-year">2026</span><span class="rail-rule"></span>' + icon('calendar') + '</div><div class="rail-content"><div class="event-header"><div class="heading-content">' + title() + meta() + '</div>' + more() + '</div><div class="event-body"><div class="event-details">' + dateTime() + locationDetail() + '</div>' + description('rail') + social() + '</div>' + footer() + '</div></div>',
  schedule: () => '<div class="event schedule"><div class="schedule-band"><div>' + icon('calendar') + '<strong>' + eventData.date + '</strong></div><div>' + icon('clock') + '<strong>' + eventData.time + '</strong><small>' + eventData.timezone + '</small></div></div><div class="event-header"><div class="heading-content">' + title() + meta() + '</div>' + more() + '</div><div class="event-body"><div class="event-details">' + locationDetail() + '</div>' + description('schedule') + social() + '</div>' + footer() + '</div>',
  compact: () => '<div class="event compact"><div class="event-header">' + dateTile() + '<div class="heading-content">' + title() + meta() + '</div>' + more() + '</div><div class="event-body"><div class="event-details">' + dateTime() + locationDetail() + '</div>' + description('compact') + social() + '</div>' + footer() + '</div>',
};
const concepts = [
  { id: 'showcase', number: '01', title: 'Framed', description: 'The title leads. A clear header, grouped event details, and a distinct response area give the existing content room to breathe.', principles: ['Title-first hierarchy', 'Description remains free-form', 'One place for the response'], recommend: 'My pick', note: 'No cover image or additional event fields.' },
  { id: 'rail', number: '02', title: 'Date rail', description: 'A strong date anchor at the edge of the post. The remaining space belongs to the title, metadata, and whatever the author wrote.', principles: ['Date visible while scanning', 'No event-specific imagery', 'Content determines the height'], note: 'The visual identity comes from the date itself.' },
  { id: 'schedule', number: '03', title: 'Schedule band', description: 'Date and time form a quiet strip above the title. A typographic treatment gives the event presence without requiring a cover or tagline.', principles: ['Time separated from description', 'A continuous reading flow', 'Simple, theme-aware surfaces'], note: 'The same treatment works for any event subject.' },
  { id: 'compact', number: '04', title: 'Compact', description: 'A smaller calendar tile and tighter spacing keep the event close to the conversation. Long descriptions expand without taking over the post.', principles: ['Small footprint in a post', 'Existing Native control sizes', 'Every supplied field retained'], note: 'Closest to the current application vocabulary.' },
];
const state = { concept: 'showcase', width: 'wide', compare: false, content: 'all', responses: {} };
const aliases = { invitation: 'showcase', rendezvous: 'rail', ticket: 'schedule', essential: 'compact' };
const root = document.documentElement;
const container = document.querySelector('#studies');
const labels = { going: 'Going', interested: 'Interested', not_going: 'Not going' };

for (const concept of concepts) {
  const article = document.createElement('article');
  article.className = 'study';
  article.dataset.study = concept.id;
  article.setAttribute('aria-labelledby', concept.id + '-heading');
  article.innerHTML = '<aside class="study-notes"><span class="eyebrow">DIRECTION ' + concept.number + ' / 04</span><h2 id="' + concept.id + '-heading">' + concept.title + '</h2><p>' + concept.description + '</p>' + (concept.recommend ? '<div class="recommendation">' + icon('sparkle') + concept.recommend + '</div>' : '') + '<div class="design-principles">' + concept.principles.map((p, i) => '<div><span>0' + (i + 1) + '</span>' + p + '</div>').join('') + '</div><p class="height-note">' + concept.note + '</p></aside><div class="preview"><div class="post">' + templates[concept.id]() + '</div></div>';
  container.append(article);
}
document.querySelectorAll('[data-icon]').forEach(el => { el.innerHTML = icon(el.dataset.icon); });

function updateLocation() {
  const params = new URLSearchParams();
  params.set('concept', state.concept);
  if (state.compare) params.set('compare', 'all');
  if (state.width === 'narrow') params.set('width', 'mobile');
  if (root.dataset.theme === 'light') params.set('theme', 'light');
  if (state.content !== 'all') params.set('content', state.content);
  history.replaceState(null, '', '#' + params.toString());
}
function renderView({ save = true } = {}) {
  document.querySelectorAll('[data-study]').forEach(el => { el.hidden = !state.compare && el.dataset.study !== state.concept; });
  document.querySelectorAll('[data-concept]').forEach(el => el.setAttribute('aria-pressed', String(el.dataset.concept === state.concept)));
  document.querySelectorAll('[data-width]').forEach(el => el.setAttribute('aria-pressed', String(el.dataset.width === state.width)));
  document.querySelectorAll('[data-content]').forEach(el => el.setAttribute('aria-pressed', String(el.dataset.content === state.content)));
  document.querySelectorAll('[data-optional]').forEach(el => { el.hidden = state.content === 'core' || (state.content === 'no-description' && el.dataset.optional === 'description'); });
  document.body.classList.toggle('narrow', state.width === 'narrow');
  document.body.classList.toggle('comparing', state.compare);
  document.body.classList.toggle('core-only', state.content === 'core');
  document.querySelector('#compare').setAttribute('aria-pressed', String(state.compare));
  const isLight = root.dataset.theme === 'light';
  document.querySelector('#theme').innerHTML = icon(isLight ? 'moon' : 'sun') + '<span class="theme-label">' + (isLight ? 'Dark' : 'Light') + '</span>';
  document.querySelector('#theme').setAttribute('aria-label', 'Switch to ' + (isLight ? 'dark' : 'light') + ' theme');
  if (save) updateLocation();
}
function readLocation() {
  const params = new URLSearchParams(location.hash.slice(1));
  const concept = aliases[params.get('concept')] || params.get('concept');
  if (concepts.some(c => c.id === concept)) state.concept = concept;
  state.compare = params.get('compare') === 'all';
  state.width = params.get('width') === 'mobile' ? 'narrow' : 'wide';
  state.content = ['no-description', 'core'].includes(params.get('content')) ? params.get('content') : 'all';
  root.dataset.theme = params.get('theme') === 'light' ? 'light' : 'dark';
  renderView({ save: false });
}
readLocation();
window.addEventListener('hashchange', readLocation);
document.querySelectorAll('[data-concept]').forEach(el => el.addEventListener('click', () => { state.concept = el.dataset.concept; state.compare = false; renderView(); }));
document.querySelectorAll('[data-width]').forEach(el => el.addEventListener('click', () => { state.width = el.dataset.width; renderView(); }));
document.querySelectorAll('[data-content]').forEach(el => el.addEventListener('click', () => { state.content = el.dataset.content; renderView(); }));
document.querySelector('#compare').addEventListener('click', () => { state.compare = !state.compare; renderView(); });
document.querySelector('#theme').addEventListener('click', () => { root.dataset.theme = root.dataset.theme === 'dark' ? 'light' : 'dark'; renderView(); });
let toastTimer;
function announce(message) {
  const toast = document.querySelector('#toast');
  toast.textContent = message;
  toast.classList.add('visible');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toast.classList.remove('visible'), 4000);
}
function setResponse(study, response) {
  state.responses[study.dataset.study] = response;
  study.querySelectorAll('[data-response]').forEach(el => el.setAttribute('aria-pressed', String(el.dataset.response === response)));
  study.querySelector('[data-count="going"]').textContent = String(eventData.going + Number(response === 'going'));
  study.querySelector('[data-count="interested"]').textContent = String(eventData.interested + Number(response === 'interested'));
}
container.addEventListener('click', e => {
  const study = e.target.closest('[data-study]');
  if (!study) return;
  const response = e.target.closest('[data-response]');
  if (response) {
    const next = state.responses[study.dataset.study] === response.dataset.response ? null : response.dataset.response;
    setResponse(study, next);
    announce(next ? 'Preview response: ' + labels[next] : 'Preview response cleared');
    return;
  }
  const toggle = e.target.closest('.description-toggle');
  if (toggle) {
    const expanded = toggle.getAttribute('aria-expanded') !== 'true';
    toggle.setAttribute('aria-expanded', String(expanded));
    toggle.querySelector('span').textContent = expanded ? 'Show less' : 'Show full description';
    toggle.closest('.description-block').classList.toggle('expanded', expanded);
    return;
  }
  const action = e.target.closest('[data-action]')?.dataset.action;
  if (action === 'location') announce('Preview only: the Google link destination was not supplied.');
  if (action === 'chat') announce('Preview only: the event chat destination and messages were not supplied.');
  if (action === 'menu') announce('Preview only: the event menu contents are not visible in the screenshot.');
});
