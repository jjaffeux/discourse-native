(() => {
  const root = document.getElementById('dn-button-directions');
  const firstExample = root.querySelector('.dn-example');
  const options = [...root.querySelectorAll('.dn-option')];
  for (const option of options.slice(1)) {
    const target = option.querySelector('.dn-example');
    for (const child of firstExample.children) target.append(child.cloneNode(true));
    target.querySelector('input').setAttribute('aria-label', 'Search topics in ' + option.querySelector('h2').textContent.toLowerCase() + ' preview');
  }

  function icon(name, className = '') {
    const element = document.createElement('i');
    element.dataset.lucide = name;
    element.setAttribute('aria-hidden', 'true');
    if (className) element.className = className;
    return element;
  }
  function renderIcons() { globalThis.lucide?.createIcons({ attrs: { width: 16, height: 16 } }); }
  function button(label, className = 'dn-control') {
    const element = document.createElement('button');
    element.type = 'button'; element.className = className; element.textContent = label;
    return element;
  }
  const samples = [
    ['Rest', 'Button', '', false], ['Hover', 'Button', 'dn-hover', false],
    ['Focus', 'Button', 'dn-focus', false], ['Disabled', 'Button', '', true],
    ['Primary', 'Reply', 'dn-primary', false], ['Secondary', 'Save', 'dn-secondary', false],
    ['Ghost', 'More', 'dn-ghost', false], ['Destructive', 'Delete', 'dn-danger', false],
    ['Link', 'View topic', 'dn-link', false]
  ];
  for (const option of options) {
    for (const [caption, label, variant, disabled] of samples) {
      const item = document.createElement('div'); item.className = 'dn-state-item';
      const captionElement = document.createElement('span'); captionElement.textContent = caption;
      const control = button(label, 'dn-control ' + variant); control.disabled = disabled;
      control.addEventListener('click', () => { option.querySelector('.dn-status').textContent = caption + ' variant activated · preview only'; });
      item.append(captionElement, control); option.querySelector('.dn-states').append(item);
    }
  }

  const settings = { appearance: 'dark', radius: '8', height: '32' };
  const palette = {
    dark: { primary: '#dddddd', secondary: '#222222', tertiary: '#0f82af', 'primary-low': '#313131' },
    light: { primary: '#222222', secondary: '#ffffff', tertiary: '#0088cc', 'primary-low': '#e9e9e9' }
  };
  function applySettings() {
    root.dataset.appearance = settings.appearance;
    root.style.setProperty('--dn-radius', settings.radius + 'px');
    root.style.setProperty('--dn-height', settings.height + 'px');
    root.querySelector('[data-rule="height"]').textContent = settings.height + ' px height';
    root.querySelector('[data-rule="radius"]').textContent = settings.radius + ' px radius';
    for (const token of root.querySelectorAll('[data-token]')) token.textContent = palette[settings.appearance][token.dataset.token];
    for (const field of root.querySelectorAll('[data-setting]')) field.value = settings[field.dataset.setting];
  }
  applySettings();
  for (const field of root.querySelectorAll('[data-setting]')) field.addEventListener('change', () => { settings[field.dataset.setting] = field.value; applySettings(); });
  if (globalThis.Tweak) {
    const tweak = new Tweak({ container: root, onChange: applySettings });
    tweak.addSelect(settings, 'appearance', { label: 'Forum palette', options: [{ label: 'Dev · dark', value: 'dark' }, { label: 'Dev · light', value: 'light' }] });
    tweak.addSelect(settings, 'radius', { label: 'Shared radius', options: [{ label: '4 px · current forum', value: '4' }, { label: '6 px', value: '6' }, { label: '8 px', value: '8' }] });
    tweak.addSelect(settings, 'height', { label: 'Shared height', options: [{ label: '32 px · regular', value: '32' }, { label: '36 px · large', value: '36' }] });
  }

  const menu = root.querySelector('.dn-menu');
  const choices = { categories: ['All categories', 'Discourse Native', 'Development', 'UX'], category: ['Discourse Native', 'Development', 'UX'], tags: ['All tags', 'design', 'feedback', 'native'], 'add-tag': ['design', 'feedback', 'native'], tracking: ['Watching', 'Tracking', 'Normal', 'Muted'], page: ['1', '2', '3', '4'] };
  let trigger = null;
  function closeMenu(restore = false) {
    const old = trigger;
    if (menu.matches(':popover-open')) menu.hidePopover();
    if (old) old.setAttribute('aria-expanded', 'false');
    trigger = null;
    if (restore) old?.focus();
  }
  function choose(value) {
    const control = trigger;
    const kind = control.dataset.menu;
    const option = control.closest('.dn-option');
    control.dataset.value = value;
    if (kind === 'page') {
      control.querySelector('.dn-current-page').textContent = value;
      control.setAttribute('aria-label', 'Jump to post, currently ' + value + ' of 4');
    } else {
      control.querySelector(kind === 'category' ? '.dn-category-label' : 'span').textContent = value;
      if (kind === 'tracking') {
        const oldIcon = control.querySelector('svg, i');
        oldIcon.replaceWith(icon(value === 'Muted' ? 'bell-off' : 'bell'));
      }
    }
    option.querySelector('.dn-status').textContent = (kind === 'page' ? 'Post ' + value + ' of 4' : value + ' selected') + ' · preview only';
    closeMenu(true); renderIcons();
  }
  function openMenu(control) {
    if (trigger === control && menu.matches(':popover-open')) { closeMenu(true); return; }
    closeMenu(); trigger = control;
    menu.replaceChildren();
    const kind = control.dataset.menu;
    menu.setAttribute('aria-label', kind === 'page' ? 'Jump to post' : kind + ' choices');
    for (const value of choices[kind]) {
      const item = button(kind === 'page' ? 'Post ' + value + ' of 4' : value, '');
      const selected = value === (control.dataset.value || ({ category: 'Discourse Native', tracking: 'Tracking', page: '1', categories: 'All categories', tags: 'All tags' }[kind]));
      item.setAttribute('aria-pressed', String(selected));
      if (selected) item.append(icon('check', 'dn-check'));
      item.addEventListener('click', () => choose(value)); menu.append(item);
    }
    control.setAttribute('aria-expanded', 'true');
    menu.showPopover();
    positionMenu();
    renderIcons(); menu.querySelector('button').focus({ preventScroll: true });
  }
  function positionMenu() {
    if (!trigger || !menu.matches(':popover-open')) return;
    const rect = trigger.getBoundingClientRect();
    const bounds = menu.getBoundingClientRect();
    const viewport = document.documentElement;
    menu.style.left = Math.max(8, Math.min(rect.left, viewport.clientWidth - bounds.width - 8)) + 'px';
    const below = rect.bottom + 6;
    const above = rect.top - bounds.height - 6;
    menu.style.top = Math.max(8, below + bounds.height > viewport.clientHeight && above >= 8 ? above : below) + 'px';
  }
  menu.addEventListener('toggle', event => {
    if (event.newState === 'closed' && !menu.matches(':popover-open')) { trigger?.setAttribute('aria-expanded', 'false'); trigger = null; }
  });
  menu.addEventListener('keydown', event => {
    if (event.key === 'Escape') { event.preventDefault(); closeMenu(true); }
    if (['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) {
      event.preventDefault(); const items = [...menu.querySelectorAll('button')]; const current = items.indexOf(document.activeElement);
      const next = event.key === 'Home' ? 0 : event.key === 'End' ? items.length - 1 : (current + (event.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length;
      items[next].focus();
    }
  });
  window.addEventListener('resize', positionMenu);
  window.addEventListener('scroll', positionMenu, { passive: true });

  root.addEventListener('click', event => {
    const control = event.target.closest('[data-menu], [data-action]'); if (!control) return;
    if (control.dataset.menu) { openMenu(control); return; }
    const option = control.closest('.dn-option');
    if (control.dataset.action === 'open-category') {
      option.querySelector('.dn-status').textContent = 'Open category on dev.discourse.org · preview only';
    }
    if (control.dataset.action === 'bookmark') {
      const saved = control.getAttribute('aria-pressed') !== 'true';
      control.setAttribute('aria-pressed', String(saved));
      control.setAttribute('aria-label', saved ? 'Remove bookmark' : 'Bookmark topic');
      control.replaceChildren(icon(saved ? 'bookmark-check' : 'bookmark'));
      option.querySelector('.dn-status').textContent = (saved ? 'Bookmarked' : 'Bookmark removed') + ' · preview only'; renderIcons();
    }
    if (control.dataset.action === 'reply') {
      let composer = option.querySelector('.dn-composer');
      if (!composer) {
        composer = document.createElement('div'); composer.className = 'dn-composer';
        const fieldId = 'dn-reply-' + option.dataset.direction;
        const label = document.createElement('label'); label.htmlFor = fieldId; label.textContent = 'Reply preview';
        const field = document.createElement('textarea'); field.id = fieldId; field.placeholder = 'Write a reply…';
        const actions = document.createElement('div'); actions.className = 'dn-actions';
        const save = button('Save preview', 'dn-control dn-primary'); const cancel = button('Cancel', 'dn-control');
        save.addEventListener('click', () => { option.querySelector('.dn-status').textContent = 'Reply preview saved locally for this session'; composer.hidden = true; control.focus(); });
        cancel.addEventListener('click', () => { composer.hidden = true; control.focus(); });
        composer.addEventListener('keydown', event => { if (event.key === 'Escape') { composer.hidden = true; control.focus(); } });
        actions.append(save, cancel); composer.append(label, field, actions); option.querySelector('.dn-example').append(composer);
      }
      composer.hidden = false; composer.querySelector('textarea').focus();
    }
  });
  for (const input of root.querySelectorAll('input[type="search"]')) input.addEventListener('input', () => {
    input.closest('.dn-option').querySelector('.dn-status').textContent = input.value.trim() ? 'Search preview: “' + input.value.trim() + '”' : '';
  });
  root.addEventListener('keydown', event => {
    if (event.key === '/' && !['INPUT', 'TEXTAREA', 'SELECT'].includes(event.target.tagName)) {
      event.preventDefault(); (event.target.closest('.dn-option') || options[0]).querySelector('input[type="search"]').focus();
    }
  });
  renderIcons();
})();
