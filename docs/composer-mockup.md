# Composer layout, September 19

The composer follows the new-topic mockup at `http://localhost:5183/`:
category and tag selectors precede a borderless title, a separator leads into
the editor, and outlined writing tools share the footer with Create topic and
Discard. Narrow panes put tools on a second row. Replies retain their recipient,
topic and expandable context, with Reply as the primary action. Header docking,
minimizing, close and draft-save status remain available.

All controls use the existing Native UI kit. No shared component API changed.
Opening a persistent topic/reply composer starts an asynchronous request for
`/drafts.json?offset=0&limit=5`. The editor is usable while it loads. The server
orders this page by most recently updated draft, then ID (see
[Discourse Draft.stream](https://github.com/discourse/discourse/blob/main/app/models/draft.rb)).
The preview has its own feed so it never changes the Drafts screen's pagination
or reported count. It refreshes for each new composer, not on typing or resizing.

The header offers those drafts using the existing resume flow, preserving the
outgoing draft. The current draft is represented by the active heading rather
than a duplicate button. Unsupported draft kinds retain the existing app's
resume restrictions and show disabled buttons with an explanatory tooltip.
Narrow headers scroll horizontally; loading failures provide a retry action.
A selection whose source composer was closed or replaced while loading cannot
reopen or overwrite that replacement. Site lifecycle changes invalidate pending
requests, and deletion/submission removes a draft from both cached feeds.

### Recent-drafts follow-up verification

- Six feature widget tests cover nonblocking loading, five-row requests,
  reopening, no refetch on typing, preserving outgoing content, new-topic and
  reply restoration, busy guards, retry, close-during-load and narrow RTL scrolling.
- 97 existing focused checks pass: draft-list controller, composer header status,
  docking, panel controls, draft-list recovery, and authoring admission.
- Static analysis is clean. Built and launched the local macOS fixture; checked
  the five buttons in dark/bottom layout, scrolling layout in light/right dock,
  and clicking a draft to restore the correct topic and reply text.

## Verification

- `flutter analyze --no-pub`: clean.
- 138 tests passed across composer header draft status, docking, panel controls,
  picker modals, upload picker, poll/emoji panels, close safety, authoring
  submission, tag search, and the control-style adoption guard.
- The broader upload-panel and draft-integration suites passed 105 tests and
  failed eight. The same eight failures reproduce at unchanged base
  `7f23a397f`: four image/gallery tests, three private-message discard tests,
  and the draft debounce test. These are not caused by this layout change.
- Built and launched the production composer through
  `tool/composer_docking_review_main.dart` in an isolated, ad-hoc-signed macOS
  app with local fake APIs and drafts. Reviewed new-topic light/right and
  dark/bottom layouts against the HTML mockup, reply light/bottom and dark/RTL
  layouts, typing, footer italic insertion and returning editor focus, and
  successful autosave status. Native screenshots and accessibility trees
  showed the controls and editor as separate accessible elements.
- Widget checks cover narrow panes, up to 3x text scaling, taxonomy selection,
  submission, picker lifecycle, keyboard shortcuts and disposal. No mobile
  device run was performed.
