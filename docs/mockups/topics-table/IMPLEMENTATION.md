# Native implementation

Implemented in the native Flutter application on 2026-09-17. The HTML file is
the approved design reference. All controls compose the public Native UI kit.

- Topic, message, aggregate and assignment lists use the available pane width.
  Card and Compact share the same column structure and differ in row spacing.
- Heading actions contain filtering and reader presentation. Search,
  refresh and account actions belong to the shell. A shared shell toolbar also
  keeps search and account access available on platforms without macOS chrome.
- Feed selection contains the Top periods directly. Counts occupy the trailing
  edge of the menu; category/subcategory colors and tag selection remain.
- The topic-list Display menu and its presentation preferences were later
  removed. Rows use their default text and metadata presentation.
- Advanced filtering is a Topics feed with the existing autocomplete parser,
  server vocabulary, remote category/tag/group/user lookups and account/session
  guards. The separate Filter page and built-in sidebar link are removed;
  legacy saved Filter routes restore as Topics feeds. Taxonomy is compiled into
  the server's q parameter. External website links remain website links.
- Forum and member filters sit at the right. Assignment headers sort Replies,
  Views and Activity: descending, ascending, then default order.
- Rows retain events, status markers, unread counts/dots, last poster, category,
  tags, assignment details, plugin metadata, read tracking and navigation.
  Discussion icons are removed; event date stamps remain.
- New topic/draft creation sits at the left of the footer. Previous/next topic
  actions are icon-only transparent-background DButtons.

UI kit additions: pill button shape, neutral Item selection, Combobox free-text
IME submission and optional focus restoration. Each retains the kit's normal
focus, semantics and size behavior. Completion menus avoid restoring focus when
moving between multiple forum inputs.


## Verification — 2026-09-17

- Static analysis: `flutter analyze --no-pub lib test tool/topics_redesign_review_main.dart`
  completed with no issues.
- 612 tests passed across the topic, inbox, assignment, aggregate, filter,
  route, settings, keyboard, accessibility, shell toolbar and affected UI-kit
  suites. The final set includes the retained-list display controls, retired
  filter callback, narrow/RTL/large-text layouts, menu keyboard selection,
  sorting, pagination and per-forum draft retention.
- Three existing failures were excluded from that final set after reproducing
  them against untouched HEAD `8a0ac354`: the custom-sidebar spacing test and
  the two phone tests returning from an unlisted topic with G J/G K.
- A broader exploratory suite also found older failures outside this redesign
  (126 reproduced in the baseline subset). The full run was stopped when the
  unrelated modal-controller lifecycle test stopped making progress. This is
  not a claim that the entire repository test suite passes.
- Production macOS debug build (`flutter build macos --debug --no-pub`) and
  the native review fixture both built successfully. An earlier native pass checked
  the dark full-width table, event stamps, footer, feed menu with counts and Top
  periods, and Display menu. It caught the retained-row preference update,
  which is fixed and covered by the final tests. The final visual refresh was
  unavailable because the Mac was locked; the desktop review lease was released.

Final focused regression command:

```sh
flutter test --no-pub \
  test/assigned_group_view_test.dart test/topic_list_navigation_test.dart \
  test/topic_filter_test.dart test/topic_inbox_test.dart \
  test/message_inbox_page_test.dart test/aggregate_view_test.dart \
  test/compact_topic_list_test.dart test/topic_list_view_lifecycle_test.dart \
  test/topic_list_semantics_test.dart test/content_reading_lane_integration_test.dart \
  test/app_settings_page_test.dart test/app_settings_controller_test.dart \
  test/app_settings_store_test.dart test/content_route_test.dart \
  test/discourse_instance_test.dart test/topic_filter_page_lifecycle_test.dart \
  test/ui/d_combobox_test.dart test/d_item_test.dart test/d_button_test.dart \
  test/d_button_transparent_background_test.dart \
  test/styleguide/button_examples_test.dart test/styleguide/combobox_examples_test.dart \
  test/content_navigation_controls_test.dart test/shell_navigation_integration_test.dart \
  test/keyboard_navigation_test.dart \
  --name '^(?!.*(?:shows custom sidebar sections and opens their links|G K opens the first listed topic from an unlisted topic at 390.0px|G J opens the first listed topic from an unlisted topic at 390.0px)).*$'
```

The approved HTML mockup is preserved alongside the native implementation.

## Hover follow-up — 2026-09-17

- Neutral Item rows now use faint foreground tints, 10px corners at the default
  theme radius, and no accent selection border. Keyboard focus is preserved.
- The nested table opts out of hover painting, leaving one continuous rounded
  highlight instead of an animated rectangular fill inside the Item.
- Topic tags use muted text links with an underline on hover. Badge hover entry
  and exit paint immediately; focus and theme transitions retain their timing.
- 113 focused Item, Badge, Table, topic-row, semantics, taxonomy and styleguide
  tests passed, including painted-state assertions during the 150ms hover
  interval. Full static analysis and the macOS review build passed.
- The final isolated native fixture was inspected in dark and light themes:
  row hover is continuous and rounded, and tags stay transparent when hovered.
  The desktop review lease was released after inspection.

Row spacing follow-up: both modes add 4px of inner vertical padding per side;
card list gaps shrink from 8px to 1px, matching compact lists. Loading gaps and
scroll estimates follow the new spacing. The macOS fixture confirmed that the
hover surface covers the padding in both modes. All 84 focused list and scroll
tests, affected-source analysis, and the native review build passed.

Header sorting follow-up: ordinary forum feeds now wire Category, Replies and
Activity headers to Discourse's server-side `order`/`ascending` parameters. Each
cycles through descending, ascending and the feed's default order. Changes keep
the category/tag filters, selected feed and open reader, reset pagination, and
use a distinct cached feed identity. Topic and Last reply stay passive; assigned
lists retain their existing supported columns. Advanced filters keep their
`order:` query syntax, and aggregate/message headers remain passive.

All 141 focused route, navigation, assigned-list, compact-row and list-lifecycle
tests passed, along with affected-source analysis and the macOS fixture build.
Native macOS review verified descending and ascending Replies, returning to
default order, and the Activity header in the offline production-widget fixture
in dark and light themes. Header labels expose the current sort direction to
accessibility. Request and response ordering were verified with the test API;
no live forum was modified.
