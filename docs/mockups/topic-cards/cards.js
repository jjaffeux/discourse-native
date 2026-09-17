'use strict';

const designs = {
  framed: 'A · Framed rows — individual surfaces and more internal padding, while keeping the familiar column alignment.',
  conversation: 'B · Conversation cards — a clear title and excerpt, with people and activity in a separate footer.',
  grid: 'C · Card grid — a responsive collection of self-contained topics. Columns adapt to the available width and become one in a narrow pane.'
};
let design = Object.hasOwn(designs, params.get('design')) ? params.get('design') : 'conversation';
state.mode = 'card';
state.excerpts = true;

const baseRender = render;
const baseRenderRows = renderRows;
const baseOpenMenu = openMenu;
const baseSaveURL = saveURL;

function cardSort(label, column) {
  if (isMessages() || state.scene === 'aggregate' || (column === 'category' && state.scene === 'assigned')) {
    return `<span class="card-field-name">${label}</span>`;
  }
  return sortHeading(label, column);
}

rowMarkup = function(t) {
  const selected = state.reader === t.id || (!state.reader && state.cursor === t.id);
  const status = [
    t.closed ? ['lock', 'Closed', 'closed'] : null,
    t.pinned ? ['pin', 'Pinned', 'pinned'] : null,
    t.bookmarked ? ['bookmark', 'Bookmarked', 'bookmark'] : null
  ].filter(Boolean).map(([glyph, label, cls]) => `<span class="status-icon ${cls}" title="${label}" aria-label="${label}">${icon(glyph)}</span>`).join('');
  const marker = t.unread
    ? `<span class="count" title="${t.unread} unread replies">${t.unread}</span>`
    : t.isNew || t.newReplies ? `<span class="dot" title="${t.isNew ? 'New topic' : 'New replies'}"></span>` : '';
  const stamp = t.event ? `<span class="event-stamp" aria-hidden="true"><small>${t.event.month}</small><strong>${t.event.day}</strong></span>` : '';
  const tags = (t.tags || []).slice(0, 2).map(tag => `<button class="tag" data-tag="${esc(tag)}" title="Filter by ${esc(tag)}">#${esc(tag)}</button>`).join('');
  return `<article class="topic card-topic ${t.visited ? 'visited' : ''} ${selected ? 'current' : ''} ${state.keyboard && state.cursor === t.id ? 'keyboard' : ''}" data-topic="${t.id}" aria-label="${esc(t.title)}${t.unread ? `, ${t.unread} unread replies` : ''}">
    <div class="card-top">${isMessages() ? `<span class="card-field-name">${icon('mail')} Private conversation</span>` : categoryMarkup(t)}${tags}${t.tags?.length > 2 ? `<button class="tag-overflow" data-tags="${t.id}" title="More tags">+${t.tags.length - 2}</button>` : ''}${state.scene === 'aggregate' ? `<span class="forum-name">${esc(t.forum)}</span>` : ''}</div>
    <div class="card-main">${stamp}<div class="card-copy">
      <div class="card-heading">${status}<a class="card-title" href="#topic-${t.id}" data-open="${t.id}">${esc(t.title)}</a>${marker}</div>
      ${t.excerpt ? `<p class="card-excerpt">${esc(t.excerpt)}</p>` : ''}
      ${t.event ? `<div class="event-meta"><button class="schedule" data-schedule="${t.id}">${esc(t.event.summary)}</button></div>` : ''}
    </div></div>
    <div class="card-tags">${assignmentMarkup(t)}</div>
    <div class="card-bottom">
      <div class="card-person" title="Last reply by ${esc(t.author)}">${avatar(t.author)}<span><span class="person-caption">Last reply by</span> ${esc(t.author)}</span></div>
      <div class="card-stat card-replies">${cardSort('Replies', 'posts')}<span class="stat-value">${t.replies}</span></div>
      ${state.scene === 'assigned' ? `<div class="card-stat card-views">${cardSort('Views', 'views')}<span class="stat-value">${topicViews(t).toLocaleString('en-US')}</span></div>` : ''}
      <div class="card-stat card-activity">${cardSort('Activity', 'activity')}<time class="stat-value" title="Last activity ${t.age} ago">${t.age}</time></div>
    </div>
  </article>`;
};

skeletons = () => Array.from({length: 6}, () => `<div class="topic card-topic card-skeleton" aria-hidden="true"><span class="skeleton"></span><span class="skeleton"></span><span class="skeleton"></span></div>`).join('');

renderRows = function() {
  state.mode = 'card';
  $('frame').dataset.design = design;
  baseRenderRows();
  $('columns').innerHTML = `<span>Topic</span><span class="category-heading">${cardSort('Category', 'category')}</span><span class="poster-heading">Last reply</span>${sortHeading('Replies', 'posts', 'replies-heading')}${state.scene === 'assigned' ? sortHeading('Views', 'views', 'views-heading') : ''}${sortHeading('Activity', 'activity')}`;
};

saveURL = function() {
  baseSaveURL();
  const url = new URL(location.href);
  url.searchParams.set('design', design);
  history.replaceState(null, '', url.pathname + url.search + url.hash);
};

render = function() {
  state.mode = 'card';
  baseRender();
  $('design-description').textContent = designs[design];
  document.querySelectorAll('[data-design-choice]').forEach(link => {
    if (link.dataset.designChoice === design) link.setAttribute('aria-current', 'page');
    else link.removeAttribute('aria-current');
    const url = new URL(location.href);
    url.searchParams.set('design', link.dataset.designChoice);
    link.href = url.pathname + url.search;
  });
};

openMenu = function(name, button) {
  baseOpenMenu(name, button);
  if (name === 'display') {
    $('popover').querySelectorAll('[data-mode]').forEach(item => item.remove());
    const label = $('popover').querySelector('h3');
    if (label) label.textContent = 'Card display';
  }
};

coverage = function() {
  showDialog('About this card study', `<p>Three alternative presentations of the same topics. All content is local sample data.</p><p>Try the feed, category and tag menus, filter autocomplete, event schedules, assignments, recent drafts and topic preview. Use Display to toggle excerpts and larger text.</p><p>A keeps sortable table headers. B and C use the field headings inside each card for Replies and Activity. Selecting a topic adds an outline, while hover adds a neutral fill.</p><p>Switch the context below to inspect messages, assigned topics, aggregate forums or signed-out mode. Loading, empty and error states are available in the State selector.</p><p>Native mapping: DCard for the surface and footer; DItem for hover and selection; the existing DButton, menus, taxonomy, badge, assignment and event components for controls. This is a design prototype, not a change to the Flutter app.</p>`);
};

document.addEventListener('click', event => {
  const link = event.target.closest('[data-design-choice]');
  if (!link || event.metaKey || event.ctrlKey || event.shiftKey) return;
  event.preventDefault();
  closePopover(false);
  design = link.dataset.designChoice;
  render();
});

render();
