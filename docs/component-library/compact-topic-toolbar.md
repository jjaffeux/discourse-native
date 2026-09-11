# Compact topic toolbar

The topic inbox composes existing Native controls into two responsive rows.
The HTML directions in `docs/topic-list-header-mockups/` record the design
exploration; direction A is the implemented composition.

- At a reading-lane width of at least 760 logical pixels, adjusted for text
  scaling, the title, feed tabs and creation actions share the first row.
  Contextual controls occupy the start of the second row; category and tag
  selectors align to its trailing edge.
- Below that width, the title and creation actions have their own row. Feed
  tabs remain directly accessible, and contextual controls share a row with
  a Filters button. The layout follows the list pane rather than the window,
  including when a topic reader is open alongside it.
- Filters uses `DSheet` with existing category and tag selectors. Edits are
  staged until Apply; dismissal discards edits. Reset clears the staged
  selection. Applying changes category and tags in one controller operation.
  Active filters remain visible as removable buttons below the toolbar.
- `DTabs` supplies feed and New-scope navigation; `DSelect` supplies Top's
  period. `DButton` and `DBadge` supply actions and counts. Existing creation,
  draft, category-notification and plugin actions retain their owners.

The app-owned `TopicListFilterSheet` is keyed to the current feed. Async tag
results and Apply callbacks are checked against that feed's ownership. Changing
feeds retires the open sheet; contextual tab selection preserves its focus.

## Local review

Run `flutter run -d macos -t tool/compact_topic_toolbar_review_main.dart` for
an offline fixture of the real inbox. It offers wide/narrow panes, light/dark
themes, 100%/200% text, RTL and a link to the Native styleguide. Filtered results
are intentionally not backed by a server; the fixture's fake API displays its
normal error state for routes without fixture data.

Focused widget coverage lives in `topic_list_navigation_test.dart`,
`topic_inbox_test.dart`, `topic_list_filter_menu_ownership_test.dart`,
`topic_create_button_accessibility_test.dart` and
`content_reading_lane_integration_test.dart`. It covers pane widths from 320
through 1120, text scaling, RTL, staged filter edits, stale callbacks, combined
filters and retention of the open reader. The macOS fixture was also inspected
at wide and narrow widths and exercised with category, subcategory and tag
selection.

The implementation passed 144 focused widget checks and analysis. Integration
with main `bd608d8f` passed the macOS build and the inbox checks. The wider
topic-reading run had six existing failures, reproduced in an unchanged
checkout of that main revision: the two off-page composer category assertions,
the sidebar New Topic assertion, the old scrollbar assertion, the sharing
action assertion and the bookmark accent assertion. Its pagination test was
updated to scroll in bounded steps instead of assuming a fixed header height;
the appended page and its first row are still asserted, and that check passes.
