# Start Topics and pins parity

Reference: `discourse-native-mockups` commits `31bdc07` and `4d045d0`,
reviewed at final snapshot `54ba01c` on 2026-10-08.

The standard Start rows from native `e777b3226` and `3e6a877a9` already
implement the earlier `8d94d09` design. This change keeps their Native
`DItem`, `DCard`, `DToggle`, `DAlphabetIndex`, link menus, drag behavior and
destination availability. The broader audit remains in
[start-page-mockup-parity.md](start-page-mockup-parity.md).

## Final changes

- The initial session pins are Recently closed followed by Topics. Re-pinning
  Recently closed places it ahead of every other pin; all other pins retain
  their own insertion order. Every section can still be unpinned independently.
- Topics uses the loaded, account-scoped Latest feed in the forum's own list
  order, including topics the reader has never visited. Matching still occurs
  before the four-row limit. Opening Start does not request the feed or other
  directories. An empty cache retains the Topics destination and its pin.
- The Start visit-history section is removed rather than renamed to Recently
  viewed. It contributes no rows, destination, pin default, index entry,
  placeholder or search-result count. Topic history elsewhere is retained.
- Topics retains the existing localized Topics label and layer-group identity.
  Its heading opens Latest; previews use the existing topic-list navigation,
  unread counts, dates, category color, pinned/closed marks and link targets.
- Account retirement continues to clear feed previews and customized pins.
  Unpinned destinations remain alphabetical, followed by Preferences and Settings.

## Validation

Forty focused tests pass:

- `test/start_page_controller_test.dart`
- `test/start_page_redesign_test.dart`
- `test/start_page_parity_test.dart`
- The 13 affected Topics, default-pin, mobile-tap, desktop-drag and restored-tab
  tests selected by name from `test/new_tab_page_test.dart`.

Targeted Dart analysis covers the changed implementation and test files.
Real-font widget exports were inspected at desktop and phone sizes, in light
and dark themes, at 200% text on a 320px viewport, and with Recently closed
re-pinned ahead of Topics and Categories. The existing Native large-text
stacking and title ellipses are retained. These are rendered shell fixtures;
there was no physical-device run or additional RTL rendering for this delta.

The broader `new_tab_page_test.dart` run retains four failures reproduced on
unchanged native `bde32adc0`: `recent categories and Start page links expose
panel actions`, `Start page links to upcoming events when the site offers
them`, `an unread chat channel opens from the start page`, and `Chat previews
follow visit order regardless of unread counts`. The first two expect removed
shortcut/menu structure; the latter two use finders that now also match cached
Channels previews. No production changes were made for those unrelated assertions.
The obsolete empty-section shortcut assertion affected by Topics was updated
to verify the current Native destination rows and default Topics pin.
