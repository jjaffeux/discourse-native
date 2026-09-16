const paths = {
  check: '<path d="m5 12 4 4L19 6"/>',
  cloud: '<path d="M7 18H6a4 4 0 0 1-.8-7.9A7 7 0 0 1 18.8 8a5 5 0 0 1 .2 10"/><path d="m9 17 3 3 5-6"/>',
  loader: '<path d="M12 3a9 9 0 1 1-9 9"/>',
  device: '<rect x="4" y="3" width="16" height="13" rx="2"/><path d="M8 21h8m-4-5v5"/>',
  alert: '<circle cx="12" cy="12" r="9"/><path d="M12 7v6m0 4h.01"/>',
  reply: '<path d="m9 5-6 6 6 6m-6-6h10a7 7 0 0 1 7 7"/>',
  close: '<path d="m6 6 12 12M6 18 18 6"/>',
  minus: '<path d="M5 12h14"/>',
  dock: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M15 4v16"/>',
  chevron: '<path d="m8 10 4 4 4-4"/>',
  trash: '<path d="M3 6h18M9 6V3h6v3m-10 0 1 15h12l1-15M10 10v7m4-7v7"/>',
  clip: '<path d="m8 12 6-6a3 3 0 0 1 4 4l-8 8a5 5 0 0 1-7-7l9-9m-6 12 8-8"/>',
  smile: '<circle cx="12" cy="12" r="9"/><path d="M8 14s1 3 4 3 4-3 4-3M8 9h.01M16 9h.01"/>',
  more: '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
  link: '<path d="m10 13 4-4m-5 7-1 1a4 4 0 0 1-6-6l4-4a4 4 0 0 1 6 0m0 10a4 4 0 0 0 6 0l4-4a4 4 0 0 0-6-6l-1 1"/>',
  list: '<path d="M9 6h12M9 12h12M9 18h12M3 6h.01M3 12h.01M3 18h.01"/>',
  code: '<path d="m8 7-5 5 5 5m8-10 5 5-5 5"/>',
  quote: '<path d="M4 12h5V5H3v7c0 4 2 6 5 7m9-7h5V5h-6v7c0 4 2 6 5 7"/>'
};
const icon = name => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths[name]}</svg>`;
const chrome = (name, extra = '') => `<span class="chrome-icon ${extra}">${icon(name)}</span>`;
const draft = 'I like the direction this is taking. The quieter header makes it much easier to stay focused on the conversation.\n\nOne small detail: could we keep the draft status visible without adding another row?';
const definitions = [
  { id: 'footer', n: '01', title: 'In the action bar', description: 'A familiar status, moved onto the existing footer row.', behavior: 'Always visible.', detail: 'A muted check and “Draft saved” sit opposite Reply.', tradeoff: 'Most familiar, but competes with footer actions on narrow composers.' },
  { id: 'header', n: '02', title: 'In the header', description: 'A small, steady signal beside the composer controls.', behavior: 'Always in the same place.', detail: '“Saving…” becomes “Saved” without shifting the editor.', tradeoff: 'Best balance of reassurance, visibility and room for plugins.' },
  { id: 'ambient', n: '03', title: 'Confirm, then recede', description: 'A brief confirmation settles into a quiet status icon.', behavior: 'Visible when it changes.', detail: '“Draft saved” appears for 2.4 seconds, then only the icon remains.', tradeoff: 'Least visual noise; the resting icon is less explicit. Click it for details.' }
];
const stateInfo = {
  saved: { icon: 'check', long: 'Draft saved', short: 'Saved', detail: 'Saved on the site. You can safely close the composer.' },
  saving: { icon: 'loader', long: 'Saving…', short: 'Saving…', detail: 'Saving the latest changes on the site…' },
  local: { icon: 'device', long: 'Device only', short: 'Device only', detail: 'Couldn’t save on the site. A copy is saved on this device.' },
  error: { icon: 'alert', long: 'Not saved', short: 'Not saved', detail: 'Couldn’t save your latest changes. Keep this composer open and try again.' }
};
let saveTimer;
let fadeTimer;
const studies = document.querySelector('#studies');

for (const d of definitions) {
  const article = document.createElement('article');
  article.className = 'study';
  article.dataset.direction = d.id;
  article.innerHTML = `
    <div class="study-title"><span class="number">${d.n}</span><h2>${d.title}</h2>${d.id === 'header' ? '<span class="preferred">Recommended</span>' : ''}</div>
    <p class="study-description">${d.description}</p>
    <div class="composer" aria-label="${d.title} composer mockup">
      <div class="composer-header">
        <span class="composer-title">${icon('reply')} Reply ${icon('chevron')}</span>
        ${d.id === 'header' ? '<span class="status header-status" role="status" aria-live="polite" aria-atomic="true"></span>' : ''}
        <span class="header-actions" aria-hidden="true">${chrome('dock', 'dock')}${chrome('minus')}${chrome('close')}</span>
      </div>
      <div class="context">${icon('reply')}<span>Making the composer feel more native</span></div>
      <div class="formatting" aria-hidden="true"><span class="chrome-icon"><b>B</b></span><span class="chrome-icon"><i>I</i></span>${chrome('link')}<span class="format-divider"></span>${chrome('quote')}${chrome('code')}${chrome('list')}<span class="footer-spacer"></span>${chrome('more')}</div>
      <textarea class="editor" aria-label="Draft text, ${d.title}" spellcheck="false"></textarea>
      <div class="warning" hidden><p></p><button class="button outline retry" type="button">Retry</button></div>
      <div class="composer-footer">
        <span class="button primary" aria-hidden="true">Reply</span>
        <span class="footer-actions" aria-hidden="true">${chrome('trash')}${chrome('clip')}${chrome('smile')}${chrome('more', 'extra-action')}</span>
        ${d.id === 'footer' ? '<span class="status footer-status" role="status" aria-live="polite" aria-atomic="true"></span>' : '<span class="footer-spacer"></span>'}
        ${d.id === 'ambient' ? '<div class="ambient"><span class="ambient-copy" aria-hidden="true"></span><button type="button" class="button icon-only status" aria-label="Draft saved. Show save details" aria-expanded="false" aria-controls="save-details" title="Draft saved · Click for details"></button></div><div class="popover" id="save-details" hidden><strong></strong><p></p></div>' : ''}
      </div>
    </div>
    <div class="study-notes"><p><strong>${d.behavior}</strong> ${d.detail}</p><p class="tradeoff">${d.tradeoff}</p></div>`;
  article.querySelector('textarea').value = draft;
  article.querySelector('textarea').addEventListener('input', event => {
    for (const field of studies.querySelectorAll('textarea')) {
      if (field !== event.target) field.value = event.target.value;
    }
    replaySave();
  });
  article.querySelector('.retry').addEventListener('click', replaySave);
  studies.append(article);
}

const ambient = document.querySelector('.ambient');
const details = document.querySelector('#save-details');
const statusButton = ambient.querySelector('button');
const ambientAnnouncement = document.createElement('span');
ambientAnnouncement.className = 'sr-only';
ambientAnnouncement.setAttribute('role', 'status');
ambientAnnouncement.setAttribute('aria-live', 'polite');
ambientAnnouncement.setAttribute('aria-atomic', 'true');
ambient.append(ambientAnnouncement);

function setState(state, confirm = false) {
  clearTimeout(saveTimer);
  clearTimeout(fadeTimer);
  const info = stateInfo[state];
  document.querySelectorAll('[data-state]').forEach(button => {
    button.setAttribute('aria-pressed', String(button.dataset.state === state));
  });
  for (const article of studies.children) {
    const direction = article.dataset.direction;
    const status = article.querySelector('.status');
    status.dataset.saveState = state;
    status.innerHTML = icon(direction === 'ambient' && state === 'saved' ? 'cloud' : info.icon) + (direction === 'ambient' ? '' : `<span>${direction === 'header' ? info.short : info.long}</span>`);
    if (direction !== 'ambient') status.setAttribute('aria-label', state === 'saved' ? 'Draft saved on the site' : info.detail);
    const warning = article.querySelector('.warning');
    warning.hidden = state !== 'local' && state !== 'error';
    warning.dataset.saveState = state;
    warning.querySelector('p').textContent = info.detail;
  }
  ambient.querySelector('.ambient-copy').textContent = info.long;
  ambient.classList.toggle('confirmation', state === 'saving' || (state === 'saved' && confirm));
  ambient.classList.toggle('attention', state === 'local' || state === 'error');
  ambient.classList.toggle('failed', state === 'error');
  statusButton.setAttribute('aria-label', `${info.long}. Show save details`);
  statusButton.title = `${info.long} · Click for details`;
  ambientAnnouncement.textContent = state === 'saved' ? 'Draft saved on the site' : info.detail;
  details.querySelector('strong').textContent = info.long;
  details.querySelector('p').textContent = info.detail;
  if (state === 'saved' && confirm) {
    fadeTimer = setTimeout(() => ambient.classList.remove('confirmation'), 2400);
  }
}

function replaySave() {
  setState('saving');
  saveTimer = setTimeout(() => setState('saved', true), 1100);
}

document.querySelectorAll('[data-state]').forEach(button => {
  button.addEventListener('click', () => setState(button.dataset.state, button.dataset.state === 'saved'));
});
document.querySelector('#replay').addEventListener('click', replaySave);
document.querySelector('#theme').addEventListener('click', event => {
  const light = document.documentElement.dataset.theme !== 'light';
  document.documentElement.dataset.theme = light ? 'light' : 'dark';
  event.currentTarget.textContent = light ? 'Switch to dark' : 'Switch to light';
});
document.querySelector('#width').addEventListener('click', event => {
  const narrow = document.body.classList.toggle('narrow');
  event.currentTarget.setAttribute('aria-pressed', String(narrow));
  event.currentTarget.textContent = narrow ? 'Full width composer' : 'Narrow composer';
});
statusButton.addEventListener('click', () => {
  details.hidden = !details.hidden;
  statusButton.setAttribute('aria-expanded', String(!details.hidden));
});
document.addEventListener('click', event => {
  if (!event.target.closest('.ambient') && !event.target.closest('.popover')) {
    details.hidden = true;
    statusButton.setAttribute('aria-expanded', 'false');
  }
});
document.addEventListener('keydown', event => {
  if (event.key === 'Escape' && !details.hidden) {
    details.hidden = true;
    statusButton.setAttribute('aria-expanded', 'false');
    statusButton.focus();
  }
});
setState('saved');
