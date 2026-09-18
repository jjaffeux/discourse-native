# Composer layout, September 19

The composer follows the new-topic mockup at `http://localhost:5183/`:
category and tag selectors precede a borderless title, a separator leads into
the editor, and outlined writing tools share the footer with Create topic and
Discard. Narrow panes put tools on a second row. Replies retain their recipient,
topic and expandable context, with Reply as the primary action. Header docking,
minimizing, close and draft-save status remain available.

All controls use the existing Native UI kit. No shared component API changed.
The five-recent-drafts strip is intentionally omitted: current-user data only
has a draft count, and `DraftListController.load` separately calls `userDrafts`.
A previously visited draft list cannot guarantee the five latest drafts. Opening
the composer makes no new draft-list request.

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
