/* Local, dependency-free design prototype. All content and submissions are simulated. */
'use strict';

const ICONS = {
  eyeOff: '<path d="m3 3 18 18M10.6 10.6a2 2 0 0 0 2.8 2.8M9.9 5.2A11 11 0 0 1 12 5c6 0 10 7 10 7a20 20 0 0 1-3.1 3.8M6.2 6.2A20 20 0 0 0 2 12s4 7 10 7a11 11 0 0 0 5.8-1.8"/>',

  compose: '<path d="m14 4 6 6M4 20l4-1L20 7a2.1 2.1 0 0 0-3-3L5 16l-1 4Z"/>',
  reply: '<path d="m9 6-6 5 6 5v-4c6 0 9 1 12 6-1-8-5-10-12-10V6Z"/>',
  chevron: '<path d="m7 10 5 5 5-5"/>',
  left: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M10 4v16M6 8v8"/>',
  right: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M14 4v16M18 8v8"/>',
  bottom: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 13h18M8 17h8"/>',
  more: '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
  minus: '<path d="M5 12h14"/>',
  close: '<path d="m6 6 12 12M6 18 18 6"/>',
  expand: '<path d="M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5M3 3l6 6m12-6-6 6M3 21l6-6m12 6-6-6"/>',
  check: '<path d="m5 12 4 4L19 6"/>',
  cloud: '<path d="M7 17H6a4 4 0 0 1-1-7.8 7 7 0 0 1 13-2 5 5 0 0 1 0 10h-1m-8-2 3 3 4-5"/>',
  search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
  home: '<path d="m3 10 9-7 9 7M5 9v11h5v-6h4v6h5V9"/>',
  inbox: '<path d="M4 4h16l2 12v4H2v-4L4 4Z"/><path d="M2 15h6l2 3h4l2-3h6"/>',
  bell: '<path d="M6 8a6 6 0 0 1 12 0v6l3 3H3l3-3V8m4 12h4"/>',
  chat: '<path d="M20 14a3 3 0 0 1-3 3H8l-5 4V6a3 3 0 0 1 3-3h11a3 3 0 0 1 3 3v8Z"/>',
  settings: '<path d="m9 3-1 3-3 1v4l-2 2 2 3 3 1 1 4h5l1-4 3-1 2-3-2-2V7l-3-1-1-3H9Z"/><circle cx="11.5" cy="12" r="3"/>',
  tag: '<path d="M3 4h8l10 10-8 8L3 12V4Z"/><circle cx="7.5" cy="8.5" r="1"/>',
  arrow: '<path d="M4 12h16m-6-6 6 6-6 6"/>',
  arrowLeft: '<path d="M20 12H4m6-6-6 6 6 6"/>',
  paperclip: '<path d="m8 13 7-7a3 3 0 0 1 4 4L9 20a5 5 0 0 1-7-7L13 2m-2 8-5 5a1 1 0 0 0 2 2l10-10"/>',
  smile: '<circle cx="12" cy="12" r="9"/><path d="M8 14a4 4 0 0 0 8 0M8 8h.01M16 8h.01"/>',
  plus: '<path d="M12 4v16M4 12h16"/>',
  link: '<path d="m10 14 4-4m-6 6-2 2a4 4 0 0 1-6-6l5-5a4 4 0 0 1 6 0m2 2a4 4 0 0 1 0-6l5-5a4 4 0 0 1 6 6l-2 2" transform="translate(3 4) scale(.78)"/>',
  quote: '<path d="M4 7h6v7H5c0 2 1 3 3 4M14 7h6v7h-5c0 2 1 3 3 4"/>',
  list: '<path d="M9 6h12M9 12h12M9 18h12M3 6h.01M3 12h.01M3 18h.01"/>',
  code: '<path d="m7 7-5 5 5 5m10-10 5 5-5 5m-4-14-2 18"/>',
  file: '<path d="M14 2H5v20h14V7l-5-5Zm0 0v6h5M8 12h8M8 16h6"/>',
  moon: '<path d="M20 14a9 9 0 0 1-10-11 9 9 0 1 0 10 11Z"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 1v2m0 18v2M1 12h2m18 0h2M4 4l2 2m12 12 2 2M4 20l2-2M18 6l2-2"/>',
  desktop: '<rect x="2" y="3" width="20" height="14" rx="2"/><path d="M8 22h8m-4-5v5"/>',
  mobile: '<rect x="6" y="2" width="12" height="20" rx="3"/><path d="M10 5h4m-3 14h2"/>',
  keyboard: '<rect x="2" y="5" width="20" height="14" rx="2"/><path d="M6 9h.1M10 9h.1M14 9h.1M18 9h.1M6 12h.1M10 12h.1M14 12h.1M18 12h.1M7 16h10"/>',
  layers: '<path d="m12 2 10 6-10 6L2 8l10-6Zm-10 11 10 6 10-6M2 18l10 6 10-6" transform="scale(.86) translate(2 0)"/>',
  lock: '<rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V6a4 4 0 0 1 8 0v4m-4 5v2"/>',
  history: '<path d="M3 11a9 9 0 1 1 1 6M3 4v7h7m2-4v6l4 2"/>',
  eye: '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/>',
  heart: '<path d="M12 21 3 12a6 6 0 0 1 9-8 6 6 0 0 1 9 8l-9 9Z"/>',
  bookmark: '<path d="M5 3h14v18l-7-5-7 5V3Z"/>',
  alert: '<path d="m12 3 10 18H2L12 3Zm0 6v5m0 3h.01"/>',
  undo: '<path d="M4 10h10a6 6 0 0 1 0 12M4 10l6-6m-6 6 6 6"/>',
};
const icon = name => `<svg viewBox="0 0 24 24" aria-hidden="true">${ICONS[name] || ICONS.compose}</svg>`;
const esc = text => String(text).replace(/[&<>"']/g, char => ({'&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;'}[char]));
const ib = (name, label, action, extra = '') => `<button type="button" class="icon-button" aria-label="${esc(label)}" title="${esc(label)}" data-action="${action}" ${extra}>${icon(name)}</button>`;

const topicTitle = 'Making the first contribution feel easier';
const sourceExcerpt = 'A little more context at the moment of writing would help. I often scroll back to remember exactly what I’m responding to.';
const whisperExcerpt = 'Let’s give the contributor a little more context before continuing this discussion in the public topic.';
const originalEdit = 'We should start with a small experiment. Let’s try this in all categories and see how it feels.\n\nWe can check back after a week and share what we learned.';
const SEEDS = {
  new: {title: 'A friendlier starting point for new contributors', body: 'What if the first post felt more like joining a conversation?\n\nI’d like to try a small welcome thread in the Support category. A place to ask a first question, share an introduction, or find someone working on the same thing.\n\nHas anyone tried something similar in their community?', category: 'Community', tags: ['onboarding', 'feedback']},
  reply: {title: topicTitle, body: 'I like this direction, especially keeping the original post close by.\n\nWe could start with a small welcome thread and see which questions come up naturally. That should give us a better sense of what new contributors actually need.', category: 'Community', tags: ['onboarding']},
  edit: {title: topicTitle, body: 'We should start with a small experiment. Let’s try this in the Support category first and see how it feels.\n\nWe can check back after two weeks and share what we learned.', category: 'Community', tags: ['onboarding']},
};
const COMPONENT_ROWS = [
  ['Docking and header', 'DResizablePanelGroup, DScrollArea, DPopover, DToggleGroup, DButton, DTooltip', 'Existing placement, size, minimize, restore and close owners.'],
  ['Reply / Whisper', 'DDropdownMenu, DButton, DTokens', 'Use currentUser.whisperer, target.replyingToWhisper and ComposerController.setWhisper.'],
  ['Title and taxonomy', 'DInput, DField, DSelect, DCombobox, DBadge', 'Existing title, category and tag values, validation and permissions.'],
  ['Reply context', 'DAvatar, DItem, DItemContent, DItemTitle, DItemDescription', 'Existing ComposerReplyContext and its cached source excerpt.'],
  ['Edit topic context', 'DItem, DItemContent, DItemTitle, DItemDescription', 'A passive muted item with a small Topic label and the existing topic title.'],
  ['Writing tools', 'DButtonGroup, DButton, DDropdownMenu, DDialog', 'Existing bold, italic, inline code and link commands; existing plugin contributions only.'],
  ['Image uploads and emoji', 'DAttachment, DAttachmentAction, DButton', 'Existing image picker/upload queue and emoji picker; retain their availability gates.'],
  ['Status and close confirmation', 'DSpinner, DToast, DAlertDialog', 'Existing draft state for topics/replies; edits offer Cancel or Discard changes.'],
];
const query = new URLSearchParams(location.search);
const requestedMode = query.get('mode') || document.body.dataset.mode || 'new';
const state = {
  mode: requestedMode === 'whisper' ? 'reply' : ['new', 'reply', 'edit'].includes(requestedMode) ? requestedMode : 'new',
  fixture: ['allowed', 'restricted', 'whisper-reply'].includes(query.get('fixture')) ? query.get('fixture') : 'allowed',
  viewport: query.get('viewport') === 'mobile' ? 'mobile' : 'desktop',
  dock: ['left', 'bottom', 'right'].includes(query.get('dock')) ? query.get('dock') : 'right',
  theme: 'light', keyboard: false, minimized: false, closed: false, expanded: false,
  error: false, popover: null,
  // The sample site has image uploads, emoji, polls and local dates enabled.
  capabilities: {uploads: true, emoji: true, poll: true, localDates: true},
  drafts: Object.fromEntries(Object.entries(SEEDS).map(([key, value]) => [key, {...value, tags: [...value.tags], files: [], selection: [0, 0], whisper: false, status: key === 'edit' ? '' : 'Draft saved'}])),
};
state.drafts.reply.whisper = state.fixture !== 'restricted' && (requestedMode === 'whisper' || query.get('whisper') === 'true' || state.fixture === 'whisper-reply');
const draft = () => state.drafts[state.mode];
const isWhisper = () => state.mode === 'reply' && state.fixture !== 'restricted' && (draft().whisper || state.fixture === 'whisper-reply');
const canToggleWhisper = () => state.mode === 'reply' && state.fixture === 'allowed' && !state.minimized && !state.closed;
const canSaveDraft = () => state.mode !== 'edit';
const modeLabel = () => ({new: 'New topic', reply: isWhisper() ? 'Whisper' : 'Reply', edit: 'Edit post #12'}[state.mode]);
const submitLabel = () => ({new: 'Create topic', reply: isWhisper() ? 'Whisper' : 'Reply', edit: 'Save'}[state.mode]);
const replyExcerpt = () => state.fixture === 'whisper-reply' ? whisperExcerpt : sourceExcerpt;
const sourceBadge = () => state.fixture === 'whisper-reply' ? `<span class="post-whisper">${icon('eyeOff')}Whisper</span>` : '';
const selectedFlow = () => isWhisper() ? 'whisper' : state.mode;
let saveTimer, toastTimer, resizeObserver;

function renderStudy() {
  state.popover = null;
  document.documentElement.dataset.theme = state.theme;
  document.getElementById('study').innerHTML = `
    <header class="study-header">
      <div class="study-brand"><span class="brand-mark">${icon('compose')}</span><div><strong>Topic composer</strong><small>Discourse Native · Quiet dock</small></div></div>
      <p class="study-title">Quiet dock</p>
      <div class="review-actions">${ib(state.theme === 'light' ? 'moon' : 'sun', 'Toggle light and dark theme', 'theme')}<button class="button outline" data-action="specs">${icon('layers')}<span class="label-short">Components<span class="label-long"> used</span></span></button></div>
    </header>
    <div class="study-controls">
      <p class="design-description">One live editor. <strong>Existing composer features, composed with Native.</strong></p>
      <span class="control-label">Try a flow</span>
      <div class="segmented" role="group" aria-label="Composer scenarios">${['new','reply','whisper','edit'].map(mode => `<button data-mode="${mode}" aria-pressed="${selectedFlow() === mode}" ${mode === 'whisper' && state.fixture === 'restricted' ? 'disabled title="This sample user cannot whisper"' : ''} ${mode === 'reply' && state.fixture === 'whisper-reply' ? 'disabled title="Replies to a whisper stay whispers"' : ''}>${{new:'New topic', reply:'Reply', whisper:'Whisper', edit:'Edit'}[mode]}</button>`).join('')}</div>
      <div class="viewport-switch" role="group" aria-label="Mockup viewport">${ib('desktop', 'Desktop layout', 'desktop', `aria-pressed="${state.viewport === 'desktop'}"`)}${ib('mobile', 'Mobile layout', 'mobile', `aria-pressed="${state.viewport === 'mobile'}"`)}${state.viewport === 'mobile' ? ib('keyboard', 'Toggle simulated keyboard', 'keyboard', `aria-pressed="${state.keyboard}"`) : ''}</div>
    </div>
    <main class="stage" aria-label="Quiet dock interactive mockup">
      <div class="app-window ${state.viewport === 'mobile' ? 'mobile' : ''} ${state.keyboard ? 'show-keyboard' : ''}" id="app-window">
        <div class="window-bar" aria-hidden="true"><div class="traffic-lights"><i></i><i></i><i></i></div><div class="window-tab">${icon('chat')} Discourse Meta</div><span class="window-context">${topicTitle}</span></div>
        <div class="window-layout">${renderSidebar()}<div class="work-area" id="work-area" data-dock="${state.dock}">
          ${renderReader()}<div class="resize-handle" role="separator" tabindex="0" aria-label="Resize composer" aria-valuemin="360" aria-valuemax="900" aria-valuenow="420"></div>
          <section class="composer" id="composer" aria-label="${modeLabel()} composer"></section>
          <button class="button primary resume-draft" data-action="restore" hidden>${icon('compose')} Resume draft</button>
        </div></div>${renderKeyboard()}
      </div>
    </main>
    <div class="study-note"><span>Local mockup · <span id="layout-note"></span> · ${state.mode === 'edit' ? 'Edits are not saved as drafts' : 'Saves and submissions are simulated'}</span><div class="fixture-control"><label for="whisper-fixture">Whisper scenario</label><select id="whisper-fixture" aria-label="Whisper scenario (mockup only)">${[['allowed','User can whisper'],['restricted','User cannot whisper'],['whisper-reply','Reply to a whisper']].map(([value,label]) => `<option value="${value}" ${state.fixture === value ? 'selected' : ''}>${label}</option>`).join('')}</select>${canSaveDraft() ? `<button class="button compact" data-action="error">${state.error ? 'Clear simulated failure' : 'Simulate save failure'}</button>` : ''}</div></div>
    <dialog class="spec-panel" id="spec-dialog" aria-labelledby="spec-title"></dialog>
    <dialog class="confirm-dialog" id="close-dialog" aria-labelledby="close-title"><h2 id="close-title">Do you want to discard your changes?</h2><div class="dialog-actions"><button class="button destructive" data-action="discard">Discard changes</button><button class="button outline" data-action="keep-editing" autofocus>Cancel</button></div></dialog>
    <dialog class="confirm-dialog" id="link-dialog" aria-labelledby="link-title"><h2 id="link-title">Insert link</h2><form id="link-form"><label class="field-label" for="link-text">Text</label><input class="text-input" id="link-text" required><label class="field-label" for="link-url">URL</label><input class="text-input" id="link-url" type="url" placeholder="https://" required><div class="dialog-actions"><button type="button" class="button" data-action="cancel-link">Cancel</button><button class="button primary" type="submit">Insert link</button></div></form></dialog>
    <div class="toast" id="toast" role="status" aria-live="polite" hidden></div>`;
  renderComposer();
  installResize();
}

function renderMeta() {
  if (state.mode === 'new') return `<div class="composer-meta"><label class="field-label" for="topic-title">Title</label><input id="topic-title" class="text-input" data-field="title" aria-label="Topic title" value="${esc(draft().title)}" placeholder="Give your topic a clear title"><div class="taxonomy-row"><button class="button outline" data-action="category" aria-haspopup="dialog"><span class="category-square"></span>${esc(draft().category)}${icon('chevron')}</button>${draft().tags.map(tag => `<span class="tag-pill">${esc(tag)}</span>`).join('')}<button class="button" data-action="tags" aria-haspopup="dialog">${icon('plus')}${draft().tags.length ? 'Tags' : 'Add tags'}</button></div></div>`;
  if (state.mode === 'edit') return `<div class="composer-meta"><dl class="edit-target"><dt>Topic</dt><dd>${esc(topicTitle)}</dd></dl></div>`;
  return `<div class="composer-meta"><button class="reply-target" data-action="context" aria-expanded="${state.expanded}"><span class="avatar small">M</span><span><strong>Replying to @maya · #8</strong><small>${topicTitle}</small></span>${icon('chevron')}</button>${state.expanded ? `<blockquote class="reply-excerpt">${esc(replyExcerpt())}</blockquote>` : ''}</div>`;
}
function renderTools() {
  return `<div class="editor-tools" role="group" aria-label="Formatting tools"><button class="icon-button" title="Bold (⌘B)" aria-label="Bold" data-format="bold"><strong>B</strong></button><button class="icon-button" title="Italic (⌘I)" aria-label="Italic" data-format="italic"><em>I</em></button><button class="icon-button" title="Inline code (⌘E)" aria-label="Inline code" data-format="code">${icon('code')}</button><span class="tool-separator"></span>${ib('link','Insert link (⌘L)','link')}</div>`;
}
function renderEditor() {
  return `<div class="editor-shell">${renderTools()}<textarea id="draft-body" aria-label="${state.mode === 'new' ? 'Topic body' : state.mode === 'edit' ? 'Edit body' : isWhisper() ? 'Whisper body' : 'Reply body'}" spellcheck="true" placeholder="${state.mode === 'new' ? 'Write your topic…' : state.mode === 'edit' ? 'Edit this post…' : 'Reply to @maya…'}">${esc(draft().body)}</textarea></div>`;
}
function renderAttachments() {
  return `<div class="attachment-list" ${draft().files.length ? '' : 'hidden'}>${draft().files.map((file, index) => `<div class="attachment">${icon('file')}<span><strong>${esc(file.name)}</strong><small>Uploaded</small></span>${ib('close',`Remove upload ${file.name}`, 'remove-file', `data-file-index="${index}"`)}</div>`).join('')}</div>`;
}
function renderHeading() {
  const content = `${icon(isWhisper() ? 'eyeOff' : state.mode === 'reply' ? 'reply' : 'compose')}<span>${modeLabel()}</span>`;
  return canToggleWhisper()
    ? `<button class="composer-heading reply-options" data-action="reply-menu" aria-label="${isWhisper() ? 'Whisper' : 'Reply'} options" aria-haspopup="menu" aria-expanded="false">${content}${icon('chevron')}</button>`
    : `<div class="composer-heading">${content}</div>`;
}
function renderComposer() {
  const root = document.getElementById('composer');
  root.classList.toggle('is-whisper', isWhisper());
  root.setAttribute('aria-label', `${modeLabel()} composer`);
  root.innerHTML = `<div class="minimized-strip">${icon(isWhisper() ? 'eyeOff' : 'compose')}<span class="draft-summary">${modeLabel()} · ${esc(draft().title)}</span>${ib('expand','Restore composer','restore')}${ib('close',canSaveDraft() ? 'Save and close' : 'Close composer','close')}</div>
    <header class="composer-header">${renderHeading()}<div class="composer-header-actions">${ib('more','Dock side','dock-menu','aria-haspopup="dialog" aria-expanded="false"')}${ib('minus','Minimize composer','minimize')}${ib('close',canSaveDraft() ? 'Save and close' : 'Close composer','close')}</div></header>
    <div class="composer-core">${renderMeta()}${renderEditor()}</div>
    <div class="upload-queue">${renderAttachments()}</div>
    <footer class="composer-footer"><div class="footer-status ${state.error ? 'status-error' : ''}" aria-live="polite" ${canSaveDraft() ? '' : 'hidden'}>${icon(state.error ? 'alert' : 'check')}<span class="save-label">${state.error ? "Couldn't save this draft on this device." : esc(draft().status)}</span></div><div class="footer-actions">${state.capabilities.uploads ? ib('paperclip','Upload images','attach') : ''}${state.capabilities.emoji ? ib('smile','Add emoji','emoji') : ''}${state.capabilities.poll || state.capabilities.localDates ? ib('plus','Insert','insert','aria-haspopup="menu"') : ''}<button class="button primary" data-action="submit">${state.mode === 'reply' ? icon(isWhisper() ? 'eyeOff' : 'reply') : ''}${submitLabel()}<span class="shortcut">⌘↵</span></button></div></footer><div id="composer-popover"></div>`;
  const editor = document.getElementById('draft-body');
  editor.setSelectionRange(...draft().selection.map(value => Math.min(value, draft().body.length)));
  document.querySelector('[data-action="dock-menu"]').classList.add('dock-trigger');
  applyLayout(); updateSubmit();
}
function applyLayout() {
  const area = document.getElementById('work-area');
  if (!area) return;
  const mobile = state.viewport === 'mobile' || document.getElementById('app-window').clientWidth < 580;
  if (state.viewport !== 'mobile') document.getElementById('app-window').classList.toggle('mobile', mobile);
  const actual = mobile || area.clientWidth < 681 ? 'bottom' : state.dock;
  area.dataset.dock = actual;
  area.classList.toggle('is-minimized', state.minimized);
  area.classList.toggle('is-closed', state.closed);
  const sideSize = Math.min(draft().sideSize || 420, Math.max(360, area.clientWidth - 321));
  let bottomSize = draft().bottomSize || (state.mode === 'new' ? 380 : 280);
  if (mobile) bottomSize = state.keyboard ? 350 : 460;
  bottomSize = Math.max(mobile ? 260 : 240, Math.min(bottomSize, area.clientHeight - (mobile ? 90 : 130)));
  area.style.setProperty('--side-size', `${sideSize}px`);
  area.style.setProperty('--bottom-size', `${bottomSize}px`);
  const handle = area.querySelector('.resize-handle');
  handle.setAttribute('aria-orientation', actual === 'bottom' ? 'horizontal' : 'vertical');
  handle.setAttribute('aria-valuemin', actual === 'bottom' ? '240' : '360');
  handle.setAttribute('aria-valuemax', String(actual === 'bottom' ? Math.max(240, area.clientHeight - 130) : Math.max(360, area.clientWidth - 321)));
  handle.setAttribute('aria-valuenow', String(Math.round(actual === 'bottom' ? bottomSize : sideSize)));
  document.getElementById('layout-note').textContent = mobile ? 'Bottom dock on mobile' : actual !== state.dock ? 'Side dock resumes when it fits' : `${{left:'Left',right:'Right',bottom:'Bottom'}[actual]} dock · drag the divider`;
  area.querySelector('.resume-draft').hidden = !state.closed || !canSaveDraft();
}
function rememberEditor() {
  const editor = document.getElementById('draft-body');
  if (editor) { draft().body = editor.value; draft().selection = [editor.selectionStart, editor.selectionEnd]; }
}
function scheduleSave() {
  updateSubmit();
  if (!canSaveDraft()) return;
  clearTimeout(saveTimer);
  const currentDraft = draft();
  state.error = false;
  currentDraft.status = 'Saving draft…'; updateStatus();
  saveTimer = setTimeout(() => { currentDraft.status = 'Draft saved'; updateStatus(); }, 650);
}
function updateStatus() {
  const label = document.querySelector('.save-label');
  if (label) label.textContent = state.error ? "Couldn't save this draft on this device." : draft().status;
  document.querySelector('.footer-status')?.classList.toggle('status-error', state.error);
}
function updateSubmit() {
  const button = document.querySelector('[data-action="submit"]');
  if (button) button.disabled = !draft().body.trim() || (state.mode === 'new' && !draft().title.trim()) || (state.mode === 'edit' && draft().body === originalEdit && !draft().files.length);
}
function insertText(before, after = '', placeholder = '') {
  rememberEditor();
  const [start, end] = draft().selection;
  const selected = draft().body.slice(start, end) || placeholder;
  draft().body = draft().body.slice(0, start) + before + selected + after + draft().body.slice(end);
  draft().selection = [start + before.length, start + before.length + selected.length];
  renderComposer(); document.getElementById('draft-body').focus(); scheduleSave();
}
function toast(message) {
  const el = document.getElementById('toast');
  el.innerHTML = `${icon('check')}<span>${esc(message)}</span>`; el.hidden = false;
  clearTimeout(toastTimer); toastTimer = setTimeout(() => { el.hidden = true; }, 3400);
}
function closePopover(restoreFocus = false) {
  const previous = state.popover;
  document.getElementById('composer-popover').innerHTML = ''; state.popover = null;
  document.querySelectorAll('[aria-expanded="true"][data-action$="-menu"]').forEach(el => el.setAttribute('aria-expanded', 'false'));
  if (restoreFocus) document.querySelector(`[data-action="${previous === 'reply' ? 'reply-menu' : previous === 'dock' ? 'dock-menu' : previous === 'emoji' ? 'emoji' : previous === 'insert' ? 'insert' : previous}"]`)?.focus();
}
function openPopover(kind) {
  if (kind === 'reply' && !canToggleWhisper()) return;
  if (state.popover === kind) { closePopover(true); return; }
  closePopover(); state.popover = kind;
  const el = document.getElementById('composer-popover');
  if (kind === 'dock') {
    document.querySelector('[data-action="dock-menu"]').setAttribute('aria-expanded', 'true');
    el.innerHTML = `<div class="popover dock-popover" role="dialog" aria-label="Dock side"><span>Dock side</span>${['left','bottom','right'].map(pos => ib(pos,`Dock ${pos}`,'set-dock',`data-dock="${pos}" aria-pressed="${state.dock === pos}"`)).join('')}</div>`;
  }
  if (kind === 'reply') {
    document.querySelector('[data-action="reply-menu"]').setAttribute('aria-expanded', 'true');
    el.innerHTML = `<div class="popover reply-popover" role="menu" aria-label="Reply options">${[false,true].map(whisper => `<button class="picker-item" role="menuitemradio" aria-checked="${isWhisper() === whisper}" data-set-whisper="${whisper}">${icon(whisper ? 'eyeOff' : 'reply')}<span>${whisper ? 'Whisper<small>Allowed groups only</small>' : 'Reply'}</span>${isWhisper() === whisper ? icon('check') : ''}</button>`).join('')}</div>`;
  }
  if (kind === 'category' || kind === 'tags') {
    const category = kind === 'category';
    const choices = category ? ['Community','Support','Feature','Dev'] : ['onboarding','feedback','ux','design','welcome'];
    el.innerHTML = `<div class="popover picker-popover" role="dialog" aria-label="${category ? 'Choose category' : 'Choose tags'}"><input class="text-input" data-picker-search aria-label="Search ${kind}" placeholder="Search ${kind}…">${choices.map(value => `<button class="picker-item" data-pick="${kind}" data-value="${value}" ${category ? '' : `aria-pressed="${draft().tags.includes(value)}"`}>${category ? '<span class="category-square"></span>' : icon('tag')}${value}${(category ? draft().category === value : draft().tags.includes(value)) ? icon('check') : ''}</button>`).join('')}${category ? '' : '<button class="button compact" data-action="done-picker">Done</button>'}</div>`;
  }
  if (kind === 'insert') el.innerHTML = `<div class="popover insert-popover" role="menu" aria-label="Insert">${state.capabilities.poll ? `<button class="picker-item" role="menuitem" data-action="sample-poll">${icon('list')}Add poll</button>` : ''}${state.capabilities.localDates ? `<button class="picker-item" role="menuitem" data-action="sample-date">${icon('history')}Insert date/time</button>` : ''}</div>`;
  if (kind === 'emoji') el.innerHTML = `<div class="popover insert-popover emoji-popover" role="dialog" aria-label="Add emoji">${[['smile','🙂'],['heart','❤️'],['thumbs up','👍'],['tada','🎉'],['wave','👋'],['thinking','🤔']].map(([label, value]) => `<button class="icon-button" data-emoji="${value}" aria-label="${label}" title="${label}">${value}</button>`).join('')}</div>`;
  el.querySelector('input, button')?.focus();
}
function setWhisper(value) {
  if (!canToggleWhisper()) return;
  rememberEditor(); draft().whisper = value;
  renderStudy(); syncUrl(); scheduleSave();
  document.querySelector('[data-action="reply-menu"]')?.focus();
}
function openSpecs() {
  const dialog = document.getElementById('spec-dialog');
  dialog.innerHTML = `<header class="spec-header"><div><span class="eyebrow">Quiet dock · Existing capabilities</span><h2 id="spec-title">Components used</h2></div><div class="spacer"></div>${ib('close','Close component requirements','close-specs')}</header><div class="spec-body"><p class="spec-highlight">No new generic Native components or composer capabilities are required.</p><table><thead><tr><th>Area</th><th>Native components</th><th>Existing owner</th></tr></thead><tbody>${COMPONENT_ROWS.map(row => `<tr>${row.map(cell => `<td>${esc(cell)}</td>`).join('')}</tr>`).join('')}</tbody></table><h3>Whisper rules</h3><ul><li>The Reply/Whisper header menu is available only when the user can whisper and the target is an ordinary reply.</li><li>A reply to a whisper stays a whisper; no public-reply toggle is shown.</li><li>New topics and edits do not offer a visibility conversion.</li><li>Keep the existing whisper flag when saving, restoring, docking or minimizing a reply. The audience is “Allowed groups only”.</li></ul><h3>Work to achieve this layout</h3><p>Recompose the existing header, fields, reply context, formatting and footer with Native. Retain ComposerController, ComposerEditor, draft persistence, plugin policies and ComposerPresentationHost. Show existing bold/italic/code/link commands in the toolbar; keep image upload, emoji and eligible plugin actions in the footer.</p><p>The only writing surface is the existing live hybrid editor. Edits have the current Cancel / Discard changes close confirmation and no draft-saving action.</p><p><a href="components.md">Read the full component and supported-feature inventory</a></p><p>The HTML editor and its dialogs are local stand-ins. Nothing is posted, saved to an account or uploaded.</p></div>`;
  dialog.showModal();
}
function setMode(mode) {
  if (mode === 'whisper' && state.fixture === 'restricted') return;
  rememberEditor();
  state.mode = mode === 'whisper' ? 'reply' : mode;
  if (state.mode === 'reply') draft().whisper = mode === 'whisper' || state.fixture === 'whisper-reply';
  state.error = false; state.expanded = false; state.minimized = false; state.closed = false; state.popover = null;
  renderStudy(); syncUrl();
}
function syncUrl() {
  const url = new URL(location.href);
  url.searchParams.delete('design'); url.searchParams.delete('whisper');
  url.searchParams.set('mode', selectedFlow()); url.searchParams.set('fixture', state.fixture);
  url.searchParams.set('viewport', state.viewport); url.searchParams.set('dock', state.dock);
  history.replaceState({}, '', url);
}
function closeComposer() {
  rememberEditor();
  if (!canSaveDraft()) {
    if (draft().body !== originalEdit || draft().files.length) document.getElementById('close-dialog').showModal();
    else { state.closed = true; state.minimized = false; applyLayout(); }
    return;
  }
  if (state.error) { toast('This draft could not be saved yet. Please try again.'); return; }
  state.closed = true; state.minimized = false; applyLayout();
  toast('Draft kept for this page session.');
}
function submit() {
  if (state.closed || document.querySelector('dialog[open]')) return;
  rememberEditor(); updateSubmit();
  if (document.querySelector('[data-action="submit"]').disabled) return;
  toast(`${state.mode === 'new' ? 'Topic created' : state.mode === 'edit' ? 'Post saved' : isWhisper() ? 'Whisper sent to allowed groups' : 'Reply posted'} — demonstration only. Nothing was sent.`);
}
function openLink() {
  rememberEditor();
  const [start, end] = draft().selection;
  document.getElementById('link-text').value = draft().body.slice(start,end);
  document.getElementById('link-url').value = '';
  document.getElementById('link-dialog').showModal();
  document.getElementById(start === end ? 'link-text' : 'link-url').focus();
}

function renderSidebar() {
  return `<aside class="rail" aria-label="Sample site navigation"><div class="site-icon">D</div><span class="rail-icon">${icon('home')}</span><span class="rail-icon">${icon('chat')}</span><span class="rail-icon">${icon('bell')}</span><div class="spacer"></div><span class="rail-icon">${icon('settings')}</span><span class="avatar small blue">J</span></aside>
    <aside class="sidebar" aria-label="Sample community sidebar"><div class="sidebar-title">Discourse Meta ${icon('chevron')}</div><div class="nav-item">${icon('inbox')} Latest <span class="count">24</span></div><div class="nav-item">${icon('bell')} Unread <span class="count">8</span></div><div class="nav-item">${icon('bookmark')} Bookmarks</div><div class="eyebrow">Categories</div><div class="nav-item active"><span class="category-square"></span> Community</div><div class="nav-item"><span class="category-square purple"></span> Support</div><div class="nav-item"><span class="category-square orange"></span> Feature</div><div class="eyebrow">Your activity</div><div class="nav-item">${icon('compose')} My drafts <span class="count">1</span></div><div class="nav-item">${icon('chat')} My posts</div></aside>`;
}
function renderReader() {
  return `<section class="reader" aria-label="Sample topic for context"><div class="reader-top">${icon('arrowLeft')}<span>Community</span><span class="spacer"></span>${icon('search')}${icon('more')}</div><div class="reader-scroll"><div class="reader-copy"><h1>${topicTitle}</h1><div class="topic-taxonomy"><span class="category-square"></span><span>Community</span><span class="tag">onboarding</span><span class="tag">feedback</span></div><article class="post"><div class="post-top"><span class="avatar purple">S</span><strong>Sarah Chen</strong><span class="subtle">sarah</span><span class="post-time">2h</span></div><div class="post-text"><p>We’ve been talking about how to make it easier for people to join in, especially when they’re writing their very first post.</p><p>My hunch is that the blank composer is part of the problem. There’s a lot to think about before you’ve even written a sentence.</p><p>What’s helped in your communities?</p></div><div class="post-actions">${icon('heart')} 12 <span class="spacer"></span><button class="button compact" data-action="reader-reply">${icon('reply')} Reply</button></div></article><article class="post highlighted"><div class="post-top"><span class="avatar">M</span><strong>Maya</strong><span class="subtle">maya</span>${sourceBadge()}<span class="post-time">#8 · 34m</span></div><div class="post-text"><p>${esc(replyExcerpt())}</p><p>Even just keeping the person and a short excerpt nearby would make it feel less like filling out a form.</p></div><div class="post-actions">${icon('heart')} 6 <span class="spacer"></span><button class="button compact" data-action="reader-reply">${icon('reply')} Reply</button></div></article><article class="post"><div class="post-top"><span class="avatar blue">J</span><strong>Joffrey</strong><span class="subtle">you</span><span class="post-time">#12 · 12m</span></div><div class="post-text"><p>${esc(originalEdit).replace(/\n\n/g, '</p><p>')}</p></div><div class="post-actions"><span class="spacer"></span><button class="button compact" data-mode="edit">${icon('compose')} Edit</button></div></article></div></div><div class="reader-footer">12 of 18 posts <span class="subtle">·</span> 8 people in this conversation</div></section>`;
}
function renderKeyboard() {
  return `<div class="keyboard" aria-hidden="true">${['qwertyuiop','asdfghjkl','zxcvbnm'].map(row => `<div class="keyboard-row">${[...row].map(letter => `<span class="keyboard-key">${letter}</span>`).join('')}</div>`).join('')}<div class="keyboard-row"><span class="keyboard-key wide">123</span><span class="keyboard-key space">space</span><span class="keyboard-key wide">return</span></div><div class="keyboard-note">Keyboard footprint simulation</div></div>`;
}

function installResize() {
  resizeObserver?.disconnect();
  resizeObserver = new ResizeObserver(applyLayout);
  resizeObserver.observe(document.getElementById('work-area'));
  const handle = document.querySelector('.resize-handle');
  handle.addEventListener('pointerdown', event => {
    event.preventDefault();
    handle.setPointerCapture(event.pointerId);
    const area = document.getElementById('work-area');
    const rect = area.getBoundingClientRect();
    const dock = area.dataset.dock;
    const onMove = ev => {
      if (dock === 'bottom') draft().bottomSize = Math.max(240, Math.min(rect.bottom - ev.clientY, rect.height - 130));
      else draft().sideSize = Math.max(360, Math.min(dock === 'left' ? ev.clientX - rect.left : rect.right - ev.clientX, rect.width - 321));
      applyLayout();
    };
    const done = () => { handle.removeEventListener('pointermove', onMove); handle.removeEventListener('pointerup', done); handle.removeEventListener('pointercancel', done); };
    handle.addEventListener('pointermove', onMove); handle.addEventListener('pointerup', done); handle.addEventListener('pointercancel', done);
  });
  handle.addEventListener('keydown', event => {
    if (!['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(event.key)) return;
    event.preventDefault();
    const dock = document.getElementById('work-area').dataset.dock;
    const current = Number(handle.getAttribute('aria-valuenow'));
    const delta = (event.key === 'ArrowUp' || (event.key === 'ArrowLeft' && dock === 'right') || (event.key === 'ArrowRight' && dock === 'left')) ? 20 : -20;
    if (dock === 'bottom') draft().bottomSize = Math.max(240, current + delta); else draft().sideSize = Math.max(360, current + delta);
    applyLayout();
  });
}


document.addEventListener('input', event => {
  if (event.target.id === 'link-url') event.target.setCustomValidity('');
  if (event.target.id === 'draft-body') { rememberEditor(); scheduleSave(); }
  if (event.target.dataset.field) { draft()[event.target.dataset.field] = event.target.value; scheduleSave(); }
  if (event.target.hasAttribute('data-picker-search')) {
    const needle = event.target.value.toLowerCase();
    document.querySelectorAll('[data-pick]').forEach(item => { item.hidden = !item.dataset.value.toLowerCase().includes(needle); });
  }
});
document.addEventListener('change', event => {
  if (event.target.id !== 'whisper-fixture') return;
  rememberEditor(); state.fixture = event.target.value;
  // A different sample user/target loads a fresh fixture, never a downgraded whisper draft.
  state.drafts.reply = {...SEEDS.reply, tags: [...SEEDS.reply.tags], files: [], selection: [0,0], whisper: state.fixture === 'whisper-reply', status: 'Draft saved'};
  state.mode = 'reply'; state.error = false; state.closed = false; state.minimized = false; state.popover = null;
  renderStudy(); syncUrl();
});
document.addEventListener('selectionchange', () => { if (document.activeElement?.id === 'draft-body') rememberEditor(); });
document.addEventListener('submit', event => {
  if (event.target.id !== 'link-form') return;
  event.preventDefault();
  const url = document.getElementById('link-url').value.trim();
  if (!/^https?:\/\//i.test(url)) { document.getElementById('link-url').setCustomValidity('Use an http or https URL.'); document.getElementById('link-url').reportValidity(); return; }
  const text = document.getElementById('link-text').value.replaceAll('[','\\[').replaceAll(']','\\]');
  document.getElementById('link-dialog').close();
  const [start,end] = draft().selection;
  draft().body = draft().body.slice(0,start) + `[${text}](${url.replaceAll(')','%29')})` + draft().body.slice(end);
  draft().selection = [start,start]; renderComposer(); scheduleSave();
});
document.addEventListener('click', event => {
  const target = event.target.closest('button, a');
  if (!target) { if (state.popover && !event.target.closest('.popover')) closePopover(); return; }
  if (target.disabled) return;
  if (target.dataset.mode) { setMode(target.dataset.mode); return; }
  if (target.hasAttribute('data-set-whisper')) { setWhisper(target.dataset.setWhisper === 'true'); return; }
  if (target.hasAttribute('data-emoji')) { if (state.capabilities.emoji) { closePopover(); insertText(target.dataset.emoji); } return; }
  if (target.dataset.format) {
    const formats = {bold:['**','**','bold text'],italic:['*','*','italic text'],code:['`','`','code']};
    insertText(...formats[target.dataset.format]); return;
  }
  if (target.dataset.pick) {
    if (state.mode !== 'new') return;
    const value = target.dataset.value;
    if (target.dataset.pick === 'category') draft().category = value;
    else draft().tags = draft().tags.includes(value) ? draft().tags.filter(tag => tag !== value) : [...draft().tags,value];
    const keepPicker = target.dataset.pick === 'tags';
    state.popover = null; renderComposer(); scheduleSave(); if (keepPicker) openPopover('tags'); return;
  }
  const action = target.dataset.action;
  if (!action) return;
  if (state.popover && !target.closest('.popover') && !['dock-menu','reply-menu','category','tags','insert','emoji'].includes(action)) closePopover();
  switch (action) {
    case 'theme': rememberEditor(); state.theme = state.theme === 'light' ? 'dark' : 'light'; renderStudy(); break;
    case 'desktop': case 'mobile': rememberEditor(); state.viewport = action; state.keyboard = false; renderStudy(); syncUrl(); break;
    case 'keyboard': rememberEditor(); state.keyboard = !state.keyboard; renderStudy(); break;
    case 'specs': openSpecs(); break;
    case 'close-specs': document.getElementById('spec-dialog').close(); break;
    case 'reply-menu': openPopover('reply'); break;
    case 'dock-menu': openPopover('dock'); break;
    case 'set-dock': state.dock = target.dataset.dock; closePopover(true); applyLayout(); syncUrl(); break;
    case 'minimize': rememberEditor(); state.minimized = true; closePopover(); applyLayout(); document.querySelector('.minimized-strip [data-action="restore"]').focus(); break;
    case 'restore': state.minimized = false; state.closed = false; applyLayout(); document.getElementById('draft-body').focus(); break;
    case 'close': closeComposer(); break;
    case 'keep-editing': document.getElementById('close-dialog').close(); break;
    case 'discard': document.getElementById('close-dialog').close(); draft().body = originalEdit; draft().files = []; state.closed = true; state.minimized = false; renderComposer(); toast('Edit discarded in this mockup.'); break;
    case 'context': rememberEditor(); state.expanded = !state.expanded; renderComposer(); break;
    case 'category': case 'tags': if (state.mode === 'new') openPopover(action); break;
    case 'insert': if (state.capabilities.poll || state.capabilities.localDates) openPopover('insert'); break;
    case 'emoji': if (state.capabilities.emoji) openPopover('emoji'); break;
    case 'done-picker': closePopover(true); break;
    case 'reader-reply': setMode(state.drafts.reply.whisper ? 'whisper' : 'reply'); document.getElementById('draft-body').focus(); break;
    case 'link': openLink(); break;
    case 'cancel-link': document.getElementById('link-dialog').close(); break;
    case 'sample-poll': if (state.capabilities.poll) { closePopover(); insertText('\n\n[poll type=regular]\n* Try it\n* Discuss more\n[/poll]\n'); toast('Sample poll inserted. The app uses its existing poll editor.'); } break;
    case 'sample-date': if (state.capabilities.localDates) { closePopover(); insertText(' [date=2026-09-24 timezone="Europe/Paris"] '); toast('Sample date inserted. The app uses its existing date/time editor.'); } break;
    case 'attach': if (state.capabilities.uploads) { rememberEditor(); draft().files.push({name:`welcome-notes${draft().files.length ? `-${draft().files.length + 1}` : ''}.png`}); renderComposer(); scheduleSave(); toast('Sample image added. No file was uploaded.'); } break;
    case 'remove-file': rememberEditor(); draft().files.splice(Number(target.dataset.fileIndex),1); renderComposer(); scheduleSave(); break;
    case 'error': if (canSaveDraft()) { rememberEditor(); clearTimeout(saveTimer); state.error = !state.error; state.closed = false; state.minimized = false; renderComposer(); } break;
    case 'submit': submit(); break;
  }
});
document.addEventListener('keydown', event => {
  if (event.key === 'Escape' && state.popover) { event.preventDefault(); closePopover(true); return; }
  if (event.target.closest('[role="menu"]') && ['ArrowUp','ArrowDown','Home','End'].includes(event.key)) {
    event.preventDefault();
    const items = [...event.target.closest('[role="menu"]').querySelectorAll('button:not(:disabled)')];
    const index = items.indexOf(document.activeElement);
    items[event.key === 'Home' ? 0 : event.key === 'End' ? items.length - 1 : (index + (event.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length]?.focus();
  }
  if ((event.metaKey || event.ctrlKey) && event.key === 'Enter') { event.preventDefault(); submit(); }
  if ((event.metaKey || event.ctrlKey) && document.activeElement?.id === 'draft-body') {
    const mark = {b:'**',i:'*',e:'`'}[event.key.toLowerCase()];
    if (mark) { event.preventDefault(); insertText(mark,mark,'text'); }
    if (event.key.toLowerCase() === 'l') { event.preventDefault(); openLink(); }
  }
});
renderStudy();
