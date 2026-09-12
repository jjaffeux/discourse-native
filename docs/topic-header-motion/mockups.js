/* Standalone, local-data motion studies. No dependencies or application writes. */
(() => {
  const root = document.getElementById('header-lab');
  const reducedPreference = matchMedia('(prefers-reduced-motion: reduce)');
  const darkPreference = matchMedia('(prefers-color-scheme: dark)');
  const titles = {
    regular: 'Customer support coverage · Seville 2026',
    long: 'Customer support coverage for our week in Seville — coordinating shifts, handovers and time zones across the whole team',
  };
  const designs = {
    a: {
      number: '01', name: 'Pinned title', behavior: 'Fixed title · scrolling details',
      heading: 'Keep the title still.',
      description: 'The title and actions stay in the same place, at the same size. Categories, tags and activity scroll underneath them with the conversation. A small upward scroll never opens the header again.',
      tradeoff: 'The calmest starting point. The opening title is smaller, and details are one click away once they scroll out of view.',
    },
    b: {
      number: '02', name: 'Natural handoff', behavior: 'Opening title → toolbar title',
      heading: 'Let the opening scroll away.',
      description: 'A large, wrapping title belongs to the first post. As its last line passes behind the fixed toolbar, the smaller title fades into that toolbar. The reading area keeps the same height throughout.',
      tradeoff: 'Best if you want a generous opening and readable long titles. The title changes location once, instead of shrinking in place.',
    },
    c: {
      number: '03', name: 'Continuous collapse', behavior: 'One gesture · one continuous movement',
      heading: 'Make motion follow your hand.',
      description: 'The header retracts by one pixel for each pixel scrolled over the opening 114 px. One title moves and scales continuously; the controls stay anchored. Stop scrolling and the header stops immediately.',
      tradeoff: 'Closest to the current idea. The title stays on one line to avoid wrapping changes during motion; open topic details to read long titles in full.',
    },
    d: {
      number: '04', name: 'Always compact', behavior: 'Fixed title + fixed category row',
      heading: 'Give the conversation a stable frame.',
      description: 'The title and category row are always visible. Nothing expands, collapses or changes size when you scroll. Open the details button for participants, activity, assignment and the full title.',
      tradeoff: 'The most predictable option. It reserves 88 px while reading, and puts the activity summary behind a deliberate click.',
    },
  };

  const iconPaths = {
    up: '<path d="m7 14 5-5 5 5M12 9v11M5 4h14"/>',
    down: '<path d="m7 10 5 5 5-5M12 15V4M5 20h14"/>',
    info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7h.01"/>',
    bookmark: '<path d="M6 4h12v17l-6-4-6 4V4Z"/>',
    more: '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
    close: '<path d="m6 6 12 12M6 18 18 6"/>',
    chevron: '<path d="m9 5 7 7-7 7"/>',
    inbox: '<path d="M4 5h16v14H4zM4 13h5l1 3h4l1-3h5"/>',
    chat: '<path d="M20 11a8 8 0 0 1-8 8H4l1.4-4.2A8 8 0 1 1 20 11Z"/>',
    search: '<circle cx="10" cy="10" r="6"/><path d="m15 15 5 5"/>',
    user: '<circle cx="9" cy="8" r="3"/><path d="M3 20v-2a6 6 0 0 1 12 0v2M19 7v6M16 10h6"/>',
    heart: '<path d="M20 5a5 5 0 0 0-8 1 5 5 0 0 0-8-1c-4 4 0 9 8 15 8-6 12-11 8-15Z"/>',
    settings: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2"/>',
    bell: '<path d="M6 9a6 6 0 0 1 12 0v5l2 3H4l2-3V9M10 21h4"/>',
  };
  const icon = (name) => `<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${iconPaths[name]}</svg>`;
  const escape = (text) => text.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
  const button = (action, label, symbol, extra = '') => `<button type="button" class="native-button ghost icon-only" data-action="${action}" aria-label="${label}" title="${label}" ${extra}>${icon(symbol)}</button>`;
  const avatars = () => '<span class="avatar-stack" aria-label="Alex, Maya and Sam"><span class="avatar">A</span><span class="avatar maya">M</span><span class="avatar sam">S</span></span>';
  const taxonomy = () => '<span class="taxonomy-parent">staff</span><span class="taxonomy-slash">/</span><span class="native-badge category"><span class="category-square"></span>world meetups</span><span class="native-badge">seville</span><span class="native-badge secondary-tag">planning</span>';
  const activity = () => `${avatars()}<span>8 replies</span><span class="activity-time">· Active 1h ago</span><button type="button" class="native-button small assign-button" data-action="assign">${icon('user')}<span class="assign-text">Assign topic</span></button>`;
  const people = [
    { name: 'Alex', handle: 'alex', initial: 'A', color: '' },
    { name: 'Maya', handle: 'maya', initial: 'M', color: 'maya' },
    { name: 'Sam', handle: 'sam', initial: 'S', color: 'sam' },
  ];
  const posts = [
    { person: 0, time: '2h ago', likes: 4, html: '<p>Sharing the support coverage plan for our week in Seville. Let’s make sure there’s always someone available while the rest of the team is at the meetup.</p><p>A little overlap between shifts should give us time for a proper handover. Here’s a starting point:</p><div class="coverage"><div class="coverage-row"><span>Morning · 09:00–13:00</span><span>Afternoon · 12:30–17:00</span></div><div class="coverage-row"><span>Mon — Maya</span><span>Alex</span></div><div class="coverage-row"><span>Tue — Maya</span><span>Sam</span></div><div class="coverage-row"><span>Wed — Alex</span><span>Sam</span></div></div><p>Add your availability below and we’ll fill in the rest together.</p>' },
    { person: 1, time: '1h ago', likes: 3, html: '<p>Monday and Tuesday mornings work for me. I’ll check the queue before the sessions start and leave handover notes here.</p><blockquote>A little overlap between shifts should give us time for a proper handover.</blockquote><p>Yes, let’s keep that half hour. <span class="mention">@sam</span>, does Tuesday afternoon still work for you?</p>' },
    { person: 2, time: '1h ago', likes: 2, html: '<p>Tuesday afternoon is good! I can take Wednesday too.</p><p>If anything needs a longer follow-up, I’ll add it here so the next person has the full context.</p>' },
    { person: 0, time: '48m ago', likes: 2, html: '<p>Perfect. I’ve added both of you to the schedule.</p><p>Let’s keep all times in the local Seville time zone. That should make it easier to coordinate once everyone arrives.</p>' },
    { person: 1, time: '35m ago', likes: 1, html: '<p>Good call on the time zone. I’ll add a calendar block for each of my shifts.</p><p>Happy to cover Thursday morning as well if we still need someone.</p>' },
    { person: 2, time: '22m ago', likes: 2, html: '<p>All set for Tuesday and Wednesday. I’ll check in with the morning person before taking over.</p><p>Looking forward to seeing everyone in Seville!</p>' },
    { person: 0, time: '18m ago', likes: 3, html: '<p>Thanks, everyone. We have Monday through Thursday covered now.</p><p>I’ll pin the final schedule before we leave so it’s easy to find during the week.</p>' },
    { person: 1, time: '12m ago', likes: 1, html: '<p>Calendar updated. I’ll bring the handover notes template we used last time — it worked well for keeping things short and useful.</p>' },
    { person: 2, time: '5m ago', likes: 2, html: '<p>Looks like we’re all set. See you there!</p>' },
  ];

  let currentTitle = titles.regular;
  let activeDesign = new URLSearchParams(location.search || location.hash.slice(1)).get('design') || 'a';
  if (!designs[activeDesign]) activeDesign = 'a';
  let comparing = false;
  let currentOffset = 0;
  let playbackFrame = 0;
  let scrollFrame = 0;
  let reduced = reducedPreference.matches;
  let motionOverride = false;
  let themeOverride = false;
  const models = [];
  const clamp = (v, a = 0, b = 1) => Math.max(a, Math.min(b, v));
  const mix = (a, b, p) => a + (b - a) * p;
  const scrub = root.querySelector('#scroll-position');
  const motionInput = root.querySelector('#reduce-motion');
  const playLabel = root.querySelector('#play-label');

  function renderStudy(study) {
    const id = study.dataset.design;
    const design = designs[id];
    const context = `<div class="header-context">${id === 'b' ? `<h3 class="hero-title" data-title>${escape(currentTitle)}</h3>` : ''}<div class="taxonomy">${taxonomy()}</div><div class="activity-row">${activity()}</div></div>`;
    study.innerHTML = `
      <div class="study-caption"><strong>${design.number} · ${design.name}</strong><span>${design.behavior}</span></div>
      <div class="app-window design-${id}">
        <div class="window-bar"><span class="window-dots" aria-hidden="true"><i></i><i></i><i></i></span><span class="window-label">Discourse · Team</span></div>
        <div class="app-body">
          <div class="app-rail" aria-hidden="true"><span class="rail-logo">d</span><span class="rail-icon selected">${icon('inbox')}</span><span class="rail-icon">${icon('chat')}</span><span class="rail-icon">${icon('search')}</span><span class="rail-spacer"></span><span class="rail-icon">${icon('settings')}</span></div>
          <aside class="topic-list" aria-label="Example topic list">
            <div class="list-title">Topics <small>Recent⌄</small></div><div class="list-filter"><span class="category-square"></span> world meetups ${icon('chevron')}</div>
            <div class="inbox-row selected" aria-current="true"><h3><span class="unread-dot"></span><span data-title>${escape(currentTitle)}</span></h3><p><span>world meetups</span><span>8 · 1h</span></p></div>
            <div class="inbox-row"><h3>Where to eat in Seville</h3><p><span>world meetups</span><span>24 · 2h</span></p></div>
            <div class="inbox-row"><h3>Arrival times & airport transfers</h3><p><span>world meetups</span><span>16 · 3h</span></p></div>
            <div class="inbox-row"><h3>Meetup session ideas</h3><p><span>staff</span><span>31 · 4h</span></p></div>
            <div class="inbox-row"><h3>The little things to pack</h3><p><span>world meetups</span><span>7 · 5h</span></p></div>
          </aside>
          <div class="reader">
            <div class="topic-scroll" role="region" tabindex="0" aria-label="${design.name}: scroll the example conversation">
              <div class="header-spacer" aria-hidden="true"></div>
              ${id === 'a' || id === 'b' ? context : ''}
              <div class="posts">${posts.map((post, i) => {
                const person = people[post.person];
                return `<article class="post" data-post="${i + 1}" aria-label="Post ${i + 1} by ${person.name}"><span class="avatar ${person.color}" aria-hidden="true">${person.initial}</span><div><div class="post-heading"><strong>${person.name}</strong><span class="handle">${person.handle}</span><time>${post.time} · #${i + 1}</time></div><div class="post-copy">${post.html}</div><span class="post-reactions" aria-label="${post.likes} likes">${icon('heart')}${post.likes}</span></div></article>`;
              }).join('')}<div class="conversation-end">You’re all caught up.</div></div>
            </div>
            <header class="topic-header" aria-label="Topic header">
              <div class="toolbar-leading">${button('top', 'Back to first post', 'up')}</div>
              ${id === 'b' ? '<div class="toolbar-category"><span class="category-square"></span>world meetups</div>' : ''}
              <div class="toolbar-title"><h3 data-title title="${escape(currentTitle)}">${escape(currentTitle)}</h3></div>
              <div class="toolbar-actions">${button('info', 'Topic details', 'info', `aria-expanded="false" aria-controls="details-${id}"`)}${button('bookmark', 'Bookmark topic', 'bookmark', 'aria-pressed="false"')}${button('more', 'More topic options', 'more', `aria-expanded="false" aria-controls="details-${id}"`)}</div>
              ${id === 'c' ? `<div class="taxonomy morph-taxonomy">${taxonomy()}</div><div class="activity-row morph-activity">${activity()}</div>` : ''}
              ${id === 'd' ? `<div class="taxonomy fixed-taxonomy">${taxonomy()}</div>` : ''}
            </header>
            <section class="detail-popover" id="details-${id}" role="dialog" aria-labelledby="detail-title-${id}" hidden>
              <div class="popover-top"><strong>Topic details</strong>${button('dismiss', 'Close topic details', 'close')}</div>
              <h4 id="detail-title-${id}" data-title>${escape(currentTitle)}</h4><div class="taxonomy">${taxonomy()}</div>
              <div class="activity-row">${avatars()}<span>8 replies · 3 participants</span></div>
              <div class="assignment-label" role="status">Unassigned · Last activity 1h ago</div>
              <div class="popover-actions"><button class="native-button" data-action="assign">${icon('user')}<span class="assign-text">Assign topic</span></button><button class="native-button" data-action="latest">Latest reply ${icon('down')}</button></div>
            </section>
            <footer class="reader-footer"><span>8 replies · 3 participants</span><span class="footer-count">1 / 9</span><button class="native-button ghost" data-action="latest">Latest ${icon('down')}</button></footer>
          </div>
        </div>
      </div>`;
    const model = {
      id, study,
      reader: study.querySelector('.reader'),
      scroller: study.querySelector('.topic-scroll'),
      header: study.querySelector('.topic-header'),
      popover: study.querySelector('.detail-popover'),
      title: study.querySelector('.toolbar-title'),
      hero: study.querySelector('.hero-title'),
      postElements: [...study.querySelectorAll('.post')],
      opener: null, assignment: 0, postTops: [], width: 0, textInset: 67, handoffStart: 0,
    };
    models.push(model);
    model.scroller.addEventListener('scroll', () => {
      if (Math.abs(model.scroller.scrollTop - currentOffset) < 1 || study.hidden) return;
      cancelAnimationFrame(scrollFrame);
      scrollFrame = requestAnimationFrame(() => setPosition(model.scroller.scrollTop, model));
    }, { passive: true });
    ['wheel', 'touchstart', 'pointerdown', 'keydown'].forEach((event) => {
      model.scroller.addEventListener(event, stopPlayback, { passive: true });
    });
    study.addEventListener('click', (event) => {
      const control = event.target.closest('[data-action]');
      if (!control) return;
      const action = control.dataset.action;
      if (action === 'info' || action === 'more') {
        if (!model.popover.hidden && model.opener === control) closeDetails(model, true);
        else openDetails(model, control);
      } else if (action === 'dismiss') {
        closeDetails(model, true);
      } else if (action === 'bookmark') {
        const selected = control.getAttribute('aria-pressed') !== 'true';
        control.setAttribute('aria-pressed', String(selected));
        const label = selected ? 'Remove bookmark' : 'Bookmark topic';
        control.setAttribute('aria-label', label);
        control.title = label;
      } else if (action === 'assign') {
        model.assignment = (model.assignment + 1) % 4;
        const name = ['Unassigned', 'Maya', 'Sam', 'Alex'][model.assignment];
        study.querySelectorAll('.assign-text').forEach((label) => { label.textContent = model.assignment ? name : 'Assign topic'; });
        study.querySelector('.assignment-label').textContent = `${name} · Last activity 1h ago`;
      } else if (action === 'top' || action === 'latest') {
        stopPlayback();
        closeDetails(model, model.popover.contains(document.activeElement));
        setPosition(action === 'top' ? 0 : Math.max(0, model.scroller.scrollHeight - model.scroller.clientHeight), model);
      }
    });
    study.addEventListener('keydown', (event) => {
      if (event.key === 'Escape' && !model.popover.hidden) {
        closeDetails(model, true);
        event.stopPropagation();
      }
    });
  }

  function closeDetails(model, restoreFocus = false) {
    model.popover.hidden = true;
    model.study.querySelectorAll('[aria-controls="details-' + model.id + '"]').forEach((control) => control.setAttribute('aria-expanded', 'false'));
    if (restoreFocus) model.opener?.focus({ preventScroll: true });
  }

  function openDetails(model, opener) {
    stopPlayback();
    models.forEach((other) => closeDetails(other));
    model.opener = opener;
    model.popover.hidden = false;
    opener.setAttribute('aria-expanded', 'true');
    model.popover.querySelector('[data-action="dismiss"]').focus({ preventScroll: true });
  }

  function measure(model) {
    if (model.study.hidden) return;
    model.width = model.reader.clientWidth;
    model.textInset = model.postElements[0].querySelector('.post-heading').getBoundingClientRect().left - model.reader.getBoundingClientRect().left;
    model.reader.style.setProperty('--text-inset', `${model.textInset}px`);
    const top = model.scroller.getBoundingClientRect().top;
    const offset = model.scroller.scrollTop;
    model.postTops = model.postElements.map((post) => post.getBoundingClientRect().top - top + offset);
    if (model.hero) model.handoffStart = model.hero.getBoundingClientRect().bottom - top + offset - 52;
  }

  function paint(model) {
    if (model.study.hidden) return;
    const offset = model.scroller.scrollTop;
    let headerHeight = model.id === 'd' ? 88 : 52;
    if (model.id === 'b') {
      // Fade the category out before the small title appears, so two strings
      // never paint over one another during the handoff.
      const progress = reduced ? Number(offset >= model.handoffStart) : clamp((offset - model.handoffStart + 14) / 28);
      const titleOpacity = clamp(progress * 2 - 1);
      model.header.style.setProperty('--handoff', titleOpacity.toFixed(3));
      model.header.style.setProperty('--category-opacity', (1 - clamp(progress * 2)).toFixed(3));
      model.title.setAttribute('aria-hidden', String(titleOpacity === 0));
    }
    if (model.id === 'c') {
      const progress = clamp(offset / 114);
      const scale = mix(1, 2 / 3, progress);
      const opacity = 1 - clamp(offset / 58);
      headerHeight = reduced ? 52 : mix(166, 52, progress);
      const width = mix(model.width - model.textInset - 26, model.width - model.textInset - 115, progress) / scale;
      model.header.style.setProperty('--header-height', `${headerHeight}px`);
      model.header.style.setProperty('--title-y', `${mix(60, 15, progress)}px`);
      model.header.style.setProperty('--title-scale', scale);
      model.header.style.setProperty('--title-width', `${Math.max(50, width)}px`);
      model.header.style.setProperty('--context-opacity', opacity);
      model.header.style.setProperty('--context-y', `${-18 * progress}px`);
      model.study.querySelectorAll('.morph-taxonomy, .morph-activity').forEach((part) => {
        part.inert = reduced || opacity < .05;
        part.setAttribute('aria-hidden', String(reduced || opacity < .05));
      });
    }
    let postNumber = 1;
    model.postTops.forEach((postTop, i) => { if (postTop <= offset + headerHeight + 36) postNumber = i + 1; });
    if (offset + model.scroller.clientHeight >= model.scroller.scrollHeight - 1) postNumber = posts.length;
    model.study.querySelector('.footer-count').textContent = `${postNumber} / 9`;
  }

  function setPosition(value, source = null) {
    const visible = models.filter((model) => !model.study.hidden);
    const driver = source || visible.find((model) => model.id === activeDesign) || visible[0];
    const max = Math.max(0, driver.scroller.scrollHeight - driver.scroller.clientHeight);
    currentOffset = clamp(value, 0, max);
    models.forEach((model) => {
      if (!model.study.hidden) {
        // Leave the scroll source alone so keyboard scrolling and trackpad
        // momentum retain their native behavior. Update only its peers.
        if (Math.abs(model.scroller.scrollTop - currentOffset) > .01) model.scroller.scrollTop = currentOffset;
        paint(model);
      }
    });
    scrub.value = Math.min(520, currentOffset);
    scrub.setAttribute('aria-valuetext', `${Math.round(currentOffset)} pixels from the top`);
    root.querySelector('#scroll-value').textContent = `${Math.round(currentOffset)} px`;
    if (reduced) {
      playLabel.textContent = currentOffset < 200 ? 'Jump to reading' : 'Back to top';
      root.querySelector('#play').setAttribute('aria-label', playLabel.textContent);
    }
  }

  function updateVisible() {
    models.forEach((model) => {
      closeDetails(model);
      model.study.hidden = !comparing && model.id !== activeDesign;
    });
    root.querySelectorAll('[data-concept]').forEach((control) => control.setAttribute('aria-pressed', String(!comparing && control.dataset.concept === activeDesign)));
    root.classList.toggle('compare-mode', comparing);
    root.querySelector('#single').setAttribute('aria-pressed', String(!comparing));
    root.querySelector('#compare').setAttribute('aria-pressed', String(comparing));
    root.querySelector('.linked-label').hidden = !comparing;
    const design = designs[activeDesign];
    root.querySelector('#note-number').textContent = `DIRECTION ${design.number}`;
    root.querySelector('#note-title').textContent = design.heading;
    root.querySelector('#note-behavior').textContent = design.description;
    root.querySelector('#note-tradeoff').textContent = design.tradeoff;
    models.forEach(measure);
    setPosition(currentOffset);
  }

  function stopPlayback() {
    cancelAnimationFrame(playbackFrame);
    playbackFrame = 0;
    root.querySelector('.play-glyph').textContent = '▶';
    playLabel.textContent = reduced ? (currentOffset < 200 ? 'Jump to reading' : 'Back to top') : 'Play scroll';
    root.querySelector('#play').setAttribute('aria-label', playLabel.textContent);
  }

  function play() {
    if (playbackFrame) { stopPlayback(); return; }
    if (reduced) { setPosition(currentOffset < 200 ? 340 : 0); return; }
    models.forEach((model) => closeDetails(model, model.popover.contains(document.activeElement)));
    setPosition(0);
    const started = performance.now();
    const stops = [[0, 0], [500, 0], [3100, 185], [4350, 460], [4950, 436], [5450, 436], [7650, 0]];
    playLabel.textContent = 'Pause';
    root.querySelector('#play').setAttribute('aria-label', 'Pause scroll demonstration');
    root.querySelector('.play-glyph').textContent = 'Ⅱ';
    const step = (now) => {
      const elapsed = now - started;
      if (elapsed >= stops.at(-1)[0]) { setPosition(0); stopPlayback(); return; }
      const endIndex = stops.findIndex(([time]) => time > elapsed);
      const from = stops[endIndex - 1];
      const to = stops[endIndex];
      setPosition(mix(from[1], to[1], (elapsed - from[0]) / (to[0] - from[0])));
      playbackFrame = requestAnimationFrame(step);
    };
    playbackFrame = requestAnimationFrame(step);
  }

  function applyReducedMotion() {
    stopPlayback();
    motionInput.checked = reduced;
    root.classList.toggle('reduced-motion', reduced);
    root.querySelector('#interaction-hint').textContent = reduced
      ? 'Reduced motion: scaling becomes a fixed toolbar and the demo jumps between states. Manual scrolling still works.'
      : 'Scroll inside the conversation, or drag the slider slowly through the transition.';
    models.forEach(measure);
    setPosition(currentOffset);
  }

  function applyTheme(dark) {
    document.documentElement.dataset.theme = dark ? 'dark' : 'light';
    root.querySelector('#theme').textContent = dark ? 'Light theme' : 'Dark theme';
  }

  root.querySelectorAll('.study').forEach(renderStudy);
  root.querySelectorAll('[data-concept]').forEach((control) => control.addEventListener('click', () => {
    stopPlayback();
    activeDesign = control.dataset.concept;
    comparing = false;
    const url = new URL(location.href);
    url.searchParams.set('design', activeDesign);
    if (location.protocol === 'file:') location.hash = `design=${activeDesign}`;
    else history.replaceState(null, '', url);
    updateVisible();
  }));
  root.querySelector('#compare').addEventListener('click', () => { stopPlayback(); comparing = true; updateVisible(); });
  root.querySelector('#single').addEventListener('click', () => { stopPlayback(); comparing = false; updateVisible(); });
  root.querySelector('#viewport').addEventListener('change', (event) => {
    stopPlayback();
    root.classList.toggle('narrow-mode', event.target.value === 'narrow');
    models.forEach(measure);
    setPosition(currentOffset);
  });
  root.querySelector('#long-title').addEventListener('change', (event) => {
    stopPlayback();
    currentTitle = event.target.checked ? titles.long : titles.regular;
    root.querySelectorAll('[data-title]').forEach((node) => {
      node.textContent = currentTitle;
      if (node.hasAttribute('title')) node.title = currentTitle;
    });
    models.forEach(measure);
    setPosition(currentOffset);
  });
  root.querySelector('#theme').addEventListener('click', () => {
    themeOverride = true;
    applyTheme(document.documentElement.dataset.theme !== 'dark');
  });
  darkPreference.addEventListener('change', () => { if (!themeOverride) applyTheme(darkPreference.matches); });
  motionInput.addEventListener('change', () => { motionOverride = true; reduced = motionInput.checked; applyReducedMotion(); });
  reducedPreference.addEventListener('change', () => { if (!motionOverride) { reduced = reducedPreference.matches; applyReducedMotion(); } });
  root.querySelector('#play').addEventListener('click', play);
  root.querySelector('#top').addEventListener('click', () => { stopPlayback(); setPosition(0); });
  scrub.addEventListener('input', () => { stopPlayback(); setPosition(Number(scrub.value)); });
  document.addEventListener('pointerdown', (event) => {
    models.forEach((model) => {
      if (!model.popover.hidden && !model.popover.contains(event.target) && !event.target.closest('[data-action="info"], [data-action="more"]')) closeDetails(model);
    });
  });
  document.addEventListener('visibilitychange', () => { if (document.hidden) stopPlayback(); });
  window.addEventListener('pagehide', () => { stopPlayback(); cancelAnimationFrame(scrollFrame); });
  const observer = new ResizeObserver(() => { models.forEach(measure); setPosition(currentOffset); });
  models.forEach((model) => observer.observe(model.reader));
  applyTheme(darkPreference.matches);
  updateVisible();
  applyReducedMotion();
})();
