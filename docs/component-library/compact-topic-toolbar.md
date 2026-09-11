# Focused topic toolbar

The approved third direction from `docs/topic-list-header-mockups/round-2/`
uses a Native `DSelect` beside the title to choose Recent, New, Top or Trending.
Category, subcategory and tag selectors remain directly accessible at every
pane width. Their selections apply immediately and preserve the open reader.

At reading-lane widths below 760 logical pixels (adjusted for text scaling),
parent and subcategory share a row and tags occupy the next row. Without a
subcategory, category and tags share the row. New's scope tabs or Top's period
selector follow below. Wider panes place taxonomy before those contextual
controls on the same row. All existing creation, draft, category-notification,
plugin and account actions retain their behavior.

There is no Clear filters action, applied-filter chip row, filter sheet,
topic-table heading, separator above the first topic, or explanatory feed text.
Each selector still offers its existing All option; returning a subcategory to
All restores its parent and keeps the tag selection.

The composition uses existing Native controls through `discourse_ui.dart`.
It introduces no UI kit component or component option. Async lookup and filter
callbacks retain their feed ownership guards, and the feed selector keeps its
focus through route changes.

## Review

`flutter run -d macos -t tool/compact_topic_toolbar_review_main.dart` opens the
offline fixture with wide/narrow, light/dark, large text, RTL and styleguide
controls. It contains representative feeds; unconfigured filtered routes show
the fake API's normal error state.

Focused coverage includes `topic_list_navigation_test.dart`,
`topic_list_filter_menu_ownership_test.dart`,
`topic_create_button_accessibility_test.dart`, `topic_inbox_test.dart` and
`content_reading_lane_integration_test.dart`. The width matrix includes a long
selected parent and subcategory from 320 through 1120, 100% and 200% text, and
both text directions. Interaction coverage includes immediate combined
filters, parent restoration, stale callbacks, keyboard feed selection, New
scope counts, Top periods and retention of the reader.

The revised composition passed 144 focused checks, static analysis and the
macOS debug build. Native inspection covered wide and 390px panes, direct
parent/subcategory selection, and the absence of the removed list chrome.
